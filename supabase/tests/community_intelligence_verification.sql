-- Run against an isolated migrated database. Fixtures are rolled back.
begin;
create function pg_temp.assert_true(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception '%', message; end if; end $$;
insert into auth.users(id,email,raw_user_meta_data)
select ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'ci-'||i||'@test.invalid',jsonb_build_object('alias','Vecino prueba '||i) from generate_series(1,10) i;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
select ('10000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,gen_random_uuid(),
 ('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'emergencia_solicitud','inundacion','Reporte prueba','Prueba aislada','150110',-12.076,-77.063+(i-1)*.001 from generate_series(1,3) i;
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=1,'Tres vecinos cercanos deben agruparse');
select pg_temp.assert_true((public.community_risk_snapshot('150110')->'clusters'->0->>'neighbors')::int=3,'Conteo independiente');
select pg_temp.assert_true(public.community_risk_snapshot('150110')->'clusters'->0->>'level'='concentration','No debe confirmar emergencias');
reset role;
-- Ten copies from the same author must never raise the independent count.
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
select gen_random_uuid(),gen_random_uuid(),'00000000-0000-4000-8000-000000000001','emergencia_solicitud','inundacion','Copia prueba','Repetición','150110',-12.076,-77.063 from generate_series(1,10);
set local role authenticated;
select pg_temp.assert_true((public.community_risk_snapshot('150110')->'clusters'->0->>'neighbors')::int=3,'Repeticiones no elevan atención');
reset role;
update public.publications set approx_lat=-12.1 where author_id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=0,'Cambio de ubicación fuera del radio');
reset role;
update public.publications set approx_lat=-12.076,created_at=now()-interval '16 minutes' where author_id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=0,'Caducidad temporal');
reset role;
update public.publications set created_at=now(),category='incendio' where author_id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=0,'Categorías incompatibles');
reset role;
update public.publications set category='inundacion',approx_lat=null,approx_lng=null where author_id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=0,'Sin ubicación no se agrupa');
reset role;
update public.publications set approx_lat=-12.076,approx_lng=-77.062,deleted_at=now() where author_id='00000000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=0,'Eliminados no se agrupan');
reset role;
-- New active incident: six independent neighbors yields attention, never verification.
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
select gen_random_uuid(),gen_random_uuid(),('00000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
'emergencia_solicitud','sismo','Sismo prueba','Prueba','150110',-12.076,-77.063 from generate_series(1,6) i;
set local role authenticated;
select pg_temp.assert_true(public.community_risk_snapshot('150110')->'clusters'->0->>'level'='attention','Seis vecinos requieren atención');
reset role;
-- A restrictive policy proves the functions cannot bypass source authorization.
create policy ci_private_category on public.publications as restrictive for select to authenticated using(category<>'sismo');
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150110')->'clusters')=0,'DBSCAN respeta RLS');
reset role;
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
values('20000000-0000-4000-8000-000000000001',gen_random_uuid(),'00000000-0000-4000-8000-000000000001','favor_solicitud','agua','Necesito agua','Agua','150110',-12.076,-77.063),
('20000000-0000-4000-8000-000000000002',gen_random_uuid(),'00000000-0000-4000-8000-000000000002','donacion','agua','Ofrezco agua','Agua','150110',-12.076,-77.063),
('20000000-0000-4000-8000-000000000003',gen_random_uuid(),'00000000-0000-4000-8000-000000000001','donacion','agua','Mi propia agua','Agua','150110',-12.076,-77.063),
('20000000-0000-4000-8000-000000000004',gen_random_uuid(),'00000000-0000-4000-8000-000000000004','donacion','transporte','Transporte disponible','Transporte','150110',-12.076,-77.063);
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_help_candidates('20000000-0000-4000-8000-000000000001')->'offers')=1,'Solo ofertas compatibles ajenas');
reset role;
update public.publications set status='resuelta' where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_help_candidates('20000000-0000-4000-8000-000000000001')->'offers')=0,'Oferta agotada/resuelta');
reset role;
update public.publications set status='abierta',approx_lat=null,approx_lng=null where id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_help_candidates('20000000-0000-4000-8000-000000000001')->'offers')=1,'Sin coordenadas conserva distrito, Dart no inventa distancia');
reset role;
create policy ci_hide_offer on public.publications as restrictive for select to authenticated using(id<>'20000000-0000-4000-8000-000000000002');
set local role authenticated;
select pg_temp.assert_true(jsonb_array_length(public.community_help_candidates('20000000-0000-4000-8000-000000000001')->'offers')=0,'Matching respeta RLS');
do $$ begin
 begin perform public.community_help_candidates('10000000-0000-4000-8000-000000000002'); raise exception 'Acceso indebido'; exception when insufficient_privilege then null; end;
 begin perform public.community_risk_snapshot('150110',0,15,3); raise exception 'Validación ausente'; exception when invalid_parameter_value then null; end;
end $$;
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.community_risk_snapshot(text,double precision,integer,integer)','execute'),'Anon no ejecuta DBSCAN');
select pg_temp.assert_true(not has_function_privilege('anon','public.community_help_candidates(uuid,uuid)','execute'),'Anon no ejecuta matching');
-- Pagination and revoked/deleted candidates cannot leak into later pages.
drop policy ci_hide_offer on public.publications;
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo)
select ('30000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,gen_random_uuid(),
 '00000000-0000-4000-8000-000000000002','donacion','agua','Oferta paginada','Prueba','150110' from generate_series(1,205) i;
set local role authenticated;
do $$ declare first_page jsonb; next_page jsonb; begin
 first_page:=public.community_help_candidates('20000000-0000-4000-8000-000000000001');
 perform pg_temp.assert_true(jsonb_array_length(first_page->'offers')=200,'Primera página acotada');
 perform pg_temp.assert_true((first_page->>'complete')::boolean=false,'Indica resultados parciales');
 next_page:=public.community_help_candidates('20000000-0000-4000-8000-000000000001',(first_page->>'next_cursor')::uuid);
 perform pg_temp.assert_true(jsonb_array_length(next_page->'offers')=6,'Segunda página sin duplicados');
 perform pg_temp.assert_true((next_page->>'complete')::boolean,'Fin de paginación');
 perform pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(first_page->'offers') a
 join jsonb_array_elements(next_page->'offers') b on a->>'id'=b->>'id'),'No repite ofertas');
end $$;
reset role;
-- More than 1000 independent reporters: refuse incomplete risk computation.
insert into auth.users(id,email,raw_user_meta_data)
select ('40000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'limit-'||i||'@test.invalid',jsonb_build_object('alias','Prueba límite') from generate_series(1,1001) i;
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,district_ubigeo,approx_lat,approx_lng)
select gen_random_uuid(),gen_random_uuid(),('40000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
 'emergencia_solicitud','inundacion','Reporte límite','Prueba','150101',-12.076,-77.063 from generate_series(1,1001) i;
set local role authenticated;
select pg_temp.assert_true((public.community_risk_snapshot('150101')->>'complete')::boolean=false,'Detección acotada');
select pg_temp.assert_true(jsonb_array_length(public.community_risk_snapshot('150101')->'clusters')=0,'No crea alertas con datos incompletos');
reset role;
rollback;
