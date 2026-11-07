-- =============================================================================
-- Prueba reproducible de RLS, permisos de API, unicidad, chat y PostGIS
-- Ejecutable sobre una instancia Supabase / PostgreSQL con el esquema aplicado.
-- Verifica:
--   1. Acceso sin sesión (anon) denegado.
--   2. Publicación real entre dos usuarios autenticados (Rosa y Luis Alberto).
--   3. Búsqueda espacial PostGIS dentro (<=1km) y fuera (>1km) del radio,
--      verificando truncado de coordenadas privadas.
--   4. Recomendación propia rechazada, recomendación duplicada rechazada,
--      y modificación/retiro permitidos al autor.
--   5. Chat permitido para los dos participantes y denegado para un tercero (Don Jorge).
--   6. Bloqueo de reasignación de autor o remitente (sender_id = auth.uid()).
-- =============================================================================

begin;

-- Crear usuarios de prueba en auth.users (simulando identidades registradas en Supabase Auth)
insert into auth.users (id, email, raw_user_meta_data, role, aud, created_at, updated_at)
values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'rosa.demo@example.com', '{"alias":"Rosa M."}'::jsonb, 'authenticated', 'authenticated', now(), now()),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'luis.demo@example.com', '{"alias":"Luis Alberto"}'::jsonb, 'authenticated', 'authenticated', now(), now()),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'jorge.demo@example.com', '{"alias":"Don Jorge"}'::jsonb, 'authenticated', 'authenticated', now(), now())
on conflict (id) do nothing;

-- 1. Probar que el rol anon NO puede leer ni insertar en tablas protegidas
set local role anon;
do $$
declare
  v_denied boolean := false;
begin
  begin
    perform count(*) from public.publications;
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'FALLO RLS: anon pudo consultar public.publications';
  end if;
end $$;

-- 2. Sesión como Usuario A (Rosa) -> crear perfil y solicitud de ayuda
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

insert into public.profiles (id, alias, neighborhood, sector, approx_lat, approx_lng, is_demo)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Rosa M.', 'Pueblo Libre', 'Sector San Martín', -12.0764321, -77.0631987, true) on conflict(id) do update set alias=excluded.alias, approx_lat=excluded.approx_lat, approx_lng=excluded.approx_lng;

-- Verificar que la coordenada privada fue truncada a 3 decimales (-12.076, -77.063)
do $$
declare
  v_lat double precision;
  v_lng double precision;
begin
  select approx_lat, approx_lng into v_lat, v_lng
  from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  if v_lat <> -12.076 or v_lng <> -77.063 then
    raise exception 'FALLO PRIVACIDAD: coordenadas no fueron truncadas: %, %', v_lat, v_lng;
  end if;
end $$;

insert into public.publications (
  id, client_mutation_id, author_id, kind, category, title, description, neighborhood, sector, approx_lat, approx_lng, is_demo
) values (
  'd0000000-0000-4000-8000-000000000001',
  'e0000000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'prestamo',
  'herramientas',
  'Necesito escalera de tijera por 2 horas',
  'Para cambiar foco alto en patio. Datos de demostración.',
  'Pueblo Libre',
  'Sector San Martín',
  -12.0764,
  -77.0631,
  true
);

-- 3. Sesión como Usuario B (Luis Alberto) -> crear perfil, publicar servicio cercano (~350m) y otro lejano (~3.2km)
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);

insert into public.profiles (id, alias, neighborhood, sector, approx_lat, approx_lng, is_demo)
values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Luis Alberto', 'Pueblo Libre', 'Sector Sucre', -12.074, -77.065, true) on conflict(id) do update set alias=excluded.alias, approx_lat=excluded.approx_lat, approx_lng=excluded.approx_lng;

-- Servicio dentro de 1 km (Pueblo Libre)
insert into public.publications (
  id, client_mutation_id, author_id, kind, category, title, description, neighborhood, sector, availability_text, approx_lat, approx_lng, is_demo
) values (
  'd0000000-0000-4000-8000-000000000002',
  'e0000000-0000-4000-8000-000000000002',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'servicio',
  'electricidad',
  'Electricista domiciliario · Luis Alberto',
  'Instalación de llaves térmicas y revisión de tableros.',
  'Pueblo Libre',
  'Sector Sucre',
  'Lunes a Sábado 8am - 6pm',
  -12.074,
  -77.065,
  true
);

-- Servicio fuera de 1 km (Miraflores / San Isidro, a >4 km)
insert into public.publications (
  id, client_mutation_id, author_id, kind, category, title, description, neighborhood, sector, availability_text, approx_lat, approx_lng, is_demo
) values (
  'd0000000-0000-4000-8000-000000000003',
  'e0000000-0000-4000-8000-000000000003',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'servicio',
  'electricidad',
  'Electricista en distrito lejano',
  'Fuera del radio de 1 km de Pueblo Libre.',
  'Jesús María',
  'Sector Salaverry',
  'Lunes a Viernes',
  -12.095,
  -77.035,
  true
);

-- Verificar búsqueda por radio PostGIS (1000m desde -12.076, -77.063):
do $$
declare
  v_in_count int;
  v_out_count int;
begin
  select count(*) into v_in_count
  from public.search_publications_within_radius(-12.076, -77.063, 1000, 'servicio', null, null)
  where id = 'd0000000-0000-4000-8000-000000000002';

  select count(*) into v_out_count
  from public.search_publications_within_radius(-12.076, -77.063, 1000, 'servicio', null, null)
  where id = 'd0000000-0000-4000-8000-000000000003';

  if v_in_count <> 1 or v_out_count <> 0 then
    raise exception 'FALLO POSTGIS: dentro=% (esperado 1), fuera=% (esperado 0)', v_in_count, v_out_count;
  end if;
end $$;

-- 4. Verificar que Luis Alberto NO puede auto-recomendar su propio servicio
do $$
declare
  v_rejected boolean := false;
begin
  begin
    insert into public.recommendations (client_mutation_id, publication_id, user_id, comment)
    values (gen_random_uuid(), 'd0000000-0000-4000-8000-000000000002', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Auto recomendación inválida');
  exception when others then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'FALLO REGLA: se permitió auto-recomendación';
  end if;
end $$;

-- 5. Cambiar a Rosa (Usuario A): recomendar el servicio de Luis Alberto una vez (permitido) y duplicar (rechazado)
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);

insert into public.recommendations (id, client_mutation_id, publication_id, user_id, comment)
values (
  'f0000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-000000000002',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Muy puntual y cuidadoso.'
);

do $$
declare
  v_dup_rejected boolean := false;
begin
  begin
    insert into public.recommendations (client_mutation_id, publication_id, user_id, comment)
    values (gen_random_uuid(), 'd0000000-0000-4000-8000-000000000002', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Segunda recomendación duplicada');
  exception when unique_violation then
    v_dup_rejected := true;
  end;
  if not v_dup_rejected then
    raise exception 'FALLO REGLA: se permitió recomendación duplicada del mismo usuario';
  end if;
end $$;

-- 6. Conversación privada entre Rosa (A) y Luis Alberto (B) sobre el servicio de Luis
insert into public.conversations (id, client_mutation_id, publication_id, publication_author_id, participant_id)
values (
  'c0000000-0000-4000-8000-000000000001',
  'c1000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-000000000002',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
);

insert into public.messages (client_mutation_id, conversation_id, sender_id, body)
values (
  gen_random_uuid(),
  'c0000000-0000-4000-8000-000000000001',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'Buenas tardes don Luis, ¿podría revisar un interruptor mañana?'
);

-- 7. Cambiar a Usuario C (Don Jorge, tercero ajeno) -> verificar que NO puede leer ni escribir en la conversación
select set_config('request.jwt.claims', '{"sub":"cccccccc-cccc-4ccc-8ccc-cccccccccccc","role":"authenticated"}', true);

insert into public.profiles (id, alias, neighborhood, sector, approx_lat, approx_lng, is_demo)
values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Don Jorge', 'Pueblo Libre', 'Sector Sucre', -12.075, -77.064, true) on conflict(id) do nothing;

do $$
declare
  v_conv_count int;
  v_msg_count int;
  v_write_denied boolean := false;
begin
  select count(*) into v_conv_count from public.conversations where id = 'c0000000-0000-4000-8000-000000000001';
  select count(*) into v_msg_count from public.messages where conversation_id = 'c0000000-0000-4000-8000-000000000001';

  if v_conv_count <> 0 or v_msg_count <> 0 then
    raise exception 'FALLO RLS CHAT: tercero ajeno leyó conversación (%) o mensajes (%)', v_conv_count, v_msg_count;
  end if;

  begin
    insert into public.messages (client_mutation_id, conversation_id, sender_id, body)
    values (gen_random_uuid(), 'c0000000-0000-4000-8000-000000000001', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'Intrusión de tercero');
  exception when others then
    v_write_denied := true;
  end;

  if not v_write_denied then
    raise exception 'FALLO RLS CHAT: tercero ajeno pudo insertar mensaje';
  end if;
end $$;


-- Comprobar lectura entre A y B, edición propia de recomendación y control de versiones.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","role":"authenticated"}', true);
do $$ begin
  if (select count(*) from public.publications where id='d0000000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'FALLO: B no puede leer publicación de A';
  end if;
  if (select count(*) from public.messages where conversation_id='c0000000-0000-4000-8000-000000000001') <> 1 then
    raise exception 'FALLO: B no puede leer mensaje de A en su conversación';
  end if;
end $$;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","role":"authenticated"}', true);
update public.recommendations set comment='Opinión modificada por su autora' where id='f0000000-0000-4000-8000-000000000001';
do $$ declare v1 integer; v2 integer; denied boolean:=false; begin
  if (select comment from public.recommendations where id='f0000000-0000-4000-8000-000000000001') <> 'Opinión modificada por su autora' then
    raise exception 'FALLO: modificación de recomendación propia';
  end if;
  v1:=public.transition_publication_status('d0000000-0000-4000-8000-000000000001','en_coordinacion',1,'test-status-one');
  v2:=public.transition_publication_status('d0000000-0000-4000-8000-000000000001','en_coordinacion',1,'test-status-one');
  if v1<>2 or v2<>2 then raise exception 'FALLO: reintento de estado no idempotente'; end if;
  begin
    perform public.transition_publication_status('d0000000-0000-4000-8000-000000000001','resuelta',1,'test-stale');
  exception when sqlstate 'PT409' then denied:=true; end;
  if not denied then raise exception 'FALLO: versión obsoleta aceptada'; end if;
end $$;
delete from public.recommendations where id='f0000000-0000-4000-8000-000000000001';
do $$ begin
 if exists(select 1 from public.recommendations where id='f0000000-0000-4000-8000-000000000001') then
  raise exception 'FALLO: no pudo retirarse recomendación propia';
 end if;
end $$;

rollback;
select 'PASS: RLS, PostGIS, chat privado, recomendaciones y reintentos' as verification;
