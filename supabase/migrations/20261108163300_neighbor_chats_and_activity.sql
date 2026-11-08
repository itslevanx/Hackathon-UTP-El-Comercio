begin;

-- Los hilos históricos conservan sus identificadores y mensajes.
-- Actualizar su actividad no requiere que el aviso original siga publicado.
create or replace function public.trg_conversations_validate()
returns trigger language plpgsql security invoker set search_path='' as $$
declare v_author uuid;
begin
  if tg_op='UPDATE' then
    if new.id<>old.id or new.client_mutation_id<>old.client_mutation_id
       or new.created_at<>old.created_at or new.publication_id<>old.publication_id
       or new.publication_author_id<>old.publication_author_id or new.participant_id<>old.participant_id then
      raise exception 'No se permite reasignar una conversación';
    end if;
    new.updated_at:=now(); return new;
  end if;
  select p.author_id into v_author from public.publications p
    where p.id=new.publication_id and p.deleted_at is null;
  if v_author is null or v_author<>new.publication_author_id or v_author=new.participant_id then
    raise exception 'La publicación o los participantes no son válidos';
  end if;
  new.updated_at:=now(); return new;
end; $$;

create or replace function public.ensure_neighbor_conversation(p_id uuid,p_mutation uuid,p_publication uuid)
returns uuid language plpgsql security invoker set search_path='' as $$
declare actor uuid:=auth.uid(); peer uuid; found_id uuid;
begin
  if actor is null then raise exception 'Inicia sesión' using errcode='42501'; end if;
  select case when c.publication_author_id=actor then c.participant_id else c.publication_author_id end
    into peer from public.conversations c where c.id=p_id and (c.publication_author_id=actor or c.participant_id=actor);
  if peer is null then
    select p.author_id into peer from public.publications p where p.id=p_publication and p.deleted_at is null;
  end if;
  if peer is null or peer=actor then raise exception 'No puedes iniciar este chat' using errcode='42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(least(actor::text,peer::text)||':'||greatest(actor::text,peer::text),0));
  select c.id into found_id from public.conversations c
   where (c.publication_author_id=actor and c.participant_id=peer)
      or (c.publication_author_id=peer and c.participant_id=actor)
   order by c.created_at,c.id limit 1;
  if found_id is not null then return found_id; end if;
  insert into public.conversations(id,client_mutation_id,publication_id,publication_author_id,participant_id)
    values(p_id,p_mutation,p_publication,peer,actor);
  return p_id;
end; $$;
revoke all on function public.ensure_neighbor_conversation(uuid,uuid,uuid) from public,anon;
grant execute on function public.ensure_neighbor_conversation(uuid,uuid,uuid) to authenticated;

create or replace function public.list_neighbor_messages(p_peer uuid)
returns table(id uuid,client_mutation_id uuid,conversation_id uuid,sender_id uuid,sender_alias text,body text,created_at timestamptz)
language sql stable security invoker set search_path='' as $$
  select m.id,m.client_mutation_id,m.conversation_id,m.sender_id,coalesce(pr.alias,'Vecino'),m.body,m.created_at
  from public.messages m join public.conversations c on c.id=m.conversation_id
  left join public.profiles pr on pr.id=m.sender_id
  where auth.uid() is not null and ((c.publication_author_id=auth.uid() and c.participant_id=p_peer)
     or (c.participant_id=auth.uid() and c.publication_author_id=p_peer))
  order by m.created_at,m.id;
$$;
revoke all on function public.list_neighbor_messages(uuid) from public,anon;
grant execute on function public.list_neighbor_messages(uuid) to authenticated;

create or replace function public.list_neighbor_messages_page(p_peer uuid,p_before_time timestamptz default null,p_before_id uuid default null)
returns table(id uuid,client_mutation_id uuid,conversation_id uuid,sender_id uuid,sender_alias text,body text,created_at timestamptz)
language sql stable security invoker set search_path='' as $$
  select m.id,m.client_mutation_id,m.conversation_id,m.sender_id,coalesce(pr.alias,'Vecino'),m.body,m.created_at
  from public.messages m join public.conversations c on c.id=m.conversation_id
  left join public.profiles pr on pr.id=m.sender_id
  where auth.uid() is not null and ((c.publication_author_id=auth.uid() and c.participant_id=p_peer)
     or (c.participant_id=auth.uid() and c.publication_author_id=p_peer))
    and (p_before_time is null or (m.created_at,m.id)<(p_before_time,p_before_id))
  order by m.created_at desc,m.id desc limit 100;
$$;
revoke all on function public.list_neighbor_messages_page(uuid,timestamptz,uuid) from public,anon;
grant execute on function public.list_neighbor_messages_page(uuid,timestamptz,uuid) to authenticated;

create or replace function public.send_neighbor_message(p_id uuid,p_mutation uuid,p_recipient uuid,p_body text)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor uuid:=auth.uid(); target uuid; saved public.messages%rowtype;
begin
  if actor is null or actor=p_recipient then raise exception 'No puedes enviar este mensaje' using errcode='42501'; end if;
  if p_body is null or char_length(trim(p_body)) not between 1 and 1000 then raise exception 'Escribe un mensaje de hasta 1000 caracteres'; end if;
  select c.id into target from public.conversations c
   where (c.publication_author_id=actor and c.participant_id=p_recipient)
      or (c.participant_id=actor and c.publication_author_id=p_recipient)
   order by c.created_at,c.id limit 1;
  if target is null then raise exception 'No existe una conversación con este vecino' using errcode='42501'; end if;
  select * into saved from public.messages where client_mutation_id=p_mutation;
  if found then
    if saved.id<>p_id or saved.sender_id<>actor or saved.body<>trim(p_body) or not exists(
      select 1 from public.conversations c where c.id=saved.conversation_id
        and ((c.publication_author_id=actor and c.participant_id=p_recipient)
          or (c.participant_id=actor and c.publication_author_id=p_recipient))) then
      raise exception 'Operación reutilizada con otros datos' using errcode='PT409';
    end if;
    return to_jsonb(saved);
  end if;
  insert into public.messages(id,client_mutation_id,conversation_id,sender_id,body)
    values(p_id,p_mutation,target,actor,trim(p_body)) on conflict(client_mutation_id) do nothing;
  select * into saved from public.messages where client_mutation_id=p_mutation;
  if not found or saved.id<>p_id or saved.sender_id<>actor or saved.conversation_id<>target or saved.body<>trim(p_body) then
    raise exception 'No se pudo confirmar el mensaje' using errcode='42501';
  end if;
  return to_jsonb(saved);
end; $$;
revoke all on function public.send_neighbor_message(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.send_neighbor_message(uuid,uuid,uuid,text) to authenticated;

create or replace function public.get_my_chat_activity(p_groups uuid[] default '{}'::uuid[])
returns table(chat_key text,last_message_at timestamptz)
language sql stable security invoker set search_path='' as $$
  select 'neighbor:'||case when c.publication_author_id=auth.uid() then c.participant_id else c.publication_author_id end::text,
    max(c.updated_at)
  from public.conversations c
  where c.publication_author_id=auth.uid() or c.participant_id=auth.uid()
  group by 1
  union all
  select 'group:'||requested.id::text,latest.created_at
  from (select distinct unnest(p_groups) as id) requested
  cross join lateral(select m.created_at from public.emergency_group_messages m
    where m.publication_id=requested.id order by m.created_at desc,m.id desc limit 1) latest;
$$;
revoke all on function public.get_my_chat_activity(uuid[]) from public,anon;
grant execute on function public.get_my_chat_activity(uuid[]) to authenticated;
do $$ begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
    select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='conversations') then
    alter publication supabase_realtime add table public.conversations;
  end if;
end $$;
notify pgrst,'reload schema';
commit;
