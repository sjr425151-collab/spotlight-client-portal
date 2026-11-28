-- WP-I I-2 (AUTH-008): fail-closed paths not covered elsewhere (01 §9.1.1; AUTHORIZATIONS
-- AUTH-008 "I-2 files"):
--   1. publication is blocked while a client approval is recorded but not yet consumed by WP-B
--      (no final-balance obligation, so G4 fails), and consumption alone does not unblock it;
--   2. issue_order_summary fails closed with no_usable_agreement_version when the database is
--      classified production and only the test-only fixture agreement exists;
--   3. the two environment classifications agree: private.runtime_environment (WP-C, mock
--      scanner) and private.environment_settings (WP-B, OI-69) say the same thing in the
--      seeded database, and with no rows a database is production with no mock scanner.
-- The project reaches each state through the real WP-B and WP-C workflow (helpers as in
-- 190_wpb_release_crosscheck.test.sql); no financial function is replaced. Synthetic events and
-- recorded mock results only (OI-63); no Stripe.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(33);

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
    'session_id', v_sid, 'amr',
      case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
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
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k; $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;

-- A project paid through the real workflow (as in 130): order summary (Owner), acceptance and
-- Checkout (client A), recorded mock results, a verified checkout.session.completed, and, when
-- p_card is set, the server's re-read of the card.
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
      p_card, 'cus_T' || p_tag || '00000', true));
  end if;
  return v_project;
end;
$$;
-- WP-C's real intake: the client saves and submits complete content; the Admin accepts it.
create function pg_temp.accept_intake(p_project uuid) returns void language plpgsql as $$
declare
  v_draft uuid;
  v_sub uuid;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v_draft := (public.save_intake_draft(p_project, jsonb_build_object('business_legal_name', 'Synthetic LLC',
    'business_display_name', 'Synthetic', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
    'address', '1 Test Street', 'service_areas', 'Test City', 'services_offered', 'Testing',
    'domain_status', 'needs_domain')) ->> 'draft_id')::uuid;
  v_sub := (public.submit_intake(p_project, v_draft) ->> 'submission_id')::uuid;
  reset role;
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  if not (public.review_intake(v_sub, 'accepted', 'Accepted') ->> 'ok')::boolean then
    raise exception 'fixture: intake for % was not accepted', p_project;
  end if;
  reset role;
end;
$$;
-- WP-C's real release_preview (staff, aal2) and approve_preview (the project's client).
-- AUTH-023 (setup only, OD-11(ii)): before a release, the project's current scope confirmation,
-- recorded by the Admin and acknowledged by its authorized signer, unless already acknowledged.
create function pg_temp.scope_ready(p_project uuid) returns void language plpgsql as $scope$
declare
  v jsonb;
  c public.scope_confirmations;
  v_signer uuid;
begin
  if private.scope_confirmation_state(p_project) = 'acknowledged' then
    return;
  end if;
  if private.scope_confirmation_state(p_project) in ('none', 'stale') then
    perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
    v := public.record_scope_confirmation(p_project, 'Synthetic client requirements', array['Synthetic selection'], '{}');
    reset role;
    if not coalesce((v ->> 'ok')::boolean, false) then
      raise exception 'fixture: record_scope_confirmation failed: %', v;
    end if;
  end if;
  c := private.current_scope_confirmation(p_project);
  v_signer := private.scope_authorized_signer(p_project);
  perform pg_temp.act_as(v_signer);
  v := public.acknowledge_scope_confirmation(c.id, c.content_sha256, true, true);
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: acknowledge_scope_confirmation failed: %', v;
  end if;
end;
$scope$;
create function pg_temp.release(p_project uuid, p_sha text) returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.scope_ready(p_project);
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  v := public.release_preview(p_project, p_sha, 'dpl_wph_' || left(p_sha, 8), 'https://preview.example.test/wph', '{}');
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: release_preview failed: %', v;
  end if;
  return (v ->> 'release_id')::uuid;
end;
$$;
create function pg_temp.approve(p_release uuid) returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.approve_preview(p_release);
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: approve_preview failed: %', v;
  end if;
  return (v ->> 'approval_id')::uuid;
end;
$$;
-- WP-C's own release.approved emission for a release (approve_preview emits once per release).
create function pg_temp.wpc_event(p_release uuid) returns bigint language sql as $$
  select id from public.domain_events where event_type = 'release.approved' and dedupe_key = 'release.approved:' || p_release;
$$;
create function pg_temp.consume(p_event bigint) returns text language sql as $$
  select private.consume_release_approved(p_event);
$$;
-- Obligations and final-balance creates for a project (both must stay zero on every rejection).
create function pg_temp.charges(p_project uuid) returns integer language sql as $$
  select ((select count(*) from public.final_balance_invoices where project_id = p_project)
        + (select count(*) from public.outbound_stripe_requests where project_id = p_project
            and purpose = 'final_balance_invoice_create'))::integer;
$$;
-- A project ready for a release: verified deposit, active card, accepted intake.
create function pg_temp.ready(p_tag text) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  v := pg_temp.paid_project(p_tag, 'pm_' || p_tag || 'card01');
  perform pg_temp.accept_intake(v);
  return v;
end;
$$;

create function pg_temp.qa_items() returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('key', a || '_check', 'area', a, 'result', 'pass'))
  from unnest(array['functional', 'responsive', 'branding_content', 'performance', 'accessibility', 'security',
                    'domain_operational', 'monitoring_rollback']) a;
$$;
create function pg_temp.sec_items() returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('key', k, 'severity', 'high', 'result', 'pass'))
  from unnest(array['https_hsts', 'security_headers', 'no_exposed_secrets', 'dependency_scan', 'form_abuse_protection',
                    'no_debug_endpoints', 'admin_surfaces_protected']) k;
$$;
grant execute on function pg_temp.qa_items(), pg_temp.sec_items() to authenticated;
-- Failing gates for a project's release, as a sorted comma list ('' = eligible).
create function pg_temp.failing(p_project uuid, p_release uuid) returns text language sql as $$
  select coalesce(string_agg(g ->> 'gate', ',' order by g ->> 'gate'), '')
  from jsonb_array_elements(private.evaluate_publication_gates(p_project, p_release) -> 'gates') g
  where not (g ->> 'passed')::boolean;
$$;
create function pg_temp.reason(p_project uuid, p_release uuid, p_gate text) returns text language sql as $$
  select g ->> 'reason' from jsonb_array_elements(private.evaluate_publication_gates(p_project, p_release) -> 'gates') g
   where g ->> 'gate' = p_gate;
$$;

-- ---------------------------------------------------------------------------
-- 1. Publication blocked by an unconsumed approval
-- ---------------------------------------------------------------------------
insert into ids select 'p', pg_temp.ready('WPIUNC')::text;
insert into ids select 'r', pg_temp.release(pg_temp.id('p'), repeat('d', 40))::text;
insert into ids select 'a', pg_temp.approve(pg_temp.id('r'))::text;
-- Every fulfillment gate passes for this release: QA, security, domain readiness, target.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((public.record_qa_result(pg_temp.id('r'), 'v1', pg_temp.qa_items()) ->> 'ok')::boolean,
  'fixture: passing QA for the approved release');
select ok((public.record_security_result(pg_temp.id('r'), 'v1', pg_temp.sec_items()) ->> 'ok')::boolean,
  'fixture: passing security checks for the approved release');
select ok((public.record_domain_check(pg_temp.id('p'), 'wpi-unconsumed.example.test', true, true, true, true, true,
  true, current_date - 30, current_date + 335, null) ->> 'ok')::boolean, 'fixture: a fresh passing domain check');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select ok((public.register_client_site_target(pg_temp.id('p'), 'wpi-unconsumed-site') ->> 'ok')::boolean,
  'fixture: the Owner registers the project''s isolated target');
reset role;

select ok(pg_temp.wpc_event(pg_temp.id('r')) is not null, 'the client approval emitted release.approved');
select ok(not exists (select 1 from private.event_consumptions where consumer = 'wpb.final_balance_invoice'
                       and domain_event_id = pg_temp.wpc_event(pg_temp.id('r'))),
  'the approval is not yet consumed by WP-B');
select is(pg_temp.charges(pg_temp.id('p')), 0, 'no final-balance obligation or create request exists yet');
select is(pg_temp.failing(pg_temp.id('p'), pg_temp.id('r')), 'G4',
  'with the approval unconsumed, G4 is the only failing gate (G3 passes: the release is approved)');
select is(pg_temp.reason(pg_temp.id('p'), pg_temp.id('r'), 'G4'), 'balance_not_verified',
  'G4 reports the unverified final balance');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.authorize_publication(pg_temp.id('p'), pg_temp.id('r')) -> 'failing_gates',
  '[{"gate": "G4", "reason": "balance_not_verified"}]'::jsonb,
  'the Owner, freshly reauthenticated, cannot authorize publication of an approval WP-B has not consumed');
reset role;
select is((select count(*)::int from public.publication_authorizations where project_id = pg_temp.id('p')), 0,
  'no publication authorization exists');
select ok(exists (select 1 from public.audit_events where action = 'publication.authorization_rejected'
                   and project_id = pg_temp.id('p') and summary -> 'failing_gates' @> '[{"gate": "G4"}]'),
  'the rejection is audited with G4');

-- Consumption creates the obligation but does not unblock publication: only a verified payment does.
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r'))), 'created', 'WP-B consumes the approval');
select is(pg_temp.charges(pg_temp.id('p')), 2, 'one final-balance invoice record and one create request');
select is(pg_temp.failing(pg_temp.id('p'), pg_temp.id('r')), 'G4',
  'after consumption, G4 still fails until the final balance is verified');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.authorize_publication(pg_temp.id('p'), pg_temp.id('r')) ->> 'error', 'gates_failed',
  'authorization is still rejected');
reset role;
select is((select count(*)::int from public.publication_authorizations where project_id = pg_temp.id('p')), 0,
  'still no publication authorization');

-- ---------------------------------------------------------------------------
-- 2. no_usable_agreement_version (fail closed)
-- ---------------------------------------------------------------------------
create function pg_temp.fresh_project(p_tag text) returns uuid language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('Biz ' || p_tag || ' LLC', 'Biz ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'Project ' || p_tag) returning id into v_project;
  return v_project;
end;
$$;
insert into ids select 'nv', pg_temp.fresh_project('WPINOVER')::text;
select ok(not exists (select 1 from public.agreement_versions v where not v.is_test_fixture),
  'precondition: the local database holds only the test-only fixture agreement');
create temporary table saved_env on commit drop as select * from private.environment_settings;
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
create temporary table oi119_runtime_400 on commit drop as select * from private.runtime_environment;
delete from private.runtime_environment;
delete from private.environment_settings;
select ok(private.is_production(), 'with no classification row the database is production');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.issue_order_summary(pg_temp.id('nv'), 'essential', '[]'::jsonb) ->> 'error', 'no_usable_agreement_version',
  'in production, the fixture is not usable and the order summary fails closed');
reset role;
select is((select count(*)::int from public.order_summaries where project_id = pg_temp.id('nv')), 0,
  'no order summary was created');
insert into private.environment_settings select * from saved_env;
insert into private.runtime_environment select * from oi119_runtime_400;
select pg_temp.oi119_assert_restored('400');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select ok((public.issue_order_summary(pg_temp.id('nv'), 'essential', '[]'::jsonb) ->> 'ok')::boolean,
  'control: with the development classification restored, the same call succeeds');
reset role;

-- ---------------------------------------------------------------------------
-- 3. Agreement of the two environment classifications
-- ---------------------------------------------------------------------------
select is((select count(*)::int from private.runtime_environment), 1, 'the seed records one runtime classification');
select is((select count(*)::int from private.environment_settings), 1, 'the seed records one billing classification');
select is((select app_env from private.runtime_environment), private.app_environment(),
  'private.runtime_environment and private.environment_settings agree');
select ok(not private.is_production() and private.scanner_permitted('mock_scanner'),
  'a seeded local database is non-production and permits the mock scanner');
select throws_ok($$ insert into private.runtime_environment (singleton, app_env) values (true, 'test') $$, '23505', null,
  'the runtime classification is a singleton');
select throws_ok($$ insert into private.environment_settings (singleton, app_env) values (true, 'test') $$, '23505', null,
  'the billing classification is a singleton');
select throws_ok($$ update private.runtime_environment set app_env = 'staging' $$, '23514', null,
  'the runtime classification can only say development or test');
select throws_ok($$ update private.environment_settings set app_env = 'production' $$, '23514', null,
  'production is never written: it is the absence of a row');

create temporary table saved_runtime on commit drop as select * from private.runtime_environment;
delete from private.runtime_environment;
delete from private.environment_settings;
select ok(private.is_production() and not private.scanner_permitted('mock_scanner'),
  'with neither row (a hosted database) it is production and the mock scanner is refused');
insert into private.environment_settings (app_env) values ('staging');
select ok(not private.is_production() and not private.scanner_permitted('mock_scanner'),
  'a staging classification never permits the mock scanner');
delete from private.environment_settings;
insert into private.runtime_environment select * from saved_runtime;
insert into private.environment_settings select * from saved_env;
select is((select app_env from private.runtime_environment), private.app_environment(),
  'restored: the classifications agree again');

select * from finish();
rollback;
