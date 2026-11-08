begin;
create table public.emergency_group_messages (
 id uuid primary key,client_mutation_id uuid not null unique,
 publication_id uuid not null references public.publications(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now()
);
create index idx_emergency_group_history on public.emergency_group_messages(publication_id,created_at desc,id desc);
create index idx_emergency_group_sender on public.emergency_group_messages(sender_id);
alter table public.emergency_group_messages enable row level security;
revoke all on public.emergency_group_messages from public,anon,authenticated;
grant select,insert on public.emergency_group_messages to authenticated;

create or replace function public.trg_emergency_group_message()
returns trigger language plpgsql security invoker set search_path='' as $$
begin new.created_at:=now();new.body:=trim(new.body);return new;end;$$;
revoke all on function public.trg_emergency_group_message() from public,anon,authenticated;
create trigger before_emergency_group_message before insert on public.emergency_group_messages
 for each row execute function public.trg_emergency_group_message();

create policy emergency_group_read on public.emergency_group_messages for select to authenticated using(
 exists(select 1 from public.publications p where p.id=publication_id and p.kind in ('emergencia_solicitud','emergencia_oferta') and p.deleted_at is null
 and (p.author_id=(select auth.uid()) or (p.district_ubigeo is not null and exists(select 1 from public.profiles me where me.id=(select auth.uid()) and me.district_ubigeo=p.district_ubigeo))))
);
create policy emergency_group_send on public.emergency_group_messages for insert to authenticated with check(
 sender_id=(select auth.uid()) and exists(select 1 from public.publications p where p.id=publication_id
 and p.kind in ('emergencia_solicitud','emergencia_oferta') and p.deleted_at is null and p.status not in ('resuelta','cancelada')
 and (p.author_id=(select auth.uid()) or (p.district_ubigeo is not null and exists(select 1 from public.profiles me where me.id=(select auth.uid()) and me.district_ubigeo=p.district_ubigeo))))
);
create or replace function public.send_emergency_group_message(p_id uuid,p_mutation uuid,p_publication uuid,p_body text)
returns uuid language plpgsql security invoker set search_path='' as $$
declare message public.emergency_group_messages%rowtype;actor uuid:=auth.uid();
begin
 if actor is null then raise exception 'Inicia sesión para conversar' using errcode='42501';end if;
 if p_id is null or p_mutation is null or p_body is null or char_length(trim(p_body)) not between 1 and 1000 then raise exception 'Escribe un mensaje válido';end if;
 select * into message from public.emergency_group_messages where client_mutation_id=p_mutation;
 if found then
  if message.id<>p_id or message.sender_id<>actor or message.publication_id<>p_publication or message.body<>trim(p_body) then
   raise exception 'Operación reutilizada con otros datos' using errcode='PT409';end if;
  return message.id;
 end if;
 insert into public.emergency_group_messages(id,client_mutation_id,publication_id,sender_id,body)
 values(p_id,p_mutation,p_publication,actor,trim(p_body)) on conflict(client_mutation_id) do nothing;
 select * into message from public.emergency_group_messages where client_mutation_id=p_mutation;
 if not found or message.id<>p_id or message.sender_id<>actor or message.publication_id<>p_publication or message.body<>trim(p_body) then
  raise exception 'No se pudo confirmar este mensaje' using errcode='42501';end if;
 return message.id;
end; $$;
revoke all on function public.send_emergency_group_message(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.send_emergency_group_message(uuid,uuid,uuid,text) to authenticated;
create or replace function public.list_emergency_group_messages(p_publication uuid,
 p_before_time timestamptz default null,p_before_id uuid default null)
returns table(id uuid,client_mutation_id uuid,publication_id uuid,sender_id uuid,sender_alias text,body text,created_at timestamptz)
language sql stable security invoker set search_path='' as $$
 select m.id,m.client_mutation_id,m.publication_id,m.sender_id,coalesce(pr.alias,'Vecino'),m.body,m.created_at
 from public.emergency_group_messages m left join public.profiles pr on pr.id=m.sender_id
 where m.publication_id=p_publication and (p_before_time is null or (m.created_at,m.id)<(p_before_time,p_before_id))
 order by m.created_at desc,m.id desc limit 100;
$$;
revoke all on function public.list_emergency_group_messages(uuid,timestamptz,uuid) from public,anon;
grant execute on function public.list_emergency_group_messages(uuid,timestamptz,uuid) to authenticated;
do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime') and not exists(
  select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='emergency_group_messages') then
  alter publication supabase_realtime add table public.emergency_group_messages;
 end if;
end $$;
notify pgrst,'reload schema';
commit;
