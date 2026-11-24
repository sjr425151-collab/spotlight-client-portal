-- WP-C authoritative scan results (05 §5.5), retries (05 §5.4 item 8), the OI-78 security
-- corrections, OI-79 release and security rules, and the dispute evidence interface
-- (04 §15.4). T-UP-12 to T-UP-19 (T-UP-15 concurrency also runs with real parallel
-- connections in tests/integration/wpc-scan-authority.test.ts), T-UP-10, T-UP-13, T-LC-16,
-- T-PUB-20, T-ARC-10 (WP-C side).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(74);

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
-- authenticated holds no EXECUTE on the private helper; evaluate it with the caller's claims.
create function pg_temp.client_member(p uuid) returns boolean language sql security definer as $$
  select private.wpc_is_client_member(p);
$$;
grant execute on function pg_temp.client_member(uuid) to authenticated;

-- The pipeline runs as the server (service_role claim). These helpers run as the table owner
-- with that claim, which is what the definer functions check.
create function pg_temp.server() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;
-- A completed upload in quarantine with the given stored hash.
create function pg_temp.mk(p_id uuid, p_sha text, p_project uuid default '20000000-0000-4000-8000-0000000000a0')
returns uuid language sql as $$
  insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
    original_name, status, quarantine_path, size_bytes, sha256, completed_at, uploaded_by)
  values (p_id, p_project, gen_random_uuid(), 1, 'logo', 'image/png', 100, p_id::text || '.png', 'quarantined',
    'quarantine/' || p_project || '/' || p_id, 100, p_sha, now(), '00000000-0000-4000-8000-0000000000a1')
  returning id;
$$;
-- Opens an attempt (content check passed) and returns its id.
create function pg_temp.open(p_id uuid) returns uuid language sql as $$
  select (private.record_content_check(p_id, true, 'image/png', null) ->> 'attempt_id')::uuid;
$$;
create function pg_temp.scan(p_id uuid, p_attempt uuid, p_verdict text, p_sha text, p_scanner text default 'mock_scanner')
returns jsonb language sql as $$
  select private.record_scan_result(p_id, p_attempt, p_scanner, '1', p_verdict, p_sha);
$$;
create function pg_temp.st(p_id uuid) returns text language sql as $$
  select status::text from public.asset_uploads where id = p_id;
$$;
-- Full happy-path release attempt after processing: confirm the stored hash, then release.
create function pg_temp.release(p_id uuid, p_sha text) returns jsonb language sql as $$
  select private.confirm_source_hash(p_id, p_sha);
  select private.release_upload(p_id, repeat('f', 64), 90);
$$;

-- ---------------------------------------------------------------------------
-- 1. T-UP-14: identical timestamps; authority by sequence, deterministically
-- ---------------------------------------------------------------------------
select pg_temp.server();
create temp table t14 as
  select pg_temp.mk(('41000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid, repeat('a', 64)) as id
  from generate_series(1, 25) g;
-- Each upload: attempt 1 gets an unpermitted-scanner clean; attempt 2 gets a permitted clean.
select count(*) from (
  select pg_temp.scan(id, pg_temp.open(id), 'clean', repeat('a', 64), 'vendor_x') from t14) x;
select count(*) from (select pg_temp.scan(id, pg_temp.open(id), 'clean', repeat('a', 64)) from t14) x;
select is((select count(distinct scanned_at)::int from public.upload_scan_results r join t14 on t14.id = r.upload_id), 1,
  'T-UP-14: every result shares one timestamp (one transaction)');
select ok((select bool_and(r2.seq > r1.seq) from public.upload_scan_results r1
  join public.upload_scan_results r2 on r2.upload_id = r1.upload_id and r2.scanner = 'mock_scanner'
  join t14 on t14.id = r1.upload_id where r1.scanner = 'vendor_x'),
  'T-UP-14: the sequence is strictly increasing in acceptance order');
select is((select count(*)::int from t14 where (pg_temp.release(id, repeat('a', 64)) ->> 'status') = 'available'), 25,
  'T-UP-14: release uses the last accepted result every time (25 of 25, never a coin toss)');

-- ---------------------------------------------------------------------------
-- 2. T-UP-16: unpermitted then permitted; and the reverse never releases
-- ---------------------------------------------------------------------------
select pg_temp.mk('42000000-0000-4000-8000-000000000001', repeat('b', 64));
create temp table a16 (n int, id uuid);
insert into a16 values (1, pg_temp.open('42000000-0000-4000-8000-000000000001'));
select is(pg_temp.scan('42000000-0000-4000-8000-000000000001', (select id from a16 where n = 1), 'clean', repeat('b', 64), 'vendor_x') ->> 'held',
  'scanner_not_permitted', 'T-UP-16: an unpermitted clean returns the file to quarantine');
insert into a16 values (2, pg_temp.open('42000000-0000-4000-8000-000000000001'));
select is(pg_temp.scan('42000000-0000-4000-8000-000000000001', (select id from a16 where n = 1), 'clean', repeat('b', 64)) ->> 'disposition',
  'stale_attempt', 'T-UP-16 / T-UP-18: a late permitted clean for the earlier attempt is non-authoritative');
select is(pg_temp.st('42000000-0000-4000-8000-000000000001'), 'scanning', 'the stale result changed nothing');
select is(pg_temp.scan('42000000-0000-4000-8000-000000000001', (select id from a16 where n = 2), 'clean', repeat('b', 64), 'vendor_x') ->> 'held',
  'scanner_not_permitted', 'the newer attempt is also unpermitted: quarantined');
select is(private.release_upload('42000000-0000-4000-8000-000000000001', repeat('f', 64), 90) ->> 'error', 'not_found',
  'T-UP-16: the reverse order (permitted for an older attempt, unpermitted for the newer) never releases');
insert into a16 values (3, pg_temp.open('42000000-0000-4000-8000-000000000001'));
select is(pg_temp.scan('42000000-0000-4000-8000-000000000001', (select id from a16 where n = 3), 'clean', repeat('b', 64)) ->> 'status',
  'processing', 'T-UP-16: a permitted clean for the newest attempt counts');
select is(pg_temp.release('42000000-0000-4000-8000-000000000001', repeat('b', 64)) ->> 'status', 'available',
  'T-UP-16: release happens only through the newer attempt');
select is((select attempt_id from private.authoritative_scan('42000000-0000-4000-8000-000000000001')), (select id from a16 where n = 3),
  'the authoritative result is the newest attempt''s');

-- ---------------------------------------------------------------------------
-- 3. T-UP-17: clean followed by malicious (any attempt, any state) or by error
-- ---------------------------------------------------------------------------
-- (a) processing, then malicious from an earlier attempt.
select pg_temp.mk('43000000-0000-4000-8000-000000000001', repeat('c', 64));
create temp table a17 (n int, id uuid);
insert into a17 values (1, pg_temp.open('43000000-0000-4000-8000-000000000001'));
select pg_temp.scan('43000000-0000-4000-8000-000000000001', (select id from a17 where n = 1), 'error', repeat('c', 64));
update public.asset_uploads set next_scan_at = null where id = '43000000-0000-4000-8000-000000000001';
insert into a17 values (2, pg_temp.open('43000000-0000-4000-8000-000000000001'));
select is(pg_temp.scan('43000000-0000-4000-8000-000000000001', (select id from a17 where n = 2), 'clean', repeat('c', 64)) ->> 'status',
  'processing', 'clean result: processing');
select is(pg_temp.scan('43000000-0000-4000-8000-000000000001', (select id from a17 where n = 1), 'malicious', repeat('c', 64)) ->> 'status',
  'rejected', 'T-UP-17: a malicious verdict from an earlier attempt, after a clean result, rejects the upload');
select is(pg_temp.release('43000000-0000-4000-8000-000000000001', repeat('c', 64)) ->> 'error', 'not_found',
  'T-UP-17: the rejected upload can never be released');
select ok((select malware_detected from public.asset_uploads where id = '43000000-0000-4000-8000-000000000001'),
  'the malware detection is recorded on the upload');
select throws_ok($$ update public.asset_uploads set malware_detected = false where id = '43000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'a malware detection never reverts');
-- (b) a malicious verdict with no attempt at all (scanner callback with an unknown attempt).
select pg_temp.mk('43000000-0000-4000-8000-000000000002', repeat('d', 64));
select pg_temp.open('43000000-0000-4000-8000-000000000002');
select is(pg_temp.scan('43000000-0000-4000-8000-000000000002', gen_random_uuid(), 'malicious', repeat('d', 64)) ->> 'status',
  'rejected', 'T-UP-17: a malicious verdict naming an unknown attempt still rejects (malware always wins)');
-- (c) after release: revoked, audited, Owner alerted.
select pg_temp.mk('43000000-0000-4000-8000-000000000003', repeat('e', 64));
select pg_temp.scan('43000000-0000-4000-8000-000000000003', pg_temp.open('43000000-0000-4000-8000-000000000003'), 'clean', repeat('e', 64));
select is(pg_temp.release('43000000-0000-4000-8000-000000000003', repeat('e', 64)) ->> 'status', 'available', 'released');
select is(pg_temp.scan('43000000-0000-4000-8000-000000000003', null, 'malicious', repeat('e', 64)) ->> 'revoked', 'true',
  'T-UP-17: a malicious verdict after release revokes the file');
select is((select status::text || '|' || rejection_code || '|' || (revoked_at is not null)::text from public.asset_uploads
  where id = '43000000-0000-4000-8000-000000000003'), 'rejected|malware_detected|true', 'the revocation is recorded');
select is((select count(*)::int from public.audit_events where action = 'upload.access_revoked'
  and target_id = '43000000-0000-4000-8000-000000000003'), 1, 'the revocation is audited');
select is((select recipient_roles::text from public.notification_outbox where notification_type = 'upload.access_revoked'
  and payload_ref ->> 'upload_id' = '43000000-0000-4000-8000-000000000003'), '{owner}', 'the Owner is alerted');
-- (d) processing, then an error for the current attempt: back to quarantine.
select pg_temp.mk('43000000-0000-4000-8000-000000000004', repeat('1', 64));
create temp table a17d as select pg_temp.open('43000000-0000-4000-8000-000000000004') as id;
select pg_temp.scan('43000000-0000-4000-8000-000000000004', (select id from a17d), 'clean', repeat('1', 64));
select is(pg_temp.scan('43000000-0000-4000-8000-000000000004', (select id from a17d), 'error', repeat('1', 64)) ->> 'status',
  'quarantined', 'T-UP-17: a clean result followed by an error returns the file to quarantine');
select is(private.release_upload('43000000-0000-4000-8000-000000000004', repeat('f', 64), 90) ->> 'error', 'not_found',
  'T-UP-17: nothing is released after the error');
select is(pg_temp.scan('43000000-0000-4000-8000-000000000004', (select id from a17d), 'clean', repeat('1', 64)) ->> 'disposition',
  'not_scanning', 'T-UP-18: re-sending the earlier clean result after the error never supersedes it');

-- ---------------------------------------------------------------------------
-- 4. T-UP-18: duplicates and replays
-- ---------------------------------------------------------------------------
select pg_temp.mk('44000000-0000-4000-8000-000000000001', repeat('2', 64));
create temp table a18 as select pg_temp.open('44000000-0000-4000-8000-000000000001') as id;
select pg_temp.scan('44000000-0000-4000-8000-000000000001', (select id from a18), 'clean', repeat('2', 64));
select is(pg_temp.scan('44000000-0000-4000-8000-000000000001', (select id from a18), 'clean', repeat('2', 64)) ->> 'disposition',
  'duplicate', 'T-UP-18: a duplicate clean result is non-authoritative');
select is(pg_temp.scan('44000000-0000-4000-8000-000000000001', (select id from a18), 'malicious', repeat('2', 64)) ->> 'status',
  'rejected', 'a malicious verdict replayed after clean still rejects');
select is(pg_temp.scan('44000000-0000-4000-8000-000000000001', (select id from a18), 'clean', repeat('2', 64)) ->> 'disposition',
  'not_scanning', 'T-UP-18: a clean replay after a malicious verdict never supersedes it');
select is(pg_temp.st('44000000-0000-4000-8000-000000000001'), 'rejected', 'the upload stays rejected');
select is((select count(*)::int from public.upload_scan_results where upload_id = '44000000-0000-4000-8000-000000000001'
  and not authoritative), 2, 'every non-authoritative result is still stored as evidence');

-- ---------------------------------------------------------------------------
-- 5. T-UP-19: exact bytes
-- ---------------------------------------------------------------------------
select pg_temp.mk('45000000-0000-4000-8000-000000000001', repeat('3', 64));
select is(pg_temp.scan('45000000-0000-4000-8000-000000000001', pg_temp.open('45000000-0000-4000-8000-000000000001'), 'clean', repeat('4', 64)) ->> 'error',
  'hash_mismatch', 'T-UP-19: a clean result for different bytes is refused');
select is(pg_temp.st('45000000-0000-4000-8000-000000000001'), 'quarantined', 'T-UP-19: and the file returns to quarantine');
select pg_temp.scan('45000000-0000-4000-8000-000000000001', pg_temp.open('45000000-0000-4000-8000-000000000001'), 'clean', repeat('3', 64));
select is(private.release_upload('45000000-0000-4000-8000-000000000001', repeat('f', 64), 90) ->> 'error', 'source_not_verified',
  'T-UP-19: release requires processing to re-read and confirm the stored object''s hash');
select is(private.confirm_source_hash('45000000-0000-4000-8000-000000000001', repeat('5', 64)) ->> 'error', 'stored_object_changed',
  'T-UP-19: a stored object changed after scanning is detected');
select is(pg_temp.st('45000000-0000-4000-8000-000000000001'), 'rejected', 'T-UP-19: and it blocks release permanently');
-- Malware anywhere for the same bytes blocks another upload of those bytes.
select pg_temp.mk('45000000-0000-4000-8000-000000000002', repeat('6', 64));
select pg_temp.mk('45000000-0000-4000-8000-000000000003', repeat('6', 64), '20000000-0000-4000-8000-0000000000b0');
select pg_temp.scan('45000000-0000-4000-8000-000000000003', pg_temp.open('45000000-0000-4000-8000-000000000003'), 'malicious', repeat('6', 64));
select is(row(pg_temp.st('45000000-0000-4000-8000-000000000002'),
  pg_temp.release('45000000-0000-4000-8000-000000000002', repeat('6', 64)) ->> 'error')::text, '(rejected,not_found)',
  'T-UP-19 / 05 §5.5 rule 3: a malicious result for the same bytes, in any upload, rejects this upload and blocks release (M1)');

-- ---------------------------------------------------------------------------
-- 6. T-UP-15 (single session): lock before insert; delayed results are non-authoritative
-- ---------------------------------------------------------------------------
select ok((select prosrc ~ 'from public\.asset_uploads where id = p_upload_id for update' from pg_proc
  where proname = 'record_scan_result' and pronamespace = 'private'::regnamespace)
  and (select position('for update' in prosrc) < position('insert into public.upload_scan_results' in prosrc) from pg_proc
  where proname = 'record_scan_result' and pronamespace = 'private'::regnamespace),
  'T-UP-15: the upload row is locked before any result is inserted');
select ok((select attidentity = 'a' from pg_attribute where attrelid = 'public.upload_scan_results'::regclass and attname = 'seq'),
  'T-UP-15: the sequence is database-assigned (generated always)');
select throws_ok($$ insert into public.upload_scan_results (seq, upload_id, project_id, scanner, engine_version, verdict,
  scanned_sha256, hash_matches, authoritative, disposition) values (1, '45000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-0000000000a0', 'mock_scanner', '1', 'clean', repeat('6', 64), true, true, 'clean_accepted') $$,
  '428C9', null, 'the sequence can never be chosen by a caller');
select throws_ok($$ insert into public.upload_scan_results (upload_id, project_id, scanner, engine_version, verdict,
  scanned_sha256, hash_matches, authoritative, disposition) values ('45000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-0000000000a0', 'mock_scanner', '1', 'clean', repeat('6', 64), true, false, 'clean_accepted') $$,
  '23514', null, 'authority always matches the disposition');

-- ---------------------------------------------------------------------------
-- 7. T-UP-12: bounded retries with backoff, then the review queue
-- ---------------------------------------------------------------------------
select pg_temp.mk('46000000-0000-4000-8000-000000000001', repeat('7', 64));
select pg_temp.scan('46000000-0000-4000-8000-000000000001', pg_temp.open('46000000-0000-4000-8000-000000000001'), 'error', repeat('7', 64));
select is(pg_temp.st('46000000-0000-4000-8000-000000000001'), 'quarantined', 'T-UP-12: a scanner error keeps the file quarantined');
select is(private.record_content_check('46000000-0000-4000-8000-000000000001', true, 'image/png', null) ->> 'error', 'scan_backoff',
  'T-UP-12: a retry waits for the backoff');
select is((select next_scan_at - now() from public.asset_uploads where id = '46000000-0000-4000-8000-000000000001'),
  interval '1 minute', 'T-UP-12: the first backoff is 1 minute (07 §3 schedule)');
do $$
begin
  for i in 2..5 loop
    update public.asset_uploads set next_scan_at = null where id = '46000000-0000-4000-8000-000000000001';
    perform pg_temp.scan('46000000-0000-4000-8000-000000000001', pg_temp.open('46000000-0000-4000-8000-000000000001'),
      'error', repeat('7', 64));
  end loop;
end;
$$;
update public.asset_uploads set next_scan_at = null where id = '46000000-0000-4000-8000-000000000001';
select is(private.record_content_check('46000000-0000-4000-8000-000000000001', true, 'image/png', null) ->> 'error',
  'scan_retries_exhausted', 'T-UP-12: retries are bounded (5 attempts)');
select is((select count(*)::int from public.upload_scan_attempts where upload_id = '46000000-0000-4000-8000-000000000001'), 5,
  'exactly five attempts were made');
select set_config('request.jwt.claims', '', true);
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok(exists (select 1 from public.operational_queue() q where q ->> 'queue' = 'upload_review'
  and q ->> 'subject_id' = '46000000-0000-4000-8000-000000000001' and q -> 'detail' ->> 'code' = 'scan_retries_exhausted'),
  'T-UP-12: exhausting the retries routes the file to the Upload review queue');
reset role;
select is(pg_temp.st('46000000-0000-4000-8000-000000000001'), 'quarantined', 'T-UP-12: the file is never served');

-- ---------------------------------------------------------------------------
-- 8. T-UP-13 and T-UP-10: 24-hour quarantine flag, 60-day domain warning, decimal units
-- ---------------------------------------------------------------------------
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes, original_name,
  status, quarantine_path, size_bytes, sha256, uploaded_by, created_at)
values ('47000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000b0', gen_random_uuid(), 1, 'logo', 'image/png',
  10, 'old.png', 'quarantined', 'quarantine/20000000-0000-4000-8000-0000000000b0/47000000-0000-4000-8000-000000000001', 10,
  repeat('8', 64), '00000000-0000-4000-8000-0000000000b1', now() - interval '25 hours'),
       ('47000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000b0', gen_random_uuid(), 1, 'logo', 'image/png',
  10, 'new.png', 'quarantined', 'quarantine/20000000-0000-4000-8000-0000000000b0/47000000-0000-4000-8000-000000000002', 10,
  repeat('9', 64), '00000000-0000-4000-8000-0000000000b1', now() - interval '23 hours');
insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
  third_party_charges_disclosed, spotlight_registered, registration_date, registrar_expiry, recorded_by)
values ('20000000-0000-4000-8000-0000000000b0', 'soon.example.test', true, true, true, true, true, current_date - 300,
        current_date + 59, '00000000-0000-4000-8000-000000000002'),
       ('20000000-0000-4000-8000-0000000000b0', 'later.example.test', true, true, true, true, true, current_date - 300,
        current_date + 61, '00000000-0000-4000-8000-000000000002');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select array_agg(q ->> 'subject_id' order by q ->> 'subject_id') from public.operational_queue() q
  where q ->> 'queue' = 'upload_review' and q ->> 'project_id' = '20000000-0000-4000-8000-0000000000b0'
    and q ->> 'subject_id' like '47%'),
  array['47000000-0000-4000-8000-000000000001'], 'T-UP-13: only the file quarantined over 24 hours is flagged');
select is((select array_agg(q -> 'detail' ->> 'domain') from public.operational_queue() q where q ->> 'queue' = 'domain_expiries'),
  array['soon.example.test'], 'T-UP-13: only the domain within 60 days of expiry is warned');
reset role;
-- T-UP-10 (OI-79 item 1): decimal limits, exactly at and one byte over.
create table private.test_financial_fixture_225 (ok boolean);
create or replace function private.project_financial_status(p_project_id uuid) returns private.project_financial_status
language plpgsql stable security definer set search_path = '' as $$
declare
  r private.project_financial_status;
begin
  r := jsonb_populate_record(null::private.project_financial_status, jsonb_build_object('project_id', p_project_id,
    'contract_version', 1, 'implemented', true, 'deposit_verified', true, 'active_billing_holds', '[]'::jsonb));
  return r;
end;
$$;
select is(private.wpc_intake_unlocked('20000000-0000-4000-8000-0000000000a0'), false,
  'T-LC-01: without the payment_authorization_ready attribute intake stays locked (fail closed)');
do $$
begin
  if not exists (select 1 from pg_attribute where attrelid = 'private.project_financial_status'::regclass
                 and attname = 'payment_authorization_ready' and not attisdropped) then
    alter type private.project_financial_status add attribute payment_authorization_ready boolean;
  end if;
end;
$$;
create or replace function private.project_financial_status(p_project_id uuid) returns private.project_financial_status
language sql stable security definer set search_path = '' as $$
  select jsonb_populate_record(null::private.project_financial_status, jsonb_build_object('project_id', p_project_id,
    'contract_version', 1, 'implemented', true, 'deposit_verified', true, 'payment_authorization_ready', true,
    'active_billing_holds', '[]'::jsonb));
$$;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 15000001, 'over.png') ->> 'error',
  'file_too_large', 'T-UP-10: one byte over the decimal 15 MB limit is rejected');
select ok((public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 15000000, 'exact.png') ->> 'ok')::boolean,
  'T-UP-10: exactly 15,000,000 bytes is accepted');
reset role;

-- ---------------------------------------------------------------------------
-- 9. OI-78 (amended): no staff-role holder is a client member; live-verification requester
-- ---------------------------------------------------------------------------
insert into public.project_memberships (project_id, user_id) values
  ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000002'),
  ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000001');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok(not pg_temp.client_member('20000000-0000-4000-8000-0000000000a0'),
  'OI-78: an Admin who also holds a project membership is never a client member');
select is(public.save_intake_draft('20000000-0000-4000-8000-0000000000a0', '{}') ->> 'error', 'forbidden',
  'OI-78: so an Admin with a membership cannot act as the client on intake');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select ok(not pg_temp.client_member('20000000-0000-4000-8000-0000000000a0'),
  'OI-78: neither is the Owner');
reset role;
-- A revoked staff grant whose profile is deactivated is not a client either (no active profile).
update public.staff_roles set status = 'revoked' where user_id = '00000000-0000-4000-8000-000000000002';
select pg_temp.act_as('00000000-0000-4000-8000-000000000002');
select ok(pg_temp.client_member('20000000-0000-4000-8000-0000000000a0'),
  'a former Admin whose staff grant is revoked and who holds a membership is a client (no staff role)');
reset role;
update public.staff_roles set status = 'active' where user_id = '00000000-0000-4000-8000-000000000002';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok(pg_temp.client_member('20000000-0000-4000-8000-0000000000a0'), 'a client with a membership is a client member');
reset role;
-- record_live_verification: requester must be Owner or Admin.
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by)
values ('48000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-0000000000b0', 1, repeat('a', 40), 'd',
        'https://p.example.test', '00000000-0000-4000-8000-000000000002');
insert into public.publication_authorizations (id, project_id, release_id, gate_result, authorized_by)
values ('48000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000b0', '48000000-0000-4000-8000-000000000001',
        '{}', '00000000-0000-4000-8000-000000000001');
insert into public.publication_deployments (id, authorization_id, project_id, release_id, commit_sha, target_ref,
  start_gate_result, started_by, outcome, provider_deployment_id, production_url, recorded_by, recorded_at)
values ('48000000-0000-4000-8000-000000000003', '48000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-0000000000b0',
        '48000000-0000-4000-8000-000000000001', repeat('a', 40), 't', '{}', '00000000-0000-4000-8000-000000000002',
        'succeeded', 'dpl', 'https://b.example.test', '00000000-0000-4000-8000-000000000002', now());
select pg_temp.server();
select is(private.record_live_verification('48000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-0000000000b1',
  repeat('a', 40), true, true, true, true) ->> 'error', 'forbidden', 'OI-78: a client requester is rejected');
select is(private.record_live_verification('48000000-0000-4000-8000-000000000003', null,
  repeat('a', 40), true, true, true, true) ->> 'error', 'forbidden', 'OI-78: a missing requester is rejected');
update public.staff_roles set status = 'revoked' where user_id = '00000000-0000-4000-8000-000000000002';
select is(private.record_live_verification('48000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002',
  repeat('a', 40), true, true, true, true) ->> 'error', 'forbidden', 'OI-78: a requester whose staff grant was revoked is rejected');
update public.staff_roles set status = 'active' where user_id = '00000000-0000-4000-8000-000000000002';
select is(private.record_live_verification('48000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000002',
  repeat('a', 40), true, true, true, true) ->> 'verified', 'true', 'an Admin requester is accepted');
select set_config('request.jwt.claims', '', true);

-- ---------------------------------------------------------------------------
-- 10. T-LC-16 and T-PUB-20
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), 'd1', 'https://p.example.test', '{}') ->> 'error',
  'intake_not_accepted', 'T-LC-16: the Owner cannot release while intake is not accepted_by_staff');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.release_preview('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), 'd1', 'https://p.example.test', '{}') ->> 'error',
  'intake_not_accepted', 'T-LC-16: neither can an Admin');
reset role;
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.proname ~ '(security|release).*(exception|override|waive|bypass)'
    and p.proname <> 'approve_performance_exception'), 0,
  'T-LC-16 / T-PUB-20: no override for the release precondition or for security findings exists');
select ok(not private.security_result_passes(row(gen_random_uuid(), 1, '48000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-0000000000b0', 'v1',
  (select jsonb_agg(jsonb_build_object('key', k, 'severity', case when k = 'security_headers' then 'high' else 'low' end,
     'result', case when k = 'security_headers' then 'fail' else 'pass' end)) from unnest(private.security_checklist_keys()) k),
  '00000000-0000-4000-8000-000000000002', now())::public.security_check_results),
  'T-PUB-20: a single failed high finding fails G7');
select ok(private.security_result_passes(row(gen_random_uuid(), 1, '48000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-0000000000b0', 'v1',
  (select jsonb_agg(jsonb_build_object('key', k, 'severity', 'medium', 'result', case when k = 'security_headers' then 'fail' else 'pass' end))
   from unnest(private.security_checklist_keys()) k),
  '00000000-0000-4000-8000-000000000002', now())::public.security_check_results),
  'a failed medium finding does not fail G7 (06 §2 names high and critical)');

-- ---------------------------------------------------------------------------
-- 11. Dispute evidence interface (04 §15.4; T-ARC-10, WP-C side)
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated', 'private.wpc_dispute_evidence(uuid, uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.wpc_dispute_evidence(uuid, uuid)', 'execute')
  and not has_function_privilege('anon', 'private.wpc_dispute_evidence(uuid, uuid)', 'execute'),
  'no API role can call the evidence interface directly (only WP-B''s definer package)');
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-000000000002', 'role', 'authenticated',
  'aal', 'aal2', 'session_id', (select id from auth.sessions where user_id = '00000000-0000-4000-8000-000000000002' limit 1))::text, true);
select is(private.wpc_dispute_evidence('20000000-0000-4000-8000-0000000000b0') ->> 'error', 'forbidden',
  'T-ARC-10: Admin cannot read dispute evidence (Owner only)');
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-0000000000b1', 'role', 'authenticated',
  'aal', 'aal1', 'session_id', (select id from auth.sessions where user_id = '00000000-0000-4000-8000-0000000000b1' limit 1))::text, true);
select is(private.wpc_dispute_evidence('20000000-0000-4000-8000-0000000000b0') ->> 'error', 'forbidden',
  'T-ARC-10: the client cannot read dispute evidence');
insert into auth.sessions (id, user_id, created_at, updated_at, aal)
values ('49000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', now(), now(), 'aal2');
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-000000000001', 'role', 'authenticated',
  'aal', 'aal2', 'session_id', '49000000-0000-4000-8000-000000000001')::text, true);
select is((select jsonb_build_array(jsonb_array_length(e -> 'preview_releases'), jsonb_array_length(e -> 'publication_authorizations'),
  jsonb_array_length(e -> 'deployments'), jsonb_array_length(e -> 'live_verifications'))
  from (select private.wpc_dispute_evidence('20000000-0000-4000-8000-0000000000b0') e) x), '[1, 1, 1, 1]'::jsonb,
  'T-ARC-10: the Owner receives the release, authorization, deployment, and live verification for the project');
select is((select (e -> 'live_verifications' -> 0 ->> 'served_build_id')
  from (select private.wpc_dispute_evidence('20000000-0000-4000-8000-0000000000b0') e) x), repeat('a', 40),
  'T-ARC-10: records are returned as stored');
select is((select jsonb_array_length(e -> 'preview_releases')
  from (select private.wpc_dispute_evidence('20000000-0000-4000-8000-0000000000a0') e) x), 0,
  'isolation: Project A evidence contains no Project B release');
select is(private.wpc_dispute_evidence('20000000-0000-4000-8000-0000000000a0', '48000000-0000-4000-8000-000000000001') ->> 'error',
  'not_found', 'isolation: a release of another project cannot be requested through Project A');
select ok((select provolatile = 's' from pg_proc where proname = 'wpc_dispute_evidence'),
  'the evidence interface is read-only (STABLE)');
select set_config('request.jwt.claims', '', true);

select * from finish();
rollback;
