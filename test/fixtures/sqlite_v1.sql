-- SQLite schema version 1
CREATE TABLE IF NOT EXISTS profiles_local (
      id TEXT PRIMARY KEY,
      alias TEXT NOT NULL,
      neighborhood TEXT NOT NULL,
      sector TEXT NOT NULL,
      email TEXT NOT NULL DEFAULT '',
      bio TEXT NOT NULL DEFAULT '',
      approx_lat REAL NOT NULL DEFAULT -12.076,
      approx_lng REAL NOT NULL DEFAULT -77.063,
      use_gps_approx INTEGER NOT NULL DEFAULT 0,
      share_resources_consent INTEGER NOT NULL DEFAULT 0,
      is_demo INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    );
CREATE TABLE IF NOT EXISTS publications_local (
      id TEXT PRIMARY KEY,
      client_mutation_id TEXT NOT NULL UNIQUE,
      owner_user_id TEXT NOT NULL,
      author_id TEXT NOT NULL,
      author_alias TEXT NOT NULL,
      kind TEXT NOT NULL,
      category TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      neighborhood TEXT NOT NULL,
      sector TEXT NOT NULL,
      availability_text TEXT NOT NULL DEFAULT '',
      priority TEXT NOT NULL DEFAULT 'normal',
      status TEXT NOT NULL DEFAULT 'abierta',
      approx_lat REAL NOT NULL DEFAULT -12.076,
      approx_lng REAL NOT NULL DEFAULT -77.063,
      share_resource_consent INTEGER NOT NULL DEFAULT 0,
      recommendation_count INTEGER NOT NULL DEFAULT 0,
      sync_status TEXT NOT NULL DEFAULT 'confirmado',
      last_error TEXT NOT NULL DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      is_demo INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE IF NOT EXISTS recommendations_local (
      id TEXT PRIMARY KEY,
      client_mutation_id TEXT NOT NULL UNIQUE,
      owner_user_id TEXT NOT NULL,
      publication_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      user_alias TEXT NOT NULL,
      comment TEXT NOT NULL DEFAULT '',
      sync_status TEXT NOT NULL DEFAULT 'confirmado',
      last_error TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(publication_id, user_id)
    );
CREATE TABLE IF NOT EXISTS help_offers_local (
      id TEXT PRIMARY KEY,
      client_mutation_id TEXT NOT NULL UNIQUE,
      owner_user_id TEXT NOT NULL,
      publication_id TEXT NOT NULL,
      helper_id TEXT NOT NULL,
      helper_alias TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      resource_shared TEXT NOT NULL DEFAULT '',
      explicit_share_consent INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'enviada',
      sync_status TEXT NOT NULL DEFAULT 'confirmado',
      last_error TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(publication_id, helper_id)
    );
CREATE TABLE IF NOT EXISTS conversations_local (
      id TEXT PRIMARY KEY,
      client_mutation_id TEXT NOT NULL UNIQUE,
      owner_user_id TEXT NOT NULL,
      publication_id TEXT NOT NULL,
      publication_title TEXT NOT NULL,
      publication_author_id TEXT NOT NULL,
      publication_author_alias TEXT NOT NULL,
      participant_id TEXT NOT NULL,
      participant_alias TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'confirmado',
      updated_at TEXT NOT NULL,
      UNIQUE(publication_id, participant_id)
    );
CREATE TABLE IF NOT EXISTS messages_local (
      id TEXT PRIMARY KEY,
      client_mutation_id TEXT NOT NULL UNIQUE,
      owner_user_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      sender_alias TEXT NOT NULL,
      body TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'confirmado',
      created_at TEXT NOT NULL
    );
CREATE TABLE IF NOT EXISTS drafts_local (
      draft_key TEXT NOT NULL,
      owner_user_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'general',
      availability_text TEXT NOT NULL DEFAULT '',
      priority TEXT NOT NULL DEFAULT 'normal',
      updated_at TEXT NOT NULL,
      PRIMARY KEY (draft_key, owner_user_id)
    );
CREATE TABLE IF NOT EXISTS outbox_operations (
      operation_id TEXT PRIMARY KEY,
      owner_user_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      action TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'pendiente',
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT NOT NULL DEFAULT '',
      expected_version INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE IF NOT EXISTS community_resources_local (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      neighborhood TEXT NOT NULL,
      sector TEXT NOT NULL,
      approx_lat REAL NOT NULL,
      approx_lng REAL NOT NULL,
      contact_info TEXT NOT NULL,
      source_label TEXT NOT NULL,
      is_demo INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL
    );
CREATE TABLE IF NOT EXISTS support_groups_local (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL,
      neighborhood TEXT NOT NULL,
      sector TEXT NOT NULL,
      coordinator_label TEXT NOT NULL,
      channel_note TEXT NOT NULL,
      is_demo INTEGER NOT NULL DEFAULT 0
    );
CREATE TABLE IF NOT EXISTS cache_metadata (
      cache_key TEXT PRIMARY KEY,
      last_synced_at TEXT NOT NULL
    );
CREATE TABLE IF NOT EXISTS practice_progress_local (
      scenario_id TEXT PRIMARY KEY,
      completed_missions_json TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE INDEX IF NOT EXISTS idx_pub_local_kind ON publications_local(kind, status, neighborhood);
CREATE INDEX IF NOT EXISTS idx_pub_local_owner ON publications_local(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_outbox_owner ON outbox_operations(owner_user_id, sync_status);
