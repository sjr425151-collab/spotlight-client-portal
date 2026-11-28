-- AUTH-026 (OI-131), WP-B: private.financial_evaluation_for_projects, the additive set-based
-- financial evaluation the staff operational queue uses. Isolation (no API-role execute; definer;
-- STABLE; empty search_path), exact equivalence with private.project_financial_status for every
-- project state built here (to_jsonb byte for byte; one row per distinct id, null and unknown ids
-- included), per-project failure parity, and the per-project fallback when the set pass raises.
-- The suite-wide equivalence (every state the other suites reach) and the performance evidence
-- are in tests/perf/ (outside the pgTAP path). Synthetic data only; everything is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(30);

-- Test-only, inside this rolled-back transaction, installed before any financial function runs here
-- (an already-resolved call site keeps the function it first resolved): holding_balance_cents is
-- wrapped so that it raises for one charge key, but only once the oi131.fail_charge setting names it.
alter function private.holding_balance_cents(text) rename to holding_balance_cents_oi131;
create function private.holding_balance_cents(p_charge_key text) returns bigint
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_charge_key = nullif(current_setting('oi131.fail_charge', true), '') then
    raise exception 'forced failure (AUTH-026 test)';
  end if;
  return private.holding_balance_cents_oi131(p_charge_key);
end;
$$;
-- Likewise calendar_version, which the per-project row assembly calls once per project. While
-- oi131.fail_assembly_at is set, every call is counted (a sequence: not rolled back by a failed
-- subtransaction) and the call with that number raises.
create sequence pg_temp.oi131_assembly_calls;
alter function private.calendar_version() rename to calendar_version_oi131;
create function private.calendar_version() returns text
language plpgsql volatile set search_path = '' as $$
begin
  if nullif(current_setting('oi131.fail_assembly_at', true), '') is not null
     and nextval('pg_temp.oi131_assembly_calls') = current_setting('oi131.fail_assembly_at')::bigint then
    raise exception 'forced assembly failure (AUTH-026 test)';
  end if;
  return private.calendar_version_oi131();
end;
$$;

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1') returns void language plpgsql as $$
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
    'session_id', v_sid, 'amr', jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)))::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
-- A project in a given state, through the real WP-B functions (the 190 pattern).
create function pg_temp.project(p_tag text, p_state text, p_other text default null) returns uuid
language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
  v_os uuid;
  v_acc uuid;
  v_cs uuid;
  v_req record;
  v_tok uuid;
  v_ingest jsonb;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('Eval ' || p_tag || ' LLC', 'Eval ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'Eval ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '00000000-0000-4000-8000-0000000000a1');
  if p_state = 'lead' then
    return v_project;
  end if;
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
  v_os := (public.issue_order_summary(v_project, 'essential') ->> 'order_summary_id')::uuid;
  reset role;
  if p_state = 'presented' then
    return v_project;
  end if;
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'Eval ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
  v_cs := (public.begin_initial_checkout(v_project) ->> 'checkout_session_id')::uuid;
  reset role;
  perform pg_temp.as_service();
  for v_req in select id, purpose from public.outbound_stripe_requests where project_id = v_project
               order by (purpose = 'customer_create') desc loop
    v_tok := (public.outbound_request_for_execution(v_req.id) ->> 'claim_token')::uuid;
    perform public.confirm_outbound_dispatch(v_req.id, v_tok);
    perform public.record_outbound_result(v_req.id, v_tok, 'succeeded',
      case when v_req.purpose = 'customer_create' then 'cus_T' || p_tag else 'cs_test_' || p_tag end, false, 200, null,
      case when v_req.purpose = 'customer_create' then '{}'::jsonb
           else jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_' || p_tag) end);
  end loop;
  if p_state = 'accepted' then
    reset role;
    return v_project;
  end if;
  -- Paid: a verified deposit.
  v_ingest := public.ingest_stripe_event(jsonb_build_object('id', 'evt_' || p_tag || 'chk', 'object', 'event',
    'type', 'checkout.session.completed', 'api_version', '2026-09-30.endive', 'livemode', false,
    'created', extract(epoch from now())::bigint, 'data', jsonb_build_object('object', jsonb_build_object(
      'id', 'cs_test_' || p_tag, 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
      'amount_total', 25900, 'payment_status', 'paid',
      'customer', 'cus_T' || p_tag, 'subscription', 'sub_' || p_tag, 'invoice', 'in_' || p_tag,
      'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
      'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
        'checkout_record_id', v_cs)))), repeat('c', 64));
  perform public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  if p_state = 'anomaly' then
    -- The 190 pattern: the initial invoice records the payment intent; a refund naming this
    -- project's payment intent and another project's invoice is quarantined (attribution conflict).
    v_ingest := public.ingest_stripe_event(jsonb_build_object('id', 'evt_' || p_tag || 'inv', 'object', 'event',
      'type', 'invoice.paid', 'api_version', '2026-09-30.endive', 'livemode', false,
      'created', extract(epoch from now())::bigint, 'data', jsonb_build_object('object', jsonb_build_object(
        'id', 'in_' || p_tag, 'object', 'invoice', 'billing_reason', 'subscription_create', 'currency', 'usd',
        'amount_paid', 25900, 'customer', 'cus_T' || p_tag, 'payment_intent', 'pi_' || p_tag || 'init',
        'parent', jsonb_build_object('subscription_details', jsonb_build_object('subscription', 'sub_' || p_tag,
          'metadata', jsonb_build_object('project_id', v_project, 'checkout_record_id', v_cs))),
        'lines', jsonb_build_object('data', jsonb_build_array(
          jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HxK5j4r4WkVPkRUJ4gnZ')),
          jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))))),
      repeat('c', 64));
    perform public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
    v_ingest := public.ingest_stripe_event(jsonb_build_object('id', 'evt_' || p_tag || 'conf', 'object', 'event',
      'type', 'refund.updated', 'api_version', '2026-09-30.endive', 'livemode', false,
      'created', extract(epoch from now())::bigint + 10, 'data', jsonb_build_object('object', jsonb_build_object(
        'id', 're_' || p_tag || 'conf', 'object', 'refund', 'amount', 1200, 'currency', 'usd', 'status', 'succeeded',
        'payment_intent', 'pi_' || p_tag || 'init', 'invoice', 'in_' || p_other, 'metadata', '{}'::jsonb))),
      repeat('c', 64));
  end if;
  perform public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  reset role;
  return v_project;
end;
$$;
create temp table ids (k text primary key, v uuid);
insert into ids values
  ('lead', pg_temp.project('EvL0001', 'lead')),
  ('presented', pg_temp.project('EvP0001', 'presented')),
  ('accepted', pg_temp.project('EvA0001', 'accepted')),
  ('paid1', pg_temp.project('EvD0001', 'paid')),
  ('paid2', pg_temp.project('EvD0002', 'paid')),
  ('anomaly', pg_temp.project('EvQ0001', 'anomaly', 'EvD0002'));
create function pg_temp.all_ids() returns uuid[] language sql as $$
  select array_agg(id) || array[null::uuid, gen_random_uuid()] from public.projects
$$;
-- The comparison: one row per distinct id, each equal to the per-project function, with failure parity.
create function pg_temp.mismatches(p_ids uuid[]) returns integer language sql as $$
  select count(*)::int from private.financial_evaluation_for_projects(p_ids) e
   where e.failed or to_jsonb(e.status) is distinct from to_jsonb(private.project_financial_status(e.project_id))
$$;

-- ---- Isolation: a private definer helper no API role may execute ----
select ok((select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
             from pg_proc p where p.oid = 'private.financial_evaluation_for_projects(uuid[])'::regprocedure),
  'AUTH-026: the helper is SECURITY DEFINER, STABLE, with an empty search_path');
select ok(not has_function_privilege('authenticated', 'private.financial_evaluation_for_projects(uuid[])', 'execute')
  and not has_function_privilege('anon', 'private.financial_evaluation_for_projects(uuid[])', 'execute')
  and not has_function_privilege('service_role', 'private.financial_evaluation_for_projects(uuid[])', 'execute')
  and not has_function_privilege('public', 'private.financial_evaluation_for_projects(uuid[])', 'execute'),
  'AUTH-026: no API role (anon, authenticated, service_role, PUBLIC) may execute the helper');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select throws_ok($$ select * from private.financial_evaluation_for_projects(array[gen_random_uuid()]) $$, '42501', null,
  'AUTH-026: even the Owner, as authenticated, cannot call the helper');
reset role;

-- ---- Drift guard (WP-C N-1): the per-project functions the helper mirrors set-based ----
-- The helper reimplements these bodies; a change to any of them must change the helper in the same
-- change (and its equivalence evidence). md5 of the merged prosrc; one assertion each.
select is(md5(p.prosrc), v.md5,
  format('drift guard: %s is unchanged; if this changes, update private.financial_evaluation_for_projects in the same change', v.sig))
  from (values
    ('private.gate_anomalies(uuid,text)', '9cbf0faf7f1fa460bd07686829b87e16'),
    ('private.obligation_disputed(uuid)', '770d51db38c019c922cb4b8e0cbb1f92'),
    ('private.obligation_net_cents(uuid)', 'e318d61a3fd9c44a00e601801868c93e'),
    ('private.payment_authorization_state(uuid)', '3590526e6a893a815df651a3e472950d'),
    ('private.project_active_billing_holds(uuid)', '4474fba2507a4c4919b9fcebdd24d9fe'),
    ('private.project_agreement_state(uuid)', 'ea07f771ee19c442d26b1707e9071e54'),
    ('private.project_balance_verified(uuid)', 'a6366dca74491ef736696a8e34057ab0'),
    ('private.project_deposit_ever_verified(uuid)', '8d34bfa3a710c01cc62886c62c6612c8'),
    ('private.project_deposit_obligation(uuid)', 'baaa0c9c1821b9d6b86a10b69376b594'),
    ('private.project_deposit_state(uuid)', 'c532a027d11518434ca700fd9f43717e'),
    ('private.project_deposit_verified(uuid)', 'd6ba50f0ce969d08137cac6faa39bdd3'),
    ('private.project_final_balance_state(uuid)', 'a70633debea04d59addd88401bc17195'),
    ('private.project_financial_anomalies(uuid)', 'c13caa4d5e64299549d0b5817efab62a'),
    ('private.project_financial_status(uuid)', 'ee4e4342fe8ce7b0e808d7e88375f392'),
    ('private.reversal_observations(uuid)', '7e513d97bb688a608040eb27ef14ab06'),
    ('private.unposted_reversals(uuid)', 'c8f426a0f8b16b1c7cbb71521f7ef3d9')) v (sig, md5)
  join pg_proc p on p.oid = v.sig::regprocedure
 order by v.sig;

-- ---- The states built through the real functions ----
select is((select array_agg((s).agreement_state::text || '/' || (s).deposit_state::text order by k)
             from (select k, private.project_financial_status(v) s from ids) x),
  array['accepted_pending_payment/pending', 'effective/verified', 'not_presented/not_started',
        'effective/verified', 'effective/verified', 'presented/not_started'],
  'setup: lead, presented, accepted, two paid and one anomaly project');
select ok((select bool_and(private.gate_anomalies(v, 'G2') = array['quarantined_event']
                     and private.gate_anomalies(v, 'G4') = array['quarantined_event'])
             from ids where k in ('anomaly', 'paid2'))
  and (select cardinality(private.gate_anomalies(v, 'G2')) = 0 from ids where k = 'paid1'),
  'setup: the attribution conflict blocks G2 and G4 for both candidate projects, and no other');

-- ---- Exact equivalence, one row per distinct id ----
select is(pg_temp.mismatches(pg_temp.all_ids()), 0,
  'AUTH-026: every project, plus a null and an unknown id, equals private.project_financial_status exactly (to_jsonb)');
select is((select count(*)::int from private.financial_evaluation_for_projects(
             (select array_agg(v) from ids) || (select array_agg(v) from ids) || array[null::uuid, null::uuid])),
  7, 'AUTH-026: one row per distinct input id (duplicates collapse; null counts once)');
select is((select count(*)::int from private.financial_evaluation_for_projects('{}'::uuid[])), 0,
  'AUTH-026: an empty input returns no rows');
select is((select to_jsonb(e.status) -> 'evidence' -> 'blocking_anomalies'
             from private.financial_evaluation_for_projects(array[(select v from ids where k = 'anomaly')]) e),
  to_jsonb(private.project_financial_status((select v from ids where k = 'anomaly'))) -> 'evidence' -> 'blocking_anomalies',
  'AUTH-026: the anomaly kinds per gate are those gate_anomalies returns');

-- ---- One project's assembly raises (WP-I N-1): that project falls back to the per-project function ----
-- A counting run (no call matches 0) gives C calls for P projects: the set pass makes C - P and the
-- assembly makes one per project, after the set pass. The next run then raises on its first
-- assembly call, call C + (C - P) + 1, so the set pass completes and exactly one assembly raises.
create temp table nn as select array_agg(id) a from public.projects;
do $$ begin perform set_config('oi131.fail_assembly_at', '0', true); end $$;
create temp table counting_run as select * from private.financial_evaluation_for_projects((select a from nn));
do $$
declare
  c bigint := (select last_value from pg_temp.oi131_assembly_calls);
  p bigint := (select cardinality(a) from pg_temp.nn);
begin
  perform set_config('oi131.calls_before', c::text, true);
  perform set_config('oi131.fail_assembly_at', (c + (c - p) + 1)::text, true);
end $$;
create temp table assembly_run as select * from private.financial_evaluation_for_projects((select a from nn));
do $$ begin perform set_config('oi131.fail_assembly_at', '', true); end $$;
select is((select last_value from pg_temp.oi131_assembly_calls), 2 * current_setting('oi131.calls_before')::bigint + 1,
  'setup: exactly one assembly raised, and that project was evaluated once more by the fallback');
select is((select count(*)::int from assembly_run e
            where e.failed or to_jsonb(e.status) is distinct from to_jsonb(private.project_financial_status(e.project_id))), 0,
  'AUTH-026: a project whose assembly raises falls back to private.project_financial_status for that project alone; no project is failed and every row is exact');

-- ---- Failure parity and the fallback when the set pass raises ----
-- The wrapper (installed above) now raises for one paid project's deposit charge only. The set pass
-- evaluates every verified deposit, so it raises and the helper falls back to the per-project
-- function, where only that project raises.
do $$ begin
  perform set_config('oi131.fail_charge', (select o.charge_key from public.payment_obligations o
    where o.project_id = (select v from pg_temp.ids where k = 'paid1') and o.kind = 'development_deposit'), true);
end $$;
select throws_ok(format('select private.project_financial_status(%L)', (select v from ids where k = 'paid1')),
  'P0001', 'forced failure (AUTH-026 test)', 'setup: the per-project function raises for that one project');
select ok((select bool_and(case when e.project_id = (select v from ids where k = 'paid1')
                                then e.failed and e.status is null
                                else not e.failed end)
             from private.financial_evaluation_for_projects(pg_temp.all_ids()) e),
  'AUTH-026: after the set pass raises, only the failing project is marked failed (status null); the call goes on');
select is((select count(*)::int from private.financial_evaluation_for_projects(pg_temp.all_ids()) e
            where e.project_id is distinct from (select v from ids where k = 'paid1')
              and to_jsonb(e.status) is distinct from to_jsonb(private.project_financial_status(e.project_id))), 0,
  'AUTH-026: in the fallback, every other project still equals the per-project function exactly');

select * from finish();
rollback;
