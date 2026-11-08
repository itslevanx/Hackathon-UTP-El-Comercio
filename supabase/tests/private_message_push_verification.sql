begin;

select set_config('test.push.author', gen_random_uuid()::text, true);
select set_config('test.push.recipient', gen_random_uuid()::text, true);
select set_config('test.push.author_session', gen_random_uuid()::text, true);
select set_config('test.push.recipient_session', gen_random_uuid()::text, true);
select set_config('test.push.publication', gen_random_uuid()::text, true);
select set_config('test.push.conversation', gen_random_uuid()::text, true);
select set_config('test.push.message', gen_random_uuid()::text, true);

insert into auth.users(id, aud, role, email, raw_user_meta_data, created_at, updated_at)
select current_setting('test.push.' || name)::uuid, 'authenticated', 'authenticated',
       name || '@private-push.example.invalid', jsonb_build_object('alias', 'Prueba ' || name),
       now(), now()
from unnest(array['author', 'recipient']) name;

insert into auth.sessions(id, user_id, created_at, updated_at)
select current_setting('test.push.' || name || '_session')::uuid,
       current_setting('test.push.' || name)::uuid, now(), now()
from unnest(array['author', 'recipient']) name;

insert into public.publications(id, client_mutation_id, author_id, kind, title, description)
values (current_setting('test.push.publication')::uuid, gen_random_uuid(),
        current_setting('test.push.author')::uuid, 'servicio', 'Servicio de prueba', 'Prueba');

insert into public.conversations(id, client_mutation_id, publication_id,
                                 publication_author_id, participant_id)
values (current_setting('test.push.conversation')::uuid, gen_random_uuid(),
        current_setting('test.push.publication')::uuid,
        current_setting('test.push.author')::uuid, current_setting('test.push.recipient')::uuid);

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('test.push.recipient'),
  'session_id', current_setting('test.push.recipient_session')
)::text, true);
select public.set_private_message_push(current_setting('test.push.recipient')::uuid, repeat('r', 22));
do $$
begin
  if not public.private_message_push_enabled() then raise exception 'No registró la instalación'; end if;
  begin
    perform public.claim_private_message_pushes();
    raise exception 'Un usuario pudo tomar trabajos del servidor';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_private_message_push(current_setting('test.push.author')::uuid, repeat('x', 22));
    raise exception 'Un usuario pudo registrar otra cuenta';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', current_setting('test.push.author'),
  'session_id', current_setting('test.push.author_session')
)::text, true);
select public.set_private_message_push(current_setting('test.push.author')::uuid, repeat('a', 22));
insert into public.messages(id, client_mutation_id, conversation_id, sender_id, body)
values (current_setting('test.push.message')::uuid, current_setting('test.push.message')::uuid,
        current_setting('test.push.conversation')::uuid,
        current_setting('test.push.author')::uuid, 'Texto privado');
insert into public.messages(id, client_mutation_id, conversation_id, sender_id, body)
values (current_setting('test.push.message')::uuid, current_setting('test.push.message')::uuid,
        current_setting('test.push.conversation')::uuid,
        current_setting('test.push.author')::uuid, 'Texto privado')
on conflict (client_mutation_id) do nothing;

reset role;
set local role service_role;
do $$
declare job record;
begin
  select * into strict job from public.claim_private_message_pushes();
  if job.recipient_id <> current_setting('test.push.recipient')::uuid
    or job.installation_id <> repeat('r', 22) or job.attempt <> 1 then
    raise exception 'Destinatario o intento incorrecto';
  end if;
  if to_jsonb(job) ? 'body' then raise exception 'La cola expuso contenido privado'; end if;
  if exists(select 1 from public.claim_private_message_pushes()) then
    raise exception 'Un trabajo en proceso se tomó dos veces';
  end if;
  perform public.finish_private_message_push(job.job_id, job.attempt);
end;
$$;

reset role;
insert into public.messages(id, client_mutation_id, conversation_id, sender_id, body)
values (gen_random_uuid(), gen_random_uuid(), current_setting('test.push.conversation')::uuid,
        current_setting('test.push.author')::uuid, 'Segundo texto');
delete from auth.sessions where id = current_setting('test.push.recipient_session')::uuid;

set local role service_role;
do $$
begin
  if exists(select 1 from public.claim_private_message_pushes()) then
    raise exception 'Se conservó un aviso para una sesión eliminada';
  end if;
end;
$$;
reset role;
rollback;
