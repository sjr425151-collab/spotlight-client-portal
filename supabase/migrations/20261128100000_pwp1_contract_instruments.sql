-- PWP-1: contractual instruments, bundles, governance events and withdrawal (AUTH-021; OD-1 to
-- OD-12, OD-18; OI-98, OI-99, OI-103, OI-104, OI-106, OI-109; FD-15; 04 §4A v0.11.0).
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02).
-- - Infrastructure only. No contractual content, counsel text or approval evidence is added
--   here (OI-106, FD-05): every function takes its content and identifiers as parameters from
--   an Owner-authenticated caller, and fixtures are installed only by supabase/seed.sql.
-- - Adds only new objects. No existing table, function, policy or grant changes; in particular
--   issue_order_summary, accept_agreement, checkout, the ledger, webhooks, the AUTH-007 and
--   AUTH-018 objects, current_package_scope and the scope and environment tables are untouched
--   (they are only read).
-- - Activation exists only for `development` and `test` (CHECK). No staging, preview or
--   production eligibility exists (OD-6, OD-18). The resolver returns nothing in production.
-- - Audit only; no domain events. No item, title or body text is ever written to an audit row,
--   returned in an error, or raised: audit targets come only from validated identifiers.
--
-- Lock order (04 §4A, OD-3 and OD-4):
-- - Instrument construction: only `contract-instrument:<kind>:<package|*>`, held alone.
-- - Bundle sealing, legal approval, activation and withdrawal (governance): the per-package lock
--   `dep18-scope-eligibility:<package>` exclusively, then the bundle row FOR UPDATE.
-- - Resolution (private.current_contract_bundle): the per-package lock shared, held to commit.
--   The resolver is volatile, so it reads only after the lock is granted (READ COMMITTED, the
--   PostgREST default). It waits on governance operations for its package; it never waits on
--   instrument construction.
-- - No payment, invoice, release or Sales lock is taken anywhere here.
--
-- Refusals return {"ok": false, "error": <code>} after writing their audit event, so the event is
-- committed with the call (an event rolled back by an exception would not count).

-- ---------------------------------------------------------------------------
-- 1. Fixture labels (OD-9) and canonical serializations (OI-109)
-- ---------------------------------------------------------------------------
create function private.contract_instrument_fixture_label() returns text
language sql immutable set search_path = '' as $$ select 'TEST FIXTURE — NOT A CONTRACT INSTRUMENT' $$;
create function private.contract_bundle_fixture_label() returns text
language sql immutable set search_path = '' as $$ select 'TEST FIXTURE — NOT A CONTRACT BUNDLE' $$;

-- spotlight.contract_instrument.v1: UTF-8 bytes as supplied, no normalization; every field is
-- length-prefixed (octet_length) in a fixed order; provisions in array order. CR is rejected
-- (never converted) by the table and the loader. A missing package key serializes as '-'.
create function private.contract_instrument_sha256(
  p_kind text, p_package_key text, p_version integer, p_title text, p_body text, p_provision_ids text[]
) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(
    'spotlight.contract_instrument.v1'
    || '|kind' || octet_length(p_kind) || ':' || p_kind
    || '|pkg' || coalesce(octet_length(p_package_key) || ':' || p_package_key, '-')
    || '|v' || p_version
    || '|t' || octet_length(p_title) || ':' || p_title
    || '|b' || octet_length(p_body) || ':' || p_body
    || '|n' || cardinality(p_provision_ids)
    || coalesce((select string_agg('|p' || octet_length(u.p) || ':' || u.p, '' order by u.o)
                   from unnest(p_provision_ids) with ordinality u (p, o)), ''),
    'UTF8'), 'sha256'), 'hex');
$$;

-- spotlight.contract_bundle.v1: the package, version and title, then every component's identity
-- and hash in a fixed order (agreement, package, maintenance, shared terms, scope version), then
-- the scope-to-provision map in position order.
create function private.contract_bundle_sha256(
  p_package_key text, p_version integer, p_title text,
  p_agreement_id uuid, p_agreement_sha text,
  p_package_id uuid, p_package_sha text,
  p_maintenance_id uuid, p_maintenance_sha text,
  p_shared_id uuid, p_shared_sha text,
  p_scope_version integer, p_scope_sha text,
  p_map jsonb
) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(
    'spotlight.contract_bundle.v1'
    || '|k' || octet_length(p_package_key) || ':' || p_package_key
    || '|v' || p_version
    || '|t' || octet_length(p_title) || ':' || p_title
    || '|a' || p_agreement_id::text || ':' || p_agreement_sha
    || '|ip' || p_package_id::text || ':' || p_package_sha
    || '|im' || p_maintenance_id::text || ':' || p_maintenance_sha
    || '|is' || p_shared_id::text || ':' || p_shared_sha
    || '|s' || p_scope_version || ':' || p_scope_sha
    || '|n' || jsonb_array_length(p_map)
    || coalesce((select string_agg('|m' || e.o || ':' || octet_length(e.v #>> '{}') || ':' || (e.v #>> '{}'), '' order by e.o)
                   from jsonb_array_elements(p_map) with ordinality e (v, o)), ''),
    'UTF8'), 'sha256'), 'hex');
$$;

-- ---------------------------------------------------------------------------
-- 2. Instrument versions: sealed on creation, append-only
-- ---------------------------------------------------------------------------
create table private.contract_instrument_versions (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in ('package_specification', 'maintenance_specification', 'shared_terms')),
  package_key text references private.billing_packages (package_key),
  instrument_version integer not null check (instrument_version >= 1),
  canonicalization text not null check (canonicalization = 'spotlight.contract_instrument.v1'),
  title text not null check (char_length(title) between 1 and 200 and position(chr(13) in title) = 0),
  body text not null check (char_length(body) between 1 and 200000 and position(chr(13) in body) = 0),
  provision_ids text[] not null check (cardinality(provision_ids) between 1 and 200 and array_position(provision_ids, null) is null),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  is_test_fixture boolean not null,
  created_by uuid,
  created_at timestamptz not null default now(),
  constraint contract_instrument_versions_package check ((kind = 'package_specification') = (package_key is not null)),
  -- OD-9: a version is a fixture if and only if its body carries the fixture label.
  constraint contract_instrument_versions_fixture_label check (
    is_test_fixture = starts_with(body, 'TEST FIXTURE — NOT A CONTRACT INSTRUMENT')),
  constraint contract_instrument_versions_identity unique nulls not distinct (kind, package_key, instrument_version)
);
revoke all on table private.contract_instrument_versions from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Contract bundles: sealed on creation, append-only
-- ---------------------------------------------------------------------------
create table private.contract_bundles (
  id uuid primary key default gen_random_uuid(),
  package_key text not null references private.billing_packages (package_key),
  bundle_version integer not null check (bundle_version >= 1),
  canonicalization text not null check (canonicalization = 'spotlight.contract_bundle.v1'),
  title text not null check (char_length(title) between 1 and 200 and position(chr(13) in title) = 0),
  agreement_version_id uuid not null references public.agreement_versions (id),
  agreement_text_sha256 text not null check (agreement_text_sha256 ~ '^[0-9a-f]{64}$'),
  package_instrument_id uuid not null references private.contract_instrument_versions (id),
  package_instrument_sha256 text not null check (package_instrument_sha256 ~ '^[0-9a-f]{64}$'),
  maintenance_instrument_id uuid not null references private.contract_instrument_versions (id),
  maintenance_instrument_sha256 text not null check (maintenance_instrument_sha256 ~ '^[0-9a-f]{64}$'),
  shared_terms_instrument_id uuid not null references private.contract_instrument_versions (id),
  shared_terms_instrument_sha256 text not null check (shared_terms_instrument_sha256 ~ '^[0-9a-f]{64}$'),
  scope_version integer not null check (scope_version >= 1),
  scope_content_sha256 text not null check (scope_content_sha256 ~ '^[0-9a-f]{64}$'),
  scope_provision_map jsonb not null check (jsonb_typeof(scope_provision_map) = 'array'
    and jsonb_array_length(scope_provision_map) between 1 and 50),
  bundle_sha256 text not null check (bundle_sha256 ~ '^[0-9a-f]{64}$'),
  is_test_fixture boolean not null,
  sealed_by uuid,
  sealed_at timestamptz not null default now(),
  -- OD-9: a bundle is a fixture if and only if its title carries the fixture label.
  constraint contract_bundles_fixture_label check (
    is_test_fixture = starts_with(title, 'TEST FIXTURE — NOT A CONTRACT BUNDLE')),
  constraint contract_bundles_identity unique (package_key, bundle_version)
);
revoke all on table private.contract_bundles from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Governance records (FD-15: separate append-only objects bound to the bundle hash)
-- ---------------------------------------------------------------------------
-- Legal approval: one record per bundle, a non-sensitive reference and an evidence hash only
-- (never counsel text). It never changes sealed content.
create table private.contract_bundle_approvals (
  bundle_id uuid primary key references private.contract_bundles (id),
  bundle_sha256 text not null check (bundle_sha256 ~ '^[0-9a-f]{64}$'),
  approval_reference text not null check (approval_reference ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_by uuid not null,
  recorded_at timestamptz not null default now()
);
revoke all on table private.contract_bundle_approvals from public, anon, authenticated, service_role;

-- Activation (per classification; development and test only, by CHECK) and irreversible
-- withdrawal (actor, reason, time and authorization reference). A withdrawal in any
-- classification makes the bundle ineligible everywhere, permanently.
create table private.contract_bundle_eligibility (
  bundle_id uuid not null references private.contract_bundles (id),
  event text not null check (event in ('activated', 'withdrawn')),
  classification text not null
    check (classification in ('development', 'test', 'preview', 'staging', 'production')),
  bundle_sha256 text not null check (bundle_sha256 ~ '^[0-9a-f]{64}$'),
  reason text check (reason is null or char_length(reason) between 1 and 500),
  authorization_reference text
    check (authorization_reference is null or authorization_reference ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'),
  recorded_by uuid not null,
  recorded_at timestamptz not null default now(),
  primary key (bundle_id, event, classification),
  constraint contract_bundle_eligibility_activation_classification
    check (event <> 'activated' or classification in ('development', 'test')),
  constraint contract_bundle_eligibility_withdrawal_evidence
    check (event <> 'withdrawn' or (reason is not null and authorization_reference is not null))
);
revoke all on table private.contract_bundle_eligibility from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. Insert protection, immutability and the fixture environment allowlist
-- ---------------------------------------------------------------------------
-- Instrument and bundle rows are accepted only while the matching internal constructor is
-- building exactly that row in the current transaction (a transaction-local marker the
-- constructor sets and clears). Fixture rows are accepted only in development and test, and
-- never while the two environment classifications disagree.
create function private.contract_content_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_expected text;
begin
  if tg_table_name = 'contract_instrument_versions' then
    v_expected := 'instrument:' || new.kind || ':' || coalesce(new.package_key, '*') || ':' || new.instrument_version;
  else
    v_expected := 'bundle:' || new.package_key || ':' || new.bundle_version;
  end if;
  if coalesce(current_setting('pwp1.contract_construction', true), '') is distinct from v_expected then
    raise exception 'contract content rows are created only by the PWP-1 constructors' using errcode = '42501';
  end if;
  if new.is_test_fixture and (private.environment_consistent() is not true
     or private.app_environment() not in ('development', 'test')) then
    raise exception 'contract fixtures are allowed only in development and test databases' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger contract_instrument_versions_construction_guard
  before insert on private.contract_instrument_versions
  for each row execute function private.contract_content_guard();
create trigger contract_bundles_construction_guard
  before insert on private.contract_bundles
  for each row execute function private.contract_content_guard();

create trigger contract_instrument_versions_append_only before update or delete on private.contract_instrument_versions
  for each row execute function private.insert_only();
create trigger contract_instrument_versions_no_truncate before truncate on private.contract_instrument_versions
  for each statement execute function private.audit_events_immutable();
create trigger contract_bundles_append_only before update or delete on private.contract_bundles
  for each row execute function private.insert_only();
create trigger contract_bundles_no_truncate before truncate on private.contract_bundles
  for each statement execute function private.audit_events_immutable();
create trigger contract_bundle_approvals_append_only before update or delete on private.contract_bundle_approvals
  for each row execute function private.insert_only();
create trigger contract_bundle_approvals_no_truncate before truncate on private.contract_bundle_approvals
  for each statement execute function private.audit_events_immutable();
create trigger contract_bundle_eligibility_append_only before update or delete on private.contract_bundle_eligibility
  for each row execute function private.insert_only();
create trigger contract_bundle_eligibility_no_truncate before truncate on private.contract_bundle_eligibility
  for each statement execute function private.audit_events_immutable();

-- ---------------------------------------------------------------------------
-- 6. Integrity helpers
-- ---------------------------------------------------------------------------
-- True when the stored instrument's content still hashes to its sealed hash.
create function private.contract_instrument_verifies(p_instrument_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select i.content_sha256 = private.contract_instrument_sha256(i.kind, i.package_key, i.instrument_version,
             i.title, i.body, i.provision_ids)
    from private.contract_instrument_versions i where i.id = p_instrument_id), false);
$$;

-- The sealed scope version's items, re-verified against its AUTH-007 header (count, positions,
-- fixture flags and canonical hash, exactly as the AUTH-018 resolver checks them), or NULL.
create function private.contract_scope_items(p_package_key text, p_scope_version integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  h private.billing_package_scope_versions;
  v_count integer;
  v_max integer;
  v_flag_mismatch boolean;
  v_sha text;
  v_items jsonb;
begin
  select * into h from private.billing_package_scope_versions v
   where v.package_key = p_package_key and v.scope_version = p_scope_version;
  if not found then
    return null;
  end if;
  select count(*)::integer, max(s.position)::integer, bool_or(s.is_test_fixture <> h.is_test_fixture),
         encode(extensions.digest(convert_to(
           'spotlight.package_scope.v1'
           || '|k' || octet_length(h.package_key) || ':' || h.package_key
           || '|v' || h.scope_version || '|n' || count(*)
           || string_agg('|p' || s.position || ':' || octet_length(s.item_text) || ':' || s.item_text, ''
                         order by s.position), 'UTF8'), 'sha256'), 'hex'),
         jsonb_agg(to_jsonb(s.item_text) order by s.position)
    into v_count, v_max, v_flag_mismatch, v_sha, v_items
  from private.billing_package_scope s
  where s.package_key = h.package_key and s.scope_version = h.scope_version;
  if v_count is distinct from h.item_count or v_max is distinct from h.item_count
     or coalesce(v_flag_mismatch, true) or v_sha is distinct from h.content_sha256 then
    return null;
  end if;
  return v_items;
end;
$$;

-- OD-8 / OI-99: the order-summary limits (50 items, 300 characters per item, 8,192 bytes of
-- serialized jsonb), the same as order_summaries_scope.
create function private.contract_scope_fits(p_items jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select p_items is not null and jsonb_typeof(p_items) = 'array'
     and jsonb_array_length(p_items) between 1 and 50
     and octet_length(p_items::text) <= 8192
     and not exists (select 1 from jsonb_array_elements(p_items) e
                     where jsonb_typeof(e) <> 'string' or char_length(e #>> '{}') not between 1 and 300);
$$;

-- F2 (interface freeze): every component and the bundle re-verify, the governing agreement is
-- usable, all components agree on fixture status, the map still matches the scope, and the scope
-- still fits. NULL-safe: an unknown bundle does not verify.
create function private.contract_bundle_verifies(p_bundle_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  b private.contract_bundles;
  a public.agreement_versions;
  ip private.contract_instrument_versions;
  im private.contract_instrument_versions;
  isr private.contract_instrument_versions;
  h private.billing_package_scope_versions;
  v_items jsonb;
begin
  select * into b from private.contract_bundles x where x.id = p_bundle_id;
  if not found then
    return false;
  end if;
  select * into a from public.agreement_versions x where x.id = b.agreement_version_id;
  select * into ip from private.contract_instrument_versions x where x.id = b.package_instrument_id;
  select * into im from private.contract_instrument_versions x where x.id = b.maintenance_instrument_id;
  select * into isr from private.contract_instrument_versions x where x.id = b.shared_terms_instrument_id;
  select * into h from private.billing_package_scope_versions x
   where x.package_key = b.package_key and x.scope_version = b.scope_version;
  if a.id is null or ip.id is null or im.id is null or isr.id is null or h.package_key is null then
    return false;
  end if;
  v_items := private.contract_scope_items(b.package_key, b.scope_version);
  return coalesce(
    private.agreement_version_usable(a.id)
    and a.text_sha256 = b.agreement_text_sha256
    and ip.kind = 'package_specification' and ip.package_key = b.package_key
    and im.kind = 'maintenance_specification' and isr.kind = 'shared_terms'
    and private.contract_instrument_verifies(ip.id) and ip.content_sha256 = b.package_instrument_sha256
    and private.contract_instrument_verifies(im.id) and im.content_sha256 = b.maintenance_instrument_sha256
    and private.contract_instrument_verifies(isr.id) and isr.content_sha256 = b.shared_terms_instrument_sha256
    and h.content_sha256 = b.scope_content_sha256
    and v_items is not null and private.contract_scope_fits(v_items)
    and jsonb_array_length(b.scope_provision_map) = jsonb_array_length(v_items)
    and not exists (select 1 from jsonb_array_elements(b.scope_provision_map) e
                    where jsonb_typeof(e) <> 'string' or not ((e #>> '{}') = any (ip.provision_ids)))
    and a.is_test_fixture = b.is_test_fixture and ip.is_test_fixture = b.is_test_fixture
    and im.is_test_fixture = b.is_test_fixture and isr.is_test_fixture = b.is_test_fixture
    and h.is_test_fixture = b.is_test_fixture
    and b.bundle_sha256 = private.contract_bundle_sha256(b.package_key, b.bundle_version, b.title,
          b.agreement_version_id, b.agreement_text_sha256, b.package_instrument_id, b.package_instrument_sha256,
          b.maintenance_instrument_id, b.maintenance_instrument_sha256, b.shared_terms_instrument_id,
          b.shared_terms_instrument_sha256, b.scope_version, b.scope_content_sha256, b.scope_provision_map),
    false);
end;
$$;

-- F3 (interface freeze): true once any withdrawal exists for the bundle; unknown is false.
create function private.contract_bundle_withdrawn(p_bundle_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.contract_bundle_eligibility e
                 where e.bundle_id = p_bundle_id and e.event = 'withdrawn');
$$;

-- ---------------------------------------------------------------------------
-- 7. Internal constructors (seed fixtures and the Owner loader; no API role)
-- ---------------------------------------------------------------------------
create function private.construct_contract_instrument(
  p_kind text, p_package_key text, p_title text, p_body text, p_provision_ids text[], p_is_test_fixture boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_version integer;
  v_sha text;
  v_id uuid;
begin
  if p_is_test_fixture is null then
    raise exception 'p_is_test_fixture is required' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('contract-instrument:' || coalesce(p_kind, '') || ':'
    || coalesce(p_package_key, '*'), 0));
  select coalesce(max(i.instrument_version), 0) + 1 into v_version from private.contract_instrument_versions i
   where i.kind = p_kind and i.package_key is not distinct from p_package_key;
  v_sha := private.contract_instrument_sha256(p_kind, p_package_key, v_version, p_title, p_body, p_provision_ids);
  perform set_config('pwp1.contract_construction',
    'instrument:' || p_kind || ':' || coalesce(p_package_key, '*') || ':' || v_version, true);
  insert into private.contract_instrument_versions (kind, package_key, instrument_version, canonicalization, title,
    body, provision_ids, content_sha256, is_test_fixture, created_by)
  values (p_kind, p_package_key, v_version, 'spotlight.contract_instrument.v1', p_title, p_body, p_provision_ids,
    v_sha, p_is_test_fixture, (select auth.uid()))
  returning id into v_id;
  perform set_config('pwp1.contract_construction', '', true);
  return jsonb_build_object('instrument_id', v_id, 'kind', p_kind, 'package_key', p_package_key,
    'instrument_version', v_version, 'content_sha256', v_sha);
end;
$$;

-- Seals a bundle. The caller holds the per-package lock exclusively (governance). Raises on any
-- invalid component (the Owner function validates first and catches errors; the seed lets them
-- abort). OD-10: a non-fixture bundle needs an AUTH-018 approval of its exact scope version.
create function private.construct_contract_bundle(
  p_package_key text, p_title text, p_agreement_version_id uuid, p_package_instrument_id uuid,
  p_maintenance_instrument_id uuid, p_shared_terms_instrument_id uuid, p_scope_version integer,
  p_scope_provision_map jsonb, p_is_test_fixture boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  a public.agreement_versions;
  ip private.contract_instrument_versions;
  im private.contract_instrument_versions;
  isr private.contract_instrument_versions;
  h private.billing_package_scope_versions;
  v_items jsonb;
  v_version integer;
  v_sha text;
  v_id uuid;
begin
  if p_is_test_fixture is null then
    raise exception 'p_is_test_fixture is required' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
  select * into a from public.agreement_versions x where x.id = p_agreement_version_id;
  select * into ip from private.contract_instrument_versions x where x.id = p_package_instrument_id;
  select * into im from private.contract_instrument_versions x where x.id = p_maintenance_instrument_id;
  select * into isr from private.contract_instrument_versions x where x.id = p_shared_terms_instrument_id;
  select * into h from private.billing_package_scope_versions x
   where x.package_key = p_package_key and x.scope_version = p_scope_version;
  v_items := private.contract_scope_items(p_package_key, p_scope_version);
  if a.id is null or not private.agreement_version_usable(a.id) then
    raise exception 'bundle_agreement_unusable' using errcode = '22023';
  elsif ip.id is null or ip.kind <> 'package_specification' or ip.package_key is distinct from p_package_key
     or im.id is null or im.kind <> 'maintenance_specification'
     or isr.id is null or isr.kind <> 'shared_terms' then
    raise exception 'bundle_instrument_mismatch' using errcode = '22023';
  elsif not (private.contract_instrument_verifies(ip.id) and private.contract_instrument_verifies(im.id)
             and private.contract_instrument_verifies(isr.id)) then
    raise exception 'bundle_component_integrity' using errcode = '22023';
  elsif h.package_key is null or v_items is null then
    raise exception 'bundle_scope_invalid' using errcode = '22023';
  elsif not private.contract_scope_fits(v_items) then
    raise exception 'bundle_scope_too_large' using errcode = '22023';
  elsif p_scope_provision_map is null or jsonb_typeof(p_scope_provision_map) <> 'array'
     or jsonb_array_length(p_scope_provision_map) <> jsonb_array_length(v_items)
     or exists (select 1 from jsonb_array_elements(p_scope_provision_map) e
                where jsonb_typeof(e) <> 'string' or not ((e #>> '{}') = any (ip.provision_ids))) then
    raise exception 'bundle_provision_map_invalid' using errcode = '22023';
  elsif a.is_test_fixture <> p_is_test_fixture or ip.is_test_fixture <> p_is_test_fixture
     or im.is_test_fixture <> p_is_test_fixture or isr.is_test_fixture <> p_is_test_fixture
     or h.is_test_fixture <> p_is_test_fixture then
    raise exception 'bundle_fixture_mismatch' using errcode = '22023';
  elsif not p_is_test_fixture and not exists (
          select 1 from private.billing_package_scope_approvals sa
          where sa.package_key = p_package_key and sa.scope_version = p_scope_version
            and sa.content_sha256 = h.content_sha256) then
    raise exception 'bundle_scope_unapproved' using errcode = '22023';
  end if;
  select coalesce(max(x.bundle_version), 0) + 1 into v_version from private.contract_bundles x
   where x.package_key = p_package_key;
  v_sha := private.contract_bundle_sha256(p_package_key, v_version, p_title, a.id, a.text_sha256,
    ip.id, ip.content_sha256, im.id, im.content_sha256, isr.id, isr.content_sha256,
    p_scope_version, h.content_sha256, p_scope_provision_map);
  perform set_config('pwp1.contract_construction', 'bundle:' || p_package_key || ':' || v_version, true);
  insert into private.contract_bundles (package_key, bundle_version, canonicalization, title, agreement_version_id,
    agreement_text_sha256, package_instrument_id, package_instrument_sha256, maintenance_instrument_id,
    maintenance_instrument_sha256, shared_terms_instrument_id, shared_terms_instrument_sha256, scope_version,
    scope_content_sha256, scope_provision_map, bundle_sha256, is_test_fixture, sealed_by)
  values (p_package_key, v_version, 'spotlight.contract_bundle.v1', p_title, a.id, a.text_sha256,
    ip.id, ip.content_sha256, im.id, im.content_sha256, isr.id, isr.content_sha256, p_scope_version,
    h.content_sha256, p_scope_provision_map, v_sha, p_is_test_fixture, (select auth.uid()))
  returning id into v_id;
  perform set_config('pwp1.contract_construction', '', true);
  return jsonb_build_object('bundle_id', v_id, 'package_key', p_package_key, 'bundle_version', v_version,
    'bundle_sha256', v_sha);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Owner functions (fresh MFA, live session, NULL-safe guards, refusal audit)
-- ---------------------------------------------------------------------------
-- The shared preconditions: Owner, fresh MFA, live session; classification consistent and
-- development or test. Returns a refusal code or NULL.
create function private.contract_governance_refusal() returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if private.is_owner() is not true or private.mfa_is_fresh() is not true
     or private.session_is_active() is not true then
    return 'forbidden';
  elsif private.environment_consistent() is not true then
    return 'classification_inconsistent';
  elsif private.app_environment() not in ('development', 'test') then
    return 'classification_not_allowed';
  end if;
  return null;
end;
$$;

-- OD-5 loader: Owner-controlled, hash-verified, audited; development and test only; synthetic
-- content only (fixtures come only from the seed). The expected hash is verified before anything
-- is written; an identical replay returns the existing version; conflicting content or identity
-- fails closed.
create function private.create_contract_instrument_version(
  p_kind text, p_package_key text, p_instrument_version integer, p_title text, p_body text,
  p_provision_ids text[], p_expected_sha256 text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_kind_ok boolean := p_kind in ('package_specification', 'maintenance_specification', 'shared_terms');
  v_target text := (case when p_kind in ('package_specification', 'maintenance_specification', 'shared_terms')
    then p_kind else 'invalid' end) || ':' || (case when exists (select 1 from private.billing_packages b
    where b.package_key = p_package_key) then p_package_key when p_package_key is null then '*' else 'invalid' end)
    || ':' || coalesce(p_instrument_version::text, 'invalid');
  v_code text := private.contract_governance_refusal();
  v_existing private.contract_instrument_versions;
  v_next integer;
  v_sha text;
  v_result jsonb;
  v_state text;
begin
  if v_code is null and (not coalesce(v_kind_ok, false)
     or (p_kind = 'package_specification') is distinct from (p_package_key is not null)
     or (p_package_key is not null and not exists (select 1 from private.billing_packages b where b.package_key = p_package_key))
     or p_instrument_version is null or p_instrument_version < 1
     or coalesce(char_length(p_title), 0) not between 1 and 200 or position(chr(13) in p_title) > 0
     or coalesce(char_length(p_body), 0) not between 1 and 200000 or position(chr(13) in p_body) > 0
     or starts_with(p_body, private.contract_instrument_fixture_label())
     or coalesce(cardinality(p_provision_ids), 0) not between 1 and 200
     or array_position(p_provision_ids, null) is not null
     or exists (select 1 from unnest(p_provision_ids) u (p) where u.p !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$')
     or (select count(distinct u.p) from unnest(p_provision_ids) u (p)) <> cardinality(p_provision_ids)
     or coalesce(p_expected_sha256, '') !~ '^[0-9a-f]{64}$') then
    v_code := 'invalid_input';
  end if;

  if v_code is null then
    perform pg_advisory_xact_lock(hashtextextended('contract-instrument:' || p_kind || ':' || coalesce(p_package_key, '*'), 0));
    v_sha := private.contract_instrument_sha256(p_kind, p_package_key, p_instrument_version, p_title, p_body, p_provision_ids);
    select * into v_existing from private.contract_instrument_versions i
     where i.kind = p_kind and i.package_key is not distinct from p_package_key and i.instrument_version = p_instrument_version;
    if found then
      if v_existing.content_sha256 = v_sha and v_sha = p_expected_sha256 and not v_existing.is_test_fixture then
        return jsonb_build_object('ok', true, 'replayed', true, 'instrument_id', v_existing.id,
          'instrument_version', v_existing.instrument_version, 'content_sha256', v_sha);
      end if;
      v_code := 'version_conflict';
    else
      select coalesce(max(i.instrument_version), 0) + 1 into v_next from private.contract_instrument_versions i
       where i.kind = p_kind and i.package_key is not distinct from p_package_key;
      if p_instrument_version <> v_next then
        v_code := 'version_conflict';
      elsif v_sha <> p_expected_sha256 then
        v_code := 'hash_mismatch';
      end if;
    end if;
  end if;

  if v_code is null then
    begin
      v_result := private.construct_contract_instrument(p_kind, p_package_key, p_title, p_body, p_provision_ids, false);
      if (v_result ->> 'instrument_version')::integer is distinct from p_instrument_version
         or v_result ->> 'content_sha256' is distinct from p_expected_sha256 then
        raise exception 'sealed identity differs from the expected identity' using errcode = 'P0001';
      end if;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      v_code := 'load_failed';
    end;
  end if;

  if v_code is not null then
    perform private.record_audit_event('contract_instrument.load_rejected', 'contract_instrument', v_target, null, null,
      jsonb_build_object('reason', v_code) || case when v_state is null then '{}'::jsonb
        else jsonb_build_object('sqlstate', v_state) end, 'general');
    return private.fail(v_code);
  end if;
  perform private.record_audit_event('contract_instrument.created', 'contract_instrument', v_target, null, null,
    jsonb_build_object('instrument_id', v_result ->> 'instrument_id', 'kind', p_kind, 'package_key', p_package_key,
      'instrument_version', p_instrument_version, 'content_sha256', p_expected_sha256,
      'classification', private.app_environment()), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'instrument_id', v_result ->> 'instrument_id',
    'instrument_version', p_instrument_version, 'content_sha256', p_expected_sha256);
end;
$$;

-- Seals a non-fixture bundle from existing components. An identical request (same package, title,
-- components and map) for an already sealed bundle returns it; anything invalid fails closed.
create function private.seal_contract_bundle(
  p_package_key text, p_title text, p_agreement_version_id uuid, p_package_instrument_id uuid,
  p_maintenance_instrument_id uuid, p_shared_terms_instrument_id uuid, p_scope_version integer,
  p_scope_provision_map jsonb
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_pkg_ok boolean := exists (select 1 from private.billing_packages b where b.package_key = p_package_key);
  v_target text := (case when exists (select 1 from private.billing_packages b where b.package_key = p_package_key)
    then p_package_key else 'invalid' end) || ':new';
  v_code text := private.contract_governance_refusal();
  v_existing private.contract_bundles;
  v_result jsonb;
  v_state text;
  v_msg text;
begin
  if v_code is null and (not v_pkg_ok
     or coalesce(char_length(p_title), 0) not between 1 and 200 or position(chr(13) in p_title) > 0
     or starts_with(p_title, private.contract_bundle_fixture_label())
     or p_agreement_version_id is null or p_package_instrument_id is null or p_maintenance_instrument_id is null
     or p_shared_terms_instrument_id is null or p_scope_version is null
     or p_scope_provision_map is null or jsonb_typeof(p_scope_provision_map) <> 'array'
     or octet_length(p_scope_provision_map::text) > 16384) then
    v_code := 'invalid_input';
  end if;

  if v_code is null then
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
    select * into v_existing from private.contract_bundles x
     where x.package_key = p_package_key and x.title = p_title and x.agreement_version_id = p_agreement_version_id
       and x.package_instrument_id = p_package_instrument_id and x.maintenance_instrument_id = p_maintenance_instrument_id
       and x.shared_terms_instrument_id = p_shared_terms_instrument_id and x.scope_version = p_scope_version
       and x.scope_provision_map = p_scope_provision_map and not x.is_test_fixture
     order by x.bundle_version desc limit 1;
    if found then
      return jsonb_build_object('ok', true, 'replayed', true, 'bundle_id', v_existing.id,
        'bundle_version', v_existing.bundle_version, 'bundle_sha256', v_existing.bundle_sha256);
    end if;
    begin
      v_result := private.construct_contract_bundle(p_package_key, p_title, p_agreement_version_id, p_package_instrument_id,
        p_maintenance_instrument_id, p_shared_terms_instrument_id, p_scope_version, p_scope_provision_map, false);
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
      -- Only the constructor's own fixed codes are reported; anything else is generic.
      v_code := case when v_msg in ('bundle_agreement_unusable', 'bundle_instrument_mismatch',
                  'bundle_component_integrity', 'bundle_scope_invalid', 'bundle_scope_too_large',
                  'bundle_provision_map_invalid', 'bundle_fixture_mismatch', 'bundle_scope_unapproved')
                  then v_msg else 'seal_failed' end;
    end;
  end if;

  if v_code is not null then
    perform private.record_audit_event('contract_bundle.seal_rejected', 'contract_bundle', v_target, null, null,
      jsonb_build_object('reason', v_code) || case when v_state is null then '{}'::jsonb
        else jsonb_build_object('sqlstate', v_state) end, 'general');
    return private.fail(v_code);
  end if;
  perform private.record_audit_event('contract_bundle.sealed', 'contract_bundle', v_result ->> 'bundle_id', null, null,
    jsonb_build_object('bundle_id', v_result ->> 'bundle_id', 'package_key', p_package_key,
      'bundle_version', (v_result ->> 'bundle_version')::integer, 'bundle_sha256', v_result ->> 'bundle_sha256',
      'classification', private.app_environment()), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'bundle_id', v_result ->> 'bundle_id',
    'bundle_version', (v_result ->> 'bundle_version')::integer, 'bundle_sha256', v_result ->> 'bundle_sha256');
end;
$$;

-- Records the legal approval of one sealed, non-fixture bundle, bound to its exact hash.
create function private.record_contract_bundle_approval(
  p_bundle_id uuid, p_bundle_sha256 text, p_approval_reference text, p_evidence_sha256 text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  b private.contract_bundles;
  v_target text := coalesce((select x.id::text from private.contract_bundles x where x.id = p_bundle_id), 'invalid');
  v_code text := private.contract_governance_refusal();
  v_existing private.contract_bundle_approvals;
begin
  if v_code is null and (v_target = 'invalid'
     or coalesce(p_bundle_sha256, '') !~ '^[0-9a-f]{64}$' or coalesce(p_evidence_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_approval_reference, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$') then
    v_code := 'invalid_input';
  end if;
  if v_code is null then
    select * into b from private.contract_bundles x where x.id = p_bundle_id;
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || b.package_key, 0));
    perform 1 from private.contract_bundles x where x.id = p_bundle_id for update;
    select * into v_existing from private.contract_bundle_approvals x where x.bundle_id = p_bundle_id;
    if found then
      if v_existing.bundle_sha256 = p_bundle_sha256 and v_existing.approval_reference = p_approval_reference
         and v_existing.evidence_sha256 = p_evidence_sha256 then
        return jsonb_build_object('ok', true, 'replayed', true, 'bundle_id', p_bundle_id, 'bundle_sha256', p_bundle_sha256);
      end if;
      v_code := 'approval_conflict';
    elsif b.is_test_fixture then
      v_code := 'fixture_not_allowed';
    elsif p_bundle_sha256 <> b.bundle_sha256 then
      v_code := 'hash_mismatch';
    elsif private.contract_bundle_withdrawn(p_bundle_id) then
      v_code := 'withdrawn';
    elsif not private.contract_bundle_verifies(p_bundle_id) then
      v_code := 'integrity_failure';
    end if;
  end if;
  if v_code is not null then
    perform private.record_audit_event('contract_bundle.approval_rejected', 'contract_bundle', v_target, null, null,
      jsonb_build_object('reason', v_code), 'general');
    return private.fail(v_code);
  end if;
  insert into private.contract_bundle_approvals (bundle_id, bundle_sha256, approval_reference, evidence_sha256, recorded_by)
  values (p_bundle_id, p_bundle_sha256, p_approval_reference, p_evidence_sha256, (select auth.uid()));
  perform private.record_audit_event('contract_bundle.approval_recorded', 'contract_bundle', v_target, null, null,
    jsonb_build_object('bundle_id', p_bundle_id, 'bundle_sha256', p_bundle_sha256,
      'approval_reference', p_approval_reference, 'evidence_sha256', p_evidence_sha256), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'bundle_id', p_bundle_id, 'bundle_sha256', p_bundle_sha256);
end;
$$;

-- Activates an approved, verifying, non-withdrawn, non-fixture bundle for the current
-- classification (development or test only).
create function private.activate_contract_bundle(p_bundle_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  b private.contract_bundles;
  v_target text := coalesce((select x.id::text from private.contract_bundles x where x.id = p_bundle_id), 'invalid');
  v_code text := private.contract_governance_refusal();
  v_env text;
begin
  if v_code is null and v_target = 'invalid' then
    v_code := 'bundle_not_found';
  end if;
  if v_code is null then
    v_env := private.app_environment();
    select * into b from private.contract_bundles x where x.id = p_bundle_id;
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || b.package_key, 0));
    perform 1 from private.contract_bundles x where x.id = p_bundle_id for update;
    if b.is_test_fixture then
      v_code := 'fixture_not_allowed';
    elsif private.contract_bundle_withdrawn(p_bundle_id) then
      v_code := 'withdrawn';
    elsif not exists (select 1 from private.contract_bundle_approvals x
                      where x.bundle_id = p_bundle_id and x.bundle_sha256 = b.bundle_sha256) then
      v_code := 'approval_missing';
    elsif not private.contract_bundle_verifies(p_bundle_id) then
      v_code := 'integrity_failure';
    elsif exists (select 1 from private.contract_bundle_eligibility e where e.bundle_id = p_bundle_id
                  and e.event = 'activated' and e.classification = v_env) then
      return jsonb_build_object('ok', true, 'replayed', true, 'bundle_id', p_bundle_id, 'classification', v_env);
    end if;
  end if;
  if v_code is not null then
    perform private.record_audit_event('contract_bundle.activation_rejected', 'contract_bundle', v_target, null, null,
      jsonb_build_object('reason', v_code), 'general');
    return private.fail(v_code);
  end if;
  insert into private.contract_bundle_eligibility (bundle_id, event, classification, bundle_sha256, recorded_by)
  values (p_bundle_id, 'activated', v_env, b.bundle_sha256, (select auth.uid()));
  perform private.record_audit_event('contract_bundle.activated', 'contract_bundle', v_target, null, null,
    jsonb_build_object('bundle_id', p_bundle_id, 'bundle_sha256', b.bundle_sha256, 'classification', v_env), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'bundle_id', p_bundle_id, 'classification', v_env);
end;
$$;

-- Withdraws a bundle from future issuance and acceptance, irreversibly. It records the actor,
-- the reason, the time and an authorization reference; it never changes sealed content or
-- accepted records. Allowed for fixture bundles too (it only removes eligibility).
create function private.withdraw_contract_bundle(p_bundle_id uuid, p_reason text, p_authorization_reference text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  b private.contract_bundles;
  v_target text := coalesce((select x.id::text from private.contract_bundles x where x.id = p_bundle_id), 'invalid');
  v_code text;
  v_env text;
begin
  -- Withdrawal only reduces eligibility, so it is not limited to development and test; it still
  -- needs the Owner, fresh MFA, a live session and a consistent classification.
  if private.is_owner() is not true or private.mfa_is_fresh() is not true
     or private.session_is_active() is not true then
    v_code := 'forbidden';
  elsif private.environment_consistent() is not true then
    v_code := 'classification_inconsistent';
  elsif v_target = 'invalid' then
    v_code := 'bundle_not_found';
  elsif coalesce(char_length(btrim(p_reason)), 0) not between 1 and 500
     or coalesce(p_authorization_reference, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$' then
    v_code := 'invalid_input';
  end if;
  if v_code is null then
    v_env := private.app_environment();
    select * into b from private.contract_bundles x where x.id = p_bundle_id;
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || b.package_key, 0));
    perform 1 from private.contract_bundles x where x.id = p_bundle_id for update;
    if private.contract_bundle_withdrawn(p_bundle_id) then
      return jsonb_build_object('ok', true, 'replayed', true, 'bundle_id', p_bundle_id);
    end if;
  end if;
  if v_code is not null then
    perform private.record_audit_event('contract_bundle.withdrawal_rejected', 'contract_bundle', v_target, null, null,
      jsonb_build_object('reason', v_code), 'general');
    return private.fail(v_code);
  end if;
  insert into private.contract_bundle_eligibility (bundle_id, event, classification, bundle_sha256, reason,
    authorization_reference, recorded_by)
  values (p_bundle_id, 'withdrawn', v_env, b.bundle_sha256, btrim(p_reason), p_authorization_reference, (select auth.uid()));
  perform private.record_audit_event('contract_bundle.withdrawn', 'contract_bundle', v_target, null, null,
    jsonb_build_object('bundle_id', p_bundle_id, 'bundle_sha256', b.bundle_sha256, 'classification', v_env,
      'authorization_reference', p_authorization_reference), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'bundle_id', p_bundle_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. The resolver (F1, interface freeze): newest sealed bundle, if eligible; otherwise nothing
-- ---------------------------------------------------------------------------
create function private.current_contract_bundle(p_package_key text)
returns table (
  bundle_id uuid, bundle_version integer, bundle_canonicalization text, bundle_sha256 text,
  agreement_version_id uuid, agreement_text_sha256 text,
  package_instrument_id uuid, package_instrument_sha256 text,
  maintenance_instrument_id uuid, maintenance_instrument_sha256 text,
  shared_terms_instrument_id uuid, shared_terms_instrument_sha256 text,
  scope_version integer, scope_content_sha256 text, scope_items jsonb, scope_provision_map jsonb,
  is_test_fixture boolean)
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_column
declare
  b private.contract_bundles;
  v_env text;
  v_items jsonb;
begin
  perform pg_advisory_xact_lock_shared(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
  if private.environment_consistent() is not true then
    return;
  end if;
  v_env := private.app_environment();
  select * into b from private.contract_bundles x where x.package_key = p_package_key
   order by x.bundle_version desc limit 1;
  if not found or private.contract_bundle_withdrawn(b.id) or not private.contract_bundle_verifies(b.id) then
    return;
  end if;
  if b.is_test_fixture then
    if v_env not in ('development', 'test') then
      return;
    end if;
  elsif not exists (select 1 from private.contract_bundle_approvals x where x.bundle_id = b.id and x.bundle_sha256 = b.bundle_sha256)
     or not exists (select 1 from private.contract_bundle_eligibility e where e.bundle_id = b.id
                    and e.event = 'activated' and e.classification = v_env and e.bundle_sha256 = b.bundle_sha256) then
    return;
  end if;
  v_items := private.contract_scope_items(b.package_key, b.scope_version);
  return query select b.id, b.bundle_version, b.canonicalization, b.bundle_sha256, b.agreement_version_id,
    b.agreement_text_sha256, b.package_instrument_id, b.package_instrument_sha256, b.maintenance_instrument_id,
    b.maintenance_instrument_sha256, b.shared_terms_instrument_id, b.shared_terms_instrument_sha256,
    b.scope_version, b.scope_content_sha256, v_items, b.scope_provision_map, b.is_test_fixture;
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. Reading the instruments (T-CON-11, staff path and negative half)
-- ---------------------------------------------------------------------------
-- The staff read path (Owner ruling via Main, Q3 as amended): the Owner and Admin (aal2, live
-- session) may read any bundle's instruments; a fixture bundle only in development and test with a
-- consistent classification. Sales, clients and everyone else read nothing here: the client read
-- path (the instruments of a client's own projects' bundles) is a separate object in PWP-2.
-- Unreadable and unknown look the same.
create function private.contract_bundle_documents(p_bundle_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  b private.contract_bundles;
begin
  select * into b from private.contract_bundles x where x.id = p_bundle_id;
  if not found then
    return private.fail('not_found');
  end if;
  if b.is_test_fixture and (private.environment_consistent() is not true
     or private.app_environment() not in ('development', 'test')) then
    return private.fail('not_found');
  end if;
  if not (private.is_staff() is true and private.is_aal2() is true and private.session_is_active() is true) then
    return private.fail('not_found');
  end if;
  return jsonb_build_object('ok', true, 'bundle_id', b.id, 'package_key', b.package_key,
    'bundle_version', b.bundle_version, 'bundle_sha256', b.bundle_sha256, 'is_test_fixture', b.is_test_fixture,
    'instruments', (select jsonb_agg(jsonb_build_object('kind', i.kind, 'instrument_id', i.id,
        'instrument_version', i.instrument_version, 'title', i.title, 'body', i.body,
        'content_sha256', i.content_sha256, 'is_test_fixture', i.is_test_fixture)
        order by array_position(array['package_specification', 'maintenance_specification', 'shared_terms'], i.kind))
      from private.contract_instrument_versions i
      where i.id in (b.package_instrument_id, b.maintenance_instrument_id, b.shared_terms_instrument_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Security-invoker wrappers and privileges
-- ---------------------------------------------------------------------------
create function public.create_contract_instrument_version(p_kind text, p_package_key text, p_instrument_version integer,
  p_title text, p_body text, p_provision_ids text[], p_expected_sha256 text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.create_contract_instrument_version(p_kind, p_package_key, p_instrument_version, p_title, p_body,
    p_provision_ids, p_expected_sha256);
$$;
create function public.seal_contract_bundle(p_package_key text, p_title text, p_agreement_version_id uuid,
  p_package_instrument_id uuid, p_maintenance_instrument_id uuid, p_shared_terms_instrument_id uuid,
  p_scope_version integer, p_scope_provision_map jsonb)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.seal_contract_bundle(p_package_key, p_title, p_agreement_version_id, p_package_instrument_id,
    p_maintenance_instrument_id, p_shared_terms_instrument_id, p_scope_version, p_scope_provision_map);
$$;
create function public.record_contract_bundle_approval(p_bundle_id uuid, p_bundle_sha256 text, p_approval_reference text,
  p_evidence_sha256 text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.record_contract_bundle_approval(p_bundle_id, p_bundle_sha256, p_approval_reference, p_evidence_sha256);
$$;
create function public.activate_contract_bundle(p_bundle_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.activate_contract_bundle(p_bundle_id);
$$;
create function public.withdraw_contract_bundle(p_bundle_id uuid, p_reason text, p_authorization_reference text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.withdraw_contract_bundle(p_bundle_id, p_reason, p_authorization_reference);
$$;
create function public.contract_bundle_documents(p_bundle_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.contract_bundle_documents(p_bundle_id);
$$;

revoke all on function
  private.contract_instrument_fixture_label(), private.contract_bundle_fixture_label(),
  private.contract_instrument_sha256(text, text, integer, text, text, text[]),
  private.contract_bundle_sha256(text, integer, text, uuid, text, uuid, text, uuid, text, uuid, text, integer, text, jsonb),
  private.contract_content_guard(), private.contract_instrument_verifies(uuid),
  private.contract_scope_items(text, integer), private.contract_scope_fits(jsonb),
  private.contract_bundle_verifies(uuid), private.contract_bundle_withdrawn(uuid),
  private.construct_contract_instrument(text, text, text, text, text[], boolean),
  private.construct_contract_bundle(text, text, uuid, uuid, uuid, uuid, integer, jsonb, boolean),
  private.contract_governance_refusal(),
  private.create_contract_instrument_version(text, text, integer, text, text, text[], text),
  private.seal_contract_bundle(text, text, uuid, uuid, uuid, uuid, integer, jsonb),
  private.record_contract_bundle_approval(uuid, text, text, text),
  private.activate_contract_bundle(uuid),
  private.withdraw_contract_bundle(uuid, text, text),
  private.current_contract_bundle(text),
  private.contract_bundle_documents(uuid),
  public.create_contract_instrument_version(text, text, integer, text, text, text[], text),
  public.seal_contract_bundle(text, text, uuid, uuid, uuid, uuid, integer, jsonb),
  public.record_contract_bundle_approval(uuid, text, text, text),
  public.activate_contract_bundle(uuid),
  public.withdraw_contract_bundle(uuid, text, text),
  public.contract_bundle_documents(uuid)
from public, anon, authenticated, service_role;
grant execute on function
  private.create_contract_instrument_version(text, text, integer, text, text, text[], text),
  private.seal_contract_bundle(text, text, uuid, uuid, uuid, uuid, integer, jsonb),
  private.record_contract_bundle_approval(uuid, text, text, text),
  private.activate_contract_bundle(uuid),
  private.withdraw_contract_bundle(uuid, text, text),
  private.contract_bundle_documents(uuid),
  public.create_contract_instrument_version(text, text, integer, text, text, text[], text),
  public.seal_contract_bundle(text, text, uuid, uuid, uuid, uuid, integer, jsonb),
  public.record_contract_bundle_approval(uuid, text, text, text),
  public.activate_contract_bundle(uuid),
  public.withdraw_contract_bundle(uuid, text, text),
  public.contract_bundle_documents(uuid)
to authenticated;
