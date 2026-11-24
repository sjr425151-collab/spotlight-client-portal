-- WP-C publication integrity (06 §2-§9; OI-71; OI-72): the single gate evaluator, Owner
-- authorization, staff-assisted deployment records, live verification, derived queues.
-- T-PUB-01 to T-PUB-08, T-PUB-10 to T-PUB-12, T-PUB-15, T-PUB-17 to T-PUB-19, T-LC-03 (WP-C
-- queues). Financial inputs come from a test-only fixture of the approved WP-B interface.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(117);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_totp_age interval default null)
returns void language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
  v_amr jsonb := jsonb_build_array(jsonb_build_object('method', 'otp',
                   'timestamp', extract(epoch from now() - interval '1 hour')::bigint));
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  if p_totp_age is not null then
    v_amr := v_amr || jsonb_build_array(jsonb_build_object('method', 'totp',
               'timestamp', extract(epoch from now() - p_totp_age)::bigint));
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated', 'aal', p_aal, 'amr', v_amr, 'session_id', v_sid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.as_owner() returns void language sql as $$
  select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
$$;
create function pg_temp.as_admin() returns void language sql as $$
  select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
$$;
create function pg_temp.as_server() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
grant execute on function pg_temp.act_as(uuid, text, interval), pg_temp.as_owner(), pg_temp.as_admin(),
  pg_temp.as_server() to authenticated, service_role;

-- Test-only fixture of the WP-B interface. All financial inputs pass by default here.
create table private.test_financial_fixture (project_id uuid primary key, data jsonb not null);
do $$
begin
  if not exists (select 1 from pg_attribute where attrelid = 'private.project_financial_status'::regclass
                 and attname = 'agreement_effective' and not attisdropped) then
    alter type private.project_financial_status add attribute agreement_state public.agreement_state,
      add attribute agreement_effective boolean;
  end if;
end;
$$;
create or replace function private.project_financial_status(p_project_id uuid) returns private.project_financial_status
language sql stable security definer set search_path = '' as $$
  select jsonb_populate_record(null::private.project_financial_status,
    jsonb_build_object('project_id', p_project_id, 'contract_version', 1, 'implemented', false,
      'deposit_state', 'not_started', 'deposit_verified', false, 'final_balance_state', 'not_due',
      'balance_verified_or_settled', false, 'balance_settled_by_adjustment', false,
      'active_billing_holds', '[]'::jsonb, 'evidence', '{}'::jsonb)
    || coalesce((select f.data from private.test_financial_fixture f where f.project_id = p_project_id), '{}'::jsonb));
$$;
create function pg_temp.fin(p jsonb) returns void language sql as $$
  update private.test_financial_fixture set data = data || p where project_id = '20000000-0000-4000-8000-0000000000a0';
$$;
insert into private.test_financial_fixture values ('20000000-0000-4000-8000-0000000000a0',
  '{"implemented": true, "agreement_state": "effective", "agreement_effective": true, "deposit_state": "verified",
    "deposit_verified": true, "final_balance_state": "verified", "balance_verified_or_settled": true,
    "balance_settled_by_adjustment": false, "active_billing_holds": [], "evidence": {"order_summary_id": "fin-secret-ref"}}');

create function pg_temp.qa_items(p_fail_area text default null) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('key', a || '_check', 'area', a,
    'result', case when a = p_fail_area then 'fail' else 'pass' end))
  from unnest(array['functional', 'responsive', 'branding_content', 'performance', 'accessibility', 'security',
                    'domain_operational', 'monitoring_rollback']) a;
$$;
create function pg_temp.sec_items(p_fail_key text default null, p_severity text default 'critical') returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('key', k, 'severity', case when k = p_fail_key then p_severity else 'high' end,
    'result', case when k = p_fail_key then 'fail' else 'pass' end))
  from unnest(array['https_hsts', 'security_headers', 'no_exposed_secrets', 'dependency_scan', 'form_abuse_protection',
                    'no_debug_endpoints', 'admin_surfaces_protected']) k;
$$;
grant execute on function pg_temp.qa_items(text), pg_temp.sec_items(text, text) to authenticated;
-- Failing gates for Project A's current release, as a sorted comma list ('' = eligible).
create function pg_temp.failing() returns text language sql as $$
  select coalesce(string_agg(g ->> 'gate', ',' order by g ->> 'gate'), '')
  from jsonb_array_elements(private.evaluate_publication_gates('20000000-0000-4000-8000-0000000000a0',
         (private.current_release('20000000-0000-4000-8000-0000000000a0')).id) -> 'gates') g
  where not (g ->> 'passed')::boolean;
$$;
create function pg_temp.reason(p_gate text) returns text language sql as $$
  select g ->> 'reason' from jsonb_array_elements(private.evaluate_publication_gates('20000000-0000-4000-8000-0000000000a0',
         (private.current_release('20000000-0000-4000-8000-0000000000a0')).id) -> 'gates') g where g ->> 'gate' = p_gate;
$$;

-- Fulfillment fixtures for Project A: accepted intake, release 1 approved by the client,
-- passing QA and security for release 1, a fresh passing domain check, an isolated target.
insert into public.intake_submissions (id, project_id, version, status, content, created_by, submitted_by, submitted_at)
values ('31000000-0000-4000-8000-0000000000a0', '20000000-0000-4000-8000-0000000000a0', 1, 'submitted', '{}',
        '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', now());
insert into public.intake_reviews (project_id, submission_id, decision, reviewed_by) values
  ('20000000-0000-4000-8000-0000000000a0', '31000000-0000-4000-8000-0000000000a0', 'accepted', '00000000-0000-4000-8000-000000000002');
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by, released_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 1, repeat('1', 40), 'dpl_a1',
        'https://preview-a.example.test', '00000000-0000-4000-8000-000000000002', now() - interval '2 days');

select ok(pg_temp.failing() = 'G3,G5,G6,G7', 'with only an unapproved release, G3, G5, G6, and G7 fail (no evidence yet)');
select is(pg_temp.reason('G5'), 'no_qa_for_release', 'missing QA evidence fails G5 with a reason');

select pg_temp.as_admin();
select is(public.record_qa_result('34000000-0000-4000-8000-0000000000a1', 'v1',
  pg_temp.qa_items() - 0) ->> 'error', 'invalid_input', 'a QA result must cover every mandatory area (06 §6)');
select ok((public.record_qa_result('34000000-0000-4000-8000-0000000000a1', 'v1', pg_temp.qa_items()) ->> 'ok')::boolean,
  'Admin records a passing QA result for release 1');
select is(public.record_security_result('34000000-0000-4000-8000-0000000000a1', 'v1', pg_temp.sec_items() - 0) ->> 'error',
  'invalid_input', 'a security result must cover the 06 §7 checklist');
select ok((public.record_security_result('34000000-0000-4000-8000-0000000000a1', 'v1', pg_temp.sec_items()) ->> 'ok')::boolean,
  'Admin records a passing security result for release 1');
select ok((public.record_domain_check('20000000-0000-4000-8000-0000000000a0', 'client-a.example.test', true, true, true, true, true,
  true, current_date - 30, current_date + 335, null) ->> 'ok')::boolean, 'Admin records a passing domain readiness check');
select is(public.register_client_site_target('20000000-0000-4000-8000-0000000000a0', 'client-a-site') ->> 'error', 'forbidden',
  'Admin cannot register a client deployment target (Owner only)');
reset role;
select pg_temp.as_owner();
select ok((public.register_client_site_target('20000000-0000-4000-8000-0000000000a0', 'client-a-site') ->> 'ok')::boolean,
  'the Owner registers Project A''s isolated target');
select is(public.register_client_site_target('20000000-0000-4000-8000-0000000000b0', 'client-a-site') ->> 'error', 'target_in_use',
  'T-PUB-15: a target belongs to exactly one project');
reset role;
select ok(pg_temp.failing() = 'G3', 'only the client approval (G3) is missing');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((public.approve_preview('34000000-0000-4000-8000-0000000000a1') ->> 'ok')::boolean, 'client A approves release 1');
reset role;
select is(pg_temp.failing(), '', 'every gate G1-G8 passes');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'eligible'::public.publication_state,
  'publication state is derived as eligible');

-- ---------------------------------------------------------------------------
-- 1. Derived queue before authorization (T-LC-03; OI-72)
-- ---------------------------------------------------------------------------
select pg_temp.as_admin();
select ok(exists (select 1 from public.operational_queue() q where q ->> 'queue' = 'ready_for_publication_review'
  and q ->> 'project_id' = '20000000-0000-4000-8000-0000000000a0' and q -> 'detail' = '{"publication_eligible": true}'),
  'Ready for publication review shows eligibility only (OI-72)');
select ok(not exists (select 1 from public.operational_queue() q where q::text like '%fin-secret-ref%'),
  'OI-72: no financial evidence reaches the Admin queue');
reset role;

-- ---------------------------------------------------------------------------
-- 2. Owner authorization (T-PUB-02, T-PUB-03, T-PUB-04)
-- ---------------------------------------------------------------------------
select pg_temp.as_admin();
select is(public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') ->> 'error',
  'forbidden', 'T-PUB-02: Admin cannot authorize publication');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') ->> 'error',
  'forbidden', 'T-PUB-02: a client cannot trigger publication');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '10 minutes');
select is(public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') ->> 'error',
  'reauthentication_required', 'T-PUB-03: authorization without fresh reauthentication is rejected');
reset role;
select is((select count(*)::int from public.audit_events where action = 'publication.authorization_rejected'
  and summary ->> 'reason' = 'reauthentication_required'), 1, 'T-PUB-03: the rejection is audited');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private')
    and (p.proname ~ '(force|override|bypass|skip|mark_paid|manual_publish)'
         or exists (select 1 from unnest(coalesce(p.proargnames, '{}')) a where a ~ '(force|override|bypass|skip)'))), 0,
  'T-PUB-04: no function or parameter exists that forces, overrides, skips, or bypasses gate evaluation');
select pg_temp.as_owner();
select ok((public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') ->> 'ok')::boolean,
  'the Owner with fresh reauthentication authorizes release 1');
select ok((public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') ->> 'existing')::boolean,
  'a repeated authorization returns the active one');
reset role;
select is((select count(*)::int from public.publication_authorizations where invalidated_at is null), 1, 'one active authorization');
select ok((select gate_result::text not like '%fin-secret-ref%' and not (gate_result::text like '%billing_holds%')
  from public.publication_authorizations), 'OI-72: the stored gate snapshot carries no financial record detail');
select ok((select gate_result -> 'eligible' = 'true'::jsonb and jsonb_array_length(gate_result -> 'gates') = 8
  from public.publication_authorizations), 'the authorization stores the structured gate result (06 §2)');
select is((select count(*)::int from public.domain_events where event_type = 'publication.authorized'), 1,
  'publication.authorized is emitted');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'authorized'::public.publication_state, 'state: authorized');
select pg_temp.as_admin();
select ok(not exists (select 1 from public.operational_queue() q where q ->> 'queue' = 'ready_for_publication_review'),
  'the publication-review queue clears once authorized');
reset role;

-- ---------------------------------------------------------------------------
-- 3. T-PUB-01 / T-PUB-07: each gate failing alone blocks authorization and deployment start
-- ---------------------------------------------------------------------------
-- G1
select pg_temp.fin('{"agreement_effective": false}');
select is(pg_temp.failing(), 'G1', 'T-PUB-01: G1 fails alone when the agreement is not effective');
select pg_temp.as_admin();
select is(public.start_deployment((select id from public.publication_authorizations where invalidated_at is null)) -> 'failing_gates',
  '[{"gate": "G1", "reason": "agreement_not_effective"}]'::jsonb,
  'T-PUB-07: gates are re-evaluated at Start deployment; a failing G1 blocks it');
reset role;
select is((select invalidated_reason from public.publication_authorizations order by authorized_at limit 1), 'gates_failed_at_start',
  'T-PUB-07: the stale authorization is invalidated');
select pg_temp.as_owner();
select is(public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') ->> 'error',
  'gates_failed', 'T-PUB-01: authorization is rejected with G1 failing');
reset role;
select pg_temp.fin('{"agreement_effective": true}');

create function pg_temp.reauthorize() returns boolean language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_owner();
  v := public.authorize_publication('20000000-0000-4000-8000-0000000000a0',
         (select r.id from public.preview_releases r where r.project_id = '20000000-0000-4000-8000-0000000000a0'
          order by r.release_number desc limit 1));
  reset role;
  return coalesce((v ->> 'ok')::boolean, false);
end;
$$;
-- start_deployment as Admin; returns the sorted failing gates or 'started'.
create function pg_temp.try_start() returns text language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_admin();
  v := public.start_deployment((select a.id from public.publication_authorizations a
         where a.project_id = '20000000-0000-4000-8000-0000000000a0' and a.invalidated_at is null));
  reset role;
  return case when (v ->> 'ok')::boolean then 'started'
    else coalesce((select string_agg(g ->> 'gate', ',' order by g ->> 'gate') from jsonb_array_elements(v -> 'failing_gates') g),
                  v ->> 'error') end;
end;
$$;

-- G2
select ok(pg_temp.reauthorize(), 're-authorized after G1 recovered');
select pg_temp.fin('{"deposit_verified": false}');
select is(pg_temp.failing(), 'G2', 'T-PUB-01: G2 fails alone when the deposit is not verified');
select is(pg_temp.try_start(), 'G2', 'T-PUB-07: a deposit change after authorization blocks deployment');
select ok(not pg_temp.reauthorize(), 'T-PUB-01: authorization is rejected with G2 failing');
select pg_temp.fin('{"deposit_verified": true}');
-- G4
select ok(pg_temp.reauthorize(), 're-authorized');
select pg_temp.fin('{"balance_verified_or_settled": false}');
select is(pg_temp.failing(), 'G4', 'T-PUB-01: G4 fails alone when the balance is not verified');
select is(pg_temp.try_start(), 'G4', 'T-PUB-07: an unverified balance blocks deployment');
select ok(not pg_temp.reauthorize(), 'T-PUB-01: authorization is rejected with G4 failing');
select pg_temp.fin('{"balance_verified_or_settled": true, "balance_settled_by_adjustment": true}');
select is((select g -> 'settled_by_adjustment' from jsonb_array_elements(private.evaluate_publication_gates(
  '20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1') -> 'gates') g where g ->> 'gate' = 'G4'),
  'true'::jsonb, 'G4 discloses a settlement by adjustment (06 §2; OI-27)');
select pg_temp.fin('{"balance_settled_by_adjustment": false}');
-- G5 (a newer failing QA result for the same release)
select ok(pg_temp.reauthorize(), 're-authorized');
insert into public.qa_results (release_id, project_id, checklist_version, items, recorded_by, recorded_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1', pg_temp.qa_items('functional'),
        '00000000-0000-4000-8000-000000000002', now() + interval '1 second');
select is(pg_temp.failing(), 'G5', 'T-PUB-01: G5 fails alone when the latest QA has a failed blocking item');
select is(pg_temp.try_start(), 'G5', 'T-PUB-07: a failing QA result blocks deployment');
select ok(not pg_temp.reauthorize(), 'T-PUB-01: authorization is rejected with G5 failing');
insert into public.qa_results (release_id, project_id, checklist_version, items, recorded_by, recorded_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1', pg_temp.qa_items('performance'),
        '00000000-0000-4000-8000-000000000002', now() + interval '2 seconds');
select is(pg_temp.failing(), 'G5', 'a failed performance item blocks without an exception');
-- T-PUB-11: only the Owner, with fresh reauthentication, may approve a performance exception.
select pg_temp.as_admin();
select is(public.approve_performance_exception('34000000-0000-4000-8000-0000000000a1', '{"lcp_ms": 2900}', 'Hero video') ->> 'error',
  'forbidden', 'T-PUB-11: Admin cannot approve a performance exception');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '10 minutes');
select is(public.approve_performance_exception('34000000-0000-4000-8000-0000000000a1', '{"lcp_ms": 2900}', 'Hero video') ->> 'error',
  'forbidden', 'T-PUB-11: the Owner needs fresh reauthentication for an exception');
reset role;
select pg_temp.as_owner();
select is(public.approve_performance_exception('34000000-0000-4000-8000-0000000000a1', '{}', 'x') ->> 'error', 'invalid_input',
  'T-PUB-11: an exception needs the measured values');
select ok((public.approve_performance_exception('34000000-0000-4000-8000-0000000000a1', '{"lcp_ms": 2900}',
  'Client-supplied hero video; measured LCP 2.9 s') ->> 'ok')::boolean, 'T-PUB-11: the Owner approves a performance exception');
reset role;
select is(pg_temp.failing(), '', 'T-PUB-11: the Owner exception covers the failed performance item');
insert into public.qa_results (release_id, project_id, checklist_version, items, recorded_by, recorded_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1', pg_temp.qa_items('accessibility'),
        '00000000-0000-4000-8000-000000000002', now() + interval '3 seconds');
select is(pg_temp.failing(), 'G5', 'T-PUB-11: the performance exception never covers any other area');
insert into public.qa_results (release_id, project_id, checklist_version, items, recorded_by, recorded_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1', pg_temp.qa_items(),
        '00000000-0000-4000-8000-000000000002', now() + interval '4 seconds');
-- G6
select ok(pg_temp.reauthorize(), 're-authorized');
insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
  registrant_in_client_name, third_party_charges_disclosed, spotlight_registered, checked_at, recorded_by)
values ('20000000-0000-4000-8000-0000000000a0', 'client-a.example.test', true, false, true, true, true, false,
        now() + interval '1 second', '00000000-0000-4000-8000-000000000002');
select is(pg_temp.failing(), 'G6', 'T-PUB-01: G6 fails alone when the domain check fails (TLS)');
select is(pg_temp.try_start(), 'G6', 'T-PUB-07: a failed domain check blocks deployment');
select ok(not pg_temp.reauthorize(), 'T-PUB-01: authorization is rejected with G6 failing');
insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
  registrant_in_client_name, third_party_charges_disclosed, spotlight_registered, checked_at, recorded_by)
values ('20000000-0000-4000-8000-0000000000a0', 'client-a.example.test', true, true, true, true, true, false,
        now() + interval '2 seconds', '00000000-0000-4000-8000-000000000002');
-- G7 (a newer failing security result)
select ok(pg_temp.reauthorize(), 're-authorized');
insert into public.security_check_results (release_id, project_id, checklist_version, items, recorded_by, recorded_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1',
        pg_temp.sec_items('no_exposed_secrets', 'critical'), '00000000-0000-4000-8000-000000000002', now() + interval '1 second');
select is(pg_temp.failing(), 'G7', 'T-PUB-01: G7 fails alone on a critical security failure');
select is(pg_temp.try_start(), 'G7', 'T-PUB-07: a security failure blocks deployment');
select ok(not pg_temp.reauthorize(), 'T-PUB-01: authorization is rejected with G7 failing');
insert into public.security_check_results (release_id, project_id, checklist_version, items, recorded_by, recorded_at)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1',
        pg_temp.sec_items('dependency_scan', 'low'), '00000000-0000-4000-8000-000000000002', now() + interval '2 seconds');
select is(pg_temp.failing(), '', 'a failed low-severity item does not block G7');
-- G8 (billing hold reported by WP-B)
select ok(pg_temp.reauthorize(), 're-authorized');
select pg_temp.fin('{"active_billing_holds": ["dispute_risk_hold"]}');
select is(pg_temp.failing(), 'G8', 'T-PUB-01: G8 fails alone with a billing hold');
select is(pg_temp.try_start(), 'G8', 'T-PUB-07: a hold placed after authorization blocks deployment');
select ok(not pg_temp.reauthorize(), 'T-PUB-01: authorization is rejected with G8 failing');
-- OI-72 redaction of the hold.
select pg_temp.as_admin();
select ok((select g ? 'billing_holds' = false and g -> 'billing_related_hold' = 'true'::jsonb
  from jsonb_array_elements(public.publication_gate_report('20000000-0000-4000-8000-0000000000a0') -> 'result' -> 'gates') g
  where g ->> 'gate' = 'G8'), 'OI-72: Admin sees only "billing-related hold" in the gate report');
select ok(exists (select 1 from public.operational_queue() q where q ->> 'queue' = 'blocked_by_hold'
  and q -> 'detail' ->> 'hold' = 'billing_related_operational_hold'), 'OI-72: Admin sees the derived billing hold state in the queue');
select ok(not exists (select 1 from public.operational_queue() q where q::text like '%dispute_risk_hold%'),
  'OI-72: the Admin queue never names the billing hold type');
reset role;
select pg_temp.as_owner();
select is((select g -> 'billing_holds' from jsonb_array_elements(public.publication_gate_report('20000000-0000-4000-8000-0000000000a0')
  -> 'result' -> 'gates') g where g ->> 'gate' = 'G8'), '["dispute_risk_hold"]'::jsonb, 'the Owner sees the billing hold type');
reset role;
select pg_temp.fin('{"active_billing_holds": []}');
-- G8 (fulfillment hold: T-PUB-17)
select ok(pg_temp.reauthorize(), 're-authorized');
insert into public.approval_holds (id, project_id, release_id, placed_by, reason, outreach_evidence_ids)
values ('35000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-000000000002', 'fixture', array[gen_random_uuid()]);
select is(pg_temp.failing(), 'G8', 'T-PUB-17: an approval hold blocks publication through G8');
select is((select g -> 'fulfillment_holds' || jsonb_build_object('billing', g -> 'billing_holds')
  from jsonb_array_elements(private.evaluate_publication_gates('20000000-0000-4000-8000-0000000000a0',
    '34000000-0000-4000-8000-0000000000a1') -> 'gates') g where g ->> 'gate' = 'G8'),
  '["approval_nonresponsive_hold", {"billing": []}]'::jsonb,
  'T-PUB-17: the gate output identifies a fulfillment hold, not a billing hold');
select is(pg_temp.try_start(), 'G8', 'T-PUB-17: the approval hold blocks deployment');
update public.approval_holds set cleared_at = now(), cleared_by = '00000000-0000-4000-8000-000000000001', clear_reason = 'fixture'
 where id = '35000000-0000-4000-8000-0000000000a1';
select is(pg_temp.failing(), '', 'all gates pass again');

-- ---------------------------------------------------------------------------
-- 4. Fail-closed interfaces and stale evidence (OI-71 revised)
-- ---------------------------------------------------------------------------
select pg_temp.fin('{"implemented": false}');
select is(pg_temp.failing(), 'G1,G2,G4,G8', 'an unimplemented financial interface fails G1, G2, G4, and G8');
select is(pg_temp.reason('G8'), 'financial_interface_not_ready', 'G8 fails closed when the financial interface is not ready');
select pg_temp.fin('{"implemented": true, "contract_version": 0}');
select is(pg_temp.failing(), 'G1,G2,G4,G8', 'an unsupported financial contract version fails closed');
select pg_temp.fin('{"contract_version": 1, "agreement_effective": null}');
select is(pg_temp.failing(), 'G1', 'a missing G1 attribute fails closed');
select pg_temp.fin('{"agreement_effective": true, "active_billing_holds": null}');
select is(pg_temp.failing(), 'G8', 'missing billing-hold evidence fails G8 closed');
select pg_temp.fin('{"active_billing_holds": [], "project_id": "20000000-0000-4000-8000-0000000000b0"}');
select is(pg_temp.failing(), 'G1,G2,G4,G8', 'an interface answering for another project fails closed');
select pg_temp.fin('{"project_id": "20000000-0000-4000-8000-0000000000a0"}');
update private.test_financial_fixture set data = data - 'project_id';
select is(pg_temp.failing(), '', 'all gates pass with a correct interface');
insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
  registrant_in_client_name, third_party_charges_disclosed, spotlight_registered, checked_at, recorded_by)
values ('20000000-0000-4000-8000-0000000000a0', 'client-a.example.test', true, true, true, true, true, false,
        now() - interval '25 hours', '00000000-0000-4000-8000-000000000002');
select is(pg_temp.failing(), 'G6', 'stale evidence fails closed: a domain check older than 24 hours fails G6');
select is(pg_temp.reason('G6'), 'domain_check_stale', 'the stale check is reported as stale');
insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
  registrant_in_client_name, third_party_charges_disclosed, spotlight_registered, checked_at, recorded_by)
values ('20000000-0000-4000-8000-0000000000a0', 'client-a.example.test', true, true, true, true, true, false,
        now(), '00000000-0000-4000-8000-000000000002');

-- ---------------------------------------------------------------------------
-- 5. Deployment records and live verification (T-PUB-06, T-PUB-08, T-PUB-10, T-PUB-18, T-PUB-19)
-- ---------------------------------------------------------------------------
select ok(pg_temp.reauthorize(), 're-authorized for deployment');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.start_deployment((select id from public.publication_authorizations where invalidated_at is null)) ->> 'error',
  'forbidden', 'T-PUB-19: a client cannot start a deployment');
reset role;
select pg_temp.as_admin();
select is(public.start_deployment(gen_random_uuid()) ->> 'error', 'not_found', 'T-PUB-19: start requires an authorization');
select is(public.start_deployment((select id from public.publication_authorizations where invalidated_at is not null limit 1)) ->> 'error',
  'authorization_invalid', 'T-PUB-19: start rejects an invalidated authorization');
reset role;
select is(pg_temp.try_start(), 'started', 'Admin starts the deployment of the authorized release');
select pg_temp.as_admin();
select ok((public.start_deployment((select id from public.publication_authorizations where invalidated_at is null)) ->> 'existing')::boolean,
  'T-PUB-10: a retried start with the same authorization returns the same deployment');
reset role;
select is((select count(*)::int from public.publication_deployments), 1, 'T-PUB-10: exactly one deployment record');
select is((select commit_sha || '|' || target_ref from public.publication_deployments), repeat('1', 40) || '|client-a-site',
  'the deployment records exactly the authorized commit and the isolated target');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'deploying'::public.publication_state, 'state: deploying');
-- T-PUB-18: a failed deployment after verified payment.
select pg_temp.as_admin();
select ok((public.record_deployment_result((select id from public.publication_deployments), false, null, null,
  'Build failed on the provider') ->> 'ok')::boolean, 'staff record a failed deployment');
select is(public.record_deployment_result((select id from public.publication_deployments), true, 'dpl_x', 'https://a.example.test', null) ->> 'error',
  'already_recorded', 'a deployment takes exactly one outcome');
reset role;
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'failed'::public.publication_state,
  'T-PUB-18: the publication is flagged failed for recovery');
select ok((select data -> 'balance_verified_or_settled' = 'true'::jsonb from private.test_financial_fixture),
  'T-PUB-18: the final balance keeps its verified status');
select is((select count(*)::int from public.publication_incidents where kind = 'deployment_failed' and resolved_at is null), 1,
  'T-PUB-18: an incident is opened');
select is((select count(*)::int from public.domain_events where category = 'financial'), 0,
  'T-PUB-18: recovery creates no financial event (no invoice or charge path exists in WP-C)');
-- Recovery: a new authorization and deployment, with no new charge.
select ok(pg_temp.reauthorize(), 'recovery re-runs the authorization through every gate');
select is(pg_temp.try_start(), 'started', 'recovery starts a new deployment');
select pg_temp.as_admin();
select ok((public.record_deployment_result((select id from public.publication_deployments where outcome = 'started'), true,
  'dpl_live_1', 'https://client-a.example.test', null) ->> 'ok')::boolean, 'staff record the successful deployment');
reset role;
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'live_unverified'::public.publication_state,
  'state: live_unverified');
-- Live verification is server-only (staff cannot assert it).
select pg_temp.as_admin();
select throws_ok($$ select public.record_live_verification((select id from public.publication_deployments where outcome = 'succeeded'),
  '00000000-0000-4000-8000-000000000002', repeat('1', 40), true, true, true, true) $$, '42501', null,
  'staff cannot record a live verification result themselves');
reset role;
select pg_temp.as_server();
select is(public.record_live_verification((select id from public.publication_deployments where outcome = 'succeeded'),
  '00000000-0000-4000-8000-0000000000a1', repeat('1', 40), true, true, true, true) ->> 'error', 'forbidden',
  'the verifier records only on behalf of a staff user');
select is(public.record_live_verification((select id from public.publication_deployments where outcome = 'succeeded'),
  '00000000-0000-4000-8000-000000000002', repeat('2', 40), true, true, true, true) ->> 'build_matches', 'false',
  'T-PUB-06: a served build that differs from the authorized release fails verification');
reset role;
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'failed'::public.publication_state,
  'T-PUB-19: a mismatched build fails live verification');
select is((select count(*)::int from public.publication_incidents where kind = 'verification_failed'), 1,
  'T-PUB-08: verification failure opens an incident');
select is((select count(*)::int from public.notification_outbox where notification_type = 'publication.live'), 0,
  'T-PUB-08: verification failure prevents the confirmation notification');
select pg_temp.as_server();
select is(public.record_live_verification((select id from public.publication_deployments where outcome = 'succeeded'),
  '00000000-0000-4000-8000-000000000002', repeat('1', 40), true, true, true, true) ->> 'verified', 'true',
  'T-PUB-06: the served build equals the authorized release');
reset role;
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'live_verified'::public.publication_state, 'state: live_verified');
select is((select count(*)::int from public.notification_outbox where notification_type = 'publication.live'), 1,
  'the publication-live notification is recorded once verified');

-- T-PUB-05 / T-PUB-12: a new release invalidates the pending authorization and needs its own evidence.
select ok(pg_temp.reauthorize(), 'an authorization is pending for release 1');
select pg_temp.as_admin();
select is((public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('3', 40), 'dpl_a2', 'https://preview-a2.example.test', '{}')
  ->> 'release_number')::int, 2, 'release 2 is recorded');
reset role;
select is((select count(*)::int from public.publication_authorizations where invalidated_at is null
  and not exists (select 1 from public.publication_deployments d where d.authorization_id = publication_authorizations.id)), 0,
  'T-PUB-05: the new release invalidates the pending authorization');
select is(pg_temp.failing(), 'G3,G5,G7', 'T-PUB-12: release 2 needs its own approval, QA, and security evidence');

-- Fulfillment interface failure: every fulfillment gate and G8 fail closed.
create or replace function private.project_fulfillment_status(p_project_id uuid) returns private.project_fulfillment_status
language plpgsql stable security definer set search_path = '' as $$ begin raise exception 'unavailable'; end; $$;
select is(pg_temp.failing(), 'G3,G5,G6,G7,G8', 'an unavailable fulfillment interface fails G3, G5, G6, G7, and G8');

select * from finish();
rollback;
