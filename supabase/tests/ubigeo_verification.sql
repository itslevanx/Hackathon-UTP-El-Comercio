begin;

create temp table original_profiles as select id, to_jsonb(p) as body from public.profiles p;
select set_config('app.test.location_a',gen_random_uuid()::text,true);
select set_config('app.test.location_b',gen_random_uuid()::text,true);
select set_config('app.test.location_publication',gen_random_uuid()::text,true);

do $$ begin
  if (select count(*) from app_private.peru_districts) <> 1893
     or (select count(distinct left(code,2)) from app_private.peru_districts) <> 25
     or (select count(distinct left(code,4)) from app_private.peru_districts) <> 196 then
    raise exception 'Catálogo INEI incompleto';
  end if;
  if not exists(select 1 from app_private.peru_districts where code='120307' and name='Sangani') then
    raise exception 'Falta Sangani en versión 2026';
  end if;
end $$;

insert into auth.users(id,aud,role,email,raw_user_meta_data,created_at,updated_at)
values
(current_setting('app.test.location_a')::uuid,'authenticated','authenticated','ubigeo-a@example.invalid',
 '{"alias":"Prueba UBIGEO A","neighborhood":"La Molina","sector":"Referencia de prueba","district_ubigeo":"150114"}',now(),now()),
(current_setting('app.test.location_b')::uuid,'authenticated','authenticated','ubigeo-b@example.invalid',
 '{"alias":"Prueba UBIGEO B","neighborhood":"Sangani","sector":"Referencia de prueba","district_ubigeo":"120307"}',now(),now());

set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('app.test.location_a'),'role','authenticated')::text,true);

do $$ declare bad_code text; blocked boolean; begin
  if not exists(select 1 from public.profiles where id=current_setting('app.test.location_a')::uuid
      and district_ubigeo='150114' and approx_lat is null and approx_lng is null and location is null) then
    raise exception 'El perfil perdió UBIGEO o recibió coordenadas ficticias';
  end if;
  foreach bad_code in array array['15','999999'] loop
    blocked:=false;
    begin
      update public.profiles set district_ubigeo=bad_code where id=current_setting('app.test.location_a')::uuid;
    exception when foreign_key_violation then blocked:=true;
    end;
    if not blocked then raise exception 'Código inválido aceptado: %',bad_code; end if;
  end loop;
end $$;

insert into public.publications(id,client_mutation_id,author_id,kind,title,description,neighborhood,sector,district_ubigeo,approx_lat,approx_lng)
values (current_setting('app.test.location_publication')::uuid,gen_random_uuid(),current_setting('app.test.location_a')::uuid,
 'favor_solicitud','Prueba de ubicación distrital','Solicitud ficticia revertida al terminar','La Molina','Referencia de prueba','150114',null,null);

do $$ declare found_count integer; begin
  select count(*) into found_count from public.search_publications_by_location(null,null,1000,'150114')
    where publication->>'id'=current_setting('app.test.location_publication');
  if found_count <> 1 then raise exception 'La búsqueda por distrito sin coordenadas falló'; end if;
  if exists(select 1 from public.search_publications_by_location(null,null,1000,'120307')
    where publication->>'id'=current_setting('app.test.location_publication')) then
    raise exception 'La búsqueda mezcla distritos diferentes';
  end if;
  if not exists(select 1 from public.search_publications_by_location(-12.076,-77.063,1000,'150114')
    where publication->>'id'=current_setting('app.test.location_publication') and publication->>'district_ubigeo'='150114'
      and publication->>'approx_lat' is null) then
    raise exception 'La búsqueda descartó un resultado distrital sin coordenadas';
  end if;
end $$;

select set_config('request.jwt.claims',jsonb_build_object('sub',current_setting('app.test.location_b'),'role','authenticated')::text,true);
do $$ declare changed integer; blocked boolean:=false; begin
  update public.profiles set district_ubigeo='120307' where id=current_setting('app.test.location_a')::uuid;
  get diagnostics changed=row_count;
  if changed<>0 then raise exception 'RLS permitió cambiar la ubicación de otro usuario'; end if;
  begin perform count(*) from app_private.peru_districts;
  exception when insufficient_privilege then blocked:=true;
  end;
  if not blocked then raise exception 'El catálogo privado es accesible directamente'; end if;
end $$;

reset role;
do $$ begin
  if exists(select 1 from original_profiles old left join public.profiles p on p.id=old.id where to_jsonb(p) is distinct from old.body) then
    raise exception 'Se modificaron perfiles preexistentes';
  end if;
  if has_function_privilege('anon','public.search_publications_by_location(double precision,double precision,double precision,text,text,text,text)','execute') then
    raise exception 'La RPC permite acceso anónimo';
  end if;
end $$;
rollback;
select 'PASS: UBIGEO 2026, perfiles, publicaciones sin GPS, códigos inválidos y RLS' as verification;
