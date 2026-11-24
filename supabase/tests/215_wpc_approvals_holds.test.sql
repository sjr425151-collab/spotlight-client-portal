-- WP-C preview releases, approvals, outreach, and the approval hold (05 §6-§7.2):
-- T-LC-05 to T-LC-09, T-LC-11 to T-LC-13, T-LC-15, T-UP-05, T-UP-10, T-ROLE-04, T-ROLE-05,
-- and the durable release.approved event (01 §7; CURRENT-STATE §8).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(63);

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
grant execute on function pg_temp.act_as(uuid, text, interval) to authenticated, service_role;

-- Test-only fixture of the WP-B interface (rolled back): deposits verified for A and B.
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
insert into private.test_financial_fixture values
  ('20000000-0000-4000-8000-0000000000a0', '{"implemented": true, "deposit_state": "verified", "deposit_verified": true, "payment_authorization_ready": true}'),
  ('20000000-0000-4000-8000-0000000000b0', '{"implemented": true, "deposit_state": "verified", "deposit_verified": true, "payment_authorization_ready": true}');

-- Accepted intake for both projects (fixture rows, written as the table owner).
insert into public.intake_submissions (id, project_id, version, status, content, created_by, submitted_by, submitted_at)
values ('31000000-0000-4000-8000-0000000000a0', '20000000-0000-4000-8000-0000000000a0', 1, 'submitted', '{}',
        '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', now()),
       ('31000000-0000-4000-8000-0000000000b0', '20000000-0000-4000-8000-0000000000b0', 1, 'submitted', '{}',
        '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', now());
insert into public.intake_reviews (project_id, submission_id, decision, reviewed_by) values
  ('20000000-0000-4000-8000-0000000000a0', '31000000-0000-4000-8000-0000000000a0', 'accepted', '00000000-0000-4000-8000-000000000002'),
  ('20000000-0000-4000-8000-0000000000b0', '31000000-0000-4000-8000-0000000000b0', 'accepted', '00000000-0000-4000-8000-000000000002');
-- One available and one quarantined asset in Project A.
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes, original_name,
  status, quarantine_path, released_path, size_bytes, sha256, released_sha256, released_bytes, uploaded_by)
values ('32000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'logo', 'image/png',
        100, 'ok.png', 'available', 'quarantine/20000000-0000-4000-8000-0000000000a0/32000000-0000-4000-8000-0000000000a1',
        '20000000-0000-4000-8000-0000000000a0/assets/32000000-0000-4000-8000-0000000000a1', 100, repeat('a', 64), repeat('a', 64), 90,
        '00000000-0000-4000-8000-0000000000a1');
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes, original_name,
  status, quarantine_path, size_bytes, sha256, uploaded_by)
values ('32000000-0000-4000-8000-0000000000a2', '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'logo', 'image/png',
        100, 'q.png', 'quarantined', 'quarantine/20000000-0000-4000-8000-0000000000a0/32000000-0000-4000-8000-0000000000a2', 100,
        repeat('b', 64), '00000000-0000-4000-8000-0000000000a1'),
       ('32000000-0000-4000-8000-0000000000a3', '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'photo', 'image/png',
        100, 'unused.png', 'quarantined', 'quarantine/20000000-0000-4000-8000-0000000000a0/32000000-0000-4000-8000-0000000000a3', 100,
        repeat('c', 64), '00000000-0000-4000-8000-0000000000a1');

-- ---------------------------------------------------------------------------
-- 1. Staff-recorded releases (T-LC-15, T-UP-05, T-UP-10)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), 'dpl_1', 'https://preview.example.test', '{}') ->> 'error',
  'forbidden', 'T-LC-15: a client cannot create a release');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', 'not-a-sha', 'dpl_1', 'https://preview.example.test', '{}') ->> 'error',
  'invalid_input', 'T-LC-15: a release requires a full commit SHA');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), 'dpl_1', 'http://preview.example.test', '{}') ->> 'error',
  'invalid_input', 'T-LC-15: a release requires an https preview URL');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), '', 'https://preview.example.test', '{}') ->> 'error',
  'invalid_input', 'T-LC-15: a release requires a deployment ID');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), 'dpl_1', 'https://preview.example.test',
  array['32000000-0000-4000-8000-0000000000a2']::uuid[]) ->> 'error', 'asset_not_available',
  'T-UP-05: a quarantined asset cannot be used in a release');
select is((public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), 'dpl_1', 'https://preview.example.test',
  array['32000000-0000-4000-8000-0000000000a1']::uuid[]) ->> 'release_number')::int, 1, 'Admin records release 1');
reset role;
select ok((select used from public.asset_uploads where id = '32000000-0000-4000-8000-0000000000a1'),
  'T-UP-10: incorporating an asset into a released preview sets used');
select ok(not (select used from public.asset_uploads where id = '32000000-0000-4000-8000-0000000000a3'),
  'T-UP-10: an asset never incorporated stays unused');
select throws_ok($$ update public.asset_uploads set used = false, used_at = null where id = '32000000-0000-4000-8000-0000000000a1' $$,
  '42501', null, 'T-UP-10: the used flag never reverts');
select throws_ok($$ update public.preview_releases set preview_url = 'https://evil.example.test' where project_id = '20000000-0000-4000-8000-0000000000a0' $$,
  '42501', null, 'T-LC-15: a released preview is immutable');
select throws_ok($$ delete from public.preview_releases $$, '42501', null, 'releases are never deleted');

-- ---------------------------------------------------------------------------
-- 2. Approval (T-LC-05, T-LC-09, T-ROLE-04) and release.approved
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is(public.approve_preview((select id from public.preview_releases where project_id = '20000000-0000-4000-8000-0000000000a0')) ->> 'error',
  'forbidden', 'T-LC-09 / T-ROLE-04: the Owner cannot approve on a client''s behalf');
select throws_ok($$ insert into public.preview_approvals (release_id, project_id, user_id)
  select id, project_id, '00000000-0000-4000-8000-0000000000a1' from public.preview_releases limit 1 $$,
  '42501', null, 'T-LC-09: staff cannot insert an approval record directly');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.approve_preview((select id from public.preview_releases where project_id = '20000000-0000-4000-8000-0000000000a0')) ->> 'error',
  'forbidden', 'T-LC-09: Admin cannot approve');
reset role;
create temp table ctx as select id as release_a1 from public.preview_releases
  where project_id = '20000000-0000-4000-8000-0000000000a0' and release_number = 1;
grant select on ctx to authenticated;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.approve_preview((select release_a1 from ctx)) ->> 'error',
  'forbidden', 'T-LC-05: client B cannot approve Project A''s release');
select is((select count(*)::int from public.preview_releases), 0, 'client B cannot see Project A releases');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((public.approve_preview((select id from public.preview_releases where release_number = 1
  and project_id = '20000000-0000-4000-8000-0000000000a0'), 'Looks great') ->> 'ok')::boolean,
  'T-LC-05: client A approves the current release of their project');
select ok((public.approve_preview((select id from public.preview_releases where release_number = 1
  and project_id = '20000000-0000-4000-8000-0000000000a0')) ->> 'existing')::boolean,
  'a repeat approval by the same user returns the existing record (idempotent)');
reset role;
select is((select count(*)::int from public.domain_events where event_type = 'release.approved'
  and project_id = '20000000-0000-4000-8000-0000000000a0'), 1, 'release.approved is emitted exactly once for the release');
select is((select payload ->> 'release_id' from public.domain_events where event_type = 'release.approved'
  and project_id = '20000000-0000-4000-8000-0000000000a0'),
  (select id::text from public.preview_releases where release_number = 1 and project_id = '20000000-0000-4000-8000-0000000000a0'),
  'release.approved names exactly the approved release (dedupe key per release)');
select is((select dedupe_key from public.domain_events where event_type = 'release.approved'
  and project_id = '20000000-0000-4000-8000-0000000000a0'),
  'release.approved:' || (select id from public.preview_releases where release_number = 1 and project_id = '20000000-0000-4000-8000-0000000000a0'),
  'the event carries the durable per-release dedupe key WP-B consumes');
select ok((private.project_fulfillment_status('20000000-0000-4000-8000-0000000000a0')).current_release_approved,
  'the fulfillment interface reports the current release approved');

-- ---------------------------------------------------------------------------
-- 3. New release invalidates the approval for publication (T-LC-06, T-LC-07)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((public.record_preview_draft('20000000-0000-4000-8000-0000000000a0', repeat('c', 40), 'internal build') ->> 'ok')::boolean,
  'staff record an internal draft');
reset role;
select ok((private.project_fulfillment_status('20000000-0000-4000-8000-0000000000a0')).current_release_approved,
  'T-LC-07: an internal draft does not supersede the current approval');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from public.preview_drafts), 0, 'clients cannot see internal drafts');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('b', 40), 'dpl_2', 'https://preview2.example.test', '{}')
  ->> 'release_number')::int, 2, 'Admin records release 2');
reset role;
select ok(not (private.project_fulfillment_status('20000000-0000-4000-8000-0000000000a0')).current_release_approved,
  'T-LC-06: after release n+1 the approval gate input fails until n+1 is approved');
select is((select count(*)::int from public.preview_approvals a join public.preview_releases r on r.id = a.release_id
  where r.release_number = 1 and r.project_id = '20000000-0000-4000-8000-0000000000a0'), 1,
  'T-LC-06: the approval of release n is still stored');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.approve_preview((select id from public.preview_releases where release_number = 1 and project_id = '20000000-0000-4000-8000-0000000000a0')) ->> 'existing',
  'true', 'the client''s existing approval of release 1 is returned, not recreated');
reset role;
-- A second client member of Project A, who never approved release 1, cannot approve it now.
insert into public.project_memberships (project_id, user_id) values
  ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-0000000000b1');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.approve_preview((select id from public.preview_releases where release_number = 1 and project_id = '20000000-0000-4000-8000-0000000000a0')) ->> 'error',
  'release_superseded', 'approving a superseded release is rejected with a reload prompt (05 §7 concurrency)');
reset role;
delete from public.project_memberships where project_id = '20000000-0000-4000-8000-0000000000a0'
  and user_id = '00000000-0000-4000-8000-0000000000b1';

-- T-LC-08: nothing but the client approval function creates approvals.
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosrc ilike '%insert into public.preview_approvals%'),
  array['approve_preview'], 'T-LC-08: the only code path that inserts an approval is the client approval function');
select is((select count(*)::int from pg_trigger t join pg_proc p on p.oid = t.tgfoid
  where not t.tgisinternal and p.prosrc ilike '%preview_approvals%' and p.proname <> 'approve_preview'), 0,
  'T-LC-08: no trigger creates or references approvals');
select ok(not exists (select 1 from pg_extension where extname = 'pg_cron'),
  'T-LC-08: no scheduled job exists that could create an approval');

-- ---------------------------------------------------------------------------
-- 4. Outreach and the day-21 hold on Project B (05 §7.1-§7.2)
-- ---------------------------------------------------------------------------
-- Release 1 of Project B, released 22 local calendar days ago.
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by, released_at)
values ('33000000-0000-4000-8000-0000000000b1', '20000000-0000-4000-8000-0000000000b0', 1, repeat('d', 40), 'dpl_b1',
        'https://preview-b.example.test', '00000000-0000-4000-8000-000000000002', now() - interval '22 days');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select array_agg(q ->> 'queue' || ':' || coalesce(q -> 'detail' ->> 'outreach', '') order by q ->> 'queue', q -> 'detail' ->> 'outreach')
  from public.operational_queue() q where q ->> 'project_id' = '20000000-0000-4000-8000-0000000000b0'),
  array['approval_followup_due:', 'approval_outreach_due:admin_notified', 'approval_outreach_due:reminder_1',
        'approval_outreach_due:reminder_2', 'awaiting_client_approval:'],
  'the derived queue shows every outreach step due at day 22 (OI-25)');
select is(public.place_approval_hold('20000000-0000-4000-8000-0000000000b0', 'No response') ->> 'error', 'outreach_required',
  'T-LC-11: the hold cannot be placed without a recorded personal follow-up');
select is(public.record_outreach('33000000-0000-4000-8000-0000000000b1', 'reminder_1', 'email',
  ((now() - interval '30 days') at time zone 'America/Detroit')::date, 'Reminder') ->> 'error', 'invalid_date',
  'outreach cannot be dated before the release');
select ok((public.record_outreach('33000000-0000-4000-8000-0000000000b1', 'reminder_1', 'email',
  ((now() - interval '19 days') at time zone 'America/Detroit')::date, 'Day-3 reminder sent') ->> 'ok')::boolean, 'day-3 reminder recorded');
select ok((public.record_outreach('33000000-0000-4000-8000-0000000000b1', 'reminder_2', 'email',
  ((now() - interval '15 days') at time zone 'America/Detroit')::date, 'Day-7 reminder sent') ->> 'ok')::boolean, 'day-7 reminder recorded');
select is((select count(*)::int from public.operational_queue() q where q ->> 'queue' = 'approval_outreach_due'
  and q ->> 'project_id' = '20000000-0000-4000-8000-0000000000b0'), 1,
  'T-LC-15: the outreach queue clears only for the steps recorded (Admin notification still due)');
select ok((public.record_outreach('33000000-0000-4000-8000-0000000000b1', 'admin_notified', 'portal',
  ((now() - interval '15 days') at time zone 'America/Detroit')::date, 'Admin notified') ->> 'ok')::boolean, 'Admin notification recorded');
select ok((public.record_outreach('33000000-0000-4000-8000-0000000000b1', 'personal_followup', 'phone',
  ((now() - interval '8 days') at time zone 'America/Detroit')::date, 'Called the client; no answer') ->> 'ok')::boolean,
  'day-14 personal follow-up recorded');
select is((select array_agg(q ->> 'queue' order by q ->> 'queue') from public.operational_queue() q
  where q ->> 'project_id' = '20000000-0000-4000-8000-0000000000b0'),
  array['approval_hold_eligible', 'awaiting_client_approval'], 'the project becomes hold-eligible at day 21+ with documented outreach');
select ok((public.place_approval_hold('20000000-0000-4000-8000-0000000000b0', 'No response after documented outreach') ->> 'ok')::boolean,
  'Admin places the approval hold');
select is(public.place_approval_hold('20000000-0000-4000-8000-0000000000b0', 'again') ->> 'error', 'hold_active',
  'only one active approval hold per project');
reset role;
select is((select cardinality(outreach_evidence_ids) from public.approval_holds where project_id = '20000000-0000-4000-8000-0000000000b0'), 4,
  'the hold records the outreach evidence IDs');
select is((private.project_fulfillment_status('20000000-0000-4000-8000-0000000000b0')).active_fulfillment_holds,
  array['approval_nonresponsive_hold']::public.hold_type[], 'the hold is reported as a fulfillment hold');
select is((select count(*)::int from public.preview_approvals where project_id = '20000000-0000-4000-8000-0000000000b0'), 0,
  'T-LC-11: placing the hold never creates an approval');
select is((select data from private.test_financial_fixture where project_id = '20000000-0000-4000-8000-0000000000b0'),
  '{"implemented": true, "deposit_state": "verified", "deposit_verified": true, "payment_authorization_ready": true}'::jsonb,
  'T-LC-13: the hold does not touch billing state');

-- T-ROLE-05: Admin cannot clear without a qualifying client response; the Owner can.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.clear_approval_hold((select id from public.approval_holds where cleared_at is null), 'Client is busy') ->> 'error',
  'client_response_required', 'T-ROLE-05: Admin cannot clear the hold without a client response');
reset role;
select is((select count(*)::int from public.audit_events where action = 'approval_hold.clear_rejected'), 1,
  'T-ROLE-05: the refused clearance is audited');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.clear_approval_hold((select id from public.approval_holds where cleared_at is null), ' ') ->> 'error',
  'reason_required', 'the Owner must give a reason');
select ok((public.clear_approval_hold((select id from public.approval_holds where cleared_at is null), 'Owner decision: resume') ->> 'ok')::boolean,
  'T-ROLE-05: the Owner clears the hold with a reason');
select ok((public.place_approval_hold('20000000-0000-4000-8000-0000000000b0', 'Still no response') ->> 'ok')::boolean,
  'the hold can be placed again while the release stays unapproved');
reset role;

-- T-LC-12 / T-LC-13: during the hold the client keeps access, can request revisions and approve.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.preview_releases where project_id = '20000000-0000-4000-8000-0000000000b0'), 1,
  'T-LC-12: the client can still view the preview during the hold');
select is(public.project_status('20000000-0000-4000-8000-0000000000b0') ->> 'approval_hold',
  'Paused: awaiting your preview response', 'the hold is shown to the client as a pause, never as a billing status');
select ok((public.request_revisions('33000000-0000-4000-8000-0000000000b1', 'Please change the header color') ->> 'ok')::boolean,
  'T-LC-12: the client can request revisions during the hold');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select array_agg(q ->> 'queue' order by q ->> 'queue') from public.operational_queue() q
  where q ->> 'project_id' = '20000000-0000-4000-8000-0000000000b0' and q ->> 'queue' like 'approval_%'),
  array['approval_hold_review'], 'a client response creates an approval_hold_review queue item and stops the outreach schedule');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select ok((public.approve_preview('33000000-0000-4000-8000-0000000000b1') ->> 'ok')::boolean,
  'T-LC-12: the client can approve during the hold');
reset role;
select ok((private.project_fulfillment_status('20000000-0000-4000-8000-0000000000b0')).current_release_approved,
  'T-LC-12: an approval made during the hold is a valid G3 input');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((public.clear_approval_hold((select id from public.approval_holds where cleared_at is null), 'Client approved') ->> 'ok')::boolean,
  'Admin clears the hold after the qualifying client response');
select ok((public.record_hold_resumption((select id from public.approval_holds where clear_reason = 'Client approved'),
  'proceed_to_final_payment', 'Client approved') ->> 'ok')::boolean, 'the resumption decision is recorded');
reset role;
-- (Both responses share the transaction timestamp here, so either may be cited first.)
select ok((select clearing_response_id is not null and clearing_response_type in ('approval', 'revision_request')
  from public.approval_holds where clear_reason = 'Client approved'),
  'the Admin clearance cites the qualifying client response it relied on');
select is((select count(*)::int from public.audit_events where action in ('approval_hold.placed', 'approval_hold.cleared',
  'approval_hold.client_response', 'approval_hold.resumption_decided') and project_id = '20000000-0000-4000-8000-0000000000b0'), 7,
  'every hold step is audited (2 placements, 2 clearances, 2 client responses, 1 resumption)');

select * from finish();
rollback;
