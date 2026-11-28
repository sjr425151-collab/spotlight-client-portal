-- AUTH-022 (PWP-2): standardized issuance and order snapshot v2 (04 §4A; OD-3, OD-7, OD-13; R-05).
-- T-CON-09 (Owner clarification 1: separate scope-only and notes-only refusals for each of Owner,
-- Admin and Sales, each with its audit row and no state change), T-CON-10 (v2 contents and hash),
-- T-CON-03 (fail closed at issuance, acceptance and display; no fallback), T-CON-11 (the positive
-- client read path; Sales, other tenants and anon read nothing), the OD-3 lock order in the
-- deployed bodies, and the OI-87 and AUTH-010 I-1 privilege boundaries.
-- Seed: Owner …01, Admin …02, Sales …05, client A …a1 (Project A …a0), client B …b1 (Project B …b0).
-- Synthetic and fixture data only; everything is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(43);

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
create temp table ids (k text primary key, v text);
grant all on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated;
create temp table mark (last_id bigint);
grant all on mark to authenticated;
create function pg_temp.mark() returns void language sql as $$
  delete from mark; insert into mark select coalesce(max(id), 0) from public.audit_events;
$$;
-- The refusal left exactly one audit row with this action and reason on the project, and no order
-- summary, domain event or notification for it.
create function pg_temp.refused_cleanly(p_project uuid, p_action text, p_reason text, p_summaries integer)
returns boolean language sql as $$
  select (select count(*) from public.audit_events e where e.id > (select last_id from mark)
           and e.project_id = p_project) = 1
     and exists (select 1 from public.audit_events e where e.id > (select last_id from mark)
           and e.project_id = p_project and e.action = p_action and e.summary ->> 'reason' = p_reason)
     and (select count(*) from public.order_summaries where project_id = p_project) = p_summaries
     and not exists (select 1 from public.domain_events d where d.project_id = p_project
           and d.event_type = 'order_summary.issued')
$$;

-- Sales: an assigned project of its own (the authorized WP-S path).
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
insert into ids select 'ps', public.sales_create_customer_project('PWP2 Synthetic LLC', 'PWP2 Synthetic', 'PWP2 site')
  ->> 'project_id';
reset role;

-- ---------------------------------------------------------------------------
-- 1. T-CON-09: separate scope-only and notes-only refusals, per role (Owner clarification 1)
-- ---------------------------------------------------------------------------
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential', '["Injected scope"]'::jsonb) ->> 'error',
  'scope_not_allowed', 'T-CON-09: the Owner''s scope-only input is rejected');
reset role;
select ok(pg_temp.refused_cleanly('20000000-0000-4000-8000-0000000000a0', 'order_summary.input_rejected', 'scope_input', 0),
  'T-CON-09: the Owner''s scope-only refusal is audited and changes nothing');
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential', '[]'::jsonb, 'Injected note') ->> 'error',
  'notes_not_allowed', 'T-CON-09: the Owner''s notes-only input is rejected');
reset role;
select ok(pg_temp.refused_cleanly('20000000-0000-4000-8000-0000000000a0', 'order_summary.input_rejected', 'notes_input', 0),
  'T-CON-09: the Owner''s notes-only refusal is audited and changes nothing');

select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential', '["Injected scope"]'::jsonb) ->> 'error',
  'scope_not_allowed', 'T-CON-09: the Admin''s scope-only input is rejected');
reset role;
select ok(pg_temp.refused_cleanly('20000000-0000-4000-8000-0000000000a0', 'order_summary.input_rejected', 'scope_input', 0),
  'T-CON-09: the Admin''s scope-only refusal is audited and changes nothing');
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential', '[]'::jsonb, 'Injected note') ->> 'error',
  'notes_not_allowed', 'T-CON-09: the Admin''s notes-only input is rejected');
reset role;
select ok(pg_temp.refused_cleanly('20000000-0000-4000-8000-0000000000a0', 'order_summary.input_rejected', 'notes_input', 0),
  'T-CON-09: the Admin''s notes-only refusal is audited and changes nothing');
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential', '[]'::jsonb, '') ->> 'error',
  'notes_not_allowed', 'T-CON-09: even an empty staff note is rejected');
reset role;

select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('ps'), 'essential', '["Injected scope"]'::jsonb) ->> 'error',
  'scope_not_allowed', 'T-CON-09: the Sales scope-only input is rejected');
reset role;
select ok(pg_temp.refused_cleanly(pg_temp.id('ps'), 'sales.order_summary_rejected', 'scope_input', 0),
  'T-CON-09: the Sales scope-only refusal is audited and changes nothing');
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('ps'), 'essential', '[]'::jsonb, 'Injected note') ->> 'error',
  'notes_not_allowed', 'T-CON-09: the Sales notes-only input is rejected');
reset role;
select ok(pg_temp.refused_cleanly(pg_temp.id('ps'), 'sales.order_summary_rejected', 'notes_input', 0),
  'T-CON-09: the Sales notes-only refusal is audited and changes nothing');

-- ---------------------------------------------------------------------------
-- 2. T-CON-10: standardized v2 issuance binds the sealed bundle
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'osa', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential') ->> 'order_summary_id';
reset role;
select isnt(pg_temp.id('osa'), null, 'T-CON-10: an Admin issues a standardized order summary without scope input');
select ok((select s.snapshot_version = 2 and s.contract_bundle_id = b.bundle_id and s.contract_bundle_sha256 = b.bundle_sha256
             and s.contract_bundle_canonicalization = b.bundle_canonicalization
             and s.agreement_version_id = b.agreement_version_id and s.agreement_text_sha256 = b.agreement_text_sha256
             and s.package_instrument_id = b.package_instrument_id and s.package_instrument_sha256 = b.package_instrument_sha256
             and s.maintenance_instrument_id = b.maintenance_instrument_id
             and s.maintenance_instrument_sha256 = b.maintenance_instrument_sha256
             and s.shared_terms_instrument_id = b.shared_terms_instrument_id
             and s.shared_terms_instrument_sha256 = b.shared_terms_instrument_sha256
             and s.scope_version = b.scope_version and s.scope_content_sha256 = b.scope_content_sha256
             and s.scope_items = b.scope_items and s.project_notes is null
           from public.order_summaries s, private.current_contract_bundle('essential') b where s.id = pg_temp.id('osa')),
  'T-CON-10: the v2 row carries the bundle, every component id and hash, and the bundle scope, with no notes');
select ok((select private.order_summary_snapshot(s) ?& array['snapshot_canonicalization', 'snapshot_version',
             'contract_bundle_id', 'contract_bundle_sha256', 'contract_bundle_canonicalization', 'agreement_version_id',
             'agreement_text_sha256', 'package_instrument_id', 'package_instrument_sha256', 'maintenance_instrument_id',
             'maintenance_instrument_sha256', 'shared_terms_instrument_id', 'shared_terms_instrument_sha256',
             'package_key', 'scope_version', 'scope_content_sha256', 'scope_items']
             and not private.order_summary_snapshot(s) ? 'project_notes'
             and private.order_summary_snapshot(s) ->> 'snapshot_canonicalization' = 'spotlight.order_summary.v2'
           from public.order_summaries s where s.id = pg_temp.id('osa')),
  'T-CON-10: snapshot v2 contains every bundle and component identifier (F5) and no notes');
select ok((select s.snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot_v2(s)::text)
             and s.snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(s)::text)
           from public.order_summaries s where s.id = pg_temp.id('osa')),
  'T-CON-10: the stored hash is the v2 snapshot hash, through the version dispatcher');
select ok(exists (select 1 from public.audit_events e where e.action = 'order_summary.issued'
             and e.target_id = pg_temp.id('osa')::text
             and e.summary ->> 'contract_bundle_id' = (select contract_bundle_id::text from public.order_summaries where id = pg_temp.id('osa'))),
  'T-CON-10: the issuance audit names the bundle');

-- ---------------------------------------------------------------------------
-- 3. v2 acceptance binds the v2 hash
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'acc', public.accept_agreement(pg_temp.id('osa'), true, true, 'Alex Client',
  'Synthetic Business A LLC', 'Managing Member', true) ->> 'acceptance_id';
reset role;
select isnt(pg_temp.id('acc'), null, 'T-CON-07: the client accepts the v2 summary while its bundle is eligible');
select is((select order_summary_sha256 from public.agreement_acceptances where id = pg_temp.id('acc')),
  (select snapshot_sha256 from public.order_summaries where id = pg_temp.id('osa')),
  'T-CON-10: the acceptance records the v2 summary hash');

-- ---------------------------------------------------------------------------
-- 4. T-CON-11: the positive client read path (and who reads nothing)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((select (r ->> 'ok')::boolean and jsonb_array_length(r -> 'instruments') = 3
             and (select array_agg(i ->> 'kind' order by i ->> 'kind') from jsonb_array_elements(r -> 'instruments') i)
               = array['maintenance_specification', 'package_specification', 'shared_terms']
             and r ->> 'bundle_id' = (select contract_bundle_id::text from public.order_summaries where id = pg_temp.id('osa'))
           from (select public.order_summary_instruments(pg_temp.id('osa')) r) x),
  'T-CON-11: the client reads the three instruments of its own accepted summary''s bundle');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.order_summary_instruments(pg_temp.id('osa')) ->> 'error', 'not_found',
  'T-CON-11: another tenant''s client reads nothing');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.order_summary_instruments(pg_temp.id('osa')) ->> 'error', 'not_found', 'T-CON-11: Sales reads nothing');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.order_summary_instruments(pg_temp.id('osa')) ->> 'ok', 'true', 'T-CON-11: an Admin at aal2 reads the same instruments');
select is(public.order_summary_instruments(gen_random_uuid()) ->> 'error', 'not_found', 'T-CON-11: an unknown summary reads nothing');
reset role;
set local role anon;
select throws_ok($$ select public.order_summary_instruments('00000000-0000-4000-8000-000000000000') $$, '42501', null,
  'T-CON-11: anon cannot call the reader');
reset role;

-- ---------------------------------------------------------------------------
-- 5. T-CON-03 and R-05: integrity failure and withdrawal fail closed, with no fallback
-- ---------------------------------------------------------------------------
-- (a) A presented summary whose bundle no longer verifies: acceptance fails closed (hash_mismatch).
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'osb1', public.issue_order_summary('20000000-0000-4000-8000-0000000000b0', 'advanced') ->> 'order_summary_id';
reset role;
select isnt(pg_temp.id('osb1'), null, 'setup: a v2 summary on Project B (advanced)');
-- Test-only tampering inside this rolled-back transaction: the append-only guard is bypassed by the
-- table owner to corrupt one sealed instrument, exactly what verification must detect.
alter table private.contract_instrument_versions disable trigger contract_instrument_versions_append_only;
update private.contract_instrument_versions set body = body || ' (tampered)'
 where id = (select package_instrument_id from public.order_summaries where id = pg_temp.id('osb1'));
alter table private.contract_instrument_versions enable trigger contract_instrument_versions_append_only;
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.accept_agreement(pg_temp.id('osb1'), true, true, 'Blair Client', 'Synthetic Business B LLC', 'Owner', true) ->> 'error',
  'hash_mismatch', 'T-CON-03: acceptance fails closed when a bundle component no longer verifies');
reset role;
select ok(exists (select 1 from public.audit_events e where e.id > (select last_id from mark)
             and e.action = 'agreement.bundle_rejected' and e.summary ->> 'reason' = 'integrity')
  and not exists (select 1 from public.agreement_acceptances where order_summary_id = pg_temp.id('osb1')),
  'T-CON-03: the integrity refusal is audited and no acceptance exists');
select is((select count(*)::int from private.current_contract_bundle('advanced')), 0,
  'T-CON-03 / R-05: the tampered bundle no longer resolves, and no older bundle is selected');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000b0', 'advanced', '[]'::jsonb, null, 'Again') ->> 'error',
  'scope_definition_missing', 'T-CON-03: issuance fails closed on the tampered bundle');
reset role;

-- (b) Withdrawal: a presented summary of a withdrawn bundle cannot be accepted; issuance fails closed.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'osb2', public.issue_order_summary('20000000-0000-4000-8000-0000000000b0', 'professional', '[]'::jsonb, null,
  'Switch package') ->> 'order_summary_id';
reset role;
select isnt(pg_temp.id('osb2'), null, 'setup: a v2 summary on Project B (professional)');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.withdraw_contract_bundle((select contract_bundle_id from public.order_summaries where id = pg_temp.id('osb2')),
  'Synthetic withdrawal for AUTH-022', 'PGTAP-AUTH-022') ->> 'ok', 'true', 'setup: the Owner withdraws the professional bundle');
reset role;
select pg_temp.mark();
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.accept_agreement(pg_temp.id('osb2'), true, true, 'Blair Client', 'Synthetic Business B LLC', 'Owner', true) ->> 'error',
  'bundle_withdrawn', 'T-CON-06 / T-CON-03: a summary of a withdrawn bundle cannot be accepted');
select is(public.order_summary_instruments(pg_temp.id('osb2')) ->> 'ok', 'true',
  'T-CON-11: the client can still review the instruments of its presented summary');
reset role;
select ok(exists (select 1 from public.audit_events e where e.id > (select last_id from mark)
             and e.action = 'agreement.bundle_rejected' and e.summary ->> 'reason' = 'withdrawn')
  and not exists (select 1 from public.agreement_acceptances where order_summary_id = pg_temp.id('osb2')),
  'T-CON-06: the withdrawal refusal is audited and no acceptance exists');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000b0', 'professional', '[]'::jsonb, null, 'Again') ->> 'error',
  'scope_definition_missing', 'T-CON-06: issuance fails closed for a withdrawn bundle, with no fallback');
reset role;
-- (c) An existing acceptance is permanent: the replay still returns it.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.accept_agreement(pg_temp.id('osa'), true, true, 'Alex Client', 'Synthetic Business A LLC', 'Managing Member', true)
  ->> 'acceptance_id', pg_temp.id('acc')::text, 'accepted records are permanent: the replay returns the existing acceptance');
reset role;

-- ---------------------------------------------------------------------------
-- 6. Requirement A: the OD-3 lock order in the deployed bodies
-- ---------------------------------------------------------------------------
select ok((select position('for no key update;' in d) < position('current_contract_bundle(p_package_key)' in d)
             and position('current_contract_bundle(p_package_key)' in d) < position('status = ''presented'' for update;' in d)
             and position('status = ''presented'' for update;' in d) < position('for share);' in d)
           from (select pg_get_functiondef('private.issue_order_summary(uuid, text, jsonb, text, text)'::regprocedure) d) x),
  'OD-3: issuance takes the project row, then the per-package lock, then the summary row, then the bundle row');
select ok((select position('pg_advisory_xact_lock_shared(hashtextextended(''dep18-scope-eligibility:''' in d)
               < position('where id = p_order_summary_id for update;' in d)
             and position('where id = p_order_summary_id for update;' in d) < position('for share);' in d)
             and position('lock table' in d) = 0
           from (select pg_get_functiondef('private.accept_agreement(uuid, boolean, boolean, text, text, text, boolean)'::regprocedure) d) x),
  'OD-3: acceptance takes the per-package lock shared before the summary row, then the bundle row');

-- ---------------------------------------------------------------------------
-- 7. Privileges: OI-87 for the new columns; the AUTH-010 I-1 boundary for the new functions
-- ---------------------------------------------------------------------------
select ok(has_column_privilege('authenticated', 'public.order_summaries', 'contract_bundle_id', 'select')
  and has_column_privilege('authenticated', 'public.order_summaries', 'scope_content_sha256', 'select')
  and has_column_privilege('authenticated', 'public.order_summaries', 'snapshot_version', 'select')
  and not has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'select')
  and not has_table_privilege('authenticated', 'public.order_summaries', 'insert')
  and not has_table_privilege('authenticated', 'public.order_summaries', 'update'),
  'OI-87: the v2 columns are granted explicitly; change_reason stays unreadable; no write grant');
select ok(has_function_privilege('authenticated', 'private.order_summary_instruments(uuid)', 'execute')
  and not has_function_privilege('anon', 'private.order_summary_instruments(uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.order_summary_instruments(uuid)', 'execute')
  and not has_function_privilege('public', 'private.order_summary_instruments(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.order_summary_snapshot_v2(public.order_summaries)', 'execute')
  and (select prosecdef from pg_proc where oid = 'private.order_summary_instruments(uuid)'::regprocedure)
  and not (select prosecdef from pg_proc where oid = 'public.order_summary_instruments(uuid)'::regprocedure),
  'AUTH-010 I-1: the definer reader is executable by authenticated only, behind an invoker wrapper; the snapshot helper by no API role');
select ok(not exists (select 1 from public.order_summaries where snapshot_version = 1 and contract_bundle_id is not null)
  and not exists (select 1 from public.order_summaries where snapshot_version = 2 and contract_bundle_id is null),
  'the snapshot shape constraint holds for every row');

select * from finish();
rollback;
