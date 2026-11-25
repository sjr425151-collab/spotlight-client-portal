-- WP-S correction: staff/client separation in the database (OI-85; CURRENT-STATE §12 C1 to C4)
-- with the enforcement ENABLED. T-SALES-24 (trigger and C1 parts; the authorization-without-
-- triggers fixture is in 300 and 310). The concurrent cases run in the integration suite.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(32);

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
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
create function pg_temp.new_user(p_id uuid, p_email text) returns void language plpgsql as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change,
    phone_change_token)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email, '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '');
  insert into public.profiles (id, email, full_name) values (p_id, p_email, 'Synthetic ' || p_email);
end;
$$;

-- Users: S1 (seeded Sales), M (client of Project B), X (Admin), R (revoked Sales).
select pg_temp.new_user('43000000-0000-4000-8000-0000000000c1', 'oi85.client@example.test');
insert into public.project_memberships (project_id, user_id) values
  ('20000000-0000-4000-8000-0000000000b0', '43000000-0000-4000-8000-0000000000c1');
select pg_temp.new_user('43000000-0000-4000-8000-0000000000a1', 'oi85.admin@example.test');
insert into public.staff_roles (user_id, role) values ('43000000-0000-4000-8000-0000000000a1', 'admin');

-- ---------------------------------------------------------------------------
-- Catalog: the enforcement exists, is enabled, and is not callable by any API role
-- ---------------------------------------------------------------------------
select is((select array_agg(tgname::text || ':' || tgenabled::text order by tgname) from pg_trigger
  where tgname in ('project_memberships_sales_separation', 'staff_roles_sales_separation',
                   'billing_package_scope_append_only', 'billing_package_scope_no_truncate')),
  array['billing_package_scope_append_only:O', 'billing_package_scope_no_truncate:O',
        'project_memberships_sales_separation:O', 'staff_roles_sales_separation:O'],
  'C2, C3, C5: every trigger exists and is enabled');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('project_memberships_sales_separation', 'staff_roles_sales_separation')
    and p.prosecdef and p.proconfig @> array['search_path=""']
    and not has_function_privilege('authenticated', p.oid, 'execute')
    and not has_function_privilege('service_role', p.oid, 'execute')
    and not has_function_privilege('anon', p.oid, 'execute')), 2,
  'C2, C3: SECURITY DEFINER, search_path = '''', no API-role execute');
select is((select count(*)::int from public.staff_roles s join public.project_memberships m on m.user_id = s.user_id
  and m.status = 'active' where s.status = 'active' and s.role = 'sales'), 0,
  'C4: no conflicting data exists after the migration (the migration-time check found none)');

-- ---------------------------------------------------------------------------
-- C2: no active membership for an active Sales user, for every writer
-- ---------------------------------------------------------------------------
select pg_temp.as_service();
select throws_ok($$ insert into public.project_memberships (project_id, user_id)
  values ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000005') $$, '42501',
  'OI-85: a user with an active Sales role cannot hold an active project membership',
  'C2: service_role cannot insert a membership for a Sales Representative');
reset role;
select throws_ok($$ insert into public.project_memberships (project_id, user_id)
  values ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000005') $$, '42501',
  'OI-85: a user with an active Sales role cannot hold an active project membership',
  'C2: the migration owner cannot insert one either');
insert into public.project_memberships (project_id, user_id, status, revoked_at)
values ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000005', 'revoked', now());
select pass('C2: a revoked (inactive) membership row for a Sales user is not a conflict');
select throws_ok($$ update public.project_memberships set status = 'active', revoked_at = null
  where user_id = '00000000-0000-4000-8000-000000000005' $$, '42501',
  'OI-85: a user with an active Sales role cannot hold an active project membership',
  'C2: re-activating a membership of a Sales user is rejected (update)');
select throws_ok($$ update public.project_memberships set user_id = '00000000-0000-4000-8000-000000000005'
  where user_id = '43000000-0000-4000-8000-0000000000c1' $$, '42501',
  'OI-85: a user with an active Sales role cannot hold an active project membership',
  'C2: moving an active membership onto a Sales user is rejected (update)');
select is((select count(*)::int from public.project_memberships where user_id = '00000000-0000-4000-8000-000000000005' and status = 'active'), 0,
  'C2: the Sales user holds no active membership');

-- ---------------------------------------------------------------------------
-- C3: no active Sales role for a user with an active membership, for every writer
-- ---------------------------------------------------------------------------
select pg_temp.as_service();
select throws_ok($$ insert into public.staff_roles (user_id, role) values ('43000000-0000-4000-8000-0000000000c1', 'sales') $$, '42501',
  'OI-85: a user with an active project membership cannot hold an active Sales role',
  'C3: service_role cannot give the Sales role to a client');
reset role;
select throws_ok($$ insert into public.staff_roles (user_id, role) values ('43000000-0000-4000-8000-0000000000c1', 'sales') $$, '42501',
  'OI-85: a user with an active project membership cannot hold an active Sales role',
  'C3: the migration owner cannot either');
insert into public.staff_roles (user_id, role, status, revoked_at) values ('43000000-0000-4000-8000-0000000000c1', 'sales', 'revoked', now());
select pass('C3: a revoked (inactive) Sales role for a client is not a conflict');
select throws_ok($$ update public.staff_roles set status = 'active', revoked_at = null where user_id = '43000000-0000-4000-8000-0000000000c1' $$, '42501',
  'OI-85: a user with an active project membership cannot hold an active Sales role',
  'C3: re-activating the Sales role of a client is rejected (update)');
update public.staff_roles set role = 'admin', status = 'active', revoked_at = null where user_id = '43000000-0000-4000-8000-0000000000c1';
select pass('C3: scoped to Sales: an active Admin role for a user with a membership is permitted (03 §4.1(a); 225)');
select throws_ok($$ update public.staff_roles set role = 'sales' where user_id = '43000000-0000-4000-8000-0000000000c1' $$, '42501',
  'OI-85: a user with an active project membership cannot hold an active Sales role',
  'C3: changing that Admin role to Sales is rejected (update)');
update public.staff_roles set status = 'revoked', revoked_at = now() where user_id = '43000000-0000-4000-8000-0000000000c1';
-- Owner and Admin memberships stay permitted (C2 is Sales-only) and grant no client authorization (C1).
insert into public.project_memberships (project_id, user_id) values
  ('20000000-0000-4000-8000-0000000000a0', '43000000-0000-4000-8000-0000000000a1');
select pass('C2: scoped to Sales: an Admin may hold a membership');

-- ---------------------------------------------------------------------------
-- The approved paths keep their own audited rejections; the trigger is the backstop
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.set_staff_role('43000000-0000-4000-8000-0000000000a1', 'sales', 'x') ->> 'error', 'client_membership',
  'set_staff_role still returns its audited client_membership rejection (not a trigger error)');
reset role;
select is(private.staff_role_of('43000000-0000-4000-8000-0000000000a1'), 'admin'::public.staff_role, 'the role is unchanged');

-- ---------------------------------------------------------------------------
-- C1: is_project_member excludes every staff role; clients and staff paths unchanged
-- ---------------------------------------------------------------------------
select pg_temp.act_as('43000000-0000-4000-8000-0000000000a1', 'aal2');
select is(private.is_project_member('20000000-0000-4000-8000-0000000000a0'), false,
  'C1: an Admin with a membership is not a project member for client authorization');
select is(private.can_access_project('20000000-0000-4000-8000-0000000000a0'), true,
  'C1: the Admin still reaches the project through its staff path');
select is((select count(*)::int from public.projects where id = '20000000-0000-4000-8000-0000000000a0'), 1,
  'C1: and still reads it (policies OR is_staff())');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(private.is_staff() and private.can_access_project('20000000-0000-4000-8000-0000000000b0'), true,
  'C1: the Owner path is unchanged');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(private.is_project_member('20000000-0000-4000-8000-0000000000a0'), true, 'C1: a client is still a project member');
select is(private.is_project_member('20000000-0000-4000-8000-0000000000b0'), false, 'C1: but not of another project');
select is((select count(*)::int from public.projects), 1, 'C1: the client reads only its project');
select is(public.project_status('20000000-0000-4000-8000-0000000000a0') ->> 'ok', 'true', 'C1: the client reads its project status');
reset role;
-- A former staff member whose role is revoked and who holds a membership is a client (225, OI-78).
select pg_temp.act_as('43000000-0000-4000-8000-0000000000c1');
select is(private.is_project_member('20000000-0000-4000-8000-0000000000b0'), true,
  'C1: a user whose staff roles are all revoked is a client again');
reset role;
-- Deactivated users stay excluded (existing condition kept).
update public.profiles set status = 'deactivated' where id = '43000000-0000-4000-8000-0000000000c1';
select pg_temp.act_as('43000000-0000-4000-8000-0000000000c1');
select is(private.is_project_member('20000000-0000-4000-8000-0000000000b0'), false, 'C1: a deactivated user is not a member');
reset role;

-- ---------------------------------------------------------------------------
-- The client path through the database keeps working (invitation, acceptance, membership)
-- ---------------------------------------------------------------------------
select pg_temp.new_user('43000000-0000-4000-8000-0000000000d1', 'oi85.newclient@example.test');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
create temp table inv as select public.create_invitation('client', 'oi85.newclient@example.test', 'New', '20000000-0000-4000-8000-0000000000a0') as r;
grant select on inv to authenticated;
reset role;
select pg_temp.act_as('43000000-0000-4000-8000-0000000000d1');
select is(public.accept_invitation(((select r from inv) ->> 'invitation_id')::uuid, (select r from inv) ->> 'token') ->> 'ok', 'true',
  'client workflow: an invited client accepts (the C2 trigger admits a non-Sales user)');
select is((select count(*)::int from public.projects where id = '20000000-0000-4000-8000-0000000000a0'), 1,
  'client workflow: and reads the project');
reset role;
-- The Sales staff invitation path still refuses a client with its audited reason.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
create temp table inv2 as select public.create_invitation('staff', 'oi85.newclient@example.test', 'New', null, 'sales') as r;
grant select on inv2 to authenticated;
reset role;
select pg_temp.act_as('43000000-0000-4000-8000-0000000000d1');
select is(public.accept_invitation(((select r from inv2) ->> 'invitation_id')::uuid, null) ->> 'error', 'invalid',
  'accept_invitation still returns its audited client_membership rejection (not a trigger error)');
reset role;
select is((select summary ->> 'reason' from public.audit_events where action = 'invitation.accept_failed'
  and target_id = (select r from inv2) ->> 'invitation_id'), 'client_membership', 'the rejection is audited with its reason');

select * from finish();
rollback;
