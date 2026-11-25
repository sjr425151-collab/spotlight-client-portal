-- WP-H (AUTH-006 and Amendment 1): the release-approval cross-check before final-balance
-- initiation. Decisions: 04 §10.2 (OI-92, Amendment 1 interface contract). Handoff:
-- docs/R1-HANDOFFS.md §1 item 4, §1A item 2.
--
-- private.consume_release_approved is its current definition (20261124160100) with one block
-- added after the consumption claim and the event-shape check, and before every existing
-- check: WP-C's per-project release advisory lock, the event's release row FOR SHARE, then in
-- fresh statements the eligibility of 04 §10.2: the fulfillment interface implemented at
-- contract version 2 or later; the project not archived; the release not withdrawn and current;
-- the event's approval recorded for that release and project and equal to the release's
-- recorded approval; the payload's release number and commit SHA equal the immutable release;
-- the anomaly-aware G2 passing and no anomaly listed for G4. Then the existing agreement,
-- deposit, catalog, balance, customer, authorization (row lock), and single-flight checks,
-- unchanged. Any failure is `rejected` with a detail, audited, and notified to the Owner, with
-- no obligation and no outbound request (the existing rejection path).
--
-- WP-C analysis: release_preview takes the same advisory lock before inserting a superseding
-- release; approve_preview takes it before recording the approval and emitting
-- release.approved; withdraw_preview locks the release row FOR UPDATE, which conflicts with
-- FOR SHARE. Neither WP-C writer takes the payment-authorization lock or reads WP-B state, so
-- the order is acyclic. No WP-C object changes; no new privilege.
-- Forward-only (T-MIG-02); merged migrations are not edited.

create or replace function private.consume_release_approved(p_domain_event_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_ev public.domain_events%rowtype;
  v_consumer constant text := 'wpb.final_balance_invoice';
  v_inserted integer;
  v_release uuid;
  v_approval uuid;
  v_agreement record;
  v_os public.order_summaries%rowtype;
  v_prices record;
  v_customer text;
  v_fbi public.final_balance_invoices%rowtype;
  v_auth public.payment_authorizations%rowtype;
  v_mode text;
  v_event bigint;
  v_outcome text;
  v_detail text;
  v_rel public.preview_releases%rowtype;
  v_ful private.project_fulfillment_status;
  v_fin private.project_financial_status;
begin
  insert into private.event_consumptions (consumer, domain_event_id) values (v_consumer, p_domain_event_id)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return 'already_consumed';
  end if;
  select * into v_ev from public.domain_events where id = p_domain_event_id;
  v_release := private.try_uuid(v_ev.subject_id);
  v_approval := private.try_uuid(v_ev.payload ->> 'approval_id');

  if v_ev.event_type <> 'release.approved' or v_ev.project_id is null or v_release is null or v_approval is null then
    v_outcome := 'rejected'; v_detail := 'invalid_event';
  else
    -- WP-H release-approval cross-check (04 §10.2; AUTH-006 Amendment 1 interface contract).
    -- Lock order: consumption row (above), WP-C's per-project release lock, the event's release
    -- row FOR SHARE, then (below) the payment authorization. Release creation and approval take
    -- the same advisory lock and withdrawal takes the release row lock, so each either commits
    -- before these checks or waits until this initiation has committed.
    perform pg_advisory_xact_lock(hashtextextended('release:' || v_ev.project_id::text, 0));
    select * into v_rel from public.preview_releases
     where id = v_release and project_id = v_ev.project_id for share;
    if found then
      -- Fresh statements after the locks: read through the WP-0 gate interfaces.
      v_ful := private.project_fulfillment_status(v_ev.project_id);
      v_fin := private.project_financial_status(v_ev.project_id);
    end if;
    if v_rel.id is null then
      v_outcome := 'rejected'; v_detail := 'release_not_found';
    elsif not coalesce(v_ful.implemented, false) or coalesce(v_ful.contract_version, 0) < 2 then
      v_outcome := 'rejected'; v_detail := 'fulfillment_interface_not_ready';
    elsif exists (select 1 from public.projects p where p.id = v_ev.project_id and p.archived_at is not null) then
      v_outcome := 'rejected'; v_detail := 'project_archived';
    elsif v_rel.withdrawn_at is not null then
      v_outcome := 'rejected'; v_detail := 'release_withdrawn';
    elsif v_ful.current_release_id is distinct from v_release then
      v_outcome := 'rejected'; v_detail := 'release_superseded';
    elsif not exists (select 1 from public.preview_approvals a
                       where a.id = v_approval and a.release_id = v_release and a.project_id = v_ev.project_id) then
      v_outcome := 'rejected'; v_detail := 'approval_not_found';
    elsif not coalesce(v_ful.current_release_approved, false) or v_ful.current_release_approval_id is distinct from v_approval then
      v_outcome := 'rejected'; v_detail := 'approval_mismatch';
    elsif (v_ev.payload ->> 'release_number') is distinct from v_rel.release_number::text
       or (v_ev.payload ->> 'commit_sha') is distinct from v_rel.commit_sha then
      v_outcome := 'rejected'; v_detail := 'release_version_mismatch';
    elsif not coalesce(v_fin.deposit_verified, false) then
      v_outcome := 'rejected'; v_detail := 'deposit_gate_blocked'; -- anomaly-aware G2 (OI-92(d))
    elsif coalesce(jsonb_array_length(v_fin.evidence -> 'blocking_anomalies' -> 'G4'), 1) > 0 then
      v_outcome := 'rejected'; v_detail := 'balance_gate_anomaly'; -- an anomaly listed for G4
    end if;
  end if;
  if v_outcome is null and v_detail is null then
    -- The existing eligibility, unchanged.
    select * into v_agreement from private.project_agreement_state(v_ev.project_id);
    if v_agreement.state <> 'effective' then
      v_outcome := 'rejected'; v_detail := 'agreement_not_effective';
    elsif not private.project_deposit_verified(v_ev.project_id) then
      v_outcome := 'rejected'; v_detail := 'deposit_not_verified';
    else
      select * into v_os from public.order_summaries where id = v_agreement.order_summary_id;
      select * into v_prices from private.verified_package_prices(v_os.package_key);
      select c.stripe_customer_id into v_customer from public.stripe_customers c
        join public.projects p on p.client_business_id = c.client_business_id where p.id = v_ev.project_id;
      if v_prices.balance_price_id is null or v_prices.balance_price_id <> v_os.balance_price_id
         or v_prices.balance_cents <> v_os.balance_cents then
        v_outcome := 'rejected'; v_detail := 'catalog_mismatch';
      elsif v_os.balance_cents <= 0 then
        v_outcome := 'rejected'; v_detail := 'no_balance_due';
      elsif v_customer is null then
        v_outcome := 'rejected'; v_detail := 'customer_missing';
      else
        -- 04 §10 (OI-74): automatic only while the authorization is active, decided under the
        -- authorization row lock that revocation and card detachment also take.
        select * into v_auth from public.payment_authorizations
         where project_id = v_ev.project_id and status <> 'revoked' for update;
        v_mode := case when v_auth.status = 'active' then 'automatic' else 'hosted_only' end;
        insert into public.final_balance_invoices (project_id, order_summary_id, acceptance_id, approval_id, release_id,
          source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode,
          payment_authorization_id, default_payment_method_id)
        values (v_ev.project_id, v_os.id, v_agreement.acceptance_id, v_approval, v_release, v_ev.id, v_os.balance_cents,
          v_os.balance_price_id, v_customer, v_mode, v_auth.id,
          case when v_mode = 'automatic' then v_auth.stripe_payment_method_id end)
        on conflict do nothing
        returning * into v_fbi;
        if v_fbi.id is null then
          v_outcome := 'duplicate_obligation'; v_detail := 'obligation_exists';
        else
          v_outcome := 'created';
          perform private.new_outbound_request('final_balance_invoice_create', v_fbi.project_id, 'final_balance_invoice',
            v_fbi.id, 'wpb-final-balance-' || v_os.id::text || '-' || v_approval::text,
            private.final_balance_invoice_params(v_fbi, v_mode));
          v_event := private.emit_domain_event('payment.balance_due', v_fbi.project_id, 'final_balance_invoice', v_fbi.id::text,
            jsonb_build_object('order_summary_id', v_os.id, 'approval_id', v_approval, 'release_id', v_release),
            'payment.balance_due:' || v_fbi.id::text);
          perform private.audit_financial('balance.collection_authorized', 'final_balance_invoice', v_fbi.id::text,
            v_fbi.project_id, jsonb_build_object('approval_id', v_approval, 'release_id', v_release,
              'order_summary_id', v_os.id, 'amount_cents', v_fbi.amount_cents, 'collection_mode', v_mode,
              'payment_consent_id', v_auth.id));
        end if;
      end if;
    end if;
  end if;
  update private.event_consumptions set outcome = v_outcome, detail = v_detail
   where consumer = v_consumer and domain_event_id = p_domain_event_id;
  if v_outcome = 'rejected' then
    perform private.audit_financial('release_approval.rejected', 'domain_event', p_domain_event_id::text, v_ev.project_id,
      jsonb_build_object('detail', v_detail));
    perform private.notify_owner('payment.final_balance_blocked', 'payment.final_balance_blocked:' || p_domain_event_id::text || ':1',
      v_ev.project_id, null, jsonb_build_object('domain_event_id', p_domain_event_id));
  elsif v_outcome = 'duplicate_obligation' then
    perform private.audit_financial('release_approval.duplicate', 'domain_event', p_domain_event_id::text, v_ev.project_id);
  end if;
  return v_outcome;
end;
$$;

