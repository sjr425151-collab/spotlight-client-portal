-- DEP-18 R1 interim scope loading and activation (AUTH-018; Decision 8a; 04 §4A "R1 interim scope
-- loading and activation"; FD-05). Serial cases; the concurrent cases run in the isolated harness.
-- Every scope item here is a synthetic, non-legal test string (D11), local and CI only, inside this
-- rolled-back transaction. None is contractual content.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(137);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false)
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
create function pg_temp.use_session(p_uid uuid, p_sid uuid, p_aal text default 'aal2', p_fresh boolean default false)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', p_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
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
-- An independent implementation of the canonical serialization (AUTH-007), for expected hashes.
create function pg_temp.sha(p_key text, p_version integer, p_items text[]) returns text language sql as $$
  select encode(extensions.digest(convert_to('spotlight.package_scope.v1|k' || octet_length(p_key) || ':' || p_key
    || '|v' || p_version || '|n' || cardinality(p_items)
    || (select string_agg('|p' || o || ':' || octet_length(t) || ':' || t, '' order by o)
          from unnest(p_items) with ordinality u (t, o)), 'UTF8'), 'sha256'), 'hex')
$$;
create function pg_temp.rows(p_key text) returns text language sql as $$
  select coalesce(string_agg(scope_version || ':' || item_position, ',' order by item_position), '')
  from private.current_package_scope(p_key)
$$;
create function pg_temp.error_of(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'no error';
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;
create temp table items (k text primary key, v text[]);
insert into items values
  ('p2', array['PGTAP SYNTHETIC SCOPE ITEM P2-A', 'PGTAP SYNTHETIC SCOPE ITEM P2-B', 'PGTAP SYNTHETIC SCOPE ITEM P2-C']),
  ('p2x', array['PGTAP SYNTHETIC SCOPE ITEM P2-A', 'PGTAP SYNTHETIC SCOPE ITEM P2-CHANGED']),
  ('p3', array['PGTAP SYNTHETIC SCOPE ITEM P3-A']),
  ('labelled', array['TEST FIXTURE — NOT A DELIVERABLE (pgtap 330)']);
grant select on items to authenticated;
create function pg_temp.items(p_k text) returns text[] language sql as $$ select v from items where k = p_k $$;
grant execute on function pg_temp.items(text) to authenticated;
create function pg_temp.sha_of(p_key text, p_version integer, p_k text) returns text language sql as $$
  select pg_temp.sha(p_key, p_version, pg_temp.items(p_k))
$$;
grant execute on function pg_temp.sha_of(text, integer, text), pg_temp.sha(text, integer, text[]) to authenticated;
-- Synthetic non-sensitive identifiers (no real approval evidence).
create function pg_temp.ev() returns text language sql as $$ select repeat('e', 64) $$;
grant execute on function pg_temp.ev() to authenticated;

-- Owner (fresh MFA), Admin, Sales and a client.
insert into ids select 'own', pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
reset role;
insert into ids select 'adm', pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
reset role;
insert into ids select 'sal', pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
insert into ids select 'prj', public.sales_create_customer_project('Synthetic Scope LLC', 'Synthetic Scope', 'Scope site') ->> 'project_id';
reset role;
insert into ids select 'cli', pg_temp.act_as('00000000-0000-4000-8000-0000000000a1', 'aal2', true);
reset role;
create function pg_temp.owner() returns void language sql as $$
  select pg_temp.use_session('00000000-0000-4000-8000-000000000001', pg_temp.id('own'), 'aal2', true)
$$;
create function pg_temp.issue(p_key text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('sal'), 'aal2', true);
  v := public.issue_order_summary(pg_temp.id('prj'), p_key, '[]'::jsonb, null, 'Synthetic order');
  reset role;
  return v;
end;
$$;

-- ===========================================================================
-- 1. Objects, privileges and isolation (no API role reads or writes the new tables)
-- ===========================================================================
select is((select count(*)::int from unnest(array['anon', 'authenticated', 'service_role', 'public']) r,
  unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p,
  unnest(array['private.billing_package_scope_approvals', 'private.billing_package_scope_eligibility']) t
  where has_table_privilege(r, t, p)), 0, 'no API role or PUBLIC holds any privilege on either new table');
select is((select count(*)::int from pg_class c where c.oid in ('private.billing_package_scope_approvals'::regclass,
  'private.billing_package_scope_eligibility'::regclass) and c.relacl is not null and c.relacl::text ~ '(anon|authenticated|service_role)='),
  0, 'neither new table carries an ACL entry for an API role');
select is((select string_agg(tgname, ',' order by tgname) from pg_trigger
  where tgrelid = 'private.billing_package_scope_approvals'::regclass and not tgisinternal),
  'billing_package_scope_approvals_append_only,billing_package_scope_approvals_no_truncate', 'approvals: append-only and no-truncate triggers');
select is((select string_agg(tgname, ',' order by tgname) from pg_trigger
  where tgrelid = 'private.billing_package_scope_eligibility'::regclass and not tgisinternal),
  'billing_package_scope_eligibility_append_only,billing_package_scope_eligibility_no_truncate', 'eligibility: append-only and no-truncate triggers');
select is((select confrelid::regclass::text from pg_constraint where conname = 'billing_package_scope_eligibility_version_fkey'),
  'private.billing_package_scope_versions', 'eligibility has a foreign key to the sealed versions');
select is((select count(*)::int from pg_constraint where conrelid = 'private.billing_package_scope_eligibility'::regclass
  and contype = 'f'), 1, 'eligibility has exactly one foreign key (none to the approvals)');
select is((select string_agg(p.proname || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ';'), '-'), ',' order by p.proname)
  from pg_proc p where p.pronamespace = 'private'::regnamespace and p.proname in ('record_package_scope_approval',
  'load_package_scope_version', 'activate_package_scope_version', 'withdraw_package_scope_version', 'current_package_scope')),
  'activate_package_scope_version:true:search_path="",current_package_scope:true:search_path="",load_package_scope_version:true:search_path="",record_package_scope_approval:true:search_path="",withdraw_package_scope_version:true:search_path=""',
  'the four Owner functions and the resolver are SECURITY DEFINER with an empty search_path');
select is((select string_agg(p.proname || ':' || p.prosecdef, ',' order by p.proname) from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.proname in ('record_package_scope_approval',
  'load_package_scope_version', 'activate_package_scope_version', 'withdraw_package_scope_version')),
  'activate_package_scope_version:false,load_package_scope_version:false,record_package_scope_approval:false,withdraw_package_scope_version:false',
  'the four public wrappers are SECURITY INVOKER');
select ok(not has_function_privilege('anon', 'public.load_package_scope_version(text,integer,text[])', 'execute')
  and not has_function_privilege('anon', 'public.activate_package_scope_version(text,integer)', 'execute')
  and not has_function_privilege('anon', 'public.withdraw_package_scope_version(text,integer)', 'execute')
  and not has_function_privilege('anon', 'public.record_package_scope_approval(text,integer,text,text,text)', 'execute'),
  'anon cannot execute any wrapper');
select ok(not has_function_privilege('anon', 'private.current_package_scope(text)', 'execute')
  and not has_function_privilege('authenticated', 'private.current_package_scope(text)', 'execute')
  and not has_function_privilege('service_role', 'private.current_package_scope(text)', 'execute'), 'no API role executes the resolver');
select is(pg_get_function_identity_arguments('private.load_package_scope_version(text,integer,text[])'::regprocedure),
  'p_package_key text, p_scope_version integer, p_items text[]', 'C-2: the load request has no hash parameter (the approval supplies it)');
select is((select provolatile::text from pg_proc where oid = 'private.current_package_scope(text)'::regprocedure), 'v',
  'the resolver is volatile, so it reads only after its eligibility lock (serialization)');
select is((select pg_get_function_result(oid) || ' / ' || pg_get_function_identity_arguments(oid) from pg_proc
  where oid = 'private.current_package_scope(text)'::regprocedure),
  'TABLE(scope_version integer, item_position smallint, item_text text) / p_package_key text', 'the resolver signature is unchanged');
-- Isolation: a client, Sales and Admin session cannot read either table.
select pg_temp.use_session('00000000-0000-4000-8000-0000000000a1', pg_temp.id('cli'), 'aal2', true);
select throws_ok($$ select count(*) from private.billing_package_scope_approvals $$, '42501', null, 'a client cannot read the approvals');
select throws_ok($$ select count(*) from private.billing_package_scope_eligibility $$, '42501', null, 'a client cannot read the eligibility');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('sal'), 'aal2', true);
select throws_ok($$ select count(*) from private.billing_package_scope_eligibility $$, '42501', null, 'Sales cannot read the eligibility');
select throws_ok($$ insert into private.billing_package_scope_eligibility values ('professional', 1, 'activated', 'development', repeat('a', 64), gen_random_uuid(), now()) $$,
  '42501', null, 'Sales cannot write the eligibility');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000002', pg_temp.id('adm'), 'aal2', true);
select throws_ok($$ select count(*) from private.billing_package_scope_approvals $$, '42501', null, 'Admin cannot read the approvals');
reset role;

-- ===========================================================================
-- 2. Owner only, fresh MFA, live session (B-2 coverage): every unauthorized caller is refused by
--    each of the four functions; every refusal is returned (not raised) and audited with the call
-- ===========================================================================
-- Calls all four wrappers as the current caller and returns their four error codes.
create function pg_temp.try_all() returns text language plpgsql as $$
begin
  return concat_ws(',',
    public.record_package_scope_approval('professional', 2, repeat('a', 64), 'PGTAP-X', repeat('e', 64)) ->> 'error',
    public.load_package_scope_version('professional', 2, array['PGTAP SYNTHETIC SCOPE ITEM X']) ->> 'error',
    public.activate_package_scope_version('professional', 1) ->> 'error',
    public.withdraw_package_scope_version('professional', 1) ->> 'error');
end;
$$;
grant execute on function pg_temp.try_all() to authenticated;
-- A session whose only TOTP verification is ten minutes old (stale MFA).
create function pg_temp.use_stale(p_uid uuid, p_sid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal2',
    'session_id', p_sid, 'amr', jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now() - interval '10 minutes')::bigint)))::text, true);
  set local role authenticated;
end;
$$;
-- Two more callers: a signed-in user with no staff role (with an enrolled TOTP factor), and an
-- Owner whose staff role has been revoked (private.is_owner() is NULL for both).
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change, phone_change_token)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email, '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', ''
from (values ('33000000-0000-4000-8000-000000000001'::uuid, 'norole.330@example.test'),
             ('33000000-0000-4000-8000-000000000002'::uuid, 'revoked.owner.330@example.test')) u (id, email);
insert into public.profiles (id, email, full_name) values
  ('33000000-0000-4000-8000-000000000002', 'revoked.owner.330@example.test', 'Synthetic revoked owner');
insert into public.staff_roles (user_id, role, status) values ('33000000-0000-4000-8000-000000000002', 'owner', 'revoked');
insert into ids select 'nor', pg_temp.act_as('33000000-0000-4000-8000-000000000001', 'aal2', true);
reset role;
insert into ids select 'rev', pg_temp.act_as('33000000-0000-4000-8000-000000000002', 'aal2', true);
reset role;
insert into ids select 'own1', pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal1', false);
reset role;
insert into ids select 'own_ended', pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
reset role;
delete from auth.sessions where id = pg_temp.id('own_ended');

-- anon: no execute privilege on any wrapper, so nothing runs (and nothing can be audited).
set local role anon;
select throws_ok($$ select public.record_package_scope_approval('professional', 2, repeat('a', 64), 'PGTAP-X', repeat('e', 64)) $$,
  '42501', null, 'anon cannot call record_package_scope_approval');
select throws_ok($$ select public.load_package_scope_version('professional', 2, array['PGTAP SYNTHETIC SCOPE ITEM X']) $$,
  '42501', null, 'anon cannot call load_package_scope_version');
select throws_ok($$ select public.activate_package_scope_version('professional', 1) $$, '42501', null, 'anon cannot call activate_package_scope_version');
select throws_ok($$ select public.withdraw_package_scope_version('professional', 1) $$, '42501', null, 'anon cannot call withdraw_package_scope_version');
reset role;
-- Each signed-in caller below gets "forbidden" from all four functions.
select pg_temp.use_session('33000000-0000-4000-8000-000000000001', pg_temp.id('nor'), 'aal2', true);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'a signed-in user without a staff role (fresh MFA) is refused by all four');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-0000000000a1', pg_temp.id('cli'), 'aal2', true);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'a client (fresh MFA) is refused by all four');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('sal'), 'aal2', true);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'Sales (fresh MFA) is refused by all four');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000002', pg_temp.id('adm'), 'aal2', true);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'Admin (fresh MFA) is refused by all four');
reset role;
select pg_temp.use_session('33000000-0000-4000-8000-000000000002', pg_temp.id('rev'), 'aal2', true);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'an Owner whose role is revoked (fresh MFA) is refused by all four');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000001', pg_temp.id('own1'), 'aal1', false);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'the Owner at aal1 (insufficient aal) is refused by all four');
reset role;
select pg_temp.use_stale('00000000-0000-4000-8000-000000000001', pg_temp.id('own'));
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'the Owner with a stale MFA verification is refused by all four');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000001', pg_temp.id('own_ended'), 'aal2', true);
select is(pg_temp.try_all(), 'forbidden,forbidden,forbidden,forbidden', 'the Owner with an ended session is refused by all four');
reset role;
-- Eight refused callers x four functions: each refusal left its own audit event, with the call.
select is(pg_temp.audits('package_scope.approval_rejected'), 8, 'record_package_scope_approval: 8 refusals, 8 audit events');
select is(pg_temp.audits('package_scope.load_rejected'), 8, 'load_package_scope_version: 8 refusals, 8 audit events');
select is(pg_temp.audits('package_scope.activation_rejected'), 8, 'activate_package_scope_version: 8 refusals, 8 audit events');
select is(pg_temp.audits('package_scope.withdrawal_rejected'), 8, 'withdraw_package_scope_version: 8 refusals, 8 audit events');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action like 'package_scope.%_rejected'
  and summary ->> 'reason' = 'forbidden' and actor_user_id is not null), 32, 'all 32 refusal events say forbidden and name the caller');
select is((select count(*)::int from private.billing_package_scope_approvals) + (select count(*)::int from private.billing_package_scope_eligibility),
  0, 'no refused attempt created a record');
select is((select count(*)::int from private.billing_package_scope_versions where not is_test_fixture), 0, 'no refused attempt created a version');

-- ===========================================================================
-- 3. Legal approval records
-- ===========================================================================
select pg_temp.owner();
select is(public.record_package_scope_approval('professional', 2, 'ABC', 'PGTAP-APPROVAL-1', pg_temp.ev()) ->> 'error',
  'invalid_input', 'a malformed content hash is refused');
select is(public.record_package_scope_approval('professional', 2, pg_temp.sha_of('professional', 2, 'p2'), 'has space', pg_temp.ev()) ->> 'error',
  'invalid_input', 'an approval reference outside the identifier charset is refused');
select is(public.record_package_scope_approval('nonexistent', 2, pg_temp.sha_of('professional', 2, 'p2'), 'PGTAP-APPROVAL-1', pg_temp.ev()) ->> 'error',
  'invalid_input', 'an unknown package is refused');
select is(public.record_package_scope_approval('professional', 1, repeat('a', 64), 'PGTAP-APPROVAL-1', pg_temp.ev()) ->> 'error',
  'fixture_not_allowed', 'a fixture version cannot be approved');
select is(public.record_package_scope_approval('professional', 2, pg_temp.sha_of('professional', 2, 'p2'), 'PGTAP-APPROVAL-1', pg_temp.ev()) ->> 'ok',
  'true', 'the Owner records an approval bound to the package, version and exact content hash');
select is(public.record_package_scope_approval('professional', 2, pg_temp.sha_of('professional', 2, 'p2'), 'PGTAP-APPROVAL-1', pg_temp.ev()) ->> 'replayed',
  'true', 'an identical approval replay returns the existing record');
select is(public.record_package_scope_approval('professional', 2, pg_temp.sha_of('professional', 2, 'p2'), 'PGTAP-APPROVAL-2', pg_temp.ev()) ->> 'error',
  'approval_conflict', 'a conflicting approval for the same version fails closed');
select is(public.record_package_scope_approval('professional', 2, pg_temp.sha_of('professional', 2, 'p2x'), 'PGTAP-APPROVAL-1', pg_temp.ev()) ->> 'error',
  'approval_conflict', 'a different content hash for the same version fails closed');
reset role;
select is((select count(*)::int from private.billing_package_scope_approvals), 1, 'exactly one approval exists');
select is(pg_temp.audits('package_scope.approval_recorded'), 1, 'one approval event; the replay added none');
select is(pg_temp.last_reason('package_scope.approval_rejected'), 'approval_conflict', 'the conflict is audited');
select is((select summary ->> 'content_sha256' from public.audit_events where id > (select last_id from mark)
  and action = 'package_scope.approval_recorded'), pg_temp.sha_of('professional', 2, 'p2'), 'the approval event carries the content hash');

-- ===========================================================================
-- 4. Loading and sealing; never activates
-- ===========================================================================
select pg_temp.owner();
select is(public.load_package_scope_version('professional', 2, '{}'::text[]) ->> 'error', 'invalid_input', 'an empty version is refused');
select is(public.load_package_scope_version('professional', 2, array['PGTAP SYNTHETIC', null]) ->> 'error', 'invalid_input', 'a null item is refused');
select is(public.load_package_scope_version('professional', 2, array[repeat('x', 301)]) ->> 'error', 'invalid_input', 'an item over 300 characters is refused');
select is(public.load_package_scope_version('professional', 2, array(select 'PGTAP SYNTHETIC ' || g from generate_series(1, 51) g)) ->> 'error',
  'invalid_input', 'more than 50 items are refused');
select is(public.load_package_scope_version('professional', 3, pg_temp.items('p3')) ->> 'error', 'approval_missing', 'loading needs an approval for the version');
select is(public.load_package_scope_version('professional', 2, pg_temp.items('p2x')) ->> 'error', 'hash_mismatch',
  'content that does not match the approved hash is refused');
reset role;
select is((select count(*)::int from private.billing_package_scope_versions where package_key = 'professional' and scope_version = 2)
  + (select count(*)::int from private.billing_package_scope where package_key = 'professional' and scope_version = 2), 0,
  'a hash mismatch leaves no header and no item');
-- An approval for a version that is not the next one: refused as a version conflict.
select pg_temp.owner();
select is(public.record_package_scope_approval('professional', 4, pg_temp.sha_of('professional', 4, 'p3'), 'PGTAP-APPROVAL-4', pg_temp.ev()) ->> 'ok',
  'true', 'setup: an approval for a later version');
select is(public.load_package_scope_version('professional', 4, pg_temp.items('p3')) ->> 'error', 'version_conflict',
  'loading a version other than the next one fails closed');
-- A sealing error is caught: no partial version, the refusal is audited by SQLSTATE only.
select is(public.record_package_scope_approval('signature', 2, pg_temp.sha_of('signature', 2, 'labelled'), 'PGTAP-APPROVAL-S2', pg_temp.ev()) ->> 'ok',
  'true', 'setup: an approval whose content carries the fixture label');
select is(public.load_package_scope_version('signature', 2, pg_temp.items('labelled')) ->> 'error', 'load_failed',
  'labelled content cannot be loaded as a non-fixture version (the label constraint holds)');
reset role;
select is((select count(*)::int from private.billing_package_scope_versions where package_key = 'signature' and scope_version = 2)
  + (select count(*)::int from private.billing_package_scope where package_key = 'signature' and scope_version = 2), 0,
  'a failed seal leaves no header and no item');
select is((select summary from public.audit_events where id > (select last_id from mark) and action = 'package_scope.load_rejected'
  order by id desc limit 1), '{"reason": "load_failed", "sqlstate": "23514"}'::jsonb, 'the failed seal is audited by code and SQLSTATE only');
-- The successful load.
select pg_temp.owner();
select is(public.load_package_scope_version('professional', 2, pg_temp.items('p2')) - 'replayed',
  jsonb_build_object('ok', true, 'package_key', 'professional', 'scope_version', 2, 'item_count', 3,
    'content_sha256', pg_temp.sha_of('professional', 2, 'p2')), 'the Owner loads and seals version 2 with the approved hash');
select is(public.load_package_scope_version('professional', 2, pg_temp.items('p2')) ->> 'replayed', 'true',
  'an identical load replay returns the existing version');
select is(public.load_package_scope_version('professional', 2, pg_temp.items('p2x')) ->> 'error', 'version_conflict',
  'conflicting content for a sealed version fails closed');
reset role;
select is((select string_agg(scope_version || ':' || item_count || ':' || is_test_fixture || ':' || (content_sha256 = pg_temp.sha_of('professional', 2, 'p2')), ',' order by scope_version)
  from private.billing_package_scope_versions where package_key = 'professional'), '1:3:true:false,2:3:false:true',
  'version 2 is sealed once, non-fixture, with the approved hash; no duplicate version');
select is(pg_temp.audits('package_scope.loaded'), 1, 'one load event; the replay added none');
select is((select count(*)::int from private.billing_package_scope_eligibility), 0, 'loading created no eligibility');
select is(pg_temp.rows('professional'), '', 'loading never activates: the newest version does not resolve');
select is(pg_temp.issue('professional') ->> 'error', 'scope_definition_missing', 'Sales issuance fails closed for a loaded, inactive version');
select is(pg_temp.rows('essential'), '1:1,1:2,1:3', 'other packages are unaffected (fixture version 1 still resolves in development)');

-- ===========================================================================
-- 5. Activation (development and test only; approval bound to the exact sealed hash)
-- ===========================================================================
-- A non-fixture version sealed directly by the database owner, without an approval.
select private.create_package_scope_version('prestige', array['PGTAP SYNTHETIC SCOPE ITEM PR2'], false);
select pg_temp.owner();
select is(public.activate_package_scope_version('essential', 1) ->> 'error', 'fixture_not_allowed', 'a fixture version can never be activated');
select is(public.activate_package_scope_version('professional', 9) ->> 'error', 'version_not_found', 'an unknown version cannot be activated');
select is(public.activate_package_scope_version('prestige', 2) ->> 'error', 'approval_missing', 'a version without an approval cannot be activated');
select is(public.record_package_scope_approval('prestige', 2, repeat('b', 64), 'PGTAP-APPROVAL-P2', pg_temp.ev()) ->> 'error', 'hash_mismatch',
  'an approval cannot be recorded for a sealed version with a different hash');
reset role;
-- A tampered approval (written directly by the database owner) does not activate.
insert into private.billing_package_scope_approvals values ('prestige', 2, repeat('b', 64), 'PGTAP-TAMPERED', pg_temp.ev(),
  '00000000-0000-4000-8000-000000000001', now());
select pg_temp.owner();
select is(public.activate_package_scope_version('prestige', 2) ->> 'error', 'approval_mismatch',
  'an approval whose hash differs from the sealed hash does not activate');
reset role;
-- Classifications other than development and test.
update private.environment_settings set app_env = 'staging';
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 2) ->> 'error', 'classification_not_allowed', 'no activation under staging');
reset role;
update private.environment_settings set app_env = 'preview';
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 2) ->> 'error', 'classification_not_allowed', 'no activation under preview');
reset role;
delete from private.environment_settings;
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 2) ->> 'error', 'classification_not_allowed',
  'no activation under a missing classification (production)');
reset role;
insert into private.environment_settings (app_env) values ('development');
select throws_ok($$ insert into private.billing_package_scope_eligibility values ('professional', 2, 'activated', 'production', repeat('a', 64), gen_random_uuid(), now()) $$,
  '23514', null, 'the table itself refuses a production activation, even from the database owner');
select is((select count(*)::int from private.billing_package_scope_eligibility), 0, 'no refused activation created a record');
-- Activation in development.
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 2) ->> 'ok', 'true', 'the Owner activates version 2 in development');
select is(public.activate_package_scope_version('professional', 2) ->> 'replayed', 'true', 'an activation replay returns the existing activation');
reset role;
select is((select count(*)::int from private.billing_package_scope_eligibility where event = 'activated'), 1, 'exactly one activation; the replay added none');
select is(pg_temp.audits('package_scope.activated'), 1, 'one activation event');
select is(pg_temp.rows('professional'), '2:1,2:2,2:3', 'the activated version resolves, in order');
select is((select string_agg(item_text, '|' order by item_position) from private.current_package_scope('professional')),
  array_to_string(pg_temp.items('p2'), '|'), 'with exactly the loaded items');
select is(pg_temp.issue('professional') ->> 'ok', 'true', 'Sales issuance succeeds for the activated version');
select is((select scope_items from public.order_summaries where project_id = pg_temp.id('prj') order by issued_at desc limit 1),
  to_jsonb(pg_temp.items('p2')), 'the issued order summary carries exactly the activated scope');
-- Activation is per classification.
update private.environment_settings set app_env = 'test';
select is(pg_temp.rows('professional'), '', 'a development activation does not resolve under test');
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 2) ->> 'ok', 'true', 'the Owner activates version 2 for test');
reset role;
select is(pg_temp.rows('professional'), '2:1,2:2,2:3', 'it resolves under test');
update private.environment_settings set app_env = 'staging';
select is(pg_temp.rows('professional'), '', 'an activated version never resolves under staging');
delete from private.environment_settings;
select is(private.app_environment(), 'production', 'setup: a missing classification reads as production');
select is(pg_temp.rows('professional'), '', 'an activated version never resolves under production (missing classification)');
insert into private.environment_settings (app_env) values ('development');
-- Tampering with sealed items makes the version fail closed (integrity re-verified at every call).
set local session_replication_role = replica;
update private.billing_package_scope set item_text = 'PGTAP SYNTHETIC SCOPE ITEM TAMPERED'
  where package_key = 'professional' and scope_version = 2 and position = 2;
set local session_replication_role = origin;
select is(pg_temp.rows('professional'), '', 'a tampered active version resolves nothing (no fallback)');
update private.environment_settings set app_env = 'test';
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 2) ->> 'error', 'integrity_failure',
  'activation re-verifies the sealed items and refuses a tampered version');
reset role;
update private.environment_settings set app_env = 'development';
set local session_replication_role = replica;
update private.billing_package_scope set item_text = 'PGTAP SYNTHETIC SCOPE ITEM P2-B'
  where package_key = 'professional' and scope_version = 2 and position = 2;
set local session_replication_role = origin;
select is(pg_temp.rows('professional'), '2:1,2:2,2:3', 'setup: the restored version resolves again');

-- ===========================================================================
-- 6. A newer loaded version suspends issuance; no fallback to an older version
-- ===========================================================================
select pg_temp.owner();
select is(public.record_package_scope_approval('professional', 3, pg_temp.sha_of('professional', 3, 'p3'), 'PGTAP-APPROVAL-3', pg_temp.ev()) ->> 'ok',
  'true', 'setup: an approval for version 3');
select is(public.load_package_scope_version('professional', 3, pg_temp.items('p3')) ->> 'ok', 'true', 'the Owner loads version 3');
reset role;
select is(pg_temp.rows('professional'), '', 'loading version 3 suspends issuance: no fallback to the active version 2');
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 3) ->> 'ok', 'true', 'the Owner activates version 3');
reset role;
select is(pg_temp.rows('professional'), '3:1', 'version 3 resolves after activation');

-- ===========================================================================
-- 7. Withdrawal: irreversible, no reactivation, no fallback
-- ===========================================================================
select pg_temp.owner();
select is(public.withdraw_package_scope_version('professional', 9) ->> 'error', 'version_not_found', 'an unknown version cannot be withdrawn');
select is(public.withdraw_package_scope_version('professional', 3) ->> 'ok', 'true', 'the Owner withdraws version 3');
select is(public.withdraw_package_scope_version('professional', 3) ->> 'replayed', 'true', 'a withdrawal replay returns the existing withdrawal');
select is(public.activate_package_scope_version('professional', 3) ->> 'error', 'withdrawn', 'a withdrawn version is never reactivated');
reset role;
select is(pg_temp.rows('professional'), '', 'a withdrawn newest version resolves nothing: no fallback to version 2');
select is(pg_temp.issue('professional') ->> 'error', 'scope_definition_missing', 'Sales issuance fails closed after withdrawal');
update private.environment_settings set app_env = 'test';
select pg_temp.owner();
select is(public.activate_package_scope_version('professional', 3) ->> 'error', 'withdrawn', 'nor under another classification');
reset role;
select is(pg_temp.rows('professional'), '', 'the withdrawal applies in every classification');
update private.environment_settings set app_env = 'development';
select is((select count(*)::int from private.billing_package_scope_eligibility where event = 'withdrawn'), 1, 'exactly one withdrawal; the replay added none');
select is(pg_temp.audits('package_scope.withdrawn'), 1, 'one withdrawal event');
select is(pg_temp.last_reason('package_scope.activation_rejected'), 'withdrawn', 'the reactivation attempt is audited');
-- A withdrawn fixture version also resolves nothing (no fallback).
select pg_temp.owner();
select is(public.withdraw_package_scope_version('advanced', 1) ->> 'ok', 'true', 'the Owner withdraws fixture version 1 of advanced');
reset role;
select is(pg_temp.rows('advanced'), '', 'a withdrawn fixture version resolves nothing');

-- ===========================================================================
-- 8. Append-only records; sealed content unchanged; no item text anywhere
-- ===========================================================================
select throws_ok($$ update private.billing_package_scope_eligibility set classification = 'test' $$, '42501', null, 'eligibility events cannot be updated');
select throws_ok($$ delete from private.billing_package_scope_eligibility $$, '42501', null, 'eligibility events cannot be deleted');
select throws_ok($$ truncate private.billing_package_scope_eligibility $$, '42501', null, 'eligibility events cannot be truncated');
select throws_ok($$ update private.billing_package_scope_approvals set approval_reference = 'X' $$, '42501', null, 'approvals cannot be updated');
select throws_ok($$ delete from private.billing_package_scope_approvals $$, '42501', null, 'approvals cannot be deleted');
select throws_ok($$ truncate private.billing_package_scope_approvals $$, '42501', null, 'approvals cannot be truncated');
-- B-4: both truncation attempts are refused and neither protected table loses data.
create temp table b4_before as select
  (select count(*) from private.billing_package_scope_versions) hn, (select count(*) from private.billing_package_scope_eligibility) en,
  (select md5(string_agg(package_key || '|' || scope_version || '|' || content_sha256, ',' order by package_key, scope_version))
     from private.billing_package_scope_versions) hd,
  (select md5(string_agg(package_key || '|' || scope_version || '|' || event || '|' || classification || '|' || approved_sha256, ','
     order by package_key, scope_version, event, classification)) from private.billing_package_scope_eligibility) ed;
select throws_ok($$ truncate private.billing_package_scope_versions cascade $$, '42501', null,
  'truncating the sealed headers with CASCADE is refused by the no-truncate triggers (42501)');
select is(pg_temp.error_of($$ truncate private.billing_package_scope_versions $$) like '0A000 %', true,
  'truncating the sealed headers alone is refused (referenced by the eligibility foreign key)');
select is((select row(hn, en, hd, ed)::text from b4_before), (select row(
  (select count(*) from private.billing_package_scope_versions), (select count(*) from private.billing_package_scope_eligibility),
  (select md5(string_agg(package_key || '|' || scope_version || '|' || content_sha256, ',' order by package_key, scope_version))
     from private.billing_package_scope_versions),
  (select md5(string_agg(package_key || '|' || scope_version || '|' || event || '|' || classification || '|' || approved_sha256, ','
     order by package_key, scope_version, event, classification)) from private.billing_package_scope_eligibility))::text),
  'neither protected table lost data after both truncation attempts (row counts and content hashes unchanged)');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action like 'package_scope.%'
  and (summary::text ~* 'PGTAP SYNTHETIC|NOT A DELIVERABLE' or coalesce(reason, '') ~* 'PGTAP SYNTHETIC|NOT A DELIVERABLE')), 0,
  'no audit event contains item text');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action like 'package_scope.%'), 
  (select count(*)::int from public.audit_events where id > (select last_id from mark) and action like 'package_scope.%' and actor_user_id is not null),
  'every package-scope event names its actor');
select pg_temp.owner();
select ok(public.load_package_scope_version('signature', 2, pg_temp.items('labelled'))::text !~* 'NOT A DELIVERABLE|PGTAP',
  'a refused load returns no item text');
reset role;
select is((select count(*)::int from private.billing_package_scope where is_test_fixture), 15, 'the seed fixtures are unchanged (5 packages x 3 items)');

-- ===========================================================================
-- 9. F-1 (WP-C review): audit targets never carry caller-supplied text
-- ===========================================================================
create temp table f1_mark as select coalesce(max(id), 0) as m from public.audit_events;
create function pg_temp.long_key() returns text language sql as $$ select repeat('k', 200000) $$;
grant execute on function pg_temp.long_key() to authenticated;
select pg_temp.use_session('00000000-0000-4000-8000-0000000000a1', pg_temp.id('cli'), 'aal2', true);
select is(public.load_package_scope_version(pg_temp.long_key(), 2, array['PGTAP SYNTHETIC SCOPE ITEM F1']) ->> 'error', 'forbidden',
  'F-1: a client with a 200,000-character key is refused');
reset role;
select is((select string_agg(action || '=' || target_id, ',') from public.audit_events where id > (select m from f1_mark)),
  'package_scope.load_rejected=invalid:2', 'F-1: exactly one refusal row for the client, target invalid:2 (bounded)');
create temp table f1_mark2 as select coalesce(max(id), 0) as m from public.audit_events;
select pg_temp.owner();
select is(public.load_package_scope_version(pg_temp.long_key(), 2, array['PGTAP SYNTHETIC SCOPE ITEM F1']) ->> 'error', 'invalid_input',
  'F-1: the Owner with a 200,000-character key is refused as invalid input');
select is(public.record_package_scope_approval(pg_temp.long_key(), 2, repeat('a', 64), 'PGTAP-F1', pg_temp.ev()) ->> 'error', 'invalid_input',
  'F-1: the same for an approval');
select is(public.activate_package_scope_version(pg_temp.long_key(), 2) ->> 'error', 'version_not_found', 'F-1: activation of an unknown key is refused');
select is(public.withdraw_package_scope_version(pg_temp.long_key(), null) ->> 'error', 'invalid_input', 'F-1: withdrawal with a null version is refused');
reset role;
select is((select string_agg(action || '=' || target_id, ',' order by id) from public.audit_events where id > (select m from f1_mark2)),
  'package_scope.load_rejected=invalid:2,package_scope.approval_rejected=invalid:2,package_scope.activation_rejected=invalid:2,'
  || 'package_scope.withdrawal_rejected=invalid:invalid',
  'F-1: one refusal row per Owner call, each with a bounded target (invalid key, version or invalid)');
select is((select count(*)::int from public.audit_events where id > (select m from f1_mark)
  and (octet_length(coalesce(target_id, '')) > 64 or summary::text ~ 'kkkk' or coalesce(reason, '') ~ 'kkkk')), 0,
  'F-1: no audit row carries the caller-supplied key or any unbounded caller text');

select * from finish();
rollback;
