-- WP-B (1 of 2): agreement versions, the test-only fixture, package pricing, the versioned
-- Stripe catalog mapping, order summaries, and acceptance evidence.
-- Specifications: 04 §1-§7 (v0.8.0), 03 §4 (v0.4.5), 01 §7; decisions OI-13, OI-14, OI-15,
-- OI-17, OI-28, OI-34, OI-47, OI-69, OI-71, OI-72. Authorization: AUTH-001 (Tier 1, with the
-- Tier 2 controls for database security work on NEW WP-B tables only).
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02).
-- - Creates only new WP-B objects. No Phase 2 or WP-0 object is modified (AUTH-001).
-- - Every table is written only through SECURITY DEFINER functions that authorize the
--   caller, write the audit event, the domain event and the outbox row in the same
--   transaction (04 §17 invariant 6).
-- - Money is integer cents only (04 §7).

-- ---------------------------------------------------------------------------
-- 0. Environment marker (OI-69). Fail closed: no row means production.
-- ---------------------------------------------------------------------------
-- Local and CI seeds insert a non-production row; production provisioning never does.
-- Only the migration owner can write it (private schema, no grants).
create table private.environment_settings (
  singleton boolean primary key default true check (singleton),
  app_env text not null check (app_env in ('development', 'test', 'preview', 'staging')),
  recorded_at timestamptz not null default now()
);
revoke all on table private.environment_settings from public, anon, authenticated, service_role;

create function private.app_environment() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select e.app_env from private.environment_settings e where e.singleton), 'production');
$$;

create function private.is_production() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.app_environment() = 'production';
$$;

-- Stripe mode the environment must use (02 §4): live only in production.
create function private.stripe_mode() returns text
language sql stable security definer set search_path = '' as $$
  select case when private.is_production() then 'live' else 'test' end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Canonical text and hashing (04 §2)
-- ---------------------------------------------------------------------------
-- UTF-8 with normalized line endings (CRLF and CR become LF).
create function private.canonical_text(p_text text) returns text
language sql immutable set search_path = '' as $$
  select replace(replace(p_text, E'\r\n', E'\n'), E'\r', E'\n');
$$;

create function private.sha256_hex(p_text text) returns text
language sql immutable set search_path = '' as $$
  select encode(extensions.digest(convert_to(p_text, 'UTF8'), 'sha256'), 'hex');
$$;

-- The legal-adviser-approved Authorization for Final Payment clause (04 §3.1), verbatim.
-- tests/unit/wpb-agreement.test.ts proves this text equals the clause in spec 04 and the
-- TypeScript constant, byte for byte.
create function private.final_payment_clause() returns text
language sql immutable set search_path = '' as $$
  select 'Authorization for Final Payment' || E'\n\n'
    || 'By accepting this agreement and submitting the initial deposit, I authorize Spotlight Marketing LLC to securely retain my payment method through Stripe for the purpose of collecting the remaining project balance.' || E'\n\n'
    || 'I understand that the outstanding balance, as specified in my accepted order, will become due upon my final approval of the completed website.' || E'\n\n'
    || 'Upon my explicit approval, I authorize Spotlight Marketing LLC to automatically charge the outstanding balance to my saved payment method without requiring a separate checkout.' || E'\n\n'
    || 'I understand that publication of the website is contingent upon successful payment. An itemized invoice and payment receipt will be provided electronically.';
$$;

-- The required label of the test-only fixture (OI-69).
create function private.test_fixture_label() returns text
language sql immutable set search_path = '' as $$
  select 'TEST FIXTURE — NOT AN AGREEMENT';
$$;

-- ---------------------------------------------------------------------------
-- 2. Agreement versions (04 §2; OI-69)
-- ---------------------------------------------------------------------------
create type public.agreement_version_status as enum ('draft', 'approved', 'retired');

create table public.agreement_versions (
  id uuid primary key default gen_random_uuid(),
  version_label text not null unique,
  canonical_text text not null,
  text_sha256 text not null,
  effective_from date not null,
  status public.agreement_version_status not null default 'draft',
  approval_reference text,
  is_test_fixture boolean not null default false,
  -- Production approval is a Tier 3 action with counsel-approved text (DEP-03). No R1
  -- function sets it; the constraint below makes it impossible for a fixture.
  approved_for_production boolean not null default false,
  contains_final_payment_clause boolean not null,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  approved_at timestamptz,
  retired_at timestamptz,
  constraint agreement_versions_label_format check (version_label ~ '^[0-9A-Za-z][0-9A-Za-z._-]{0,39}$'),
  constraint agreement_versions_text_bounded check (char_length(canonical_text) between 1 and 200000),
  constraint agreement_versions_hash_format check (text_sha256 ~ '^[0-9a-f]{64}$'),
  constraint agreement_versions_reference_bounded check (approval_reference is null or char_length(approval_reference) between 1 and 200),
  -- OI-69: a fixture can never be approved for production use.
  constraint agreement_versions_fixture_never_production check (not (is_test_fixture and approved_for_production)),
  constraint agreement_versions_production_requires_approval check (not approved_for_production or status in ('approved', 'retired')),
  constraint agreement_versions_fixture_labeled check (
    not is_test_fixture or left(canonical_text, 31) = 'TEST FIXTURE — NOT AN AGREEMENT')
);

-- Insert: canonicalize, hash, detect the clause, refuse fixtures in production.
-- Update: only draft -> approved -> retired; the text, hash and flags never change.
create function private.agreement_versions_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'agreement versions are never deleted' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.canonical_text := private.canonical_text(new.canonical_text);
    new.text_sha256 := private.sha256_hex(new.canonical_text);
    new.contains_final_payment_clause := position(private.final_payment_clause() in new.canonical_text) > 0;
    new.created_by := coalesce((select auth.uid()), new.created_by);
    if new.is_test_fixture and private.is_production() then
      raise exception 'a test-only agreement fixture cannot be created in production (OI-69)'
        using errcode = '42501';
    end if;
    if new.approved_for_production then
      raise exception 'production approval is not granted at creation' using errcode = '42501';
    end if;
    if new.status = 'approved' then new.approved_at := now(); end if;
    return new;
  end if;
  if (new.id, new.version_label, new.canonical_text, new.text_sha256, new.effective_from,
      new.is_test_fixture, new.contains_final_payment_clause, new.created_by, new.created_at,
      new.approval_reference)
     is distinct from
     (old.id, old.version_label, old.canonical_text, old.text_sha256, old.effective_from,
      old.is_test_fixture, old.contains_final_payment_clause, old.created_by, old.created_at,
      old.approval_reference) then
    raise exception 'agreement version text and identity are immutable' using errcode = '42501';
  end if;
  if new.approved_for_production and not old.approved_for_production and new.is_test_fixture then
    raise exception 'a test-only agreement fixture cannot be approved for production (OI-69)'
      using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'draft' and new.status = 'approved')
    or (old.status = 'approved' and new.status = 'retired')) then
    raise exception 'invalid agreement version transition % -> %', old.status, new.status
      using errcode = '23514';
  end if;
  if new.status = 'approved' and old.status = 'draft' then new.approved_at := now(); end if;
  if new.status = 'retired' and old.status = 'approved' then new.retired_at := now(); end if;
  return new;
end;
$$;
create trigger agreement_versions_guard
  before insert or update or delete on public.agreement_versions
  for each row execute function private.agreement_versions_guard();

-- Hash verification on read (04 §2).
create function private.agreement_version_hash_ok(p_version_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select v.text_sha256 = private.sha256_hex(private.canonical_text(v.canonical_text))
    from public.agreement_versions v where v.id = p_version_id), false);
$$;

-- A version clients may be shown and may accept in this environment (04 §2): approved,
-- carrying the §3.1 clause, hash intact; in production also approved for production and
-- never a fixture.
create function private.agreement_version_usable(p_version_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select v.status = 'approved'
       and v.contains_final_payment_clause
       and private.agreement_version_hash_ok(v.id)
       and (not private.is_production() or (v.approved_for_production and not v.is_test_fixture))
    from public.agreement_versions v where v.id = p_version_id), false);
$$;

-- Installs the OI-69 fixture: the label, then only the verbatim §3.1 clause. Refused in
-- production. Idempotent. Called by the local/CI seed; no API role may execute it.
create function private.install_test_agreement_fixture() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if private.is_production() then
    raise exception 'a test-only agreement fixture cannot be installed in production (OI-69)'
      using errcode = '42501';
  end if;
  select id into v_id from public.agreement_versions where version_label = 'test-fixture-1';
  if v_id is not null then
    return v_id;
  end if;
  insert into public.agreement_versions (
    version_label, canonical_text, text_sha256, effective_from, status, approval_reference,
    is_test_fixture, contains_final_payment_clause)
  values (
    'test-fixture-1',
    private.test_fixture_label() || E'\n\n' || private.final_payment_clause(),
    repeat('0', 64), date '2026-11-24', 'approved', 'OI-69 test-only fixture', true, false)
  returning id into v_id;
  return v_id;
end;
$$;

-- Owner-only, fresh MFA: record a counsel-approved agreement text as a draft, and approve it
-- for use (04 §2; CLAUDE.md §5). Production approval is a separate Tier 3 action.
create function private.create_agreement_version(
  p_version_label text, p_canonical_text text, p_effective_from date, p_approval_reference text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if left(coalesce(p_canonical_text, ''), 31) = private.test_fixture_label() then
    return private.fail('fixture_not_allowed');
  end if;
  insert into public.agreement_versions (version_label, canonical_text, text_sha256, effective_from,
    approval_reference, contains_final_payment_clause)
  values (p_version_label, p_canonical_text, repeat('0', 64), p_effective_from,
    nullif(btrim(p_approval_reference), ''), false)
  returning id into v_id;
  perform private.record_audit_event('agreement_version.created', 'agreement_version', v_id::text,
    null, null, jsonb_build_object('version_label', p_version_label), 'general');
  return jsonb_build_object('ok', true, 'agreement_version_id', v_id);
exception
  when unique_violation then return private.fail('duplicate_version');
  when check_violation or invalid_text_representation then return private.fail('invalid_input');
end;
$$;

create function private.approve_agreement_version(p_version_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  update public.agreement_versions set status = 'approved'
   where id = p_version_id and status = 'draft' and contains_final_payment_clause;
  if not found then
    return private.fail('not_approvable');
  end if;
  perform private.record_audit_event('agreement_version.approved', 'agreement_version',
    p_version_id::text, null, null, '{}'::jsonb, 'general');
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Package pricing and the versioned catalog mapping (04 §5-§7; OI-14, OI-15, OI-47)
-- ---------------------------------------------------------------------------
create table private.billing_packages (
  package_key text primary key,
  display_name text not null,
  total_cents integer not null,
  deposit_cents integer not null,
  balance_cents integer not null,
  constraint billing_packages_key check (package_key in ('essential', 'professional', 'advanced', 'signature', 'prestige')),
  constraint billing_packages_positive check (total_cents > 0 and deposit_cents > 0 and balance_cents > 0),
  -- 04 §7: deposit = round_half_up(total x 20%), in integer arithmetic; deposit + balance = total.
  constraint billing_packages_deposit_rule check (deposit_cents = (total_cents * 20 + 50) / 100),
  constraint billing_packages_sum_rule check (deposit_cents + balance_cents = total_cents)
);
revoke all on table private.billing_packages from public, anon, authenticated, service_role;

insert into private.billing_packages (package_key, display_name, total_cents, deposit_cents, balance_cents) values
  ('essential', 'Essential', 80000, 16000, 64000),
  ('professional', 'Professional', 149500, 29900, 119600),
  ('advanced', 'Advanced', 249500, 49900, 199600),
  ('signature', 'Signature', 349500, 69900, 279600),
  ('prestige', 'Prestige', 499500, 99900, 399600);

-- 04 §5.1: maintenance is 9900 cents per month and is never reduced (OI-44, OI-47).
create function private.maintenance_monthly_cents() returns integer
language sql immutable set search_path = '' as $$ select 9900; $$;

-- 04 §5.2 rule and §6.1: package key -> environment -> Price IDs with expected cents.
-- Only the TEST catalog (DEP-01, verified 2026-11-23) is loaded. The live Price IDs are
-- reference identifiers used only in production after DEP-02 under production
-- authorization; they are deliberately absent, so production fails closed here.
create table private.stripe_catalog_prices (
  environment text not null,
  catalog_version smallint not null,
  catalog_key text not null,
  package_key text references private.billing_packages (package_key),
  component text not null,
  price_id text not null,
  expected_unit_amount integer not null,
  currency text not null default 'usd',
  price_type text not null,
  recurring_interval text,
  primary key (environment, catalog_version, catalog_key),
  unique (environment, price_id),
  constraint stripe_catalog_environment check (environment in ('test', 'live')),
  constraint stripe_catalog_component check (component in ('deposit', 'balance', 'maintenance')),
  constraint stripe_catalog_price_id check (price_id ~ '^price_[A-Za-z0-9]{8,64}$'),
  constraint stripe_catalog_amount check (expected_unit_amount > 0),
  constraint stripe_catalog_currency check (currency = 'usd'),
  constraint stripe_catalog_type check (
    (component = 'maintenance' and price_type = 'recurring' and recurring_interval = 'month' and package_key is null)
    or (component <> 'maintenance' and price_type = 'one_time' and recurring_interval is null and package_key is not null))
);
revoke all on table private.stripe_catalog_prices from public, anon, authenticated, service_role;

insert into private.stripe_catalog_prices
  (environment, catalog_version, catalog_key, package_key, component, price_id, expected_unit_amount, price_type, recurring_interval) values
  ('test', 1, 'essential.deposit', 'essential', 'deposit', 'price_1Uf5HxK5j4r4WkVPkRUJ4gnZ', 16000, 'one_time', null),
  ('test', 1, 'essential.balance', 'essential', 'balance', 'price_1Uf5HyK5j4r4WkVPfrkvOv7h', 64000, 'one_time', null),
  ('test', 1, 'professional.deposit', 'professional', 'deposit', 'price_1Uf5HyK5j4r4WkVPOtk24lGw', 29900, 'one_time', null),
  ('test', 1, 'professional.balance', 'professional', 'balance', 'price_1Uf5HzK5j4r4WkVPRH6Wkz6D', 119600, 'one_time', null),
  ('test', 1, 'advanced.deposit', 'advanced', 'deposit', 'price_1Uf5HzK5j4r4WkVP35jgGOiy', 49900, 'one_time', null),
  ('test', 1, 'advanced.balance', 'advanced', 'balance', 'price_1Uf5I0K5j4r4WkVPZLs7eS9w', 199600, 'one_time', null),
  ('test', 1, 'signature.deposit', 'signature', 'deposit', 'price_1Uf5I0K5j4r4WkVPW6smdGo2', 69900, 'one_time', null),
  ('test', 1, 'signature.balance', 'signature', 'balance', 'price_1Uf5I1K5j4r4WkVPB0lY2MgL', 279600, 'one_time', null),
  ('test', 1, 'prestige.deposit', 'prestige', 'deposit', 'price_1Uf5I1K5j4r4WkVPyCBIiYGP', 99900, 'one_time', null),
  ('test', 1, 'prestige.balance', 'prestige', 'balance', 'price_1Uf5I1K5j4r4WkVPDvIUmRD9', 399600, 'one_time', null),
  ('test', 1, 'maintenance.monthly', null, 'maintenance', 'price_1Uf5I2K5j4r4WkVPJodSnaBe', 9900, 'recurring', 'month');

create function private.current_catalog_version() returns smallint
language sql immutable set search_path = '' as $$ select 1::smallint; $$;

-- The resolved, verified prices for one package in this environment, or no row when any
-- price is missing or its expected amount differs from the package pricing (04 §7: a
-- mismatch blocks Checkout and final-balance invoice creation; T-PAY-12).
create function private.verified_package_prices(p_package_key text)
returns table (deposit_price_id text, balance_price_id text, maintenance_price_id text,
               deposit_cents integer, balance_cents integer, total_cents integer, catalog_version smallint)
language sql stable security definer set search_path = '' as $$
  select d.price_id, b.price_id, m.price_id, p.deposit_cents, p.balance_cents, p.total_cents,
         private.current_catalog_version()
  from private.billing_packages p
  join private.stripe_catalog_prices d on d.environment = private.stripe_mode()
    and d.catalog_version = private.current_catalog_version()
    and d.package_key = p.package_key and d.component = 'deposit'
  join private.stripe_catalog_prices b on b.environment = d.environment
    and b.catalog_version = d.catalog_version and b.package_key = p.package_key and b.component = 'balance'
  join private.stripe_catalog_prices m on m.environment = d.environment
    and m.catalog_version = d.catalog_version and m.component = 'maintenance'
  where p.package_key = p_package_key
    and d.expected_unit_amount = p.deposit_cents
    and b.expected_unit_amount = p.balance_cents
    and m.expected_unit_amount = private.maintenance_monthly_cents()
    and d.currency = 'usd' and b.currency = 'usd' and m.currency = 'usd';
$$;

-- ---------------------------------------------------------------------------
-- 4. Order summaries (04 §4): immutable price and scope snapshots
-- ---------------------------------------------------------------------------
create type public.order_summary_status as enum ('presented', 'superseded');

create table public.order_summaries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  revision integer not null,
  agreement_version_id uuid not null references public.agreement_versions (id),
  agreement_text_sha256 text not null,
  package_key text not null references private.billing_packages (package_key),
  package_total_cents integer not null,
  deposit_cents integer not null,
  balance_cents integer not null,
  maintenance_monthly_cents integer not null,
  currency text not null default 'usd',
  catalog_environment text not null,
  catalog_version smallint not null,
  deposit_price_id text not null,
  balance_price_id text not null,
  maintenance_price_id text not null,
  scope_items jsonb not null default '[]'::jsonb,
  project_notes text,
  business_legal_name text not null,
  snapshot_sha256 text not null,
  status public.order_summary_status not null default 'presented',
  supersedes_id uuid references public.order_summaries (id),
  change_reason text,
  issued_by uuid not null references public.profiles (id),
  issued_at timestamptz not null default now(),
  superseded_at timestamptz,
  unique (project_id, revision),
  constraint order_summaries_revision check (revision >= 1),
  constraint order_summaries_cents check (
    package_total_cents > 0 and deposit_cents > 0 and balance_cents >= 0
    and deposit_cents + balance_cents = package_total_cents
    and deposit_cents = (package_total_cents * 20 + 50) / 100),
  constraint order_summaries_maintenance check (maintenance_monthly_cents = 9900),
  constraint order_summaries_currency check (currency = 'usd'),
  constraint order_summaries_scope check (
    jsonb_typeof(scope_items) = 'array' and jsonb_array_length(scope_items) <= 50
    and octet_length(scope_items::text) <= 8192),
  constraint order_summaries_notes_bounded check (project_notes is null or char_length(project_notes) <= 2000),
  constraint order_summaries_reason_bounded check (change_reason is null or char_length(change_reason) <= 1000),
  constraint order_summaries_name_bounded check (char_length(business_legal_name) between 1 and 200),
  constraint order_summaries_hash_format check (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  constraint order_summaries_superseded_shape check ((status = 'superseded') = (superseded_at is not null))
);
create unique index order_summaries_one_presented on public.order_summaries (project_id)
  where status = 'presented';
create index order_summaries_project_idx on public.order_summaries (project_id, revision);

-- The canonical snapshot whose hash is stored and re-verified at acceptance. jsonb output
-- is deterministic (keys are stored sorted), so the hash is reproducible.
create function private.order_summary_snapshot(p public.order_summaries) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'order_summary_id', p.id, 'project_id', p.project_id, 'revision', p.revision,
    'agreement_version_id', p.agreement_version_id, 'agreement_text_sha256', p.agreement_text_sha256,
    'package_key', p.package_key, 'package_total_cents', p.package_total_cents,
    'deposit_cents', p.deposit_cents, 'balance_cents', p.balance_cents,
    'maintenance_monthly_cents', p.maintenance_monthly_cents, 'currency', p.currency,
    'catalog_environment', p.catalog_environment, 'catalog_version', p.catalog_version,
    'deposit_price_id', p.deposit_price_id, 'balance_price_id', p.balance_price_id,
    'maintenance_price_id', p.maintenance_price_id, 'scope_items', p.scope_items,
    'project_notes', p.project_notes, 'business_legal_name', p.business_legal_name);
$$;

create function private.order_summaries_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'order summaries are never deleted' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.snapshot_sha256 := private.sha256_hex(private.order_summary_snapshot(new)::text);
    return new;
  end if;
  -- The only change ever allowed: presented -> superseded.
  if (to_jsonb(new) - 'status' - 'superseded_at') is distinct from (to_jsonb(old) - 'status' - 'superseded_at')
     or not (old.status = 'presented' and new.status = 'superseded') then
    raise exception 'order summaries are immutable snapshots (04 §4)' using errcode = '42501';
  end if;
  new.superseded_at := now();
  return new;
end;
$$;
create trigger order_summaries_guard
  before insert or update or delete on public.order_summaries
  for each row execute function private.order_summaries_guard();

-- ---------------------------------------------------------------------------
-- 5. Acceptance evidence (04 §3; OI-28, OI-34)
-- ---------------------------------------------------------------------------
create table public.agreement_acceptances (
  id uuid primary key default gen_random_uuid(),
  order_summary_id uuid not null unique references public.order_summaries (id),
  project_id uuid not null references public.projects (id),
  agreement_version_id uuid not null references public.agreement_versions (id),
  agreement_text_sha256 text not null,
  order_summary_sha256 text not null,
  price_snapshot jsonb not null,
  signer_user_id uuid not null references public.profiles (id),
  signer_verified_email text not null,
  signer_full_legal_name text not null,
  business_legal_name text not null,
  business_name_matches boolean not null,
  signer_title text not null,
  accepted boolean not null,
  authority_confirmed boolean not null,
  checkbox_unchecked_by_default boolean not null,
  includes_final_payment_clause boolean not null,
  accepted_at timestamptz not null default now(),
  ip text,
  user_agent text,
  request_id text,
  constraint agreement_acceptances_explicit check (
    accepted and authority_confirmed and checkbox_unchecked_by_default and includes_final_payment_clause),
  constraint agreement_acceptances_names check (
    char_length(signer_full_legal_name) between 1 and 200 and char_length(business_legal_name) between 1 and 200
    and char_length(signer_title) between 1 and 200 and char_length(signer_verified_email) between 3 and 320),
  constraint agreement_acceptances_meta_bounded check (
    (ip is null or char_length(ip) <= 100) and (user_agent is null or char_length(user_agent) <= 300)
    and (request_id is null or char_length(request_id) <= 100)),
  constraint agreement_acceptances_snapshot check (jsonb_typeof(price_snapshot) = 'object')
);
create index agreement_acceptances_project_idx on public.agreement_acceptances (project_id);

create function private.insert_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception '% is insert-only', tg_table_name using errcode = '42501';
end;
$$;
create trigger agreement_acceptances_insert_only
  before update or delete on public.agreement_acceptances
  for each row execute function private.insert_only();

-- Business-name matching rule [PROPOSED, 04 §3]: case-insensitive, whitespace-collapsed.
-- A mismatch is recorded and flagged for staff review; it does not invent a match.
create function private.normalized_name(p_name text) returns text
language sql immutable set search_path = '' as $$
  select lower(btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g')));
$$;

-- Active client members of a project (notification recipients).
create function private.project_client_user_ids(p_project_id uuid) returns uuid[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(m.user_id order by m.user_id), '{}')
  from public.project_memberships m join public.profiles p on p.id = m.user_id
  where m.project_id = p_project_id and m.status = 'active' and p.status = 'active';
$$;

-- ---------------------------------------------------------------------------
-- 6. Registered WP-B domain event types (01 §7). WP-B rows only.
-- ---------------------------------------------------------------------------
insert into private.domain_event_types (event_type, domain, owner_package, description) values
  ('agreement.effective', 'agreement', 'WP-B', 'The accepted agreement became effective on verified deposit'),
  ('agreement.reacceptance_required', 'agreement', 'WP-B', 'A material change superseded an effective acceptance'),
  ('order_summary.issued', 'agreement', 'WP-B', 'Staff issued an order summary snapshot for a project'),
  ('payment.balance_due', 'payment', 'WP-B', 'Client approval made the final balance due and created its obligation'),
  ('payment.balance_invoice_opened', 'payment', 'WP-B', 'The final-balance invoice is open on its Stripe-hosted page'),
  ('payment.balance_verified', 'payment', 'WP-B', 'The final balance was verified from a signature-verified Stripe event'),
  ('payment.balance_failed', 'payment', 'WP-B', 'A final-balance payment failed or needs authentication'),
  ('payment.hold_placed', 'payment', 'WP-B', 'A WP-B billing hold was placed'),
  ('payment.hold_cleared', 'payment', 'WP-B', 'A WP-B billing hold was cleared'),
  ('payment.refund_recorded', 'payment', 'WP-B', 'A Stripe refund was recorded in the ledger'),
  ('payment.dispute_opened', 'payment', 'WP-B', 'A Stripe dispute was opened'),
  ('payment.dispute_closed', 'payment', 'WP-B', 'A Stripe dispute was closed'),
  ('subscription.status_changed', 'subscription', 'WP-B', 'The mirrored Stripe subscription status changed'),
  ('subscription.payment_failed', 'subscription', 'WP-B', 'A maintenance renewal failed and recovery started'),
  ('subscription.payment_recovered', 'subscription', 'WP-B', 'A failed maintenance renewal was paid'),
  ('subscription.cancellation_exception', 'subscription', 'WP-B', 'Stripe deleted a subscription with no authorized termination'),
  ('subscription.cancellation_requested', 'subscription', 'WP-B', 'A client requested cancellation'),
  ('subscription.termination_authorized', 'subscription', 'WP-B', 'The Owner authorized a documented service termination'),
  ('subscription.termination_effective', 'subscription', 'WP-B', 'A service termination reached its effective cancellation date');

-- ---------------------------------------------------------------------------
-- 7. Workflows: issue an order summary (staff), accept the agreement (client)
-- ---------------------------------------------------------------------------
-- 03 §4 "Prepare order summary": Owner and Admin, at aal2 in a live session. A new summary
-- for a project supersedes the presented one (a material change, 04 §4).
create function private.issue_order_summary(
  p_project_id uuid,
  p_package_key text,
  p_scope_items jsonb default '[]'::jsonb,
  p_project_notes text default null,
  p_change_reason text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_project public.projects%rowtype;
  v_legal_name text;
  v_version_id uuid;
  v_version_hash text;
  v_prices record;
  v_current public.order_summaries%rowtype;
  v_paid_summary public.order_summaries%rowtype;
  v_revision integer;
  v_id uuid;
  v_effective_acceptance boolean := false;
  v_event bigint;
begin
  if not (private.is_staff() and private.is_aal2() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  select * into v_project from public.projects where id = p_project_id and archived_at is null for update;
  if not found then
    return private.fail('project_not_found');
  end if;
  if p_scope_items is null or jsonb_typeof(p_scope_items) <> 'array'
     or exists (select 1 from jsonb_array_elements(p_scope_items) e
                where jsonb_typeof(e) <> 'string' or char_length(e #>> '{}') not between 1 and 300) then
    return private.fail('invalid_input');
  end if;
  select legal_name into v_legal_name from public.client_businesses where id = v_project.client_business_id;

  select v.id, v.text_sha256 into v_version_id, v_version_hash
  from public.agreement_versions v
  where private.agreement_version_usable(v.id)
  order by v.effective_from desc, v.created_at desc
  limit 1;
  if v_version_id is null then
    return private.fail('no_usable_agreement_version');
  end if;

  select * into v_prices from private.verified_package_prices(p_package_key);
  if not found then
    perform private.record_audit_event('order_summary.catalog_mismatch', 'project', p_project_id::text,
      p_project_id, null, jsonb_build_object('package_key', left(p_package_key, 40)), 'general');
    return private.fail('catalog_mismatch');
  end if;

  -- OI-81 (approved, R1): once the deposit is verified, the agreed price is fixed. A new
  -- summary whose total, deposit, or balance differs from the order summary accepted with
  -- the verified deposit is rejected and audited.
  select os.* into v_paid_summary from public.order_summaries os
   where os.id = (select l.order_summary_id from public.ledger_entries l
                   where l.project_id = p_project_id and l.entry_type = 'deposit_charge' order by l.id limit 1);
  if v_paid_summary.id is not null
     and (v_paid_summary.package_total_cents, v_paid_summary.deposit_cents, v_paid_summary.balance_cents)
         is distinct from (v_prices.total_cents, v_prices.deposit_cents, v_prices.balance_cents) then
    perform private.record_audit_event('order_summary.price_change_rejected', 'project', p_project_id::text,
      p_project_id, p_change_reason,
      jsonb_build_object('accepted_order_summary_id', v_paid_summary.id, 'requested_package_key', left(p_package_key, 40)),
      'general');
    return private.fail('price_change_after_deposit');
  end if;

  select * into v_current from public.order_summaries
   where project_id = p_project_id and status = 'presented' for update;
  if found then
    if nullif(btrim(coalesce(p_change_reason, '')), '') is null then
      return private.fail('reason_required');
    end if;
    v_effective_acceptance := private.project_deposit_ever_verified(p_project_id)
      and exists (select 1 from public.agreement_acceptances a where a.order_summary_id = v_current.id);
    update public.order_summaries set status = 'superseded' where id = v_current.id;
    perform private.record_audit_event('order_summary.superseded', 'order_summary', v_current.id::text,
      p_project_id, p_change_reason, '{}'::jsonb, 'general');
  end if;

  select coalesce(max(revision), 0) + 1 into v_revision from public.order_summaries where project_id = p_project_id;
  insert into public.order_summaries (
    project_id, revision, agreement_version_id, agreement_text_sha256, package_key, package_total_cents,
    deposit_cents, balance_cents, maintenance_monthly_cents, catalog_environment, catalog_version,
    deposit_price_id, balance_price_id, maintenance_price_id, scope_items, project_notes,
    business_legal_name, snapshot_sha256, supersedes_id, change_reason, issued_by)
  values (
    p_project_id, v_revision, v_version_id, v_version_hash, p_package_key, v_prices.total_cents,
    v_prices.deposit_cents, v_prices.balance_cents, private.maintenance_monthly_cents(), private.stripe_mode(),
    v_prices.catalog_version, v_prices.deposit_price_id, v_prices.balance_price_id, v_prices.maintenance_price_id,
    p_scope_items, nullif(btrim(coalesce(p_project_notes, '')), ''), v_legal_name, repeat('0', 64),
    v_current.id, nullif(btrim(coalesce(p_change_reason, '')), ''), v_uid)
  returning id into v_id;

  perform private.record_audit_event('order_summary.issued', 'order_summary', v_id::text, p_project_id,
    p_change_reason, jsonb_build_object('revision', v_revision, 'package_key', p_package_key), 'general');
  v_event := private.emit_domain_event('order_summary.issued', p_project_id, 'order_summary', v_id::text,
    jsonb_build_object('revision', v_revision, 'supersedes_id', v_current.id),
    'order_summary.issued:' || v_id::text);
  if v_effective_acceptance then
    perform private.record_audit_event('agreement.reacceptance_required', 'order_summary', v_id::text,
      p_project_id, p_change_reason, '{}'::jsonb, 'general');
    v_event := private.emit_domain_event('agreement.reacceptance_required', p_project_id, 'order_summary',
      v_id::text, jsonb_build_object('superseded_order_summary_id', v_current.id),
      'agreement.reacceptance_required:' || v_id::text);
    perform private.enqueue_notification('agreement.reacceptance_required',
      'agreement.reacceptance_required:' || v_id::text || ':1', 'agreement.reacceptance_required', 1,
      p_project_id, v_event, private.project_client_user_ids(p_project_id), '{owner}',
      jsonb_build_object('order_summary_id', v_id), 'general');
  end if;
  return jsonb_build_object('ok', true, 'order_summary_id', v_id, 'revision', v_revision);
exception
  when check_violation or invalid_text_representation then
    return private.fail('invalid_input');
end;
$$;

-- 03 §4 "Accept agreement": a client member who is the authorized signer. Staff cannot
-- accept on a client's behalf (T-AGR-05, T-ROLE-04). Explicit booleans only (T-AGR-01,
-- T-AGR-06). One acceptance per order summary; a resubmission by the same signer returns
-- the existing record (04 §3 idempotency).
create function private.accept_agreement(
  p_order_summary_id uuid,
  p_accepted boolean,
  p_authority_confirmed boolean,
  p_signer_full_legal_name text,
  p_business_legal_name text,
  p_signer_title text,
  p_checkbox_unchecked_by_default boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_summary public.order_summaries%rowtype;
  v_version public.agreement_versions%rowtype;
  v_existing public.agreement_acceptances%rowtype;
  v_email text;
  v_id uuid;
  v_event bigint;
begin
  if v_uid is null or private.staff_role_of(v_uid) is not null or not private.is_active_user()
     or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  select * into v_summary from public.order_summaries where id = p_order_summary_id for update;
  if not found or not private.is_project_member(v_summary.project_id) then
    return private.fail('not_found');
  end if;
  if p_accepted is not true or p_authority_confirmed is not true or p_checkbox_unchecked_by_default is not true then
    return private.fail('explicit_acceptance_required');
  end if;
  if nullif(btrim(coalesce(p_signer_full_legal_name, '')), '') is null
     or nullif(btrim(coalesce(p_business_legal_name, '')), '') is null
     or nullif(btrim(coalesce(p_signer_title, '')), '') is null then
    return private.fail('signer_details_required');
  end if;

  select * into v_existing from public.agreement_acceptances where order_summary_id = v_summary.id;
  if found then
    if v_existing.signer_user_id = v_uid then
      return jsonb_build_object('ok', true, 'acceptance_id', v_existing.id, 'existing', true);
    end if;
    return private.fail('already_accepted');
  end if;
  if v_summary.status <> 'presented' then
    return private.fail('order_summary_superseded');
  end if;

  select * into v_version from public.agreement_versions where id = v_summary.agreement_version_id;
  if v_summary.snapshot_sha256 <> private.sha256_hex(private.order_summary_snapshot(v_summary)::text)
     or v_version.text_sha256 <> v_summary.agreement_text_sha256
     or not private.agreement_version_hash_ok(v_version.id) then
    perform private.record_audit_event('agreement.hash_mismatch', 'order_summary', v_summary.id::text,
      v_summary.project_id, null, '{}'::jsonb, 'general');
    return private.fail('hash_mismatch');
  end if;
  if not private.agreement_version_usable(v_version.id) then
    return private.fail('agreement_version_not_usable');
  end if;

  select lower(u.email) into v_email from auth.users u
   where u.id = v_uid and u.email_confirmed_at is not null;
  if v_email is null then
    return private.fail('email_not_verified');
  end if;

  insert into public.agreement_acceptances (
    order_summary_id, project_id, agreement_version_id, agreement_text_sha256, order_summary_sha256,
    price_snapshot, signer_user_id, signer_verified_email, signer_full_legal_name, business_legal_name,
    business_name_matches, signer_title, accepted, authority_confirmed, checkbox_unchecked_by_default,
    includes_final_payment_clause, ip, user_agent, request_id)
  values (
    v_summary.id, v_summary.project_id, v_version.id, v_version.text_sha256, v_summary.snapshot_sha256,
    jsonb_build_object('package_key', v_summary.package_key, 'package_total_cents', v_summary.package_total_cents,
      'deposit_cents', v_summary.deposit_cents, 'balance_cents', v_summary.balance_cents,
      'maintenance_monthly_cents', v_summary.maintenance_monthly_cents, 'currency', v_summary.currency),
    v_uid, v_email, btrim(p_signer_full_legal_name), btrim(p_business_legal_name),
    private.normalized_name(p_business_legal_name) = private.normalized_name(v_summary.business_legal_name),
    btrim(p_signer_title), true, true, true, v_version.contains_final_payment_clause,
    left(coalesce(private.request_header('x-client-ip'), private.request_header('x-forwarded-for')), 100),
    left(private.request_header('user-agent'), 300), left(private.request_header('x-request-id'), 100))
  returning id into v_id;

  perform private.record_audit_event('agreement.accepted', 'agreement_acceptance', v_id::text,
    v_summary.project_id, null,
    jsonb_build_object('order_summary_id', v_summary.id, 'agreement_version_id', v_version.id,
      'agreement_text_sha256', v_version.text_sha256), 'general');
  v_event := private.emit_domain_event('agreement.accepted', v_summary.project_id, 'agreement_acceptance',
    v_id::text, jsonb_build_object('order_summary_id', v_summary.id, 'agreement_version_id', v_version.id),
    'agreement.accepted:' || v_id::text);
  perform private.enqueue_notification('agreement.accepted', 'agreement.accepted:' || v_id::text || ':1',
    'agreement.accepted', 1, v_summary.project_id, v_event,
    private.project_client_user_ids(v_summary.project_id), '{owner}',
    jsonb_build_object('acceptance_id', v_id), 'general');

  -- Re-acceptance after a non-price material change: the deposit is already verified, so
  -- the new acceptance is effective at once (04 §1 reacceptance_required -> effective).
  if private.project_deposit_ever_verified(v_summary.project_id) then
    perform private.mark_agreement_effective(v_id);
  end if;
  return jsonb_build_object('ok', true, 'acceptance_id', v_id, 'existing', false);
exception
  when unique_violation then
    select * into v_existing from public.agreement_acceptances where order_summary_id = p_order_summary_id;
    if v_existing.signer_user_id = v_uid then
      return jsonb_build_object('ok', true, 'acceptance_id', v_existing.id, 'existing', true);
    end if;
    return private.fail('already_accepted');
  when check_violation or invalid_text_representation then
    return private.fail('invalid_input');
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. RLS, grants, wrappers
-- ---------------------------------------------------------------------------
alter table public.agreement_versions enable row level security;
alter table public.order_summaries enable row level security;
alter table public.agreement_acceptances enable row level security;

revoke all on table public.agreement_versions, public.order_summaries, public.agreement_acceptances
  from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.agreement_versions, public.order_summaries, public.agreement_acceptances from service_role;
grant select on table public.agreement_versions, public.order_summaries to authenticated;
-- Signer network metadata is evidence for the Owner (dispute packages), not for display.
grant select (id, order_summary_id, project_id, agreement_version_id, agreement_text_sha256,
  order_summary_sha256, price_snapshot, signer_user_id, signer_verified_email, signer_full_legal_name,
  business_legal_name, business_name_matches, signer_title, accepted, authority_confirmed,
  checkbox_unchecked_by_default, includes_final_payment_clause, accepted_at)
  on public.agreement_acceptances to authenticated;

-- 03 §4 "View agreement and order summary": Owner, Admin, and members of the project.
create policy agreement_versions_select on public.agreement_versions for select to authenticated
  using ((select private.is_staff()) or exists (
    select 1 from public.order_summaries os
    where os.agreement_version_id = agreement_versions.id and private.is_project_member(os.project_id)));
create policy order_summaries_select on public.order_summaries for select to authenticated
  using ((select private.is_staff()) or private.is_project_member(project_id));
create policy agreement_acceptances_select on public.agreement_acceptances for select to authenticated
  using ((select private.is_staff()) or private.is_project_member(project_id));

do $$
declare
  t text;
begin
  foreach t in array array['agreement_versions', 'order_summaries', 'agreement_acceptances'] loop
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated
         using (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))
         with check (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))',
      t || '_staff_aal2', t);
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated
         using ((select private.is_active_user())) with check ((select private.is_active_user()))',
      t || '_active_user', t);
  end loop;
end;
$$;

create function public.issue_order_summary(p_project_id uuid, p_package_key text,
  p_scope_items jsonb default '[]'::jsonb, p_project_notes text default null, p_change_reason text default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.issue_order_summary(p_project_id, p_package_key, p_scope_items, p_project_notes, p_change_reason);
$$;
create function public.accept_agreement(p_order_summary_id uuid, p_accepted boolean, p_authority_confirmed boolean,
  p_signer_full_legal_name text, p_business_legal_name text, p_signer_title text,
  p_checkbox_unchecked_by_default boolean)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.accept_agreement(p_order_summary_id, p_accepted, p_authority_confirmed,
    p_signer_full_legal_name, p_business_legal_name, p_signer_title, p_checkbox_unchecked_by_default);
$$;
create function public.create_agreement_version(p_version_label text, p_canonical_text text,
  p_effective_from date, p_approval_reference text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.create_agreement_version(p_version_label, p_canonical_text, p_effective_from, p_approval_reference);
$$;
create function public.approve_agreement_version(p_version_id uuid)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.approve_agreement_version(p_version_id);
$$;

revoke all on function
  private.app_environment(), private.is_production(), private.stripe_mode(),
  private.canonical_text(text), private.sha256_hex(text), private.final_payment_clause(),
  private.test_fixture_label(), private.agreement_versions_guard(), private.agreement_version_hash_ok(uuid),
  private.agreement_version_usable(uuid), private.install_test_agreement_fixture(),
  private.create_agreement_version(text, text, date, text), private.approve_agreement_version(uuid),
  private.maintenance_monthly_cents(), private.current_catalog_version(), private.verified_package_prices(text),
  private.order_summary_snapshot(public.order_summaries), private.order_summaries_guard(), private.insert_only(),
  private.normalized_name(text), private.project_client_user_ids(uuid),
  private.issue_order_summary(uuid, text, jsonb, text, text),
  private.accept_agreement(uuid, boolean, boolean, text, text, text, boolean),
  public.issue_order_summary(uuid, text, jsonb, text, text),
  public.accept_agreement(uuid, boolean, boolean, text, text, text, boolean),
  public.create_agreement_version(text, text, date, text), public.approve_agreement_version(uuid)
from public, anon, authenticated, service_role;

grant execute on function
  private.issue_order_summary(uuid, text, jsonb, text, text),
  private.accept_agreement(uuid, boolean, boolean, text, text, text, boolean),
  private.create_agreement_version(text, text, date, text), private.approve_agreement_version(uuid),
  public.issue_order_summary(uuid, text, jsonb, text, text),
  public.accept_agreement(uuid, boolean, boolean, text, text, text, boolean),
  public.create_agreement_version(text, text, date, text), public.approve_agreement_version(uuid)
to authenticated;
