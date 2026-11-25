-- WP-H (AUTH-006), OI-86: lock-order deadlock between issue_order_summary and accept_agreement.
-- Decision: OI-86 (Owner, 2026-11-25; mandatory R1 release-candidate blocker). Authorization:
-- AUTH-006, existing object (1). Handoff: docs/R1-HANDOFFS.md §1 item 1.
--
-- The current definition (20261125120100 §10) is reproduced byte for byte, except the project
-- row lock: `for update` becomes `for no key update`.
--
-- Why this removes the deadlock: accept_agreement locks the order-summary row, then inserts an
-- acceptance whose foreign key takes FOR KEY SHARE on the project row. FOR UPDATE conflicts with
-- FOR KEY SHARE (opposite lock order, so PostgreSQL aborted one side with 40P01); FOR NO KEY
-- UPDATE does not, so the acceptance proceeds and the two calls serialize on the order-summary
-- row lock alone, which decides the race exactly as before (OI-84(c)).
--
-- What it keeps: FOR NO KEY UPDATE still conflicts with FOR UPDATE, FOR NO KEY UPDATE and FOR
-- SHARE, so issuance still serializes with end_sales_assignment, assign_sales_representative,
-- begin_initial_checkout and begin_payment_method_recovery (FOR UPDATE) and with
-- create_invitation and revoke_invitation (FOR SHARE), and with itself. No column the lock
-- protects is a key: issue_order_summary never updates the projects row.
--
-- Financial analysis: only foreign-key inserts into project child tables (FOR KEY SHARE) stop
-- waiting for issuance. The deposit path (handle_checkout_session, mark_deposit_verified) takes
-- no project lock; under FOR UPDATE its ledger insert only waited and then posted. Any
-- interleaving now is equivalent to a serial order that was already possible (deposit before
-- issuance: the OI-81 price lock sees it; deposit after issuance: unchanged behavior), so the
-- OI-81 price lock and every other rule hold unchanged.
--
-- Forward-only (T-MIG-02); the merged 20261125120100 is not edited. Signature, owner and grants
-- are unchanged (CREATE OR REPLACE keeps them).

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
  if v_sales then
    -- OI-84(b): the representative supplies only the package key and a change reason.
    if p_scope_items is not null and p_scope_items <> '[]'::jsonb then
      perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
        p_project_id, null, jsonb_build_object('reason', 'scope_input'), 'general');
      return private.fail('scope_not_allowed');
    end if;
    if p_project_notes is not null then
      perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
        p_project_id, null, jsonb_build_object('reason', 'notes_input'), 'general');
      return private.fail('notes_not_allowed');
    end if;
    select coalesce(jsonb_agg(to_jsonb(s.item_text) order by s.item_position), '[]'::jsonb), max(s.scope_version)
      into p_scope_items, v_scope_version
      from private.current_package_scope(p_package_key) s;
    if v_scope_version is null then
      perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
        p_project_id, null, jsonb_build_object('reason', 'missing_scope_definition'), 'general');
      return private.fail('scope_definition_missing');
    end if;
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
    business_legal_name, snapshot_sha256, supersedes_id, change_reason, issued_by)
  values (
    p_project_id, v_revision, v_version_id, v_version_hash, p_package_key, v_prices.total_cents,
    v_prices.deposit_cents, v_prices.balance_cents, private.maintenance_monthly_cents(), private.stripe_mode(),
    v_prices.catalog_version, v_prices.deposit_price_id, v_prices.balance_price_id, v_prices.maintenance_price_id,
    p_scope_items, nullif(btrim(coalesce(p_project_notes, '')), ''), v_legal_name, repeat('0', 64),
    v_current.id, nullif(btrim(coalesce(p_change_reason, '')), ''), v_uid)
  returning id into v_id;

  perform private.record_audit_event('order_summary.issued', 'order_summary', v_id::text, p_project_id,
    p_change_reason, jsonb_build_object('revision', v_revision, 'package_key', p_package_key)
      || case when v_sales then jsonb_build_object('scope_version', v_scope_version) else '{}'::jsonb end,
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
