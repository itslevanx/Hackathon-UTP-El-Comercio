select 'app_tables' as check_name, count(*)::text as result
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relname in
('profiles','publications','recommendations','help_offers','conversations','messages','community_resources','support_groups')
union all
select 'app_tables_without_rls', count(*)::text
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and not c.relrowsecurity and c.relname in
('profiles','publications','recommendations','help_offers','conversations','messages','community_resources','support_groups')
union all select 'postgis_schema',extnamespace::regnamespace::text from pg_extension where extname='postgis'
union all select 'postgis_version',extversion from pg_extension where extname='postgis'
union all select 'realtime_messages',count(*)::text from pg_publication_tables
where pubname='supabase_realtime' and schemaname='public' and tablename='messages'
union all select 'test_users_remaining',count(*)::text from auth.users
where id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','cccccccc-cccc-4ccc-8ccc-cccccccccccc')
union all select 'anonymous_chat_read',has_table_privilege('anon','public.messages','SELECT')::text;
