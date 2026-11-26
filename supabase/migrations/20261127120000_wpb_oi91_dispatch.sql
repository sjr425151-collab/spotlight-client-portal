-- WP-B (AUTH-009): OI-91 dispatch ownership, confirmation and lock order. Decisions: OI-91,
-- OI-92(e); Owner design decisions of 2026-11-25 and the grant of 2026-11-26 (AUTHORIZATIONS
-- AUTH-009: interface A1 to A3, lock order, privileges, engineering defaults).
--
-- States of an outbound request: claimed (atomic claim; a random token whose SHA-256 is stored
-- set-once in claim_token_sha256, the plaintext returned once to the claiming executor) ->
-- confirmed (dispatch_confirmed_at, set once, reported as confirmed only to the call that set
-- it) -> send attempted (not observable here) -> recorded -> reconciled. A matching token
-- proves executor ownership, never that Stripe executed anything. Confirmation is necessary,
-- not sufficient: every recorded validation, ownership, deadline and eligibility check stays.
--
-- Recording (R1) checks, in order: pending, token, livemode (the abort is unchanged),
-- confirmation. An unconfirmed result, and a success recorded after the late-result boundary
-- (claimed_at + 6 minutes), is recorded `ambiguous` with its submitted evidence and no domain
-- effect; Owner reconciliation decides. Payment, settlement and publication eligibility come
-- only from verified webhooks, unchanged.
--
-- Lock hierarchy: payment authorization (the project's rows, id order), then final-balance
-- invoice, then outbound request, in outbound_request_for_execution, confirm_outbound_dispatch,
-- record_outbound_result, reconcile_outbound_request, handle_invoice_failed and
-- handle_final_balance_paid. Revocation and detachment already lock the authorization, then
-- the invoice (halt_automatic_collection). Requests for other purposes lock only their row.
--
-- Migration compatibility: no token backfill and no fabricated ownership. A request claimed
-- before this migration has no token hash; it can be neither confirmed nor recorded through
-- the token path, and goes through the existing stale rule to `ambiguous` and Owner
-- reconciliation. No automatic replay.
--
-- Engineering defaults (approved 2026-11-25, not production-validated): confirmation window
-- 5 minutes after the claim; send deadline 30 seconds (enforced by the executor from the start
-- of its confirmation call; send_by is returned as an outer bound); late-result boundary
-- 6 minutes; stale threshold 10 minutes (unchanged); lock timeout 5 seconds on the four
-- dispatch functions (a function-level setting; the webhook handlers keep the session's).
--
-- PENDING (Owner rulings requested 2026-11-26, AUTH-009 S1 and S2): the Owner-only controlled
-- stop retry and its wrapper, and the audit action for a rejected claim token. Neither is
-- implemented here; this migration must not merge until both are resolved.
-- Forward-only (T-MIG-02); merged migrations are not edited.

-- ---------------------------------------------------------------------------
-- 1. The two set-once columns and the guard
-- ---------------------------------------------------------------------------
alter table public.outbound_stripe_requests
  add column claim_token_sha256 text,
  add column dispatch_confirmed_at timestamptz,
  add constraint outbound_claim_token_format check (claim_token_sha256 is null or claim_token_sha256 ~ '^[0-9a-f]{64}$'),
  add constraint outbound_confirmation_claimed check (
    dispatch_confirmed_at is null or (claimed_at is not null and claim_token_sha256 is not null));

-- The merged guard with the two set-once columns added: the token hash is set only by the
-- claim itself (never backfilled onto an earlier claim), and confirmation only on a claimed,
-- token-bearing request that is still pending.
create or replace function private.outbound_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'outbound Stripe requests are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.purpose, new.project_id, new.domain_record_type, new.domain_record_id, new.attempt,
      new.idempotency_key, new.request_params, new.created_at)
     is distinct from
     (old.id, old.purpose, old.project_id, old.domain_record_type, old.domain_record_id, old.attempt,
      old.idempotency_key, old.request_params, old.created_at)
     or not private.set_once(old.stripe_object_id, new.stripe_object_id)
     or not private.set_once(old.claimed_at::text, new.claimed_at::text)
     or not private.set_once(old.claim_token_sha256, new.claim_token_sha256)
     or not private.set_once(old.dispatch_confirmed_at::text, new.dispatch_confirmed_at::text) then
    raise exception 'outbound Stripe request identity is immutable' using errcode = '42501';
  end if;
  if (old.claim_token_sha256 is null and new.claim_token_sha256 is not null
      and not (old.claimed_at is null and new.claimed_at is not null))
     or (old.dispatch_confirmed_at is null and new.dispatch_confirmed_at is not null
      and not (old.status = 'pending' and new.status = 'pending' and old.claim_token_sha256 is not null)) then
    raise exception 'outbound Stripe request ownership is set only by its claim and confirmation' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'pending' and new.status in ('succeeded', 'failed', 'ambiguous'))
    or (old.status = 'ambiguous' and new.status in ('reconciled_present', 'reconciled_absent'))
    -- B1: a failed automatic-collection stop is reconciled by the Owner against Stripe.
    or (old.status = 'failed' and new.status in ('reconciled_present', 'reconciled_absent')
        and old.purpose = 'final_balance_invoice_disable_auto' and coalesce(old.error_code, '') <> 'already_paid')) then
    raise exception 'invalid outbound request transition % -> %', old.status, new.status using errcode = '23514';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. OI-92(e): withdrawal or supersession of the originating release after initiation
-- ---------------------------------------------------------------------------
-- Read-only detection through WP-C's current_release semantics (the latest release, none when
-- the latest is withdrawn). One deduplicated Owner notification per invoice; the obligation
-- stands and nothing else changes. Takes no lock, so it never enters the release lock order.
create function private.note_final_balance_release_change(p_final_balance_invoice_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_withdrawn timestamptz;
  v_reason text;
begin
  select * into v_fbi from public.final_balance_invoices where id = p_final_balance_invoice_id;
  if not found then
    return null;
  end if;
  select r.withdrawn_at into v_withdrawn from public.preview_releases r where r.id = v_fbi.release_id;
  if v_withdrawn is not null then
    v_reason := 'withdrawn';
  elsif (select r.id from private.current_release(v_fbi.project_id) r) is distinct from v_fbi.release_id then
    v_reason := 'superseded';
  end if;
  if v_reason is not null then
    perform private.notify_owner('final_balance.release_changed', 'final_balance.release_changed:' || v_fbi.id::text || ':1',
      v_fbi.project_id, null, jsonb_build_object('final_balance_invoice_id', v_fbi.id, 'release_id', v_fbi.release_id,
        'reason', v_reason));
  end if;
  return v_reason;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The claim (A2): lock order, and a one-time claim token
-- ---------------------------------------------------------------------------
-- The merged definition with the lock order changed (the authorizations before the invoice,
-- the claim update last), the claim token added, and OI-92(e) detection after a successful
-- final-balance claim. The supersession and already-paid rules are unchanged.
create or replace function private.outbound_request_for_execution(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
  v_customer text;
  v_fbi public.final_balance_invoices%rowtype;
  v_auth public.payment_authorizations%rowtype;
  v_next uuid;
  v_token uuid;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id;
  if not found or v_req.status <> 'pending' then
    return private.fail('not_pending');
  end if;
  -- AUTH-009 lock hierarchy: the project's payment authorizations (id order), then the invoice;
  -- the outbound row is locked last, by the claim update.
  if v_req.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto') then
    perform 1 from public.payment_authorizations where project_id = v_req.project_id order by id for update;
    select * into v_fbi from public.final_balance_invoices where id = v_req.domain_record_id for update;
    select * into v_auth from public.payment_authorizations where project_id = v_req.project_id and status <> 'revoked';
  end if;
  -- 04 §10, §8.1 (OI-74): an automatic charge is sent only while the authorization is still
  -- active with the same card. A request that no longer qualifies is replaced, before it is
  -- ever sent, by a hosted-only attempt on the same single invoice record.
  if v_req.purpose = 'final_balance_invoice_create' then
    if v_req.request_params -> 'auto_advance' = 'true'::jsonb and (
         v_fbi.collection_mode <> 'automatic' or v_auth.id is distinct from v_fbi.payment_authorization_id
         or v_auth.status is distinct from 'active'
         or v_auth.stripe_payment_method_id is distinct from (v_req.request_params ->> 'default_payment_method')) then
      update public.outbound_stripe_requests set status = 'failed', error_code = 'authorization_changed', completed_at = now()
       where id = v_req.id and status = 'pending' and claimed_at is null;
      if not found then
        return private.fail('already_claimed');
      end if;
      if v_fbi.collection_mode = 'automatic' then
        update public.final_balance_invoices set collection_mode = 'hosted_only', automatic_stop_required = true,
          halt_cause = coalesce(halt_cause, 'authorization_changed')
         where id = v_fbi.id returning * into v_fbi;
      end if;
      v_next := private.new_outbound_request('final_balance_invoice_create', v_fbi.project_id, 'final_balance_invoice',
        v_fbi.id, 'wpb-final-balance-' || v_fbi.order_summary_id::text || '-' || v_fbi.approval_id::text,
        private.final_balance_invoice_params(v_fbi, 'hosted_only'));
      perform private.audit_financial('balance.automatic_collection_superseded', 'final_balance_invoice', v_fbi.id::text,
        v_fbi.project_id, jsonb_build_object('superseded_request_id', v_req.id, 'hosted_request_id', v_next));
      return jsonb_build_object('ok', false, 'error', 'superseded', 'next_request_id', v_next);
    end if;
  end if;
  if v_req.purpose = 'final_balance_invoice_disable_auto' then
    if v_fbi.status = 'paid' then
      update public.outbound_stripe_requests set status = 'failed', error_code = 'already_paid', completed_at = now()
       where id = v_req.id and status = 'pending' and claimed_at is null;
      return private.fail('not_needed');
    end if;
  end if;
  if v_req.purpose in ('checkout_session_create', 'final_balance_invoice_create', 'recovery_session_create') then
    select c.stripe_customer_id into v_customer from public.stripe_customers c
      join public.projects p on p.client_business_id = c.client_business_id where p.id = v_req.project_id;
    if v_customer is null then
      return private.fail('customer_missing');
    end if;
  end if;
  -- A2: the plaintext token exists only in this result; only its SHA-256 is stored. Never logged.
  v_token := gen_random_uuid();
  update public.outbound_stripe_requests
     set claimed_at = now(), claim_token_sha256 = encode(sha256(convert_to(v_token::text, 'UTF8')), 'hex')
   where id = v_req.id and status = 'pending' and claimed_at is null;
  if not found then
    return private.fail('already_claimed');
  end if;
  if v_req.purpose = 'final_balance_invoice_create' then
    perform private.note_final_balance_release_change(v_fbi.id);
  end if;
  return jsonb_build_object('ok', true, 'id', v_req.id, 'purpose', v_req.purpose,
    'idempotency_key', v_req.idempotency_key, 'params', v_req.request_params, 'customer', v_customer,
    'expected_livemode', private.expected_livemode(), 'claim_token', v_token);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Dispatch confirmation (A3): set once, immediately before the provider request
-- ---------------------------------------------------------------------------
-- Server (secret key) only. Confirms that the claiming executor is about to send, within the
-- confirmation window, after re-checking the claim's eligibility under the same locks. The
-- executor may start the provider request only within 30 seconds of starting this call, and
-- never after send_by. A repeated, late or mismatched confirmation never authorizes a send.
create function private.confirm_outbound_dispatch(p_request_id uuid, p_claim_token uuid) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
  v_fbi public.final_balance_invoices%rowtype;
  v_auth public.payment_authorizations%rowtype;
  v_next uuid;
  v_at timestamptz;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id;
  if not found then
    return private.fail('not_pending');
  end if;
  -- Lock hierarchy: authorizations, invoice, then the outbound row; other purposes lock only the row.
  if v_req.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto') then
    perform 1 from public.payment_authorizations where project_id = v_req.project_id order by id for update;
    select * into v_fbi from public.final_balance_invoices where id = v_req.domain_record_id for update;
    select * into v_auth from public.payment_authorizations where project_id = v_req.project_id and status <> 'revoked';
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id for update;
  if v_req.status <> 'pending' then
    return private.fail('not_pending');
  end if;
  if v_req.claimed_at is null then
    return private.fail('not_claimed');
  end if;
  if v_req.claim_token_sha256 is null then
    return private.fail('legacy_claim');
  end if;
  if p_claim_token is null or encode(sha256(convert_to(p_claim_token::text, 'UTF8')), 'hex') <> v_req.claim_token_sha256 then
    perform private.notify_owner('outbound.claim_token_rejected', 'outbound.claim_token_rejected:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id, 'operation', 'confirm'));
    -- PENDING (AUTH-009 S2, Owner ruling): the audit event for a rejected claim token.
    return private.fail('claim_token_mismatch');
  end if;
  if v_req.dispatch_confirmed_at is not null then
    return private.fail('already_confirmed');
  end if;
  if v_req.claimed_at < now() - interval '5 minutes' then
    return private.fail('confirmation_window_expired');
  end if;
  -- Revocation or detachment committed after the claim: the automatic create is never sent and
  -- is replaced deterministically by the hosted-only attempt, exactly as at claim time.
  if v_req.purpose = 'final_balance_invoice_create' and v_req.request_params -> 'auto_advance' = 'true'::jsonb and (
       v_fbi.collection_mode <> 'automatic' or v_auth.id is distinct from v_fbi.payment_authorization_id
       or v_auth.status is distinct from 'active'
       or v_auth.stripe_payment_method_id is distinct from (v_req.request_params ->> 'default_payment_method')) then
    update public.outbound_stripe_requests set status = 'failed', error_code = 'authorization_changed', completed_at = now()
     where id = v_req.id;
    if v_fbi.collection_mode = 'automatic' then
      update public.final_balance_invoices set collection_mode = 'hosted_only', automatic_stop_required = true,
        halt_cause = coalesce(halt_cause, 'authorization_changed')
       where id = v_fbi.id returning * into v_fbi;
    end if;
    v_next := private.new_outbound_request('final_balance_invoice_create', v_fbi.project_id, 'final_balance_invoice',
      v_fbi.id, 'wpb-final-balance-' || v_fbi.order_summary_id::text || '-' || v_fbi.approval_id::text,
      private.final_balance_invoice_params(v_fbi, 'hosted_only'));
    perform private.audit_financial('balance.automatic_collection_superseded', 'final_balance_invoice', v_fbi.id::text,
      v_fbi.project_id, jsonb_build_object('superseded_request_id', v_req.id, 'hosted_request_id', v_next));
    return jsonb_build_object('ok', false, 'error', 'superseded', 'next_request_id', v_next);
  end if;
  if v_req.purpose = 'final_balance_invoice_disable_auto' and v_fbi.status = 'paid' then
    update public.outbound_stripe_requests set status = 'failed', error_code = 'already_paid', completed_at = now()
     where id = v_req.id;
    return private.fail('not_needed');
  end if;
  update public.outbound_stripe_requests set dispatch_confirmed_at = now()
   where id = v_req.id and dispatch_confirmed_at is null
  returning dispatch_confirmed_at into v_at;
  return jsonb_build_object('ok', true, 'confirmed', true, 'dispatch_confirmed_at', v_at,
    'send_by', v_at + interval '30 seconds');
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Recording (A1, R1): the claim token is the second parameter
-- ---------------------------------------------------------------------------
drop function public.record_outbound_result(uuid, text, text, boolean, integer, text, jsonb);
drop function private.record_outbound_result(uuid, text, text, boolean, integer, text, jsonb);

-- Server (secret key) only: records the outcome of a Stripe request. The merged domain effects
-- are unchanged and apply only to a confirmed result recorded in time.
create function private.record_outbound_result(p_request_id uuid, p_claim_token uuid, p_outcome text,
  p_stripe_object_id text, p_livemode boolean, p_http_status integer, p_error_code text,
  p_details jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
  v_fbi public.final_balance_invoices%rowtype;
  v_token_ok boolean;
  v_reason text;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id;
  if not found then
    return private.fail('not_pending');
  end if;
  -- Lock hierarchy: authorizations, invoice, then the outbound row; other purposes lock only the row.
  if v_req.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto') then
    perform 1 from public.payment_authorizations where project_id = v_req.project_id order by id for update;
    perform 1 from public.final_balance_invoices where id = v_req.domain_record_id for update;
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id for update;
  v_token_ok := v_req.claim_token_sha256 is not null and p_claim_token is not null
    and encode(sha256(convert_to(p_claim_token::text, 'UTF8')), 'hex') = v_req.claim_token_sha256;
  -- 1. Pending. An identical resubmission of the recorded result (a lost response) returns the
  -- stored outcome: it applies nothing and never authorizes another provider request.
  if v_req.status <> 'pending' then
    if v_token_ok and v_req.completed_at is not null and v_req.reconciled_at is null
       and v_req.http_status is not distinct from p_http_status
       and v_req.livemode is not distinct from p_livemode
       and ((v_req.status::text = p_outcome and v_req.stripe_object_id is not distinct from p_stripe_object_id
             and v_req.error_code is not distinct from left(p_error_code, 100))
         or (v_req.status = 'ambiguous' and v_req.error_code in ('unconfirmed_dispatch', 'late_result')
             and v_req.stripe_object_id is not distinct from p_stripe_object_id)
         or (v_req.status = 'ambiguous' and v_req.error_code = 'livemode_mismatch' and p_outcome = 'succeeded')) then
      return jsonb_build_object('ok', true, 'status', v_req.status, 'replayed', true);
    end if;
    return private.fail('not_pending');
  end if;
  -- 2. Token: only the claiming executor records. A request claimed before AUTH-009 has no token
  -- and goes through the stale rule.
  if v_req.claim_token_sha256 is null then
    return private.fail(case when v_req.claimed_at is null then 'not_claimed' else 'legacy_claim' end);
  end if;
  if not v_token_ok then
    perform private.notify_owner('outbound.claim_token_rejected', 'outbound.claim_token_rejected:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id, 'operation', 'record'));
    -- PENDING (AUTH-009 S2, Owner ruling): the audit event for a rejected claim token.
    return private.fail('claim_token_mismatch');
  end if;
  if p_outcome not in ('succeeded', 'failed', 'ambiguous') or (p_outcome = 'succeeded' and p_stripe_object_id is null) then
    return private.fail('invalid_input');
  end if;
  -- 3. Livemode: the abort is unchanged (CLAUDE.md §4).
  if p_outcome = 'succeeded' and p_livemode is distinct from private.expected_livemode() then
    update public.outbound_stripe_requests set status = 'ambiguous', livemode = p_livemode, http_status = p_http_status,
      error_code = 'livemode_mismatch', completed_at = now() where id = v_req.id;
    perform private.audit_financial('outbound.livemode_mismatch', 'outbound_stripe_request', v_req.id::text, v_req.project_id);
    perform private.notify_owner('outbound.livemode_mismatch', 'outbound.livemode_mismatch:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id));
    return private.fail('livemode_mismatch');
  end if;
  -- 4. Confirmation, and the outer late-result boundary for a success.
  if v_req.dispatch_confirmed_at is null then
    v_reason := 'unconfirmed_dispatch';
  elsif p_outcome = 'succeeded' and now() > v_req.claimed_at + interval '6 minutes' then
    v_reason := 'late_result';
  end if;
  if v_reason is not null then
    update public.outbound_stripe_requests
       set status = 'ambiguous', stripe_object_id = p_stripe_object_id, livemode = p_livemode, http_status = p_http_status,
           error_code = v_reason, completed_at = now()
     where id = v_req.id;
    perform private.audit_financial('outbound.request_ambiguous', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
      jsonb_build_object('purpose', v_req.purpose, 'reason', v_reason, 'submitted_outcome', p_outcome,
        'submitted_error_code', left(p_error_code, 100)));
    perform private.notify_owner('outbound.request_ambiguous', 'outbound.request_ambiguous:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id));
    return jsonb_build_object('ok', true, 'status', 'ambiguous', 'reason', v_reason);
  end if;

  update public.outbound_stripe_requests
     set status = p_outcome::public.outbound_request_status, stripe_object_id = p_stripe_object_id,
         livemode = p_livemode, http_status = p_http_status, error_code = left(p_error_code, 100), completed_at = now()
   where id = v_req.id;

  if p_outcome = 'succeeded' then
    perform private.apply_outbound_success(v_req, p_stripe_object_id, p_livemode, coalesce(p_details, '{}'::jsonb));
  elsif p_outcome = 'failed' then
    if v_req.purpose = 'checkout_session_create' then
      update public.checkout_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
    elsif v_req.purpose = 'recovery_session_create' then
      update public.recovery_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
    elsif v_req.purpose = 'final_balance_invoice_disable_auto' then
      perform private.notify_owner('payment.automatic_stop_failed', 'payment.automatic_stop_failed:' || v_req.id::text || ':1',
        v_req.project_id, null, jsonb_build_object('final_balance_invoice_id', v_req.domain_record_id));
    elsif v_req.purpose = 'final_balance_invoice_create' then
      update public.final_balance_invoices set status = 'creation_failed'
       where id = v_req.domain_record_id and status = 'creating' returning * into v_fbi;
      perform private.notify_owner('payment.final_invoice_creation_failed',
        'payment.final_invoice_creation_failed:' || v_req.id::text || ':1', v_req.project_id, null,
        jsonb_build_object('final_balance_invoice_id', v_req.domain_record_id));
    end if;
    perform private.audit_financial('outbound.request_failed', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
      jsonb_build_object('purpose', v_req.purpose, 'http_status', p_http_status));
  else
    perform private.audit_financial('outbound.request_ambiguous', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
      jsonb_build_object('purpose', v_req.purpose));
    perform private.notify_owner('outbound.request_ambiguous', 'outbound.request_ambiguous:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id));
  end if;
  return jsonb_build_object('ok', true, 'status', p_outcome);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Owner reconciliation: lock order only
-- ---------------------------------------------------------------------------
-- The merged definition with the lock hierarchy applied; the Owner, fresh-MFA and live-session
-- check and every rule are unchanged. It keeps its grant to authenticated (AUTH-009 grant).
create or replace function private.reconcile_outbound_request(p_request_id uuid, p_found boolean, p_stripe_object_id text, p_note text)
returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null or p_found is null then
    return private.fail('reason_required');
  end if;
  -- AUTH-009 lock hierarchy: authorizations, invoice, then the outbound row.
  select * into v_req from public.outbound_stripe_requests where id = p_request_id;
  if found and v_req.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto') then
    perform 1 from public.payment_authorizations where project_id = v_req.project_id order by id for update;
    perform 1 from public.final_balance_invoices where id = v_req.domain_record_id for update;
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id for update;
  -- B1: a failed automatic-collection stop (other than already_paid) is reconciled the same
  -- way: found = Stripe shows automatic collection off on that invoice.
  if not found or not (v_req.status = 'ambiguous'
       or (v_req.status = 'failed' and v_req.purpose = 'final_balance_invoice_disable_auto'
           and coalesce(v_req.error_code, '') <> 'already_paid')) then
    return private.fail('not_ambiguous');
  end if;
  if p_found and coalesce(v_req.error_code, '') = 'livemode_mismatch' then
    return private.fail('livemode_mismatch');
  end if;
  update public.outbound_stripe_requests
     set status = case when p_found then 'reconciled_present'::public.outbound_request_status else 'reconciled_absent'::public.outbound_request_status end,
         stripe_object_id = case when p_found then p_stripe_object_id else stripe_object_id end,
         reconciled_by = (select auth.uid()), reconciled_at = now(), reconcile_note = btrim(p_note)
   where id = v_req.id;
  if p_found then
    perform private.apply_outbound_success(v_req, p_stripe_object_id, private.expected_livemode(), '{}'::jsonb);
  elsif v_req.purpose = 'checkout_session_create' then
    update public.checkout_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
  elsif v_req.purpose = 'final_balance_invoice_create' then
    update public.final_balance_invoices set status = 'creation_failed' where id = v_req.domain_record_id and status = 'creating';
  elsif v_req.purpose = 'recovery_session_create' then
    update public.recovery_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
  end if;
  perform private.audit_financial('outbound.request_reconciled', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
    jsonb_build_object('found', p_found, 'gates', private.financial_gate_recheck(v_req.project_id)), p_note);
  return jsonb_build_object('ok', true, 'gates', private.financial_gate_recheck(v_req.project_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Invoice webhooks, project reconciliation and anomalies: the merged definitions with the
--    lock hierarchy, the OI-92(e) detection and the stop-specific anomaly added
-- ---------------------------------------------------------------------------
create or replace function private.handle_final_balance_paid(e public.webhook_events, inv jsonb, p_fbi_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_entry bigint;
  v_event bigint;
  v_key text;
begin
  -- AUTH-009 lock hierarchy: the project's payment authorizations (id order), then the invoice.
  perform 1 from public.payment_authorizations
   where project_id = (select f.project_id from public.final_balance_invoices f where f.id = p_fbi_id)
   order by id for update;
  select * into v_fbi from public.final_balance_invoices where id = p_fbi_id for update;
  update public.webhook_events set project_id = v_fbi.project_id where id = e.id;
  if (inv #>> '{metadata,final_balance_invoice_id}') is distinct from v_fbi.id::text
     or (inv #>> '{metadata,project_id}') is distinct from v_fbi.project_id::text
     or (inv #>> '{metadata,order_summary_id}') is distinct from v_fbi.order_summary_id::text
     or (v_fbi.stripe_invoice_id is not null and v_fbi.stripe_invoice_id <> inv ->> 'id') then
    return 'quarantined:metadata_mismatch';
  end if;
  if (inv ->> 'customer') is distinct from v_fbi.stripe_customer_id or inv ->> 'currency' is distinct from 'usd' then
    return 'quarantined:customer_or_currency_mismatch';
  end if;
  if private.invoice_price_ids(inv) <> array[v_fbi.balance_price_id] or not private.invoice_line_quantities_ok(inv) then
    return 'quarantined:line_items_mismatch';
  end if;
  if private.invoice_discount_cents(inv) <> 0 or coalesce((inv ->> 'tax')::bigint, 0) <> 0 then
    return 'quarantined:discount_or_tax_present';
  end if;
  -- The charged amount equals the authorized snapshot balance (T-PAY-26).
  if (inv ->> 'amount_paid')::bigint is distinct from v_fbi.amount_cents then
    return 'quarantined:amount_mismatch';
  end if;
  -- An invoice created for automatic collection must still name the authorization's card;
  -- any other card, or none, is quarantined (T-PAY-26, fail closed).
  if v_fbi.default_payment_method_id is not null
     and (inv ->> 'default_payment_method') is distinct from v_fbi.default_payment_method_id then
    return 'quarantined:payment_method_mismatch';
  end if;
  perform private.link_payment_refs(v_fbi.project_id, 'final_balance', v_fbi.id, inv);
  update public.final_balance_invoices
     set status = 'paid', paid_at = coalesce(paid_at, now()), stripe_invoice_id = coalesce(stripe_invoice_id, inv ->> 'id'),
         hosted_invoice_url = coalesce(hosted_invoice_url, case when inv ->> 'hosted_invoice_url' ~ '^https://invoice\.stripe\.com/' then inv ->> 'hosted_invoice_url' end),
         charged_after_halt = charged_after_halt or coalesce(halt_cause in ('revoked', 'payment_method_detached'), false),
         last_event_created = greatest(coalesce(last_event_created, e.stripe_created_at), e.stripe_created_at)
   where id = v_fbi.id and status <> 'paid';
  v_key := 'final_balance:' || v_fbi.id::text;
  v_entry := private.post_ledger_entry(v_fbi.project_id, v_fbi.order_summary_id, 'balance_charge', v_fbi.amount_cents,
    'development', e.id, 'invoice', inv ->> 'id', inv ->> 'id', null, null, v_key || ':balance');
  perform private.create_obligation(v_fbi.project_id, v_fbi.order_summary_id, 'development_balance', v_key, v_key || ':balance');
  if v_entry is not null then
    v_event := private.emit_domain_event('payment.balance_verified', v_fbi.project_id, 'final_balance_invoice',
      v_fbi.id::text, jsonb_build_object('order_summary_id', v_fbi.order_summary_id),
      'payment.balance_verified:' || v_fbi.id::text);
    perform private.audit_financial('balance.charge_succeeded', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id,
      jsonb_build_object('approval_id', v_fbi.approval_id, 'amount_cents', v_fbi.amount_cents,
        'collection_mode', v_fbi.collection_mode));
    perform private.enqueue_notification('payment.final_verified', 'payment.final_verified:' || v_fbi.id::text || ':1',
      'payment.final_verified', 1, v_fbi.project_id, v_event, private.project_client_user_ids(v_fbi.project_id),
      '{owner,admin}', jsonb_build_object('project_id', v_fbi.project_id), 'general');
    -- Stripe is authoritative for money: a payment that landed after automatic collection
    -- was halted (revocation or detached card) is verified, and goes to Owner review.
    if v_fbi.halt_cause in ('revoked', 'payment_method_detached') then
      if v_fbi.payment_authorization_id is not null then
        perform private.record_authorization_event(v_fbi.payment_authorization_id, 'charged_after_halt',
          (select status from public.payment_authorizations where id = v_fbi.payment_authorization_id),
          (select status from public.payment_authorizations where id = v_fbi.payment_authorization_id), null, e.id, null);
      end if;
      perform private.notify_owner('payment.charged_after_halt', 'payment.charged_after_halt:' || v_fbi.id::text || ':1',
        v_fbi.project_id, v_event, jsonb_build_object('final_balance_invoice_id', v_fbi.id));
      -- B1: G4 stays blocked until the Owner reviews this item (resolve_reconciliation_mismatch).
      insert into public.reconciliation_mismatches (project_id, kind, charge_key, observed_cents)
      values (v_fbi.project_id, 'charged_after_halt', v_key, v_fbi.amount_cents)
      on conflict (charge_key) where kind = 'charged_after_halt' do nothing;
      perform private.audit_financial('balance.charged_after_halt', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id);
    end if;
  end if;
  return 'processed';
end;
$$;
create or replace function private.handle_invoice_failed(e public.webhook_events, inv jsonb, p_action_required boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_sub text := private.invoice_subscription_id(inv);
  v_project uuid;
  v_rec uuid;
  v_t0 timestamptz;
  v_event bigint;
begin
  select * into v_fbi from public.final_balance_invoices
   where stripe_invoice_id = inv ->> 'id' or id = private.try_uuid(inv #>> '{metadata,final_balance_invoice_id}')
   limit 1;
  if found then
    -- AUTH-009 lock hierarchy: the project's payment authorizations (id order), then the invoice.
    perform 1 from public.payment_authorizations where project_id = v_fbi.project_id order by id for update;
    select * into v_fbi from public.final_balance_invoices where id = v_fbi.id for update;
    update public.webhook_events set project_id = v_fbi.project_id where id = e.id;
    if (inv #>> '{metadata,final_balance_invoice_id}') is distinct from v_fbi.id::text then
      return 'quarantined:metadata_mismatch';
    end if;
    -- Stale events never move the balance backwards (T-ARC-03).
    if v_fbi.status in ('paid', 'void') or (v_fbi.last_event_created is not null and e.stripe_created_at < v_fbi.last_event_created) then
      return 'ignored';
    end if;
    update public.final_balance_invoices
       set status = case when p_action_required then 'action_required'::public.final_balance_invoice_status
                         else 'payment_failed'::public.final_balance_invoice_status end,
           stripe_invoice_id = coalesce(stripe_invoice_id, inv ->> 'id'),
           hosted_invoice_url = coalesce(hosted_invoice_url, case when inv ->> 'hosted_invoice_url' ~ '^https://invoice\.stripe\.com/' then inv ->> 'hosted_invoice_url' end),
           last_event_created = e.stripe_created_at
     where id = v_fbi.id;
    v_event := private.emit_domain_event('payment.balance_failed', v_fbi.project_id, 'final_balance_invoice', v_fbi.id::text,
      jsonb_build_object('action_required', p_action_required), 'payment.balance_failed:' || e.stripe_event_id);
    -- A failed automatic charge (04 §8.1 "When"): the card is unavailable for automatic use and
    -- recovery is offered; this invoice is completed on its hosted page (T-PAY-14). A failure
    -- on the hosted page of a hosted-only invoice says nothing about the authorization's card.
    if not p_action_required and v_fbi.collection_mode = 'automatic' then
      update public.payment_authorizations set status = 'payment_method_unavailable'
       where project_id = v_fbi.project_id and status = 'active';
      if found then
        perform private.record_authorization_event((select id from public.payment_authorizations
            where project_id = v_fbi.project_id and status = 'payment_method_unavailable'),
          'unavailable', 'active', 'payment_method_unavailable', null, e.id, 'final_balance_charge_failed');
        perform private.audit_financial('payment_authorization.unavailable', 'final_balance_invoice', v_fbi.id::text,
          v_fbi.project_id, jsonb_build_object('cause', 'invoice.payment_failed'));
      end if;
      -- No automatic retry without an active authorization (04 §8.1 invariant 14).
      perform private.halt_automatic_collection(v_fbi.project_id, 'charge_failed');
    end if;
    perform private.audit_financial(case when p_action_required then 'balance.action_required' else 'balance.charge_failed' end,
      'final_balance_invoice', v_fbi.id::text, v_fbi.project_id, jsonb_build_object('stripe_event_id', e.stripe_event_id));
    perform private.enqueue_notification('payment.final_action_required',
      'payment.final_action_required:' || e.stripe_event_id || ':1', 'payment.final_action_required', 1,
      v_fbi.project_id, v_event, private.project_client_user_ids(v_fbi.project_id), '{}',
      jsonb_build_object('project_id', v_fbi.project_id), 'general');
    return 'processed';
  end if;

  if p_action_required or inv ->> 'billing_reason' is distinct from 'subscription_cycle' then
    return 'ignored';
  end if;
  select project_id into v_project from public.subscriptions where stripe_subscription_id = v_sub;
  if v_project is null then
    v_project := (select p.id from public.projects p where p.id = private.try_uuid(private.invoice_subscription_metadata(inv) ->> 'project_id'));
  end if;
  if v_project is null then
    return 'deferred';
  end if;
  update public.webhook_events set project_id = v_project where id = e.id;
  if exists (select 1 from public.ledger_entries where dedupe_key = 'invoice:' || (inv ->> 'id') || ':maintenance') then
    return 'ignored';
  end if;
  -- OI-26: T0 is Stripe's failure time; recovery ends 23:59:59 America/Detroit on the 7th
  -- calendar day after T0's local date (02 §13.2).
  v_t0 := e.stripe_created_at;
  insert into public.maintenance_recoveries (project_id, stripe_invoice_id, stripe_subscription_id, failed_at,
    recovery_ends_at, calendar_version)
  values (v_project, inv ->> 'id', v_sub, v_t0, private.end_of_local_day(private.local_date(v_t0) + 7),
    private.calendar_version())
  on conflict (stripe_invoice_id) do nothing
  returning id into v_rec;
  if v_rec is not null then
    v_event := private.emit_domain_event('subscription.payment_failed', v_project, 'maintenance_recovery', v_rec::text,
      '{}'::jsonb, 'subscription.payment_failed:' || v_rec::text);
    perform private.audit_financial('maintenance.payment_failed', 'maintenance_recovery', v_rec::text, v_project,
      jsonb_build_object('stripe_invoice_id', inv ->> 'id'));
    perform private.enqueue_notification('billing.maintenance_payment_failed',
      'billing.maintenance_payment_failed:' || v_rec::text || ':1', 'billing.maintenance_payment_failed', 1, v_project,
      v_event, private.project_client_user_ids(v_project), '{owner}', jsonb_build_object('project_id', v_project), 'financial');
  end if;
  return 'processed';
end;
$$;
create or replace function private.record_project_reconciliation(p_run_id uuid, p_project_id uuid, p_stripe jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_charges bigint;
  v_refunds bigint;
  v_os public.order_summaries%rowtype;
  v_deposit bigint;
  v_balance bigint;
  v_fbi_amount bigint;
  v_open bigint;
  v_count integer := 0;
  v_kind text;
  v_expected bigint;
  v_observed bigint;
  v_obj jsonb;
  v_charge_key text;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  if not exists (select 1 from public.reconciliation_runs where id = p_run_id and completed_at is null) then
    raise exception 'unknown or completed reconciliation run' using errcode = '22023';
  end if;
  select coalesce(sum(amount_cents) filter (where entry_type in ('deposit_charge', 'maintenance_charge', 'balance_charge')), 0),
         coalesce(-sum(amount_cents) filter (where entry_type = 'refund'), 0),
         coalesce(sum(amount_cents) filter (where entry_type = 'deposit_charge'), 0),
         coalesce(sum(amount_cents) filter (where entry_type = 'balance_charge'), 0)
    into v_charges, v_refunds, v_deposit, v_balance
  from public.ledger_entries where project_id = p_project_id;
  select count(*) into v_open from public.disputes where project_id = p_project_id and private.dispute_is_open(status);
  select * into v_os from public.order_summaries where project_id = p_project_id and status = 'presented';
  select amount_cents into v_fbi_amount from public.final_balance_invoices where project_id = p_project_id and status = 'paid';

  for v_kind, v_expected, v_observed in
    select 'charges_total', v_charges, (p_stripe ->> 'charges_cents')::bigint
    union all select 'refunds_total', v_refunds, (p_stripe ->> 'refunds_cents')::bigint
    union all select 'disputes_open', v_open, (p_stripe ->> 'open_disputes')::bigint
    union all select 'deposit_snapshot', v_os.deposit_cents::bigint, nullif(v_deposit, 0)
    union all select 'balance_snapshot', v_fbi_amount, nullif(v_balance, 0)
  loop
    if v_kind in ('deposit_snapshot', 'balance_snapshot') and (v_observed is null or v_expected is null) then
      continue;
    end if;
    if v_observed is distinct from v_expected then
      insert into public.reconciliation_mismatches (run_id, project_id, kind, expected_cents, observed_cents)
      values (p_run_id, p_project_id, v_kind, v_expected, v_observed);
      v_count := v_count + 1;
    end if;
  end loop;
  -- B1: every refund and dispute Stripe holds for this customer that WP-B has not recorded
  -- (its event never arrived, was deferred, or could not be attributed) is attributed through
  -- its charge and becomes a blocking item. One item per object state; nothing is posted.
  for v_obj in
    select r || jsonb_build_object('object', 'refund') from jsonb_array_elements(
      case when jsonb_typeof(p_stripe -> 'refunds') = 'array' then p_stripe -> 'refunds' else '[]'::jsonb end) r
    union all
    select d || jsonb_build_object('object', 'dispute') from jsonb_array_elements(
      case when jsonb_typeof(p_stripe -> 'disputes') = 'array' then p_stripe -> 'disputes' else '[]'::jsonb end) d
  loop
    if (v_obj ->> 'object' = 'refund' and exists (select 1 from public.refunds where stripe_refund_id = v_obj ->> 'id'))
       or (v_obj ->> 'object' = 'dispute' and exists (select 1 from public.disputes where stripe_dispute_id = v_obj ->> 'id')) then
      continue;
    end if;
    select case when count(distinct private.link_charge_key(l)) = 1 then min(private.link_charge_key(l)) end
      into v_charge_key
      from private.stripe_payment_links l
     where l.project_id = p_project_id
       and (l.stripe_ref in (v_obj ->> 'charge', v_obj ->> 'payment_intent') or l.stripe_invoice_id = v_obj ->> 'invoice');
    insert into public.reconciliation_mismatches (run_id, project_id, kind, charge_key, stripe_object_id, observed_status,
      observed_cents)
    values (p_run_id, p_project_id, case when v_obj ->> 'object' = 'refund' then 'unmatched_refund' else 'unmatched_dispute' end,
      v_charge_key, v_obj ->> 'id', coalesce(substring(v_obj ->> 'status' from '^[a-z_]{1,40}$'), 'unknown'), private.try_cents(v_obj -> 'amount'))
    on conflict (stripe_object_id, observed_status) where stripe_object_id is not null do nothing;
    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  -- AUTH-009 (OI-92(e)): a release withdrawn or superseded after initiation is notified once;
  -- the obligation stands and nothing else changes.
  perform private.note_final_balance_release_change(f.id) from public.final_balance_invoices f
   where f.project_id = p_project_id and f.status <> 'void';
  update public.reconciliation_runs set projects_checked = projects_checked + 1, mismatch_count = mismatch_count + v_count
   where id = p_run_id;
  if v_count > 0 then
    perform private.audit_financial('reconciliation.mismatch', 'reconciliation_run', p_run_id::text, p_project_id,
      jsonb_build_object('mismatches', v_count));
    perform private.notify_owner('reconciliation.mismatch', 'reconciliation.mismatch:' || p_run_id::text || ':' || p_project_id::text,
      p_project_id, null, jsonb_build_object('run_id', p_run_id));
  end if;
  return v_count;
end;
$$;
create or replace function private.project_financial_anomalies(p_project_id uuid) returns table (kind text, gates text[])
language sql stable security definer set search_path = '' as $$
  -- 1. Quarantined events, attributed through the charge they concern.
  select 'quarantined_event', private.charge_kind_gates(private.event_charge_kinds(w))
    from public.webhook_events w
   where w.project_id = p_project_id and w.processing_status = 'quarantined' and w.quarantine_resolved_at is null
  union all
  -- 2. Open reconciliation items.
  select 'reconciliation_mismatch', case
           when m.kind = 'deposit_snapshot' then array['G2']
           when m.kind in ('balance_snapshot', 'charged_after_halt') then array['G4']
           when m.kind in ('unmatched_refund', 'unmatched_dispute') then private.charge_key_gates(m.charge_key)
           else array['G2', 'G4'] end
    from public.reconciliation_mismatches m
   where m.project_id = p_project_id and m.resolved_at is null
  union all
  -- 3. Ambiguous outbound requests, by the charge their record belongs to.
  select 'ambiguous_request', case
           when o.purpose = 'checkout_session_create' then array['G2']
           when o.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto', 'recovery_session_create')
             then array['G4']
           else array['G2', 'G4'] end
    from public.outbound_stripe_requests o
   where o.project_id = p_project_id and o.status = 'ambiguous'
  union all
  -- 4. A failed automatic-collection stop; already_paid alone is not an anomaly.
  select 'automatic_stop_failed', array['G4']
    from public.outbound_stripe_requests o
   where o.project_id = p_project_id and o.purpose = 'final_balance_invoice_disable_auto' and o.status = 'failed'
     and coalesce(o.error_code, '') <> 'already_paid'
  union all
  -- 5. A charge after halted collection that the Owner has not reviewed (its item resolved).
  select 'charged_after_halt', array['G4']
    from public.final_balance_invoices f
   where f.project_id = p_project_id and f.charged_after_halt
     and not exists (select 1 from public.reconciliation_mismatches m where m.kind = 'charged_after_halt'
                       and m.charge_key = 'final_balance:' || f.id::text and m.resolved_at is not null)
  union all
  -- 6. Reversals Stripe reports that the ledger has not posted.
  select 'unposted_reversal', u.gates from private.unposted_reversals(p_project_id) u
  union all
  -- 7. N1(a) (Amendment 1): an event with conflicting authoritative projects blocks G2 and G4 for
  -- every candidate project, and for any project the event already carried. The Owner's review
  -- never clears it (OI-93); it persists until a separately authorized mechanism exists.
  select 'quarantined_event', array['G2', 'G4']
    from public.webhook_events w
   where exists (select 1 from private.financial_event_project_candidates c where c.webhook_event_id = w.id)
     and (w.project_id = p_project_id
          or exists (select 1 from private.financial_event_project_candidates c
                      where c.webhook_event_id = w.id and c.project_id = p_project_id))
  union all
  -- 8. AUTH-009 (automatic-stop reconciliation): a stop the Owner reconciled as absent did not
  -- establish that automatic collection ceased, so G4 stays blocked, unless verified payment
  -- of that invoice makes further collection impossible. Only this item is cleared by payment.
  select 'automatic_stop_unresolved', array['G4']
    from public.outbound_stripe_requests o
    join public.final_balance_invoices f on f.id = o.domain_record_id
   where o.project_id = p_project_id and o.purpose = 'final_balance_invoice_disable_auto'
     and o.domain_record_type = 'final_balance_invoice' and o.status = 'reconciled_absent' and f.status <> 'paid';
$$;

-- ---------------------------------------------------------------------------
-- 8. Wrappers and privileges: server (secret key) only, as the merged executor functions
-- ---------------------------------------------------------------------------
create function public.confirm_outbound_dispatch(p_request_id uuid, p_claim_token uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.confirm_outbound_dispatch(p_request_id, p_claim_token); $$;
create function public.record_outbound_result(p_request_id uuid, p_claim_token uuid, p_outcome text, p_stripe_object_id text,
  p_livemode boolean, p_http_status integer, p_error_code text, p_details jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_outbound_result(p_request_id, p_claim_token, p_outcome, p_stripe_object_id, p_livemode,
    p_http_status, p_error_code, p_details);
$$;

revoke all on function
  private.note_final_balance_release_change(uuid),
  private.confirm_outbound_dispatch(uuid, uuid), public.confirm_outbound_dispatch(uuid, uuid),
  private.record_outbound_result(uuid, uuid, text, text, boolean, integer, text, jsonb),
  public.record_outbound_result(uuid, uuid, text, text, boolean, integer, text, jsonb)
from public, anon, authenticated, service_role;

grant execute on function
  private.confirm_outbound_dispatch(uuid, uuid), public.confirm_outbound_dispatch(uuid, uuid),
  private.record_outbound_result(uuid, uuid, text, text, boolean, integer, text, jsonb),
  public.record_outbound_result(uuid, uuid, text, text, boolean, integer, text, jsonb)
to service_role;
