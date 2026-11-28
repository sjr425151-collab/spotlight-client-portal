-- OI-120 (AUTH-019): private.is_owner() is NULL-safe, so every Owner guard refuses a caller who is
-- not an active Owner. Regressions for the three reproduced escalations; one representative per
-- affected site class, called by a fresh-MFA client, a revoked former staff member with fresh MFA,
-- an Admin, a Sales user and anon, with no privileged state change; the genuine Owner still
-- succeeds; is_owner() and owner_ok() are false (never NULL) for non-Owners; attributes and ACL
-- unchanged. Synthetic data, inside this rolled-back transaction.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(60);

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
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  set local role authenticated;
  return v_sid;
end;
$$;
-- The project used for project-scoped calls: seeded Project A (client A is its member; Project B is not).
create function pg_temp.state() returns text language sql as $$
  select concat_ws('|',
    (select count(*) from public.agreement_versions where version_label like 'OI120-%'),
    (select count(*) from public.invitations where lower(email) like 'oi120.%'),
    (select count(*) from public.client_site_targets where project_id = '20000000-0000-4000-8000-0000000000a0'),
    (select count(*) from public.billing_holds where project_id = '20000000-0000-4000-8000-0000000000a0'),
    (select string_agg(user_id || ':' || role || ':' || status, ',' order by user_id) from public.staff_roles))
$$;
create temp table before_state as select pg_temp.state() s;
create temp table results (k text primary key, v text);
grant select, insert on results to authenticated;
-- Calls one representative of each affected site class as the current caller; records the result.
create function pg_temp.try_all(p_who text) returns void language plpgsql as $$
begin
  -- class (a), contractual: create_agreement_version (20261124160000:216)
  insert into results values (p_who || ':agreement',
    coalesce(public.create_agreement_version('OI120-' || p_who, 'OI-120 synthetic probe text', current_date, null) ->> 'error', 'ok'));
  -- class (a), staff invitation: create_invitation with kind staff (20261125120100:278)
  insert into results values (p_who || ':invitation', coalesce(public.create_invitation('staff', 'oi120.' || p_who || '@example.test',
    'OI-120 probe', null, 'admin') ->> 'error', 'ok'));
  -- class (a), WP-C: register_client_site_target (20261124140200:1286)
  insert into results values (p_who || ':site_target',
    coalesce(public.register_client_site_target('20000000-0000-4000-8000-0000000000a0', 'oi120-' || p_who) ->> 'error', 'ok'));
  -- class (b): set_staff_role, the reproduced escalation (client promotes the Admin to Owner) (20261125120100:468)
  insert into results values (p_who || ':staff_role',
    coalesce(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'owner', 'OI-120 probe') ->> 'error', 'ok'));
  -- class (c), owner_ok() callers: place_billing_hold (20261124160100:3648, via owner_ok at :3638)
  insert into results values (p_who || ':billing_hold',
    coalesce(public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold', 'OI-120 probe') ->> 'error', 'ok'));
  -- class (c), expression with a member path: project_billing_status on a project the caller is not a member of (:4709)
  insert into results values (p_who || ':billing_status',
    coalesce(public.project_billing_status('20000000-0000-4000-8000-0000000000b0') ->> 'error', 'ok'));
  insert into results values (p_who || ':is_owner', coalesce(private.is_owner()::text, 'NULL'));
end;
$$;
-- owner_ok() has no API grant: evaluated by the test owner right after `reset role`, with the
-- caller's JWT claims still set, so it sees the same caller identity.
create function pg_temp.capture_owner_ok(p_who text) returns void language sql as $$
  insert into results values (p_who || ':owner_ok', coalesce(private.owner_ok(false)::text, 'NULL') || ','
    || coalesce(private.owner_ok(true)::text, 'NULL'));
$$;
grant execute on function pg_temp.try_all(text) to authenticated;
create function pg_temp.r(p_k text) returns text language sql as $$ select v from results where k = p_k $$;

-- ===========================================================================
-- 1. Attributes and ACL of private.is_owner() are unchanged
-- ===========================================================================
select is((select pg_get_userbyid(p.proowner) || '|' || l.lanname || '|' || p.provolatile::text || '|' || p.prosecdef::text || '|'
  || array_to_string(p.proconfig, ';') || '|' || p.proacl::text || '|' || pg_get_function_result(p.oid) || '|'
  || pg_get_function_identity_arguments(p.oid)
  from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = 'private.is_owner()'::regprocedure),
  'postgres|sql|s|true|search_path=""|{postgres=X/postgres,authenticated=X/postgres}|boolean|',
  'is_owner keeps owner, language, volatility, SECURITY DEFINER, search_path, ACL and signature');
select is((select count(*)::int from pg_proc where proname = 'is_owner' and pronamespace = 'private'::regnamespace), 1,
  'exactly one is_owner (no overload)');
select ok((select prosrc ~ 'coalesce\(private\.staff_role_of\(\(select auth\.uid\(\)\)\) = ''owner'', false\)'
  from pg_proc where oid = 'private.is_owner()'::regprocedure), 'is_owner coalesces to false');

-- ===========================================================================
-- 2. Refused callers: fresh-MFA client, Admin, Sales, revoked former staff member
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select pg_temp.try_all('client');
reset role;
select pg_temp.capture_owner_ok('client');
select pg_temp.act_as('00000000-0000-4000-8000-000000000005');
select pg_temp.try_all('sales');
reset role;
select pg_temp.capture_owner_ok('sales');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002');
select pg_temp.try_all('admin');
-- Extra guard: the Admin promoting itself to Owner (already refused before OI-120; stays refused).
insert into results values ('admin:self_promotion',
  coalesce(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'owner', 'OI-120 self') ->> 'error', 'ok'));
reset role;
select pg_temp.capture_owner_ok('admin');
-- Revoked former staff member (225/240 pattern: the Admin, because the only Owner cannot be revoked).
update public.staff_roles set status = 'revoked', revoked_at = now() where user_id = '00000000-0000-4000-8000-000000000002';
create temp table revoked_state as select pg_temp.state() s;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002');
select pg_temp.try_all('revoked');
reset role;
select pg_temp.capture_owner_ok('revoked');

-- Regression 1: a fresh-MFA client cannot create an agreement version.
select is(pg_temp.r('client:agreement'), 'forbidden', 'regression 1: a fresh-MFA client cannot create an agreement version');
-- Regression 2: a fresh-MFA client cannot promote the Admin to Owner.
select is(pg_temp.r('client:staff_role'), 'forbidden', 'regression 2: a fresh-MFA client cannot promote the Admin to Owner (set_staff_role)');
-- Regression 3: a revoked former staff member cannot re-grant itself Owner.
select is(pg_temp.r('revoked:staff_role'), 'forbidden', 'regression 3: a revoked former staff member cannot re-grant itself Owner');
select is(pg_temp.r('admin:self_promotion'), 'forbidden', 'extra guard: the Admin cannot promote itself to Owner');

-- Every representative refuses every non-Owner caller.
select isnt(pg_temp.r(w || ':' || f), 'ok', f || ' refuses the ' || w)
  from unnest(array['client', 'sales', 'admin', 'revoked']) w,
       unnest(array['agreement', 'invitation', 'site_target', 'staff_role', 'billing_hold', 'billing_status']) f;
-- is_owner() and owner_ok() are false, never NULL, for every non-Owner.
select is(pg_temp.r(w || ':is_owner'), 'false', 'is_owner() is false (not NULL) for the ' || w)
  from unnest(array['client', 'sales', 'admin', 'revoked']) w;
select is(pg_temp.r(w || ':owner_ok'), 'false,false', 'owner_ok() is false (not NULL) for the ' || w)
  from unnest(array['client', 'sales', 'admin', 'revoked']) w;
-- No privileged state change by any refused caller.
select is(pg_temp.state(), (select s from revoked_state), 'no refused caller changed any privileged state (row counts and staff roles)');
select is((select s from revoked_state), regexp_replace((select s from before_state),
  '00000000-0000-4000-8000-000000000002:admin:active', '00000000-0000-4000-8000-000000000002:admin:revoked'),
  'before the revocation, the client, Sales and Admin calls changed nothing either');

-- ===========================================================================
-- 3. anon cannot execute any representative
-- ===========================================================================
set local role anon;
select throws_ok($$ select public.create_agreement_version('OI120-anon', 'x', current_date, null) $$, '42501', null, 'anon cannot create an agreement version');
select throws_ok($$ select public.create_invitation('staff', 'oi120.anon@example.test', 'x', null, 'admin') $$, '42501', null, 'anon cannot create a staff invitation');
select throws_ok($$ select public.register_client_site_target('20000000-0000-4000-8000-0000000000a0', 'oi120-anon') $$, '42501', null, 'anon cannot register a site target');
select throws_ok($$ select public.set_staff_role('00000000-0000-4000-8000-000000000002', 'owner', 'x') $$, '42501', null, 'anon cannot set a staff role');
select throws_ok($$ select public.place_billing_hold('20000000-0000-4000-8000-0000000000a0', 'owner_manual_hold', 'x') $$, '42501', null, 'anon cannot place a billing hold');
select throws_ok($$ select public.project_billing_status('20000000-0000-4000-8000-0000000000b0') $$, '42501', null, 'anon cannot read billing status');
reset role;
select is(pg_temp.state(), (select s from revoked_state), 'anon changed nothing');

-- ===========================================================================
-- 4. The genuine Owner with fresh MFA still succeeds
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000001');
select pg_temp.try_all('owner');
select is(coalesce(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'admin', 'OI-120 restore') ->> 'error', 'ok'), 'ok',
  'the Owner can still restore the revoked Admin (set_staff_role)');
reset role;
select pg_temp.capture_owner_ok('owner');
select is(pg_temp.r('owner:agreement'), 'ok', 'the Owner still creates an agreement version');
select is(pg_temp.r('owner:invitation'), 'ok', 'the Owner still creates a staff invitation');
select is(pg_temp.r('owner:site_target'), 'ok', 'the Owner still registers a site target');
select is(pg_temp.r('owner:billing_hold'), 'ok', 'the Owner still places a billing hold');
select is(pg_temp.r('owner:billing_status'), 'ok', 'the Owner still reads billing status of any project');
select is(pg_temp.r('owner:is_owner'), 'true', 'is_owner() is true for the Owner');
select is(pg_temp.r('owner:owner_ok'), 'true,true', 'owner_ok() is true for the Owner with fresh MFA');
select is(pg_temp.r('owner:staff_role'), 'ok', 'the Owner can still change a staff role');
select is((select role::text || ':' || status::text from public.staff_roles where user_id = '00000000-0000-4000-8000-000000000002'),
  'admin:active', 'the Owner restored the Admin');
select is((select count(*)::int from public.agreement_versions where version_label like 'OI120-%'), 1, 'only the Owner''s agreement version exists');
-- The Owner without fresh MFA is still refused by a fresh-MFA guard.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.create_agreement_version('OI120-stale', 'x', current_date, null) ->> 'error', 'forbidden', 'the Owner without fresh MFA is still refused');
reset role;

select * from finish();
rollback;
