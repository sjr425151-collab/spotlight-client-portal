-- WP-B: the release.approved consumer and the final-balance obligation, reacceptance,
-- failed-maintenance recovery and billing holds, Owner hold controls, service termination
-- and cancellation (M1, M2), the financial gate interface, and the OI-72 projection.
-- Covers: T-PAY-09, T-PAY-12, T-AGR-04, T-ARC-03, T-BIL-01 to -03, -07, -14 to -17,
-- -22, T-ROLE-06 (termination), T-CAL-04, OI-71 (G1, G2, G4, G8 inputs), OI-72.
-- Synthetic events only (OI-63). Seed: Owner …01, Admin …02, client A …a1 (Project A), client B …b1.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(106);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false)
returns void language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
create function pg_temp.evt(p_id text, p_type text, p_obj jsonb, p_offset integer default 0)
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type, 'api_version', '2026-09-30.endive',
    'livemode', false, 'created', extract(epoch from now())::bigint + p_offset, 'data', jsonb_build_object('object', p_obj));
$$;
grant execute on function pg_temp.evt(text, text, jsonb, integer) to service_role, authenticated;
create function pg_temp.deliver(p_event jsonb) returns jsonb language plpgsql as $$
declare
  v_ingest jsonb;
  v_result jsonb;
begin
  perform pg_temp.as_service();
  v_ingest := public.ingest_stripe_event(p_event, repeat('b', 64));
  if not (v_ingest ->> 'ok')::boolean then
    reset role;
    return v_ingest;
  end if;
  v_result := public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  reset role;
  return v_result || jsonb_build_object('duplicate', v_ingest -> 'duplicate');
end;
$$;
-- The job entry points (T-ARC-09), reported in one object for the assertions below.
create function pg_temp.jobs() returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_service();
  v := jsonb_build_object(
    'holds_placed', public.run_billing_job('maintenance_recovery') #> '{result,holds_placed}',
    'terminations_effective', public.run_billing_job('service_terminations') #> '{result,became_effective}');
  reset role;
  return v;
end;
$$;
-- The release.approved consumer, invoked as the server (its job entry point returns counts
-- only; these tests need each outcome).
create function pg_temp.consume() returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v := private.consume_release_approvals(50);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;
-- AUTH-006 Amendment 2 (revision 2): WP-C-valid release and approval records for the
-- release.approved consumer. The release is recorded by the active Admin (WP-C release_preview is
-- staff-only) and the approval by the project's own non-staff client member (WP-C approve_preview);
-- the test fails unless WP-C's project_fulfillment_status reports both as current. SYNTHETIC TEST
-- EMISSION: the event is written through the WP-0 writer in WP-C's payload shape to exercise the
-- consumer; it never stands in for WP-C's approve_preview, which is unchanged.
create function pg_temp.genuine_release_approved(p_project uuid, p_release uuid, p_approval uuid, p_key text) returns bigint
language plpgsql as $$
declare
  v_rel public.preview_releases%rowtype;
  v_ful private.project_fulfillment_status;
  v_first boolean;
  v_event bigint;
  v_canon public.domain_events%rowtype;
begin
  select * into v_rel from public.preview_releases where id = p_release;
  if not found then
    insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by)
    values (p_release, p_project,
      coalesce((select max(r.release_number) from public.preview_releases r where r.project_id = p_project), 0) + 1,
      substr(encode(sha256(convert_to(p_release::text, 'UTF8')), 'hex'), 1, 40),
      'dpl_' || substr(replace(p_release::text, '-', ''), 1, 24), 'https://preview.example.test/' || p_release,
      (select s.user_id from public.staff_roles s where s.role = 'admin' and s.status = 'active' order by s.user_id limit 1))
    returning * into v_rel;
  end if;
  -- OI-113 (AUTH-013 fixture integrity): only a call that creates the release's first approval
  -- emits WP-C's canonical event (as approve_preview does); later calls use the supplied
  -- non-canonical key. A canonical event is never fabricated, replaced or repaired.
  v_first := not exists (select 1 from public.preview_approvals where release_id = v_rel.id);
  if not exists (select 1 from public.preview_approvals where id = p_approval) then
    insert into public.preview_approvals (id, release_id, project_id, user_id)
    values (p_approval, v_rel.id, v_rel.project_id, (select m.user_id from public.project_memberships m
      where m.project_id = v_rel.project_id and private.staff_role_of(m.user_id) is null order by m.user_id limit 1));
  end if;
  if not v_first and p_key = 'release.approved:' || p_release::text then
    raise exception 'fixture: canonical key % is reserved for the first approval of release %', p_key, p_release;
  end if;
  v_event := private.emit_domain_event('release.approved', p_project, 'preview_release', p_release::text,
    jsonb_build_object('release_id', v_rel.id, 'release_number', v_rel.release_number, 'approval_id', p_approval,
      'commit_sha', v_rel.commit_sha),
    case when v_first then 'release.approved:' || p_release::text else p_key end);
  -- (a) Exactly one canonical event (dedupe_key is unique), of the right type, subject and
  --     project, naming an approval of this release and project, and naming p_approval when
  --     this call created the release's first approval.
  select * into v_canon from public.domain_events where dedupe_key = 'release.approved:' || p_release::text;
  if v_canon.id is null or v_canon.event_type <> 'release.approved' or v_canon.subject_type <> 'preview_release'
     or v_canon.subject_id <> p_release::text or v_canon.project_id is distinct from p_project
     or not exists (select 1 from public.preview_approvals a where a.id::text = v_canon.payload ->> 'approval_id'
                     and a.release_id = p_release and a.project_id = p_project)
     or (v_first and v_canon.payload ->> 'approval_id' is distinct from p_approval::text) then
    raise exception 'fixture: release % has no consistent canonical release.approved event', p_release;
  end if;
  -- (b) The fulfillment interface reports this release and approval as current.
  v_ful := private.project_fulfillment_status(p_project);
  if v_ful.current_release_id is distinct from p_release or v_ful.current_release_approval_id is distinct from p_approval then
    raise exception 'fixture: release % / approval % is not WP-C current (current %, recorded %)',
      p_release, p_approval, v_ful.current_release_id, v_ful.current_release_approval_id;
  end if;
  return v_event;
end;
$$;
-- WP-C's emission of release.approved, simulated through the WP-0 writer (consumer contract:
-- subject_type preview_release, subject_id = release ID, payload.approval_id).
create function pg_temp.release_approved(p_project uuid, p_release uuid, p_approval uuid) returns bigint
language sql as $$
  select pg_temp.genuine_release_approved(p_project, p_release, p_approval, 'release.approved:' || p_approval::text);
$$;
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 0. Setup: Project A reaches a verified deposit through the real workflow
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'os1', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'professional',
  '["Ten-page website"]'::jsonb) ->> 'order_summary_id';
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'acc1', public.accept_agreement((select v::uuid from ids where k = 'os1'), true, true, 'Alex Client',
  'Synthetic Business A LLC', 'Managing Member', true) ->> 'acceptance_id';
insert into ids select 'cs', public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'checkout_session_id';
reset role;
select pg_temp.as_service();
select public.record_outbound_result(id, 'succeeded', 'cus_TestA000001', false, 200, null, '{}')
  from public.outbound_stripe_requests where purpose = 'customer_create';
select public.record_outbound_result(id, 'succeeded', 'cs_test_A000001', false, 200, null,
  '{"url": "https://checkout.stripe.com/c/pay/cs_test_A000001"}') from public.outbound_stripe_requests where purpose = 'checkout_session_create';
reset role;
select is(pg_temp.deliver(pg_temp.evt('evt_setup0000001', 'checkout.session.completed', jsonb_build_object('id', 'cs_test_A000001',
  'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd', 'amount_total', 39800, 'payment_status', 'paid',
  'customer', 'cus_TestA000001', 'subscription', 'sub_TestA000001', 'invoice', 'in_TestA000001',
  'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0', 'order_summary_id', (select v from ids where k = 'os1'),
    'acceptance_id', (select v from ids where k = 'acc1'), 'checkout_record_id', (select v from ids where k = 'cs'))))) ->> 'status',
  'processed', 'setup: the deposit is verified from a synthetic signed-format event');
select is(pg_temp.deliver(pg_temp.evt('evt_setup0000002', 'customer.subscription.created', jsonb_build_object('id', 'sub_TestA000001',
  'object', 'subscription', 'status', 'active', 'customer', 'cus_TestA000001',
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0')))) ->> 'status', 'processed',
  'setup: the subscription mirror is active');

-- ---------------------------------------------------------------------------
-- 1. Reacceptance after a material change (04 §1, §4; T-AGR-04; OI-81)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'prestige', '[]'::jsonb, null, 'Upgrade') ->> 'error',
  'price_change_after_deposit', 'OI-81: a summary whose price differs from the accepted one is rejected once the deposit is verified');
select ok(exists (select 1 from public.audit_events where action = 'order_summary.price_change_rejected'),
  'OI-81: the rejection is audited');
insert into ids select 'os2', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'professional',
  '["Ten-page website", "Blog"]'::jsonb, null, 'Scope adds a blog at the same price') ->> 'order_summary_id';
reset role;
select is((select state::text from private.project_agreement_state('20000000-0000-4000-8000-0000000000a0')), 'reacceptance_required',
  'T-AGR-04: a material change moves the agreement to reacceptance_required');
select ok(not (private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).agreement_effective
  and (private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).deposit_verified,
  'T-AGR-04 / G1: the gate interface reports G1 unmet while the deposit stays verified (separate domains)');
select ok(exists (select 1 from public.domain_events where event_type = 'agreement.reacceptance_required')
  and exists (select 1 from public.notification_outbox where notification_type = 'agreement.reacceptance_required'),
  'reacceptance_required is emitted and the client is notified');
insert into ids select 'ev0', pg_temp.release_approved('20000000-0000-4000-8000-0000000000a0',
  '30000000-0000-4000-8000-000000000000', '40000000-0000-4000-8000-000000000000')::text;
select is(pg_temp.consume() #>> '{results,0,outcome}', 'rejected',
  'T-AGR-04: an approval while reacceptance is required creates no final-balance invoice');
select ok(not exists (select 1 from public.final_balance_invoices)
  and exists (select 1 from public.notification_outbox where notification_type = 'payment.final_balance_blocked'),
  'the blocked obligation is an Owner intervention item');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'acc2', public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'Alex Client',
  'Synthetic Business A LLC', 'Managing Member', true) ->> 'acceptance_id';
reset role;
select is((select state::text from private.project_agreement_state('20000000-0000-4000-8000-0000000000a0')), 'effective',
  'T-AGR-04: re-acceptance restores effective (deposit already verified)');
select is((select count(*)::integer from public.domain_events where event_type = 'agreement.effective'), 2,
  'each acceptance becomes effective exactly once');

-- ---------------------------------------------------------------------------
-- 2. The final-balance obligation (04 §10; T-PAY-09, financial integrity; the retired T-PAY-17 is superseded by T-PAY-13)
-- ---------------------------------------------------------------------------
insert into ids select 'evB', pg_temp.release_approved('20000000-0000-4000-8000-0000000000b0',
  '30000000-0000-4000-8000-0000000000b1', '40000000-0000-4000-8000-0000000000b1')::text;
select is(pg_temp.consume() #>> '{results,0,outcome}', 'rejected',
  'T-PAY-09: an approval without an effective agreement and verified deposit creates nothing');
select is((select count(*)::integer from public.final_balance_invoices where project_id = '20000000-0000-4000-8000-0000000000b0'), 0,
  'T-PAY-09: no final-balance invoice exists for Project B');

insert into ids select 'ev1', pg_temp.release_approved('20000000-0000-4000-8000-0000000000a0',
  '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001')::text;
select is(pg_temp.consume() #>> '{results,0,outcome}', 'created', 'T-PAY-13: the approval creates the obligation');
select is(jsonb_array_length(pg_temp.consume() -> 'results'), 0, 'a second run finds nothing to consume');
insert into ids select 'fbi', id::text from public.final_balance_invoices where project_id = '20000000-0000-4000-8000-0000000000a0';
select ok((select order_summary_id = (select v::uuid from ids where k = 'os2') and amount_cents = 119600
           and balance_price_id = 'price_1Uf5HzK5j4r4WkVPRH6Wkz6D' and collection_method = 'charge_automatically'
           and collection_mode = 'hosted_only' and default_payment_method_id is null
           and approval_id = '40000000-0000-4000-8000-000000000001' and release_id = '30000000-0000-4000-8000-000000000001'
           and stripe_customer_id = 'cus_TestA000001' and status = 'creating'
           from public.final_balance_invoices where id = (select v::uuid from ids where k = 'fbi')),
  'T-PAY-13 / T-PAY-19: one obligation for the snapshot balance, referencing the approval and release; with no active authorization, hosted only');
select ok((select idempotency_key = 'wpb-final-balance-' || (select v from ids where k = 'os2') || '-40000000-0000-4000-8000-000000000001-a1'
           and request_params -> 'lines' = '[{"price": "price_1Uf5HzK5j4r4WkVPRH6Wkz6D", "quantity": 1}]'::jsonb
           and request_params -> 'discounts' = '[]'::jsonb and request_params ->> 'collection_method' = 'charge_automatically'
           and request_params -> 'auto_advance' = 'false'::jsonb and not request_params ? 'default_payment_method'
           and (request_params ->> 'expected_amount_due')::integer = 119600
           from public.outbound_stripe_requests where purpose = 'final_balance_invoice_create'),
  'T-PAY-19 / T-BIL-22: a single balance line, no discount, no automatic attempt (auto_advance false), key from order summary and approval');
select is(private.project_final_balance_state('20000000-0000-4000-8000-0000000000a0')::text, 'due', 'the balance is due on approval');
select ok(exists (select 1 from public.audit_events where action = 'balance.collection_authorized' and category = 'financial'
                  and summary ->> 'approval_id' = '40000000-0000-4000-8000-000000000001'),
  'balance.collection_authorized is audited with the approval ID');

-- Replays, repeated approvals, later releases, a superseding summary: never a second obligation.
select is(private.consume_release_approved((select v::bigint from ids where k = 'ev1')), 'already_consumed',
  'a replayed release.approved event is already consumed');
-- AUTH-006 Amendment 2: SYNTHETIC consumer-defense test construction, not a WP-C emission. A re-delivery of
-- release ...001's recorded approval under a distinct deduplication key: WP-C's approve_preview emits
-- release.approved once per release (on its first approval, key release.approved:<release_id>) and never this.
-- Release ...001 is current when it is emitted and superseded (release ...002, below) when it is consumed.
insert into ids select 'out_before', count(*)::text from public.outbound_stripe_requests;
select pg_temp.genuine_release_approved('20000000-0000-4000-8000-0000000000a0', '30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001', 'release.approved:redelivery:40000000-0000-4000-8000-000000000001');
select pg_temp.release_approved('20000000-0000-4000-8000-0000000000a0', '30000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000003');
select is((select array_agg(r ->> 'outcome') from jsonb_array_elements(pg_temp.consume() -> 'results') r),
  array['rejected', 'duplicate_obligation'],
  'T-PAY-13 / OI-92: an approval of a superseded release is rejected; the current release''s approval collapses onto the existing obligation');
select ok((select count(*) from public.final_balance_invoices) = 1
  and (select count(*) from public.outbound_stripe_requests where purpose = 'final_balance_invoice_create') = 1,
  'T-PAY-13: exactly one obligation and one outbound create exist');
-- AUTH-006 Amendment 2, C-2: the superseded approval took the 04 §10.2 rejection path (detail, audit,
-- Owner notification) and added no outbound request.
insert into ids select 'ev_sup', id::text from public.domain_events
 where dedupe_key = 'release.approved:redelivery:40000000-0000-4000-8000-000000000001';
select is((select detail from private.event_consumptions where consumer = 'wpb.final_balance_invoice'
            and domain_event_id = (select v::bigint from ids where k = 'ev_sup')), 'release_superseded',
  'C-2 / OI-92: the superseded release''s approval is rejected as release_superseded');
select ok(exists (select 1 from public.audit_events where action = 'release_approval.rejected' and category = 'financial'
                   and target_type = 'domain_event' and target_id = (select v from ids where k = 'ev_sup')
                   and summary ->> 'detail' = 'release_superseded')
  and exists (select 1 from public.notification_outbox where notification_type = 'payment.final_balance_blocked'
               and idempotency_key = 'payment.final_balance_blocked:' || (select v from ids where k = 'ev_sup') || ':1'),
  'C-2: the rejection is audited and the Owner is notified');
select is((select count(*)::text from public.outbound_stripe_requests), (select v from ids where k = 'out_before'),
  'C-2: no outbound request is added by the rejected or the duplicate approval');
-- AUTH-006 Amendment 2, C-1: a further event for the current release and its recorded approval, under a
-- distinct deduplication key (SYNTHETIC consumer-defense test construction; WP-C never emits it), creates
-- no second obligation.
select pg_temp.genuine_release_approved('20000000-0000-4000-8000-0000000000a0', '30000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000003', 'release.approved:redelivery:40000000-0000-4000-8000-000000000003');
select is(pg_temp.consume() #>> '{results,0,outcome}', 'duplicate_obligation',
  'C-1: a valid current-release approval cannot create a second obligation');
select ok((select count(*) from public.final_balance_invoices) = 1
  and (select count(*) from public.outbound_stripe_requests where purpose = 'final_balance_invoice_create') = 1,
  'C-1: still exactly one obligation and one outbound create');
select throws_ok($$ insert into public.final_balance_invoices (project_id, order_summary_id, acceptance_id, approval_id, release_id,
    source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode)
  select project_id, (select v::uuid from ids where k = 'os1'), acceptance_id, gen_random_uuid(), gen_random_uuid(),
    source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode from public.final_balance_invoices $$,
  '23505', null, 'the database forbids a second non-void obligation for the project, even under another order summary');
select throws_ok($$ insert into public.final_balance_invoices (project_id, order_summary_id, acceptance_id, approval_id, release_id,
    source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode, status)
  select project_id, order_summary_id, acceptance_id, gen_random_uuid(), gen_random_uuid(),
    source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode, 'void' from public.final_balance_invoices $$,
  '23505', null, 'the database forbids a second obligation for the same order summary');
select throws_ok($$ update public.final_balance_invoices set amount_cents = 1 $$, '42501', null, 'the obligation is immutable');

-- Hosted invoice, failure, mismatch, verified payment, stale failure (04 §10, §11; T-ARC-03).
select pg_temp.as_service();
select is(public.record_outbound_result((select id from public.outbound_stripe_requests where purpose = 'final_balance_invoice_create'),
  'succeeded', 'in_TestAFB00001', false, 200, null, '{"hosted_invoice_url": "https://invoice.stripe.com/i/acct_test/in_TestAFB00001"}')
  ->> 'status', 'succeeded', 'the invoice create result is recorded');
reset role;
select is(private.project_final_balance_state('20000000-0000-4000-8000-0000000000a0')::text, 'pending',
  'the balance is pending once the invoice is open on its hosted page');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.project_billing_status('20000000-0000-4000-8000-0000000000a0') ->> 'final_invoice_url',
  'https://invoice.stripe.com/i/acct_test/in_TestAFB00001', 'R1: the client pays on the Stripe-hosted invoice page');
reset role;
create temporary table inv (body jsonb) on commit drop;
grant all on inv to service_role;
insert into inv select jsonb_build_object('id', 'in_TestAFB00001', 'object', 'invoice', 'billing_reason', 'manual', 'currency', 'usd',
  'amount_paid', 119600, 'customer', 'cus_TestA000001', 'hosted_invoice_url', 'https://invoice.stripe.com/i/acct_test/in_TestAFB00001',
  'payment_intent', 'pi_TestAFB00001', 'total_discount_amounts', '[]'::jsonb,
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0', 'order_summary_id', (select v from ids where k = 'os2'),
    'final_balance_invoice_id', (select v from ids where k = 'fbi')),
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
    'pricing', jsonb_build_object('price_details', jsonb_build_object('price', 'price_1Uf5HzK5j4r4WkVPRH6Wkz6D'))))));
select is(pg_temp.deliver(pg_temp.evt('evt_fbfail000001', 'invoice.payment_failed', (select body from inv), 10)) ->> 'status', 'processed',
  'a failed final payment is processed');
select ok(private.project_final_balance_state('20000000-0000-4000-8000-0000000000a0') = 'failed'
  and exists (select 1 from public.notification_outbox where notification_type = 'payment.final_action_required'),
  'the balance is failed and the client is offered the hosted page for the same invoice');
select is(pg_temp.deliver(pg_temp.evt('evt_fbpaid00bad1', 'invoice.paid', (select body from inv) || '{"amount_paid": 119500}', 20)) ->> 'reason',
  'amount_mismatch', 'an amount that differs from the snapshot is quarantined');
select is(pg_temp.deliver(pg_temp.evt('evt_fbpaid00bad2', 'invoice.paid', jsonb_set((select body from inv), '{lines,data}',
  (select body #> '{lines,data}' from inv) || '[{"quantity": 1, "price": {"id": "price_1Uf5I2K5j4r4WkVPJodSnaBe"}}]'::jsonb), 21)) ->> 'reason',
  'line_items_mismatch', 'an invoice carrying any line besides the balance price is quarantined');
select is(private.project_final_balance_state('20000000-0000-4000-8000-0000000000a0')::text, 'failed',
  'quarantined events never verify the balance');
select is(pg_temp.deliver(pg_temp.evt('evt_fbpaid000001', 'invoice.paid', (select body from inv), 30)) ->> 'status', 'processed',
  'the paid final-balance invoice is processed');
select ok(private.project_final_balance_state('20000000-0000-4000-8000-0000000000a0') = 'verified'
  and (select count(*) from public.ledger_entries where entry_type = 'balance_charge' and amount_cents = 119600) = 1
  and exists (select 1 from public.domain_events where event_type = 'payment.balance_verified'),
  'T-PAY-13: the balance is verified only from the webhook, with one balance_charge entry');
select is(pg_temp.deliver(pg_temp.evt('evt_fbfail000002', 'invoice.payment_failed', (select body from inv), 5)) ->> 'status', 'ignored',
  'T-ARC-03: invoice.payment_failed after invoice.paid is ignored');
select is(private.project_final_balance_state('20000000-0000-4000-8000-0000000000a0')::text, 'verified',
  'T-ARC-03: the stale failure does not move the balance backwards');
select is(pg_temp.deliver(pg_temp.evt('evt_fbpaid000001', 'invoice.paid', (select body from inv), 30)) ->> 'duplicate', 'true',
  'a replayed payment is a duplicate');
select is((select count(*)::integer from public.ledger_entries where entry_type = 'balance_charge'), 1, 'no second balance entry');
-- B1: the two quarantined final-balance events above are unresolved anomalies of the
-- final-balance charge, so G4 fails closed although a valid payment is verified.
select is((private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).evidence -> 'blocking_anomalies',
  '{"G2": [], "G4": ["quarantined_event"]}'::jsonb,
  'B1: unresolved quarantined final-balance events block G4 only (attributed to the final-balance charge)');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select results_eq($$ select deposit_requirement_satisfied, final_balance_requirement_satisfied, publication_financially_eligible,
    owner_intervention_required from public.operational_payment_states(array['20000000-0000-4000-8000-0000000000a0'::uuid]) $$,
  $$ values (true, false, false, true) $$,
  'B1 / OI-72: while the anomaly is open, Admin sees the final balance unsatisfied, not eligible, and Owner intervention');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is((select array_agg(public.resolve_quarantined_event(id, 'Reviewed: mismatched copies of the paid invoice') -> 'gates' ->> 'G4' order by id)
           from public.webhook_events where stripe_event_id in ('evt_fbpaid00bad1', 'evt_fbpaid00bad2')),
  array['false', 'true'], 'B1: resolving one anomaly leaves G4 blocked by the other; the last review re-derives G4 from the valid payment');
reset role;
select is((select count(*)::integer from public.audit_events where action = 'quarantine.resolved'
           and project_id = '20000000-0000-4000-8000-0000000000a0'), 2, 'each resolution is audited against the project');
select is((select count(*)::integer from public.ledger_entries where entry_type = 'balance_charge'), 1,
  'B1: a resolution posts nothing');
select is((select row(s.contract_version, s.implemented, s.agreement_effective, s.deposit_verified, s.balance_verified_or_settled,
                      s.balance_settled_by_adjustment, cardinality(s.active_billing_holds))::text
           from private.project_financial_status('20000000-0000-4000-8000-0000000000a0') s), '(3,t,t,t,t,f,0)',
  'OI-71: G1, G2 and G4 are satisfied, no adjustment, no WP-B hold');

-- ---------------------------------------------------------------------------
-- 3. Failed maintenance recovery and the maintenance_payment_hold (04 §9.1; OI-26, OI-46)
-- ---------------------------------------------------------------------------
create temporary table renew (k text primary key, body jsonb) on commit drop;
grant all on renew to service_role;
insert into renew select k, jsonb_build_object('id', id, 'object', 'invoice', 'billing_reason', 'subscription_cycle', 'currency', 'usd',
  'amount_paid', 9900, 'customer', 'cus_TestA000001', 'subscription', 'sub_TestA000001', 'payment_intent', pi,
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
    'pricing', jsonb_build_object('price_details', jsonb_build_object('price', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))))
from (values ('recent', 'in_TestARenew01', 'pi_TestARenew01'), ('old', 'in_TestARenew02', 'pi_TestARenew02'),
             ('older', 'in_TestARenew03', 'pi_TestARenew03')) v(k, id, pi);

select is(pg_temp.deliver(pg_temp.evt('evt_renewfail001', 'invoice.payment_failed', (select body from renew where k = 'recent'), -2 * 86400))
  ->> 'status', 'processed', 'a failed renewal two days ago starts recovery');
select ok((select recovery_ends_at = private.end_of_local_day(private.local_date(failed_at) + 7)
             and recovery_ends_at > now() and calendar_version = 'us-federal-5usc6103-v1'
           from public.maintenance_recoveries where stripe_invoice_id = 'in_TestARenew01'),
  'T-CAL-04: the recovery deadline is stored once in UTC with its calendar version');
select is((pg_temp.jobs() ->> 'holds_placed')::integer, 0, 'T-BIL-01: no hold during the seven-day recovery period');
select ok(not exists (select 1 from public.billing_holds) and not exists (select 1 from public.service_terminations),
  'T-BIL-14: through the recovery period, no hold and no termination state');
select is(pg_temp.deliver(pg_temp.evt('evt_renewfail002', 'invoice.payment_failed', (select body from renew where k = 'old'), -10 * 86400))
  ->> 'status', 'processed', 'a failure ten days ago is recorded');
select is((pg_temp.jobs() ->> 'holds_placed')::integer, 1, 'T-BIL-01: the hold is placed after seven full days unresolved');
insert into ids select 'hold', id::text from public.billing_holds where hold_type = 'maintenance_payment_hold';
select ok((select trigger_source = 'system' and cleared_at is null from public.billing_holds where id = (select v::uuid from ids where k = 'hold'))
  and exists (select 1 from public.notification_outbox where notification_type = 'billing.hold_review_required' and recipient_roles = '{owner}')
  and not exists (select 1 from public.service_terminations),
  'T-BIL-14: after the period the hold exists, an Owner review item exists, and no termination starts');
select is((private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).active_billing_holds::text,
  '{maintenance_payment_hold}', 'T-BIL-02 / G8: the hold is reported to the gate evaluator and blocks publication');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok(public.project_billing_status('20000000-0000-4000-8000-0000000000a0') ->> 'billing_hold_active' = 'true'
  and (select count(*) from public.order_summaries) = 2,
  'T-BIL-02: the client keeps portal access and sees the hold');
reset role;
select is((pg_temp.jobs() ->> 'holds_placed')::integer, 0, 'the hold job is idempotent');

-- Owner controls on the system hold (03 §4, §7; OI-26).
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.clear_billing_hold((select v::uuid from ids where k = 'hold'), 'x') ->> 'error', 'forbidden', 'an Admin cannot clear a billing hold');
select ok((select count(*) from public.billing_holds) = 0, 'OI-72: an Admin cannot read billing hold records');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.clear_billing_hold((select v::uuid from ids where k = 'hold'), 'x') ->> 'error', 'forbidden',
  'a system hold exception needs fresh reauthentication');
select is(public.decide_billing_hold_review((select v::uuid from ids where k = 'hold'), 'continue_collection', 'Stripe retries continue') ->> 'ok',
  'true', 'the Owner records a continue-collection review decision');
reset role;
select is(pg_temp.deliver(pg_temp.evt('evt_renewpaid002', 'invoice.paid', (select body from renew where k = 'old'), 60)) ->> 'status',
  'processed', 'the recovery payment is processed');
select ok((select clear_kind = 'verified_recovery' and cleared_at is not null from public.billing_holds where id = (select v::uuid from ids where k = 'hold'))
  and (select status = 'recovered' from public.maintenance_recoveries where stripe_invoice_id = 'in_TestARenew02')
  and exists (select 1 from public.ledger_entries where dedupe_key = 'invoice:in_TestARenew02:maintenance' and amount_cents = 9900),
  'T-BIL-03: verified recovery clears the hold automatically and posts the maintenance charge');
select is(pg_temp.deliver(pg_temp.evt('evt_renewpaid001', 'invoice.paid', (select body from renew where k = 'recent'), 61)) ->> 'status',
  'processed', 'recovery within the window is processed');
select ok((select status = 'recovered' from public.maintenance_recoveries where stripe_invoice_id = 'in_TestARenew01')
  and (select count(*) from public.billing_holds) = 1, 'T-BIL-01: recovery within the window places no hold');

-- Manual holds: Owner only, with a reason (03 §4; 04 §14).
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold', 'x') ->> 'error', 'forbidden',
  'an Admin cannot place an owner_manual_hold');
reset role;
select ok(exists (select 1 from public.audit_events where action = 'hold.placement_denied'), 'the denied attempt is audited');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'maintenance_payment_hold', 'x') ->> 'error',
  'hold_type_not_manual', 'the Owner cannot fabricate a system hold');
select is(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold', ' ') ->> 'error', 'reason_required',
  'a manual hold needs a reason');
insert into ids select 'manual', public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold',
  'Awaiting brand sign-off') ->> 'hold_id';
select is(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold', 'again') ->> 'existing', 'true',
  'placing the same manual hold twice returns the active hold');
select ok(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'dispute_risk_hold', 'Chargeback risk') ->> 'ok' = 'true',
  'the Owner places a dispute_risk_hold (OI-37)');
reset role;
select is((private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).active_billing_holds::text,
  '{dispute_risk_hold,owner_manual_hold}', 'OI-71 item 3: both Owner holds are reported in active_billing_holds');

-- ---------------------------------------------------------------------------
-- 4. The OI-72 derived projection (03 §4; 05 §9)
-- ---------------------------------------------------------------------------
select results_eq($$ select n::text collate "default", format_type(t, null)::text collate "default" from pg_proc p,
    unnest(p.proallargtypes, p.proargmodes, p.proargnames) x(t, m, n)
    where p.oid = 'public.operational_payment_states(uuid[])'::regprocedure and m = 't' $$,
  $$ values ('project_id', 'uuid'), ('deposit_requirement_satisfied', 'boolean'), ('final_balance_requirement_satisfied', 'boolean'),
            ('payment_recovery_required', 'boolean'), ('publication_financially_eligible', 'boolean'),
            ('billing_operational_hold', 'boolean'), ('owner_intervention_required', 'boolean') $$,
  'OI-72: the projection returns exactly the six approved derived states as booleans (no amounts or records)');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select results_eq($$ select deposit_requirement_satisfied, final_balance_requirement_satisfied, payment_recovery_required,
    publication_financially_eligible, billing_operational_hold, owner_intervention_required
    from public.operational_payment_states(array['20000000-0000-4000-8000-0000000000a0'::uuid]) $$,
  $$ values (true, true, true, false, true, false) $$,
  'OI-72: an Admin reads derived states only: requirements met, recovery required (no payment authorization, OI-74), billing-related hold, not eligible; no Owner intervention once the B1 anomalies are reviewed');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select throws_ok($$ select * from public.operational_payment_states() $$, '42501', null, 'staff below aal2 cannot read the projection');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select throws_ok($$ select * from public.operational_payment_states() $$, '42501', null, 'clients cannot read the staff projection');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select ok(public.clear_billing_hold((select v::uuid from ids where k = 'manual'), 'Sign-off received') ->> 'ok' = 'true'
  and public.clear_billing_hold((select id from public.billing_holds where hold_type = 'dispute_risk_hold' and cleared_at is null),
        'Risk resolved') ->> 'ok' = 'true', 'the Owner clears manual holds with a reason');
select is((select publication_financially_eligible from public.operational_payment_states(array['20000000-0000-4000-8000-0000000000a0'::uuid])),
  true, 'with no WP-B hold, the financial publication requirements are met');
select is((select owner_intervention_required from public.operational_payment_states(array['20000000-0000-4000-8000-0000000000b0'::uuid])),
  true, 'the blocked Project B approval shows to staff only as "Owner intervention required"');
reset role;

-- ---------------------------------------------------------------------------
-- 5. Billing-hold termination (OI-46; T-BIL-16, T-BIL-17, T-ROLE-06)
-- ---------------------------------------------------------------------------
select is(pg_temp.deliver(pg_temp.evt('evt_renewfail003', 'invoice.payment_failed', (select body from renew where k = 'older'), -20 * 86400))
  ->> 'status', 'processed', 'another unresolved failure');
select is((pg_temp.jobs() ->> 'holds_placed')::integer, 1, 'its hold is placed');
insert into ids select 'hold2', id::text from public.billing_holds where hold_type = 'maintenance_payment_hold' and cleared_at is null;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.decide_billing_hold_review((select v::uuid from ids where k = 'hold2'), 'initiate_termination', 'Unpaid') ->> 'error',
  'forbidden', 'T-ROLE-06: initiating termination needs fresh reauthentication');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'term', public.decide_billing_hold_review((select v::uuid from ids where k = 'hold2'), 'initiate_termination',
  'Unpaid after recovery and outreach') ->> 'termination_id';
select is(public.decide_billing_hold_review((select v::uuid from ids where k = 'hold2'), 'initiate_termination', 'again') ->> 'error',
  'termination_already_active', 'T-BIL-16: at most one active termination per project');
select ok(public.authorize_service_termination((select v::uuid from ids where k = 'term'), current_date - 100, 'Documented termination') ->> 'existing' = 'false'
  and public.authorize_service_termination((select v::uuid from ids where k = 'term'), current_date - 50, 'duplicate') ->> 'existing' = 'true',
  'T-BIL-16: a duplicate authorization is idempotent');
reset role;
select ok((select count(*) = 1 from public.service_terminations)
  and (select effective_cancellation_date = current_date - 100
         and m1_deadline = private.end_of_local_day(private.add_business_days(current_date - 100, 12))
         and m2_deadline = private.end_of_local_day(current_date - 100 + 60) and calendar_version is not null
       from public.service_terminations),
  'T-BIL-16: exactly one termination with one set of M1 and M2 deadlines');
select is((pg_temp.jobs() ->> 'terminations_effective')::integer, 1, 'the termination becomes effective at its date');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_services_deactivated((select v::uuid from ids where k = 'term'), 'Offboarding') ->> 'error', 'notices_missing',
  'T-BIL-17: deactivation is rejected without the required notices');
select ok(public.record_termination_notice((select v::uuid from ids where k = 'term'), 'milestones_and_responsibilities') ->> 'ok' = 'true'
  and public.record_termination_notice((select v::uuid from ids where k = 'term'), 'm1_reached') ->> 'ok' = 'true'
  and public.record_termination_notice((select v::uuid from ids where k = 'term'), 'm2_minus_30_days') ->> 'ok' = 'true'
  and public.record_termination_notice((select v::uuid from ids where k = 'term'), 'm2_minus_7_days') ->> 'ok' = 'true',
  'the Owner records each required notice');
select is(public.record_maintenance_ceased((select v::uuid from ids where k = 'term'), 'M1 passed') ->> 'ok', 'true',
  'maintenance cessation is accepted after M1');
reset role;
delete from private.environment_settings;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_services_deactivated((select v::uuid from ids where k = 'term'), 'Offboarding') ->> 'error', 'legal_terms_pending',
  '04 §15.1: M2 deactivation is never enforced in production before counsel-approved terms');
reset role;
insert into private.environment_settings (app_env) values ('development');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_services_deactivated((select v::uuid from ids where k = 'term'), 'Offboarding after M2') ->> 'ok', 'true',
  'T-BIL-17: deactivation is accepted after M2 with every notice recorded');
reset role;
select is(pg_temp.deliver(pg_temp.evt('evt_subdeleted01', 'customer.subscription.deleted', jsonb_build_object('id', 'sub_TestA000001',
  'object', 'subscription', 'status', 'canceled', 'customer', 'cus_TestA000001'), 90)) ->> 'status', 'processed',
  'a deletion matching an authorized termination is processed');
select is((select count(*)::integer from public.stripe_cancellation_exceptions), 0,
  'a deletion that matches an authorized termination is not an exception');

-- ---------------------------------------------------------------------------
-- 6. Client cancellation requests (04 §15.1.1; T-BIL-07, T-BIL-17)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.submit_cancellation_request('20000000-0000-4000-8000-0000000000b0') ->> 'error', 'not_found',
  'a client cannot request cancellation for another project');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
insert into ids select 'creq', public.submit_cancellation_request('20000000-0000-4000-8000-0000000000b0') ->> 'cancellation_request_id';
select is(public.submit_cancellation_request('20000000-0000-4000-8000-0000000000b0') ->> 'cancellation_request_id',
  (select v from ids where k = 'creq'), 'a repeated request returns the open request');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.confirm_cancellation((select v::uuid from ids where k = 'creq'), current_date) ->> 'error', 'forbidden',
  'an Admin cannot confirm a cancellation');
reset role;
insert into ids select 'eff', (private.local_date(now()) + 3)::text;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'cterm', public.confirm_cancellation((select v::uuid from ids where k = 'creq'),
  (select v::date from ids where k = 'eff')) ->> 'termination_id';
reset role;
select ok((select r.request_date <> t.effective_cancellation_date::timestamptz and t.effective_cancellation_date = private.local_date(now()) + 3
           and t.m1_deadline = private.end_of_local_day(private.add_business_days(t.effective_cancellation_date, 12))
           and t.m2_deadline = private.end_of_local_day(t.effective_cancellation_date + 60)
           from public.cancellation_requests r join public.service_terminations t on t.cancellation_request_id = r.id
           where r.id = (select v::uuid from ids where k = 'creq')),
  'T-BIL-07 / T-CAL-06: request and effective dates are separate; M1 and M2 are computed and stored');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_maintenance_ceased((select v::uuid from ids where k = 'cterm'), 'early') ->> 'error', 'invalid_state',
  'nothing ceases before the effective cancellation date');
reset role;
update public.service_terminations set effective_cancellation_date = private.local_date(now()),
  m1_deadline = (private.termination_deadlines(private.local_date(now()))).m1,
  m2_deadline = (private.termination_deadlines(private.local_date(now()))).m2
  where id = (select v::uuid from ids where k = 'cterm');
select is((pg_temp.jobs() ->> 'terminations_effective')::integer, 1, 'the cancellation becomes effective on its date');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_maintenance_ceased((select v::uuid from ids where k = 'cterm'), 'early') ->> 'error', 'before_m1',
  'T-BIL-17: maintenance discontinuation is rejected before M1');
select is(public.record_services_deactivated((select v::uuid from ids where k = 'cterm'), 'early') ->> 'error', 'before_m2',
  'T-BIL-17: deactivation is rejected before M2');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select ok((select count(*) = 1 and bool_and(m1_deadline is not null and m2_deadline is not null) from public.service_terminations),
  'the client sees its own milestones');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select count(*)::integer from public.service_terminations) + (select count(*)::integer from public.cancellation_requests), 0,
  'OI-72: an Admin reads no termination or cancellation record');
reset role;

select * from finish();
rollback;
