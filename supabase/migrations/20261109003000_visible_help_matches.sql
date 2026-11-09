begin;
-- Visible district requests only; source RLS and caller identity remain in force.
create function public.community_visible_help_candidates(p_request uuid, p_after uuid default null) returns jsonb
 language plpgsql stable security invoker set search_path='' set statement_timeout='4s' as $$
declare need public.publications; result jsonb;
begin
 if auth.uid() is null then raise exception 'Sesión requerida' using errcode='42501'; end if;
 select * into need from public.publications where id=p_request and district_ubigeo=(select me.district_ubigeo from public.profiles me where me.id=auth.uid()) and
 kind in ('favor_solicitud','emergencia_solicitud') and status='abierta' and deleted_at is null and not is_demo;
 if need.id is null then raise exception 'Solicitud no disponible' using errcode='42501'; end if;
 -- Same district is an explicit eligibility boundary; unknown distances are not fabricated.
 with candidates as materialized (
 select p.*,pr.alias as author_alias from public.publications p join public.profiles pr on pr.id=p.author_id
 where p.author_id<>need.author_id and (p_after is null or p.id>p_after) and p.status='abierta' and p.deleted_at is null and not p.is_demo
 and p.district_ubigeo=need.district_ubigeo
 and p.kind in ('favor_oferta','emergencia_oferta','prestamo','donacion','habilidad','servicio')
 and (p.kind<>'emergencia_oferta' or p.share_resource_consent)
 and need.category not in ('general','donaciones','habilidades')
 and public.community_resource_family(p.category)=public.community_resource_family(need.category)
 and (p.location is null or need.location is null or extensions.ST_DWithin(p.location,need.location,20000))
 order by p.id limit 201
 ) select jsonb_build_object('fetched_at',statement_timestamp(),'expires_at',statement_timestamp()+interval '30 seconds',
 'request',(to_jsonb(need)-'location'-'service_location')||jsonb_build_object('author_alias',(select alias from public.profiles where id=need.author_id)), 'complete',(select count(*) from candidates)<=200,
 'next_cursor',case when (select count(*) from candidates)>200 then (select id from candidates order by id offset 199 limit 1) else null end,
 'offers',coalesce((select jsonb_agg(to_jsonb(c)-'location'-'service_location' order by c.id)
 from (select * from candidates order by id limit 200) c),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function public.community_visible_help_candidates(uuid,uuid) from public,anon;
grant execute on function public.community_visible_help_candidates(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
