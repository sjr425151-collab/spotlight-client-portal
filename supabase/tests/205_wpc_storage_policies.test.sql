-- WP-C storage security (AUTH-004; 05 §4-§5; 03 §9.4; T-UP-05, T-UP-06, T-TEN-03).
-- Evaluates the COMBINED effect of the unchanged Phase 2 policies and the new restrictive
-- WP-C policies on storage.objects, for every role and path class:
--   quarantine/<project>/<id>   never reachable with a user JWT (read, list, write, update, delete)
--   <project>/assets/<id>       readable by that project's members and staff (aal2); never writable
--   <project>/<other>           unchanged Phase 2 behaviour
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, anon, service_role;
grant execute on all functions in schema extensions to authenticated, anon, service_role;
select plan(40);

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
grant execute on function pg_temp.act_as(uuid, text, interval) to authenticated, anon, service_role;
-- Row count of a write run with the caller's privileges (RLS applies).
create function pg_temp.rows_affected(p_sql text) returns integer language plpgsql as $$
declare
  n integer;
begin
  execute p_sql;
  get diagnostics n = row_count;
  return n;
end;
$$;
grant execute on function pg_temp.rows_affected(text) to authenticated, anon, service_role;

-- The Storage API sets this for its own deletes; set here so RLS alone decides deletes.
select set_config('storage.allow_delete_query', 'true', true);

-- Synthetic objects (A = …a0, B = …b0).
insert into storage.objects (bucket_id, name) values
  ('project-assets', 'quarantine/20000000-0000-4000-8000-0000000000a0/q-a'),
  ('project-assets', 'quarantine/20000000-0000-4000-8000-0000000000b0/q-b'),
  ('project-assets', '20000000-0000-4000-8000-0000000000a0/assets/rel-a'),
  ('project-assets', '20000000-0000-4000-8000-0000000000b0/assets/rel-b'),
  ('project-assets', '20000000-0000-4000-8000-0000000000a0/brand/legacy-a');

-- ---------------------------------------------------------------------------
-- 1. Existing Phase 2 policies are unchanged; the WP-C policies only narrow (AUTH-004)
-- ---------------------------------------------------------------------------
select is((select qual from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'project_assets_select'),
  '((bucket_id = ''project-assets''::text) AND private.can_access_project_path(name))',
  'AUTH-004: project_assets_select is unchanged');
select is((select row(permissive, roles::text, cmd)::text from pg_policies
  where schemaname = 'storage' and tablename = 'objects' and policyname = 'project_assets_select'),
  '(PERMISSIVE,{authenticated},SELECT)', 'AUTH-004: project_assets_select keeps its role and command');
select is((select qual from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'project_assets_staff_aal2'),
  '((bucket_id <> ''project-assets''::text) OR (NOT ( SELECT private.is_staff() AS is_staff)) OR (( SELECT private.is_aal2() AS is_aal2) AND ( SELECT private.session_is_active() AS session_is_active)))',
  'AUTH-004: project_assets_staff_aal2 is unchanged');
select is((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects'
  and permissive = 'PERMISSIVE'), 1,
  'AUTH-004: the only permissive storage policy is the Phase 2 select policy (no new grant of access)');
select is((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects'
  and permissive = 'PERMISSIVE' and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')), 0,
  'no permissive write policy exists: no user JWT can write, copy, or move any object');
select is((select array_agg(policyname::text order by policyname) from pg_policies where schemaname = 'storage'
  and tablename = 'objects' and policyname like 'project_assets_%' and permissive = 'RESTRICTIVE'),
  array['project_assets_quarantine_isolated', 'project_assets_released_server_delete_only',
        'project_assets_released_server_update_only', 'project_assets_released_server_write_only',
        'project_assets_staff_aal2'],
  'the WP-C storage policies are all RESTRICTIVE');
select ok((select not public from storage.buckets where id = 'project-assets'), 'the project-assets bucket stays private');
select ok(private.can_access_project_path('quarantine/20000000-0000-4000-8000-0000000000a0/q-a') is false
  or private.can_access_project_path('quarantine/20000000-0000-4000-8000-0000000000a0/q-a') is null,
  'quarantine paths never satisfy the Phase 2 path check (first segment is not a project id)');

-- ---------------------------------------------------------------------------
-- 2. Client A (member of A)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from storage.objects where name like 'quarantine/%'), 0,
  'client A cannot list or read any quarantined object, including their own project''s');
select is((select array_agg(name order by name) from storage.objects where bucket_id = 'project-assets'),
  array['20000000-0000-4000-8000-0000000000a0/assets/rel-a', '20000000-0000-4000-8000-0000000000a0/brand/legacy-a'],
  'client A reads only Project A released and Phase 2 paths (T-UP-06)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', 'quarantine/20000000-0000-4000-8000-0000000000a0/x') $$,
  '42501', null, 'client A cannot write into their own quarantine area');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', '20000000-0000-4000-8000-0000000000a0/assets/x') $$,
  '42501', null, 'client A cannot write into the released area (no self-release)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', 'quarantine/20000000-0000-4000-8000-0000000000b0/x') $$,
  '42501', null, 'client A cannot write into Project B quarantine (T-UP-06)');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', '20000000-0000-4000-8000-0000000000b0/brand/x') $$,
  '42501', null, 'client A cannot upload into Project B paths (T-UP-06)');
select is(pg_temp.rows_affected($q$update storage.objects set name = '20000000-0000-4000-8000-0000000000a0/assets/moved'
  where name = 'quarantine/20000000-0000-4000-8000-0000000000a0/q-a'$q$), 0,
  'client A cannot move a quarantined object into the released area');
select is(pg_temp.rows_affected($q$update storage.objects set metadata = '{"x":1}'
  where name = '20000000-0000-4000-8000-0000000000a0/assets/rel-a'$q$), 0,
  'client A cannot alter a released object');
select is(pg_temp.rows_affected($q$delete from storage.objects where bucket_id = 'project-assets'$q$), 0,
  'client A cannot delete any object');
reset role;

-- ---------------------------------------------------------------------------
-- 3. Client B and a revoked member
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from storage.objects where name like '%0000000000a0%'), 0,
  'client B sees no Project A object in any path class (T-UP-06)');
select is((select count(*)::int from storage.objects where name like 'quarantine/%'), 0,
  'client B sees no quarantined object');
reset role;

update public.project_memberships set status = 'revoked', revoked_at = now()
 where user_id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from storage.objects where bucket_id = 'project-assets'), 0,
  'a revoked member immediately loses access to released objects');
reset role;
update public.project_memberships set status = 'active', revoked_at = null
 where user_id = '00000000-0000-4000-8000-0000000000a1';

-- ---------------------------------------------------------------------------
-- 4. Staff: Admin at aal1, Admin and Owner at aal2
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select is((select count(*)::int from storage.objects where bucket_id = 'project-assets'), 0,
  'Admin at aal1 reads nothing (Phase 2 restrictive aal2 policy still applies)');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select count(*)::int from storage.objects where name like 'quarantine/%'), 0,
  'Admin at aal2 cannot read quarantined (unscanned) objects');
select is((select count(*)::int from storage.objects where name like '%/assets/%'), 2,
  'Admin at aal2 reads released objects of every project');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', '20000000-0000-4000-8000-0000000000a0/assets/x') $$,
  '42501', null, 'Admin cannot write into the released area with a user JWT');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', 'quarantine/20000000-0000-4000-8000-0000000000a0/x') $$,
  '42501', null, 'Admin cannot write into quarantine with a user JWT');
select is(pg_temp.rows_affected($q$update storage.objects set name = '20000000-0000-4000-8000-0000000000a0/assets/q'
  where name like 'quarantine/%'$q$), 0,
  'Admin cannot release a quarantined object by moving it');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is((select count(*)::int from storage.objects where name like 'quarantine/%'), 0,
  'the Owner (fresh MFA) cannot read quarantined objects either');
select is(pg_temp.rows_affected($q$delete from storage.objects where name like '%/assets/%'$q$), 0,
  'the Owner cannot delete released objects with a user JWT');
reset role;

-- ---------------------------------------------------------------------------
-- 5. Anonymous
-- ---------------------------------------------------------------------------
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select is((select count(*)::int from storage.objects), 0, 'anon reads no object');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', 'quarantine/20000000-0000-4000-8000-0000000000a0/x') $$,
  '42501', null, 'anon cannot write into quarantine');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', '20000000-0000-4000-8000-0000000000a0/assets/x') $$,
  '42501', null, 'anon cannot write into the released area');
reset role;

-- ---------------------------------------------------------------------------
-- 6. Function-level release controls (no client or staff self-certification)
-- ---------------------------------------------------------------------------
select ok(not has_function_privilege('authenticated', 'public.record_scan_result(uuid, text, text, text, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'private.record_scan_result(uuid, text, text, text, text, text)', 'execute'),
  'authenticated users cannot execute the scan-result recorder (no self-certification)');
select ok(not has_function_privilege('authenticated', 'public.release_upload(uuid, text, bigint)', 'execute')
  and not has_function_privilege('authenticated', 'private.release_upload(uuid, text, bigint)', 'execute'),
  'authenticated users cannot execute the quarantine release');
select ok(not has_function_privilege('authenticated', 'public.complete_upload(uuid, bigint, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_content_check(uuid, boolean, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.record_processing_outcome(uuid, text, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.purge_failed_uploads()', 'execute'),
  'every pipeline step is service_role only');
select ok(not has_function_privilege('anon', 'public.record_scan_result(uuid, text, text, text, text, text)', 'execute'),
  'anon cannot execute the scan-result recorder');
select ok(has_function_privilege('service_role', 'public.record_scan_result(uuid, text, text, text, text, text)', 'execute'),
  'the server (service_role) records scan results');
select ok(not has_table_privilege('authenticated', 'private.runtime_environment', 'select')
  and not has_table_privilege('service_role', 'private.runtime_environment', 'insert'),
  'no API role can read or change the runtime-environment marker that gates the mock scanner');

-- A JWT claiming service_role does not help a session running as authenticated.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select throws_ok($$ select public.record_scan_result(gen_random_uuid(), 'mock_scanner', '1', 'clean', repeat('a', 64)) $$,
  '42501', null, 'a forged service_role claim on the authenticated role cannot record a scan');
reset role;

-- Defense in depth: even with EXECUTE, the definer refuses non-service-role callers.
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is(private.record_scan_result(gen_random_uuid(), 'mock_scanner', '1', 'clean', repeat('a', 64)) ->> 'error',
  'forbidden', 'the scan recorder itself refuses a caller whose JWT role is not service_role');
select is(private.release_upload(gen_random_uuid(), repeat('a', 64), 1) ->> 'error',
  'forbidden', 'the release function itself refuses a caller whose JWT role is not service_role');

select * from finish();
rollback;
