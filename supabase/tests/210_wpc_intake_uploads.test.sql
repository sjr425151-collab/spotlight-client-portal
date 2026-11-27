-- WP-C intake and uploads (05 §3-§5): T-LC-01, T-LC-04, T-UP-01, T-UP-04 (serial part; the
-- concurrent part is in tests/integration/wpc-uploads.test.ts), T-UP-05, T-UP-06, T-UP-07,
-- T-UP-09, DEP-07 mock-scanner restriction, and no scan self-certification (AUTH-004).
-- Financial input comes from a test-only fixture of the approved WP-B interface (rolled back).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(81);

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
create function pg_temp.as_server() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
grant execute on function pg_temp.act_as(uuid, text, interval), pg_temp.as_server() to authenticated, service_role;
-- The upload's current scan attempt (05 §5.5), as the server learns it from record_content_check.
create function pg_temp.cur(p_name text) returns uuid language sql as $$
  select current_scan_attempt_id from public.asset_uploads where original_name = p_name;
$$;
grant execute on function pg_temp.cur(text) to service_role;

-- Test-only fixture of private.project_financial_status (WP-B interface; OI-71 attribute
-- names). jsonb_populate_record keeps it valid whatever attributes WP-B adds.
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

create function pg_temp.complete_content() returns jsonb language sql as $$
  select jsonb_build_object('business_legal_name', 'Synthetic Business A LLC', 'business_display_name', 'Business A',
    'contact_phone', '555-0100', 'contact_email', 'contact@example.test', 'address', '1 Test St, Detroit, MI',
    'service_areas', jsonb_build_array('Detroit'), 'services_offered', jsonb_build_array('Plumbing'),
    'domain_status', 'needs_domain');
$$;
grant execute on function pg_temp.complete_content() to authenticated;

-- ---------------------------------------------------------------------------
-- 1. T-LC-01: intake and uploads are locked until the deposit is verified
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.get_intake_state('20000000-0000-4000-8000-0000000000a0'), 'locked'::public.intake_state,
  'T-LC-01: intake is locked while the deposit is not verified');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'intake_locked',
  'T-LC-01: saving intake is denied before the deposit is verified');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 1000, 'logo.png') ->> 'error',
  'intake_locked', 'T-LC-01: uploads are denied before the deposit is verified');
reset role;
-- WP-B interface reports implemented but unverified: still locked.
insert into private.test_financial_fixture values ('20000000-0000-4000-8000-0000000000a0',
  '{"implemented": true, "deposit_state": "pending", "deposit_verified": false}');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'intake_locked',
  'T-LC-01: a pending deposit keeps intake locked');
reset role;
-- OI-74: a verified deposit alone is not enough; the payment authorization must be ready.
update private.test_financial_fixture set data = '{"implemented": true, "deposit_verified": true, "payment_authorization_ready": false}';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'intake_locked',
  'T-LC-01: a verified deposit without a ready payment authorization keeps intake locked (OI-74)');
reset role;
update private.test_financial_fixture set data = '{"implemented": true, "deposit_verified": true}';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'intake_locked',
  'T-LC-01: a missing payment_authorization_ready attribute fails closed');
reset role;
-- An interface that raises reads as "not verified" (fail closed).
update private.test_financial_fixture set data = '{"implemented": true, "deposit_verified": true, "payment_authorization_ready": true}';
select ok(private.wpc_deposit_verified('20000000-0000-4000-8000-0000000000a0'), 'deposit reads as verified from the interface');
select ok(not private.wpc_deposit_verified('20000000-0000-4000-8000-0000000000b0'),
  'a project without a verified deposit reads as not verified');
select ok(not private.wpc_deposit_verified(null), 'a null project reads as not verified');

-- ---------------------------------------------------------------------------
-- 2. Save and resume, submission, immutability (05 §3; T-LC-04)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.get_intake_state('20000000-0000-4000-8000-0000000000a0'), 'open'::public.intake_state,
  'intake opens once the deposit is verified');
select ok((public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{"business_legal_name": "Draft"}') ->> 'ok')::boolean,
  'client A saves a partial draft');
select is((public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{"business_legal_name": "Draft 2"}') ->> 'version')::int, 1,
  'saving again resumes the same draft version');
select is((select content ->> 'business_legal_name' from public.intake_submissions
  where project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'draft'), 'Draft 2',
  'the draft is stored server-side (resume after sign-out)');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{"unknown_field": "x"}') ->> 'error', 'invalid_input',
  'unknown intake fields are rejected');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', jsonb_build_object('services_offered', '[1]'::jsonb)) ->> 'error',
  'invalid_input', 'non-string list items are rejected');
select is(public.submit_intake('20000000-0000-4000-8000-0000000000a0',
  (select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'draft')) ->> 'error',
  'incomplete', 'an incomplete intake cannot be submitted');
select ok((public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', pg_temp.complete_content()) ->> 'ok')::boolean,
  'client A completes the draft');
select ok((public.submit_intake('20000000-0000-4000-8000-0000000000a0',
  (select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'draft')) ->> 'ok')::boolean,
  'client A submits the intake');
select is(public.get_intake_state('20000000-0000-4000-8000-0000000000a0'), 'submitted'::public.intake_state, 'intake is submitted');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'intake_not_editable',
  'a submitted intake cannot be edited by the client');
select throws_ok($$ update public.intake_submissions set content = '{}' where project_id = '20000000-0000-4000-8000-0000000000a0' $$,
  '42501', null, 'T-LC-04: clients cannot update intake rows directly');
reset role;
select throws_ok($$ update public.intake_submissions set content = '{}' where project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'submitted' $$,
  '42501', null, 'T-LC-04: a submitted version is immutable even for the table owner');
select is((select count(*)::int from public.audit_events where action = 'intake.submitted'
  and project_id = '20000000-0000-4000-8000-0000000000a0'), 1, 'intake.submitted is audited once');
select is((select count(*)::int from public.notification_outbox where notification_type = 'intake.submitted'
  and project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'recorded'), 1,
  'a staff notification is recorded in the outbox (R1: recorded, never sent)');

-- Staff review: changes requested, resubmission, acceptance.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select is(public.review_intake((select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0'
  and status = 'submitted'), 'accepted', null) ->> 'error', 'forbidden', 'staff at aal1 cannot review intake');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.review_intake((select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0'
  and status = 'submitted'), 'changes_requested', ' ') ->> 'error', 'note_required', 'a change request needs a note');
select ok((public.review_intake((select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0'
  and status = 'submitted'), 'changes_requested', 'Please add service areas') ->> 'ok')::boolean, 'Admin requests changes');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'forbidden',
  'staff cannot write the client''s draft (clients only)');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.get_intake_state('20000000-0000-4000-8000-0000000000a0'), 'changes_requested'::public.intake_state,
  'the client sees changes requested');
select is((public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', pg_temp.complete_content()) ->> 'version')::int, 2,
  'the revised intake is a new version');
select ok((public.submit_intake('20000000-0000-4000-8000-0000000000a0',
  (select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'draft')) ->> 'ok')::boolean,
  'the client resubmits');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
-- OI-79 item 7 (03 §4 v0.5.4): the Owner may correct intake too, but never without a reason.
select is(public.correct_intake('20000000-0000-4000-8000-0000000000a0', pg_temp.complete_content(), '  ') ->> 'error', 'reason_required',
  'T-LC-17: an Owner correction without a reason is rejected');
select ok((public.review_intake((select id from public.intake_submissions where project_id = '20000000-0000-4000-8000-0000000000a0'
  and status = 'submitted' order by version desc limit 1), 'accepted', null) ->> 'ok')::boolean, 'the Owner accepts version 2');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.correct_intake('20000000-0000-4000-8000-0000000000a0', pg_temp.complete_content(), ' ') ->> 'error', 'reason_required',
  'a staff correction needs a reason');
select is((public.correct_intake('20000000-0000-4000-8000-0000000000a0',
  pg_temp.complete_content() || '{"contact_phone": "555-0199"}', 'Client phoned in a corrected number') ->> 'version')::int, 3,
  'T-LC-04: an Admin correction creates a new audited version');
reset role;
select is((select array_agg(source || ':' || status order by version) from public.intake_submissions
  where project_id = '20000000-0000-4000-8000-0000000000a0'),
  array['client:submitted', 'client:submitted', 'staff_correction:submitted'],
  'T-LC-04: earlier versions are preserved unchanged');
select is((select count(*)::int from public.audit_events where action = 'intake.edited_by_staff'
  and reason = 'Client phoned in a corrected number'), 1, 'the correction is audited with its reason');
-- T-LC-17: the Owner corrects with a reason; the original submission stays unchanged and
-- readable by the client; a client can never correct.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is((public.correct_intake('20000000-0000-4000-8000-0000000000a0',
  pg_temp.complete_content() || '{"contact_email": "office@example.test"}', 'Owner: client emailed a new address') ->> 'version')::int, 4,
  'T-LC-17: the Owner corrects intake with a reason, as a new version');
reset role;
select is((select actor_role || '|' || reason from public.audit_events where action = 'intake.edited_by_staff'
  and reason = 'Owner: client emailed a new address'), 'owner|Owner: client emailed a new address',
  'T-LC-17: the correction records the actor role and reason');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select content ->> 'contact_phone' || '|' || source from public.intake_submissions
  where project_id = '20000000-0000-4000-8000-0000000000a0' and version = 1), '555-0100|client',
  'T-LC-17: the original submission is unchanged and readable by the client');
select is(public.correct_intake('20000000-0000-4000-8000-0000000000a0', pg_temp.complete_content(), 'client edit') ->> 'error',
  'forbidden', 'T-LC-17: a client cannot correct intake');
reset role;

-- Cross-tenant (T-TEN-01, T-TEN-02 for the new tables).
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.intake_submissions), 0, 'client B sees no Project A intake');
select is((select count(*)::int from public.intake_reviews), 0, 'client B sees no Project A intake reviews');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'forbidden',
  'client B cannot write Project A intake');
select is(public.get_intake_state('20000000-0000-4000-8000-0000000000a0'), null, 'client B cannot read Project A intake state');
reset role;

-- ---------------------------------------------------------------------------
-- 3. Upload validation and quota (T-UP-01, T-UP-04, T-UP-06)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 15000001, 'logo.png') ->> 'error',
  'file_too_large', 'T-UP-01: a logo over 15 MB is rejected');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'application/pdf', 1000, 'logo.pdf') ->> 'error',
  'type_not_allowed', 'T-UP-01: a disallowed type for the category is rejected');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'video', 'video/mp4', 250000001, 'v.mp4') ->> 'error',
  'file_too_large', 'T-UP-01: a video over 250 MB is rejected');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'other', 'application/zip', 1000, 'a.zip') ->> 'error',
  'type_exception_required', 'T-UP-01: an "other" type needs an approved exception');
select ok((public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 1000, 'logo.png') ->> 'ok')::boolean,
  'a valid logo upload is accepted into the quarantine pipeline');
select is((select quarantine_path from public.asset_uploads where original_name = 'logo.png'),
  'quarantine/20000000-0000-4000-8000-0000000000a0/' || (select id from public.asset_uploads where original_name = 'logo.png'),
  'the only writable path is the project''s quarantine area');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 1000, 'x.png') ->> 'error',
  'forbidden', 'T-UP-06: client B cannot upload into Project A');
select is((select count(*)::int from public.asset_uploads), 0, 'T-UP-06: client B cannot list Project A uploads');
reset role;

-- Quota: 100 files and 2 GB per project (05 §5.1).
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
  original_name, status, quarantine_path, uploaded_by)
select g.id, '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'photo', 'image/jpeg', 1000, 'p.jpg',
  'uploading', 'quarantine/20000000-0000-4000-8000-0000000000a0/' || g.id, '00000000-0000-4000-8000-0000000000a1'
from (select gen_random_uuid() id from generate_series(1, 99)) g;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 1000, 'l101.png') ->> 'error',
  'quota_files', 'T-UP-04: the 101st file is rejected');
reset role;
-- Free the file count but fill the byte quota.
update public.asset_uploads set status = 'failed_upload'
 where project_id = '20000000-0000-4000-8000-0000000000a0' and original_name = 'p.jpg';
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
  original_name, status, quarantine_path, uploaded_by)
select g.id, '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'video', 'video/mp4', 249000000, 'v.mp4',
  'uploading', 'quarantine/20000000-0000-4000-8000-0000000000a0/' || g.id, '00000000-0000-4000-8000-0000000000a1'
from (select gen_random_uuid() id from generate_series(1, 8)) g;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'video', 'video/mp4', 10000000, 'big.mp4') ->> 'error',
  'quota_bytes', 'T-UP-04: an upload beyond 2 GB is rejected');
reset role;
update public.asset_uploads set status = 'failed_upload'
 where project_id = '20000000-0000-4000-8000-0000000000a0' and original_name = 'v.mp4';

-- ---------------------------------------------------------------------------
-- 4. Pipeline: content check, scan, release (05 §5.3; T-UP-05, T-UP-09; DEP-07)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select throws_ok($$ select public.complete_upload((select id from public.asset_uploads where original_name = 'logo.png'), 1000, repeat('a', 64)) $$,
  '42501', null, 'a client cannot report an upload complete (server only)');
select is(public.record_asset_access((select id from public.asset_uploads where original_name = 'logo.png')) ->> 'error',
  'not_available', 'T-UP-05: an asset still uploading or in quarantine cannot be downloaded');
reset role;
select pg_temp.as_server();
select is(public.complete_upload((select id from public.asset_uploads where original_name = 'logo.png'), 1001, repeat('a', 64)) ->> 'error',
  'size_mismatch', 'a stored object larger than declared fails the upload');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 1000, 'logo2.png') ->> 'ok')::boolean, 'a new logo upload');
select ok((public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 1000, 'evil.png') ->> 'ok')::boolean, 'a second upload');
reset role;
select pg_temp.as_server();
select is(public.complete_upload((select id from public.asset_uploads where original_name = 'logo2.png'), 900, repeat('b', 64)) ->> 'status',
  'quarantined', 'a completed upload enters quarantine');
select is(public.record_content_check((select id from public.asset_uploads where original_name = 'logo2.png'), true, 'image/png', null) ->> 'status',
  'scanning', 'a content-valid file moves to scanning, still in quarantine');
select is(public.record_scan_result((select id from public.asset_uploads where original_name = 'logo2.png'), pg_temp.cur('logo2.png'), 'mock_scanner', '1', 'clean', repeat('c', 64)) ->> 'error',
  'hash_mismatch', 'a scan result must be bound to the exact stored bytes');
select is(public.release_upload((select id from public.asset_uploads where original_name = 'logo2.png'), repeat('d', 64), 900) ->> 'error',
  'not_found', 'nothing is released before a clean scan');
-- 05 §5.5 rule 4: the mismatched result returned the file to quarantine; a new attempt opens.
select public.record_content_check((select id from public.asset_uploads where original_name = 'logo2.png'), true, 'image/png', null);
-- DEP-07: without a development runtime marker the mock scanner cannot release anything.
reset role;
delete from private.runtime_environment;
select pg_temp.as_server();
select is(public.record_scan_result((select id from public.asset_uploads where original_name = 'logo2.png'), pg_temp.cur('logo2.png'), 'mock_scanner', '1', 'clean', repeat('b', 64)) ->> 'held',
  'scanner_not_permitted', 'DEP-07: outside a development database a mock "clean" leaves the file in quarantine');
reset role;
insert into private.runtime_environment (app_env) values ('test');
-- OI-119: the billing classification agrees with the runtime 'test' row, so they never disagree.
update private.environment_settings set app_env = 'test';
select pg_temp.as_server();
select is(public.record_content_check((select id from public.asset_uploads where original_name = 'logo2.png'), true, 'image/png', null) ->> 'status',
  'scanning', 'the file is re-checked');
select is(public.record_scan_result((select id from public.asset_uploads where original_name = 'logo2.png'), pg_temp.cur('logo2.png'), 'vendor_x', '1', 'clean', repeat('b', 64)) ->> 'held',
  'scanner_not_permitted', 'DEP-07: no real scanner is permitted yet');
select is(public.record_content_check((select id from public.asset_uploads where original_name = 'logo2.png'), true, 'image/png', null) ->> 'status',
  'scanning', 'the file is re-checked again');
select is(public.record_scan_result((select id from public.asset_uploads where original_name = 'logo2.png'), pg_temp.cur('logo2.png'), 'mock_scanner', '1', 'clean', repeat('b', 64)) ->> 'status',
  'processing', 'a clean mock scan in a test database moves the file to processing');
-- 05 §5.5 rule 5: processing re-read the stored quarantine object and confirmed its hash.
select public.confirm_source_hash((select id from public.asset_uploads where original_name = 'logo2.png'), repeat('b', 64));
select is(public.release_upload((select id from public.asset_uploads where original_name = 'logo2.png'), repeat('d', 64), 880) ->> 'released_path',
  '20000000-0000-4000-8000-0000000000a0/assets/' || (select id from public.asset_uploads where original_name = 'logo2.png'),
  'release writes the record for the released path only after the clean scan');
-- T-UP-09: a malicious file is rejected and both parties are notified.
select public.complete_upload((select id from public.asset_uploads where original_name = 'evil.png'), 1000, repeat('e', 64));
select public.record_content_check((select id from public.asset_uploads where original_name = 'evil.png'), true, 'image/png', null);
select is(public.record_scan_result((select id from public.asset_uploads where original_name = 'evil.png'), pg_temp.cur('evil.png'), 'mock_scanner', '1', 'malicious', repeat('e', 64), 'EICAR') ->> 'status',
  'rejected', 'T-UP-09: a failed scan rejects the asset');
select is(public.release_upload((select id from public.asset_uploads where original_name = 'evil.png'), repeat('e', 64), 1000) ->> 'error',
  'not_found', 'T-UP-09: a rejected asset can never be released');
reset role;
select is((select array_agg(coalesce(array_to_string(recipient_user_ids, ','), '') || '|' || array_to_string(recipient_roles, ','))
  from public.notification_outbox where notification_type = 'upload.rejected'
  and payload_ref ->> 'upload_id' = (select id::text from public.asset_uploads where original_name = 'evil.png')),
  array['00000000-0000-4000-8000-0000000000a1|staff'], 'T-UP-09: the uploader and staff are notified (OI-31)');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.record_asset_access((select id from public.asset_uploads where original_name = 'evil.png')) ->> 'error',
  'not_available', 'T-UP-09: a rejected asset cannot be downloaded');
select ok((public.record_asset_access((select id from public.asset_uploads where original_name = 'logo2.png')) ->> 'ok')::boolean,
  'an available asset can be downloaded, and the access is audited');
reset role;

-- ---------------------------------------------------------------------------
-- 5. T-UP-07: failed uploads are purged after 7 days
-- ---------------------------------------------------------------------------
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
  original_name, status, quarantine_path, uploaded_by, status_changed_at)
values ('30000000-0000-4000-8000-0000000000f1', '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'logo',
  'image/png', 10, 'old.png', 'failed_upload', 'quarantine/20000000-0000-4000-8000-0000000000a0/30000000-0000-4000-8000-0000000000f1',
  '00000000-0000-4000-8000-0000000000a1', now() - interval '8 days');
select pg_temp.as_server();
select ok(public.purge_failed_uploads() -> 'paths' ? 'quarantine/20000000-0000-4000-8000-0000000000a0/30000000-0000-4000-8000-0000000000f1',
  'T-UP-07: a failed upload older than 7 days is purged (its object path is returned for deletion)');
select is((select count(*)::int from jsonb_array_elements_text(public.purge_failed_uploads() -> 'paths')), 0,
  'T-UP-07: purge is idempotent and recent failures are kept');
reset role;

-- Exceptions (05 §5.1-§5.2): an approved file-type exception permits that type only.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((public.request_upload_exception('20000000-0000-4000-8000-0000000000a0', 'file_type', 'application/zip', 5000000,
  null, null, 'Font files for the brand') ->> 'ok')::boolean, 'a client requests a file-type exception');
select is(public.decide_upload_exception((select id from public.upload_exceptions limit 1), true, 'ok') ->> 'error', 'forbidden',
  'a client cannot approve an exception');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((public.decide_upload_exception((select id from public.upload_exceptions limit 1), true, 'Brand fonts approved') ->> 'ok')::boolean,
  'Admin approves the exception with a reason');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((public.request_upload('20000000-0000-4000-8000-0000000000a0', 'other', 'application/zip', 1000, 'fonts.zip') ->> 'ok')::boolean,
  'the approved type can now be uploaded (and is still quarantined and scanned)');
reset role;

select * from finish();
rollback;
