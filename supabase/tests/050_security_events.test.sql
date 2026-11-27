-- Phase 2 remediation D1: security events are written only by the server (secret key),
-- with a verified actor and bounded payloads; no API role can forge audit rows (spec 03 §11,
-- T-ROLE-01, T-AUD-01/02).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(24);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_totp_age interval default null)
returns uuid language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
  v_amr jsonb := jsonb_build_array(jsonb_build_object('method', 'otp',
                   'timestamp', extract(epoch from now() - interval '1 hour')::bigint));
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  -- aal2 also requires a verified factor (private.is_aal2).
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  -- The totp entry is deliberately NOT first: the freshness check must not rely on amr order.
  if p_totp_age is not null then
    v_amr := v_amr || jsonb_build_array(jsonb_build_object('method', 'totp',
               'timestamp', extract(epoch from now() - p_totp_age)::bigint));
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated', 'aal', p_aal, 'amr', v_amr, 'session_id', v_sid)::text, true);
  set local role authenticated;
  return v_sid;
end;
$$;

-- ---- Grants: the trusted boundary is service_role only ----
select ok(not has_function_privilege('authenticated', 'public.record_security_event(uuid, text, jsonb)', 'execute'),
  'D1: authenticated cannot execute public.record_security_event');
select ok(not has_function_privilege('anon', 'public.record_security_event(uuid, text, jsonb)', 'execute'),
  'D1: anon cannot execute public.record_security_event');
select ok(not has_function_privilege('authenticated', 'private.record_security_event(uuid, text, jsonb)', 'execute'),
  'D1: authenticated cannot execute private.record_security_event');
select ok(not has_function_privilege('authenticated', 'private.record_audit_event(text, text, text, uuid, text, jsonb, text)', 'execute'),
  'D1: authenticated cannot execute private.record_audit_event');
select ok(not has_function_privilege('service_role', 'private.record_audit_event(text, text, text, uuid, text, jsonb, text)', 'execute'),
  'D1: service_role cannot execute private.record_audit_event (only definer code and triggers write audit)');
select ok(has_function_privilege('service_role', 'public.record_security_event(uuid, text, jsonb)', 'execute'),
  'D1: service_role can execute public.record_security_event');
select ok(not exists (
  select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.proname in ('record_security_event', 'record_audit_event')
    and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
         or has_function_privilege('public', p.oid, 'execute'))),
  'D1: no overload of an audit-writing function is executable by anon, authenticated, or PUBLIC');
select is((
  select array_agg(p.proname::text order by p.proname::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')),
  array(select unnest(array[
        -- Phase 2
        'accept_invitation', 'auth_context', 'create_invitation', 'revoke_invitation',
        'revoke_membership', 'revoke_staff', 'set_staff_role', 'set_user_status',
        -- WP-C (reviewed in 200_wpc_catalog.test.sql; each re-authorizes inside its definer function)
        'approve_performance_exception', 'approve_preview', 'authorize_publication', 'classify_revision_request',
        'clear_approval_hold', 'correct_intake', 'decide_upload_exception', 'get_intake_state', 'operational_queue',
        'place_approval_hold', 'project_status', 'publication_gate_report', 'record_asset_access',
        'record_deployment_result', 'record_domain_check', 'record_hold_resumption', 'record_outreach',
        'record_preview_draft', 'record_qa_result', 'record_security_result', 'register_client_site_target',
        'release_preview', 'reopen_failed_publication', 'request_revisions', 'request_upload', 'request_upload_exception', 'resolve_incident',
        'retry_object_deletion', 'review_intake', 'save_intake_draft', 'start_deployment', 'submit_intake', 'withdraw_preview',
        -- WP-B (each re-authorizes the caller inside its definer function; none writes audit rows directly)
        'accept_agreement', 'approve_agreement_version', 'authorize_service_termination', 'begin_initial_checkout',
        'clear_billing_hold', 'confirm_cancellation', 'create_agreement_version', 'decide_billing_hold_review',
        'dispute_evidence_package', 'issue_order_summary', 'operational_payment_states', 'place_billing_hold',
        'project_billing_status', 'reconcile_outbound_request', 'record_maintenance_ceased', 'record_refund_decision',
        'record_service_transfer', 'record_services_deactivated', 'record_termination_notice',
        'record_written_cancellation_notice', 'resolve_quarantined_event', 'resolve_reconciliation_mismatch',
        'resolve_stripe_cancellation_exception', 'retry_final_balance_invoice', 'retry_final_balance_stop', 'submit_cancellation_request',
        'withdraw_service_termination',
        -- WP-B, OI-74 and OI-82 (payment authorization, recovery, revocation, holding reconciliation)
        'begin_payment_method_recovery', 'reconcile_holding_reversal', 'record_payment_authorization_revocation',
        'review_authorization_revocation', 'revoke_payment_authorization',
        -- WP-B, AUTH-010 U-2 (OI-93 conflict decisions; Owner, fresh MFA and a live session checked inside)
        'financial_conflict_attempt_status', 'financial_conflict_events', 'record_financial_conflict_decision',
        'retry_financial_conflict_application',
        -- WP-S (AUTH-005; reviewed in 300_wps_sales_*.test.sql; each re-authorizes inside its definer function)
        'assign_sales_representative', 'end_sales_assignment', 'sales_create_customer_project',
        'sales_list_customers', 'sales_project_progress',
        -- DEP-18 (AUTH-018; reviewed in 330_dep18_scope_loader_activation.test.sql; each re-authorizes inside its definer function)
        'activate_package_scope_version', 'load_package_scope_version', 'record_package_scope_approval',
        'withdraw_package_scope_version'
      ]) order by 1)::text[],
  'D1: the public RPC surface for signed-in users is exactly the reviewed list (no audit writers)');

-- ---- Callers that must be refused ----
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select throws_ok($$ select public.record_security_event('00000000-0000-4000-8000-000000000001', 'mfa.reset', '{}') $$,
  '42501', null, 'D1: an authenticated client cannot forge a security event');
select throws_ok($$ insert into public.audit_events (action, category) values ('mfa.reset', 'security') $$,
  '42501', null, 'D1: an authenticated client cannot insert audit rows directly');
-- Even forged claims claiming service_role do not help a session running as authenticated.
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select throws_ok($$ select public.record_security_event(null, 'auth.sign_in_succeeded', '{}') $$,
  '42501', null, 'D1: a service_role claim on the authenticated database role is still refused');
reset role;

select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select throws_ok($$ select public.record_security_event('00000000-0000-4000-8000-000000000001', 'mfa.reset', '{}') $$,
  '42501', null, 'D1: an Owner at aal2 with fresh MFA cannot bypass the server boundary');
reset role;

set local role anon;
select throws_ok($$ select public.record_security_event(null, 'auth.otp_requested', '{}') $$,
  '42501', null, 'D1: an unauthenticated (anon) caller cannot invoke the audit writer');
reset role;

-- Defense in depth: the database role alone is not enough; the JWT must say service_role.
select set_config('request.jwt.claims', '{"role": "authenticated"}', true);
set local role service_role;
select throws_ok($$ select public.record_security_event(null, 'auth.otp_requested', '{}') $$,
  '42501', null, 'D1: the function itself refuses a caller whose JWT role is not service_role');
reset role;

-- ---- The trusted server path ----
create temp table mark as select coalesce(max(id), 0) as last_id from public.audit_events;
grant select on mark to service_role;
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
set local role service_role;
select lives_ok($$ select public.record_security_event('00000000-0000-4000-8000-000000000001', 'mfa.reset',
  '{"target": "00000000-0000-4000-8000-000000000002", "factors": 1}') $$,
  'D1: the server records a security event with a verified actor');
select lives_ok($$ select public.record_security_event(null, 'auth.otp_requested', '{"outcome": "sent"}') $$,
  'D1: the server records an actor-less system event');
select throws_ok($$ select public.record_security_event(null, 'auth.sign_in_failed',
  jsonb_build_object('blob', repeat('x', 3000))) $$, '22023', null,
  'D1: a summary over 2048 bytes is rejected');
select throws_ok($$ select public.record_security_event(null, 'auth.sign_in_failed', '[1, 2, 3]'::jsonb) $$,
  '22023', null, 'D1: a non-object summary is rejected');
select throws_ok($$ select public.record_security_event(null, 'membership.revoked', '{}') $$,
  '22023', null, 'D1: actions outside auth./mfa./session. are rejected');
select throws_ok($$ select public.record_security_event('99999999-9999-4999-8999-999999999999', 'auth.sign_in_succeeded', '{}') $$,
  '22023', null, 'D1: an actor that is not a real user is rejected');
select throws_ok($$ update public.audit_events set summary = '{}' where id > (select last_id from mark) $$,
  '42501', null, 'D1: service_role cannot update security audit rows (append-only)');
reset role;

select is((select actor_user_id::text || '|' || actor_role || '|' || category from public.audit_events
  where id > (select last_id from mark) and action = 'mfa.reset'),
  '00000000-0000-4000-8000-000000000001|owner|security',
  'D1: the actor and role come from the verified actor, not from the caller');
select is((select actor_role from public.audit_events where id > (select last_id from mark) and action = 'auth.otp_requested'),
  'system', 'D1: an actor-less server event is attributed to system');
select throws_ok($$ insert into public.audit_events (action, summary) values ('x.oversized', jsonb_build_object('blob', repeat('x', 9000))) $$,
  '23514', null, 'D1: the table itself rejects summaries over 8192 bytes, even for its owner');

select * from finish();
rollback;
