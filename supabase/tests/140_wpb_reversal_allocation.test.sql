-- WP-B: refund and dispute reversal allocation (04 §15.2.1; OI-82), on the combined initial
-- charge and on single-obligation charges (maintenance renewal, final balance).
-- Covers: T-PAY-27 to T-PAY-36 (T-PAY-28, -29, -30, -32, -34 also on the initial charge in 110).
-- No deposit-first, maintenance-first, or proportional rule exists (code search in unit tests).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(40);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false, p_otp_fresh boolean default false)
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
    'session_id', v_sid, 'amr',
      case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
           when p_otp_fresh then jsonb_build_array(jsonb_build_object('method', 'otp', 'timestamp', extract(epoch from now())::bigint))
           else jsonb_build_array(jsonb_build_object('method', 'otp', 'timestamp', extract(epoch from now())::bigint - 3600)) end)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
create function pg_temp.svc(p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_service();
  execute p_sql into v;
  reset role;
  return v;
end;
$$;
create function pg_temp.evt(p_id text, p_type text, p_obj jsonb, p_offset integer default 0)
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type, 'api_version', '2026-09-30.endive',
    'livemode', false, 'created', extract(epoch from now())::bigint + p_offset, 'data', jsonb_build_object('object', p_obj));
$$;
grant execute on function pg_temp.evt(text, text, jsonb, integer) to service_role;
create function pg_temp.deliver(p_event jsonb) returns jsonb language plpgsql as $$
declare
  v_ingest jsonb;
  v_result jsonb;
begin
  perform pg_temp.as_service();
  v_ingest := public.ingest_stripe_event(p_event, repeat('c', 64));
  if not (v_ingest ->> 'ok')::boolean then
    reset role;
    return v_ingest;
  end if;
  v_result := public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  reset role;
  return v_result || jsonb_build_object('duplicate', v_ingest -> 'duplicate');
end;
$$;
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
create function pg_temp.approve(p_project uuid, p_n integer) returns bigint language sql as $$
  select private.emit_domain_event('release.approved', p_project, 'preview_release',
    ('30000000-0000-4000-8000-' || lpad(p_n::text, 12, '0')), jsonb_build_object('approval_id',
    ('40000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))), 'release.approved:t130:' || p_project || ':' || p_n);
$$;
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;

-- A project paid through the real workflow: order summary (Owner), acceptance and Checkout
-- (client A), recorded mock results, a verified checkout.session.completed, and, when
-- p_card is set, the server's re-read of the card (attached or not).
create function pg_temp.paid_project(p_tag text, p_card text) returns uuid language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
  v_os uuid;
  v_acc uuid;
  v_cs uuid;
  v_req record;
  v_tok uuid;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('Biz ' || p_tag || ' LLC', 'Biz ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'Project ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '00000000-0000-4000-8000-0000000000a1');
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
  v_os := (public.issue_order_summary(v_project, 'essential', '[]'::jsonb) ->> 'order_summary_id')::uuid;
  reset role;
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'Biz ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
  v_cs := (public.begin_initial_checkout(v_project) ->> 'checkout_session_id')::uuid;
  reset role;
  perform pg_temp.as_service();
  for v_req in select id, purpose from public.outbound_stripe_requests where project_id = v_project
               order by (purpose = 'customer_create') desc loop
    -- AUTH-009 (setup): claim, confirm with the one-time token, then record with it.
    v_tok := (public.outbound_request_for_execution(v_req.id) ->> 'claim_token')::uuid;
    perform public.confirm_outbound_dispatch(v_req.id, v_tok);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cus_T' || p_tag || '00000', false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cs_test_' || p_tag || '00000', false, 200, null,
        jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_' || p_tag || '00000'));
    end if;
  end loop;
  reset role;
  perform pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'checkout0', 'checkout.session.completed', jsonb_build_object(
    'id', 'cs_test_' || p_tag || '00000', 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
    'amount_total', 25900, 'payment_status', 'paid', 'customer', 'cus_T' || p_tag || '00000',
    'subscription', 'sub_' || p_tag || '00000', 'invoice', 'in_' || p_tag || '00000',
    'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
    'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
      'checkout_record_id', v_cs))));
  if p_card is not null then
    perform pg_temp.svc(format('select public.record_payment_method_lookup(%L, %L, %L, %L, false, %L)', 'initial', v_cs,
      case when p_card = 'detached' then 'pm_' || p_tag || 'card01' else p_card end, 'cus_T' || p_tag || '00000',
      p_card <> 'detached'));
  end if;
  return v_project;
end;
$$;

-- The charge ledger helpers.
create function pg_temp.ob(p_project uuid, p_kind text) returns uuid language sql as $$
  select id from public.payment_obligations where project_id = p_project and kind = p_kind::public.obligation_kind
  order by created_at desc limit 1;
$$;
create function pg_temp.refund(p_id text, p_re text, p_amount bigint, p_pi text, p_status text default 'succeeded',
  p_decision uuid default null, p_offset integer default 0) returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'refund.created', jsonb_build_object('id', p_re, 'object', 'refund', 'amount', p_amount,
    'currency', 'usd', 'status', p_status, 'payment_intent', p_pi,
    'metadata', case when p_decision is null then '{}'::jsonb else jsonb_build_object('refund_decision_id', p_decision) end), p_offset));
$$;
create function pg_temp.dispute(p_id text, p_dp text, p_amount bigint, p_pi text, p_status text, p_offset integer default 0)
returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'charge.dispute.' || case when p_status in ('won', 'lost') then 'closed' else 'created' end,
    jsonb_build_object('id', p_dp, 'object', 'dispute', 'amount', p_amount, 'currency', 'usd', 'status', p_status,
      'payment_intent', p_pi), p_offset));
$$;
grant execute on function pg_temp.ob(uuid, text) to authenticated;
-- The initial invoice (links the payment intent used by refunds and disputes).
create function pg_temp.initial_invoice(p_project uuid, p_tag text) returns jsonb language plpgsql as $$
declare
  v_cs public.checkout_sessions%rowtype;
begin
  select * into v_cs from public.checkout_sessions where project_id = p_project;
  return pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'initinv0', 'invoice.paid', jsonb_build_object('id', 'in_' || p_tag || '00000',
    'object', 'invoice', 'billing_reason', 'subscription_create', 'currency', 'usd', 'amount_paid', 25900,
    'customer', 'cus_T' || p_tag || '00000', 'payment_intent', 'pi_' || p_tag || 'init01',
    'parent', jsonb_build_object('subscription_details', jsonb_build_object('subscription', 'sub_' || p_tag || '00000',
      'metadata', jsonb_build_object('project_id', p_project, 'checkout_record_id', v_cs.id))),
    'lines', jsonb_build_object('data', jsonb_build_array(
      jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HxK5j4r4WkVPkRUJ4gnZ')),
      jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe')))))));
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Full reversal of the initial charge (rule 2b; T-PAY-27)
-- ---------------------------------------------------------------------------
insert into ids select 'p1', pg_temp.paid_project('FULL', null)::text;
select is(pg_temp.initial_invoice((select v::uuid from ids where k = 'p1'), 'FULL') ->> 'status', 'processed', 'the initial invoice is linked');
select is(pg_temp.refund('evt_FULLrefund01', 're_FULLrefund01', 25900, 'pi_FULLinit01') ->> 'status', 'processed',
  'a verified full refund of the initial charge is processed');
select results_eq(format($$ select o.kind::text, l.amount_cents, l.service_category::text from public.ledger_entries l
    join public.payment_obligations o on o.id = l.obligation_id where l.stripe_object_id = 're_FULLrefund01' order by o.kind $$),
  $$ values ('development_deposit', -16000::bigint, 'development'), ('maintenance', -9900::bigint, 'maintenance') $$,
  'T-PAY-27: each line is reversed in full, in its own category');
select is(private.project_deposit_state((select v::uuid from ids where k = 'p1'))::text, 'refunded',
  'G2 fails once the deposit obligation is fully reversed');
select is(pg_temp.refund('evt_FULLrefund02', 're_FULLrefund02', 1, 'pi_FULLinit01') ->> 'reason', 'reversal_exceeds_charge',
  'T-PAY-31: any further reversal of a fully reversed charge is quarantined');
select is((select count(*)::integer from public.refunds where stripe_refund_id = 're_FULLrefund02'), 0,
  'a quarantined event leaves no partial record');

-- ---------------------------------------------------------------------------
-- 2. Recorded allocation vs mismatch (rule 2c/2d; T-PAY-28, T-PAY-29)
-- ---------------------------------------------------------------------------
insert into ids select 'p2', pg_temp.paid_project('PART', null)::text;
select pg_temp.initial_invoice((select v::uuid from ids where k = 'p2'), 'PART');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'd2', public.record_refund_decision((select v::uuid from ids where k = 'p2'), 4000, 'Partial goodwill',
  jsonb_build_array(jsonb_build_object('obligation_id', pg_temp.ob((select v::uuid from ids where k = 'p2'), 'development_deposit'), 'amount_cents', 4000)))
  ->> 'refund_decision_id';
reset role;
select is(pg_temp.refund('evt_PARTrefund01', 're_PARTrefund01', 3000, 'pi_PARTinit01', 'succeeded', (select v::uuid from ids where k = 'd2')) ->> 'status',
  'processed', 'a refund whose amount does not match its recorded allocation is processed');
select ok((select holding_charge_key is not null and amount_cents = -3000 from public.ledger_entries where stripe_object_id = 're_PARTrefund01')
  and (select matched_refund_id is null from public.refund_decisions where id = (select v::uuid from ids where k = 'd2')),
  'T-PAY-28: a mismatched allocation is not applied; the amount goes to the holding account');
select is(pg_temp.refund('evt_PARTrefund02', 're_PARTrefund02', 4000, 'pi_PARTinit01', 'succeeded', (select v::uuid from ids where k = 'd2')) ->> 'status',
  'processed', 'a refund matching its recorded allocation is processed');
select ok((select o.kind = 'development_deposit' and l.amount_cents = -4000 from public.ledger_entries l
           join public.payment_obligations o on o.id = l.obligation_id where l.stripe_object_id = 're_PARTrefund02'),
  'T-PAY-28: the matching allocation posts one entry per recorded line');
select is(pg_temp.refund('evt_PARTrefund03', 're_PARTrefund03', 500, 'pi_PARTinit01', 'succeeded', (select v::uuid from ids where k = 'd2')) ->> 'status',
  'processed', 'a second refund naming an already-used decision is processed');
select ok((select holding_charge_key is not null from public.ledger_entries where stripe_object_id = 're_PARTrefund03'),
  'a recorded allocation is used once; a second refund referencing it goes to the holding account');
select is(private.holding_balance_cents('initial:' || (select id from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p2'))),
  -3500::bigint, 'the holding account holds exactly the unresolved amounts (integer cents)');
select is(pg_temp.dispute('evt_PARTdisp0001', 'dp_PARTdisp0001', 1200, 'pi_PARTinit01', 'needs_response') ->> 'status', 'processed',
  'a partial dispute of the initial charge is processed');
select ok((select holding_charge_key is not null and amount_cents = -1200 from public.ledger_entries
           where stripe_object_id = 'dp_PARTdisp0001' and entry_type = 'dispute_opened'),
  'T-PAY-29: a partial dispute goes to the holding account; no category is assumed');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.reconcile_holding_reversal((select v::uuid from ids where k = 'p2'),
  'initial:' || (select id from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p2')),
  jsonb_build_array(jsonb_build_object('obligation_id', pg_temp.ob((select v::uuid from ids where k = 'p2'), 'maintenance'), 'amount_cents', -9901)),
  'x') ->> 'error', 'allocation_exceeds_limit', 'T-PAY-31 / T-PAY-34: reconciliation can never over-reverse an obligation');
select is(public.reconcile_holding_reversal((select v::uuid from ids where k = 'p2'),
  'initial:' || (select id from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p2')),
  jsonb_build_array(jsonb_build_object('obligation_id', pg_temp.ob((select v::uuid from ids where k = 'p2'), 'maintenance'), 'amount_cents', -3000),
                    jsonb_build_object('obligation_id', pg_temp.ob((select v::uuid from ids where k = 'p2'), 'development_deposit'), 'amount_cents', -1700)),
  'Allocated per the client correspondence') ->> 'ok', 'true', 'the Owner reconciles both lines');
reset role;
select ok(private.holding_balance_cents('initial:' || (select id from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p2'))) = 0
  and private.obligation_net_cents(pg_temp.ob((select v::uuid from ids where k = 'p2'), 'development_deposit')) = 16000 - 4000 - 1700
  and private.obligation_net_cents(pg_temp.ob((select v::uuid from ids where k = 'p2'), 'maintenance')) = 9900 - 3000,
  'T-PAY-34: the reclassification balances exactly and every amount is in integer cents');
select is(private.project_deposit_state((select v::uuid from ids where k = 'p2'))::text, 'disputed',
  'the deposit stays disputed while the reclassified dispute is open');

-- ---------------------------------------------------------------------------
-- 3. Disputes: opened, won, lost (rule 5; T-PAY-33, T-PAY-36)
-- ---------------------------------------------------------------------------
insert into ids select 'p3', pg_temp.paid_project('DISP', null)::text;
select pg_temp.initial_invoice((select v::uuid from ids where k = 'p3'), 'DISP');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.place_billing_hold((select v::uuid from ids where k = 'p3'), 'dispute_risk_hold', 'Chargeback risk') ->> 'ok', 'true',
  'T-PAY-36: the Owner may place a dispute_risk_hold (OI-37)');
reset role;
select is(pg_temp.dispute('evt_DISPopen0001', 'dp_DISPopen0001', 25900, 'pi_DISPinit01', 'needs_response') ->> 'status', 'processed',
  'a full dispute of the initial charge is processed');
select is((select count(*)::integer from public.ledger_entries where stripe_object_id = 'dp_DISPopen0001' and entry_type = 'dispute_opened'
  and obligation_id is not null), 2, 'rule 2b: a full dispute reverses each line');
select is(pg_temp.dispute('evt_DISPopen0001', 'dp_DISPopen0001', 25900, 'pi_DISPinit01', 'needs_response') ->> 'duplicate', 'true',
  'T-PAY-32: a replayed dispute event is a duplicate');
select is(pg_temp.dispute('evt_DISPlost0001', 'dp_DISPopen0001', 25900, 'pi_DISPinit01', 'lost', 10) ->> 'status', 'processed',
  'the lost outcome is processed');
select ok((select count(*) = 2 and bool_and(amount_cents = 0) from public.ledger_entries where stripe_object_id = 'dp_DISPopen0001'
           and entry_type = 'dispute_lost')
  and (select count(*) = 4 from public.ledger_entries where stripe_object_id = 'dp_DISPopen0001')
  and private.project_deposit_state((select v::uuid from ids where k = 'p3')) = 'disputed',
  'T-PAY-33: a lost dispute posts final zero-amount entries; the reversal stays final; G2 fails');
select is(pg_temp.dispute('evt_DISPwon00001', 'dp_DISPopen0001', 25900, 'pi_DISPinit01', 'won', 5) ->> 'status', 'processed',
  'a stale won event after lost is processed');
select is((select count(*)::integer from public.ledger_entries where stripe_object_id = 'dp_DISPopen0001' and entry_type = 'dispute_won'), 0,
  'T-ARC-03: a closed dispute never changes outcome');
select is((select array_agg(hold_type::text) from public.billing_holds where project_id = (select v::uuid from ids where k = 'p3') and cleared_at is null),
  array['dispute_risk_hold'], 'T-PAY-36: allocation leaves the OI-37 hold unchanged');
select throws_ok(format($$ update public.ledger_entries set amount_cents = 0 where stripe_object_id = %L $$, 'dp_DISPopen0001'),
  '42501', null, 'T-PAY-33: no existing ledger entry is ever updated');

-- ---------------------------------------------------------------------------
-- 4. Single-obligation charges (rule 2a; T-PAY-35, T-PAY-31, T-PAY-32, T-PAY-30 for G4)
-- ---------------------------------------------------------------------------
insert into ids select 'p4', pg_temp.paid_project('SNGL', null)::text;
select pg_temp.deliver(pg_temp.evt('evt_SNGLsub00001', 'customer.subscription.created', jsonb_build_object('id', 'sub_SNGL00000',
  'object', 'subscription', 'status', 'active', 'customer', 'cus_TSNGL00000', 'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p4')))));
select is(pg_temp.refund('evt_SNGLearly001', 're_SNGLearly001', 500, 'pi_SNGLrenew01', 'succeeded', null, -50) ->> 'status', 'deferred',
  'T-PAY-32: a refund that arrives before its charge is deferred, not guessed');
select is(pg_temp.deliver(pg_temp.evt('evt_SNGLrenew001', 'invoice.paid', jsonb_build_object('id', 'in_SNGLrenew01', 'object', 'invoice',
  'billing_reason', 'subscription_cycle', 'currency', 'usd', 'amount_paid', 9900, 'customer', 'cus_TSNGL00000',
  'subscription', 'sub_SNGL00000', 'payment_intent', 'pi_SNGLrenew01',
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))))) ->> 'status',
  'processed', 'a maintenance renewal is paid');
select pg_temp.svc($$ select public.run_billing_job('webhook_backfill') $$);
select ok((select o.kind = 'maintenance' and l.amount_cents = -500 and o.charge_key = 'renewal:in_SNGLrenew01'
           from public.ledger_entries l join public.payment_obligations o on o.id = l.obligation_id where l.stripe_object_id = 're_SNGLearly001'),
  'T-PAY-35 / T-PAY-32: once the charge exists, the retried refund is allocated to that maintenance obligation only');
select is(pg_temp.refund('evt_SNGLrefund02', 're_SNGLrefund02', 9401, 'pi_SNGLrenew01') ->> 'reason', 'reversal_exceeds_charge',
  'T-PAY-31: cumulative reversals beyond the obligation are quarantined');
select is(pg_temp.dispute('evt_SNGLdisp001', 'dp_SNGLdisp001', 9900, 'pi_SNGLrenew01', 'needs_response') ->> 'reason', 'reversal_exceeds_charge',
  'T-PAY-32: a dispute on funds already refunded is never double-counted');
select is(private.project_deposit_state((select v::uuid from ids where k = 'p4'))::text, 'verified',
  'T-PAY-35: a maintenance refund never touches the deposit');
-- G4 reads the final-balance holding account (rule 3). Rule 2a never routes a final-balance
-- reversal there, so the gate wiring is shown with a fixture entry in this rolled-back test.
insert into public.final_balance_invoices (project_id, order_summary_id, acceptance_id, approval_id, release_id,
  source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode, status)
select p.id, os.id, a.id, gen_random_uuid(), gen_random_uuid(), (select max(id) from public.domain_events), 64000,
  os.balance_price_id, 'cus_TSNGL00000', 'hosted_only', 'creating'
from public.projects p join public.order_summaries os on os.project_id = p.id join public.agreement_acceptances a on a.order_summary_id = os.id
where p.id = (select v::uuid from ids where k = 'p4');
select is(pg_temp.deliver(pg_temp.evt('evt_SNGLfinal001', 'invoice.paid', jsonb_build_object('id', 'in_SNGLfinal001', 'object', 'invoice',
  'billing_reason', 'manual', 'currency', 'usd', 'amount_paid', 64000, 'customer', 'cus_TSNGL00000', 'payment_intent', 'pi_SNGLfinal01',
  'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p4'),
    'order_summary_id', (select order_summary_id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p4')),
    'final_balance_invoice_id', (select id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p4'))),
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HyK5j4r4WkVPfrkvOv7h'))))))) ->> 'status',
  'processed', 'the final balance is paid');
select ok(private.project_balance_verified((select v::uuid from ids where k = 'p4')), 'G4 passes');
select is(pg_temp.refund('evt_SNGLfinref01', 're_SNGLfinref01', 1000, 'pi_SNGLfinal01') ->> 'status', 'processed',
  'a partial refund of the final balance is processed');
select ok((select o.kind = 'development_balance' from public.ledger_entries l join public.payment_obligations o on o.id = l.obligation_id
           where l.stripe_object_id = 're_SNGLfinref01')
  and private.project_final_balance_state((select v::uuid from ids where k = 'p4')) = 'refunded'
  and not private.project_balance_verified((select v::uuid from ids where k = 'p4')),
  'T-PAY-35: a final-balance refund is allocated to the balance obligation only, and G4 fails');
insert into public.ledger_entries (project_id, entry_type, amount_cents, service_category, source, webhook_event_id, holding_charge_key, dedupe_key)
select (select v::uuid from ids where k = 'p4'), 'refund', -1, null, 'webhook', (select max(id) from public.webhook_events),
  'final_balance:' || (select id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p4')), 'fixture:holding';
select ok(not private.project_balance_verified((select v::uuid from ids where k = 'p4'))
  and not (private.project_financial_status((select v::uuid from ids where k = 'p4'))).balance_verified_or_settled,
  'T-PAY-30: an unresolved reversal on the final-balance invoice fails G4');

select * from finish();
rollback;
