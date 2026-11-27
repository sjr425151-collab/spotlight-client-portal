-- WP-B (AUTH-010; Owner grant 2026-11-27): OI-93 conflict decisions, part 1 of 2.
-- Decision: OI-93; Owner design decisions of 2026-11-25 (S1, S2, S0 in principle; one decision
-- per event; no webhook guard transition; outcome classes; per-decision rate limit; at most 10
-- durable attempts); AUTHORIZATIONS AUTH-010 (design rows, grant, U-1 to U-4).
--
-- This migration holds the records and the pure building blocks:
-- - four private, insert-only tables with no API privilege: the Owner's conflict decisions (one
--   per event), the application attempts, the ledger entries each attempt posted or cited, and
--   the effect recognitions (one per effect key: provider object, effect type, amount);
-- - the classifier (financial_conflict_scope, financial_conflict_classify) and the oi93.fp.v1
--   evidence fingerprint (oi93_canonical_json, financial_conflict_fingerprint);
-- - the extracted per-project paths apply_refund_for_project and apply_dispute_for_project, and
--   charge_refunded_objects (the charge.refunded expansion), so that the normal handlers and a
--   conflict application run the same code;
-- - handle_refund, handle_dispute and handle_charge_refunded replaced with equivalent bodies: the
--   attribution step is unchanged and the rest delegates to the extracted functions. Equivalence
--   is shown by the unchanged pgTAP 140, 160, 180, 190 and 191.
--
-- Unchanged (AUTH-010 "Prohibited"): webhook_events_guard, apply_reversal, mirror_reversal,
-- post_reversal_entry, every ledger rule and constraint, process_stripe_event,
-- resolve_quarantined_event. The original event stays immutable and quarantined.
-- Forward-only (T-MIG-02); merged migrations are not edited.

-- ---------------------------------------------------------------------------
-- 1. Records: private, insert-only, no API role (cross-tenant isolation: pgTAP 195)
-- ---------------------------------------------------------------------------
-- One immutable Owner decision per event: the chosen project (a recorded candidate), the
-- Owner's evidence references and reason. A decision alone never clears a block.
create table private.financial_conflict_decisions (
  id uuid primary key default gen_random_uuid(),
  webhook_event_id bigint not null unique references public.webhook_events (id),
  project_id uuid not null references public.projects (id),
  evidence jsonb not null,
  reason text not null,
  decided_by uuid not null references public.profiles (id),
  decided_at timestamptz not null default now(),
  constraint financial_conflict_decisions_evidence check (jsonb_typeof(evidence) = 'object'
    and evidence <> '{}'::jsonb and octet_length(evidence::text) <= 16384),
  constraint financial_conflict_decisions_reason check (char_length(reason) between 1 and 1000)
);
create index financial_conflict_decisions_project_idx on private.financial_conflict_decisions (project_id);

-- Durable application attempts: at most 10 per decision, numbered under the decision-row lock.
-- terminal_reason 'exhausted' marks the tenth non-success row; its outcome and evidence stay.
create table private.financial_conflict_applications (
  id uuid primary key default gen_random_uuid(),
  decision_id uuid not null references private.financial_conflict_decisions (id),
  webhook_event_id bigint not null references public.webhook_events (id),
  project_id uuid not null references public.projects (id),
  attempt_no integer not null,
  attempt_request_id uuid not null unique,
  category text,
  outcome text not null,
  terminal_reason text,
  fingerprint_version text not null default 'oi93.fp.v1',
  fingerprint text not null,
  detail jsonb not null default '{}'::jsonb,
  reason text not null,
  requested_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  unique (decision_id, attempt_no),
  constraint financial_conflict_applications_attempt check (attempt_no between 1 and 10),
  constraint financial_conflict_applications_category check (category is null or category in ('S1', 'S2')),
  constraint financial_conflict_applications_outcome check (outcome in ('posted', 'represented', 'awaiting_evidence',
    'operational_failure', 'permanently_unsupported')),
  constraint financial_conflict_applications_exhausted check ((terminal_reason is not null)
    = (attempt_no = 10 and outcome not in ('posted', 'represented'))),
  constraint financial_conflict_applications_terminal check (terminal_reason is null or terminal_reason = 'exhausted'),
  constraint financial_conflict_applications_fp_version check (fingerprint_version = 'oi93.fp.v1'),
  constraint financial_conflict_applications_fp check (fingerprint ~ '^[0-9a-f]{64}$'),
  constraint financial_conflict_applications_detail check (jsonb_typeof(detail) = 'object'
    and octet_length(detail::text) <= 32768),
  constraint financial_conflict_applications_reason check (char_length(reason) between 1 and 1000)
);
-- At most one successful application per decision (a success ends the attempts).
create unique index financial_conflict_applications_success_idx on private.financial_conflict_applications (decision_id)
  where outcome in ('posted', 'represented');
create index financial_conflict_applications_event_idx on private.financial_conflict_applications (webhook_event_id);

-- One recognition per effect key (provider object, effect type, amount). Any number of events
-- may cite a recognized effect, each with its own exact match; citing never creates, moves or
-- re-recognizes money.
create table private.financial_conflict_effects (
  id uuid primary key default gen_random_uuid(),
  stripe_object_id text not null,
  effect_type text not null,
  amount_cents bigint not null,
  currency text not null default 'usd',
  project_id uuid not null references public.projects (id),
  -- Deferred: the recognition and the application's entries are recorded in the same protected
  -- step as the application row, which is written last, once the outcome is known.
  recognized_by_application_id uuid not null references private.financial_conflict_applications (id)
    deferrable initially deferred,
  recognized_at timestamptz not null default now(),
  unique (stripe_object_id, effect_type, amount_cents),
  constraint financial_conflict_effects_object check (stripe_object_id ~ '^(re|pyr|dp|du)_[A-Za-z0-9_]{6,200}$'),
  constraint financial_conflict_effects_type check (effect_type in ('refund', 'refund_reversed', 'dispute_opened',
    'dispute_won', 'dispute_lost')),
  constraint financial_conflict_effects_amount check (amount_cents >= 0),
  constraint financial_conflict_effects_currency check (currency = 'usd')
);
create index financial_conflict_effects_project_idx on private.financial_conflict_effects (project_id);

-- The exact ledger entries an application posted (role new) or cited (role cited), with the
-- recorded values every re-verification compares against.
create table private.financial_conflict_application_entries (
  application_id uuid not null references private.financial_conflict_applications (id) deferrable initially deferred,
  ledger_entry_id bigint not null references public.ledger_entries (id),
  effect_id uuid not null references private.financial_conflict_effects (id),
  role text not null,
  project_id uuid not null references public.projects (id),
  stripe_object_id text not null,
  entry_type public.ledger_entry_type not null,
  amount_cents bigint not null,
  currency text not null,
  obligation_id uuid references public.payment_obligations (id),
  holding_charge_key text,
  primary key (application_id, ledger_entry_id),
  constraint financial_conflict_application_entries_role check (role in ('new', 'cited')),
  constraint financial_conflict_application_entries_target check ((obligation_id is null) <> (holding_charge_key is null))
);
-- A ledger entry is posted ("new") by at most one application.
create unique index financial_conflict_application_entries_new_idx
  on private.financial_conflict_application_entries (ledger_entry_id) where role = 'new';
create index financial_conflict_application_entries_effect_idx on private.financial_conflict_application_entries (effect_id);

create trigger financial_conflict_decisions_insert_only
  before update or delete on private.financial_conflict_decisions
  for each row execute function private.insert_only();
create trigger financial_conflict_decisions_no_truncate
  before truncate on private.financial_conflict_decisions
  for each statement execute function private.audit_events_immutable();
create trigger financial_conflict_applications_insert_only
  before update or delete on private.financial_conflict_applications
  for each row execute function private.insert_only();
create trigger financial_conflict_applications_no_truncate
  before truncate on private.financial_conflict_applications
  for each statement execute function private.audit_events_immutable();
create trigger financial_conflict_effects_insert_only
  before update or delete on private.financial_conflict_effects
  for each row execute function private.insert_only();
create trigger financial_conflict_effects_no_truncate
  before truncate on private.financial_conflict_effects
  for each statement execute function private.audit_events_immutable();
create trigger financial_conflict_application_entries_insert_only
  before update or delete on private.financial_conflict_application_entries
  for each row execute function private.insert_only();
create trigger financial_conflict_application_entries_no_truncate
  before truncate on private.financial_conflict_application_entries
  for each statement execute function private.audit_events_immutable();
revoke all on table private.financial_conflict_decisions, private.financial_conflict_applications,
  private.financial_conflict_effects, private.financial_conflict_application_entries
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. The extracted per-project paths (handler equivalence)
-- ---------------------------------------------------------------------------
-- The refund objects of a charge.refunded event, each carrying the charge's own identifiers
-- (charge, payment intent, invoice) as well as its own (N1(a)); in the event's order.
create function private.charge_refunded_objects(ch jsonb) returns table (ord bigint, obj jsonb)
language sql immutable set search_path = '' as $$
  select x.i, x.r || jsonb_strip_nulls(jsonb_build_object('charge', ch ->> 'id',
           'payment_intent', coalesce(x.r ->> 'payment_intent', ch ->> 'payment_intent'), 'invoice', ch ->> 'invoice'))
    from jsonb_array_elements(case when jsonb_typeof(ch #> '{refunds,data}') = 'array' then ch #> '{refunds,data}'
                                   else '[]'::jsonb end) with ordinality x(r, i);
$$;

-- handle_refund after attribution, for one identified project: the body of the WP-H handler
-- (20261126120200) from the refund-decision check on, with v_project as p_project_id.
create function private.apply_refund_for_project(e public.webhook_events, r jsonb, p_project_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_link private.stripe_payment_links%rowtype;
  v_existing public.refunds%rowtype;
  -- A malformed amount is quarantined once the charge is known, never a processing error.
  v_amount bigint := private.try_cents(r -> 'amount');
  v_decision uuid := private.try_uuid(r #>> '{metadata,refund_decision_id}');
  v_outcome text := 'processed';
begin
  -- A refund decision counts only when it exists and its charge matches this event's charge.
  if v_decision is not null and not exists (
       select 1 from private.financial_event_attribution(r, v_decision) c where c.source = 'refund_decision') then
    v_decision := null;
  end if;
  select * into v_link from private.stripe_payment_links
   where stripe_ref in (r ->> 'charge', r ->> 'payment_intent') and project_id = p_project_id order by stripe_ref limit 1;
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

-- handle_dispute after attribution, for one identified project: the body of the WP-H handler
-- (20261126120200) from the payment-link lookup on, with v_project as p_project_id.
create function private.apply_dispute_for_project(e public.webhook_events, d jsonb, p_project_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_link private.stripe_payment_links%rowtype;
  v_existing public.disputes%rowtype;
  v_amount bigint := private.try_cents(d -> 'amount');
  v_event bigint;
  v_new boolean := false;
  v_outcome text := 'processed';
begin
  select * into v_link from private.stripe_payment_links
   where stripe_ref in (d ->> 'charge', d ->> 'payment_intent') and project_id = p_project_id order by stripe_ref limit 1;
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

-- ---------------------------------------------------------------------------
-- 3. Handlers: the WP-H attribution step unchanged; the rest delegates (equivalent behavior)
-- ---------------------------------------------------------------------------
create or replace function private.handle_refund(e public.webhook_events, r jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_decision uuid := private.try_uuid(r #>> '{metadata,refund_decision_id}');
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
  -- AUTH-010: the rest of the path, shared with an Owner conflict application.
  return private.apply_refund_for_project(e, r, v_project);
end;
$$;

create or replace function private.handle_dispute(e public.webhook_events, d jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
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
  -- AUTH-010: the rest of the path, shared with an Owner conflict application.
  return private.apply_dispute_for_project(e, d, v_project);
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
  -- N1(a): each refund is attributed with the charge's own identifiers (charge, payment
  -- intent, invoice) as well as its own. AUTH-010: the expansion is shared with an Owner
  -- conflict application (charge_refunded_objects).
  for v_refund in select c.obj from private.charge_refunded_objects(ch) c order by c.ord loop
    v_outcome := private.handle_refund(e, v_refund);
    if v_outcome <> 'processed' then
      return v_outcome;
    end if;
    v_any := true;
  end loop;
  return case when v_any then 'processed' else 'ignored' end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The classifier
-- ---------------------------------------------------------------------------
-- The provider objects a refund, charge.refunded or dispute event concerns, and their
-- authoritative relationships: charge references, invoices, payment links and charge keys
-- (the same derivation as financial_event_attribution). Objects the event cannot name are
-- returned as they are, for the classifier to refuse.
create function private.financial_conflict_scope(e public.webhook_events) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_obj jsonb := e.payload #> '{data,object}';
  v_objects jsonb;
  v_refs text[];
  v_invoices text[];
  v_keys text[];
begin
  if e.event_type = 'charge.refunded' then
    select coalesce(jsonb_agg(c.obj order by c.ord), '[]'::jsonb) into v_objects
      from private.charge_refunded_objects(coalesce(v_obj, '{}'::jsonb)) c;
  elsif v_obj is not null then
    v_objects := jsonb_build_array(v_obj);
  else
    v_objects := '[]'::jsonb;
  end if;
  select coalesce(array_agg(distinct x.ref order by x.ref), '{}') into v_refs
    from jsonb_array_elements(v_objects) o
   cross join lateral unnest(array[o ->> 'charge', o ->> 'payment_intent']) x(ref)
   where jsonb_typeof(o) = 'object' and x.ref ~ '^(ch|py|pi)_[A-Za-z0-9_]{6,200}$';
  select coalesce(array_agg(distinct o ->> 'invoice' order by o ->> 'invoice'), '{}') into v_invoices
    from jsonb_array_elements(v_objects) o
   where jsonb_typeof(o) = 'object' and o ->> 'invoice' ~ '^in_[A-Za-z0-9_]{6,200}$';
  select coalesce(array_agg(distinct k.k order by k.k), '{}') into v_keys
    from (select private.link_charge_key(l) as k from private.stripe_payment_links l
           where l.stripe_ref = any (v_refs) or l.stripe_invoice_id = any (v_invoices)
          union select 'initial:' || c.id::text from public.checkout_sessions c where c.stripe_invoice_id = any (v_invoices)
          union select 'final_balance:' || f.id::text from public.final_balance_invoices f
                 where f.stripe_invoice_id = any (v_invoices)
          union select 'renewal:' || m.stripe_invoice_id from public.maintenance_recoveries m
                 where m.stripe_invoice_id = any (v_invoices)) k
   where k.k is not null;
  return jsonb_build_object('objects', v_objects, 'refs', to_jsonb(v_refs), 'invoices', to_jsonb(v_invoices),
    'charge_keys', to_jsonb(v_keys),
    'object_ids', (select coalesce(jsonb_agg(o ->> 'id' order by x.i), '[]'::jsonb)
                     from jsonb_array_elements(v_objects) with ordinality x(o, i)
                    where jsonb_typeof(o) = 'object' and o ->> 'id' is not null));
end;
$$;

-- Classifies an attribution-conflict event for one chosen project (AUTH-010 "Categories"):
-- S1 refunds and S2 disputes where exactly one candidate, the chosen project, holds the posted
-- obligations. Everything on the unsupported list is permanently_unsupported. Missing
-- obligations are awaiting_evidence (the charge may not be posted yet: order independence).
-- Read-only; the attempt re-checks the money-moving conditions after posting, under the locks.
create function private.financial_conflict_classify(e public.webhook_events, p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_scope jsonb := private.financial_conflict_scope(e);
  v_kind text;
  v_category text;
  v_o jsonb;
  v_ord bigint;
  v_details jsonb := '[]'::jsonb;
  v_outcome text;
  v_reason text;
  v_obj_outcome text;
  v_obj_reason text;
  v_holders uuid[];
  v_dec uuid;
begin
  -- Event-level conditions.
  if e.processing_status <> 'quarantined' or e.quarantine_reason is distinct from 'attribution_conflict' then
    v_reason := 'not_attribution_conflict';
  elsif e.event_type in ('refund.created', 'refund.updated', 'refund.failed', 'charge.refund.updated', 'charge.refunded') then
    v_kind := 'refund';
    v_category := 'S1';
  elsif e.event_type in ('charge.dispute.created', 'charge.dispute.updated', 'charge.dispute.closed',
                         'charge.dispute.funds_withdrawn', 'charge.dispute.funds_reinstated') then
    v_kind := 'dispute';
    v_category := 'S2';
  else
    v_reason := 'event_type_unsupported';
  end if;
  if v_reason is null and (e.livemode is distinct from private.expected_livemode()
       or (e.payload ? 'livemode' and (e.payload -> 'livemode') is distinct from to_jsonb(private.expected_livemode()))) then
    v_reason := 'livemode_mismatch';
  end if;
  if v_reason is null and not exists (select 1 from private.financial_event_project_candidates c
                                        where c.webhook_event_id = e.id and c.project_id = p_project_id) then
    v_reason := 'not_a_candidate';
  end if;
  if v_reason is null and jsonb_array_length(v_scope -> 'objects') = 0 then
    v_reason := 'unresolvable_reference';
  end if;
  if v_reason is not null then
    return jsonb_build_object('category', v_category, 'outcome', 'permanently_unsupported', 'reason', v_reason,
      'objects', '[]'::jsonb);
  end if;

  -- Per-object conditions; the event's outcome is the most severe (unsupported, then awaiting).
  for v_o, v_ord in select x.o, x.i from jsonb_array_elements(v_scope -> 'objects') with ordinality x(o, i) order by x.i loop
    v_obj_outcome := null;
    v_obj_reason := null;
    if jsonb_typeof(v_o) <> 'object' or v_o ->> 'object' is distinct from v_kind
       or not coalesce((v_o ->> 'id') ~ (case when v_kind = 'refund' then '^(re|pyr)_[A-Za-z0-9_]{6,200}$'
                                           else '^(dp|du)_[A-Za-z0-9_]{6,200}$' end), false)
       or not exists (select 1 from unnest(array[v_o ->> 'charge', v_o ->> 'payment_intent']) x(ref)
                       where x.ref ~ '^(ch|py|pi)_[A-Za-z0-9_]{6,200}$') then
      v_obj_reason := 'unresolvable_reference';
    elsif (v_o ? 'livemode' and (v_o -> 'livemode') is distinct from to_jsonb(private.expected_livemode())) then
      v_obj_reason := 'livemode_mismatch';
    elsif v_o ->> 'currency' is distinct from 'usd' or coalesce(private.try_cents(v_o -> 'amount'), 0) <= 0
          or (v_kind = 'refund' and coalesce(v_o ->> 'status', '') not in ('pending', 'requires_action', 'succeeded',
                                                                            'failed', 'canceled'))
          or (v_kind = 'dispute' and coalesce(v_o ->> 'status', '') not in ('warning_needs_response',
                'warning_under_review', 'warning_closed', 'needs_response', 'under_review', 'won', 'lost', 'prevented')) then
      v_obj_reason := 'invalid_object';
    end if;
    if v_obj_reason is null and v_kind = 'refund' then
      v_dec := private.try_uuid(v_o #>> '{metadata,refund_decision_id}');
      if v_dec is not null and exists (select 1 from public.refund_decisions d
                                        where d.id = v_dec and d.project_id <> p_project_id) then
        v_obj_reason := 'refund_decision_other_project';
      end if;
    end if;
    -- An effect or record of this object under another project: never moved or re-recognized.
    if v_obj_reason is null and (
         exists (select 1 from public.ledger_entries l where l.stripe_object_id = v_o ->> 'id' and l.project_id <> p_project_id)
         or exists (select 1 from private.financial_conflict_effects f
                     where f.stripe_object_id = v_o ->> 'id' and f.project_id <> p_project_id)
         or exists (select 1 from public.refunds x where x.stripe_refund_id = v_o ->> 'id' and x.project_id <> p_project_id)
         or exists (select 1 from public.disputes x where x.stripe_dispute_id = v_o ->> 'id' and x.project_id <> p_project_id)) then
      v_obj_reason := 'recognized_under_other_project';
    end if;
    if v_obj_reason is null then
      -- Who holds the posted obligations of the charge this object concerns.
      select coalesce(array_agg(distinct o.project_id order by o.project_id), '{}') into v_holders
        from public.payment_obligations o
       where o.charge_key in (
         select private.link_charge_key(l) from private.stripe_payment_links l
          where l.stripe_ref in (v_o ->> 'charge', v_o ->> 'payment_intent') or l.stripe_invoice_id = v_o ->> 'invoice'
         union select 'initial:' || c.id::text from public.checkout_sessions c where c.stripe_invoice_id = v_o ->> 'invoice'
         union select 'final_balance:' || f.id::text from public.final_balance_invoices f
                where f.stripe_invoice_id = v_o ->> 'invoice'
         union select 'renewal:' || m.stripe_invoice_id from public.maintenance_recoveries m
                where m.stripe_invoice_id = v_o ->> 'invoice');
      if cardinality(v_holders) > 1 then
        v_obj_reason := 'obligations_several_projects';
      elsif cardinality(v_holders) = 1 and v_holders[1] <> p_project_id then
        v_obj_reason := 'obligations_other_project';
      elsif cardinality(v_holders) = 0 then
        v_obj_outcome := 'awaiting_evidence';
        v_obj_reason := 'obligations_missing';
      end if;
    end if;
    if v_obj_reason is not null and v_obj_outcome is null then
      v_obj_outcome := 'permanently_unsupported';
    end if;
    v_details := v_details || jsonb_build_array(jsonb_build_object('ord', v_ord, 'object_id', v_o ->> 'id',
      'outcome', v_obj_outcome, 'reason', v_obj_reason));
    if v_obj_outcome = 'permanently_unsupported' then
      v_outcome := 'permanently_unsupported';
    elsif v_obj_outcome = 'awaiting_evidence' and v_outcome is null then
      v_outcome := 'awaiting_evidence';
    end if;
  end loop;
  return jsonb_build_object('category', v_category, 'outcome', v_outcome,
    'reason', case when v_outcome is not null then 'object' end, 'objects', v_details);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The oi93.fp.v1 evidence fingerprint
-- ---------------------------------------------------------------------------
-- Canonical JSON: UTF-8, object keys sorted by code point, no insignificant whitespace, arrays
-- in the order built (each array below is sorted by its stated keys), integers as integers,
-- explicit nulls.
create function private.oi93_canonical_json(p jsonb) returns text
language plpgsql immutable set search_path = '' as $$
begin
  if p is null then
    return 'null';
  end if;
  case jsonb_typeof(p)
    when 'object' then
      return '{' || coalesce((select string_agg(to_jsonb(x.k)::text || ':' || private.oi93_canonical_json(x.v), ','
                                                order by x.k collate "C")
                                from jsonb_each(p) x(k, v)), '') || '}';
    when 'array' then
      return '[' || coalesce((select string_agg(private.oi93_canonical_json(x.v), ',' order by x.i)
                                from jsonb_array_elements(p) with ordinality x(v, i)), '') || ']';
    else
      return p::text;
  end case;
end;
$$;

-- SHA-256 (hex) of the canonical evidence document of a decision: the decision, the event and
-- its raw-body hash, the candidates, the payment links, the obligations and balances, the
-- relevant ledger entries, the refund or dispute rows, the refund decisions and their lines, and
-- the effect recognitions. Reads, audits, notifications and attempt rows are excluded.
create function private.financial_conflict_fingerprint(p_decision_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v_dec private.financial_conflict_decisions%rowtype;
  v_evt public.webhook_events%rowtype;
  v_scope jsonb;
  v_ids text[];
  v_refs text[];
  v_invoices text[];
  v_keys text[];
  v_decisions uuid[];
  v_doc jsonb;
begin
  select * into v_dec from private.financial_conflict_decisions where id = p_decision_id;
  if not found then
    return null;
  end if;
  select * into v_evt from public.webhook_events where id = v_dec.webhook_event_id;
  v_scope := private.financial_conflict_scope(v_evt);
  select coalesce(array_agg(x), '{}') into v_ids from jsonb_array_elements_text(v_scope -> 'object_ids') x;
  select coalesce(array_agg(x), '{}') into v_refs from jsonb_array_elements_text(v_scope -> 'refs') x;
  select coalesce(array_agg(x), '{}') into v_invoices from jsonb_array_elements_text(v_scope -> 'invoices') x;
  select coalesce(array_agg(x), '{}') into v_keys from jsonb_array_elements_text(v_scope -> 'charge_keys') x;
  select coalesce(array_agg(distinct d.id), '{}') into v_decisions from public.refund_decisions d
   where d.charge_key = any (v_keys)
      or d.id in (select private.try_uuid(o #>> '{metadata,refund_decision_id}') from jsonb_array_elements(v_scope -> 'objects') o
                   where jsonb_typeof(o) = 'object');
  v_doc := jsonb_build_object(
    'version', 'oi93.fp.v1',
    'decision', jsonb_build_object('id', v_dec.id, 'webhook_event_id', v_dec.webhook_event_id,
      'project_id', v_dec.project_id, 'evidence', v_dec.evidence, 'reason', v_dec.reason, 'decided_by', v_dec.decided_by),
    'event', jsonb_build_object('id', v_evt.id, 'stripe_event_id', v_evt.stripe_event_id, 'event_type', v_evt.event_type,
      'api_version', v_evt.api_version, 'livemode', v_evt.livemode, 'object_type', v_evt.object_type,
      'object_id', v_evt.object_id, 'raw_body_sha256', v_evt.raw_body_sha256,
      'processing_status', v_evt.processing_status, 'quarantine_reason', v_evt.quarantine_reason,
      'project_id', v_evt.project_id),
    'candidates', (select coalesce(jsonb_agg(jsonb_build_object('project_id', c.project_id, 'source', c.source,
                      'stripe_ref', c.stripe_ref, 'provider_object_id', c.provider_object_id)
                      order by c.project_id, c.source), '[]'::jsonb)
                     from private.financial_event_project_candidates c where c.webhook_event_id = v_evt.id),
    'payment_links', (select coalesce(jsonb_agg(jsonb_build_object('stripe_ref', l.stripe_ref, 'project_id', l.project_id,
                         'kind', l.kind, 'domain_record_id', l.domain_record_id, 'stripe_invoice_id', l.stripe_invoice_id)
                         order by l.stripe_ref), '[]'::jsonb)
                        from private.stripe_payment_links l
                       where l.stripe_ref = any (v_refs) or l.stripe_invoice_id = any (v_invoices)),
    'obligations', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'project_id', o.project_id, 'kind', o.kind,
                       'charge_key', o.charge_key, 'charge_entry_id', o.charge_entry_id, 'original_cents', o.original_cents,
                       'service_category', o.service_category, 'net_cents', private.obligation_net_cents(o.id))
                       order by o.charge_key, o.kind, o.id), '[]'::jsonb)
                      from public.payment_obligations o where o.charge_key = any (v_keys)),
    'holding_balances', (select coalesce(jsonb_agg(jsonb_build_object('charge_key', k.k,
                            'balance_cents', private.holding_balance_cents(k.k)) order by k.k), '[]'::jsonb)
                           from unnest(v_keys) k(k)),
    'ledger_entries', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'project_id', l.project_id,
                          'entry_type', l.entry_type, 'amount_cents', l.amount_cents, 'currency', l.currency,
                          'service_category', l.service_category, 'source', l.source, 'webhook_event_id', l.webhook_event_id,
                          'stripe_object_type', l.stripe_object_type, 'stripe_object_id', l.stripe_object_id,
                          'stripe_charge_ref', l.stripe_charge_ref, 'obligation_id', l.obligation_id,
                          'holding_charge_key', l.holding_charge_key, 'dedupe_key', l.dedupe_key) order by l.id), '[]'::jsonb)
                         from public.ledger_entries l
                        where l.stripe_object_id = any (v_ids) or l.holding_charge_key = any (v_keys)
                           or l.obligation_id in (select o.id from public.payment_obligations o where o.charge_key = any (v_keys))
                           or l.id in (select o.charge_entry_id from public.payment_obligations o where o.charge_key = any (v_keys))),
    'refunds', (select coalesce(jsonb_agg(jsonb_build_object('stripe_refund_id', r.stripe_refund_id, 'project_id', r.project_id,
                   'stripe_charge_ref', r.stripe_charge_ref, 'amount_cents', r.amount_cents, 'currency', r.currency,
                   'status', r.status, 'refund_decision_id', r.refund_decision_id,
                   'last_event_created', to_char(r.last_event_created at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
                   order by r.stripe_refund_id), '[]'::jsonb)
                  from public.refunds r where r.stripe_refund_id = any (v_ids)),
    'disputes', (select coalesce(jsonb_agg(jsonb_build_object('stripe_dispute_id', d.stripe_dispute_id, 'project_id', d.project_id,
                    'stripe_charge_ref', d.stripe_charge_ref, 'amount_cents', d.amount_cents, 'currency', d.currency,
                    'status', d.status,
                    'last_event_created', to_char(d.last_event_created at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
                    order by d.stripe_dispute_id), '[]'::jsonb)
                   from public.disputes d where d.stripe_dispute_id = any (v_ids)),
    'refund_decisions', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'project_id', d.project_id,
                            'charge_key', d.charge_key, 'amount_cents', d.amount_cents, 'matched_refund_id', d.matched_refund_id,
                            'lines', (select coalesce(jsonb_agg(jsonb_build_object('obligation_id', x.obligation_id,
                                        'amount_cents', x.amount_cents) order by x.obligation_id), '[]'::jsonb)
                                        from public.refund_decision_lines x where x.refund_decision_id = d.id))
                            order by d.id), '[]'::jsonb)
                           from public.refund_decisions d where d.id = any (v_decisions)),
    'effects', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'stripe_object_id', f.stripe_object_id,
                   'effect_type', f.effect_type, 'amount_cents', f.amount_cents, 'currency', f.currency,
                   'project_id', f.project_id, 'recognized_by_application_id', f.recognized_by_application_id)
                   order by f.stripe_object_id, f.effect_type, f.amount_cents), '[]'::jsonb)
                  from private.financial_conflict_effects f where f.stripe_object_id = any (v_ids)));
  return encode(sha256(convert_to(private.oi93_canonical_json(v_doc), 'UTF8')), 'hex');
end;
$$;

revoke all on function
  private.charge_refunded_objects(jsonb),
  private.apply_refund_for_project(public.webhook_events, jsonb, uuid),
  private.apply_dispute_for_project(public.webhook_events, jsonb, uuid),
  private.financial_conflict_scope(public.webhook_events),
  private.financial_conflict_classify(public.webhook_events, uuid),
  private.oi93_canonical_json(jsonb),
  private.financial_conflict_fingerprint(uuid)
from public, anon, authenticated, service_role;
