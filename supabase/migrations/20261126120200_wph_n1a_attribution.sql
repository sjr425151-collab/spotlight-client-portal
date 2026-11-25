-- WP-H (AUTH-006 and Amendment 1), N1(a): attribution of refunds and disputes at receipt.
-- Decision: 04 §15.2.1 rules 8-9; Owner 2026-11-25 (AUTH-006 N1(a) rules, binding
-- clarifications; Amendment 1 conflict design; OI-93). Handoff: docs/R1-HANDOFFS.md §1 item 3, §1A.
--
-- Rules implemented here:
-- - An event is attributed only through deterministic authoritative relationships: the recorded
--   payment links (charge, payment intent, invoice), the invoice links (checkout_sessions,
--   final_balance_invoices, maintenance_recoveries), and a refund decision that exists and whose
--   charge_key equals a charge of this event. Metadata alone never attributes.
-- - One project: the current path (the project is set only if the event has none; an existing
--   association is never re-pointed). Incomplete charge evidence defers, and the B1 gates of the
--   identified project fail closed meanwhile.
-- - Two or more projects: quarantined:attribution_conflict, no project set. The handler writes
--   the exact candidate set; process_stripe_event keeps it through the rollback and records it
--   with the quarantine in one transaction. Every candidate project fails G2 and G4; the Owner's
--   review re-checks and audits every candidate and never clears the block (OI-93).
-- - None: deferred, kept for reconciliation and Owner review; never discarded.
--
-- Changed existing functions (AUTH-006 (3), Amendment 1): handle_refund, handle_dispute,
-- handle_charge_refunded, process_stripe_event, project_financial_anomalies (one additive
-- branch reusing the quarantined_event kind), resolve_quarantined_event (body only). Each is the
-- current definition from 20261124160100 with only the changes marked "N1(a)". No change to
-- project_financial_status, contract_version 3, the anomaly kinds, or any API privilege.
-- Forward-only (T-MIG-02); merged migrations are not edited.

-- ---------------------------------------------------------------------------
-- Candidate evidence (Amendment 1): private, insert-only, no API role
-- ---------------------------------------------------------------------------
create table private.financial_event_project_candidates (
  webhook_event_id bigint not null references public.webhook_events (id),
  project_id uuid not null references public.projects (id),
  source text not null check (source in ('refund_decision', 'payment_link', 'checkout_session',
    'final_balance_invoice', 'maintenance_recovery')),
  stripe_ref text check (stripe_ref is null or stripe_ref ~ '^[a-z]{2,4}_[A-Za-z0-9_]{6,200}$'
    or stripe_ref ~ '^[0-9a-f-]{36}$'),
  provider_object_id text check (provider_object_id is null or provider_object_id ~ '^[a-z]{2,4}_[A-Za-z0-9_]{6,200}$'),
  created_at timestamptz not null default now(),
  primary key (webhook_event_id, project_id, source)
);
create index financial_event_project_candidates_project_idx on private.financial_event_project_candidates (project_id);
create trigger financial_event_project_candidates_insert_only
  before update or delete on private.financial_event_project_candidates
  for each row execute function private.insert_only();
create trigger financial_event_project_candidates_no_truncate
  before truncate on private.financial_event_project_candidates
  for each statement execute function private.audit_events_immutable();
revoke all on table private.financial_event_project_candidates from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The attribution helper (AUTH-006: one private helper)
-- ---------------------------------------------------------------------------
-- Every authoritative project relationship of a refund, dispute or charge object. A refund
-- decision counts only when it exists and its charge_key is a charge of this object (derived
-- from the object's own charge, payment intent or invoice, never from metadata alone).
create function private.financial_event_attribution(p_obj jsonb, p_decision_id uuid)
returns table (project_id uuid, source text, stripe_ref text, provider_object_id text)
language sql stable security definer set search_path = '' as $$
  with refs as (
    select distinct x.ref from unnest(array[p_obj ->> 'charge', p_obj ->> 'payment_intent',
             case when p_obj ->> 'object' = 'charge' then p_obj ->> 'id' end]) x(ref)
     where x.ref ~ '^(ch|py|pi)_[A-Za-z0-9_]{6,200}$'),
  inv as (
    select p_obj ->> 'invoice' as id where p_obj ->> 'invoice' ~ '^in_[A-Za-z0-9_]{6,200}$'),
  links as (
    select l.* from private.stripe_payment_links l
     where l.stripe_ref in (select r.ref from refs r) or l.stripe_invoice_id in (select i.id from inv i)),
  charge_keys as (
    select private.link_charge_key(l) as k from links l
    union select 'initial:' || c.id::text from public.checkout_sessions c where c.stripe_invoice_id in (select i.id from inv i)
    union select 'final_balance:' || f.id::text from public.final_balance_invoices f
           where f.stripe_invoice_id in (select i.id from inv i)
    union select 'renewal:' || m.stripe_invoice_id from public.maintenance_recoveries m
           where m.stripe_invoice_id in (select i.id from inv i)),
  found as (
    select l.project_id, 'payment_link' as source, l.stripe_ref from links l
    union all
    select c.project_id, 'checkout_session', c.stripe_invoice_id from public.checkout_sessions c
     where c.stripe_invoice_id in (select i.id from inv i)
    union all
    select f.project_id, 'final_balance_invoice', f.stripe_invoice_id from public.final_balance_invoices f
     where f.stripe_invoice_id in (select i.id from inv i)
    union all
    select m.project_id, 'maintenance_recovery', m.stripe_invoice_id from public.maintenance_recoveries m
     where m.stripe_invoice_id in (select i.id from inv i)
    union all
    select d.project_id, 'refund_decision', d.id::text from public.refund_decisions d
     where d.id = p_decision_id and d.charge_key in (select k.k from charge_keys k))
  select distinct on (f.project_id, f.source) f.project_id, f.source, f.stripe_ref,
         case when p_obj ->> 'id' ~ '^[a-z]{2,4}_[A-Za-z0-9_]{6,200}$' then p_obj ->> 'id' end
    from found f
   order by f.project_id, f.source, f.stripe_ref;
$$;
revoke all on function private.financial_event_attribution(jsonb, uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Handlers, processing, anomalies, resolution (current definitions; changes marked N1(a))
-- ---------------------------------------------------------------------------
create or replace function private.handle_refund(e public.webhook_events, r jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_link private.stripe_payment_links%rowtype;
  v_existing public.refunds%rowtype;
  -- A malformed amount is quarantined once the charge is known, never a processing error.
  v_amount bigint := private.try_cents(r -> 'amount');
  v_decision uuid := private.try_uuid(r #>> '{metadata,refund_decision_id}');
  v_outcome text := 'processed';
  v_projects integer;
  v_project uuid;
begin
  -- N1(a) (AUTH-006, Amendment 1): attribution at receipt through authoritative relationships
  -- only, plus any project this event already carries (never re-pointed).
  select count(distinct x.p), (array_agg(distinct x.p))[1] into v_projects, v_project
    from (select c.project_id as p from private.financial_event_attribution(r, v_decision) c
          union select w.project_id from public.webhook_events w where w.id = e.id and w.project_id is not null) x;
  if v_projects = 0 then
    return 'deferred'; -- unattributable: kept for reconciliation and Owner review
  end if;
  if v_projects > 1 then
    -- Conflicting authoritative projects: never choose one. The exact candidate set is
    -- recorded for process_stripe_event to keep through the quarantine rollback.
    insert into private.financial_event_project_candidates (webhook_event_id, project_id, source, stripe_ref,
      provider_object_id)
    select e.id, c.project_id, c.source, c.stripe_ref, c.provider_object_id
      from private.financial_event_attribution(r, v_decision) c
    on conflict do nothing;
    return 'quarantined:attribution_conflict';
  end if;
  update public.webhook_events set project_id = v_project where id = e.id and project_id is null;
  -- A refund decision counts only when it exists and its charge matches this event's charge.
  if v_decision is not null and not exists (
       select 1 from private.financial_event_attribution(r, v_decision) c where c.source = 'refund_decision') then
    v_decision := null;
  end if;
  select * into v_link from private.stripe_payment_links
   where stripe_ref in (r ->> 'charge', r ->> 'payment_intent') and project_id = v_project order by stripe_ref limit 1;
  if not found then
    return 'deferred'; -- project known, charge evidence incomplete: the B1 gates fail closed
  end if;
  if r ->> 'currency' is distinct from 'usd' or v_amount is null or v_amount <= 0 then
    return 'quarantined:refund_invalid';
  end if;
  select * into v_existing from public.refunds where stripe_refund_id = r ->> 'id' for update;
  if not found then
    insert into public.refunds (stripe_refund_id, project_id, stripe_charge_ref, amount_cents, currency, status,
      refund_decision_id, last_event_created)
    values (r ->> 'id', v_link.project_id, v_link.stripe_ref, v_amount, 'usd', r ->> 'status',
      (select d.id from public.refund_decisions d where d.id = v_decision and d.project_id = v_link.project_id),
      e.stripe_created_at);
  elsif v_existing.amount_cents <> v_amount then
    return 'quarantined:refund_amount_changed';
  elsif e.stripe_created_at >= v_existing.last_event_created and v_existing.status not in ('failed', 'canceled') then
    update public.refunds set status = r ->> 'status', last_event_created = e.stripe_created_at, updated_at = now()
     where stripe_refund_id = v_existing.stripe_refund_id;
  end if;

  if r ->> 'status' = 'succeeded' then
    v_outcome := private.apply_reversal(e, v_link, 'refund', 'refund', r ->> 'id', v_amount, v_decision);
  elsif r ->> 'status' in ('failed', 'canceled') then
    perform private.mirror_reversal(e, r ->> 'id', 'refund', 'refund', 'reversal');
  end if;
  if v_outcome = 'processed' then
    perform private.emit_domain_event('payment.refund_recorded', v_link.project_id, 'refund', r ->> 'id',
      jsonb_build_object('status', r ->> 'status'), 'payment.refund_recorded:' || e.stripe_event_id);
    perform private.audit_financial('refund.recorded', 'refund', r ->> 'id', v_link.project_id,
      jsonb_build_object('amount_cents', v_amount, 'status', r ->> 'status', 'refund_decision_id', v_decision));
  end if;
  return v_outcome;
end;
$$;

create or replace function private.handle_dispute(e public.webhook_events, d jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_link private.stripe_payment_links%rowtype;
  v_existing public.disputes%rowtype;
  v_amount bigint := private.try_cents(d -> 'amount');
  v_event bigint;
  v_new boolean := false;
  v_outcome text := 'processed';
  v_projects integer;
  v_project uuid;
begin
  -- N1(a) (AUTH-006, Amendment 1): attribution at receipt, as in handle_refund.
  select count(distinct x.p), (array_agg(distinct x.p))[1] into v_projects, v_project
    from (select c.project_id as p from private.financial_event_attribution(d, null) c
          union select w.project_id from public.webhook_events w where w.id = e.id and w.project_id is not null) x;
  if v_projects = 0 then
    return 'deferred';
  end if;
  if v_projects > 1 then
    insert into private.financial_event_project_candidates (webhook_event_id, project_id, source, stripe_ref,
      provider_object_id)
    select e.id, c.project_id, c.source, c.stripe_ref, c.provider_object_id
      from private.financial_event_attribution(d, null) c
    on conflict do nothing;
    return 'quarantined:attribution_conflict';
  end if;
  update public.webhook_events set project_id = v_project where id = e.id and project_id is null;
  select * into v_link from private.stripe_payment_links
   where stripe_ref in (d ->> 'charge', d ->> 'payment_intent') and project_id = v_project order by stripe_ref limit 1;
  if not found then
    return 'deferred';
  end if;
  if d ->> 'currency' is distinct from 'usd' or v_amount is null or v_amount <= 0
     or d ->> 'status' not in ('warning_needs_response', 'warning_under_review', 'warning_closed', 'needs_response',
                               'under_review', 'won', 'lost', 'prevented') then
    return 'quarantined:dispute_invalid';
  end if;
  if not exists (select 1 from public.payment_obligations where charge_key = private.link_charge_key(v_link)) then
    return 'deferred';
  end if;
  select * into v_existing from public.disputes where stripe_dispute_id = d ->> 'id' for update;
  if not found then
    v_new := true;
    insert into public.disputes (stripe_dispute_id, project_id, stripe_charge_ref, amount_cents, currency, status, reason,
      evidence_due_by, opened_at, closed_at, last_event_created)
    values (d ->> 'id', v_link.project_id, v_link.stripe_ref, v_amount, 'usd', d ->> 'status', left(d ->> 'reason', 100),
      private.unix_ts(d #> '{evidence_details,due_by}'), coalesce(private.unix_ts(d -> 'created'), e.stripe_created_at),
      case when d ->> 'status' in ('won', 'lost', 'warning_closed', 'prevented') then now() end, e.stripe_created_at);
  elsif v_existing.amount_cents <> v_amount then
    return 'quarantined:dispute_amount_changed';
  elsif e.stripe_created_at >= v_existing.last_event_created and v_existing.status not in ('won', 'lost') then
    update public.disputes
       set status = d ->> 'status', reason = coalesce(left(d ->> 'reason', 100), reason),
           evidence_due_by = coalesce(private.unix_ts(d #> '{evidence_details,due_by}'), evidence_due_by),
           closed_at = case when d ->> 'status' in ('won', 'lost', 'warning_closed', 'prevented') then coalesce(closed_at, now()) end,
           last_event_created = e.stripe_created_at, updated_at = now()
     where stripe_dispute_id = v_existing.stripe_dispute_id;
  end if;

  -- Funds are withdrawn for any non-inquiry status (a dispute first seen as won or lost
  -- still withdrew funds before closing).
  if d ->> 'status' not in ('warning_needs_response', 'warning_under_review', 'warning_closed', 'prevented')
     and not exists (select 1 from public.ledger_entries where stripe_object_id = d ->> 'id' and entry_type = 'dispute_opened') then
    v_outcome := private.apply_reversal(e, v_link, 'dispute_opened', 'dispute', d ->> 'id', v_amount, null);
    if v_outcome <> 'processed' then
      return v_outcome;
    end if;
    v_event := private.emit_domain_event('payment.dispute_opened', v_link.project_id, 'dispute', d ->> 'id', '{}'::jsonb,
      'payment.dispute_opened:' || (d ->> 'id'));
    perform private.audit_financial('dispute.opened', 'dispute', d ->> 'id', v_link.project_id,
      jsonb_build_object('amount_cents', v_amount, 'evidence_due_by', d #> '{evidence_details,due_by}'));
    -- OI-37: immediate Owner notification; no takedown and no automatic hold.
    perform private.notify_owner('dispute.opened', 'dispute.opened:' || (d ->> 'id') || ':1', v_link.project_id, v_event,
      jsonb_build_object('dispute_id', d ->> 'id'));
  end if;
  -- Only the stored, monotonic outcome is mirrored: a stale "won" after "lost" (or the
  -- reverse) never posts anything (04 §17 #5, T-ARC-03).
  if d ->> 'status' in ('won', 'lost')
     and (select x.status from public.disputes x where x.stripe_dispute_id = d ->> 'id') = d ->> 'status' then
    if private.mirror_reversal(e, d ->> 'id', 'dispute_opened',
         case when d ->> 'status' = 'won' then 'dispute_won'::public.ledger_entry_type
              else 'dispute_lost'::public.ledger_entry_type end, d ->> 'status') > 0 then
      perform private.emit_domain_event('payment.dispute_closed', v_link.project_id, 'dispute', d ->> 'id',
        jsonb_build_object('outcome', d ->> 'status'), 'payment.dispute_closed:' || (d ->> 'id'));
      perform private.audit_financial('dispute.closed', 'dispute', d ->> 'id', v_link.project_id,
        jsonb_build_object('outcome', d ->> 'status'));
    end if;
  elsif not v_new then
    perform private.audit_financial('dispute.updated', 'dispute', d ->> 'id', v_link.project_id,
      jsonb_build_object('status', d ->> 'status'));
  end if;
  return 'processed';
end;
$$;

create or replace function private.handle_charge_refunded(e public.webhook_events, ch jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_refund jsonb;
  v_outcome text;
  v_any boolean := false;
begin
  if jsonb_typeof(ch #> '{refunds,data}') <> 'array' then
    return 'ignored'; -- refund.* events carry each refund object
  end if;
  for v_refund in select * from jsonb_array_elements(ch #> '{refunds,data}') loop
    -- N1(a): each refund is attributed with the charge's own identifiers (charge, payment
    -- intent, invoice) as well as its own.
    v_outcome := private.handle_refund(e, v_refund || jsonb_strip_nulls(jsonb_build_object('charge', ch ->> 'id',
      'payment_intent', coalesce(v_refund ->> 'payment_intent', ch ->> 'payment_intent'), 'invoice', ch ->> 'invoice')));
    if v_outcome <> 'processed' then
      return v_outcome;
    end if;
    v_any := true;
  end loop;
  return case when v_any then 'processed' else 'ignored' end;
end;
$$;

create or replace function private.process_stripe_event(p_webhook_event_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_evt public.webhook_events%rowtype;
  v_outcome text;
  v_status public.webhook_processing_status;
  v_reason text;
  v_message text;
  v_state text;
  v_project uuid;
  v_candidates jsonb := '[]'::jsonb;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_evt from public.webhook_events where id = p_webhook_event_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if v_evt.processing_status in ('processed', 'ignored', 'quarantined') then
    return jsonb_build_object('ok', true, 'status', v_evt.processing_status, 'already', true);
  end if;
  begin
    v_outcome := private.dispatch_stripe_event(v_evt);
    -- A quarantine decision rolls back every effect the handler made before deciding, so a
    -- quarantined event never leaves a partial record (04 §11 rule 6). Only the project
    -- attribution is kept for the Owner's review.
    if v_outcome like 'quarantined:%' then
      select project_id into v_project from public.webhook_events where id = v_evt.id;
      -- N1(a) (Amendment 1): the exact candidate set the handler decided on is read before the
      -- rollback; like v_outcome and v_project it survives it, and it is recorded below.
      select coalesce(jsonb_agg(jsonb_build_object('project_id', c.project_id, 'source', c.source,
               'stripe_ref', c.stripe_ref, 'provider_object_id', c.provider_object_id)
               order by c.project_id, c.source), '[]'::jsonb)
        into v_candidates
        from private.financial_event_project_candidates c where c.webhook_event_id = v_evt.id;
      raise exception using errcode = 'WPBQ1', message = v_outcome;
    end if;
  exception when sqlstate 'WPBQ1' then
    null; -- v_outcome and v_project survive the rollback of the handler's subtransaction
  when others then
    get stacked diagnostics v_message = message_text, v_state = returned_sqlstate;
    update public.webhook_events set processing_status = 'failed', attempts = attempts + 1,
      last_error = left(v_state || ': ' || v_message, 500) where id = v_evt.id;
    perform private.audit_financial('webhook.processing_failed', 'webhook_event', v_evt.id::text, null,
      jsonb_build_object('stripe_event_id', v_evt.stripe_event_id, 'sqlstate', v_state));
    return jsonb_build_object('ok', false, 'status', 'failed');
  end;
  if v_outcome like 'quarantined:%' then
    v_status := 'quarantined';
    v_reason := left(substr(v_outcome, 13), 200);
  else
    v_status := v_outcome::public.webhook_processing_status;
  end if;
  update public.webhook_events
     set processing_status = v_status, attempts = attempts + 1, quarantine_reason = v_reason,
         project_id = coalesce(v_project, project_id),
         processed_at = case when v_status in ('processed', 'ignored', 'quarantined') then now() end, last_error = null
   where id = v_evt.id
  returning * into v_evt;
  -- Same transaction as the quarantine status: the candidates and the disposition commit together.
  insert into private.financial_event_project_candidates (webhook_event_id, project_id, source, stripe_ref,
    provider_object_id)
  select v_evt.id, (c ->> 'project_id')::uuid, c ->> 'source', c ->> 'stripe_ref', c ->> 'provider_object_id'
    from jsonb_array_elements(v_candidates) c
  on conflict do nothing;
  if v_status = 'quarantined' then
    -- Candidate project IDs appear only here (Owner-only financial audit) and in the private table.
    perform private.audit_financial('webhook.quarantined', 'webhook_event', v_evt.id::text, v_evt.project_id,
      jsonb_build_object('stripe_event_id', v_evt.stripe_event_id, 'reason', v_reason)
        || case when jsonb_array_length(v_candidates) > 0 then jsonb_build_object('candidate_project_ids',
             (select jsonb_agg(distinct c ->> 'project_id') from jsonb_array_elements(v_candidates) c)) else '{}'::jsonb end);
    perform private.notify_owner('webhook.quarantined', 'webhook.quarantined:' || v_evt.stripe_event_id || ':1',
      v_evt.project_id, null, jsonb_build_object('webhook_event_id', v_evt.id));
  elsif v_status = 'processed' then
    perform private.audit_financial('webhook.processed', 'webhook_event', v_evt.id::text, v_evt.project_id,
      jsonb_build_object('stripe_event_id', v_evt.stripe_event_id, 'event_type', v_evt.event_type));
  end if;
  return jsonb_build_object('ok', true, 'status', v_status, 'reason', v_reason);
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
                      where c.webhook_event_id = w.id and c.project_id = p_project_id));
$$;

create or replace function private.resolve_quarantined_event(p_webhook_event_id bigint, p_resolution text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
  v_candidate uuid;
  v_candidates jsonb := '[]'::jsonb;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_resolution, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.webhook_events set quarantine_resolved_at = now(), quarantine_resolved_by = (select auth.uid()),
    quarantine_resolution = btrim(p_resolution)
   where id = p_webhook_event_id and processing_status = 'quarantined' and quarantine_resolved_at is null
  returning project_id into v_project;
  if not found then
    return private.fail('not_found');
  end if;
  -- B1: resolving records the Owner's review only. Nothing is reprocessed or posted; the
  -- gates are re-derived from all the evidence, so a reversal the event shows still blocks.
  perform private.audit_financial('quarantine.resolved', 'webhook_event', p_webhook_event_id::text, v_project,
    jsonb_build_object('gates', private.financial_gate_recheck(v_project)), p_resolution);
  -- N1(a), OI-93 (Amendment 1): every candidate project is re-checked and audited. The review
  -- never clears an attribution-conflict candidate block; those gates stay failed in R1.
  for v_candidate in
    select distinct c.project_id from private.financial_event_project_candidates c
     where c.webhook_event_id = p_webhook_event_id and c.project_id is distinct from v_project
     order by c.project_id
  loop
    perform private.audit_financial('quarantine.resolved', 'webhook_event', p_webhook_event_id::text, v_candidate,
      jsonb_build_object('gates', private.financial_gate_recheck(v_candidate), 'candidate', true), p_resolution);
    v_candidates := v_candidates || jsonb_build_array(jsonb_build_object('project_id', v_candidate,
      'gates', private.financial_gate_recheck(v_candidate)));
  end loop;
  return jsonb_build_object('ok', true, 'gates', private.financial_gate_recheck(v_project))
    || case when jsonb_array_length(v_candidates) > 0 then jsonb_build_object('candidates', v_candidates)
            else '{}'::jsonb end;
end;
$$;
