begin;
alter table public.publications add column if not exists service_lat double precision;
alter table public.publications add column if not exists service_lng double precision;
alter table public.publications add column if not exists service_address text not null default '';
alter table public.publications add column if not exists share_service_location boolean not null default false;

create or replace function public.trg_public_service_location()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if new.share_service_location then
    if new.kind <> 'servicio' or new.service_lat is null or new.service_lng is null
      or not (new.service_lat between -85.05112878 and 85.05112878)
      or not (new.service_lng between -180 and 180) then
      raise exception 'Un punto exacto requiere un servicio y coordenadas válidas';
    end if;
    new.service_lat := round(new.service_lat::numeric,6)::double precision;
    new.service_lng := round(new.service_lng::numeric,6)::double precision;
    new.service_address := left(trim(new.service_address),300);
    new.approx_lat := public.round_public_coord(new.service_lat);
    new.approx_lng := public.round_public_coord(new.service_lng);
  else
    new.service_lat := null;
    new.service_lng := null;
    new.service_address := '';
  end if;
  return new;
end;
$$;
revoke all on function public.trg_public_service_location() from public,anon,authenticated;
drop trigger if exists before_public_service_location on public.publications;
create trigger before_public_service_location before insert or update on public.publications
for each row execute function public.trg_public_service_location();

create table if not exists app_private.publication_location_operations (
  actor_id uuid not null references auth.users(id) on delete cascade,
  operation_id text not null,
  publication_id uuid not null references public.publications(id) on delete cascade,
  location jsonb not null,
  resulting_version integer not null,
  primary key(actor_id,operation_id)
);
create index if not exists idx_location_operations_publication on app_private.publication_location_operations(publication_id);
alter table app_private.publication_location_operations enable row level security;
revoke all on app_private.publication_location_operations from public,anon,authenticated;

create or replace function app_private.update_publication_location(
  p_id uuid,p_expected_version integer,p_operation_id text,p_location jsonb
) returns integer language plpgsql security definer set search_path='' as $$
declare
  actor uuid := auth.uid();
  publication public.publications%rowtype;
  receipt app_private.publication_location_operations%rowtype;
  district app_private.peru_districts%rowtype;
  payload jsonb;
  result_version integer;
begin
  if actor is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
  if p_operation_id is null or length(p_operation_id) not between 1 and 100 then
    raise exception 'Operación inválida';
  end if;
  select * into publication from public.publications where id=p_id for update;
  if not found or publication.author_id<>actor then
    raise exception 'Solo el autor puede ubicar su publicación' using errcode='42501';
  end if;
  select * into district from app_private.peru_districts where code=p_location->>'district_ubigeo';
  if not found then raise exception 'Selecciona un distrito válido'; end if;
  if not ((p_location->>'approx_lat')::double precision between -85.05112878 and 85.05112878)
    or not ((p_location->>'approx_lng')::double precision between -180 and 180)
    or p_location->>'approx_lat' is null or p_location->>'approx_lng' is null then
    raise exception 'Selecciona un punto válido';
  end if;
  payload := jsonb_build_object(
    'district_ubigeo',district.code,
    'approx_lat',public.round_public_coord((p_location->>'approx_lat')::double precision),
    'approx_lng',public.round_public_coord((p_location->>'approx_lng')::double precision),
    'share_service_location',coalesce((p_location->>'share_service_location')::boolean,false),
    'service_lat',case when coalesce((p_location->>'share_service_location')::boolean,false) then (p_location->>'service_lat')::double precision else null end,
    'service_lng',case when coalesce((p_location->>'share_service_location')::boolean,false) then (p_location->>'service_lng')::double precision else null end,
    'service_address',case when coalesce((p_location->>'share_service_location')::boolean,false) then left(coalesce(p_location->>'service_address',''),300) else '' end);
  select * into receipt from app_private.publication_location_operations
    where actor_id=actor and operation_id=p_operation_id;
  if found then
    if receipt.publication_id<>p_id or receipt.location<>payload then
      raise exception 'Operación reutilizada con otros datos' using errcode='PT409';
    end if;
    return receipt.resulting_version;
  end if;
  if publication.version<>p_expected_version then
    raise exception 'La publicación cambió. Revisa antes de guardar' using errcode='PT409';
  end if;
  update public.publications set district_ubigeo=district.code,neighborhood=district.name,
    approx_lat=(payload->>'approx_lat')::double precision,approx_lng=(payload->>'approx_lng')::double precision,
    share_service_location=(payload->>'share_service_location')::boolean,
    service_lat=(payload->>'service_lat')::double precision,service_lng=(payload->>'service_lng')::double precision,
    service_address=payload->>'service_address'
  where id=p_id returning version into result_version;
  insert into app_private.publication_location_operations values(actor,p_operation_id,p_id,payload,result_version);
  return result_version;
end;
$$;
revoke all on function app_private.update_publication_location(uuid,integer,text,jsonb) from public,anon;
grant execute on function app_private.update_publication_location(uuid,integer,text,jsonb) to authenticated;
create or replace function public.update_publication_location(
  p_id uuid,p_expected_version integer,p_operation_id text,p_location jsonb
) returns integer language sql security invoker set search_path='' as $$
 select app_private.update_publication_location(p_id,p_expected_version,p_operation_id,p_location);
$$;
revoke all on function public.update_publication_location(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.update_publication_location(uuid,integer,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
