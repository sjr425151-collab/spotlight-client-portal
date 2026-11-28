-- AUTH-022 (PWP-2, WP-B): standardized issuance and order snapshot v2.
-- Decisions: OD-1 to OD-19 (Owner, 2026-11-28); 04 §4A v0.11.0 (canonical lock hierarchy, OD-3);
-- OD-13 (freeform scope ends for every R1 catalog order; RPC signature kept; scope and notes inputs
-- rejected and audited); OD-7 and R-05 (newest sealed eligible bundle, no fallback); T-CON-11
-- split (the positive client read path is this migration's).
-- Builds on the frozen PWP-1 interface (AUTH-021, 20261128100000): F1 current_contract_bundle,
-- F2 contract_bundle_verifies, F3 contract_bundle_withdrawn, F4 the per-package lock, F5 the
-- snapshot v2 component identifiers. No AUTH-021 object is changed.
--
-- Lock order (OD-3), every path:
--   issuance:   project row FOR NO KEY UPDATE (OI-86) -> per-package lock shared (resolver)
--               -> presented order-summary row FOR UPDATE -> bundle row FOR SHARE;
--   acceptance: per-package lock shared -> order-summary row FOR UPDATE -> bundle row FOR SHARE
--               -> project row FOR KEY SHARE, implicitly, through the acceptance insert's foreign key.
-- No path holds an order-summary row while waiting for the per-package lock. No payment, invoice,
-- release or Sales lock is added; the financial paths are unchanged (OI-81, OI-86, OI-91 to OI-93).
--
-- v1 is frozen: no backfill and no rehash. Every existing row keeps snapshot_version 1 and its
-- hash; the v1 snapshot expression is unchanged (golden vectors, 196).
-- Never touched: the ledger, payments, invoices, checkout, webhooks, the OI-81 price lock, the
-- OI-86 project lock, the existing OI-87 grants and the Sales rules (T-SALES-19, T-SALES-32).
-- Forward-only (T-MIG-02); no merged migration is edited.

-- ---------------------------------------------------------------------------
-- 1. Snapshot v2 columns (null for every v1 row)
-- ---------------------------------------------------------------------------
alter table public.order_summaries
  add column snapshot_version smallint not null default 1,
  add column contract_bundle_id uuid references private.contract_bundles (id),
  add column contract_bundle_sha256 text,
  add column contract_bundle_canonicalization text,
  add column package_instrument_id uuid,
  add column package_instrument_sha256 text,
  add column maintenance_instrument_id uuid,
  add column maintenance_instrument_sha256 text,
  add column shared_terms_instrument_id uuid,
  add column shared_terms_instrument_sha256 text,
  add column scope_version integer,
  add column scope_content_sha256 text;
alter table public.order_summaries
  add constraint order_summaries_snapshot_version check (snapshot_version in (1, 2)),
  add constraint order_summaries_snapshot_shape check (
    (snapshot_version = 1 and contract_bundle_id is null and contract_bundle_sha256 is null
      and contract_bundle_canonicalization is null and package_instrument_id is null
      and package_instrument_sha256 is null and maintenance_instrument_id is null
      and maintenance_instrument_sha256 is null and shared_terms_instrument_id is null
      and shared_terms_instrument_sha256 is null and scope_version is null and scope_content_sha256 is null)
    or (snapshot_version = 2 and contract_bundle_id is not null
      and contract_bundle_sha256 ~ '^[0-9a-f]{64}$'
      and contract_bundle_canonicalization = 'spotlight.contract_bundle.v1'
      and package_instrument_id is not null and package_instrument_sha256 ~ '^[0-9a-f]{64}$'
      and maintenance_instrument_id is not null and maintenance_instrument_sha256 ~ '^[0-9a-f]{64}$'
      and shared_terms_instrument_id is not null and shared_terms_instrument_sha256 ~ '^[0-9a-f]{64}$'
      and scope_version >= 1 and scope_content_sha256 ~ '^[0-9a-f]{64}$'
      and project_notes is null));
create index order_summaries_bundle_idx on public.order_summaries (contract_bundle_id)
  where contract_bundle_id is not null;

-- ---------------------------------------------------------------------------
-- 2. OI-87 pattern: the new columns are granted explicitly; change_reason stays unreadable.
-- ---------------------------------------------------------------------------
grant select (snapshot_version, contract_bundle_id, contract_bundle_sha256, contract_bundle_canonicalization,
  package_instrument_id, package_instrument_sha256, maintenance_instrument_id, maintenance_instrument_sha256,
  shared_terms_instrument_id, shared_terms_instrument_sha256, scope_version, scope_content_sha256)
  on public.order_summaries to authenticated;
do $$
declare
  v_missing text;
begin
  select string_agg(c.column_name, ', ' order by c.ordinal_position) into v_missing
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'order_summaries' and c.column_name <> 'change_reason'
    and not has_column_privilege('authenticated', 'public.order_summaries', c.column_name, 'select');
  if v_missing is not null then
    raise exception 'OI-87: order_summaries columns not readable by authenticated: %', v_missing;
  end if;
  if has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'select') then
    raise exception 'OI-87: change_reason is still readable by authenticated';
  end if;
  if has_table_privilege('authenticated', 'public.order_summaries', 'insert')
     or has_table_privilege('authenticated', 'public.order_summaries', 'update') then
    raise exception 'OI-87: authenticated may not write order_summaries';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Snapshot v2 (spotlight.order_summary.v2): every v1 contractual field except the notes,
--    plus every F5 bundle and component identifier and hash.
-- ---------------------------------------------------------------------------
create function private.order_summary_snapshot_v2(p public.order_summaries) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'snapshot_canonicalization', 'spotlight.order_summary.v2', 'snapshot_version', 2,
    'order_summary_id', p.id, 'project_id', p.project_id, 'revision', p.revision,
    'agreement_version_id', p.agreement_version_id, 'agreement_text_sha256', p.agreement_text_sha256,
    'package_key', p.package_key, 'package_total_cents', p.package_total_cents,
    'deposit_cents', p.deposit_cents, 'balance_cents', p.balance_cents,
    'maintenance_monthly_cents', p.maintenance_monthly_cents, 'currency', p.currency,
    'catalog_environment', p.catalog_environment, 'catalog_version', p.catalog_version,
    'deposit_price_id', p.deposit_price_id, 'balance_price_id', p.balance_price_id,
    'maintenance_price_id', p.maintenance_price_id, 'scope_items', p.scope_items,
    'business_legal_name', p.business_legal_name,
    'contract_bundle_id', p.contract_bundle_id, 'contract_bundle_sha256', p.contract_bundle_sha256,
    'contract_bundle_canonicalization', p.contract_bundle_canonicalization,
    'package_instrument_id', p.package_instrument_id, 'package_instrument_sha256', p.package_instrument_sha256,
    'maintenance_instrument_id', p.maintenance_instrument_id,
    'maintenance_instrument_sha256', p.maintenance_instrument_sha256,
    'shared_terms_instrument_id', p.shared_terms_instrument_id,
    'shared_terms_instrument_sha256', p.shared_terms_instrument_sha256,
    'scope_version', p.scope_version, 'scope_content_sha256', p.scope_content_sha256);
$$;

-- ---------------------------------------------------------------------------
-- 4. order_summary_snapshot: v1 frozen (the v1 expression below is the merged body verbatim);
--    v2 rows only are hashed with the v2 snapshot.
-- ---------------------------------------------------------------------------
create or replace function private.order_summary_snapshot(p public.order_summaries) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p.snapshot_version = 2 then private.order_summary_snapshot_v2(p) else
  jsonb_build_object(
    'order_summary_id', p.id, 'project_id', p.project_id, 'revision', p.revision,
    'agreement_version_id', p.agreement_version_id, 'agreement_text_sha256', p.agreement_text_sha256,
    'package_key', p.package_key, 'package_total_cents', p.package_total_cents,
    'deposit_cents', p.deposit_cents, 'balance_cents', p.balance_cents,
    'maintenance_monthly_cents', p.maintenance_monthly_cents, 'currency', p.currency,
    'catalog_environment', p.catalog_environment, 'catalog_version', p.catalog_version,
    'deposit_price_id', p.deposit_price_id, 'balance_price_id', p.balance_price_id,
    'maintenance_price_id', p.maintenance_price_id, 'scope_items', p.scope_items,
    'project_notes', p.project_notes, 'business_legal_name', p.business_legal_name) end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Standardized issuance (OD-13, OD-3). Derived from 20261126120000 by insertions only.
-- ---------------------------------------------------------------------------
create or replace function private.issue_order_summary(
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
  v_sales boolean := false;
  v_scope_version integer;
  v_bundle record;
  v_bundle_lock uuid;
begin
  if not (private.is_staff() and private.is_aal2() and private.session_is_active()) then
    -- WP-S: the one added caller, an actively assigned Sales Representative.
    if not private.sales_assigned(p_project_id) then
      return private.fail('forbidden');
    end if;
    v_sales := true;
  end if;
  select * into v_project from public.projects where id = p_project_id and archived_at is null for no key update;
  if not found then
    return private.fail('project_not_found');
  end if;
  -- WP-S: re-read the assignment after the project lock, which end_sales_assignment also
  -- takes, so an assignment that ended concurrently is always seen (no issuance after it).
  if v_sales and not private.sales_assigned(p_project_id) then
    return private.fail('forbidden');
  end if;
  -- AUTH-022 (OD-13): standardized issuance. No role supplies scope or notes: both come from the
  -- sealed bundle. A supplied input is rejected and audited (Sales with its existing action and
  -- reasons, OI-84(b); Owner and Admin as order_summary.input_rejected) and nothing is written.
  if p_scope_items is null then
    return private.fail('invalid_input');
  end if;
  if p_scope_items <> '[]'::jsonb then
    perform private.record_audit_event(
      case when v_sales then 'sales.order_summary_rejected' else 'order_summary.input_rejected' end,
      'project', p_project_id::text, p_project_id, null, jsonb_build_object('reason', 'scope_input'), 'general');
    return private.fail('scope_not_allowed');
  end if;
  if p_project_notes is not null then
    perform private.record_audit_event(
      case when v_sales then 'sales.order_summary_rejected' else 'order_summary.input_rejected' end,
      'project', p_project_id::text, p_project_id, null, jsonb_build_object('reason', 'notes_input'), 'general');
    return private.fail('notes_not_allowed');
  end if;
  -- Sales resolves at the merged Sales-scope position, so its error precedence is unchanged
  -- (T-SALES-36); Owner and Admin resolve after the price checks (110, 400).
  if v_sales then
    -- OD-3: after the project row, the per-package lock shared (taken by the resolver and held to
    -- commit), before any order-summary row. The resolver returns the newest sealed eligible bundle
    -- or nothing, with no fallback (OD-7, R-05).
    select * into v_bundle from private.current_contract_bundle(p_package_key);
    if v_bundle.bundle_id is null then
      perform private.record_audit_event(
        case when v_sales then 'sales.order_summary_rejected' else 'order_summary.bundle_unavailable' end,
        'project', p_project_id::text, p_project_id, null, jsonb_build_object('reason', 'missing_scope_definition'),
        'general');
      return private.fail('scope_definition_missing');
    end if;
    p_scope_items := v_bundle.scope_items;
    v_scope_version := v_bundle.scope_version;
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

  if not v_sales then
    -- OD-3: after the project row, the per-package lock shared (taken by the resolver and held to
    -- commit), before any order-summary row. The resolver returns the newest sealed eligible bundle
    -- or nothing, with no fallback (OD-7, R-05).
    select * into v_bundle from private.current_contract_bundle(p_package_key);
    if v_bundle.bundle_id is null then
      perform private.record_audit_event(
        case when v_sales then 'sales.order_summary_rejected' else 'order_summary.bundle_unavailable' end,
        'project', p_project_id::text, p_project_id, null, jsonb_build_object('reason', 'missing_scope_definition'),
        'general');
      return private.fail('scope_definition_missing');
    end if;
    p_scope_items := v_bundle.scope_items;
    v_scope_version := v_bundle.scope_version;
  end if;
  -- AUTH-022: the governing agreement version is the bundle's (04 §4A), re-checked as usable.
  v_version_id := v_bundle.agreement_version_id;
  v_version_hash := v_bundle.agreement_text_sha256;
  if v_version_id is null or not private.agreement_version_usable(v_version_id) then
    return private.fail('no_usable_agreement_version');
  end if;

  select * into v_current from public.order_summaries
   where project_id = p_project_id and status = 'presented' for update;
  -- AUTH-022 (OD-3 step 5): the bundle row FOR SHARE, then its re-verification (F2, F3).
  -- An assignment, not PERFORM: FOUND must still describe the presented-row lookup above.
  v_bundle_lock := (select b.id from private.contract_bundles b where b.id = v_bundle.bundle_id for share);
  if private.contract_bundle_withdrawn(v_bundle.bundle_id) or private.contract_bundle_verifies(v_bundle.bundle_id) is not true then
    perform private.record_audit_event(
      case when v_sales then 'sales.order_summary_rejected' else 'order_summary.bundle_unavailable' end,
      'project', p_project_id::text, p_project_id, null, jsonb_build_object('reason', 'missing_scope_definition'),
      'general');
    return private.fail('scope_definition_missing');
  end if;
  -- OI-84(c): no Sales replacement once the project has any acceptance or a verified deposit.
  -- Checked after the order-summary row lock that accept_agreement also takes, so a
  -- concurrent acceptance and Sales replacement serialize and never both succeed.
  if v_sales and (
    exists (select 1 from public.agreement_acceptances a where a.project_id = p_project_id)
    or private.project_deposit_ever_verified(p_project_id)
  ) then
    perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
      p_project_id, null, jsonb_build_object('reason', 'after_acceptance'), 'general');
    return private.fail('replacement_after_acceptance');
  end if;
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
    business_legal_name, snapshot_sha256, supersedes_id, change_reason, issued_by,
    snapshot_version, contract_bundle_id, contract_bundle_sha256, contract_bundle_canonicalization,
    package_instrument_id, package_instrument_sha256, maintenance_instrument_id, maintenance_instrument_sha256,
    shared_terms_instrument_id, shared_terms_instrument_sha256, scope_version, scope_content_sha256)
  values (
    p_project_id, v_revision, v_version_id, v_version_hash, p_package_key, v_prices.total_cents,
    v_prices.deposit_cents, v_prices.balance_cents, private.maintenance_monthly_cents(), private.stripe_mode(),
    v_prices.catalog_version, v_prices.deposit_price_id, v_prices.balance_price_id, v_prices.maintenance_price_id,
    p_scope_items, nullif(btrim(coalesce(p_project_notes, '')), ''), v_legal_name, repeat('0', 64),
    v_current.id, nullif(btrim(coalesce(p_change_reason, '')), ''), v_uid,
    2, v_bundle.bundle_id, v_bundle.bundle_sha256, v_bundle.bundle_canonicalization,
    v_bundle.package_instrument_id, v_bundle.package_instrument_sha256, v_bundle.maintenance_instrument_id,
    v_bundle.maintenance_instrument_sha256, v_bundle.shared_terms_instrument_id, v_bundle.shared_terms_instrument_sha256,
    v_bundle.scope_version, v_bundle.scope_content_sha256)
  returning id into v_id;

  perform private.record_audit_event('order_summary.issued', 'order_summary', v_id::text, p_project_id,
    p_change_reason, jsonb_build_object('revision', v_revision, 'package_key', p_package_key)
      || case when v_sales then jsonb_build_object('scope_version', v_scope_version) else '{}'::jsonb end
      || jsonb_build_object('contract_bundle_id', v_bundle.bundle_id),
    'general');
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

-- ---------------------------------------------------------------------------
-- 6. Acceptance (OD-3, R-05). Derived from 20261124160000 by insertions only.
-- ---------------------------------------------------------------------------
create or replace function private.accept_agreement(
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
  v_package_key text;
  v_bundle_sha text;
begin
  if v_uid is null or private.staff_role_of(v_uid) is not null or not private.is_active_user()
     or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  -- AUTH-022 (OD-3): read the package key without a lock, take the per-package lock shared, then
  -- the order-summary row, and re-check the key under the lock. The project row's FOR KEY SHARE is
  -- implicit, through the acceptance insert's foreign key, after the order-summary row (step 1).
  select os.package_key into v_package_key from public.order_summaries os where os.id = p_order_summary_id;
  if v_package_key is not null then
    perform pg_advisory_xact_lock_shared(hashtextextended('dep18-scope-eligibility:' || v_package_key, 0));
  end if;
  select * into v_summary from public.order_summaries where id = p_order_summary_id for update;
  if found and v_summary.package_key is distinct from v_package_key then
    return private.fail('not_found');
  end if;
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
  -- AUTH-022: a v2 summary is acceptable only while its bundle is not withdrawn and re-verifies
  -- (04 §4A eligibility; R-05). The bundle row FOR SHARE (step 5), then F3 and F2 in later
  -- statements. A withdrawal committed first prevents the acceptance; an existing acceptance
  -- (above) is permanent.
  if v_summary.snapshot_version = 2 then
    v_bundle_sha := (select b.bundle_sha256 from private.contract_bundles b
                      where b.id = v_summary.contract_bundle_id for share);
    if private.contract_bundle_withdrawn(v_summary.contract_bundle_id) then
      perform private.record_audit_event('agreement.bundle_rejected', 'order_summary', v_summary.id::text,
        v_summary.project_id, null, jsonb_build_object('reason', 'withdrawn'), 'general');
      return private.fail('bundle_withdrawn');
    end if;
    if private.contract_bundle_verifies(v_summary.contract_bundle_id) is not true
       or v_bundle_sha is distinct from v_summary.contract_bundle_sha256 then
      perform private.record_audit_event('agreement.bundle_rejected', 'order_summary', v_summary.id::text,
        v_summary.project_id, null, jsonb_build_object('reason', 'integrity'), 'general');
      return private.fail('hash_mismatch');
    end if;
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
-- 7. T-CON-11 positive client read path (Main ruling: the PWP-2 half): a client member reads the
--    instruments of its own project's presented or accepted v2 order summary. Owner and Admin
--    (aal2, live session) may read the same. Sales, other tenants and anon read nothing. A
--    fixture bundle is readable only in development and test with a consistent classification.
--    Unreadable and unknown look the same.
-- ---------------------------------------------------------------------------
create function private.order_summary_instruments(p_order_summary_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  s public.order_summaries;
  b private.contract_bundles;
begin
  select * into s from public.order_summaries x where x.id = p_order_summary_id;
  if not found or s.snapshot_version <> 2 then
    return private.fail('not_found');
  end if;
  if not ((private.wpc_is_client_member(s.project_id) is true)
          or (private.is_staff() is true and private.is_aal2() is true and private.session_is_active() is true)) then
    return private.fail('not_found');
  end if;
  if s.status <> 'presented'
     and not exists (select 1 from public.agreement_acceptances a where a.order_summary_id = s.id) then
    return private.fail('not_found');
  end if;
  select * into b from private.contract_bundles x where x.id = s.contract_bundle_id;
  if not found or (b.is_test_fixture and (private.environment_consistent() is not true
                   or private.app_environment() not in ('development', 'test'))) then
    return private.fail('not_found');
  end if;
  return jsonb_build_object('ok', true, 'order_summary_id', s.id, 'bundle_id', b.id, 'package_key', b.package_key,
    'bundle_version', b.bundle_version, 'bundle_sha256', b.bundle_sha256, 'is_test_fixture', b.is_test_fixture,
    'instruments', (select jsonb_agg(jsonb_build_object('kind', i.kind, 'instrument_id', i.id,
        'instrument_version', i.instrument_version, 'title', i.title, 'body', i.body,
        'content_sha256', i.content_sha256, 'is_test_fixture', i.is_test_fixture)
        order by array_position(array['package_specification', 'maintenance_specification', 'shared_terms'], i.kind))
      from private.contract_instrument_versions i
      where i.id in (s.package_instrument_id, s.maintenance_instrument_id, s.shared_terms_instrument_id)));
end;
$$;

create function public.order_summary_instruments(p_order_summary_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.order_summary_instruments(p_order_summary_id);
$$;

-- AUTH-010 I-1 boundary: the private SECURITY DEFINER implementation behind the public INVOKER
-- wrapper is executable by authenticated only; the snapshot helper by no API role.
revoke all on function
  private.order_summary_snapshot_v2(public.order_summaries),
  private.order_summary_instruments(uuid),
  public.order_summary_instruments(uuid)
from public, anon, authenticated, service_role;
grant execute on function
  private.order_summary_instruments(uuid),
  public.order_summary_instruments(uuid)
to authenticated;
