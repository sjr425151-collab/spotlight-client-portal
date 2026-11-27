-- WP-C (AUTH-015, OI-114): controlled recovery after a failed deployment or a failed live
-- verification (06 §8.1; D1 to D4). Project A, release 1, with every gate passing (the same
-- fixtures as 220: a test-only fixture of the approved WP-B financial interface, so G2 and G4
-- can be flipped; WP-C's real functions for everything else). Two-connection concurrency is in
-- tests/integration/wpc-oi114-recovery-race.test.ts. Synthetic data only.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(51);

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
-- WP-B's approved attributes (OI-71 item 1; 04 §8.1), added only if WP-B has not yet.
do $$
begin
  if not exists (select 1 from pg_attribute where attrelid = 'private.project_financial_status'::regclass
                 and attname = 'agreement_effective' and not attisdropped) then
    alter type private.project_financial_status add attribute agreement_state public.agreement_state,
      add attribute agreement_effective boolean;
  end if;
  if not exists (select 1 from pg_attribute where attrelid = 'private.project_financial_status'::regclass
                 and attname = 'payment_authorization_ready' and not attisdropped) then
    alter type private.project_financial_status add attribute payment_authorization_ready boolean,
      add attribute payment_authorization_state text;
  end if;
end;
$$;
create or replace function private.project_financial_status(p_project_id uuid) returns private.project_financial_status
language sql stable security definer set search_path = '' as $$
  select jsonb_populate_record(null::private.project_financial_status,
    jsonb_build_object('project_id', p_project_id, 'contract_version', 1, 'implemented', false,
      'deposit_state', 'not_started', 'deposit_verified', false, 'final_balance_state', 'not_due',
      'balance_verified_or_settled', false, 'balance_settled_by_adjustment', false,
      'payment_authorization_ready', false, 'active_billing_holds', '[]'::jsonb, 'evidence', '{}'::jsonb)
    || coalesce((select f.data from private.test_financial_fixture f where f.project_id = p_project_id), '{}'::jsonb));
$$;
create function pg_temp.fin(p jsonb) returns void language sql as $$
  update private.test_financial_fixture set data = data || p where project_id = '20000000-0000-4000-8000-0000000000a0';
$$;
insert into private.test_financial_fixture values ('20000000-0000-4000-8000-0000000000a0',
  '{"implemented": true, "agreement_state": "effective", "agreement_effective": true, "deposit_state": "verified",
    "deposit_verified": true, "payment_authorization_ready": true, "final_balance_state": "verified", "balance_verified_or_settled": true,
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


select pg_temp.as_admin();
select public.record_qa_result('34000000-0000-4000-8000-0000000000a1', 'v1', pg_temp.qa_items()) ->> 'ok';
select public.record_security_result('34000000-0000-4000-8000-0000000000a1', 'v1', pg_temp.sec_items()) ->> 'ok';
select public.record_domain_check('20000000-0000-4000-8000-0000000000a0', 'client-a.example.test', true, true, true, true, true,
  true, current_date - 30, current_date + 335, null) ->> 'ok';
reset role;
select pg_temp.as_owner();
select public.register_client_site_target('20000000-0000-4000-8000-0000000000a0', 'client-a-site') ->> 'ok';
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select public.approve_preview('34000000-0000-4000-8000-0000000000a1') ->> 'ok';
reset role;

-- Helpers for this file.
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k; $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;
create function pg_temp.authorize() returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_owner();
  v := public.authorize_publication('20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1');
  reset role;
  return v;
end;
$$;
create function pg_temp.start(p_auth uuid) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_admin();
  v := public.start_deployment(p_auth);
  reset role;
  return v;
end;
$$;
create function pg_temp.record(p_dep uuid, p_ok boolean, p_url text default 'https://client-a.example.test')
returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_admin();
  v := public.record_deployment_result(p_dep, p_ok, case when p_ok then 'dpl_' || left(replace(p_dep::text, '-', ''), 12) end,
    case when p_ok then p_url end, case when p_ok then null else 'Provider build failed' end);
  reset role;
  return v;
end;
$$;
create function pg_temp.verify(p_dep uuid, p_build text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_server();
  v := public.record_live_verification(p_dep, '00000000-0000-4000-8000-000000000002', p_build, true, true, true, true);
  reset role;
  return v;
end;
$$;
-- The Owner's recovery, with a configurable session (default: fresh aal2).
create function pg_temp.reopen(p_dep uuid, p_reason text default 'Redeploying after a failed publication',
  p_uid uuid default '00000000-0000-4000-8000-000000000001', p_aal text default 'aal2',
  p_totp_age interval default interval '1 minute') returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as(p_uid, p_aal, p_totp_age);
  v := public.reopen_failed_publication(p_dep, p_reason);
  reset role;
  return v;
end;
$$;
create function pg_temp.audits(p_action text) returns integer language sql as $$
  select count(*)::int from public.audit_events where action = p_action and project_id = '20000000-0000-4000-8000-0000000000a0';
$$;
create function pg_temp.side_effects() returns text language sql as $$
  -- Project A only, so committed rows of other projects (other test files) never interfere.
  select (select count(*) from public.publication_authorizations where project_id = '20000000-0000-4000-8000-0000000000a0')
    || '/' || (select count(*) from public.publication_deployments where project_id = '20000000-0000-4000-8000-0000000000a0')
    || '/' || (select count(*) from public.deployment_verifications where project_id = '20000000-0000-4000-8000-0000000000a0')
    || '/' || (select count(*) from public.notification_outbox where project_id = '20000000-0000-4000-8000-0000000000a0')
    || '/' || (select count(*) from public.domain_events where project_id = '20000000-0000-4000-8000-0000000000a0');
$$;

-- ---------------------------------------------------------------------------
-- 1. A failed deployment: D1, the Owner-only recovery, D2, D3 (two steps), G2 and G4
-- ---------------------------------------------------------------------------
select is(pg_temp.failing(), '', 'every gate G1-G8 passes for release 1');
insert into ids select 'a1', pg_temp.authorize() ->> 'authorization_id';
insert into ids select 'd1', pg_temp.start(pg_temp.id('a1')) ->> 'deployment_id';
select is(pg_temp.reopen(pg_temp.id('d1')) -> 'detail', '"deployment_in_progress"'::jsonb,
  'a started deployment cannot be recovered');
select ok((pg_temp.record(pg_temp.id('d1'), false) ->> 'ok')::boolean, 'staff record the failed deployment');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'failed'::public.publication_state, 'state: failed');
select is(pg_temp.authorize() ->> 'error', 'recovery_required',
  'D1: the same release cannot be re-authorized while its used authorization is active');
select ok(pg_temp.audits('publication.authorization_rejected') = 1
  and exists (select 1 from public.audit_events where action = 'publication.authorization_rejected'
               and summary ->> 'reason' = 'recovery_required'),
  'D1: the refusal is audited (recovery_required)');
select is((select count(*)::int from public.publication_authorizations where project_id = '20000000-0000-4000-8000-0000000000a0'), 1,
  'D1: no new authorization was issued');

-- Denials.
select is(pg_temp.reopen(pg_temp.id('d1'), p_uid => '00000000-0000-4000-8000-000000000002') ->> 'error', 'forbidden',
  'the Admin cannot recover a publication (Owner only)');
select is(pg_temp.reopen(pg_temp.id('d1'), p_uid => '00000000-0000-4000-8000-0000000000a1', p_aal => 'aal1',
  p_totp_age => null) ->> 'error', 'forbidden', 'a client cannot recover a publication');
select is(pg_temp.reopen(pg_temp.id('d1'), p_aal => 'aal1', p_totp_age => null) ->> 'error', 'forbidden',
  'the Owner at aal1 cannot recover a publication');
-- OI-120: private.is_owner() is NULL for a non-staff caller; the guard must still refuse a
-- client, or a revoked former staff member, at aal2 with fresh MFA and a live session.
select is(pg_temp.reopen(pg_temp.id('d1'), p_uid => '00000000-0000-4000-8000-0000000000a1') ->> 'error', 'forbidden',
  'OI-120: a client at aal2 with fresh MFA and a live session cannot recover a publication');
update public.staff_roles set status = 'revoked' where user_id = '00000000-0000-4000-8000-000000000002';
select is(pg_temp.reopen(pg_temp.id('d1'), p_uid => '00000000-0000-4000-8000-000000000002') ->> 'error', 'forbidden',
  'OI-120: a revoked former staff member at aal2 with fresh MFA cannot recover a publication');
update public.staff_roles set status = 'active' where user_id = '00000000-0000-4000-8000-000000000002';
select is(pg_temp.reopen(pg_temp.id('d1'), p_totp_age => interval '2 hours') ->> 'error', 'reauthentication_required',
  'the Owner needs fresh reauthentication');
select is(pg_temp.audits('publication.recovery_rejected'), 2,
  'the stale-MFA refusal is audited (with the in-progress refusal above)');
select is(pg_temp.reopen(pg_temp.id('d1'), p_reason => '  ') ->> 'error', 'reason_required', 'a reason is required');
select is(pg_temp.reopen(gen_random_uuid()) ->> 'error', 'not_found', 'an unknown deployment is not found');
select is((select invalidated_at from public.publication_authorizations where id = pg_temp.id('a1')), null,
  'no refused call closed the authorization');

-- A gate failure after the failed deployment closes its authorization (gates_failed, the
-- existing 06 §3 rule); that deployment is then not recoverable.
select pg_temp.fin('{"deposit_verified": false}');
select is(pg_temp.authorize() ->> 'error', 'gates_failed', 'a failing gate refuses the re-authorization');
select is(pg_temp.reopen(pg_temp.id('d1')) -> 'detail', '"authorization_closed"'::jsonb,
  'a deployment whose authorization is already closed cannot be recovered');
select pg_temp.fin('{"deposit_verified": true}');
-- Setup: with the gates passing again, a new authorization and a second failed deployment of
-- release 1. The rest of this section recovers that deployment.
update ids set v = (select pg_temp.authorize() ->> 'authorization_id') where k = 'a1';
update ids set v = (select pg_temp.start(pg_temp.id('a1')) ->> 'deployment_id') where k = 'd1';
select pg_temp.record(pg_temp.id('d1'), false) ->> 'ok';

-- The recovery.
insert into ids values ('before', pg_temp.side_effects());
select ok((select (r ->> 'ok')::boolean and not (r ->> 'existing')::boolean and r ->> 'authorization_id' = pg_temp.id('a1')::text
           from (select pg_temp.reopen(pg_temp.id('d1'), 'Provider build failed; redeploying the same release') r) x),
  'D2: the Owner recovers the failed deployment');
select is((select invalidated_reason from public.publication_authorizations where id = pg_temp.id('a1')),
  'failed_publication_recovery', 'the failed deployment''s authorization is closed by the recovery');
select ok(exists (select 1 from public.audit_events where action = 'publication.recovery_opened'
            and target_id = pg_temp.id('d1')::text and actor_user_id = '00000000-0000-4000-8000-000000000001'
            and reason = 'Provider build failed; redeploying the same release'
            and summary ->> 'failure' = 'deployment_failed' and summary ->> 'authorization_id' = pg_temp.id('a1')::text
            and jsonb_array_length(summary -> 'incident_ids') = 1)
  and exists (select 1 from public.audit_events where action = 'publication.authorization_invalidated'
               and target_id = pg_temp.id('a1')::text and summary ->> 'reason' = 'failed_publication_recovery'),
  'the recovery is audited with the reason, the failure and the open incident');
select is(pg_temp.side_effects(), (select v from ids where k = 'before'),
  'D3: the recovery issues no authorization, deployment, verification, notification or domain event');
insert into ids select 'r1b', pg_temp.reopen(pg_temp.id('d1'))::text;
select ok(((select v from ids where k = 'r1b')::jsonb ->> 'existing')::boolean and pg_temp.audits('publication.recovery_opened') = 1,
  'a repeated recovery returns the existing recovery and writes nothing');
select is((select count(*)::int from public.publication_incidents where resolved_at is null and deployment_id = pg_temp.id('d1')), 1,
  'the incident stays open until the Owner resolves it');

-- The normal flow re-runs every gate (D3), including G2 and G4.
select pg_temp.fin('{"deposit_verified": false}');
select is((select string_agg(g ->> 'gate', ',') from jsonb_array_elements(pg_temp.authorize() -> 'failing_gates') g), 'G2',
  'after recovery, authorization re-evaluates G2');
select pg_temp.fin('{"deposit_verified": true, "balance_verified_or_settled": false}');
select is((select string_agg(g ->> 'gate', ',') from jsonb_array_elements(pg_temp.authorize() -> 'failing_gates') g), 'G4',
  'after recovery, authorization re-evaluates G4');
select pg_temp.fin('{"balance_verified_or_settled": true}');
insert into ids select 'a2', pg_temp.authorize() ->> 'authorization_id';
select ok((select release_id = '34000000-0000-4000-8000-0000000000a1' and invalidated_at is null
           from public.publication_authorizations where id = pg_temp.id('a2')) and pg_temp.id('a2') <> pg_temp.id('a1'),
  'a new authorization is issued for the same release identity');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'authorized'::public.publication_state,
  'state: authorized');
insert into ids select 'd2', pg_temp.start(pg_temp.id('a2')) ->> 'deployment_id';
select ok((select seq > (select seq from public.publication_deployments where id = pg_temp.id('d1'))
             and commit_sha = repeat('1', 40) and outcome = 'started'
           from public.publication_deployments where id = pg_temp.id('d2')),
  'start_deployment re-evaluates the gates and records a new deployment of the same commit');

-- ---------------------------------------------------------------------------
-- 2. A failed live verification; a late verification never counts; D4
-- ---------------------------------------------------------------------------
select ok((pg_temp.record(pg_temp.id('d2'), true) ->> 'ok')::boolean, 'staff record the successful deployment');
select is(pg_temp.reopen(pg_temp.id('d2')) -> 'detail', '"live_unverified"'::jsonb,
  'an unverified deployment cannot be recovered (verify it first)');
select is(pg_temp.verify(pg_temp.id('d2'), repeat('2', 40)) ->> 'verified', 'false', 'a mismatched build fails live verification');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'failed'::public.publication_state, 'state: failed');
select is(pg_temp.reopen(pg_temp.id('d1')) ->> 'existing', 'true',
  'the earlier, already-recovered deployment only returns its existing recovery');
insert into ids select 'r2', pg_temp.reopen(pg_temp.id('d2'))::text;
select ok(((select v from ids where k = 'r2')::jsonb ->> 'ok')::boolean
  and exists (select 1 from public.audit_events where action = 'publication.recovery_opened'
               and target_id = pg_temp.id('d2')::text and summary ->> 'failure' = 'verification_failed'),
  'D2: the Owner recovers the failed live verification');
insert into ids values ('verifications', (select count(*) from public.deployment_verifications where project_id = '20000000-0000-4000-8000-0000000000a0')::text);
select is(pg_temp.verify(pg_temp.id('d2'), repeat('1', 40)) ->> 'error', 'deployment_closed',
  'a late verification of the recovered deployment is refused');
select ok((select count(*) from public.deployment_verifications where project_id = '20000000-0000-4000-8000-0000000000a0')::text = (select v from ids where k = 'verifications')
  and (select count(*) from public.notification_outbox where notification_type = 'publication.live' and project_id = '20000000-0000-4000-8000-0000000000a0') = 0,
  'the late verification records nothing and announces nothing');
insert into ids select 'a3', pg_temp.authorize() ->> 'authorization_id';
insert into ids select 'd3', pg_temp.start(pg_temp.id('a3')) ->> 'deployment_id';
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'deploying'::public.publication_state,
  'the new deployment does not inherit an earlier verification');
insert into ids select 'rec3', pg_temp.record(pg_temp.id('d3'), true)::text;
select ok(((select v from ids where k = 'rec3')::jsonb ->> 'ok')::boolean
  and private.publication_state_of('20000000-0000-4000-8000-0000000000a0') = 'live_unverified',
  'the new deployment needs its own live verification');
select is(pg_temp.verify(pg_temp.id('d3'), repeat('1', 40)) ->> 'verified', 'true', 'the new deployment verifies');
select is(private.publication_state_of('20000000-0000-4000-8000-0000000000a0'), 'live_verified'::public.publication_state,
  'state: live_verified');
select is(pg_temp.reopen(pg_temp.id('d3')) -> 'detail', '"live_verified"'::jsonb,
  'D4: a release whose latest verification passed cannot be recovered');
select is(pg_temp.authorize() ->> 'error', 'recovery_required', 'D4: and it cannot be re-authorized or redeployed');

-- ---------------------------------------------------------------------------
-- 3. Only the current release; isolation; catalog
-- ---------------------------------------------------------------------------
select is(pg_temp.verify(pg_temp.id('d3'), null) ->> 'verified', 'false', 'a later verification fails');
select pg_temp.as_admin();
select public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('3', 40), 'dpl_a2', 'https://preview-a2.example.test', '{}') ->> 'ok';
reset role;
select is(pg_temp.reopen(pg_temp.id('d3')) -> 'detail', '"release_not_current"'::jsonb,
  'a superseded release cannot be recovered');
select is((select invalidated_at from public.publication_authorizations where id = pg_temp.id('a3')), null,
  'the refused recovery left the authorization unchanged');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.audit_events where project_id = '20000000-0000-4000-8000-0000000000a0'), 0,
  'client B sees no Project A audit event');
reset role;
select ok(not exists (select 1 from public.audit_events a where a.action like 'publication.recovery%'
                       and a.target_id in (select d.id::text from public.publication_deployments d
                                            where d.project_id = '20000000-0000-4000-8000-0000000000a0')
                       and a.project_id is distinct from '20000000-0000-4000-8000-0000000000a0'),
  'every recovery audit of a Project A deployment belongs to Project A');
select ok(has_function_privilege('authenticated', 'public.reopen_failed_publication(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'public.reopen_failed_publication(uuid, text)', 'execute')
  and not has_function_privilege('service_role', 'public.reopen_failed_publication(uuid, text)', 'execute')
  and not has_function_privilege('anon', 'private.reopen_failed_publication(uuid, text)', 'execute')
  and not has_function_privilege('service_role', 'private.reopen_failed_publication(uuid, text)', 'execute'),
  'only authenticated callers reach the recovery, which re-authorizes the Owner inside');
select ok((select prosecdef and proconfig = array['search_path=""'] from pg_proc
           where oid = 'private.reopen_failed_publication(uuid, text)'::regprocedure),
  'the recovery is security definer with an empty search_path');

select * from finish();
rollback;
