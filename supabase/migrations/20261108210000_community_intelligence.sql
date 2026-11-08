begin;
-- Snapshot functions are invokers: every source row remains subject to RLS.
create index if not exists idx_publications_risk_window
 on public.publications(district_ubigeo, created_at desc, category, author_id)
 where deleted_at is null and kind='emergencia_solicitud' and status in ('abierta','en_coordinacion') and not is_demo;


create function public.community_resource_family(p_category text) returns text
 language sql immutable security invoker set search_path='' as $$
 select case p_category when 'agua_potable' then 'agua' when 'movilidad' then 'transporte'
 when 'albergue' then 'refugio' else p_category end;
$$;

create index if not exists idx_publications_help_category
 on public.publications(district_ubigeo,public.community_resource_family(category),id)
 where deleted_at is null and status='abierta' and not is_demo;

create function public.community_risk_snapshot(p_district text, p_radius double precision default 300,
 p_minutes integer default 15, p_minimum integer default 3) returns jsonb
 language plpgsql stable security invoker set search_path='' set statement_timeout='4s' as $$
declare result jsonb; stamp timestamptz := statement_timestamp();
begin
 if auth.uid() is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
 if p_district is null or p_district !~ '^[0-9]{6}$' or p_radius is null or not(p_radius between 50 and 1000)
 or p_minutes is null or not(p_minutes between 1 and 60) or p_minimum is null or not(p_minimum between 3 and 20) then
 raise exception 'Parámetros inválidos' using errcode='22023'; end if;
 with source as materialized (
 select distinct on (p.category,p.author_id) p.id,p.author_id,p.category,p.created_at,p.approx_lat,p.approx_lng,p.location
 from public.publications p where p.district_ubigeo=p_district
 and p.kind='emergencia_solicitud' and p.status in ('abierta','en_coordinacion')
 and p.deleted_at is null and not p.is_demo and p.author_id is not null and p.location is not null
 and p.approx_lat between -19 and 0 and p.approx_lng between -82 and -68
 and p.created_at between stamp-make_interval(mins=>p_minutes) and stamp
 order by p.category,p.author_id,p.created_at desc,p.id limit 1001
 ), independent as (
 select * from source
 ), projection as (
 select 32700+greatest(1,least(60,floor((avg(approx_lng)+180)/6)::integer+1)) srid from independent
 ), clusters as (
 select i.*,extensions.ST_ClusterDBSCAN(extensions.ST_Transform(i.location::extensions.geometry,projection.srid),
 eps=>p_radius,minpoints=>p_minimum) over(partition by category order by id) cluster
 from independent i cross join projection where (select count(*) from source)<=1000
 ), summaries as (
 select category,cluster,count(*) neighbors,min(created_at) oldest,max(created_at) newest,
 round(avg(approx_lat)::numeric,3)::double precision lat,round(avg(approx_lng)::numeric,3)::double precision lng,
 jsonb_agg(id order by id) report_ids,
 case when count(*)>=greatest(p_minimum+2,p_minimum*2) and
 max(created_at)>=stamp-make_interval(mins=>greatest(1,p_minutes/3)) then 'attention' else 'concentration' end level
 from clusters where cluster is not null group by category,cluster having count(*)>=p_minimum
 ) select jsonb_build_object('fetched_at',stamp,'expires_at',stamp+interval '30 seconds','district',p_district,
 'complete',(select count(*) from source)<=1000,'source_count',(select count(*) from source),
 'clusters',coalesce((select jsonb_agg(to_jsonb(s)-'cluster' order by category,oldest,cluster) from summaries s),'[]'::jsonb)) into result;
 return result;
end $$;

create function public.community_help_candidates(p_request uuid, p_after uuid default null) returns jsonb
 language plpgsql stable security invoker set search_path='' set statement_timeout='4s' as $$
declare need public.publications; result jsonb;
begin
 if auth.uid() is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
 select * into need from public.publications where id=p_request and author_id=auth.uid() and
 kind in ('favor_solicitud','emergencia_solicitud') and status='abierta' and deleted_at is null and not is_demo;
 if need.id is null then raise exception 'Solicitud no disponible' using errcode='42501'; end if;
 -- Same district is an explicit eligibility boundary; unknown distances are not fabricated.
 with candidates as materialized (
 select p.*,pr.alias as author_alias from public.publications p join public.profiles pr on pr.id=p.author_id
 where p.author_id<>auth.uid() and (p_after is null or p.id>p_after) and p.status='abierta' and p.deleted_at is null and not p.is_demo
 and p.district_ubigeo=need.district_ubigeo
 and p.kind in ('favor_oferta','emergencia_oferta','prestamo','donacion','habilidad','servicio')
 and (p.kind<>'emergencia_oferta' or p.share_resource_consent)
 and need.category not in ('general','donaciones','habilidades')
 and public.community_resource_family(p.category)=public.community_resource_family(need.category)
 and (p.location is null or need.location is null or extensions.ST_DWithin(p.location,need.location,20000))
 order by p.id limit 201
 ) select jsonb_build_object('fetched_at',statement_timestamp(),'expires_at',statement_timestamp()+interval '30 seconds',
 'request',to_jsonb(need)-'location'-'service_location', 'complete',(select count(*) from candidates)<=200,
 'next_cursor',case when (select count(*) from candidates)>200 then (select id from candidates order by id offset 199 limit 1) else null end,
 'offers',coalesce((select jsonb_agg(to_jsonb(c)-'location'-'service_location' order by c.id)
 from (select * from candidates order by id limit 200) c),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function public.community_resource_family(text) from public,anon;
revoke all on function public.community_risk_snapshot(text,double precision,integer,integer) from public,anon;
revoke all on function public.community_help_candidates(uuid,uuid) from public,anon;
grant execute on function public.community_resource_family(text) to authenticated;
grant execute on function public.community_risk_snapshot(text,double precision,integer,integer) to authenticated;
grant execute on function public.community_help_candidates(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
