-- Empty deployment only: aborts if any geographic table contains rows.
-- No CASCADE; unexpected dependencies abort and roll back all changes.
begin;
lock table public.profiles, public.publications, public.community_resources in access exclusive mode;
do $$ begin
  if exists(select 1 from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='postgis' and n.nspname='public') then
    if exists(select 1 from public.profiles) or exists(select 1 from public.publications) or exists(select 1 from public.community_resources) then
      raise exception 'Safety stop: database has data; request supported PostGIS relocation';
    end if;
    alter table public.profiles drop column location;
    alter table public.publications drop column location;
    alter table public.community_resources drop column location;
    drop extension postgis restrict;
    create extension postgis with schema extensions;
    alter table public.profiles add column location extensions.geography(Point,4326);
    alter table public.publications add column location extensions.geography(Point,4326);
    alter table public.community_resources add column location extensions.geography(Point,4326);
    create index idx_profiles_location on public.profiles using gist(location);
    create index idx_publications_location on public.publications using gist(location);
    create index idx_community_resources_location on public.community_resources using gist(location);
  end if;
end $$;
alter function public.trg_profiles_sanitize() set search_path = public, extensions;
alter function public.trg_publications_validate() set search_path = public, extensions;
alter function public.trg_community_resources_sanitize() set search_path = public, extensions;
alter function public.search_publications_within_radius(double precision,double precision,double precision,text,text,text) set search_path = public, extensions;
alter function public.search_resources_within_radius(double precision,double precision,double precision,text) set search_path = public, extensions;
do $$ begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
  end if;
end $$;
notify pgrst, 'reload schema';
commit;
select extnamespace::regnamespace as postgis_schema from pg_extension where extname='postgis';
