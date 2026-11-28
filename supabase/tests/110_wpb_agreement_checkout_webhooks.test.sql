-- WP-B: agreement versions and the test-only fixture, order summaries, acceptance evidence,
-- the initial Checkout, outbound request idempotency, durable webhook ingestion, processing,
-- replay, out-of-order delivery, quarantine, the append-only ledger, refunds, disputes,
-- reconciliation, and cross-tenant isolation of every WP-B table touched here.
-- Synthetic Stripe-format events only (OI-63); no Stripe request is made anywhere.
-- Seed: Owner …01, Admin …02, client A …a1 (Project A …a0), client B …b1 (Project B …b0).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(142);

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
create function pg_temp.evt(p_id text, p_type text, p_obj jsonb, p_offset integer default 0, p_livemode jsonb default 'false')
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type, 'api_version', '2026-09-30.endive',
    'livemode', p_livemode, 'created', extract(epoch from now())::bigint + p_offset, 'data', jsonb_build_object('object', p_obj));
$$;
-- Ingest then process, as the webhook route does (server role). Returns the processing result.
create function pg_temp.deliver(p_event jsonb) returns jsonb language plpgsql as $$
declare
  v_ingest jsonb;
  v_result jsonb;
begin
  perform pg_temp.as_service();
  v_ingest := public.ingest_stripe_event(p_event, repeat('a', 64));
  if not (v_ingest ->> 'ok')::boolean then
    reset role;
    return v_ingest;
  end if;
  v_result := public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  reset role;
  return v_result || jsonb_build_object('duplicate', v_ingest -> 'duplicate');
end;
$$;
create function pg_temp.status_of(p_event_id text) returns text language sql as $$
  select processing_status::text from public.webhook_events where stripe_event_id = p_event_id;
$$;
grant execute on function pg_temp.evt(text, text, jsonb, integer, jsonb) to service_role, authenticated;
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;
-- AUTH-009 (setup): the one-time claim tokens, kept test-locally; never printed or asserted.
create temporary table claim_tokens (request_id uuid primary key, token uuid not null) on commit drop;
grant all on claim_tokens to service_role;
create function pg_temp.token(p_request_id uuid) returns uuid language sql as $$
  select token from claim_tokens where request_id = p_request_id;
$$;
grant execute on function pg_temp.token(uuid) to service_role;
-- AUTH-009 (setup): claim and confirm as the executor does; the token is stored, not returned.
create function pg_temp.claim(p_request_id uuid) returns jsonb language plpgsql as $$
declare
  v jsonb := public.outbound_request_for_execution(p_request_id);
begin
  if v ? 'claim_token' then
    insert into claim_tokens values (p_request_id, (v ->> 'claim_token')::uuid);
    perform public.confirm_outbound_dispatch(p_request_id, (v ->> 'claim_token')::uuid);
  end if;
  return v - 'claim_token';
end;
$$;
grant execute on function pg_temp.claim(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 1. Agreement versions and the test-only fixture (04 §2; OI-69; T-AGR-08, T-PAY-15)
-- ---------------------------------------------------------------------------
insert into ids select 'fixture', id::text from public.agreement_versions where version_label = 'test-fixture-1';
select ok((select is_test_fixture and status = 'approved' and not approved_for_production and contains_final_payment_clause
           and left(canonical_text, 31) = 'TEST FIXTURE — NOT AN AGREEMENT'
           and canonical_text = private.test_fixture_label() || E'\n\n' || private.final_payment_clause()
           from public.agreement_versions where version_label = 'test-fixture-1'),
  'T-AGR-08: the seeded fixture is labeled, approved for test use only, and holds only the verbatim §3.1 clause');
select ok(private.agreement_version_hash_ok((select v::uuid from ids where k = 'fixture'))
  and (select text_sha256 = private.sha256_hex(canonical_text) from public.agreement_versions where version_label = 'test-fixture-1'),
  'T-PAY-15: the stored SHA-256 matches the canonical text');
select throws_ok($$ update public.agreement_versions set approved_for_production = true where version_label = 'test-fixture-1' $$,
  '42501', null, 'T-AGR-08: the database refuses to approve a fixture for production use');
select ok(exists (select 1 from pg_constraint where conname = 'agreement_versions_fixture_never_production'
  and pg_get_constraintdef(oid) like '%NOT (is_test_fixture AND approved_for_production)%'),
  'T-AGR-08: a check constraint independently forbids a production-approved fixture');
select throws_ok($$ update public.agreement_versions set canonical_text = 'changed' where version_label = 'test-fixture-1' $$,
  '42501', null, 'agreement text is immutable');
select throws_ok($$ delete from public.agreement_versions where version_label = 'test-fixture-1' $$,
  '42501', null, 'agreement versions are never deleted');
-- OI-119 (AUTH-016, option A): setup-only guard. Aborts the file unless both classifications
-- are back to the seeded single development rows; it adds no pgTAP assertion.
create function pg_temp.oi119_assert_restored(p_site text) returns void language plpgsql as $oi119$
begin
  if (select count(*) from private.runtime_environment) <> 1
     or (select count(*) from private.environment_settings) <> 1
     or (select app_env from private.runtime_environment) <> 'development'
     or (select app_env from private.environment_settings) <> 'development' then
    raise exception 'OI-119: classifications not restored at %', p_site;
  end if;
end;
$oi119$;
-- OI-119: remove the runtime classification with the billing one, so they never disagree.
create temporary table oi119_runtime_110 on commit drop as select * from private.runtime_environment;
delete from private.runtime_environment;
delete from private.environment_settings;
select throws_ok($$ select private.install_test_agreement_fixture() $$, '42501', null,
  'T-AGR-08: the fixture cannot be installed in production');
select ok(not private.agreement_version_usable((select v::uuid from ids where k = 'fixture')),
  'T-AGR-08: in production the fixture is never usable for acceptance');
insert into private.environment_settings (app_env) values ('development');
insert into private.runtime_environment select * from oi119_runtime_110;
select pg_temp.oi119_assert_restored('110');

-- ---------------------------------------------------------------------------
-- 2. Order summaries (04 §4; 03 §4 "Prepare order summary")
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential') ->> 'error', 'forbidden',
  'a client cannot prepare an order summary');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential') ->> 'error', 'forbidden',
  'staff below aal2 cannot prepare an order summary');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'os1', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential')
  ->> 'order_summary_id';
select isnt((select v from ids where k = 'os1'), null, 'an Admin at aal2 prepares an order summary');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'nonexistent') ->> 'error', 'catalog_mismatch',
  'an unknown package resolves no verified prices');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'professional') ->> 'error', 'reason_required',
  'superseding a presented summary requires a reason');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'os2', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'professional',
  '[]'::jsonb, null, 'Client chose Professional') ->> 'order_summary_id';
reset role;
select results_eq($$ select status::text, revision from public.order_summaries
                     where project_id = '20000000-0000-4000-8000-0000000000a0' order by revision $$,
  $$ values ('superseded', 1), ('presented', 2) $$, 'a new summary supersedes the presented one (material change)');
select ok((select package_total_cents = 149500 and deposit_cents = 29900 and balance_cents = 119600 and maintenance_monthly_cents = 9900
           and deposit_price_id = 'price_1Uf5HyK5j4r4WkVPOtk24lGw' and balance_price_id = 'price_1Uf5HzK5j4r4WkVPRH6Wkz6D'
           and maintenance_price_id = 'price_1Uf5I2K5j4r4WkVPJodSnaBe' and catalog_environment = 'test'
           and business_legal_name = 'Synthetic Business A LLC'
           and snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(o)::text)
           from public.order_summaries o where id = (select v::uuid from ids where k = 'os2')),
  'the snapshot holds the package cents, test Price IDs, legal name and a reproducible hash');
select throws_ok($$ update public.order_summaries set deposit_cents = 1 where project_id = '20000000-0000-4000-8000-0000000000a0' $$,
  '42501', null, 'order summaries are immutable snapshots');
select results_eq($$ select p.package_key, v.deposit_cents + private.maintenance_monthly_cents()
                     from private.billing_packages p, private.verified_package_prices(p.package_key) v order by p.total_cents $$,
  $$ values ('essential', 25900), ('professional', 39800), ('advanced', 59800), ('signature', 79800), ('prestige', 109800) $$,
  'T-PAY-01: the initial charge is deposit + 9900 for every package (04 §8 table)');

-- ---------------------------------------------------------------------------
-- 3. Acceptance (04 §3; T-AGR-01, -03, -05, -06; T-ROLE-04)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'X', 'Y', 'Z', true) ->> 'error',
  'forbidden', 'T-AGR-05 / T-ROLE-04: the Owner cannot accept on the client''s behalf');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'X', 'Y', 'Z', true) ->> 'error',
  'forbidden', 'T-AGR-05 / T-ROLE-04: an Admin cannot accept on the client''s behalf');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'X', 'Y', 'Z', true) ->> 'error',
  'not_found', 'a client of Project B cannot accept Project A''s summary');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), false, true, 'Alex Client', 'Synthetic Business A LLC', 'Owner', true) ->> 'error',
  'explicit_acceptance_required', 'T-AGR-01: acceptance without an explicit true value is rejected');
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), null, true, 'Alex Client', 'Synthetic Business A LLC', 'Owner', true) ->> 'error',
  'explicit_acceptance_required', 'T-AGR-01: a missing acceptance value is rejected');
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), true, false, 'Alex Client', 'Synthetic Business A LLC', 'Owner', true) ->> 'error',
  'explicit_acceptance_required', 'T-AGR-06: the separate authority confirmation must be explicitly true');
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'Alex Client', 'Synthetic Business A LLC', ' ', true) ->> 'error',
  'signer_details_required', 'T-AGR-06: the signer title is required');
select is(public.accept_agreement((select v::uuid from ids where k = 'os1'), true, true, 'Alex Client', 'Synthetic Business A LLC', 'Owner', true) ->> 'error',
  'order_summary_superseded', 'acceptance of a superseded summary is rejected');
select is(public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'acceptance_required',
  'T-AGR-02: initial Checkout cannot start without a current acceptance');
insert into ids select 'acc', public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'Alex Client',
  'synthetic  business a llc', 'Managing Member', true) ->> 'acceptance_id';
select is(public.accept_agreement((select v::uuid from ids where k = 'os2'), true, true, 'Alex Client',
  'synthetic  business a llc', 'Managing Member', true) ->> 'acceptance_id', (select v from ids where k = 'acc'),
  'a resubmission by the same signer returns the existing acceptance');
reset role;
select ok((select a.agreement_version_id = (select v::uuid from ids where k = 'fixture')
           and a.agreement_text_sha256 = (select text_sha256 from public.agreement_versions where version_label = 'test-fixture-1')
           and a.order_summary_sha256 = o.snapshot_sha256 and a.signer_user_id = '00000000-0000-4000-8000-0000000000a1'
           and a.signer_verified_email = 'client.a@example.test' and a.signer_full_legal_name = 'Alex Client'
           and a.signer_title = 'Managing Member' and a.business_name_matches and a.authority_confirmed and a.accepted
           and a.checkbox_unchecked_by_default and a.includes_final_payment_clause
           and (a.price_snapshot ->> 'deposit_cents')::integer = 29900 and a.accepted_at is not null
           from public.agreement_acceptances a join public.order_summaries o on o.id = a.order_summary_id
           where a.id = (select v::uuid from ids where k = 'acc')),
  'T-AGR-03: the acceptance holds every 04 §3 evidence field and the hashes match');
select throws_ok($$ update public.agreement_acceptances set signer_title = 'x' $$, '42501', null, 'acceptances are insert-only');
select is((select state::text from private.project_agreement_state('20000000-0000-4000-8000-0000000000a0')),
  'accepted_pending_payment', 'the agreement is accepted, pending payment');
select is((select count(*)::integer from public.domain_events where event_type = 'agreement.accepted'
           and subject_id = (select v from ids where k = 'acc')), 1, 'agreement.accepted is emitted once');
select is((select count(*)::integer from public.domain_events where event_type = 'agreement.effective'), 0,
  'T-AGR-07: agreement.effective is not emitted at acceptance');

-- ---------------------------------------------------------------------------
-- 4. Initial Checkout and outbound requests (04 §8, §17 #2-#3; T-PAY-11, T-ARC-04/05, T-BIL-20)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'not_found',
  'T-PAY-11: a client cannot create a Checkout Session for another project');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'not_found',
  'staff cannot start a client''s Checkout');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'begin1', public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0')::text;
select is((select (v::jsonb ->> 'reused')::boolean from ids where k = 'begin1'), false, 'the first request creates a session record');
select is(public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'checkout_session_id',
  (select v::jsonb ->> 'checkout_session_id' from ids where k = 'begin1'),
  'T-ARC-05: a double click returns the same session record');
reset role;
insert into ids select 'cs1', v::jsonb ->> 'checkout_session_id' from ids where k = 'begin1';
insert into ids select 'req_customer', id::text from public.outbound_stripe_requests where purpose = 'customer_create';
insert into ids select 'req_cs1', id::text from public.outbound_stripe_requests where purpose = 'checkout_session_create';
select is((select count(*)::integer from public.checkout_sessions where project_id = '20000000-0000-4000-8000-0000000000a0'), 1,
  'exactly one session record exists');
select ok((select request_params -> 'line_items' = jsonb_build_array(
             jsonb_build_object('price', 'price_1Uf5HyK5j4r4WkVPOtk24lGw', 'quantity', 1),
             jsonb_build_object('price', 'price_1Uf5I2K5j4r4WkVPJodSnaBe', 'quantity', 1))
           and request_params ->> 'mode' = 'subscription' and request_params -> 'discounts' = '[]'::jsonb
           and request_params -> 'allow_promotion_codes' = 'false'::jsonb
           and request_params #> '{automatic_tax,enabled}' = 'false'::jsonb
           and (request_params ->> 'expected_amount_total')::integer = 39800
           from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_cs1')),
  'T-BIL-20 / T-PAY-01: exactly the standard deposit and maintenance prices, no discount or promotion code, total 39800');
select ok((select idempotency_key = 'wpb-checkout-' || (select v from ids where k = 'os2') || '-c1-a1'
           from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_cs1'))
  and (select idempotency_key = 'wpb-customer-10000000-0000-4000-8000-0000000000a0-a1'
       from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_customer')),
  'T-ARC-04: each create has a prior request row with a key derived from the record and attempt');
select throws_ok($$ insert into public.checkout_sessions (project_id, order_summary_id, acceptance_id, attempt)
  select '20000000-0000-4000-8000-0000000000a0', order_summary_id, acceptance_id, 9 from public.checkout_sessions limit 1 $$,
  '23505', null, 'T-ARC-05: a unique index allows at most one open initial session per project');

select pg_temp.as_service();
select is(public.outbound_request_for_execution((select v::uuid from ids where k = 'req_cs1')) ->> 'error', 'customer_missing',
  'the Checkout create waits for the Customer');
select pg_temp.claim((select v::uuid from ids where k = 'req_customer')) ->> 'purpose';
select is(public.record_outbound_result((select v::uuid from ids where k = 'req_customer'),
  pg_temp.token((select v::uuid from ids where k = 'req_customer')), 'succeeded', 'cus_TestA000001',
  false, 200, null, '{}') ->> 'status', 'succeeded', 'the Customer create result is recorded');
select is(pg_temp.claim((select v::uuid from ids where k = 'req_cs1')) ->> 'customer', 'cus_TestA000001',
  'the Checkout create resolves the Customer from the database, not from the client');
select is(public.outbound_request_for_execution((select v::uuid from ids where k = 'req_cs1')) ->> 'error', 'already_claimed',
  'exactly one executor can claim a request; a concurrent worker never sends the same create twice');
select is(public.run_billing_job('outbound_requests') #>> '{result,marked_ambiguous}', '0',
  'a request claimed moments ago is not marked ambiguous (only claims older than 10 minutes are)');
select is(public.record_outbound_result((select v::uuid from ids where k = 'req_cs1'),
  pg_temp.token((select v::uuid from ids where k = 'req_cs1')), 'succeeded', 'cs_test_A000001',
  true, 200, null, '{}') ->> 'error', 'livemode_mismatch', 'a live-mode Stripe result outside production aborts');
reset role;
select is((select status::text from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_cs1')),
  'ambiguous', 'the aborted create is ambiguous and blocks any new attempt until reconciled');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.reconcile_outbound_request((select v::uuid from ids where k = 'req_cs1'), false, null, 'checked') ->> 'error',
  'forbidden', 'reconciliation needs fresh reauthentication');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.reconcile_outbound_request((select v::uuid from ids where k = 'req_cs1'), true, 'cs_test_A000001', 'checked') ->> 'error',
  'livemode_mismatch', 'a live-mode object can never be adopted by reconciliation');
select is(public.reconcile_outbound_request((select v::uuid from ids where k = 'req_cs1'), false, null,
  'No session in the test-mode Dashboard request log') ->> 'ok', 'true', 'the Owner reconciles the request as absent');
reset role;
select is((select status::text from public.checkout_sessions where id = (select v::uuid from ids where k = 'cs1')), 'failed',
  'the unreconciled session record is closed as failed');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'cs2', public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'checkout_session_id';
reset role;
insert into ids select 'req_cs2', id::text from public.outbound_stripe_requests
  where domain_record_id = (select v::uuid from ids where k = 'cs2');
select is((select idempotency_key from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_cs2')),
  'wpb-checkout-' || (select v from ids where k = 'os2') || '-c2-a1', 'a new attempt derives a new key from the attempt number');
select pg_temp.as_service();
select pg_temp.claim((select v::uuid from ids where k = 'req_cs2')) ->> 'purpose';
select is(public.record_outbound_result((select v::uuid from ids where k = 'req_cs2'),
  pg_temp.token((select v::uuid from ids where k = 'req_cs2')), 'succeeded', 'cs_test_A000002', false, 200,
  null, jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_A000002', 'expires_at', extract(epoch from now())::bigint + 86400))
  ->> 'status', 'succeeded', 'the Checkout Session create result is recorded');
reset role;
select is((select status::text || ':' || checkout_url from public.checkout_sessions where id = (select v::uuid from ids where k = 'cs2')),
  'open:https://checkout.stripe.com/c/pay/cs_test_A000002', 'the session is open with its Stripe-hosted URL');
select is(private.project_deposit_state('20000000-0000-4000-8000-0000000000a0')::text, 'pending',
  'T-PAY-04: returning from Checkout without a processed webhook leaves the deposit pending');
select ok(not (private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).deposit_verified,
  'T-PAY-04: the gate interface reports the deposit unverified (intake stays locked)');

-- ---------------------------------------------------------------------------
-- 5. Webhook ingestion and processing (04 §11, §17; T-PAY-03 to -08, T-ARC-01 to -03, -06)
-- ---------------------------------------------------------------------------
create temporary table ev (k text primary key, body jsonb) on commit drop;
grant all on ev to service_role;
insert into ev values ('session', jsonb_build_object('id', 'cs_test_A000002', 'object', 'checkout.session', 'mode', 'subscription',
  'currency', 'usd', 'amount_total', 39800, 'payment_status', 'paid', 'customer', 'cus_TestA000001',
  'subscription', 'sub_TestA000001', 'invoice', 'in_TestA000001',
  'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
  'customer_details', jsonb_build_object('email', 'client.a@example.test', 'name', 'Alex Client'),
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0',
    'order_summary_id', (select v from ids where k = 'os2'), 'acceptance_id', (select v from ids where k = 'acc'),
    'checkout_record_id', (select v from ids where k = 'cs2'))));
insert into ev values ('invoice', jsonb_build_object('id', 'in_TestA000001', 'object', 'invoice', 'billing_reason', 'subscription_create',
  'currency', 'usd', 'amount_paid', 39800, 'customer', 'cus_TestA000001', 'total_discount_amounts', '[]'::jsonb, 'discounts', '[]'::jsonb,
  'parent', jsonb_build_object('subscription_details', jsonb_build_object('subscription', 'sub_TestA000001',
    'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0', 'checkout_record_id', (select v from ids where k = 'cs2')))),
  'payments', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('payment', jsonb_build_object('payment_intent', 'pi_TestA000001')))),
  'lines', jsonb_build_object('data', jsonb_build_array(
     jsonb_build_object('quantity', 1, 'pricing', jsonb_build_object('price_details', jsonb_build_object('price', 'price_1Uf5HyK5j4r4WkVPOtk24lGw'))),
     jsonb_build_object('quantity', 1, 'pricing', jsonb_build_object('price_details', jsonb_build_object('price', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))),
  'payment_method_details', jsonb_build_object('card', jsonb_build_object('last4', '4242'))));

select is(pg_temp.deliver(pg_temp.evt('evt_live000000001', 'checkout.session.completed', (select body from ev where k = 'session'), 0, 'true')) ->> 'error',
  'livemode_mismatch', 'T-PAY-08: a livemode: true event is rejected outside production');
select is(pg_temp.deliver(pg_temp.evt('evt_live000000002', 'checkout.session.completed', (select body from ev where k = 'session'), 0, 'null')) ->> 'error',
  'livemode_mismatch', 'T-PAY-08: a missing or null livemode fails closed');
select is((select count(*)::integer from public.webhook_events where stripe_event_id like 'evt_live%'), 0,
  'T-PAY-08: rejected events are not stored and change no state');
select is((select count(*)::integer from public.audit_events where action = 'webhook.rejected'), 2, 'each rejection is audited');

select is(pg_temp.deliver(pg_temp.evt('evt_amount0000001', 'checkout.session.completed',
  (select body from ev where k = 'session') || '{"amount_total": 39801}', 1)) ->> 'status', 'quarantined',
  'T-PAY-07: an amount that differs from the snapshot is quarantined');
select is(private.project_deposit_state('20000000-0000-4000-8000-0000000000a0')::text, 'pending',
  'T-PAY-07: a quarantined event never verifies payment');
select is((select count(*)::integer from public.notification_outbox where notification_type = 'webhook.quarantined'
           and category = 'financial'), 1, 'quarantine alerts the Owner (financial outbox row)');
select is(pg_temp.deliver(pg_temp.evt('evt_meta00000001', 'checkout.session.completed',
  jsonb_set((select body from ev where k = 'session'), '{metadata,order_summary_id}', to_jsonb((select v from ids where k = 'os1'))), 2))
  ->> 'reason', 'metadata_mismatch', '04 §11 rule 6: an order summary that does not match is quarantined');
select is(pg_temp.deliver(pg_temp.evt('evt_disc00000001', 'checkout.session.completed',
  (select body from ev where k = 'session') || '{"total_details": {"amount_discount": 500, "amount_tax": 0}}', 3)) ->> 'reason',
  'discount_or_tax_present', 'T-BIL-20: a discounted initial Checkout is quarantined');

-- Out of order: invoice.paid first, then checkout.session.completed (T-PAY-06).
select is(pg_temp.deliver(pg_temp.evt('evt_invoice000001', 'invoice.paid', (select body from ev where k = 'invoice'), 10)) ->> 'status',
  'processed', 'T-PAY-06: invoice.paid arriving first is processed');
select is(private.project_deposit_state('20000000-0000-4000-8000-0000000000a0')::text, 'verified',
  'T-PAY-06: the deposit is verified from the signature-verified invoice event');
select is(pg_temp.deliver(pg_temp.evt('evt_session000001', 'checkout.session.completed', (select body from ev where k = 'session'), 5)) ->> 'status',
  'processed', 'T-PAY-06: the later checkout.session.completed is processed');
select results_eq($$ select entry_type::text, amount_cents, service_category::text from public.ledger_entries
                     where project_id = '20000000-0000-4000-8000-0000000000a0' order by id $$,
  $$ values ('deposit_charge', 29900::bigint, 'development'), ('maintenance_charge', 9900::bigint, 'maintenance') $$,
  'T-PAY-06 / T-BIL-10: one deposit and one maintenance entry, integer cents, each with a service category');

-- Replay (T-PAY-05).
select is(pg_temp.deliver(pg_temp.evt('evt_session000001', 'checkout.session.completed', (select body from ev where k = 'session'), 5)) ->> 'duplicate',
  'true', 'T-PAY-05: a replayed event id is a duplicate');
select pg_temp.as_service();
select is((select count(*)::integer from generate_series(1, 5) i,
  lateral (select public.ingest_stripe_event(pg_temp.evt('evt_invoice000001', 'invoice.paid', (select body from ev where k = 'invoice'), 10),
    repeat('a', 64)) r) x where (x.r ->> 'duplicate')::boolean), 5, 'T-PAY-05: five more replays are all duplicates');
select is(public.process_stripe_event((select id from public.webhook_events where stripe_event_id = 'evt_invoice000001')) ->> 'already',
  'true', 'T-PAY-05: reprocessing a processed event has no effect');
reset role;
select is((select count(*)::integer from public.ledger_entries where project_id = '20000000-0000-4000-8000-0000000000a0'), 2,
  'T-PAY-05: each ledger entry is posted exactly once');
select is((select count(*)::integer from public.webhook_events where stripe_event_id = 'evt_invoice000001'), 1,
  'stripe_event_id is unique');
select ok((select not (payload::text like '%4242%') and not (payload::text like '%client.a@example.test%')
           from public.webhook_events where stripe_event_id = 'evt_invoice000001')
  and (select not (payload::text like '%customer_details%') from public.webhook_events where stripe_event_id = 'evt_session000001'),
  'card and customer contact details are stripped before storage (CLAUDE.md §3)');
select throws_ok($$ update public.webhook_events set payload = '{}' where stripe_event_id = 'evt_invoice000001' $$,
  '42501', null, 'stored events are immutable');

-- Domain separation and the agreement becoming effective (T-AGR-07).
select is((select count(*)::integer from public.domain_events where event_type = 'payment.deposit_verified'), 1,
  'payment.deposit_verified is emitted once');
select ok((select e.occurred_at >= a.occurred_at and e.id > a.id from public.domain_events e, public.domain_events a
           where e.event_type = 'agreement.effective' and a.event_type = 'agreement.accepted'),
  'T-AGR-07: agreement.effective is a distinct event, after acceptance, on deposit verification');
select is((select state::text from private.project_agreement_state('20000000-0000-4000-8000-0000000000a0')), 'effective',
  'the agreement is effective');
select is((select row(s.implemented, s.contract_version, s.deposit_verified, s.agreement_effective, s.balance_verified_or_settled)::text
           from private.project_financial_status('20000000-0000-4000-8000-0000000000a0') s), '(t,3,t,t,f)',
  'the gate interface reports G1 and G2 satisfied and G4 not');
select is((select array_agg(k order by k) from jsonb_object_keys((private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).evidence) k),
  array['acceptance_id', 'blocking_anomalies', 'calendar_version', 'evaluated_at', 'ledger_digest', 'order_summary_id'],
  'OI-72: gate evidence carries no amounts and no restricted record identifiers');
select is((private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).evidence -> 'blocking_anomalies',
  '{"G2": [], "G4": []}'::jsonb, 'B1 / OI-72: the anomaly evidence names gates and anomaly kinds only; none block here');
select is((select count(*)::integer from public.notification_outbox where notification_type = 'payment.deposit_verified'
           and status = 'recorded' and recipient_user_ids = array['00000000-0000-4000-8000-0000000000a1'::uuid]), 1,
  'the deposit-verified notification is recorded for the client (R1: recorded, never sent)');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.begin_initial_checkout('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'deposit_already_verified',
  'no second initial Checkout after the deposit is verified');
reset role;

-- A stale failure can never move a verified payment backwards (T-ARC-03).
select is(pg_temp.deliver(pg_temp.evt('evt_asyncfail0001', 'checkout.session.async_payment_failed',
  (select body from ev where k = 'session') || '{"payment_status": "unpaid"}', -100)) ->> 'reason', 'async_payment_not_expected',
  'OI-74 card only: an async payment event is not expected and is quarantined for Owner review');
select is(pg_temp.deliver(pg_temp.evt('evt_stale000000001', 'checkout.session.completed',
  (select body from ev where k = 'session') || '{"payment_status": "unpaid"}', -100)) ->> 'status', 'processed',
  'T-ARC-03: a stale completion reporting unpaid is processed');
select ok((select payment_status = 'paid' from public.checkout_sessions where id = (select v::uuid from ids where k = 'cs2'))
  and private.project_deposit_state('20000000-0000-4000-8000-0000000000a0') = 'verified',
  'T-ARC-03: the stale event does not move the deposit backwards');

-- Processing failure after storage stays retryable and leaves nothing half-committed (T-ARC-02, T-ARC-06).
select is(pg_temp.deliver(pg_temp.evt('evt_sub000000001', 'customer.subscription.created', jsonb_build_object('id', 'sub_TestA000001',
  'object', 'subscription', 'status', 'active', 'customer', 'cus_TestA000001',
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0')), 20)) ->> 'status', 'processed',
  'the subscription mirror records the first subscription');
select is(pg_temp.deliver(pg_temp.evt('evt_sub000000002', 'customer.subscription.created', jsonb_build_object('id', 'sub_TestA000002',
  'object', 'subscription', 'status', 'active', 'customer', 'cus_TestA000001',
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0')), 21)) ->> 'status', 'failed',
  'T-ARC-06: a handler failure (a second active subscription) fails the attempt');
select ok(pg_temp.status_of('evt_sub000000002') = 'failed'
  and not exists (select 1 from public.subscriptions where stripe_subscription_id = 'sub_TestA000002')
  and not exists (select 1 from public.domain_events where dedupe_key = 'subscription.status_changed:evt_sub000000002'),
  'T-ARC-06: none of the failed attempt''s effects committed; the stored event is retryable');
select is(pg_temp.deliver(pg_temp.evt('evt_subdel0000001', 'customer.subscription.deleted', jsonb_build_object('id', 'sub_TestA000001',
  'object', 'subscription', 'status', 'canceled', 'customer', 'cus_TestA000001',
  'metadata', jsonb_build_object('project_id', '20000000-0000-4000-8000-0000000000a0')), 22)) ->> 'status', 'processed',
  'an unexpected subscription deletion is processed');
select ok(exists (select 1 from public.stripe_cancellation_exceptions where stripe_subscription_id = 'sub_TestA000001')
  and not exists (select 1 from public.service_terminations where project_id = '20000000-0000-4000-8000-0000000000a0'),
  'T-BIL-15: it creates an Owner exception review and starts no termination');
select pg_temp.as_service();
select is((public.run_billing_job('webhook_backfill') #>> '{result,events_retried}')::integer >= 1, true,
  'the webhook backfill job reprocesses the failed event');
reset role;
select is(pg_temp.status_of('evt_sub000000002'), 'processed', 'T-ARC-02: the retried event now processes');

-- The ledger is append-only (04 §12).
select throws_ok($$ update public.ledger_entries set amount_cents = 1 $$, '42501', null, 'ledger entries cannot be updated');
select throws_ok($$ delete from public.ledger_entries $$, '42501', null, 'ledger entries cannot be deleted');
select throws_ok($$ truncate public.ledger_entries cascade $$, '42501', null, 'the ledger cannot be truncated');

-- ---------------------------------------------------------------------------
-- 6. Refunds and disputes on the combined initial charge (04 §15.2, §15.2.1, §15.4; OI-82;
--    T-ARC-08, T-BIL-09, T-PAY-28 to T-PAY-34 on this charge; full coverage in 140)
-- ---------------------------------------------------------------------------
insert into ids select 'ob_dep', id::text from public.payment_obligations
  where charge_key = 'initial:' || (select v from ids where k = 'cs2') and kind = 'development_deposit';
insert into ids select 'ob_mnt', id::text from public.payment_obligations
  where charge_key = 'initial:' || (select v from ids where k = 'cs2') and kind = 'maintenance';
select ok((select count(*) = 2 and sum(original_cents) = 39800 from public.payment_obligations
           where charge_key = 'initial:' || (select v from ids where k = 'cs2')),
  'OI-82 rule 1: the initial charge maps to a development deposit and a maintenance obligation');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.record_refund_decision('20000000-0000-4000-8000-0000000000a0', 5000, 'Goodwill') ->> 'error', 'forbidden',
  'an Admin cannot record a refund decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.record_refund_decision('20000000-0000-4000-8000-0000000000a0', 5000, 'Goodwill') ->> 'error', 'forbidden',
  'the Owner needs fresh reauthentication for a refund decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_refund_decision('20000000-0000-4000-8000-0000000000a0', 5000, 'Goodwill',
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', 3000),
                    jsonb_build_object('obligation_id', (select v from ids where k = 'ob_mnt'), 'amount_cents', 1000))) ->> 'error',
  'allocation_must_equal_amount', 'an allocation must sum exactly to the refund amount');
select is(public.record_refund_decision('20000000-0000-4000-8000-0000000000a0', 12000, 'Goodwill',
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_mnt'), 'amount_cents', 12000))) ->> 'error',
  'invalid_allocation', 'an allocation line can never exceed its obligation');
insert into ids select 'decision', public.record_refund_decision('20000000-0000-4000-8000-0000000000a0', 5000,
  'Goodwill for a delayed launch',
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', 3000),
                    jsonb_build_object('obligation_id', (select v from ids where k = 'ob_mnt'), 'amount_cents', 2000)))
  ->> 'refund_decision_id';
reset role;
select is((select count(*)::integer from public.ledger_entries where entry_type = 'refund'), 0,
  'T-ARC-08: a refund decision posts no refund; only the webhook does');
select is(pg_temp.deliver(pg_temp.evt('evt_refund000001', 'refund.created', jsonb_build_object('id', 're_TestA000001', 'object', 'refund',
  'amount', 5000, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_TestA000001',
  'metadata', jsonb_build_object('refund_decision_id', (select v from ids where k = 'decision'))), 30)) ->> 'status', 'processed',
  'T-ARC-08: a refund webhook is processed');
select results_eq($$ select l.amount_cents, l.service_category::text, o.kind::text from public.ledger_entries l
                     join public.payment_obligations o on o.id = l.obligation_id
                     where l.stripe_object_id = 're_TestA000001' order by o.kind $$,
  $$ values (-3000::bigint, 'development', 'development_deposit'), (-2000::bigint, 'maintenance', 'maintenance') $$,
  'T-PAY-28: a partial refund with a matching Owner-recorded allocation posts one entry per line, per category');
select ok((select refund_decision_id is not null from public.refunds where stripe_refund_id = 're_TestA000001')
  and (select matched_refund_id = 're_TestA000001' from public.refund_decisions where id = (select v::uuid from ids where k = 'decision')),
  'T-ARC-08: the refund is linked to the Owner''s decision');
select ok(private.project_deposit_verified('20000000-0000-4000-8000-0000000000a0'),
  'G2: a partial refund leaves the deposit verified (06 §2 G2)');

select is(pg_temp.deliver(pg_temp.evt('evt_refund000002', 'refund.created', jsonb_build_object('id', 're_TestA000002', 'object', 'refund',
  'amount', 1000, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_TestA000001'), 31)) ->> 'status', 'processed',
  'a refund made outside the portal is processed');
select ok((select amount_cents = -1000 and holding_charge_key = 'initial:' || (select v from ids where k = 'cs2')
             and service_category is null and obligation_id is null
           from public.ledger_entries where stripe_object_id = 're_TestA000002')
  and exists (select 1 from public.notification_outbox where notification_type = 'reversal.reconciliation_required'),
  'T-PAY-29: a refund made outside the portal goes to the holding account with no category assumed, and alerts the Owner');
select ok(private.project_deposit_state('20000000-0000-4000-8000-0000000000a0') = 'verified'
  and not private.project_deposit_verified('20000000-0000-4000-8000-0000000000a0')
  and not (private.project_financial_status('20000000-0000-4000-8000-0000000000a0')).deposit_verified,
  'T-PAY-30: an unresolved reversal on the initial charge fails G2 until the Owner reconciles it');
select is(pg_temp.deliver(pg_temp.evt('evt_refund000002', 'refund.created', jsonb_build_object('id', 're_TestA000002', 'object', 'refund',
  'amount', 1000, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_TestA000001'), 31)) ->> 'duplicate', 'true',
  'a replayed refund event is a duplicate');
select is(pg_temp.deliver(pg_temp.evt('evt_refund000003', 'charge.refunded', jsonb_build_object('id', 'ch_TestA000001', 'object', 'charge',
  'refunds', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('id', 're_TestA000002', 'object', 'refund',
    'amount', 1000, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_TestA000001')))), 32)) ->> 'status', 'processed',
  'a second event about the same refund is processed');
select is((select count(*)::integer from public.ledger_entries where stripe_object_id = 're_TestA000002'), 1,
  'T-PAY-32: a refund reported by two events is counted once');

select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.reconcile_holding_reversal('20000000-0000-4000-8000-0000000000a0', 'initial:' || (select v from ids where k = 'cs2'),
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', -1000)), 'x') ->> 'error',
  'forbidden', 'T-PAY-34: Admin cannot reconcile the holding account');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.reconcile_holding_reversal('20000000-0000-4000-8000-0000000000a0', 'initial:' || (select v from ids where k = 'cs2'),
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', -1000)), 'x') ->> 'error',
  'forbidden', 'T-PAY-34: reconciliation needs fresh reauthentication');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.reconcile_holding_reversal('20000000-0000-4000-8000-0000000000a0', 'initial:' || (select v from ids where k = 'cs2'),
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', -900)), 'x') ->> 'error',
  'allocation_must_balance', 'T-PAY-34: entries must balance the holding account exactly');
select is(public.reconcile_holding_reversal('20000000-0000-4000-8000-0000000000a0', 'initial:' || (select v from ids where k = 'cs2'),
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', -1000)), ' ') ->> 'error',
  'reason_required', 'T-PAY-34: a reason is required');
select is(public.reconcile_holding_reversal('20000000-0000-4000-8000-0000000000a0', 'initial:' || (select v from ids where k = 'cs2'),
  jsonb_build_array(jsonb_build_object('obligation_id', (select v from ids where k = 'ob_dep'), 'amount_cents', -1000)),
  'Owner confirmed the refund was for development work') ->> 'ok', 'true', 'the Owner reconciles the holding account');
reset role;
select ok(private.project_deposit_verified('20000000-0000-4000-8000-0000000000a0')
  and private.holding_balance_cents('initial:' || (select v from ids where k = 'cs2')) = 0
  and (select sum(amount_cents) = 0 and count(*) = 2 from public.ledger_entries where entry_type = 'reclassification')
  and exists (select 1 from public.audit_events where action = 'reversal.reconciled' and category = 'financial'),
  'T-PAY-34: append-only reclassification entries balance exactly, are audited, and restore G2');

-- A refund and a dispute on the same funds are never double-counted (rule 4, T-PAY-31/32).
select is(pg_temp.deliver(pg_temp.evt('evt_dispute00000', 'charge.dispute.created', jsonb_build_object('id', 'dp_TestA000000', 'object', 'dispute',
  'amount', 39800, 'currency', 'usd', 'status', 'needs_response', 'payment_intent', 'pi_TestA000001'), 39)) ->> 'reason',
  'reversal_exceeds_charge', 'T-PAY-31: a dispute of the full charge after 6000 cents were refunded exceeds it and is quarantined');
select is(pg_temp.deliver(pg_temp.evt('evt_dispute00001', 'charge.dispute.created', jsonb_build_object('id', 'dp_TestA000001', 'object', 'dispute',
  'amount', 2000, 'currency', 'usd', 'status', 'needs_response', 'reason', 'fraudulent', 'payment_intent', 'pi_TestA000001',
  'created', extract(epoch from now())::bigint, 'evidence_details', jsonb_build_object('due_by', extract(epoch from now())::bigint + 7 * 86400),
  'evidence', jsonb_build_object('customer_email_address', 'client.a@example.test')), 40)) ->> 'status', 'processed',
  'T-BIL-09: a partial dispute webhook is processed');
select ok((select evidence_due_by is not null and status = 'needs_response' from public.disputes where stripe_dispute_id = 'dp_TestA000001')
  and exists (select 1 from public.ledger_entries where entry_type = 'dispute_opened' and amount_cents = -2000
                and holding_charge_key is not null)
  and exists (select 1 from public.notification_outbox where notification_type = 'dispute.opened' and recipient_roles = '{owner}')
  and not exists (select 1 from public.billing_holds where project_id = '20000000-0000-4000-8000-0000000000a0'),
  'T-BIL-09 / T-PAY-29: the deadline is recorded, a partial dispute goes to the holding account, the Owner is notified, nothing is held or taken down');
select is(private.project_deposit_state('20000000-0000-4000-8000-0000000000a0')::text, 'disputed', 'G2 fails while disputed');
select is(pg_temp.deliver(pg_temp.evt('evt_dispute00002', 'charge.dispute.closed', jsonb_build_object('id', 'dp_TestA000001', 'object', 'dispute',
  'amount', 2000, 'currency', 'usd', 'status', 'won', 'payment_intent', 'pi_TestA000001'), 41)) ->> 'status', 'processed',
  'a won dispute is processed');
select ok(private.project_deposit_verified('20000000-0000-4000-8000-0000000000a0')
  and exists (select 1 from public.ledger_entries where entry_type = 'dispute_won' and amount_cents = 2000 and holding_charge_key is not null),
  'T-PAY-33: a won dispute posts a reinstatement entry and restores the deposit');
select is(pg_temp.deliver(pg_temp.evt('evt_dispute00003', 'charge.dispute.updated', jsonb_build_object('id', 'dp_TestA000001', 'object', 'dispute',
  'amount', 2000, 'currency', 'usd', 'status', 'under_review', 'payment_intent', 'pi_TestA000001'), 35)) ->> 'status', 'processed',
  'a stale dispute update is processed');
select is((select status from public.disputes where stripe_dispute_id = 'dp_TestA000001'), 'won',
  'T-ARC-03: a stale dispute update cannot reopen a closed dispute');

-- ---------------------------------------------------------------------------
-- 7. Reconciliation (04 §13; T-ARC-07)
-- ---------------------------------------------------------------------------
select pg_temp.as_service();
insert into ids select 'run', public.start_reconciliation_run('mocked_gateway')::text;
select is(public.record_project_reconciliation((select v::uuid from ids where k = 'run'), '20000000-0000-4000-8000-0000000000a0',
  '{"charges_cents": 39800, "refunds_cents": 6000, "open_disputes": 0}'), 0, 'matching Stripe totals produce no mismatch');
select is(public.record_project_reconciliation((select v::uuid from ids where k = 'run'), '20000000-0000-4000-8000-0000000000a0',
  '{"charges_cents": 49800, "refunds_cents": 6000, "open_disputes": 0}'), 1, 'T-ARC-07: a seeded ledger and Stripe mismatch is detected');
select is(public.complete_reconciliation_run((select v::uuid from ids where k = 'run')) ->> 'mismatches', '1', 'the run records the mismatch');
reset role;
select ok(exists (select 1 from public.notification_outbox where notification_type = 'reconciliation.mismatch' and category = 'financial')
  and private.project_deposit_state('20000000-0000-4000-8000-0000000000a0') = 'verified'
  and (select count(*) from public.ledger_entries where project_id = '20000000-0000-4000-8000-0000000000a0') = 10,
  'T-ARC-07: the mismatch alerts the Owner and changes no payment state or ledger entry');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.resolve_reconciliation_mismatch((select id from public.reconciliation_mismatches limit 1), 'x') ->> 'error', 'forbidden',
  'reconciliation is Owner-only (OI-72)');
reset role;

-- ---------------------------------------------------------------------------
-- 8. Isolation and OI-72 visibility (T-TEN-01, T-TEN-02 for WP-B tables)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::integer from public.order_summaries) + (select count(*)::integer from public.agreement_acceptances)
  + (select count(*)::integer from public.checkout_sessions) + (select count(*)::integer from public.ledger_entries)
  + (select count(*)::integer from public.webhook_events) + (select count(*)::integer from public.disputes)
  + (select count(*)::integer from public.refunds) + (select count(*)::integer from public.subscriptions)
  + (select count(*)::integer from public.outbound_stripe_requests) + (select count(*)::integer from public.stripe_customers)
  + (select count(*)::integer from public.reconciliation_mismatches) + (select count(*)::integer from public.agreement_versions), 0,
  'T-TEN-01: client B reads no WP-B row of Project A');
select is(public.project_billing_status('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'not_found',
  'T-TEN-01: client B cannot read Project A''s billing status');
select throws_ok($$ update public.checkout_sessions set status = 'expired' $$, '42501', null,
  'T-TEN-02: client B cannot write a checkout session');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((select count(*) from public.order_summaries) = 2 and (select count(*) from public.checkout_sessions) = 2
  and (select count(*) from public.ledger_entries) = 0 and (select count(*) from public.webhook_events) = 0
  and (select count(*) from public.disputes) = 0,
  'client A reads its own summaries and checkout sessions, never the ledger, webhooks or disputes');
select is(public.project_billing_status('20000000-0000-4000-8000-0000000000a0') ->> 'deposit_state', 'verified',
  'client A reads its own payment status');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((select count(*) from public.order_summaries) = 2 and (select count(*) from public.agreement_acceptances) = 1
  and (select count(*) from public.ledger_entries) = 0 and (select count(*) from public.webhook_events) = 0
  and (select count(*) from public.disputes) = 0 and (select count(*) from public.checkout_sessions) = 0
  and (select count(*) from public.refunds) = 0 and (select count(*) from public.reconciliation_mismatches) = 0
  and (select count(*) from public.audit_events where category = 'financial') = 0
  and (select count(*) from public.domain_events where category = 'financial') = 0,
  'OI-72: Admin reads agreements and summaries but no payment, ledger, dispute, reconciliation or financial audit record');
select is(public.project_billing_status('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'not_found',
  'OI-72: Admin cannot read amounts through the client billing status');
-- OI-83: Admin reads the agreed order-summary pricing (total, deposit, balance) of the
-- accepted summary; paid amounts and invoices stay restricted (above).
select is((select count(*)::integer from public.order_summaries os
            where os.project_id = '20000000-0000-4000-8000-0000000000a0'
              and os.package_total_cents = os.deposit_cents + os.balance_cents and os.package_total_cents > 0
              and exists (select 1 from public.agreement_acceptances a where a.order_summary_id = os.id)), 1,
  'OI-83: Admin reads the agreed total, deposit and balance of the accepted order summary');
select is((select count(*)::integer from public.final_balance_invoices) + (select count(*)::integer from public.payment_authorizations)
  + (select count(*)::integer from public.payment_obligations) + (select count(*)::integer from public.refund_decisions), 0,
  'OI-83: Admin reads no invoice, payment authorization, obligation or refund decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select ok((select count(*) from public.ledger_entries) = 10 and (select count(*) from public.webhook_events) > 0,
  'the Owner reads the financial records');
reset role;

select * from finish();
rollback;
