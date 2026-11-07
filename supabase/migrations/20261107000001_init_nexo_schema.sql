begin;

-- =============================================================================
-- NEXO (nombre provisional) — Esquema inicial PostgreSQL + PostGIS + RLS
-- Escenario demo: Pueblo Libre, Lima, Perú (arquitectura abierta a cualquier distrito)
-- =============================================================================

create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

-- 1. Extensiones requeridas
create extension if not exists pgcrypto;
create extension if not exists postgis with schema extensions;

-- 2. Función utilitaria para redondear coordenadas públicas (~110m de precisión)
-- Garantiza que nunca se almacene ni exponga la ubicación domiciliaria exacta.
create or replace function public.round_public_coord(val double precision)
returns double precision
language sql
immutable
security invoker
set search_path = public, extensions
as $$
  select case
    when val is null then null
    else round(val::numeric, 3)::double precision
  end;
$$;

-- 3. Tabla de perfiles públicos mínimos (profiles)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  alias text not null check (char_length(trim(alias)) between 2 and 60),
  neighborhood text not null default 'Pueblo Libre' check (char_length(trim(neighborhood)) between 2 and 80),
  sector text not null default 'Sector San Martín' check (char_length(trim(sector)) between 2 and 100),
  bio text not null default '' check (char_length(bio) <= 280),
  approx_lat double precision check (approx_lat is null or (approx_lat between -90 and 90)),
  approx_lng double precision check (approx_lng is null or (approx_lng between -180 and 180)),
  location extensions.geography(Point, 4326),
  use_gps_approx boolean not null default false,
  share_resources_consent boolean not null default false,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_neighborhood on public.profiles(neighborhood, sector);
create index if not exists idx_profiles_location on public.profiles using gist(location);

create or replace function public.trg_profiles_sanitize()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  if tg_op = 'UPDATE' and new.id <> old.id then
    raise exception 'No se permite reasignar el identificador del perfil';
  end if;
  new.alias := trim(new.alias);
  new.neighborhood := trim(new.neighborhood);
  new.sector := trim(new.sector);
  new.approx_lat := public.round_public_coord(new.approx_lat);
  new.approx_lng := public.round_public_coord(new.approx_lng);
  if new.approx_lat is not null and new.approx_lng is not null then
    new.location := ST_SetSRID(ST_MakePoint(new.approx_lng, new.approx_lat), 4326)::geography;
  else
    new.location := null;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_profiles_sanitize on public.profiles;
create trigger before_profiles_sanitize
before insert or update on public.profiles
for each row execute function public.trg_profiles_sanitize();

-- 4. Tabla de publicaciones (servicios, favores, préstamos, donaciones, habilidades y emergencias)
create table if not exists public.publications (
  id uuid primary key default gen_random_uuid(),
  client_mutation_id uuid not null unique,
  author_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (
    kind in (
      'servicio',
      'favor_solicitud',
      'favor_oferta',
      'prestamo',
      'donacion',
      'habilidad',
      'emergencia_solicitud',
      'emergencia_oferta'
    )
  ),
  category text not null default 'general' check (char_length(trim(category)) between 2 and 50),
  title text not null check (char_length(trim(title)) between 3 and 120),
  description text not null default '' check (char_length(description) <= 1000),
  neighborhood text not null default 'Pueblo Libre' check (char_length(trim(neighborhood)) between 2 and 80),
  sector text not null default 'Sector San Martín' check (char_length(trim(sector)) between 2 and 100),
  availability_text text not null default '' check (char_length(availability_text) <= 200),
  priority text not null default 'normal' check (priority in ('normal', 'urgente', 'emergencia')),
  status text not null default 'abierta' check (status in ('abierta', 'en_coordinacion', 'resuelta', 'cancelada')),
  approx_lat double precision not null default -12.076 check (approx_lat between -90 and 90),
  approx_lng double precision not null default -77.063 check (approx_lng between -180 and 180),
  location extensions.geography(Point, 4326),
  share_resource_consent boolean not null default false,
  recommendation_count integer not null default 0 check (recommendation_count >= 0),
  version integer not null default 1 check (version >= 1),
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_publications_kind_status on public.publications(kind, status, neighborhood);
create index if not exists idx_publications_author on public.publications(author_id, created_at desc);
create index if not exists idx_publications_category on public.publications(category);
create index if not exists idx_publications_location on public.publications using gist(location);

create or replace function public.trg_publications_validate()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  if tg_op = 'UPDATE' then
    if new.author_id <> old.author_id then
      raise exception 'No se permite reasignar el autor de una publicación';
    end if;
    if new.client_mutation_id <> old.client_mutation_id then
      raise exception 'No se permite modificar el identificador de idempotencia';
    end if;
    if old.status = 'cancelada' and new.status <> 'cancelada' then
      raise exception 'Una publicación cancelada no puede reabrirse';
    end if;
    if old.status = 'resuelta' and new.status not in ('resuelta', 'abierta') then
      raise exception 'Transición desde resuelta no permitida';
    end if;
    new.version := old.version + 1;
  end if;

  if new.kind = 'emergencia_oferta' and new.share_resource_consent is not true then
    raise exception 'Compartir un recurso en emergencia requiere decisión explícita del usuario';
  end if;

  new.title := trim(new.title);
  new.category := trim(new.category);
  new.neighborhood := trim(new.neighborhood);
  new.sector := trim(new.sector);
  new.approx_lat := public.round_public_coord(new.approx_lat);
  new.approx_lng := public.round_public_coord(new.approx_lng);
  new.location := ST_SetSRID(ST_MakePoint(new.approx_lng, new.approx_lat), 4326)::geography;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_publications_validate on public.publications;
create trigger before_publications_validate
before insert or update on public.publications
for each row execute function public.trg_publications_validate();

-- 5. Tabla de recomendaciones vecinales (una por usuario y servicio, sin auto-recomendación)
create table if not exists public.recommendations (
  id uuid primary key default gen_random_uuid(),
  client_mutation_id uuid not null unique,
  publication_id uuid not null references public.publications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  comment text not null default '' check (char_length(comment) <= 400),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (publication_id, user_id)
);

create index if not exists idx_recommendations_publication on public.recommendations(publication_id);
create index if not exists idx_recommendations_user on public.recommendations(user_id);

create or replace function app_private.trg_recommendations_validate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_author_id uuid;
  v_kind text;
begin
  if tg_op = 'DELETE' then
    update public.publications
    set recommendation_count = greatest(0, (
      select count(*)::int from public.recommendations where publication_id = old.publication_id and id <> old.id
    ))
    where id = old.publication_id;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id or new.publication_id <> old.publication_id then
      raise exception 'No se permite reasignar autor o servicio de una recomendación';
    end if;
  end if;

  select author_id, kind into v_author_id, v_kind
  from public.publications
  where id = new.publication_id;

  if v_author_id is null then
    raise exception 'La publicación indicada no existe';
  end if;

  if v_kind <> 'servicio' then
    raise exception 'Solo se pueden recomendar publicaciones del directorio de servicios';
  end if;

  if v_author_id = new.user_id then
    raise exception 'No puedes recomendar tu propio servicio';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

create or replace function app_private.trg_recommendations_recount()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pub_id uuid;
begin
  v_pub_id := coalesce(new.publication_id, old.publication_id);
  update public.publications
  set recommendation_count = (
    select count(*)::int from public.recommendations where publication_id = v_pub_id
  )
  where id = v_pub_id;
  return null;
end;
$$;

drop trigger if exists before_recommendations_validate on public.recommendations;
create trigger before_recommendations_validate
before insert or update on public.recommendations
for each row execute function app_private.trg_recommendations_validate();

drop trigger if exists after_recommendations_recount on public.recommendations;
create trigger after_recommendations_recount
after insert or update or delete on public.recommendations
for each row execute function app_private.trg_recommendations_recount();

-- 6. Tabla de ofertas de ayuda solidaria (help_offers)
create table if not exists public.help_offers (
  id uuid primary key default gen_random_uuid(),
  client_mutation_id uuid not null unique,
  publication_id uuid not null references public.publications(id) on delete cascade,
  helper_id uuid not null references public.profiles(id) on delete cascade,
  note text not null default '' check (char_length(note) <= 500),
  resource_shared text not null default '' check (char_length(resource_shared) <= 200),
  explicit_share_consent boolean not null default false,
  status text not null default 'enviada' check (status in ('enviada', 'aceptada', 'retirada', 'completada')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (publication_id, helper_id)
);

create index if not exists idx_help_offers_publication on public.help_offers(publication_id);
create index if not exists idx_help_offers_helper on public.help_offers(helper_id);

create or replace function public.trg_help_offers_validate()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_author_id uuid;
  v_pub_status text;
begin
  select author_id, status into v_author_id, v_pub_status
  from public.publications
  where id = new.publication_id;

  if v_author_id is null then
    raise exception 'La solicitud asociada no existe';
  end if;

  if tg_op = 'INSERT' then
    if v_author_id = new.helper_id then
      raise exception 'No puedes enviar una oferta de ayuda a tu propia publicación';
    end if;
    if v_pub_status in ('resuelta', 'cancelada') then
      raise exception 'La solicitud ya no admite nuevas ofertas';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    if new.helper_id <> old.helper_id or new.publication_id <> old.publication_id then
      raise exception 'No se permite reasignar el autor ni la publicación de la oferta';
    end if;
    if auth.uid() is not null and auth.uid() <> old.helper_id and auth.uid() <> v_author_id then
      raise exception 'No autorizado para modificar esta oferta de ayuda';
    end if;
    if auth.uid() = old.helper_id and new.status not in ('enviada', 'retirada') and new.status <> old.status then
      raise exception 'Quien ofrece ayuda solo puede actualizar su nota o retirar su oferta';
    end if;
  end if;

  if char_length(trim(new.resource_shared)) > 0 and new.explicit_share_consent is not true then
    raise exception 'Compartir un recurso requiere consentimiento explícito del usuario';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_help_offers_validate on public.help_offers;
create trigger before_help_offers_validate
before insert or update on public.help_offers
for each row execute function public.trg_help_offers_validate();

-- 7. Tabla de conversaciones privadas contextuales a una publicación/solicitud
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  client_mutation_id uuid not null unique,
  publication_id uuid not null references public.publications(id) on delete cascade,
  publication_author_id uuid not null references public.profiles(id) on delete cascade,
  participant_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (publication_author_id <> participant_id),
  unique (publication_id, participant_id)
);

create index if not exists idx_conversations_author on public.conversations(publication_author_id, updated_at desc);
create index if not exists idx_conversations_participant on public.conversations(participant_id, updated_at desc);

create or replace function public.trg_conversations_validate()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_real_author uuid;
begin
  if tg_op = 'UPDATE' then
    if new.publication_id <> old.publication_id
       or new.publication_author_id <> old.publication_author_id
       or new.participant_id <> old.participant_id then
      raise exception 'No se permite reasignar participantes ni publicación de una conversación';
    end if;
  end if;

  select author_id into v_real_author
  from public.publications
  where id = new.publication_id;

  if v_real_author is null then
    raise exception 'La publicación asociada a la conversación no existe';
  end if;

  if v_real_author <> new.publication_author_id then
    raise exception 'El autor de la publicación no coincide con publication_author_id';
  end if;

  if new.participant_id = v_real_author then
    raise exception 'No se puede iniciar una conversación privada consigo mismo';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_conversations_validate on public.conversations;
create trigger before_conversations_validate
before insert or update on public.conversations
for each row execute function public.trg_conversations_validate();

-- 8. Tabla de mensajes privados entre los dos participantes
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  client_mutation_id uuid not null unique,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists idx_messages_conversation on public.messages(conversation_id, created_at asc);

create or replace function public.trg_messages_validate()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions
as $$
declare
  v_author uuid;
  v_participant uuid;
begin
  if tg_op = 'UPDATE' then
    raise exception 'Los mensajes enviados no permiten reasignación ni edición';
  end if;

  select publication_author_id, participant_id
  into v_author, v_participant
  from public.conversations
  where id = new.conversation_id;

  if v_author is null then
    raise exception 'La conversación no existe o no tienes permiso para acceder a ella';
  end if;

  if new.sender_id <> v_author and new.sender_id <> v_participant then
    raise exception 'El remitente no pertenece a esta conversación';
  end if;

  if auth.uid() is not null and new.sender_id <> auth.uid() then
    raise exception 'sender_id debe coincidir con auth.uid()';
  end if;

  new.body := trim(new.body);

  update public.conversations
  set updated_at = now()
  where id = new.conversation_id;

  return new;
end;
$$;

drop trigger if exists before_messages_validate on public.messages;
create trigger before_messages_validate
before insert or update on public.messages
for each row execute function public.trg_messages_validate();

-- 9. Tablas de recursos comunitarios y grupos de apoyo vecinal
create table if not exists public.community_resources (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('punto_encuentro', 'recurso_comunitario', 'grupo_apoyo', 'directorio_oficial')),
  title text not null check (char_length(trim(title)) between 3 and 140),
  description text not null check (char_length(description) <= 1000),
  neighborhood text not null default 'Pueblo Libre',
  sector text not null default 'Sector Plaza Bolívar',
  approx_lat double precision not null check (approx_lat between -90 and 90),
  approx_lng double precision not null check (approx_lng between -180 and 180),
  location extensions.geography(Point, 4326),
  contact_info text not null default '',
  source_label text not null default 'Referencia comunitaria · sin confirmar en terreno',
  is_demo boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists idx_community_resources_neighborhood on public.community_resources(neighborhood, kind);
create index if not exists idx_community_resources_location on public.community_resources using gist(location);

create or replace function public.trg_community_resources_sanitize()
returns trigger
language plpgsql
security invoker
set search_path = public, extensions
as $$
begin
  new.approx_lat := public.round_public_coord(new.approx_lat);
  new.approx_lng := public.round_public_coord(new.approx_lng);
  new.location := ST_SetSRID(ST_MakePoint(new.approx_lng, new.approx_lat), 4326)::geography;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_community_resources_sanitize on public.community_resources;
create trigger before_community_resources_sanitize
before insert or update on public.community_resources
for each row execute function public.trg_community_resources_sanitize();

create table if not exists public.support_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 3 and 120),
  description text not null check (char_length(description) <= 600),
  neighborhood text not null default 'Pueblo Libre',
  sector text not null default 'Sector San Martín',
  coordinator_label text not null default 'Coordinación vecinal voluntaria',
  channel_note text not null default 'Grupo barrial informativo · No sustituye centrales de emergencia',
  is_demo boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists idx_support_groups_neighborhood on public.support_groups(neighborhood, sector);

-- =============================================================================
-- 10. Funciones RPC espaciales con PostGIS (privacidad preservada)
-- =============================================================================
create or replace function public.search_publications_within_radius(
  p_lat double precision,
  p_lng double precision,
  p_radius_meters double precision default 1000,
  p_kind text default null,
  p_category text default null,
  p_search text default null
)
returns table (
  id uuid,
  client_mutation_id uuid,
  author_id uuid,
  author_alias text,
  kind text,
  category text,
  title text,
  description text,
  neighborhood text,
  sector text,
  availability_text text,
  priority text,
  status text,
  public_lat double precision,
  public_lng double precision,
  approx_distance_m integer,
  recommendation_count integer,
  is_demo boolean,
  version integer,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with origin as (
    select ST_SetSRID(
      ST_MakePoint(public.round_public_coord(p_lng), public.round_public_coord(p_lat)),
      4326
    )::geography as pt
  )
  select
    p.id,
    p.client_mutation_id,
    p.author_id,
    coalesce(pr.alias, 'Vecino') as author_alias,
    p.kind,
    p.category,
    p.title,
    p.description,
    p.neighborhood,
    p.sector,
    p.availability_text,
    p.priority,
    p.status,
    public.round_public_coord(p.approx_lat) as public_lat,
    public.round_public_coord(p.approx_lng) as public_lng,
    greatest(50, (round(ST_Distance(p.location, o.pt) / 50.0) * 50)::int) as approx_distance_m,
    p.recommendation_count,
    p.is_demo,
    p.version,
    p.created_at,
    p.updated_at
  from public.publications p
  cross join origin o
  left join public.profiles pr on pr.id = p.author_id
  where ST_DWithin(p.location, o.pt, greatest(100, least(p_radius_meters, 20000)))
    and (p_kind is null or p.kind = p_kind)
    and (p_category is null or p_category = 'todos' or p.category = p_category)
    and (
      p_search is null
      or trim(p_search) = ''
      or p.title ilike '%' || trim(p_search) || '%'
      or p.description ilike '%' || trim(p_search) || '%'
      or p.sector ilike '%' || trim(p_search) || '%'
    )
  order by
    case when p.priority = 'emergencia' then 0 when p.priority = 'urgente' then 1 else 2 end,
    ST_Distance(p.location, o.pt) asc,
    p.created_at desc;
$$;

create or replace function public.search_resources_within_radius(
  p_lat double precision,
  p_lng double precision,
  p_radius_meters double precision default 2000,
  p_kind text default null
)
returns table (
  id uuid,
  kind text,
  title text,
  description text,
  neighborhood text,
  sector text,
  public_lat double precision,
  public_lng double precision,
  approx_distance_m integer,
  contact_info text,
  source_label text,
  is_demo boolean,
  updated_at timestamptz
)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with origin as (
    select ST_SetSRID(
      ST_MakePoint(public.round_public_coord(p_lng), public.round_public_coord(p_lat)),
      4326
    )::geography as pt
  )
  select
    r.id,
    r.kind,
    r.title,
    r.description,
    r.neighborhood,
    r.sector,
    public.round_public_coord(r.approx_lat) as public_lat,
    public.round_public_coord(r.approx_lng) as public_lng,
    greatest(50, (round(ST_Distance(r.location, o.pt) / 50.0) * 50)::int) as approx_distance_m,
    r.contact_info,
    r.source_label,
    r.is_demo,
    r.updated_at
  from public.community_resources r
  cross join origin o
  where ST_DWithin(r.location, o.pt, greatest(100, least(p_radius_meters, 20000)))
    and (p_kind is null or r.kind = p_kind)
  order by ST_Distance(r.location, o.pt) asc;
$$;

-- =============================================================================
-- 11. Row Level Security (RLS) y privilegios explícitos de API
-- =============================================================================
alter table public.profiles enable row level security;
alter table public.publications enable row level security;
alter table public.recommendations enable row level security;
alter table public.help_offers enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.community_resources enable row level security;
alter table public.support_groups enable row level security;

drop policy if exists profiles_select_authenticated on public.profiles;
create policy profiles_select_authenticated
  on public.profiles for select to authenticated using (true);

drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
  on public.profiles for insert to authenticated with check (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists publications_select_authenticated on public.publications;
create policy publications_select_authenticated
  on public.publications for select to authenticated using (true);

drop policy if exists publications_insert_own on public.publications;
create policy publications_insert_own
  on public.publications for insert to authenticated with check (author_id = auth.uid());

drop policy if exists publications_update_own on public.publications;
create policy publications_update_own
  on public.publications for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());

drop policy if exists publications_delete_own on public.publications;
create policy publications_delete_own
  on public.publications for delete to authenticated using (author_id = auth.uid());

drop policy if exists recommendations_select_authenticated on public.recommendations;
create policy recommendations_select_authenticated
  on public.recommendations for select to authenticated using (true);

drop policy if exists recommendations_insert_own on public.recommendations;
create policy recommendations_insert_own
  on public.recommendations for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.publications p
      where p.id = publication_id
        and p.kind = 'servicio'
        and p.author_id <> auth.uid()
    )
  );

drop policy if exists recommendations_update_own on public.recommendations;
create policy recommendations_update_own
  on public.recommendations for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists recommendations_delete_own on public.recommendations;
create policy recommendations_delete_own
  on public.recommendations for delete to authenticated using (user_id = auth.uid());

drop policy if exists help_offers_select_involved on public.help_offers;
create policy help_offers_select_involved
  on public.help_offers for select to authenticated
  using (
    helper_id = auth.uid()
    or exists (
      select 1 from public.publications p
      where p.id = help_offers.publication_id and p.author_id = auth.uid()
    )
  );

drop policy if exists help_offers_insert_own on public.help_offers;
create policy help_offers_insert_own
  on public.help_offers for insert to authenticated
  with check (
    helper_id = auth.uid()
    and exists (
      select 1 from public.publications p
      where p.id = publication_id
        and p.author_id <> auth.uid()
        and p.status in ('abierta', 'en_coordinacion')
    )
  );

drop policy if exists help_offers_update_involved on public.help_offers;
create policy help_offers_update_involved
  on public.help_offers for update to authenticated
  using (
    helper_id = auth.uid()
    or exists (
      select 1 from public.publications p
      where p.id = help_offers.publication_id and p.author_id = auth.uid()
    )
  )
  with check (
    helper_id = auth.uid()
    or exists (
      select 1 from public.publications p
      where p.id = help_offers.publication_id and p.author_id = auth.uid()
    )
  );

drop policy if exists conversations_select_participants on public.conversations;
create policy conversations_select_participants
  on public.conversations for select to authenticated
  using (auth.uid() = publication_author_id or auth.uid() = participant_id);

drop policy if exists conversations_insert_participants on public.conversations;
create policy conversations_insert_participants
  on public.conversations for insert to authenticated
  with check (
    (auth.uid() = participant_id or auth.uid() = publication_author_id)
    and publication_author_id <> participant_id
  );

drop policy if exists conversations_update_participants on public.conversations;
create policy conversations_update_participants
  on public.conversations for update to authenticated
  using (auth.uid() = publication_author_id or auth.uid() = participant_id)
  with check (auth.uid() = publication_author_id or auth.uid() = participant_id);

drop policy if exists messages_select_participants on public.messages;
create policy messages_select_participants
  on public.messages for select to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and (c.publication_author_id = auth.uid() or c.participant_id = auth.uid())
    )
  );

drop policy if exists messages_insert_participants on public.messages;
create policy messages_insert_participants
  on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.publication_author_id = auth.uid() or c.participant_id = auth.uid())
    )
  );

drop policy if exists community_resources_select_authenticated on public.community_resources;
create policy community_resources_select_authenticated
  on public.community_resources for select to authenticated using (true);

drop policy if exists support_groups_select_authenticated on public.support_groups;
create policy support_groups_select_authenticated
  on public.support_groups for select to authenticated using (true);

revoke all on public.profiles from anon;
revoke all on public.publications from anon;
revoke all on public.recommendations from anon;
revoke all on public.help_offers from anon;
revoke all on public.conversations from anon;
revoke all on public.messages from anon;
revoke all on public.community_resources from anon;
revoke all on public.support_groups from anon;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update, delete on public.publications to authenticated;
grant select, insert, update, delete on public.recommendations to authenticated;
grant select, insert, update on public.help_offers to authenticated;
grant select, insert, update on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;
grant select on public.community_resources to authenticated;
grant select on public.support_groups to authenticated;

revoke execute on function public.search_publications_within_radius(double precision, double precision, double precision, text, text, text) from public, anon;
grant execute on function public.search_publications_within_radius(double precision, double precision, double precision, text, text, text) to authenticated;
revoke execute on function public.search_resources_within_radius(double precision, double precision, double precision, text) from public, anon;
grant execute on function public.search_resources_within_radius(double precision, double precision, double precision, text) to authenticated;
grant execute on function public.round_public_coord(double precision) to authenticated;

-- Perfil creado de forma transaccional incluso cuando Auth exige verificar correo.
create or replace function app_private.create_user_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, alias, neighborhood, sector)
  values (new.id,
    left(coalesce(nullif(trim(new.raw_user_meta_data->>'alias'), ''), 'Vecino'),60),
    left(coalesce(nullif(trim(new.raw_user_meta_data->>'neighborhood'), ''), 'Pueblo Libre'),80),
    left(coalesce(nullif(trim(new.raw_user_meta_data->>'sector'), ''), 'Sector San Martín'),100))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function app_private.create_user_profile() from public, anon, authenticated;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function app_private.create_user_profile();

-- Registro privado de operaciones de estado para comparar versión y reconocer reintentos.
create table if not exists app_private.publication_state_operations (
  actor_id uuid not null references auth.users(id) on delete cascade,
  operation_id text not null,
  publication_id uuid not null references public.publications(id) on delete cascade,
  target_status text not null,
  resulting_version integer not null,
  primary key(actor_id, operation_id)
);
alter table app_private.publication_state_operations enable row level security;
revoke all on app_private.publication_state_operations from public, anon, authenticated;

create or replace function app_private.transition_publication_status(
  p_id uuid, p_status text, p_expected_version integer, p_operation_id text
) returns integer language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  publication public.publications%rowtype;
  receipt app_private.publication_state_operations%rowtype;
  updated_version integer;
begin
  if actor is null then raise exception 'Sesión requerida' using errcode = '42501'; end if;
  select * into publication from public.publications where id = p_id for update;
  if not found or publication.author_id <> actor then
    raise exception 'Solo el autor puede cambiar el estado' using errcode = '42501';
  end if;
  select * into receipt from app_private.publication_state_operations
    where actor_id = actor and operation_id = p_operation_id;
  if found then
    if receipt.publication_id <> p_id or receipt.target_status <> p_status then
      raise exception 'Identificador de operación reutilizado para otra acción' using errcode = 'PT409';
    end if;
    return receipt.resulting_version;
  end if;
  if publication.version <> p_expected_version then
    raise exception 'Conflicto de versión' using errcode = 'PT409';
  end if;
  update public.publications set status = p_status where id = p_id returning version into updated_version;
  insert into app_private.publication_state_operations values(actor, p_operation_id, p_id, p_status, updated_version);
  return updated_version;
end;
$$;
revoke all on function app_private.transition_publication_status(uuid,text,integer,text) from public, anon;
grant usage on schema app_private to authenticated;
grant execute on function app_private.transition_publication_status(uuid,text,integer,text) to authenticated;
create or replace function public.transition_publication_status(
  p_id uuid, p_status text, p_expected_version integer, p_operation_id text
) returns integer language sql security invoker set search_path = '' as $$
  select app_private.transition_publication_status(p_id,p_status,p_expected_version,p_operation_id);
$$;
revoke all on function public.transition_publication_status(uuid,text,integer,text) from public, anon;
grant execute on function public.transition_publication_status(uuid,text,integer,text) to authenticated;

-- Realtime usa las mismas políticas de lectura de mensajes que la API.
do $$ begin
  if exists(select 1 from pg_publication where pubname = 'supabase_realtime') and
    not exists(select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

commit;
