-- Catalog security checks (spec 03 §9.1; T-TEN-05, T-TEN-06, T-TEN-07, T-AUD-02 grants).
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

select is_empty($$
  select n.nspname || '.' || c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind in ('r', 'p') and n.nspname in ('public', 'graphql_public') and not c.relrowsecurity
$$, 'T-TEN-05: every table in an exposed schema has RLS enabled');

select is_empty($$
  select table_name || ':' || privilege_type
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
$$, 'T-TEN-05: anon and PUBLIC hold no table privileges in public');

select is_empty($$
  select table_name || ':' || privilege_type
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee = 'authenticated' and privilege_type in ('DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
$$, 'T-TEN-05: authenticated holds no DELETE/TRUNCATE/REFERENCES/TRIGGER privileges in public');

select is_empty($$
  select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'graphql_public') and p.prosecdef
$$, 'T-TEN-06: no SECURITY DEFINER function exists in an exposed schema');

select is_empty($$
  select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prolang <> (select oid from pg_language where lanname = 'internal')
    and not coalesce(p.proconfig @> array['search_path=""'], false)
$$, 'T-TEN-06: every function in public and private pins search_path to empty');

select is_empty($$
  select p.oid::regprocedure::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and has_function_privilege('anon', p.oid, 'execute')
$$, 'T-TEN-06: anon (and PUBLIC) cannot execute any function in public or private');

select is_empty($$
  select n.nspname || '.' || c.relname
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where c.relkind = 'v' and n.nspname in ('public', 'graphql_public')
    and not coalesce(c.reloptions @> array['security_invoker=true'], false)
$$, 'T-TEN-07: every view in an exposed schema uses security_invoker');

select ok(
  not has_table_privilege('service_role', 'public.audit_events', 'insert')
  and not has_table_privilege('service_role', 'public.audit_events', 'update')
  and not has_table_privilege('service_role', 'public.audit_events', 'delete')
  and not has_table_privilege('authenticated', 'public.audit_events', 'update')
  and not has_table_privilege('authenticated', 'public.audit_events', 'delete'),
  'T-AUD-02: no role holds INSERT/UPDATE/DELETE on audit_events (writes only via definer functions)');

select ok(
  not has_column_privilege('authenticated', 'public.invitations', 'token_hash', 'select'),
  'T-AUTH-08: invitation token hashes are never selectable by end users');

select * from finish();
rollback;
