-- WP-B: billing job entry points (04 §13; T-ARC-09) and the dispute evidence package with
-- WP-C's evidence interface (04 §15.4; T-ARC-10). Concurrent single-flight runs across two
-- connections are proven in tests/integration/wpb-billing.test.ts.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(18);

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
    perform public.outbound_request_for_execution(v_req.id);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, 'succeeded', 'cus_T' || p_tag || '00000', false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, 'succeeded', 'cs_test_' || p_tag || '00000', false, 200, null,
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

-- ---------------------------------------------------------------------------
-- 1. Job entry points (T-ARC-09)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select throws_ok($$ select public.run_billing_job('maintenance_recovery') $$, '42501', null,
  'T-ARC-09: a job entry point is not executable by a signed-in user, even the Owner');
reset role;
select ok(not has_function_privilege('service_role', 'private.evaluate_maintenance_recoveries()', 'execute')
  and not has_function_privilege('service_role', 'private.consume_release_approvals(integer)', 'execute')
  and not has_function_privilege('service_role', 'private.retry_pending_webhook_events(integer)', 'execute')
  and not has_function_privilege('service_role', 'private.advance_service_terminations()', 'execute')
  and not has_function_privilege('service_role', 'private.mark_stale_outbound_requests()', 'execute'),
  'T-ARC-09: the job internals are reachable only through their single entry point');
select is(pg_temp.svc($$ select public.run_billing_job('drop_everything') $$) ->> 'error', 'unknown_job', 'unknown jobs are refused');
insert into ids select 'p_job', pg_temp.paid_project('JOBS', null)::text;
select pg_temp.deliver(pg_temp.evt('evt_JOBSsub00001', 'customer.subscription.created', jsonb_build_object('id', 'sub_JOBS00000',
  'object', 'subscription', 'status', 'active', 'customer', 'cus_TJOBS00000', 'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p_job')))));
select pg_temp.deliver(pg_temp.evt('evt_JOBSfail0001', 'invoice.payment_failed', jsonb_build_object('id', 'in_JOBSrenew01', 'object', 'invoice',
  'billing_reason', 'subscription_cycle', 'currency', 'usd', 'customer', 'cus_TJOBS00000', 'subscription', 'sub_JOBS00000'), -12 * 86400));
select is(pg_temp.svc($$ select public.run_billing_job('maintenance_recovery') $$) #>> '{result,holds_placed}', '1', 'the first run places the hold');
select is(pg_temp.svc($$ select public.run_billing_job('maintenance_recovery') $$) #>> '{result,holds_placed}', '0',
  'T-ARC-09: a rerun changes nothing (idempotent)');
select is((select count(*)::integer from public.billing_holds where project_id = (select v::uuid from ids where k = 'p_job')), 1, 'exactly one hold exists');
select ok((select count(*) = 2 and bool_and(status = 'completed' and result is not null) from public.billing_job_runs where job = 'maintenance_recovery')
  and (select count(*) = 2 from public.audit_events where action = 'billing_job.completed' and target_id = 'maintenance_recovery'
         and category = 'financial'),
  'T-ARC-09: each run is recorded with its result and audited');
select ok((pg_temp.svc($$ select public.run_billing_job('webhook_backfill') $$) ->> 'ok')::boolean
  and (pg_temp.svc($$ select public.run_billing_job('release_approvals') $$) ->> 'ok')::boolean
  and (pg_temp.svc($$ select public.run_billing_job('service_terminations') $$) ->> 'ok')::boolean
  and (pg_temp.svc($$ select public.run_billing_job('outbound_requests') $$) ->> 'ok')::boolean,
  'every database job has its own entry point (04 §13)');
select isnt(pg_temp.svc($$ select to_jsonb(public.start_reconciliation_run('mocked_gateway', 'run-150')) $$), null::jsonb,
  'the daily reconciliation run starts');
select is(pg_temp.svc($$ select to_jsonb(public.start_reconciliation_run('mocked_gateway', 'run-150')) $$), null::jsonb,
  'T-ARC-09: a second reconciliation with the same run key is a no-op');
select ok(exists (select 1 from public.audit_events where action = 'billing_job.skipped' and target_id = 'reconciliation'),
  'the skipped reconciliation is audited');
select isnt(pg_temp.svc($$ select to_jsonb(public.begin_billing_job('payment_method_lookups')) $$), null::jsonb,
  'the server-driven card re-read job starts');
select is(pg_temp.svc($$ select to_jsonb(public.begin_billing_job('payment_method_lookups')) $$), null::jsonb,
  'T-ARC-09: a second concurrent start of the server-driven job is refused (single-flight)');

-- ---------------------------------------------------------------------------
-- 2. Dispute evidence with WP-C's interface (04 §15.4; T-ARC-10)
-- ---------------------------------------------------------------------------
insert into ids select 'p_ev', pg_temp.paid_project('EVID', 'pm_EVIDcard01')::text;
-- WP-C records, as a fixture in this rolled-back test (WP-B code never writes WP-C tables).
insert into public.preview_releases (project_id, release_number, commit_sha, deployment_id, preview_url, released_by)
values ((select v::uuid from ids where k = 'p_ev'), 1, repeat('a', 40), 'dpl_evid_1', 'https://preview.example.test/1',
        '00000000-0000-4000-8000-000000000002') returning id \gset rel_
insert into ids values ('rel', :'rel_id');
insert into public.preview_approvals (release_id, project_id, user_id)
values ((select v::uuid from ids where k = 'rel'), (select v::uuid from ids where k = 'p_ev'), '00000000-0000-4000-8000-0000000000a1')
returning id \gset appr_
insert into ids values ('appr', :'appr_id');
select private.emit_domain_event('release.approved', (select v::uuid from ids where k = 'p_ev'), 'preview_release',
  (select v from ids where k = 'rel'), jsonb_build_object('approval_id', (select v from ids where k = 'appr')), 'release.approved:t150');
select pg_temp.consume();
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select id from public.outbound_stripe_requests
  where project_id = (select v::uuid from ids where k = 'p_ev') and purpose = 'final_balance_invoice_create')));
select pg_temp.svc(format('select public.record_outbound_result(%L, ''succeeded'', ''in_EVIDfinal01'', false, 200, null, ''{}'')',
  (select id from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_ev') and purpose = 'final_balance_invoice_create')));
select is(pg_temp.deliver(pg_temp.evt('evt_EVIDpaid0001', 'invoice.paid', jsonb_build_object('id', 'in_EVIDfinal01', 'object', 'invoice',
  'billing_reason', 'manual', 'currency', 'usd', 'amount_paid', 64000, 'customer', 'cus_TEVID00000', 'default_payment_method', 'pm_EVIDcard01',
  'payment_intent', 'pi_EVIDfinal01',
  'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p_ev'),
    'order_summary_id', (select order_summary_id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_ev')),
    'final_balance_invoice_id', (select id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_ev'))),
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HyK5j4r4WkVPfrkvOv7h'))))))) ->> 'status',
  'processed', 'the final balance is paid automatically');
select is(pg_temp.deliver(pg_temp.evt('evt_EVIDdisp0001', 'charge.dispute.created', jsonb_build_object('id', 'dp_EVIDdisp0001', 'object', 'dispute',
  'amount', 64000, 'currency', 'usd', 'status', 'needs_response', 'payment_intent', 'pi_EVIDfinal01'))) ->> 'status', 'processed',
  'a dispute of the final-balance charge is processed');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.dispute_evidence_package('dp_EVIDdisp0001') ->> 'error', 'forbidden', 'T-ARC-10: the package is Owner-only');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'pkg', public.dispute_evidence_package('dp_EVIDdisp0001')::text;
reset role;
select ok((select (v::jsonb #>> '{fulfillment,ok}') = 'true'
             and (v::jsonb #>> '{fulfillment,release_filter}') = (select v from ids where k = 'rel')
             and (v::jsonb #>> '{fulfillment,preview_approvals,0,id}') = (select v from ids where k = 'appr')
             and (v::jsonb #> '{fulfillment}') ? 'publication_authorizations'
             and (v::jsonb #> '{fulfillment}') ? 'deployments' and (v::jsonb #> '{fulfillment}') ? 'live_verifications'
             and not (v::jsonb) ? 'note'
           from ids where k = 'pkg'),
  'T-ARC-10: the package includes WP-C''s evidence for exactly the charged release, its approval, publication, deployment, and live verification');
-- Still under the Owner's claims (the interface is Owner-only); now() is fixed in this transaction.
select ok((select (v::jsonb -> 'fulfillment') = private.wpc_dispute_evidence((select v::uuid from ids where k = 'p_ev'), (select v::uuid from ids where k = 'rel'))
             and jsonb_array_length(v::jsonb -> 'payment_authorizations') = 1
             and jsonb_array_length(v::jsonb -> 'acceptances') = 1
           from ids where k = 'pkg'),
  'T-ARC-10: WP-C''s interface result is included in full and unaltered, alongside WP-B''s authorization and acceptance records');

select * from finish();
rollback;
