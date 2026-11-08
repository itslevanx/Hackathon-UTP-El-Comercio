begin;
alter table public.publications add column if not exists deleted_at timestamptz;
alter table public.publications drop constraint if exists publications_kind_check;
alter table public.publications add constraint publications_kind_check check(kind in
 ('anuncio','servicio','favor_solicitud','favor_oferta','prestamo','donacion','habilidad','emergencia_solicitud','emergencia_oferta'));
create index if not exists idx_publications_feed on public.publications(district_ubigeo,created_at desc,id desc) where deleted_at is null;
drop policy if exists publications_select_authenticated on public.publications;
create policy publications_select_authenticated on public.publications for select to authenticated
 using(deleted_at is null or author_id=(select auth.uid()));
revoke delete on public.publications from authenticated;

create table if not exists public.publication_tombstones(
 publication_id uuid primary key, deleted_at timestamptz not null
);
alter table public.publication_tombstones enable row level security;
revoke all on public.publication_tombstones from public,anon,authenticated;
grant select on public.publication_tombstones to authenticated;
create policy publication_tombstones_read on public.publication_tombstones for select to authenticated using(true);
create or replace function app_private.record_publication_deletion()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.deleted_at is not null then raise exception 'La publicación fue eliminada' using errcode='PT409'; end if;
 if new.deleted_at is not null then
   insert into public.publication_tombstones(publication_id,deleted_at) values(new.id,new.deleted_at)
   on conflict(publication_id) do nothing;
 end if;
 return new;
end; $$;
revoke all on function app_private.record_publication_deletion() from public,anon,authenticated;
create trigger before_publication_deletion before update on public.publications
 for each row execute function app_private.record_publication_deletion();

create table app_private.publication_content_operations(
 actor_id uuid not null references auth.users(id) on delete cascade,
 operation_id text not null, publication_id uuid not null references public.publications(id) on delete cascade,
 deleting boolean not null, changes jsonb not null, resulting_version integer not null,
 primary key(actor_id,operation_id)
);
create index idx_content_operations_publication on app_private.publication_content_operations(publication_id);
alter table app_private.publication_content_operations enable row level security;
revoke all on app_private.publication_content_operations from public,anon,authenticated;
create or replace function app_private.mutate_publication(p_id uuid,p_expected_version integer,
 p_operation_id text,p_delete boolean,p_changes jsonb)
returns integer language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); publication public.publications%rowtype;
 receipt app_private.publication_content_operations%rowtype; payload jsonb; result_version integer;
begin
 if actor is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
 if p_operation_id is null or length(p_operation_id) not between 1 and 100 or p_delete is null then
   raise exception 'Operación inválida'; end if;
 select * into publication from public.publications where id=p_id for update;
 if not found or publication.author_id<>actor then raise exception 'Solo el autor puede cambiar su publicación' using errcode='42501'; end if;
 payload:=case when p_delete then '{}'::jsonb else jsonb_build_object(
  'title',trim(p_changes->>'title'),'description',trim(p_changes->>'description'),
  'category',trim(p_changes->>'category'),'availability_text',trim(coalesce(p_changes->>'availability_text',''))) end;
 select * into receipt from app_private.publication_content_operations where actor_id=actor and operation_id=p_operation_id;
 if found then
  if receipt.publication_id<>p_id or receipt.deleting<>p_delete or receipt.changes<>payload then
    raise exception 'Operación reutilizada con otros datos' using errcode='PT409'; end if;
  return receipt.resulting_version;
 end if;
 if publication.deleted_at is not null or publication.version<>p_expected_version then
  raise exception 'La publicación cambió. Revisa antes de guardar' using errcode='PT409'; end if;
 if p_delete then
  update public.publications set deleted_at=now() where id=p_id returning version into result_version;
 else
  if payload->>'title' is null or char_length(payload->>'title') not between 3 and 120
    or payload->>'description' is null or char_length(payload->>'description') not between 1 and 1000
    or payload->>'category' is null or char_length(payload->>'category') not between 2 and 50
    or char_length(payload->>'availability_text')>200 then raise exception 'Revisa los campos de la publicación'; end if;
  update public.publications set title=payload->>'title',description=payload->>'description',
    category=payload->>'category',availability_text=payload->>'availability_text'
    where id=p_id returning version into result_version;
 end if;
 insert into app_private.publication_content_operations values(actor,p_operation_id,p_id,p_delete,payload,result_version);
 return result_version;
end; $$;
revoke all on function app_private.mutate_publication(uuid,integer,text,boolean,jsonb) from public,anon;
grant execute on function app_private.mutate_publication(uuid,integer,text,boolean,jsonb) to authenticated;
create or replace function public.mutate_publication(p_id uuid,p_expected_version integer,
 p_operation_id text,p_delete boolean,p_changes jsonb)
returns integer language sql security invoker set search_path='' as $$
 select app_private.mutate_publication(p_id,p_expected_version,p_operation_id,p_delete,p_changes);
$$;
revoke all on function public.mutate_publication(uuid,integer,text,boolean,jsonb) from public,anon;
grant execute on function public.mutate_publication(uuid,integer,text,boolean,jsonb) to authenticated;

create or replace function public.neighborhood_feed(p_district text default null,
 p_before_time timestamptz default null,p_before_id uuid default null,p_limit integer default 30)
returns table(publication jsonb,author_alias text) language sql stable security invoker set search_path='' as $$
 select to_jsonb(p)-'location',coalesce(pr.alias,'Vecino') from public.publications p
 left join public.profiles pr on pr.id=p.author_id
 where p.deleted_at is null and (p_district is null or p.district_ubigeo=p_district or p.author_id=(select auth.uid()))
 and (p_before_time is null or (p.created_at,p.id)<(p_before_time,p_before_id))
 order by p.created_at desc,p.id desc limit greatest(1,least(coalesce(p_limit,30),100));
$$;
revoke all on function public.neighborhood_feed(text,timestamptz,uuid,integer) from public,anon;
grant execute on function public.neighborhood_feed(text,timestamptz,uuid,integer) to authenticated;
create or replace function public.search_publications_by_location(
  p_lat double precision default null,
  p_lng double precision default null,
  p_radius_meters double precision default 1000,
  p_district_ubigeo text default null,
  p_kind text default null,
  p_category text default null,
  p_search text default null
) returns table(publication jsonb, author_alias text)
language sql stable security invoker set search_path=public, extensions as $$
  with origin as (
    select case when p_lat between -90 and 90 and p_lng between -180 and 180
      then st_setsrid(st_makepoint(public.round_public_coord(p_lng),public.round_public_coord(p_lat)),4326)::geography
      else null end as point
  )
  select to_jsonb(p)-'location', coalesce(pr.alias,'Vecino')
  from public.publications p
  cross join origin o
  left join public.profiles pr on pr.id=p.author_id
  where (
    (o.point is not null and p.location is not null and st_dwithin(p.location,o.point,greatest(100,least(p_radius_meters,20000))))
    or (p.district_ubigeo=p_district_ubigeo and (o.point is null or p.location is null))
  )
    and p.deleted_at is null
    and (p_kind is null or p.kind=p_kind)
    and (p_category is null or p_category='todos' or p.category=p_category)
    and (p_search is null or trim(p_search)='' or p.title ilike '%'||trim(p_search)||'%' or p.description ilike '%'||trim(p_search)||'%' or p.sector ilike '%'||trim(p_search)||'%')
  order by case p.priority when 'emergencia' then 0 when 'urgente' then 1 else 2 end,
    st_distance(p.location,o.point) nulls last,p.created_at desc;
$$;
revoke all on function public.search_publications_by_location(double precision,double precision,double precision,text,text,text,text) from public, anon;
grant execute on function public.search_publications_by_location(double precision,double precision,double precision,text,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
