begin;

select set_config('app.test.guest_report', jsonb_build_object(
  'id', gen_random_uuid(),
  'client_mutation_id', gen_random_uuid(),
  'kind', 'emergencia_solicitud',
  'category', 'general',
  'title', 'Árbol caído',
  'description', 'El árbol bloquea el paso.',
  'neighborhood', 'Pueblo Libre',
  'sector', 'Sector San Martín',
  'district_ubigeo', '150121',
  'approx_lat', -12.07641,
  'approx_lng', -77.06323
)::text, true);

set local role anon;
do $$
declare
  report jsonb := current_setting('app.test.guest_report')::jsonb;
begin
  if public.submit_guest_emergency(report) is distinct from 1
    or public.submit_guest_emergency(report) is distinct from 1 then
    raise exception 'El reporte de invitado debe confirmarse sin duplicarse';
  end if;

  begin
    perform public.submit_guest_emergency(report || '{"kind":"servicio"}');
    raise exception 'El RPC aceptó un servicio' using errcode = 'XX000';
  exception when raise_exception then
    null;
  end;

  begin
    perform 1 from public.publications limit 1;
    raise exception 'El invitado puede leer publicaciones';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
do $$
declare
  report jsonb := current_setting('app.test.guest_report')::jsonb;
  report_id uuid := (report->>'id')::uuid;
begin
  if public.submit_guest_emergency(report) is distinct from 1 then
    raise exception 'El invitado debe poder reintentar tras iniciar sesión';
  end if;
  if not exists (
    select 1 from public.neighborhood_feed('150121', null, null, 30)
    where publication->>'id' = report_id::text
      and publication->>'priority' = 'emergencia'
      and publication->>'author_id' is null
  ) then
    raise exception 'El reporte no aparece en el barrio como emergencia sin autor';
  end if;
  if not exists (
    select 1 from public.search_publications_by_location(
      -12.076, -77.063, 1000, '150121', 'emergencia_solicitud', null, null
    )
    where publication->>'id' = report_id::text
      and (publication->>'approx_lat')::double precision = -12.076
      and (publication->>'approx_lng')::double precision = -77.063
  ) then
    raise exception 'El reporte no aparece en el mapa con coordenadas aproximadas';
  end if;

  begin
    perform public.mutate_publication(report_id, 1, 'delete-guest', true, '{}');
    raise exception 'Otra cuenta pudo eliminar el reporte';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;

reset role;
rollback;
