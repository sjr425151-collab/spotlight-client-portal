-- WP-0 shared contracts (spec 01 §7; 05 §2; 06 §2; 07 §2-§3; 03 §8-§11).
-- Covers: state-domain types, the typed domain-event registry, append-only domain events,
-- the notification outbox state machine, gate-interface contracts, privileges, and
-- cross-tenant isolation for both new tables (T-TEN-01 to T-TEN-03 pattern).
-- Seed: client A (…a1) is a member of Project A only; client B (…b1) of Project B only;
-- …01 is the Owner and …02 an Admin.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(63);

-- Impersonation helper: real session row + JWT claims, then SET LOCAL ROLE (as 010).
create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1')
returns void language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated', 'aal', p_aal, 'session_id', v_sid)::text, true);
  set local role authenticated;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. State-domain types (05 §2)
-- ---------------------------------------------------------------------------
select enum_has_labels('public', 'state_domain',
  array['agreement', 'payment', 'subscription', 'fulfillment', 'approval', 'deployment'],
  'state_domain lists the six separately tracked domains (01 §7)');
select enum_has_labels('public', 'agreement_state',
  array['not_presented', 'presented', 'accepted_pending_payment', 'effective', 'superseded', 'reacceptance_required', 'expired'],
  'agreement_state matches 05 §2');
select enum_has_labels('public', 'deposit_state',
  array['not_started', 'pending', 'verified', 'failed', 'refunded', 'disputed'],
  'deposit_state matches 05 §2');
select enum_has_labels('public', 'final_balance_state',
  array['not_due', 'due', 'pending', 'verified', 'failed', 'refunded', 'disputed', 'settled_by_adjustment'],
  'final_balance_state matches 05 §2');
select enum_has_labels('public', 'subscription_status',
  array['incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'canceled', 'unpaid', 'paused'],
  'subscription_status mirrors the Stripe subscription statuses');
select enum_has_labels('public', 'service_termination_state',
  array['none', 'under_owner_review', 'termination_authorized', 'effective', 'maintenance_ceased', 'offboarded', 'transferred', 'withdrawn'],
  'service_termination_state matches 05 §2');
select enum_has_labels('public', 'intake_state',
  array['locked', 'open', 'submitted', 'accepted_by_staff', 'changes_requested'], 'intake_state matches 05 §2');
select enum_has_labels('public', 'development_state',
  array['not_started', 'in_progress', 'ready_for_preview', 'paused'], 'development_state matches 05 §2');
select enum_has_labels('public', 'release_approval_state',
  array['released', 'approved', 'superseded', 'withdrawn'], 'release_approval_state matches 05 §2');
select enum_has_labels('public', 'publication_state',
  array['not_eligible', 'eligible', 'authorized', 'deploying', 'live_unverified', 'live_verified', 'failed', 'rolled_back'],
  'publication_state matches 05 §2');
select enum_has_labels('public', 'hold_type',
  array['maintenance_payment_hold', 'approval_nonresponsive_hold', 'dispute_risk_hold', 'owner_manual_hold'],
  'hold_type matches 04 §14');
select enum_has_labels('public', 'notification_status',
  array['recorded', 'pending', 'sending', 'sent', 'failed', 'dead'], 'notification_status matches 07 §2');

-- ---------------------------------------------------------------------------
-- 2. Privileges: nobody calls the write or gate functions directly
-- ---------------------------------------------------------------------------
select ok(
  not has_function_privilege('authenticated', 'private.emit_domain_event(text, uuid, text, text, jsonb, text)', 'execute')
  and not has_function_privilege('service_role', 'private.emit_domain_event(text, uuid, text, text, jsonb, text)', 'execute')
  and not has_function_privilege('anon', 'private.emit_domain_event(text, uuid, text, text, jsonb, text)', 'execute'),
  'emit_domain_event is not executable by anon, authenticated, or service_role');
select ok(
  not has_function_privilege('authenticated', 'private.enqueue_notification(text, text, text, integer, uuid, bigint, uuid[], public.notification_recipient_role[], jsonb, text)', 'execute')
  and not has_function_privilege('service_role', 'private.enqueue_notification(text, text, text, integer, uuid, bigint, uuid[], public.notification_recipient_role[], jsonb, text)', 'execute'),
  'enqueue_notification is not executable by authenticated or service_role');
select ok(
  not has_function_privilege('authenticated', 'private.project_financial_status(uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.project_financial_status(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.project_fulfillment_status(uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.project_fulfillment_status(uuid)', 'execute'),
  'gate interfaces are not executable by authenticated or service_role');
select ok(
  not has_table_privilege('service_role', 'public.domain_events', 'insert')
  and not has_table_privilege('service_role', 'public.domain_events', 'update')
  and not has_table_privilege('service_role', 'public.domain_events', 'delete')
  and not has_table_privilege('service_role', 'public.notification_outbox', 'insert')
  and not has_table_privilege('service_role', 'public.notification_outbox', 'update')
  and not has_table_privilege('service_role', 'public.notification_outbox', 'delete'),
  'service_role cannot write domain_events or notification_outbox directly');
select ok(
  not has_table_privilege('authenticated', 'public.domain_events', 'insert')
  and not has_table_privilege('authenticated', 'public.domain_events', 'update')
  and not has_table_privilege('authenticated', 'public.notification_outbox', 'insert')
  and not has_table_privilege('authenticated', 'public.notification_outbox', 'update'),
  'authenticated cannot write domain_events or notification_outbox directly');
select ok(
  not has_table_privilege('authenticated', 'private.domain_event_types', 'select')
  and not has_table_privilege('service_role', 'private.domain_event_types', 'insert'),
  'the event-type registry is not readable or writable by API roles');

-- ---------------------------------------------------------------------------
-- 3. Domain events: typed, bounded, idempotent, append-only (run as the migration role)
-- ---------------------------------------------------------------------------
select throws_ok(
  $$ select private.emit_domain_event('payment.made_up', '20000000-0000-4000-8000-0000000000a0', 'project', 'x') $$,
  '23503', null, 'an unregistered event type is rejected');
select throws_ok(
  $$ select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000a0', 'release', 'r1',
       '{"approval": {"session_token": "abc"}}') $$,
  '22023', null, 'a payload with a secret-like key at any depth is rejected');
select throws_ok(
  $$ select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000a0', 'release', 'r1',
       jsonb_build_object('blob', repeat('x', 9000))) $$,
  '22023', null, 'an oversized payload is rejected');
select throws_ok(
  $$ select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000a0', 'release', 'r1', '[1, 2]') $$,
  '22023', null, 'a non-object payload is rejected');
select lives_ok(
  $$ select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000a0', 'release', 'r1',
       '{"company": "Synthetic A", "release_number": 3}') $$,
  'ordinary keys such as company are accepted');

select is(
  private.emit_domain_event('payment.deposit_verified', '20000000-0000-4000-8000-0000000000a0', 'checkout_session', 'cs_test_1', '{}', 'evt_test_1'),
  private.emit_domain_event('payment.deposit_verified', '20000000-0000-4000-8000-0000000000a0', 'checkout_session', 'cs_test_1', '{}', 'evt_test_1'),
  'T-PAY-05 pattern: a replayed emission with the same dedupe key returns the original event');
select is((select count(*)::int from public.domain_events where dedupe_key = 'evt_test_1'), 1,
  'T-PAY-05 pattern: the replay wrote exactly one event');
select throws_ok(
  $$ select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000a0', 'release', 'r9', '{}', 'evt_test_1') $$,
  '23505', null, 'reusing a dedupe key for a different event is rejected');

select is(
  (select row(domain, category, schema_version)::text from public.domain_events where dedupe_key = 'evt_test_1'),
  '(payment,financial,1)', 'events take domain, category, and version from the registry (payment is financial)');
select is(
  (select category from public.domain_events where event_type = 'release.approved' limit 1),
  'general', 'approval events are non-financial');

select throws_ok($$ update public.domain_events set subject_id = 'tampered' $$, '42501', null,
  'domain_events rejects UPDATE, even for the table owner');
select throws_ok($$ delete from public.domain_events $$, '42501', null,
  'domain_events rejects DELETE, even for the table owner');
select throws_ok($$ truncate public.domain_events cascade $$, '42501', null,
  'domain_events rejects TRUNCATE');

-- Same-transaction guarantee: an event written by a state change that rolls back disappears.
savepoint before_failed_change;
select private.emit_domain_event('publication.authorized', '20000000-0000-4000-8000-0000000000b0', 'release', 'rb1', '{}', 'rollback_probe');
rollback to savepoint before_failed_change;
select is((select count(*)::int from public.domain_events where dedupe_key = 'rollback_probe'), 0,
  'an event emitted in a rolled-back transaction is not persisted');

-- Project B events for the isolation checks below.
select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000b0', 'release', 'rb1', '{}', 'b_release');
select private.emit_domain_event('payment.deposit_verified', '20000000-0000-4000-8000-0000000000b0', 'checkout_session', 'cs_b', '{}', 'b_deposit');

-- ---------------------------------------------------------------------------
-- 4. Notification outbox (07 §2-§3)
-- ---------------------------------------------------------------------------
select is(
  private.enqueue_notification('preview.released', 'preview.released:r1:1', 'preview_released', 1,
    '20000000-0000-4000-8000-0000000000a0', null, array['00000000-0000-4000-8000-0000000000a1']::uuid[]),
  private.enqueue_notification('preview.released', 'preview.released:r1:1', 'preview_released', 1,
    '20000000-0000-4000-8000-0000000000a0', null, array['00000000-0000-4000-8000-0000000000a1']::uuid[]),
  'a duplicate enqueue with the same idempotency key is a no-op returning the same row');
select is((select count(*)::int from public.notification_outbox where idempotency_key = 'preview.released:r1:1'), 1,
  'the duplicate enqueue wrote exactly one row');
select is((select status::text from public.notification_outbox where idempotency_key = 'preview.released:r1:1'), 'recorded',
  'R1 rows are recorded and never sent');
select throws_ok(
  $$ update public.notification_outbox set status = 'pending' where idempotency_key = 'preview.released:r1:1' $$,
  '23514', null, 'a recorded row can never move into delivery');
select throws_ok(
  $$ select private.enqueue_notification('preview.released', 'no-recipient', 'preview_released', 1) $$,
  '23514', null, 'a notification needs at least one recipient');
select throws_ok(
  $$ select private.enqueue_notification('preview.released', 'secret-payload', 'preview_released', 1, null, null,
       '{}', array['owner']::public.notification_recipient_role[], '{"magic_link_token": "x"}') $$,
  '23514', null, 'a payload reference with a secret-like key is rejected');

-- Delivery state machine on an R2-style row (inserted directly by the migration role).
insert into public.notification_outbox (notification_type, recipient_roles, template_key, template_version,
  idempotency_key, status)
values ('hold.placed', array['owner']::public.notification_recipient_role[], 'hold_placed', 1, 'sm-probe', 'pending');
select throws_ok($$ update public.notification_outbox set status = 'sent' where idempotency_key = 'sm-probe' $$,
  '23514', null, 'pending cannot jump to sent');
select lives_ok($$ update public.notification_outbox set status = 'sending', attempt_count = 1 where idempotency_key = 'sm-probe' $$,
  'pending -> sending is allowed');
select lives_ok($$ update public.notification_outbox set status = 'failed', last_error = 'synthetic' where idempotency_key = 'sm-probe' $$,
  'sending -> failed is allowed');
select lives_ok($$ update public.notification_outbox set status = 'dead' where idempotency_key = 'sm-probe' $$,
  'failed -> dead is allowed');
select throws_ok($$ update public.notification_outbox set status = 'sending' where idempotency_key = 'sm-probe' $$,
  '23514', null, 'dead is terminal');
select throws_ok($$ update public.notification_outbox set template_key = 'other' where idempotency_key = 'preview.released:r1:1' $$,
  '42501', null, 'notification content is immutable');
select throws_ok($$ delete from public.notification_outbox where idempotency_key = 'sm-probe' $$,
  '42501', null, 'notification rows are not deleted');

-- Project B notifications for the isolation checks below.
select private.enqueue_notification('preview.released', 'b:preview', 'preview_released', 1,
  '20000000-0000-4000-8000-0000000000b0', null, array['00000000-0000-4000-8000-0000000000b1']::uuid[]);
select private.enqueue_notification('payment.deposit_verified', 'b:deposit', 'deposit_verified', 1,
  '20000000-0000-4000-8000-0000000000b0', null, array['00000000-0000-4000-8000-0000000000b1']::uuid[],
  '{}', '{}', 'financial');

-- ---------------------------------------------------------------------------
-- 5. Gate interfaces (06 §2): typed contracts, fail-closed until implemented
-- ---------------------------------------------------------------------------
select is(
  (select row(s.implemented, s.deposit_verified, s.balance_verified_or_settled, cardinality(s.active_billing_holds))::text
   from private.project_financial_status('20000000-0000-4000-8000-0000000000a0') s),
  '(t,f,f,0)', 'project_financial_status is implemented by WP-B and satisfies no gate input for a project with no payment');
-- WP-C implemented project_fulfillment_status (contract v2); with no fulfillment records it
-- satisfies no gate input. Its behaviour is tested in 220_wpc_gates.test.sql.
select is(
  (select row(s.implemented, s.contract_version, s.intake_accepted, s.current_release_approved, s.qa_passed,
              s.security_passed, s.domain_ready)::text
   from private.project_fulfillment_status('20000000-0000-4000-8000-0000000000a0') s),
  '(t,2,f,f,f,f,f)', 'project_fulfillment_status (WP-C, v2) satisfies no gate input without fulfillment records');
select is(
  (select array_agg(a.attname::text order by a.attnum) from pg_attribute a
   where a.attrelid = 'private.project_financial_status'::regclass and a.attnum > 0 and not a.attisdropped),
  array['project_id', 'contract_version', 'implemented', 'deposit_state', 'deposit_verified', 'final_balance_state',
        'balance_verified_or_settled', 'balance_settled_by_adjustment', 'active_billing_holds', 'evidence',
        -- WP-B, additive (OI-71 item 1: G1)
        'agreement_state', 'agreement_effective',
        -- WP-B, additive (OI-74: WP-C's intake precondition)
        'payment_authorization_ready', 'payment_authorization_state'],
  'the financial status contract has the agreed attributes in order');
select is(
  (select array_agg(a.attname::text order by a.attnum) from pg_attribute a
   where a.attrelid = 'private.project_fulfillment_status'::regclass and a.attnum > 0 and not a.attisdropped),
  array['project_id', 'contract_version', 'implemented', 'intake_state', 'intake_accepted', 'current_release_id',
        'current_release_approved', 'current_release_approval_id', 'qa_passed', 'security_passed',
        'active_fulfillment_holds', 'evidence',
        -- WP-C additions (OI-71 item 2), additive:
        'domain_ready', 'domain_check_id', 'domain_checked_at'],
  'the fulfillment status contract has the agreed attributes in order');

-- ---------------------------------------------------------------------------
-- 6. Cross-tenant isolation and role access (03 §8-§9; T-TEN-01 to T-TEN-03 pattern)
-- ---------------------------------------------------------------------------
-- Client A: sees nothing, including events and notifications about their own project.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from public.domain_events), 0, 'client A cannot read any domain event');
select is((select count(*)::int from public.domain_events where project_id = '20000000-0000-4000-8000-0000000000b0'), 0,
  'client A cannot read Project B domain events');
select is((select count(*)::int from public.notification_outbox), 0, 'client A cannot read any outbox row');
select throws_ok(
  $$ insert into public.domain_events (event_type, schema_version, domain, category, subject_type, subject_id)
     values ('release.approved', 1, 'approval', 'general', 'release', 'forged') $$,
  '42501', null, 'client A cannot insert a domain event');
select throws_ok(
  $$ insert into public.notification_outbox (notification_type, recipient_roles, template_key, template_version, idempotency_key)
     values ('preview.released', array['client']::public.notification_recipient_role[], 't', 1, 'forged') $$,
  '42501', null, 'client A cannot insert an outbox row');
select throws_ok(
  $$ select private.emit_domain_event('release.approved', '20000000-0000-4000-8000-0000000000a0', 'release', 'forged') $$,
  '42501', null, 'client A cannot call emit_domain_event');
select throws_ok(
  $$ select private.project_financial_status('20000000-0000-4000-8000-0000000000b0') $$,
  '42501', null, 'client A cannot call a gate interface');
reset role;

-- Client B: same isolation from Project A and from all internal records.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.domain_events), 0, 'client B cannot read any domain event');
select is((select count(*)::int from public.notification_outbox), 0, 'client B cannot read any outbox row');
reset role;

-- Admin at aal1: nothing (staff need aal2 and a live session, 03 §7).
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select is((select count(*)::int from public.domain_events), 0, 'Admin at aal1 cannot read domain events');
reset role;

-- Admin at aal2: non-financial rows only.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((select count(*) from public.domain_events where category = 'general') > 0
  and (select count(*) from public.domain_events where category = 'financial') = 0,
  'Admin at aal2 reads non-financial domain events and no financial ones');
select ok((select count(*) from public.notification_outbox where category = 'general') > 0
  and (select count(*) from public.notification_outbox where category = 'financial') = 0,
  'Admin at aal2 reads non-financial outbox rows and no financial ones');
reset role;

-- Owner at aal2: everything.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select ok((select count(*) from public.domain_events where category = 'financial') > 0,
  'Owner at aal2 reads financial domain events');
select ok((select count(*) from public.notification_outbox where category = 'financial') > 0,
  'Owner at aal2 reads financial outbox rows');
reset role;

select * from finish();
rollback;
