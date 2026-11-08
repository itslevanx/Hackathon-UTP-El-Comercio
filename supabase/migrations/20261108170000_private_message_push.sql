begin;

create table app_private.private_message_installations (
  session_id uuid primary key references auth.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id text not null unique
    check (installation_id ~ '^[A-Za-z0-9_-]{22}$')
);
create index private_message_installations_user_idx
  on app_private.private_message_installations(user_id);

create table app_private.private_message_push_queue (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  session_id uuid not null
    references app_private.private_message_installations(session_id) on delete cascade,
  created_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  attempts integer not null default 0,
  unique (message_id, session_id)
);
create index private_message_push_queue_available_idx
  on app_private.private_message_push_queue(available_at);
create index private_message_push_queue_session_idx
  on app_private.private_message_push_queue(session_id);

alter table app_private.private_message_installations enable row level security;
alter table app_private.private_message_push_queue enable row level security;
revoke all on app_private.private_message_installations,
  app_private.private_message_push_queue from public, anon, authenticated;

create function app_private.active_private_push_session()
returns uuid
language sql stable security definer set search_path = '' as $$
  select s.id from auth.sessions s
  where s.id = nullif(auth.jwt()->>'session_id', '')::uuid and s.user_id = auth.uid();
$$;
revoke all on function app_private.active_private_push_session()
  from public, anon, authenticated;

create function public.private_message_push_enabled()
returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from app_private.private_message_installations i
    where i.session_id = app_private.active_private_push_session()
  );
$$;

create function public.set_private_message_push(p_user_id uuid, p_installation_id text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  active_session uuid := app_private.active_private_push_session();
begin
  if active_session is null or p_user_id is distinct from auth.uid() then
    raise exception 'La sesión de esta instalación cambió' using errcode = '42501';
  end if;

  if p_installation_id is null then
    delete from app_private.private_message_installations where session_id = active_session;
    return;
  end if;

  -- Una instalación pertenece a una sola sesión. Si cambió la cuenta del
  -- teléfono, la asociación anterior y sus avisos pendientes se eliminan.
  delete from app_private.private_message_installations
  where installation_id = p_installation_id and session_id <> active_session;

  insert into app_private.private_message_installations(session_id, user_id, installation_id)
  values (active_session, p_user_id, p_installation_id)
  on conflict (session_id) do update set installation_id = excluded.installation_id;
end;
$$;

revoke all on function public.private_message_push_enabled(),
  public.set_private_message_push(uuid, text) from public, anon;
grant execute on function public.private_message_push_enabled(),
  public.set_private_message_push(uuid, text) to authenticated;

create function app_private.enqueue_private_message_push()
returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into app_private.private_message_push_queue(message_id, session_id)
  select new.id, i.session_id
  from public.conversations c
  join app_private.private_message_installations i
    on i.user_id = case
      when new.sender_id = c.publication_author_id then c.participant_id
      when new.sender_id = c.participant_id then c.publication_author_id
    end
  where c.id = new.conversation_id
  on conflict (message_id, session_id) do nothing;
  return new;
end;
$$;
revoke all on function app_private.enqueue_private_message_push()
  from public, anon, authenticated;

create trigger after_private_message_enqueue_push
after insert on public.messages for each row
execute function app_private.enqueue_private_message_push();

create function public.claim_private_message_pushes()
returns table (
  job_id uuid, attempt integer, installation_id text, recipient_id uuid,
  conversation_id uuid, message_id uuid
)
language plpgsql security definer set search_path = '' as $$
begin
  delete from app_private.private_message_push_queue q
  where q.created_at < now() - interval '1 hour'
     or (q.attempts >= 5 and q.available_at <= now());

  return query
  with ready as (
    select q.id
    from app_private.private_message_push_queue q
    where q.available_at <= now() and q.attempts < 5
    order by q.available_at, q.id
    limit 20
    for update skip locked
  ), claimed as (
    update app_private.private_message_push_queue q
    set attempts = q.attempts + 1, available_at = now() + interval '2 minutes'
    from ready r where q.id = r.id
    returning q.id, q.attempts, q.session_id, q.message_id
  )
  select c.id, c.attempts, i.installation_id, i.user_id, m.conversation_id, m.id
  from claimed c
  join app_private.private_message_installations i on i.session_id = c.session_id
  join public.messages m on m.id = c.message_id;
end;
$$;

create function public.finish_private_message_push(
  p_job_id uuid, p_attempt integer, p_invalid_installation_id text default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  affected_session uuid;
begin
  delete from app_private.private_message_push_queue q
  where q.id = p_job_id and q.attempts = p_attempt
  returning q.session_id into affected_session;

  if p_invalid_installation_id is not null and affected_session is not null then
    delete from app_private.private_message_installations
    where session_id = affected_session and installation_id = p_invalid_installation_id;
  end if;
end;
$$;

revoke all on function public.claim_private_message_pushes(),
  public.finish_private_message_push(uuid, integer, text) from public, anon, authenticated;
grant execute on function public.claim_private_message_pushes(),
  public.finish_private_message_push(uuid, integer, text) to service_role;

notify pgrst, 'reload schema';
commit;
