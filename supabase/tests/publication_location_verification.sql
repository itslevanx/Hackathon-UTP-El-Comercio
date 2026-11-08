begin;
create temp table original_locations as select id,district_ubigeo,approx_lat,approx_lng from public.publications;
select set_config('app.test.actor',gen_random_uuid()::text,true);
select set_config('app.test.other',gen_random_uuid()::text,true);
select set_config('app.test.publication',gen_random_uuid()::text,true);
insert into auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at) values
(current_setting('app.test.actor')::uuid,'authenticated','authenticated','location-author@example.invalid','{"alias":"Prueba ubicación"}',now(),now()),
(current_setting('app.test.other')::uuid,'authenticated','authenticated','location-other@example.invalid','{"alias":"Prueba permisos"}',now(),now());
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('app.test.actor'),'role','authenticated')::text,true);
insert into public.publications(id,client_mutation_id,author_id,kind,category,title,description,neighborhood,sector,approx_lat,approx_lng)
values(current_setting('app.test.publication')::uuid,gen_random_uuid(),current_setting('app.test.actor')::uuid,'servicio','electricidad','Prueba transaccional de ubicación','Registro revertido al terminar','Lima','Referencia de prueba',null,null);
do $$ declare v integer; result integer; blocked boolean:=false; payload jsonb; begin
  select version into v from public.publications where id=current_setting('app.test.publication')::uuid;
  payload:='{"district_ubigeo":"150110","approx_lat":-11.9,"approx_lng":-77.05,"share_service_location":true,"service_lat":-11.900123,"service_lng":-77.050456,"service_address":"Referencia de prueba"}';
  result:=public.update_publication_location(current_setting('app.test.publication')::uuid,v,'location-operation',payload);
  if result<>v+1 then raise exception 'No se incrementó la versión';end if;
  if public.update_publication_location(current_setting('app.test.publication')::uuid,v,'location-operation',payload)<>result then raise exception 'Reintento no idempotente';end if;
  if not exists(select 1 from public.publications where id=current_setting('app.test.publication')::uuid
    and district_ubigeo='150110' and share_service_location and service_lat=-11.900123
    and approx_lat=-11.9 and location is not null) then raise exception 'Ubicación no guardada';end if;
  begin perform public.update_publication_location(current_setting('app.test.publication')::uuid,v,'conflicting-operation',payload);
    exception when sqlstate 'PT409' then blocked:=true;end;
  if not blocked then raise exception 'Se aceptó una versión antigua';end if;
  payload:=jsonb_set(payload,'{share_service_location}','false');
  perform public.update_publication_location(current_setting('app.test.publication')::uuid,result,'remove-public-exact',payload);
  if exists(select 1 from public.publications where id=current_setting('app.test.publication')::uuid
    and (service_lat is not null or service_lng is not null or service_address<>'' or share_service_location)) then
    raise exception 'Se retuvo dirección exacta sin consentimiento';end if;
end $$;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('app.test.other'),'role','authenticated')::text,true);
do $$ declare blocked boolean:=false; begin
  begin perform public.update_publication_location(current_setting('app.test.publication')::uuid,1,'other-user','{}');
    exception when insufficient_privilege then blocked:=true;end;
  if not blocked then raise exception 'Otro usuario pudo cambiar la ubicación';end if;
  blocked:=false;
  begin perform count(*) from app_private.publication_location_operations;
    exception when insufficient_privilege then blocked:=true;end;
  if not blocked then raise exception 'Se expusieron recibos privados';end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from original_locations old join public.publications p using(id)
    where p.district_ubigeo is distinct from old.district_ubigeo or p.approx_lat is distinct from old.approx_lat or p.approx_lng is distinct from old.approx_lng) then
    raise exception 'Se modificaron publicaciones anteriores';end if;
  if has_function_privilege('anon','public.update_publication_location(uuid,integer,text,jsonb)','execute') then
    raise exception 'Se permitió acceso anónimo';end if;
end $$;
rollback;
select 'PASS: ubicación propia, consentimiento, idempotencia, conflictos y registros anteriores intactos' as verification;
