-- WP-C catalog and cross-tenant isolation for every new table (03 §8-§9, §13; CLAUDE.md §3:
-- every new table ships with cross-tenant isolation tests). T-TEN-01, T-TEN-02, T-ROLE-01
-- extended to the WP-C tables.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(15);

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
grant execute on function pg_temp.act_as(uuid, text) to authenticated;

create temp table wpc_tables (name text primary key, client_visible boolean not null);
insert into wpc_tables values
  ('intake_submissions', true), ('intake_reviews', true), ('upload_exceptions', true), ('asset_uploads', true),
  ('upload_scan_results', false), ('upload_scan_attempts', false), ('preview_drafts', false), ('preview_releases', true),
  ('preview_release_assets', true), ('preview_approvals', true), ('preview_revision_requests', true),
  ('revision_classifications', false), ('approval_outreach_records', false), ('approval_holds', false),
  ('approval_hold_resumption_decisions', false), ('qa_results', false), ('qa_performance_exceptions', false),
  ('security_check_results', false), ('domain_readiness_checks', false), ('client_site_targets', false),
  ('publication_authorizations', false), ('publication_deployments', false), ('deployment_verifications', false),
  ('publication_incidents', false);
grant select on wpc_tables to authenticated;

-- ---------------------------------------------------------------------------
-- 1. Catalog
-- ---------------------------------------------------------------------------
select is((select count(*)::int from wpc_tables w join pg_class c on c.relname = w.name
  and c.relnamespace = 'public'::regnamespace where c.relrowsecurity), 24, 'RLS is enabled on all 24 WP-C tables');
select is((select array_agg(w.name order by w.name) from wpc_tables w
  where has_table_privilege('authenticated', 'public.' || w.name, 'insert')
     or has_table_privilege('authenticated', 'public.' || w.name, 'update')
     or has_table_privilege('authenticated', 'public.' || w.name, 'delete')
     or has_table_privilege('anon', 'public.' || w.name, 'select')
     or has_table_privilege('service_role', 'public.' || w.name, 'insert')
     or has_table_privilege('service_role', 'public.' || w.name, 'update')
     or has_table_privilege('service_role', 'public.' || w.name, 'delete')), null,
  'no API role can write a WP-C table directly; anon cannot read one (definer functions only)');
select is((select count(*)::int from wpc_tables w where
  (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = w.name and p.permissive = 'RESTRICTIVE'
     and p.policyname in (w.name || '_staff_aal2', w.name || '_active_user')) = 2), 24,
  'every WP-C table carries the restrictive staff-aal2 and active-user policies');
select is((select count(*)::int from wpc_tables w join pg_attribute a on a.attrelid = ('public.' || w.name)::regclass
  and a.attname = 'project_id' and a.attnotnull), 24, 'every WP-C table carries a non-null project_id (03 §8)');
select is((select count(*)::int from pg_policies p join wpc_tables w on w.name = p.tablename
  where p.schemaname = 'public' and p.permissive = 'PERMISSIVE' and p.cmd <> 'SELECT'), 0,
  'no permissive write policy exists on any WP-C table');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and p.proname in (select proname from pg_proc p2
    join pg_namespace n2 on n2.oid = p2.pronamespace where n2.nspname = 'private')), 0,
  'every exposed WP-C RPC is a SECURITY INVOKER wrapper (definer code stays in private)');

-- ---------------------------------------------------------------------------
-- 2. One row in every WP-C table for Project A (fixture rows, written as the owner)
-- ---------------------------------------------------------------------------
insert into public.intake_submissions (id, project_id, version, status, content, created_by, submitted_by, submitted_at)
values ('31000000-0000-4000-8000-0000000000a0', '20000000-0000-4000-8000-0000000000a0', 1, 'submitted', '{}',
        '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', now());
insert into public.intake_reviews (project_id, submission_id, decision, reviewed_by) values
  ('20000000-0000-4000-8000-0000000000a0', '31000000-0000-4000-8000-0000000000a0', 'accepted', '00000000-0000-4000-8000-000000000002');
insert into public.upload_exceptions (project_id, kind, extra_files, justification, requested_by)
values ('20000000-0000-4000-8000-0000000000a0', 'quota', 5, 'more photos', '00000000-0000-4000-8000-0000000000a1');
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes, original_name,
  status, quarantine_path, size_bytes, sha256, uploaded_by)
values ('32000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'logo',
  'image/png', 10, 'a.png', 'scanning', 'quarantine/20000000-0000-4000-8000-0000000000a0/32000000-0000-4000-8000-0000000000a1',
  10, repeat('a', 64), '00000000-0000-4000-8000-0000000000a1');
insert into public.upload_scan_attempts (id, upload_id, project_id, attempt_number, expected_sha256)
values ('3b000000-0000-4000-8000-0000000000a1', '32000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0',
        1, repeat('a', 64));
insert into public.upload_scan_results (upload_id, project_id, attempt_id, claimed_attempt_id, scanner, engine_version, verdict,
  scanned_sha256, hash_matches, authoritative, disposition)
values ('32000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', '3b000000-0000-4000-8000-0000000000a1',
        '3b000000-0000-4000-8000-0000000000a1', 'mock_scanner', '1', 'clean', repeat('a', 64), true, true, 'clean_accepted');
insert into public.preview_drafts (project_id, commit_sha, recorded_by)
values ('20000000-0000-4000-8000-0000000000a0', repeat('a', 40), '00000000-0000-4000-8000-000000000002');
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 1, repeat('a', 40), 'd1',
        'https://p.example.test', '00000000-0000-4000-8000-000000000002');
update public.asset_uploads set status = 'processing' where id = '32000000-0000-4000-8000-0000000000a1';
update public.asset_uploads set status = 'available', released_path = project_id || '/assets/' || id,
  released_sha256 = sha256, released_bytes = 10 where id = '32000000-0000-4000-8000-0000000000a1';
insert into public.preview_release_assets (release_id, upload_id, project_id)
values ('34000000-0000-4000-8000-0000000000a1', '32000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0');
insert into public.preview_approvals (id, release_id, project_id, user_id)
values ('36000000-0000-4000-8000-0000000000a1', '34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0',
        '00000000-0000-4000-8000-0000000000a1');
insert into public.preview_revision_requests (id, release_id, project_id, user_id, comments)
values ('37000000-0000-4000-8000-0000000000a1', '34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0',
        '00000000-0000-4000-8000-0000000000a1', 'change');
insert into public.revision_classifications (revision_request_id, project_id, scope, classified_by)
values ('37000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'in_scope', '00000000-0000-4000-8000-000000000002');
insert into public.approval_outreach_records (id, project_id, release_id, kind, channel, occurred_on, summary, recorded_by)
values ('38000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1',
        'reminder_1', 'email', current_date, 'sent', '00000000-0000-4000-8000-000000000002');
insert into public.approval_holds (id, project_id, release_id, placed_by, reason, outreach_evidence_ids)
values ('35000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1',
        '00000000-0000-4000-8000-000000000002', 'fixture', array['38000000-0000-4000-8000-0000000000a1'::uuid]);
insert into public.approval_hold_resumption_decisions (hold_id, project_id, decision, decided_by)
values ('35000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'remain_held', '00000000-0000-4000-8000-000000000002');
insert into public.qa_results (release_id, project_id, checklist_version, items, recorded_by)
select '34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1',
  jsonb_agg(jsonb_build_object('key', a, 'area', a, 'result', 'pass')), '00000000-0000-4000-8000-000000000002'
from unnest(private.qa_mandatory_areas()) a;
insert into public.qa_performance_exceptions (release_id, project_id, measured_values, reason, approved_by)
values ('34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', '{"lcp_ms": 1}', 'r',
        '00000000-0000-4000-8000-000000000001');
insert into public.security_check_results (release_id, project_id, checklist_version, items, recorded_by)
select '34000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 'v1',
  jsonb_agg(jsonb_build_object('key', k, 'severity', 'high', 'result', 'pass')), '00000000-0000-4000-8000-000000000002'
from unnest(private.security_checklist_keys()) k;
insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
  third_party_charges_disclosed, spotlight_registered, recorded_by)
values ('20000000-0000-4000-8000-0000000000a0', 'a.example.test', true, true, true, true, false, '00000000-0000-4000-8000-000000000002');
insert into public.client_site_targets (project_id, target_ref, registered_by)
values ('20000000-0000-4000-8000-0000000000a0', 'site-a', '00000000-0000-4000-8000-000000000001');
insert into public.publication_authorizations (id, project_id, release_id, gate_result, authorized_by)
values ('39000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', '34000000-0000-4000-8000-0000000000a1',
        '{}', '00000000-0000-4000-8000-000000000001');
insert into public.publication_deployments (id, authorization_id, project_id, release_id, commit_sha, target_ref,
  start_gate_result, started_by, outcome, provider_deployment_id, production_url, recorded_by, recorded_at)
values ('3a000000-0000-4000-8000-0000000000a1', '39000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0',
        '34000000-0000-4000-8000-0000000000a1', repeat('a', 40), 'site-a', '{}', '00000000-0000-4000-8000-000000000002',
        'succeeded', 'dpl', 'https://a.example.test', '00000000-0000-4000-8000-000000000002', now());
insert into public.deployment_verifications (deployment_id, project_id, served_build_id, http_ok, tls_ok, key_pages_ok,
  forms_ok, build_matches, verified, requested_by)
values ('3a000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', repeat('a', 40), true, true, true,
        true, true, true, '00000000-0000-4000-8000-000000000002');
insert into public.publication_incidents (project_id, deployment_id, severity, kind, summary)
values ('20000000-0000-4000-8000-0000000000a0', '3a000000-0000-4000-8000-0000000000a1', 'sev3', 'verification_failed', 'x');

create function pg_temp.visible_tables() returns text[] language plpgsql as $$
declare
  w record;
  n integer;
  v text[] := '{}';
begin
  for w in select name from wpc_tables order by name loop
    execute format('select count(*) from public.%I', w.name) into n;
    if n > 0 then v := v || w.name; end if;
  end loop;
  return v;
end;
$$;
create function pg_temp.writable_tables() returns text[] language plpgsql as $$
declare
  w record;
  v text[] := '{}';
begin
  for w in select name from wpc_tables order by name loop
    begin
      execute format('update public.%I set project_id = project_id', w.name);
      v := v || w.name;
    exception when insufficient_privilege then
      null;
    end;
    begin
      execute format('delete from public.%I', w.name);
      v := v || (w.name || ':delete');
    exception when insufficient_privilege then
      null;
    end;
  end loop;
  return v;
end;
$$;
grant execute on function pg_temp.visible_tables(), pg_temp.writable_tables() to authenticated;

select is((select count(*)::int from wpc_tables w where (xpath('/row/c/text()',
  query_to_xml(format('select count(*) as c from public.%I', w.name), false, true, '')))[1]::text::int > 0), 24,
  'fixture: every WP-C table has a Project A row');

-- ---------------------------------------------------------------------------
-- 3. Cross-tenant and role visibility (T-TEN-01, T-TEN-02, T-ROLE-01)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(pg_temp.visible_tables(), '{}'::text[], 'T-TEN-01: client B sees no Project A row in any WP-C table');
select is(pg_temp.writable_tables(), '{}'::text[], 'T-TEN-02: client B cannot update or delete any WP-C table');
reset role;

select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(pg_temp.visible_tables(), (select array_agg(name order by name) from wpc_tables where client_visible),
  'client A sees exactly the client-visible WP-C tables for their own project, and no staff-only table');
select is(pg_temp.writable_tables(), '{}'::text[], 'T-ROLE-01: client A cannot write any WP-C table directly');
reset role;

select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select is(pg_temp.visible_tables(), '{}'::text[], 'Admin at aal1 sees nothing (03 §7)');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(pg_temp.visible_tables(), (select array_agg(name order by name) from wpc_tables),
  'Admin at aal2 reads every WP-C table (all are non-financial, OI-72)');
select is(pg_temp.writable_tables(), '{}'::text[], 'Admin cannot write any WP-C table directly (definer functions only)');
reset role;

update public.profiles set status = 'deactivated' where id = '00000000-0000-4000-8000-0000000000a1';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(pg_temp.visible_tables(), '{}'::text[], 'a deactivated client sees nothing immediately (T-AUTH-09 pattern)');
reset role;

select * from finish();
rollback;
