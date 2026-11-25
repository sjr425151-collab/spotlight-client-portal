-- WP-D18: package-scope version sealing (DEP-18 sealing amendment).
-- Decisions: DEP-18 (Owner, 2026-11-24/25: append-only, then sealed versions), OI-84(b), A2, A5,
-- the environment-isolation amendment. Authorization: AUTH-007 (Tier 2, active 2026-11-25).
-- Handoff: docs/R1-HANDOFFS.md §2.
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02). No merged migration is edited.
-- - Changes only the AUTH-007 objects: new private.billing_package_scope_versions, new
--   private.create_package_scope_version(text, text[], boolean), one insert-protection trigger
--   function (attached to the items and the headers), and private.current_package_scope(text)
--   (sealed versions only; same signature). No WP-B, WP-C, or Phase 2 object changes;
--   issue_order_summary is unchanged and keeps calling current_package_scope.
-- - No package content is added here (DEP-18: production content comes from the Owner;
--   local and CI fixtures come only from supabase/seed.sql, through the new function).
-- - Existing rows are the seed's labeled fixtures only. They are sealed as version 1 per package
--   where the classification allows fixtures; any non-fixture row stops the migration and
--   nothing changes.

-- ---------------------------------------------------------------------------
-- 1. Version headers: one sealed header per (package, version); append-only
-- ---------------------------------------------------------------------------
create table private.billing_package_scope_versions (
  package_key text not null references private.billing_packages (package_key),
  scope_version integer not null check (scope_version >= 1),
  item_count integer not null check (item_count between 1 and 50),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  is_test_fixture boolean not null,
  sealed_at timestamptz not null default now(),
  primary key (package_key, scope_version)
);
revoke all on table private.billing_package_scope_versions from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Insert protection for items and headers (the one new trigger function)
-- ---------------------------------------------------------------------------
-- A row is accepted only while private.create_package_scope_version is building exactly that
-- (package, version) in the current transaction, and never for a version that is already sealed.
-- The marker is transaction-local and cleared by the function before it returns. A fixture header
-- keeps the development/test allowlist (fixture items already have it through the existing
-- billing_package_scope_fixture_guard, which is unchanged).
create function private.billing_package_scope_construction_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('wpd18.scope_construction', true), '')
     is distinct from (new.package_key || ':' || new.scope_version::text) then
    raise exception 'package scope rows are created only by private.create_package_scope_version'
      using errcode = '42501';
  end if;
  if tg_table_name = 'billing_package_scope' and exists (
    select 1 from private.billing_package_scope_versions h
    where h.package_key = new.package_key and h.scope_version = new.scope_version
  ) then
    raise exception 'package scope version %:% is sealed', new.package_key, new.scope_version
      using errcode = '42501';
  end if;
  if tg_table_name = 'billing_package_scope_versions' and new.is_test_fixture
     and private.app_environment() not in ('development', 'test') then
    raise exception 'package-scope test fixtures are allowed only in development and test databases'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Migration from the current representation (before the guard is attached)
-- ---------------------------------------------------------------------------
-- Fresh run (migrations before the seed): no rows, nothing to seal. A local database that
-- already holds the seed's synthetic fixtures: seal each existing (package, version) where the
-- classification allows fixtures. Any non-fixture row, or a version whose positions are not
-- 1..n, stops the migration; nothing is repaired, deleted, or rewritten.
do $$
declare
  r record;
begin
  if exists (select 1 from private.billing_package_scope where not is_test_fixture) then
    raise exception 'WP-D18: non-fixture package-scope rows exist; the migration stops and changes nothing'
      using errcode = '23514';
  end if;
  if exists (
    select 1 from private.billing_package_scope
    group by package_key, scope_version
    having min(position) <> 1 or max(position) <> count(*)
  ) then
    raise exception 'WP-D18: an existing package-scope version has non-contiguous positions; the migration stops and changes nothing'
      using errcode = '23514';
  end if;
  if private.app_environment() in ('development', 'test') then
    for r in
      select s.package_key, s.scope_version, count(*)::integer as n,
             encode(extensions.digest(convert_to(
               'spotlight.package_scope.v1'
               || '|k' || octet_length(s.package_key) || ':' || s.package_key
               || '|v' || s.scope_version || '|n' || count(*)
               || string_agg('|p' || s.position || ':' || octet_length(s.item_text) || ':' || s.item_text, ''
                             order by s.position), 'UTF8'), 'sha256'), 'hex') as sha
      from private.billing_package_scope s
      group by s.package_key, s.scope_version
    loop
      insert into private.billing_package_scope_versions (package_key, scope_version, item_count, content_sha256, is_test_fixture)
      values (r.package_key, r.scope_version, r.n, r.sha, true);
    end loop;
  end if;
end;
$$;

create trigger billing_package_scope_construction_guard
  before insert on private.billing_package_scope
  for each row execute function private.billing_package_scope_construction_guard();
create trigger billing_package_scope_versions_construction_guard
  before insert on private.billing_package_scope_versions
  for each row execute function private.billing_package_scope_construction_guard();
-- Sealed headers are never modified, deleted, truncated, or unsealed (existing guards, reused).
create trigger billing_package_scope_versions_append_only
  before update or delete on private.billing_package_scope_versions
  for each row execute function private.insert_only();
create trigger billing_package_scope_versions_no_truncate
  before truncate on private.billing_package_scope_versions
  for each statement execute function private.audit_events_immutable();

-- ---------------------------------------------------------------------------
-- 4. The only way to create a version: atomic construction and sealing
-- ---------------------------------------------------------------------------
-- Serialized per package (advisory lock), so concurrent creation yields consecutive versions.
-- Items get positions 1..n in array order; the header is written last with the item count and
-- the SHA-256 of the canonical, length-prefixed serialization. Any error (bad item, label check,
-- fixture allowlist, constraint) aborts the call and rolls back the whole version.
create function private.create_package_scope_version(
  p_package_key text,
  p_items text[],
  p_is_test_fixture boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_version integer;
  v_count integer := coalesce(cardinality(p_items), 0);
  v_sha text;
begin
  if p_is_test_fixture is null then
    raise exception 'p_is_test_fixture is required' using errcode = '22023';
  end if;
  if not exists (select 1 from private.billing_packages where package_key = p_package_key) then
    raise exception 'unknown package key' using errcode = '22023';
  end if;
  if v_count not between 1 and 50 or array_position(p_items, null) is not null then
    raise exception 'a scope version has 1 to 50 non-null items' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('wpd18-scope-version:' || p_package_key, 0));
  select coalesce(max(v), 0) + 1 into v_version from (
    select max(scope_version) as v from private.billing_package_scope where package_key = p_package_key
    union all
    select max(scope_version) from private.billing_package_scope_versions where package_key = p_package_key
  ) x;

  perform set_config('wpd18.scope_construction', p_package_key || ':' || v_version::text, true);
  insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  select p_package_key, v_version, i.ord::smallint, i.item, p_is_test_fixture
  from unnest(p_items) with ordinality as i (item, ord);

  select encode(extensions.digest(convert_to(
           'spotlight.package_scope.v1'
           || '|k' || octet_length(p_package_key) || ':' || p_package_key
           || '|v' || v_version || '|n' || v_count
           || string_agg('|p' || s.position || ':' || octet_length(s.item_text) || ':' || s.item_text, ''
                         order by s.position), 'UTF8'), 'sha256'), 'hex')
    into v_sha
  from private.billing_package_scope s
  where s.package_key = p_package_key and s.scope_version = v_version;

  insert into private.billing_package_scope_versions (package_key, scope_version, item_count, content_sha256, is_test_fixture)
  values (p_package_key, v_version, v_count, v_sha, p_is_test_fixture);
  perform set_config('wpd18.scope_construction', '', true);

  return jsonb_build_object('package_key', p_package_key, 'scope_version', v_version,
    'item_count', v_count, 'content_sha256', v_sha);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The resolver: sealed versions only, re-verified at every call (same signature)
-- ---------------------------------------------------------------------------
-- Takes the newest SEALED version of the package and returns its items only if, recomputed now,
-- the item count, positions 1..n, the fixture flag of every item, and the canonical content hash
-- all match the sealed header, and the fixture allowlist admits it. Otherwise nothing is returned
-- (no fallback to an older version), so Sales issuance fails closed. Unsealed rows are never read.
create or replace function private.current_package_scope(p_package_key text)
returns table (scope_version integer, item_position smallint, item_text text)
language plpgsql stable security definer set search_path = '' as $$
#variable_conflict use_column
declare
  h private.billing_package_scope_versions;
  v_count integer;
  v_max integer;
  v_flag_mismatch boolean;
  v_sha text;
begin
  select * into h from private.billing_package_scope_versions v
   where v.package_key = p_package_key order by v.scope_version desc limit 1;
  if not found then
    return;
  end if;
  if h.is_test_fixture and private.app_environment() not in ('development', 'test') then
    return;
  end if;
  select count(*)::integer, max(s.position)::integer, bool_or(s.is_test_fixture <> h.is_test_fixture),
         encode(extensions.digest(convert_to(
           'spotlight.package_scope.v1'
           || '|k' || octet_length(h.package_key) || ':' || h.package_key
           || '|v' || h.scope_version || '|n' || count(*)
           || string_agg('|p' || s.position || ':' || octet_length(s.item_text) || ':' || s.item_text, ''
                         order by s.position), 'UTF8'), 'sha256'), 'hex')
    into v_count, v_max, v_flag_mismatch, v_sha
  from private.billing_package_scope s
  where s.package_key = h.package_key and s.scope_version = h.scope_version;
  if v_count is distinct from h.item_count or v_max is distinct from h.item_count
     or coalesce(v_flag_mismatch, true) or v_sha is distinct from h.content_sha256 then
    return;
  end if;
  return query
    select s.scope_version, s.position, s.item_text
    from private.billing_package_scope s
    where s.package_key = h.package_key and s.scope_version = h.scope_version
    order by s.position;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Privileges: no API role reads, writes, or executes any of these objects
-- ---------------------------------------------------------------------------
revoke all on function
  private.billing_package_scope_construction_guard(),
  private.create_package_scope_version(text, text[], boolean),
  private.current_package_scope(text)
from public, anon, authenticated, service_role;
