begin;

alter table public.publications
  alter column author_id drop not null,
  add constraint publications_guest_emergency_only
    check (author_id is not null or (
      kind = 'emergencia_solicitud' and priority = 'emergencia'
    ));

-- Protege los reportes sin autor también desde los RPC de edición.
create function app_private.protect_guest_emergency()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.author_id is distinct from old.author_id
    or (old.author_id is null and auth.uid() is not null) then
    raise exception 'Solo el autor puede cambiar su publicación'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function app_private.protect_guest_emergency()
  from public, anon, authenticated;

create trigger before_guest_emergency_update
  before update on public.publications
  for each row execute function app_private.protect_guest_emergency();

create function public.submit_guest_emergency(p_report jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  report_id uuid := (p_report->>'id')::uuid;
  mutation_id uuid := (p_report->>'client_mutation_id')::uuid;
  report_description text := trim(p_report->>'description');
  saved_version integer;
begin
  if p_report->>'kind' is distinct from 'emergencia_solicitud'
    or coalesce(length(report_description), 0) not between 1 and 1000 then
    raise exception 'Completa la descripción del reporte de emergencia';
  end if;

  insert into public.publications (
    id, client_mutation_id, kind, category, title, description,
    neighborhood, sector, district_ubigeo, availability_text,
    priority, approx_lat, approx_lng
  ) values (
    report_id, mutation_id, 'emergencia_solicitud', p_report->>'category',
    p_report->>'title', report_description, p_report->>'neighborhood',
    p_report->>'sector', p_report->>'district_ubigeo',
    coalesce(p_report->>'availability_text', ''), 'emergencia',
    (p_report->>'approx_lat')::double precision,
    (p_report->>'approx_lng')::double precision
  )
  on conflict (client_mutation_id) do nothing
  returning version into saved_version;

  if not found then
    select version into saved_version from public.publications
    where id = report_id and client_mutation_id = mutation_id
      and author_id is null;
    if not found then
      raise exception 'El identificador ya pertenece a otra publicación';
    end if;
  end if;
  return saved_version;
end;
$$;

revoke all on function public.submit_guest_emergency(jsonb) from public;
-- El invitado puede iniciar sesión antes de que se reintente su reporte.
grant execute on function public.submit_guest_emergency(jsonb)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
