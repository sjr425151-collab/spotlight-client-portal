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
select plan(12);

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
create function pg_temp.project(p_tag text, p_state text) returns uuid language plpgsql as $$
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
  -- Paid (a verified deposit), or an anomaly: a mismatched amount, which processing quarantines.
  v_ingest := public.ingest_stripe_event(jsonb_build_object('id', 'evt_' || p_tag || 'chk', 'object', 'event',
    'type', 'checkout.session.completed', 'api_version', '2026-09-30.endive', 'livemode', false,
    'created', extract(epoch from now())::bigint, 'data', jsonb_build_object('object', jsonb_build_object(
      'id', 'cs_test_' || p_tag, 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
      'amount_total', case when p_state = 'anomaly' then 12345 else 25900 end, 'payment_status', 'paid',
      'customer', 'cus_T' || p_tag, 'subscription', 'sub_' || p_tag, 'invoice', 'in_' || p_tag,
      'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
      'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
        'checkout_record_id', v_cs)))), repeat('c', 64));
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
  ('anomaly', pg_temp.project('EvQ0001', 'anomaly'));
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

-- ---- The states built through the real functions ----
select is((select array_agg((s).agreement_state::text || '/' || (s).deposit_state::text order by k)
             from (select k, private.project_financial_status(v) s from ids) x),
  array['accepted_pending_payment/pending', 'accepted_pending_payment/pending', 'not_presented/not_started',
        'effective/verified', 'effective/verified', 'presented/not_started'],
  'setup: lead, presented, accepted, two paid and one anomaly project');
select ok((select cardinality(private.gate_anomalies(v, 'G2')) > 0 from ids where k = 'anomaly'),
  'setup: the anomaly project carries an unresolved G2 anomaly (a quarantined event)');

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

-- ---- Failure parity and the fallback when the set pass raises ----
-- Test-only, inside this rolled-back transaction: holding_balance_cents is wrapped so that it raises
-- for one paid project's charge only. The set pass evaluates every verified deposit, so it raises
-- and the helper falls back to the per-project function, where only that project raises.
alter function private.holding_balance_cents(text) rename to holding_balance_cents_oi131;
create function private.holding_balance_cents(p_charge_key text) returns bigint
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_charge_key = (select o.charge_key from public.payment_obligations o
                      where o.project_id = (select v from pg_temp.ids where k = 'paid1')
                        and o.kind = 'development_deposit') then
    raise exception 'forced failure (AUTH-026 test)';
  end if;
  return private.holding_balance_cents_oi131(p_charge_key);
end;
$$;
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
