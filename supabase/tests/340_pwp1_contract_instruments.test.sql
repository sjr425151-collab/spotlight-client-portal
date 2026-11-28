-- PWP-1 (AUTH-021; 04 §4A v0.11.0): contractual instruments, bundles, governance events and
-- withdrawal. T-CON-01, T-CON-03 to T-CON-06, T-CON-08, T-CON-11, T-CON-12 (serial parts; the
-- two-session parts, T-CON-02 and the withdrawal side of T-CON-07, run in the integration suite),
-- golden vectors (OI-109) and requirement F. Every instrument, title and scope string here is a
-- synthetic, non-legal test string, local and CI only, inside this rolled-back transaction. The
-- synthetic agreement holds only the approved 04 §3.1 clause text.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(172);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal2', p_fresh boolean default true)
returns uuid language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform pg_temp.use_session(p_uid, v_sid, p_aal, p_fresh);
  return v_sid;
end;
$$;
create function pg_temp.use_session(p_uid uuid, p_sid uuid, p_aal text default 'aal2', p_fresh boolean default true)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', p_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.use_stale(p_uid uuid, p_sid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2',
    'session_id', p_sid, 'amr', jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now() - interval '10 minutes')::bigint)))::text, true);
  set local role authenticated;
end;
$$;
create temp table ids (k text primary key, v text);
grant select, insert, update on ids to authenticated, service_role;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;
create temp table mark as select coalesce(max(id), 0) as last_id from public.audit_events;
create function pg_temp.audits(p_action text) returns integer language sql as $$
  select count(*)::int from public.audit_events where id > (select last_id from mark) and action = p_action
$$;
create function pg_temp.last_reason(p_action text) returns text language sql as $$
  select summary ->> 'reason' from public.audit_events where id > (select last_id from mark) and action = p_action
  order by id desc limit 1
$$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;
create function pg_temp.owner() returns void language sql as $$
  select pg_temp.use_session('00000000-0000-4000-8000-000000000001', pg_temp.id('own'), 'aal2', true)
$$;
create function pg_temp.resolved(p_key text) returns text language sql as $$
  select coalesce((select bundle_version::text || ':' || is_test_fixture::text from private.current_contract_bundle(p_key)), '')
$$;
-- Classification helpers (consistent pairs; OI-115/OI-123 pattern).
create function pg_temp.classify(p_env text) returns void language plpgsql as $$
begin
  delete from private.runtime_environment;
  delete from private.environment_settings;
  if p_env in ('development', 'test') then
    insert into private.runtime_environment (app_env) values (p_env);
    insert into private.environment_settings (app_env) values (p_env);
  elsif p_env in ('preview', 'staging') then
    insert into private.environment_settings (app_env) values (p_env);
  elsif p_env = 'inconsistent' then
    insert into private.runtime_environment (app_env) values ('development');
    insert into private.environment_settings (app_env) values ('staging');
  end if; -- 'production': both absent
end;
$$;
create function pg_temp.isha(p_kind text, p_pkg text, p_v integer, p_t text, p_b text, p_p text[]) returns text
language sql as $$ select private.contract_instrument_sha256(p_kind, p_pkg, p_v, p_t, p_b, p_p) $$;
grant execute on function pg_temp.isha(text, text, integer, text, text, text[]) to authenticated;
grant execute on function private.contract_instrument_sha256(text, text, integer, text, text, text[]) to authenticated;

-- Sessions.
insert into ids select 'own', pg_temp.act_as('00000000-0000-4000-8000-000000000001');
reset role;
insert into ids select 'adm', pg_temp.act_as('00000000-0000-4000-8000-000000000002');
reset role;
insert into ids select 'sal', pg_temp.act_as('00000000-0000-4000-8000-000000000005');
reset role;
insert into ids select 'cli', pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
reset role;

-- ===========================================================================
-- 1. Objects, privileges, immutability and isolation
-- ===========================================================================
select is((select count(*)::int from unnest(array['anon', 'authenticated', 'service_role', 'public']) r,
  unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p,
  unnest(array['private.contract_instrument_versions', 'private.contract_bundles', 'private.contract_bundle_approvals',
    'private.contract_bundle_eligibility']) t
  where has_table_privilege(r, t, p)), 0, 'no API role or PUBLIC holds any privilege on the four PWP-1 tables');
select is((select string_agg(c.relname || ':' || (select string_agg(g.tgname, ',' order by g.tgname) from pg_trigger g
  where g.tgrelid = c.oid and not g.tgisinternal), ' ' order by c.relname) from pg_class c
  where c.relnamespace = 'private'::regnamespace and c.relname in ('contract_instrument_versions', 'contract_bundles',
    'contract_bundle_approvals', 'contract_bundle_eligibility')),
  'contract_bundle_approvals:contract_bundle_approvals_append_only,contract_bundle_approvals_no_truncate '
  || 'contract_bundle_eligibility:contract_bundle_eligibility_append_only,contract_bundle_eligibility_no_truncate '
  || 'contract_bundles:contract_bundles_append_only,contract_bundles_construction_guard,contract_bundles_no_truncate '
  || 'contract_instrument_versions:contract_instrument_versions_append_only,contract_instrument_versions_construction_guard,contract_instrument_versions_no_truncate',
  'append-only, no-truncate and construction-guard triggers on every PWP-1 table');
select is((select string_agg(p.proname || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ';'), '-'), ',' order by p.proname)
  from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname in ('current_contract_bundle',
  'contract_bundle_verifies', 'contract_bundle_withdrawn', 'create_contract_instrument_version', 'seal_contract_bundle',
  'record_contract_bundle_approval', 'activate_contract_bundle', 'withdraw_contract_bundle', 'contract_bundle_documents',
  'construct_contract_instrument', 'construct_contract_bundle')),
  'activate_contract_bundle:true:search_path="",construct_contract_bundle:true:search_path="",construct_contract_instrument:true:search_path="",'
  || 'contract_bundle_documents:true:search_path="",contract_bundle_verifies:true:search_path="",contract_bundle_withdrawn:true:search_path="",'
  || 'create_contract_instrument_version:true:search_path="",current_contract_bundle:true:search_path="",record_contract_bundle_approval:true:search_path="",'
  || 'seal_contract_bundle:true:search_path="",withdraw_contract_bundle:true:search_path=""',
  'every PWP-1 function is SECURITY DEFINER with an empty search_path');
select is((select string_agg(p.proname || ':' || p.prosecdef, ',' order by p.proname) from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.proname in ('create_contract_instrument_version', 'seal_contract_bundle',
  'record_contract_bundle_approval', 'activate_contract_bundle', 'withdraw_contract_bundle', 'contract_bundle_documents')),
  'activate_contract_bundle:false,contract_bundle_documents:false,create_contract_instrument_version:false,'
  || 'record_contract_bundle_approval:false,seal_contract_bundle:false,withdraw_contract_bundle:false',
  'the six public wrappers are SECURITY INVOKER');
select ok(not has_function_privilege(r, f, 'execute'), 'no ' || r || ' execute on ' || f)
  from unnest(array['anon', 'authenticated', 'service_role']) r,
       unnest(array['private.current_contract_bundle(text)', 'private.contract_bundle_verifies(uuid)',
         'private.contract_bundle_withdrawn(uuid)', 'private.construct_contract_instrument(text,text,text,text,text[],boolean)',
         'private.construct_contract_bundle(text,text,uuid,uuid,uuid,uuid,integer,jsonb,boolean)']) f;
select is((select provolatile::text from pg_proc where oid = 'private.current_contract_bundle(text)'::regprocedure), 'v',
  'the resolver is volatile (it reads after its shared per-package lock)');
select is((select pg_get_function_result(oid) from pg_proc where oid = 'private.current_contract_bundle(text)'::regprocedure),
  'TABLE(bundle_id uuid, bundle_version integer, bundle_canonicalization text, bundle_sha256 text, agreement_version_id uuid, '
  || 'agreement_text_sha256 text, package_instrument_id uuid, package_instrument_sha256 text, maintenance_instrument_id uuid, '
  || 'maintenance_instrument_sha256 text, shared_terms_instrument_id uuid, shared_terms_instrument_sha256 text, scope_version integer, '
  || 'scope_content_sha256 text, scope_items jsonb, scope_provision_map jsonb, is_test_fixture boolean)',
  'the resolver returns exactly the interface-freeze columns (F1)');
select pg_temp.use_session('00000000-0000-4000-8000-0000000000a1', pg_temp.id('cli'));
select throws_ok($$ select count(*) from private.contract_bundles $$, '42501', null, 'a client cannot read the bundles');
select throws_ok($$ select count(*) from private.contract_instrument_versions $$, '42501', null, 'a client cannot read the instruments');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('sal'));
select throws_ok($$ select count(*) from private.contract_bundle_eligibility $$, '42501', null, 'Sales cannot read the eligibility');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000002', pg_temp.id('adm'));
select throws_ok($$ select count(*) from private.contract_bundle_approvals $$, '42501', null, 'Admin cannot read the approvals table directly');
reset role;
select is(pg_temp.error_of($$ insert into private.contract_instrument_versions (kind, instrument_version, canonicalization, title,
  body, provision_ids, content_sha256, is_test_fixture) values ('shared_terms', 9, 'spotlight.contract_instrument.v1', 'T', 'B',
  array['X'], repeat('a', 64), false) $$), '42501 contract content rows are created only by the PWP-1 constructors',
  'even the database owner cannot insert an instrument outside the constructor');
select is(pg_temp.error_of($$ update private.contract_instrument_versions set title = 'changed' $$),
  '42501 contract_instrument_versions is insert-only', 'sealed instruments cannot be updated');
select is(pg_temp.error_of($$ delete from private.contract_bundles $$), '42501 contract_bundles is insert-only',
  'sealed bundles cannot be deleted');

-- ===========================================================================
-- 2. Golden vectors (OI-109)
-- ===========================================================================
select is(private.contract_instrument_sha256('package_specification', 'essential', 1, 'Golden title',
  E'Golden body line 1\nline 2 — ünïcödé', array['GV-P1', 'GV-P2']),
  '5f94b322b79461dc965b98f47db3dddf79bb2e9e49b93945a8ffa8055c8a4b0d', 'golden vector I1 (spotlight.contract_instrument.v1)');
select is(private.contract_instrument_sha256('shared_terms', null, 3, 'T', 'B', array['X']),
  '3cc806a6959c8b922616020221aa679737cc23aac35a9ad82f92fbaba5f1bf41', 'golden vector I2 (no package key)');
select is(private.contract_bundle_sha256('essential', 2, 'Golden bundle',
  '11111111-1111-4111-8111-111111111111', repeat('a', 64), '22222222-2222-4222-8222-222222222222', repeat('b', 64),
  '33333333-3333-4333-8333-333333333333', repeat('c', 64), '44444444-4444-4444-8444-444444444444', repeat('d', 64),
  1, repeat('e', 64), '["GV-P1", "GV-P2", "GV-P1"]'::jsonb),
  '0c91eddd2cbb598687711b22e575a2b3bd5769fec7f223060e6bc799c0e038db', 'golden vector B1 (spotlight.contract_bundle.v1)');
select is((select count(*)::int from private.contract_bundles b where b.is_test_fixture
  and private.contract_bundle_verifies(b.id)), 5, 'the five seeded fixture bundles verify');

-- ===========================================================================
-- 3. Owner only, fresh MFA, live session: every refusal returned and audited
-- ===========================================================================
create function pg_temp.try_all() returns text language plpgsql as $$
declare
  v_b uuid := (select id from private.contract_bundles where package_key = 'essential' and bundle_version = 1);
begin
  return concat_ws(',',
    public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP SYNTHETIC', 'PGTAP SYNTHETIC BODY',
      array['X'], repeat('a', 64)) ->> 'error',
    public.seal_contract_bundle('essential', 'PGTAP SYNTHETIC', v_b, v_b, v_b, v_b, 1, '["X"]') ->> 'error',
    public.record_contract_bundle_approval(v_b, repeat('a', 64), 'PGTAP-X', repeat('e', 64)) ->> 'error',
    public.activate_contract_bundle(v_b) ->> 'error',
    public.withdraw_contract_bundle(v_b, 'PGTAP probe', 'PGTAP-AUTH') ->> 'error');
end;
$$;
grant execute on function pg_temp.try_all() to authenticated;
grant select on private.contract_bundles to authenticated;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email, '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from (values ('34000000-0000-4000-8000-000000000001'::uuid, 'norole.340@example.test'),
             ('34000000-0000-4000-8000-000000000002'::uuid, 'revoked.owner.340@example.test')) u (id, email);
insert into public.profiles (id, email, full_name) values
  ('34000000-0000-4000-8000-000000000002', 'revoked.owner.340@example.test', 'Synthetic revoked owner');
insert into public.staff_roles (user_id, role, status) values ('34000000-0000-4000-8000-000000000002', 'owner', 'revoked');
insert into ids select 'nor', pg_temp.act_as('34000000-0000-4000-8000-000000000001');
reset role;
insert into ids select 'rev', pg_temp.act_as('34000000-0000-4000-8000-000000000002');
reset role;
insert into ids select 'own1', pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal1', false);
reset role;
insert into ids select 'own_ended', pg_temp.act_as('00000000-0000-4000-8000-000000000001');
reset role;
delete from auth.sessions where id = pg_temp.id('own_ended');
create temp table before_refusals as select (select count(*) from private.contract_instrument_versions) i,
  (select count(*) from private.contract_bundles) b, (select count(*) from private.contract_bundle_approvals) a,
  (select count(*) from private.contract_bundle_eligibility) e;
set local role anon;
select throws_ok($$ select public.create_contract_instrument_version('shared_terms', null, 2, 'T', 'B', array['X'], repeat('a', 64)) $$,
  '42501', null, 'anon cannot call create_contract_instrument_version');
select throws_ok($$ select public.seal_contract_bundle('essential', 'T', null, null, null, null, 1, '[]') $$, '42501', null, 'anon cannot call seal_contract_bundle');
select throws_ok($$ select public.record_contract_bundle_approval(null, null, null, null) $$, '42501', null, 'anon cannot call record_contract_bundle_approval');
select throws_ok($$ select public.activate_contract_bundle(null) $$, '42501', null, 'anon cannot call activate_contract_bundle');
select throws_ok($$ select public.withdraw_contract_bundle(null, null, null) $$, '42501', null, 'anon cannot call withdraw_contract_bundle');
select throws_ok($$ select public.contract_bundle_documents(null) $$, '42501', null, 'anon cannot call contract_bundle_documents');
reset role;
select pg_temp.use_session('34000000-0000-4000-8000-000000000001', pg_temp.id('nor'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'a signed-in user without a staff role (fresh MFA) is refused by all five');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-0000000000a1', pg_temp.id('cli'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'a client (fresh MFA) is refused by all five');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('sal'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'Sales (fresh MFA) is refused by all five');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000002', pg_temp.id('adm'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'Admin (fresh MFA) is refused by all five');
reset role;
select pg_temp.use_session('34000000-0000-4000-8000-000000000002', pg_temp.id('rev'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'a revoked Owner (fresh MFA) is refused by all five');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000001', pg_temp.id('own1'), 'aal1', false);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'the Owner at aal1 is refused by all five');
reset role;
select pg_temp.use_stale('00000000-0000-4000-8000-000000000001', pg_temp.id('own'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'the Owner with a stale MFA verification is refused by all five');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000001', pg_temp.id('own_ended'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden,forbidden', 'the Owner with an ended session is refused by all five');
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and action in ('contract_instrument.load_rejected', 'contract_bundle.seal_rejected', 'contract_bundle.approval_rejected',
    'contract_bundle.activation_rejected', 'contract_bundle.withdrawal_rejected')
  and summary ->> 'reason' = 'forbidden' and actor_user_id is not null), 40,
  'eight refused callers x five functions: forty refusal events, each naming the caller');
select is((select row((select count(*) from private.contract_instrument_versions), (select count(*) from private.contract_bundles),
  (select count(*) from private.contract_bundle_approvals), (select count(*) from private.contract_bundle_eligibility))::text),
  (select row(i, b, a, e)::text from before_refusals), 'no refused caller changed any PWP-1 record');
revoke select on private.contract_bundles from authenticated;

-- ===========================================================================
-- 4. The OD-5 loader: hash-verified, development and test only, synthetic content only
-- ===========================================================================
create temp table txt (k text primary key, v text);
grant select on txt to authenticated;
insert into txt values ('body_pkg', E'PGTAP SYNTHETIC PACKAGE SPECIFICATION\nline two'),
  ('body_mnt', 'PGTAP SYNTHETIC MAINTENANCE SPECIFICATION'), ('body_shr', 'PGTAP SYNTHETIC SHARED TERMS'),
  ('agreement', 'PGTAP SYNTHETIC AGREEMENT' || E'\n\n' || private.final_payment_clause());
create function pg_temp.t(p_k text) returns text language sql as $$ select v from txt where k = p_k $$;
grant execute on function pg_temp.t(text) to authenticated;
select pg_temp.owner();
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP', E'line\r\nCR', array['S1'],
  pg_temp.isha('shared_terms', null, 2, 'PGTAP', E'line\r\nCR', array['S1'])) ->> 'error', 'invalid_input',
  'a body with CR is rejected, never converted (OI-109)');
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP', 'TEST FIXTURE — NOT A CONTRACT INSTRUMENT (x)',
  array['S1'], repeat('a', 64)) ->> 'error', 'invalid_input', 'fixture-labelled content cannot be loaded (fixtures come only from the seed)');
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP', 'B', array['bad id'], repeat('a', 64)) ->> 'error',
  'invalid_input', 'a malformed provision identifier is rejected');
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP', 'B', array['S1', 'S1'], repeat('a', 64)) ->> 'error',
  'invalid_input', 'duplicate provision identifiers are rejected');
select is(public.create_contract_instrument_version('shared_terms', 'essential', 2, 'PGTAP', 'B', array['S1'], repeat('a', 64)) ->> 'error',
  'invalid_input', 'a package key on a non-package instrument is rejected');
select is(public.create_contract_instrument_version('package_specification', null, 2, 'PGTAP', 'B', array['S1'], repeat('a', 64)) ->> 'error',
  'invalid_input', 'a package instrument without a package is rejected');
select is(public.create_contract_instrument_version('bogus_kind', null, 1, 'PGTAP', 'B', array['S1'], repeat('a', 64)) ->> 'error',
  'invalid_input', 'an unknown kind is rejected');
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP', pg_temp.t('body_shr'), array['S1'],
  repeat('a', 64)) ->> 'error', 'hash_mismatch', 'content that does not match the expected hash is refused');
select is(public.create_contract_instrument_version('shared_terms', null, 5, 'PGTAP', pg_temp.t('body_shr'), array['S1'],
  pg_temp.isha('shared_terms', null, 5, 'PGTAP', pg_temp.t('body_shr'), array['S1'])) ->> 'error', 'version_conflict',
  'a version other than the next one is refused');
reset role;
select is((select count(*)::int from private.contract_instrument_versions where not is_test_fixture), 0,
  'no refused load created an instrument');
select is(pg_temp.last_reason('contract_instrument.load_rejected'), 'version_conflict', 'the last refusal is audited by code');
-- Successful loads (synthetic, non-fixture).
select pg_temp.owner();
insert into ids select 'ip', public.create_contract_instrument_version('package_specification', 'advanced', 2, 'PGTAP package',
  pg_temp.t('body_pkg'), array['P-1', 'P-2'], pg_temp.isha('package_specification', 'advanced', 2, 'PGTAP package',
  pg_temp.t('body_pkg'), array['P-1', 'P-2'])) ->> 'instrument_id';
insert into ids select 'im', public.create_contract_instrument_version('maintenance_specification', null, 2, 'PGTAP maintenance',
  pg_temp.t('body_mnt'), array['M-1'], pg_temp.isha('maintenance_specification', null, 2, 'PGTAP maintenance',
  pg_temp.t('body_mnt'), array['M-1'])) ->> 'instrument_id';
insert into ids select 'is', public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP shared',
  pg_temp.t('body_shr'), array['S-1'], pg_temp.isha('shared_terms', null, 2, 'PGTAP shared', pg_temp.t('body_shr'), array['S-1']))
  ->> 'instrument_id';
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP shared', pg_temp.t('body_shr'), array['S-1'],
  pg_temp.isha('shared_terms', null, 2, 'PGTAP shared', pg_temp.t('body_shr'), array['S-1'])) ->> 'replayed', 'true',
  'an identical load replay returns the existing version');
select is(public.create_contract_instrument_version('shared_terms', null, 2, 'PGTAP shared CHANGED', pg_temp.t('body_shr'), array['S-1'],
  pg_temp.isha('shared_terms', null, 2, 'PGTAP shared CHANGED', pg_temp.t('body_shr'), array['S-1'])) ->> 'error', 'version_conflict',
  'conflicting content for an existing version fails closed (T-CON-08)');
reset role;
select is((select string_agg(kind || ':' || coalesce(package_key, '*') || ':' || instrument_version || ':' || is_test_fixture
  || ':' || private.contract_instrument_verifies(id), ',' order by kind) from private.contract_instrument_versions where not is_test_fixture),
  'maintenance_specification:*:2:false:true,package_specification:advanced:2:false:true,shared_terms:*:2:false:true',
  'three synthetic instruments sealed on creation, each verifying; the replay added none');
select is(pg_temp.audits('contract_instrument.created'), 3, 'three creation events');
-- Classification restrictions (requirement B and F).
select pg_temp.classify('staging');
select pg_temp.owner();
select is(public.create_contract_instrument_version('shared_terms', null, 3, 'PGTAP', 'B', array['S1'],
  pg_temp.isha('shared_terms', null, 3, 'PGTAP', 'B', array['S1'])) ->> 'error', 'classification_not_allowed', 'no loading under staging');
reset role;
select pg_temp.classify('inconsistent');
select pg_temp.owner();
select is(public.create_contract_instrument_version('shared_terms', null, 3, 'PGTAP', 'B', array['S1'],
  pg_temp.isha('shared_terms', null, 3, 'PGTAP', 'B', array['S1'])) ->> 'error', 'classification_inconsistent',
  'no loading under an inconsistent classification');
reset role;
select pg_temp.classify('development');

-- ===========================================================================
-- 5. Sealing (T-CON-01, T-CON-04, T-CON-05; OD-8, OD-10)
-- ===========================================================================
-- A synthetic, approved agreement (only the 04 §3.1 clause besides a synthetic heading).
select pg_temp.owner();
insert into ids select 'agr', public.create_agreement_version('pgtap-pwp1-1', pg_temp.t('agreement'), current_date, 'PGTAP-AGR')
  ->> 'agreement_version_id';
select is(public.approve_agreement_version(pg_temp.id('agr')) ->> 'ok', 'true', 'setup: a synthetic agreement is approved');
-- A synthetic AUTH-018 scope version 2 for advanced, approved and loaded.
create temp table sitems (k text primary key, v text[]);
grant select on sitems to authenticated;
reset role;
insert into sitems values ('a2', array['PGTAP SYNTHETIC SCOPE ITEM A', 'PGTAP SYNTHETIC SCOPE ITEM B']),
  ('big', array(select 'PGTAP SYNTHETIC LONG SCOPE ITEM ' || g || ' ' || repeat('x', 250) from generate_series(1, 40) g));
create function pg_temp.items(p_k text) returns text[] language sql as $$ select v from sitems where k = p_k $$;
grant execute on function pg_temp.items(text) to authenticated;
create function pg_temp.ssha(p_key text, p_version integer, p_items text[]) returns text language sql as $$
  select encode(extensions.digest(convert_to('spotlight.package_scope.v1|k' || octet_length(p_key) || ':' || p_key
    || '|v' || p_version || '|n' || cardinality(p_items)
    || (select string_agg('|p' || o || ':' || octet_length(t) || ':' || t, '' order by o)
          from unnest(p_items) with ordinality u (t, o)), 'UTF8'), 'sha256'), 'hex')
$$;
grant execute on function pg_temp.ssha(text, integer, text[]) to authenticated;
select pg_temp.owner();
select is(public.record_package_scope_approval('advanced', 2, pg_temp.ssha('advanced', 2, pg_temp.items('a2')), 'PGTAP-SCOPE-A2',
  repeat('e', 64)) ->> 'ok', 'true', 'setup: AUTH-018 approval of advanced scope version 2');
select is(public.load_package_scope_version('advanced', 2, pg_temp.items('a2')) ->> 'ok', 'true',
  'setup: AUTH-018 load of advanced scope version 2');
-- Refusals (no partial bundle).
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('im'), pg_temp.id('im'),
  pg_temp.id('is'), 2, '["P-1", "P-2"]') ->> 'error', 'bundle_instrument_mismatch',
  'T-CON-04: a maintenance instrument in the package slot is refused');
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('is'),
  pg_temp.id('is'), 2, '["P-1", "P-2"]') ->> 'error', 'bundle_instrument_mismatch',
  'T-CON-04: a shared-terms instrument in the maintenance slot is refused');
select is(public.seal_contract_bundle('essential', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('im'),
  pg_temp.id('is'), 1, '["P-1", "P-2", "P-1"]') ->> 'error', 'bundle_instrument_mismatch',
  'T-CON-04: a package instrument of another package is refused');
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('im'),
  pg_temp.id('is'), 2, '["P-1"]') ->> 'error', 'bundle_provision_map_invalid', 'a map that does not cover every scope item is refused');
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('im'),
  pg_temp.id('is'), 2, '["P-1", "P-9"]') ->> 'error', 'bundle_provision_map_invalid',
  'a map naming a provision the package instrument does not declare is refused (OI-99 traceability)');
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', (select id from public.agreement_versions where version_label = 'test-fixture-1'),
  pg_temp.id('ip'), pg_temp.id('im'), pg_temp.id('is'), 2, '["P-1", "P-2"]') ->> 'error', 'bundle_fixture_mismatch',
  'a fixture agreement with non-fixture components is refused');
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('im'),
  pg_temp.id('is'), 1, '["P-1", "P-2", "P-1"]') ->> 'error', 'bundle_fixture_mismatch',
  'a fixture scope version with non-fixture instruments is refused');
select is(public.seal_contract_bundle('advanced', 'TEST FIXTURE — NOT A CONTRACT BUNDLE (x)', pg_temp.id('agr'), pg_temp.id('ip'),
  pg_temp.id('im'), pg_temp.id('is'), 2, '["P-1", "P-2"]') ->> 'error', 'invalid_input',
  'a fixture-labelled bundle cannot be sealed by the Owner (fixtures come only from the seed)');
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('im'),
  pg_temp.id('is'), 9, '["P-1", "P-2"]') ->> 'error', 'bundle_scope_invalid', 'an unknown scope version is refused');
reset role;
select is((select count(*)::int from private.contract_bundles where not is_test_fixture), 0,
  'T-CON-01: no refused seal left a bundle');

-- T-CON-05 / OD-8: a scope that exceeds the order-summary limit is rejected at sealing.
select pg_temp.owner();
insert into ids select 'ipsig', public.create_contract_instrument_version('package_specification', 'signature', 2, 'PGTAP package sig',
  pg_temp.t('body_pkg'), array['P-1'], pg_temp.isha('package_specification', 'signature', 2, 'PGTAP package sig',
  pg_temp.t('body_pkg'), array['P-1'])) ->> 'instrument_id';
select is(public.record_package_scope_approval('signature', 2, pg_temp.ssha('signature', 2, pg_temp.items('big')), 'PGTAP-SCOPE-BIG',
  repeat('e', 64)) ->> 'ok', 'true', 'setup: approval of a 40-item scope version over 8,192 serialized bytes');
select is(public.load_package_scope_version('signature', 2, pg_temp.items('big')) ->> 'ok', 'true', 'setup: its load');
select is(public.seal_contract_bundle('signature', 'PGTAP bundle sig', pg_temp.id('agr'), pg_temp.id('ipsig'), pg_temp.id('im'),
  pg_temp.id('is'), 2, (select jsonb_agg('P-1'::text) from generate_series(1, 40))) ->> 'error', 'bundle_scope_too_large',
  'T-CON-05: a scope over 8,192 serialized bytes is rejected at sealing');
reset role;
select ok(octet_length((select jsonb_agg(to_jsonb(t)) from unnest(pg_temp.items('big')) t)::text) > 8192,
  'setup check: that scope really exceeds 8,192 bytes');
-- OD-10: a non-fixture scope version without an AUTH-018 approval is refused.
select private.create_package_scope_version('prestige', array['PGTAP SYNTHETIC UNAPPROVED SCOPE ITEM'], false);
select pg_temp.owner();
insert into ids select 'ippre', public.create_contract_instrument_version('package_specification', 'prestige', 2, 'PGTAP package pre',
  pg_temp.t('body_pkg'), array['P-1'], pg_temp.isha('package_specification', 'prestige', 2, 'PGTAP package pre',
  pg_temp.t('body_pkg'), array['P-1'])) ->> 'instrument_id';
select is(public.seal_contract_bundle('prestige', 'PGTAP bundle pre', pg_temp.id('agr'), pg_temp.id('ippre'), pg_temp.id('im'),
  pg_temp.id('is'), 2, '["P-1"]') ->> 'error', 'bundle_scope_unapproved',
  'OD-10: a scope version without its AUTH-018 approval cannot enter a non-fixture bundle');
-- The successful seal.
insert into ids select 'b2', public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'),
  pg_temp.id('im'), pg_temp.id('is'), 2, '["P-1", "P-2"]') ->> 'bundle_id';
select is(public.seal_contract_bundle('advanced', 'PGTAP bundle', pg_temp.id('agr'), pg_temp.id('ip'), pg_temp.id('im'),
  pg_temp.id('is'), 2, '["P-1", "P-2"]') ->> 'replayed', 'true', 'T-CON-08: an identical seal request returns the existing bundle');
reset role;
select isnt(pg_temp.id('b2'), null, 'the Owner seals a synthetic advanced bundle');
select is((select bundle_version from private.contract_bundles where id = pg_temp.id('b2')), 2, 'it is advanced bundle version 2');
select ok(private.contract_bundle_verifies(pg_temp.id('b2')), 'it verifies (F2)');
select is((select bundle_sha256 from private.contract_bundles where id = pg_temp.id('b2')),
  (select private.contract_bundle_sha256(b.package_key, b.bundle_version, b.title, b.agreement_version_id, b.agreement_text_sha256,
    b.package_instrument_id, b.package_instrument_sha256, b.maintenance_instrument_id, b.maintenance_instrument_sha256,
    b.shared_terms_instrument_id, b.shared_terms_instrument_sha256, b.scope_version, b.scope_content_sha256, b.scope_provision_map)
   from private.contract_bundles b where b.id = pg_temp.id('b2')), 'T-CON-03: the recomputed bundle hash matches');
select is((select count(*)::int from private.contract_bundles where package_key = 'advanced'), 2, 'the replay added no bundle');
select is(pg_temp.audits('contract_bundle.sealed'), 1, 'one seal event');
select is(pg_temp.resolved('advanced'), '', 'OD-7: a sealed but unactivated newer bundle suspends issuance (no fallback to fixture version 1)');
select is(pg_temp.resolved('essential'), '1:true', 'other packages are unaffected (the essential fixture bundle resolves in development)');

-- ===========================================================================
-- 6. Legal approval and activation; the resolver (F1)
-- ===========================================================================
create temp table bsha as select bundle_sha256 v from private.contract_bundles where id = pg_temp.id('b2');
grant select on bsha to authenticated;
insert into ids select 'bfx', id from private.contract_bundles where package_key = 'essential' and bundle_version = 1;
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'error', 'approval_missing', 'activation needs a legal approval');
select is(public.record_contract_bundle_approval(pg_temp.id('b2'), repeat('a', 64), 'PGTAP-LEGAL-1', repeat('e', 64)) ->> 'error',
  'hash_mismatch', 'an approval bound to a different hash is refused');
select is(public.record_contract_bundle_approval(pg_temp.id('b2'), (select v from bsha),
  'has space', repeat('e', 64)) ->> 'error', 'invalid_input', 'a malformed approval reference is refused');
select is(public.record_contract_bundle_approval(pg_temp.id('b2'), (select v from bsha), 'PGTAP-LEGAL-1', repeat('e', 64)) ->> 'ok',
  'true', 'the Owner records the legal approval bound to the exact bundle hash');
select is(public.record_contract_bundle_approval(pg_temp.id('b2'), (select v from bsha), 'PGTAP-LEGAL-1', repeat('e', 64)) ->> 'replayed',
  'true', 'T-CON-08: an identical approval returns the existing record');
select is(public.record_contract_bundle_approval(pg_temp.id('b2'), (select v from bsha), 'PGTAP-LEGAL-2', repeat('e', 64)) ->> 'error',
  'approval_conflict', 'T-CON-08: a conflicting approval fails closed');
select is(public.record_contract_bundle_approval(pg_temp.id('bfx'),
  repeat('a', 64), 'PGTAP-LEGAL-F', repeat('e', 64)) ->> 'error', 'fixture_not_allowed', 'a fixture bundle can never be approved');
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'ok', 'true', 'the Owner activates the bundle in development');
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'replayed', 'true', 'T-CON-08: an activation replay returns the existing activation');
reset role;
select is(pg_temp.last_reason('contract_bundle.approval_rejected'), 'fixture_not_allowed', 'refusals are audited by reason code');
select is((select count(*)::int from private.contract_bundle_eligibility where bundle_id = pg_temp.id('b2') and event = 'activated'), 1,
  'exactly one activation');
select is(pg_temp.resolved('advanced'), '2:false', 'the approved, activated bundle resolves');
select is((select row(r.bundle_id, r.bundle_version, r.bundle_canonicalization, r.bundle_sha256, r.agreement_version_id,
    r.package_instrument_id, r.maintenance_instrument_id, r.shared_terms_instrument_id, r.scope_version, r.scope_items,
    r.scope_provision_map, r.is_test_fixture)::text from private.current_contract_bundle('advanced') r),
  (select row(b.id, b.bundle_version, 'spotlight.contract_bundle.v1', b.bundle_sha256, b.agreement_version_id,
    b.package_instrument_id, b.maintenance_instrument_id, b.shared_terms_instrument_id, 2,
    to_jsonb(pg_temp.items('a2')), '["P-1", "P-2"]'::jsonb, false)::text from private.contract_bundles b where b.id = pg_temp.id('b2')),
  'F1: the resolver returns the exact bundle, components and scope items');
-- Activation is per classification; nothing resolves outside development and test.
select pg_temp.classify('test');
select is(pg_temp.resolved('advanced'), '', 'a development activation does not resolve under test');
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'ok', 'true', 'the Owner activates it for test');
reset role;
select is(pg_temp.resolved('advanced'), '2:false', 'it resolves under test');
select pg_temp.classify('staging');
select is(pg_temp.resolved('advanced'), '', 'nothing resolves under staging');
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'error', 'classification_not_allowed', 'no activation under staging');
reset role;
select pg_temp.classify('preview');
select is(pg_temp.resolved('advanced'), '', 'nothing resolves under preview');
select pg_temp.classify('production');
select is(private.app_environment(), 'production', 'setup: no classification reads as production');
select is(pg_temp.resolved('advanced'), '', 'OD-6: nothing resolves in production');
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'error', 'classification_not_allowed', 'no activation in production');
reset role;
select pg_temp.classify('inconsistent');
select is(pg_temp.resolved('advanced'), '', 'requirement F: nothing resolves under an inconsistent classification (and nothing raises)');
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'error', 'classification_inconsistent',
  'no activation under an inconsistent classification');
reset role;
select pg_temp.classify('development');
select throws_ok($$ insert into private.contract_bundle_eligibility (bundle_id, event, classification, bundle_sha256, recorded_by)
  values ((select id from private.contract_bundles where package_key = 'advanced' and bundle_version = 2), 'activated', 'production',
  repeat('a', 64), gen_random_uuid()) $$, '23514', null, 'the table itself refuses a production activation, even from the database owner');

-- ===========================================================================
-- 7. Integrity failure without fallback (T-CON-03, R-05)
-- ===========================================================================
set local session_replication_role = replica;
update private.contract_instrument_versions set body = 'PGTAP SYNTHETIC TAMPERED' where id = pg_temp.id('im');
set local session_replication_role = origin;
select ok(not private.contract_bundle_verifies(pg_temp.id('b2')), 'a tampered component makes the bundle fail verification');
select is(pg_temp.resolved('advanced'), '', 'T-CON-03: a tampered bundle resolves nothing, with no fallback to the fixture bundle');
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'error', 'integrity_failure',
  'activation re-verifies every component and refuses a tampered bundle, even when already activated');
reset role;
set local session_replication_role = replica;
update private.contract_instrument_versions set body = pg_temp.t('body_mnt') where id = pg_temp.id('im');
update private.billing_package_scope set item_text = 'PGTAP SYNTHETIC TAMPERED SCOPE' where package_key = 'advanced' and scope_version = 2 and position = 1;
set local session_replication_role = origin;
select is(pg_temp.resolved('advanced'), '', 'a tampered scope item also fails closed');
set local session_replication_role = replica;
update private.billing_package_scope set item_text = 'PGTAP SYNTHETIC SCOPE ITEM A' where package_key = 'advanced' and scope_version = 2 and position = 1;
update public.agreement_versions set canonical_text = canonical_text || ' ' where id = pg_temp.id('agr');
set local session_replication_role = origin;
select is(pg_temp.resolved('advanced'), '', 'a tampered governing agreement also fails closed');
set local session_replication_role = replica;
update public.agreement_versions set canonical_text = pg_temp.t('agreement') where id = pg_temp.id('agr');
set local session_replication_role = origin;
select is(pg_temp.resolved('advanced'), '2:false', 'setup: restored, it resolves again');

-- ===========================================================================
-- 8. The reader (T-CON-11)
-- ===========================================================================
select pg_temp.owner();
select is((public.contract_bundle_documents(pg_temp.id('b2')) -> 'instruments' -> 0 ->> 'kind'), 'package_specification',
  'the Owner reads the bundle''s instruments, package first');
select is(jsonb_array_length(public.contract_bundle_documents(pg_temp.id('b2')) -> 'instruments'), 3, 'all three instruments');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000002', pg_temp.id('adm'));
select is(public.contract_bundle_documents(pg_temp.id('b2')) ->> 'ok', 'true', 'Admin reads them');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('sal'));
select is(public.contract_bundle_documents(pg_temp.id('b2')) ->> 'error', 'not_found', 'Sales reads nothing');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-0000000000a1', pg_temp.id('cli'));
select is(public.contract_bundle_documents(pg_temp.id('b2')) ->> 'error', 'not_found',
  'T-CON-11: a client reads nothing through the staff reader (the client path is PWP-2)');
select is(public.contract_bundle_documents(pg_temp.id('bfx')) ->> 'error', 'not_found', 'nor any fixture bundle');
reset role;
select pg_temp.use_session('34000000-0000-4000-8000-000000000001', pg_temp.id('nor'));
select is(public.contract_bundle_documents(pg_temp.id('b2')) ->> 'error', 'not_found', 'a signed-in user without a role reads nothing');
reset role;
select pg_temp.owner();
select is(public.contract_bundle_documents(pg_temp.id('bfx')) ->> 'ok', 'true', 'the Owner reads a fixture bundle in development');
select is(public.contract_bundle_documents(gen_random_uuid()) ->> 'error', 'not_found', 'an unknown bundle looks the same as an unreadable one');
reset role;
select pg_temp.classify('staging');
select pg_temp.owner();
select is(public.contract_bundle_documents(pg_temp.id('bfx')) ->> 'error', 'not_found', 'T-CON-11: fixture content is never readable under staging');
reset role;
select pg_temp.classify('production');
select pg_temp.owner();
select is(public.contract_bundle_documents(pg_temp.id('bfx')) ->> 'error', 'not_found', 'nor in production (missing classification)');
reset role;
select pg_temp.classify('inconsistent');
select pg_temp.owner();
select is(public.contract_bundle_documents(pg_temp.id('bfx')) ->> 'error', 'not_found', 'nor under an inconsistent classification');
reset role;
select pg_temp.classify('development');

-- ===========================================================================
-- 9. Fixture bundles (T-CON-12, requirement F)
-- ===========================================================================
select is(pg_temp.resolved('essential'), '1:true', 'a fixture bundle resolves in development');
select pg_temp.classify('test');
select is(pg_temp.resolved('essential'), '1:true', 'and in test');
select pg_temp.classify('staging');
select is(pg_temp.resolved('essential'), '', 'T-CON-12: never under staging');
select pg_temp.classify('preview');
select is(pg_temp.resolved('essential'), '', 'T-CON-12: never under preview');
select pg_temp.classify('production');
select is(pg_temp.resolved('essential'), '', 'T-CON-12: never in production (missing classification)');
select is(pg_temp.error_of($$ select private.construct_contract_instrument('shared_terms', null, 'TEST FIXTURE x',
  'TEST FIXTURE — NOT A CONTRACT INSTRUMENT (production probe)', array['X'], true) $$),
  '42501 contract fixtures are allowed only in development and test databases', 'no fixture instrument can be created in production');
select pg_temp.classify('staging');
select is(pg_temp.error_of($$ select private.construct_contract_instrument('shared_terms', null, 'TEST FIXTURE x',
  'TEST FIXTURE — NOT A CONTRACT INSTRUMENT (staging probe)', array['X'], true) $$),
  '42501 contract fixtures are allowed only in development and test databases', 'nor under staging');
select pg_temp.classify('inconsistent');
select is(pg_temp.resolved('essential'), '', 'requirement F: never under an inconsistent classification');
select is(pg_temp.error_of($$ select private.construct_contract_instrument('shared_terms', null, 'TEST FIXTURE x',
  'TEST FIXTURE — NOT A CONTRACT INSTRUMENT (inconsistent probe)', array['X'], true) $$),
  '42501 contract fixtures are allowed only in development and test databases', 'nor under an inconsistent classification');
select pg_temp.classify('development');
select pg_temp.owner();
select is(public.activate_contract_bundle(pg_temp.id('bfx')) ->> 'error', 'fixture_not_allowed', 'T-CON-12: a fixture bundle can never be activated');
reset role;
select is(pg_temp.error_of($$ select private.construct_contract_instrument('shared_terms', null, 'PGTAP', 'TEST FIXTURE — NOT A CONTRACT INSTRUMENT (unflagged)',
  array['X'], false) $$) like '23514 %', true, 'a labelled instrument cannot be created without the fixture flag');
select is(pg_temp.error_of($$ select private.construct_contract_instrument('shared_terms', null, 'PGTAP', 'PGTAP SYNTHETIC unlabelled',
  array['X'], true) $$) like '23514 %', true, 'a flagged instrument cannot be created without the label');

-- ===========================================================================
-- 10. Withdrawal: Owner only, irreversible, no fallback, content unchanged (T-CON-06)
-- ===========================================================================
create temp table before_withdrawal as select (select row(b.*)::text from private.contract_bundles b where b.id = pg_temp.id('b2')) b,
  (select string_agg(i.content_sha256, ',' order by i.id) from private.contract_instrument_versions i) i;
select pg_temp.owner();
select is(public.withdraw_contract_bundle(pg_temp.id('b2'), '', 'PGTAP-WD-1') ->> 'error', 'invalid_input', 'a withdrawal needs a reason');
select is(public.withdraw_contract_bundle(pg_temp.id('b2'), 'PGTAP reason', 'has space') ->> 'error', 'invalid_input',
  'and a well-formed authorization reference');
select is(public.withdraw_contract_bundle(pg_temp.id('b2'), 'PGTAP synthetic withdrawal', 'PGTAP-WD-1') ->> 'ok', 'true',
  'the Owner withdraws the bundle');
select is(public.withdraw_contract_bundle(pg_temp.id('b2'), 'PGTAP synthetic withdrawal again', 'PGTAP-WD-2') ->> 'replayed', 'true',
  'a second withdrawal returns the existing one');
select is(public.activate_contract_bundle(pg_temp.id('b2')) ->> 'error', 'withdrawn', 'a withdrawn bundle is never reactivated');
select is(public.record_contract_bundle_approval(pg_temp.id('b2'), (select v from bsha), 'PGTAP-LEGAL-1', repeat('e', 64)) ->> 'replayed',
  'true', 'its existing approval is unchanged');
reset role;
select ok(private.contract_bundle_withdrawn(pg_temp.id('b2')), 'F3: contract_bundle_withdrawn is true');
select ok(not private.contract_bundle_withdrawn(gen_random_uuid()), 'F3: an unknown bundle is not withdrawn');
select ok(not private.contract_bundle_verifies(gen_random_uuid()), 'F2: an unknown bundle does not verify');
select is(pg_temp.resolved('advanced'), '', 'a withdrawn newest bundle resolves nothing: no fallback to the fixture bundle');
select pg_temp.classify('test');
select is(pg_temp.resolved('advanced'), '', 'in every classification, including the one it was activated for');
select pg_temp.classify('development');
select is((select row(b.*)::text from private.contract_bundles b where b.id = pg_temp.id('b2')), (select b from before_withdrawal),
  'withdrawal never changes the sealed bundle');
select is((select string_agg(i.content_sha256, ',' order by i.id) from private.contract_instrument_versions i), (select i from before_withdrawal),
  'nor any instrument');
select is((select row(event, reason, authorization_reference, recorded_by)::text from private.contract_bundle_eligibility
  where bundle_id = pg_temp.id('b2') and event = 'withdrawn'),
  row('withdrawn', 'PGTAP synthetic withdrawal', 'PGTAP-WD-1', '00000000-0000-4000-8000-000000000001'::uuid)::text,
  'the withdrawal records the actor, reason and authorization reference');
select is(pg_temp.audits('contract_bundle.withdrawn'), 1, 'one withdrawal event');
select is(pg_temp.last_reason('contract_bundle.activation_rejected'), 'withdrawn', 'the reactivation attempt is audited');
select is(pg_temp.error_of($$ update private.contract_bundle_eligibility set reason = 'changed' $$),
  '42501 contract_bundle_eligibility is insert-only', 'eligibility events cannot be updated');
select is(pg_temp.error_of($$ delete from private.contract_bundle_approvals $$), '42501 contract_bundle_approvals is insert-only',
  'approvals cannot be deleted');
select is(pg_temp.error_of($$ truncate private.contract_bundle_eligibility $$) like '42501 %', true, 'eligibility cannot be truncated');
select is(pg_temp.error_of($$ truncate private.contract_bundles cascade $$) like '42501 %', true, 'bundles cannot be truncated, even with CASCADE');
-- A fixture bundle can also be withdrawn (it only removes eligibility).
select pg_temp.owner();
select is(public.withdraw_contract_bundle(pg_temp.id('bfx'), 'PGTAP synthetic fixture withdrawal', 'PGTAP-WD-F') ->> 'ok', 'true',
  'the Owner can withdraw a fixture bundle');
reset role;
select is(pg_temp.resolved('essential'), '', 'a withdrawn fixture bundle resolves nothing');

-- ===========================================================================
-- 11. No content text in audit rows; the AUTH-018 and AUTH-007 objects are unchanged
-- ===========================================================================
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and (action like 'contract_%') and (summary::text ~* 'PGTAP SYNTHETIC|NOT A CONTRACT|ünïcödé' or coalesce(target_id, '') ~* 'PGTAP SYNTHETIC')), 0,
  'no PWP-1 audit row carries instrument, bundle or scope text');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action like 'contract_%'
  and octet_length(coalesce(target_id, '')) > 64), 0, 'every PWP-1 audit target is a bounded identifier');
select is((select provolatile::text from pg_proc where oid = 'private.current_package_scope(text)'::regprocedure), 'v',
  'the AUTH-018 resolver is unchanged (still volatile)');

select * from finish();
rollback;
