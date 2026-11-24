-- WP-C corrections from the PR #19 review (H1, M1, and the M2 database side):
--   H1  durable deletion of revoked released objects: pending rows written with the
--       revocation, leased and bounded attempts, interruption recovery, audit, Owner
--       alerts, and the Owner's manual retry; delivery decided by the database
--   M1  malicious bytes identified by the server-verified stored hash: identical bytes are
--       revoked or rejected in every project, a scanner-reported hash never acts on other
--       uploads, release refuses known malicious bytes, and alerts stay within their tenant
--   M2  a refused upload request is audited in its project; a caller without access leaves
--       no record there
-- Real concurrency (release racing a malicious verdict; racing claims) runs in
-- tests/integration/wpc-delivery.test.ts.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, anon, service_role;
grant execute on all functions in schema extensions to authenticated, anon, service_role;
select plan(58);

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
grant execute on function pg_temp.act_as(uuid, text) to authenticated, anon, service_role;
create function pg_temp.server() returns void language sql as $$
  select set_config('request.jwt.claims', '{"role":"service_role"}', true);
$$;

-- Fixture uploads. A = …a0 (client …a1), B = …b0 (client …b1).
create function pg_temp.mk(p_id uuid, p_sha text, p_project uuid, p_status text default 'quarantined')
returns uuid language sql as $$
  insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
    original_name, status, quarantine_path, released_path, size_bytes, sha256, released_sha256, released_bytes,
    completed_at, uploaded_by, rejection_code)
  values (p_id, p_project, gen_random_uuid(), 1, 'logo', 'image/png', 100, 'f.png', p_status::public.upload_status,
    'quarantine/' || p_project || '/' || p_id,
    case when p_status = 'available' then p_project || '/assets/' || p_id end, 100, p_sha,
    case when p_status = 'available' then p_sha end, case when p_status = 'available' then 100 end, now(),
    case when p_project = '20000000-0000-4000-8000-0000000000a0' then '00000000-0000-4000-8000-0000000000a1'::uuid
         else '00000000-0000-4000-8000-0000000000b1'::uuid end,
    case when p_status = 'rejected' then 'content_invalid' end)
  returning id;
$$;
create function pg_temp.open(p_id uuid) returns uuid language sql as $$
  select (private.record_content_check(p_id, true, 'image/png', null) ->> 'attempt_id')::uuid;
$$;
create function pg_temp.st(p_id uuid) returns text language sql as $$
  select status::text from public.asset_uploads where id = p_id;
$$;
-- Read as the table owner, so a role under test can name a row it may not see.
create function pg_temp.del(p_upload uuid) returns public.asset_object_deletions language sql security definer as $$
  select * from public.asset_object_deletions where upload_id = p_upload;
$$;
grant execute on function pg_temp.del(uuid) to authenticated;
create function pg_temp.claim(p_upload uuid) returns jsonb language sql as $$
  select private.claim_object_deletions(array[(pg_temp.del(p_upload)).id], 10) -> 'claimed';
$$;
create function pg_temp.report(p_upload uuid, p_attempt integer, p_deleted boolean, p_error text default 'storage_error')
returns jsonb language sql as $$
  select private.record_object_deletion((pg_temp.del(p_upload)).id, p_attempt, p_deleted, p_error);
$$;
-- Makes a pending row due now (the backoff has elapsed).
create function pg_temp.due(p_upload uuid) returns void language sql as $$
  update public.asset_object_deletions set next_attempt_at = now() - interval '1 second' where upload_id = p_upload;
$$;

-- ---------------------------------------------------------------------------
-- 1. Privileges
-- ---------------------------------------------------------------------------
select ok(not has_table_privilege('authenticated', 'private.malicious_content', 'select')
  and not has_table_privilege('anon', 'private.malicious_content', 'select')
  and not has_table_privilege('service_role', 'private.malicious_content', 'select'),
  'M1: no API role can read the malicious-content record (no cross-tenant content disclosure)');
select ok(not has_table_privilege('authenticated', 'public.asset_object_deletions', 'insert')
  and not has_table_privilege('authenticated', 'public.asset_object_deletions', 'update')
  and not has_table_privilege('service_role', 'public.asset_object_deletions', 'update')
  and not has_table_privilege('anon', 'public.asset_object_deletions', 'select'),
  'H1: deletion records are written only by definer functions');
select ok(not has_function_privilege('authenticated', 'public.claim_object_deletions(uuid[], integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_object_deletion(uuid, integer, boolean, text)', 'execute')
  and not has_function_privilege('anon', 'public.retry_object_deletion(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.claim_object_deletions(uuid[], integer)', 'execute')
  and has_function_privilege('authenticated', 'public.retry_object_deletion(uuid)', 'execute'),
  'H1: claiming and reporting deletions is service_role only; the retry RPC re-authorizes inside');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is(private.claim_object_deletions(null, 10) ->> 'error', 'forbidden',
  'H1: the claim function itself refuses a non-service-role caller');

-- ---------------------------------------------------------------------------
-- 2. M1: identical bytes in several uploads and projects
-- ---------------------------------------------------------------------------
-- H = '7'x64. Released in A and in B; quarantined in A; scanning in B; processing in A;
-- already rejected (another reason) in A; the scanned source in B. C holds other bytes ('8').
select pg_temp.mk('51000000-0000-4000-8000-0000000000a1', repeat('7', 64), '20000000-0000-4000-8000-0000000000a0', 'available');
select pg_temp.mk('51000000-0000-4000-8000-0000000000b1', repeat('7', 64), '20000000-0000-4000-8000-0000000000b0', 'available');
select pg_temp.mk('51000000-0000-4000-8000-0000000000a2', repeat('7', 64), '20000000-0000-4000-8000-0000000000a0');
select pg_temp.mk('51000000-0000-4000-8000-0000000000b2', repeat('7', 64), '20000000-0000-4000-8000-0000000000b0');
select pg_temp.mk('51000000-0000-4000-8000-0000000000a3', repeat('7', 64), '20000000-0000-4000-8000-0000000000a0');
select pg_temp.mk('51000000-0000-4000-8000-0000000000a4', repeat('7', 64), '20000000-0000-4000-8000-0000000000a0', 'rejected');
select pg_temp.mk('51000000-0000-4000-8000-0000000000b3', repeat('7', 64), '20000000-0000-4000-8000-0000000000b0');
select pg_temp.mk('51000000-0000-4000-8000-0000000000c1', repeat('8', 64), '20000000-0000-4000-8000-0000000000a0', 'available');
select pg_temp.server();
select pg_temp.open('51000000-0000-4000-8000-0000000000b2');
select private.record_scan_result('51000000-0000-4000-8000-0000000000a3', pg_temp.open('51000000-0000-4000-8000-0000000000a3'),
  'mock_scanner', '1', 'clean', repeat('7', 64));
select is(pg_temp.st('51000000-0000-4000-8000-0000000000a3'), 'processing', 'fixture: one identical upload is processing');

-- The verdict for B3 reports a different hash, which happens to be C's bytes.
create temp table verdict as
select private.record_scan_result('51000000-0000-4000-8000-0000000000b3', pg_temp.open('51000000-0000-4000-8000-0000000000b3'),
  'mock_scanner', '1', 'malicious', repeat('8', 64), 'EICAR') as r;
select is((select (r ->> 'revoked_count')::int || '/' || (r ->> 'rejected_count')::int from verdict), '2/4',
  'M1: one verdict revokes both released copies and rejects the four non-final uploads (source included)');
select is((select array_agg(id::text order by id) from public.asset_uploads where sha256 = repeat('7', 64)
  and status = 'rejected' and malware_detected and revoked_at is not null),
  array['51000000-0000-4000-8000-0000000000a1', '51000000-0000-4000-8000-0000000000b1'],
  'M1: identical released bytes in every project are revoked (05 §5.5 rule 3)');
select is((select array_agg(id::text order by id) from public.asset_uploads where sha256 = repeat('7', 64)
  and status = 'rejected' and malware_detected and rejection_code = 'malware_detected' and revoked_at is null),
  array['51000000-0000-4000-8000-0000000000a2', '51000000-0000-4000-8000-0000000000a3',
        '51000000-0000-4000-8000-0000000000b2', '51000000-0000-4000-8000-0000000000b3'],
  'M1: identical quarantined, scanning, and processing uploads are rejected for malware');
select is((select count(*)::int from public.upload_scan_attempts a join public.asset_uploads u on u.id = a.upload_id
  where u.sha256 = repeat('7', 64) and a.closed_at is null), 0,
  'M1: no scan attempt for those bytes stays open (a late clean result cannot act)');
select ok((select malware_detected and rejection_code = 'content_invalid' from public.asset_uploads
  where id = '51000000-0000-4000-8000-0000000000a4'),
  'M1: an upload already rejected for another reason is flagged, so it can never be released');
select is((select first_upload_id::text from private.malicious_content where sha256 = repeat('7', 64)),
  '51000000-0000-4000-8000-0000000000b3', 'M1: the stored hash is recorded permanently, with its source');
select is(row(pg_temp.st('51000000-0000-4000-8000-0000000000c1'),
  exists (select 1 from private.malicious_content where sha256 = repeat('8', 64)))::text, '(available,f)',
  'M1: the scanner-reported hash never revokes or blocks another upload''s bytes (identity is the stored hash)');
select is((select row(scanned_sha256 = repeat('8', 64), hash_matches, disposition)::text from public.upload_scan_results
  where upload_id = '51000000-0000-4000-8000-0000000000b3' and verdict = 'malicious'), '(t,f,malicious_accepted)',
  'M1: the reported hash and its mismatch are kept as evidence; the verdict still acts on the stored bytes');
select is((select array_agg(row(upload_id, reason, status, attempts, object_path = project_id || '/assets/' || upload_id)::text
  order by upload_id) from public.asset_object_deletions where upload_id::text like '51000000-%'),
  array['(51000000-0000-4000-8000-0000000000a1,identical_malicious_content,pending,0,t)',
        '(51000000-0000-4000-8000-0000000000b1,identical_malicious_content,pending,0,t)'],
  'H1/M1: every revoked object gets its own durable pending deletion, in the same transaction');
select is((select array_agg(r) from (select jsonb_array_elements_text(r -> 'deletion_ids') r from verdict) x),
  (select array_agg(id::text) from public.asset_object_deletions where upload_id::text like '51000000-%'),
  'H1: the verdict returns the deletion ids so the server deletes at once');

-- Tenant isolation of alerts, notifications, and audit (M1).
select is((select array_agg(row(project_id, recipient_user_ids::text, recipient_roles::text)::text order by project_id)
  from public.notification_outbox where notification_type = 'upload.rejected'
   and payload_ref ->> 'upload_id' in ('51000000-0000-4000-8000-0000000000a1', '51000000-0000-4000-8000-0000000000b1')),
  array['(20000000-0000-4000-8000-0000000000a0,{00000000-0000-4000-8000-0000000000a1},{staff})',
        '(20000000-0000-4000-8000-0000000000b0,{00000000-0000-4000-8000-0000000000b1},{staff})'],
  'M1: each client is notified only about their own revoked upload, in their own project');
select is((select count(*)::int from public.notification_outbox n
  where n.project_id = '20000000-0000-4000-8000-0000000000a0' and n.created_at >= now() - interval '1 hour'
    and (n.payload_ref::text like '%0000000000b0%' or n.payload_ref::text like '%51000000-0000-4000-8000-0000000000b%')), 0,
  'M1: no Project A notification names a Project B project or upload');
select is((select count(*)::int from public.audit_events e
  where e.project_id = '20000000-0000-4000-8000-0000000000a0'
    and (e.summary::text like '%0000000000b0%' or e.summary::text like '%51000000-0000-4000-8000-0000000000b%'
         or e.target_id like '51000000-0000-4000-8000-0000000000b%')), 0,
  'M1: no Project A audit event names a Project B project or upload');
select is((select summary ->> 'reason' from public.audit_events where action = 'upload.access_revoked'
  and target_id = '51000000-0000-4000-8000-0000000000a1'), 'identical_malicious_content',
  'M1: the revocation of identical bytes is audited in the affected project');
select is((select count(*)::int from public.notification_outbox where notification_type = 'upload.access_revoked'
  and payload_ref ->> 'upload_id' like '51000000-%' and recipient_roles = array['owner']::public.notification_recipient_role[]), 2,
  'M1: the Owner is alerted once per revoked upload');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from public.asset_uploads where id::text like '51000000-0000-4000-8000-0000000000b%'), 0,
  'M1: client A sees none of Project B''s affected uploads');
reset role;
select pg_temp.server();

-- Permanent rejection: the same bytes uploaded again are rejected at the content check.
select pg_temp.mk('51000000-0000-4000-8000-0000000000a5', repeat('7', 64), '20000000-0000-4000-8000-0000000000a0');
select is(private.record_content_check('51000000-0000-4000-8000-0000000000a5', true, 'image/png', null) ->> 'status', 'rejected',
  'M1: known malicious bytes uploaded again are rejected before scanning');
select ok((select malware_detected and rejection_code = 'malware_detected' from public.asset_uploads
  where id = '51000000-0000-4000-8000-0000000000a5'), 'M1: and flagged for malware, permanently');

-- Release refuses known malicious bytes on its own (here the hash is recorded directly, as a
-- concurrent verdict that committed first would have).
select pg_temp.mk('51000000-0000-4000-8000-0000000000a6', repeat('9', 64), '20000000-0000-4000-8000-0000000000a0');
select private.record_scan_result('51000000-0000-4000-8000-0000000000a6', pg_temp.open('51000000-0000-4000-8000-0000000000a6'),
  'mock_scanner', '1', 'clean', repeat('9', 64));
select private.confirm_source_hash('51000000-0000-4000-8000-0000000000a6', repeat('9', 64));
insert into private.malicious_content (sha256, first_upload_id) values (repeat('9', 64), '51000000-0000-4000-8000-0000000000b3');
select is(private.release_upload('51000000-0000-4000-8000-0000000000a6', repeat('9', 64), 100) ->> 'error', 'malware_detected',
  'M1: release refuses bytes recorded as malicious, whichever upload they were found in');

-- A malicious verdict for an upload already rejected for another reason still revokes
-- identical released bytes.
select pg_temp.mk('51000000-0000-4000-8000-0000000000a7', repeat('6', 64), '20000000-0000-4000-8000-0000000000a0', 'rejected');
select pg_temp.mk('51000000-0000-4000-8000-0000000000b7', repeat('6', 64), '20000000-0000-4000-8000-0000000000b0', 'available');
select is(private.record_scan_result('51000000-0000-4000-8000-0000000000a7', null, 'mock_scanner', '1', 'malicious',
  repeat('6', 64)) ->> 'revoked_count', '1', 'M1: a verdict on a rejected upload revokes identical released bytes elsewhere');

-- ---------------------------------------------------------------------------
-- 3. H1: deletion lifecycle
-- ---------------------------------------------------------------------------
select is((select jsonb_agg(c - 'id' order by c ->> 'object_path')
  from jsonb_array_elements(private.claim_object_deletions(
    array[(pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id, (pg_temp.del('51000000-0000-4000-8000-0000000000b1')).id], 10)
    -> 'claimed') c),
  '[{"attempt": 1, "object_path": "20000000-0000-4000-8000-0000000000a0/assets/51000000-0000-4000-8000-0000000000a1"},
    {"attempt": 1, "object_path": "20000000-0000-4000-8000-0000000000b0/assets/51000000-0000-4000-8000-0000000000b1"}]'::jsonb,
  'H1: due deletions are claimed with a counted attempt');
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1'), '[]'::jsonb,
  'H1: a row under a live lease is not claimed twice');
select is(pg_temp.report('51000000-0000-4000-8000-0000000000a1', 1, false) ->> 'status', 'pending',
  'H1: a failed attempt keeps the deletion pending');
select ok((select status = 'pending' and last_error = 'storage_error' and leased_until is null
  and next_attempt_at > now() from public.asset_object_deletions where upload_id = '51000000-0000-4000-8000-0000000000a1'),
  'H1: and backs off before the next attempt (07 §3 schedule)');
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1'), '[]'::jsonb, 'H1: a row in backoff is not claimed');
select ok(exists (select 1 from public.audit_events where action = 'upload.object_deletion_failed'
    and target_id = (pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id::text
    and summary ->> 'error' = 'storage_error' and project_id = '20000000-0000-4000-8000-0000000000a0')
  and exists (select 1 from public.notification_outbox where notification_type = 'upload.object_deletion_failed'
    and idempotency_key = 'upload.object_deletion_failed:' || (pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id || ':1'
    and recipient_roles = array['owner']::public.notification_recipient_role[]),
  'H1: the failure is audited and alerts the Owner');
select is(pg_temp.report('51000000-0000-4000-8000-0000000000a1', 1, false) ->> 'error', 'stale_attempt',
  'H1: a repeated or stale failure report changes nothing');
select is(pg_temp.report('51000000-0000-4000-8000-0000000000b1', 1, true) ->> 'status', 'deleted',
  'H1: a confirmed deletion completes the row');
select ok(exists (select 1 from public.audit_events where action = 'upload.object_deleted'
  and target_id = (pg_temp.del('51000000-0000-4000-8000-0000000000b1')).id::text
  and project_id = '20000000-0000-4000-8000-0000000000b0'), 'H1: the deletion is audited in its own project');
select is(pg_temp.report('51000000-0000-4000-8000-0000000000b1', 1, true) ->> 'already', 'true',
  'H1: reporting a deletion again is idempotent');

-- Process interruption: an attempt claimed but never reported.
select pg_temp.due('51000000-0000-4000-8000-0000000000a1');
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1') -> 0 ->> 'attempt', '2', 'H1: attempt 2 is claimed');
update public.asset_object_deletions set leased_until = now() - interval '1 second'
 where upload_id = '51000000-0000-4000-8000-0000000000a1'; -- the worker died; its lease expired
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1') -> 0 ->> 'attempt', '3',
  'H1: an interrupted attempt is recovered: the row is claimed again once its lease expires');
select is((pg_temp.del('51000000-0000-4000-8000-0000000000a1')).last_error, 'interrupted',
  'H1: and the interruption is recorded');
-- Attempts 3 to 5 fail: the row fails and alerts the Owner as exhausted.
select pg_temp.report('51000000-0000-4000-8000-0000000000a1', 3, false);
select pg_temp.due('51000000-0000-4000-8000-0000000000a1');
select pg_temp.claim('51000000-0000-4000-8000-0000000000a1');
select pg_temp.report('51000000-0000-4000-8000-0000000000a1', 4, false);
select pg_temp.due('51000000-0000-4000-8000-0000000000a1');
select pg_temp.claim('51000000-0000-4000-8000-0000000000a1');
select is(pg_temp.report('51000000-0000-4000-8000-0000000000a1', 5, false, 'still_present') ->> 'status', 'failed',
  'H1: retries are bounded: after the fifth failed attempt the deletion fails');
select ok(exists (select 1 from public.notification_outbox where notification_type = 'upload.object_deletion_failed'
  and payload_ref ->> 'deletion_id' = (pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id::text
  and (payload_ref ->> 'exhausted')::boolean), 'H1: the Owner is alerted that the deletion needs a retry');
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1'), '[]'::jsonb, 'H1: a failed deletion is not claimed again on its own');
-- Interrupted on the last attempt: failed and alerted, never left pending.
update public.asset_object_deletions set attempts = 5, leased_until = now() - interval '1 second'
 where upload_id = '51000000-0000-4000-8000-0000000000b7';
select pg_temp.claim('51000000-0000-4000-8000-0000000000b7');
select is((select row(status, last_error)::text from public.asset_object_deletions
  where upload_id = '51000000-0000-4000-8000-0000000000b7'), '(failed,interrupted)',
  'H1: a row interrupted on its last attempt fails and alerts instead of staying pending');

-- Owner retry (until DEP-17 scheduling).
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id) ->> 'error', 'forbidden',
  'H1: a client cannot retry a deletion');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id) ->> 'error', 'forbidden',
  'H1: the Admin cannot retry a deletion (Owner only)');
select is((select count(*)::int from public.asset_object_deletions where upload_id::text like '51000000-%'), 3,
  'H1: staff at aal2 see the deletion records');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal1');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id) ->> 'error', 'forbidden',
  'H1: the Owner at aal1 cannot retry');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id) ->> 'ok', 'true',
  'H1: the Owner at aal2 retries a failed deletion');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000b1')).id) ->> 'error', 'already_deleted',
  'H1: a completed deletion cannot be retried');
reset role;
select ok(exists (select 1 from public.audit_events where action = 'upload.object_deletion_retried'
  and actor_user_id = '00000000-0000-4000-8000-000000000001'
  and target_id = (pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id::text), 'H1: the Owner retry is audited');
select pg_temp.server();
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1') -> 0 ->> 'attempt', '6',
  'H1: the retry allows exactly one more attempt');
select is(pg_temp.claim('51000000-0000-4000-8000-0000000000a1'), '[]'::jsonb, 'H1: and no other');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000a1')).id) ->> 'error', 'deletion_in_progress',
  'H1: a retry is refused while an attempt holds a live lease');
reset role;
update public.asset_object_deletions set manual_retries = 10 where upload_id = '51000000-0000-4000-8000-0000000000b7';
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.retry_object_deletion((pg_temp.del('51000000-0000-4000-8000-0000000000b7')).id) ->> 'error', 'retry_limit',
  'H1: Owner retries are bounded');
reset role;
select throws_ok($$ update public.asset_object_deletions set status = 'pending', completed_at = null
  where upload_id = '51000000-0000-4000-8000-0000000000b1' $$, '42501', null,
  'H1: a completed deletion record never changes');

-- ---------------------------------------------------------------------------
-- 4. M2 (database side): refused upload requests
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'application/x-msdownload', 4, 'tool.exe') ->> 'error',
  'type_not_allowed', 'T-UP-01: a disallowed type is refused');
reset role;
select is((select row(actor_user_id, summary ->> 'code', summary ->> 'declared_mime')::text from public.audit_events
  where action = 'upload.refused' and project_id = '20000000-0000-4000-8000-0000000000a0'),
  '(00000000-0000-4000-8000-0000000000a1,type_not_allowed,application/x-msdownload)',
  'M2: the refusal is audited in the project, with the caller and reason; nothing is reserved');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.request_upload('20000000-0000-4000-8000-0000000000a0', 'logo', 'image/png', 4, 'x.png') ->> 'error',
  'forbidden', 'T-UP-06: client B cannot request an upload into Project A');
reset role;
select is((select count(*)::int from public.audit_events where project_id = '20000000-0000-4000-8000-0000000000a0'
  and actor_user_id = '00000000-0000-4000-8000-0000000000b1'), 0,
  'M2: a caller without access leaves no record in the other project');

select * from finish();
rollback;
