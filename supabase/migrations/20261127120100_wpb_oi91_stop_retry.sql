-- WP-B (AUTH-009 S1; Owner ruling 2026-11-26): the Owner-only controlled automatic-collection
-- stop retry (AUTHORIZATIONS AUTH-009, "Automatic-stop reconciliation").
--
-- A final-balance invoice whose latest stop attempt the Owner reconciled as absent (Stripe still
-- shows automatic collection on) may get one new stop attempt, at the Owner's explicit request:
-- Owner, fresh MFA, a live session and a reason; the approved lock hierarchy (payment
-- authorization, then final-balance invoice, then outbound request); a fresh attempt-specific
-- idempotency key (wpb-final-balance-stop-<invoice>-a<n>, the merged derivation). Any other
-- state is a typed refusal that writes nothing. A duplicate or concurrent call is deterministic:
-- it waits for the first under the same locks and returns the attempt in flight, creating
-- nothing. Automatic collection is never re-enabled and nothing is retried automatically: the
-- new attempt is an ordinary stop request (auto_advance false) that the executor claims,
-- confirms and records under 20261127120000. Billing holds and every other anomaly are
-- untouched; the stop-specific item clears only on authoritative evidence (a later attempt
-- Stripe confirmed, or the Owner reconciled as present: project_financial_anomalies item 8).
-- Audited as outbound.request_retried (04 §10) with the Owner's reason.
-- Forward-only (T-MIG-02); merged migrations are not edited.

create function private.retry_final_balance_stop(p_final_balance_invoice_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_last public.outbound_stripe_requests%rowtype;
  v_next uuid;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  select * into v_fbi from public.final_balance_invoices where id = p_final_balance_invoice_id;
  if not found then
    return private.fail('not_found');
  end if;
  -- Lock hierarchy: the project's authorizations (id order), the invoice, then the stop rows.
  -- Simultaneous retries serialize here; the second sees the first's attempt.
  perform 1 from public.payment_authorizations where project_id = v_fbi.project_id order by id for update;
  select * into v_fbi from public.final_balance_invoices where id = p_final_balance_invoice_id for update;
  select * into v_last from public.outbound_stripe_requests
   where domain_record_type = 'final_balance_invoice' and domain_record_id = v_fbi.id
     and purpose = 'final_balance_invoice_disable_auto'
   order by attempt desc limit 1 for update;
  if v_last.id is null then
    return private.fail('not_eligible');
  end if;
  -- Duplicate or concurrent request: the attempt in flight is returned; nothing is created.
  if v_last.status = 'pending' then
    return jsonb_build_object('ok', true, 'existing', true, 'request_id', v_last.id);
  end if;
  if v_fbi.status in ('paid', 'void') then
    return private.fail('not_needed');
  end if;
  -- An unreconciled stop is reconciled first (reconcile_outbound_request), never retried blind.
  if v_last.status = 'ambiguous'
     or (v_last.status = 'failed' and coalesce(v_last.error_code, '') <> 'already_paid') then
    return private.fail('reconciliation_required');
  end if;
  if v_last.status <> 'reconciled_absent' then
    return private.fail('not_needed');
  end if;
  if v_fbi.stripe_invoice_id is null or not v_fbi.automatic_stop_required then
    return private.fail('not_eligible');
  end if;
  if (select max(o.attempt) from public.outbound_stripe_requests o
       where o.domain_record_type = 'final_balance_invoice' and o.domain_record_id = v_fbi.id) >= 20 then
    return private.fail('attempts_exhausted');
  end if;
  v_next := private.new_outbound_request('final_balance_invoice_disable_auto', v_fbi.project_id, 'final_balance_invoice',
    v_fbi.id, 'wpb-final-balance-stop-' || v_fbi.id::text,
    jsonb_build_object('invoice', v_fbi.stripe_invoice_id, 'auto_advance', false));
  perform private.audit_financial('outbound.request_retried', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id,
    jsonb_build_object('purpose', 'final_balance_invoice_disable_auto', 'request_id', v_next,
      'superseded_request_id', v_last.id), btrim(p_reason));
  return jsonb_build_object('ok', true, 'existing', false, 'request_id', v_next);
end;
$$;

create function public.retry_final_balance_stop(p_final_balance_invoice_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.retry_final_balance_stop(p_final_balance_invoice_id, p_reason); $$;

-- Owner-only: granted to authenticated (the function re-authorizes the caller), as
-- retry_final_balance_invoice and reconcile_outbound_request; never anon, PUBLIC or the server role.
revoke all on function
  private.retry_final_balance_stop(uuid, text), public.retry_final_balance_stop(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function
  private.retry_final_balance_stop(uuid, text), public.retry_final_balance_stop(uuid, text)
to authenticated;
