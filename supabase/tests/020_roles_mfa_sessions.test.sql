-- Roles, MFA assurance, fresh reauthentication, and live sessions
-- (spec 03 §3-§7; T-ROLE-01, T-ROLE-02, T-ROLE-03, T-ROLE-07, T-ROLE-08, T-AUTH-04, T-AUTH-05, T-AUTH-10).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(35);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_totp_age interval default null)
returns uuid language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
  v_amr jsonb := jsonb_build_array(jsonb_build_object('method', 'otp',
                   'timestamp', extract(epoch from now() - interval '1 hour')::bigint));
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  -- aal2 also requires a verified factor (private.is_aal2).
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  -- The totp entry is deliberately NOT first: the freshness check must not rely on amr order.
  if p_totp_age is not null then
    v_amr := v_amr || jsonb_build_array(jsonb_build_object('method', 'totp',
               'timestamp', extract(epoch from now() - p_totp_age)::bigint));
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated', 'aal', p_aal, 'amr', v_amr, 'session_id', v_sid)::text, true);
  set local role authenticated;
  return v_sid;
end;
$$;

-- ---- T-ROLE-01: client cannot write protected data ----
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select lives_ok($$ update public.profiles set full_name = 'Renamed Client A' where id = '00000000-0000-4000-8000-0000000000a1' $$,
  'T-ROLE-01: a client may update their own full_name');
select throws_ok($$ update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000000a1' $$,
  '42501', null, 'T-ROLE-01: a client cannot change profile status');
select throws_ok($$ insert into public.staff_roles (user_id, role) values ('00000000-0000-4000-8000-0000000000a1', 'admin') $$,
  '42501', null, 'T-ROLE-01: a client cannot grant themselves a staff role');
select throws_ok($$ insert into public.audit_events (action) values ('forged') $$,
  '42501', null, 'T-ROLE-01: a client cannot write audit events');
select throws_ok($$ insert into public.invitations (kind, email, full_name, project_id, token_hash, created_by) values ('client', 'x@example.test', 'x', '20000000-0000-4000-8000-0000000000a0', '\x00', '00000000-0000-4000-8000-0000000000a1') $$,
  '42501', null, 'T-ROLE-01: a client cannot write invitations');
select is(public.create_invitation('client', 'x@example.test', 'X', '20000000-0000-4000-8000-0000000000a0') ->> 'error', 'forbidden',
  'T-ROLE-01: a client cannot create invitations');
select is(public.revoke_membership((select id from public.project_memberships limit 1), 'x') ->> 'error', 'forbidden',
  'T-ROLE-01: a client cannot revoke memberships');
reset role;
select is((select full_name from public.profiles where id = '00000000-0000-4000-8000-0000000000a1'), 'Renamed Client A',
  'T-ROLE-01: own full_name update persisted');

-- ---- T-AUTH-04: staff at aal1 are denied by restrictive aal2 policies ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
select is((select count(*)::int from public.projects), 0, 'T-AUTH-04: an Admin at aal1 reads no projects');
select is((select count(*)::int from public.profiles where id <> '00000000-0000-4000-8000-000000000002'), 0,
  'T-AUTH-04: an Admin at aal1 reads no other profiles');
select throws_ok($$ insert into public.client_businesses (legal_name, display_name) values ('aal1 LLC', 'aal1') $$,
  '42501', null, 'T-AUTH-04: an Admin at aal1 cannot create a business');
select is(public.create_invitation('client', 'y@example.test', 'Y', '20000000-0000-4000-8000-0000000000a0') ->> 'error', 'forbidden',
  'T-AUTH-04: an Admin at aal1 cannot invite');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', interval '1 minute');
select is((select count(*)::int from public.projects), 2, 'T-AUTH-04: an Admin at aal2 reads all projects');
select lives_ok($$ insert into public.client_businesses (legal_name, display_name) values ('aal2 LLC', 'aal2') $$,
  'T-AUTH-04: an Admin at aal2 can create a business');

-- ---- T-ROLE-02: Admin cannot manage staff, even at aal2 with fresh MFA ----
select is(public.create_invitation('staff', 'new.admin@example.test', 'New Admin', null, 'admin') ->> 'error', 'forbidden',
  'T-ROLE-02: an Admin cannot invite staff');
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'owner', 'self-promote') ->> 'error', 'forbidden',
  'T-ROLE-02: an Admin cannot change staff roles (including self-promotion)');
select is(public.revoke_staff('00000000-0000-4000-8000-000000000001', 'x') ->> 'error', 'forbidden',
  'T-ROLE-02: an Admin cannot revoke staff');
select is(public.set_user_status('00000000-0000-4000-8000-000000000001', 'deactivated', 'x') ->> 'error', 'forbidden',
  'T-ROLE-02: an Admin cannot deactivate a staff user');
select is(public.set_user_status('00000000-0000-4000-8000-0000000000a1', 'deactivated', 'synthetic test') ->> 'ok', 'true',
  'T-ROLE-02: an Admin at aal2 can deactivate a client user');
reset role;
update public.profiles set status = 'active' where id = '00000000-0000-4000-8000-0000000000a1';

-- ---- T-ROLE-07 / T-AUTH-05: Owner staff changes need aal2 and MFA within 5 minutes ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal1');
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'admin', 'x') ->> 'error', 'forbidden',
  'T-ROLE-07: an Owner at aal1 cannot change staff roles');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '10 minutes');
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'admin', 'x') ->> 'error', 'forbidden',
  'T-AUTH-05: an Owner with stale MFA (10 min) is rejected by the database');
select is(public.create_invitation('staff', 'stale@example.test', 'Stale', null, 'admin') ->> 'error', 'forbidden',
  'T-AUTH-05: stale MFA cannot invite staff');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'admin', 'confirm role') ->> 'ok', 'true',
  'T-ROLE-07: an Owner at aal2 with fresh MFA can change staff roles (totp not first in amr)');

-- ---- T-ROLE-03: Fulfillment is never assignable, and attempts are audited ----
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'fulfillment', 'attempt') ->> 'error', 'role_not_assignable',
  'T-ROLE-03: assigning Fulfillment is rejected');
select is(public.create_invitation('staff', 'ful@example.test', 'Ful', null, 'fulfillment') ->> 'error', 'role_not_assignable',
  'T-ROLE-03: inviting as Fulfillment is rejected');
reset role;
select is((select count(*)::int from public.audit_events where action = 'staff_role.fulfillment_assignment_attempted'), 2,
  'T-ROLE-03: both Fulfillment attempts are audited');
select throws_ok($$ insert into public.staff_roles (user_id, role) values ('00000000-0000-4000-8000-0000000000a1', 'fulfillment') $$,
  '23514', null, 'T-ROLE-03: the database check constraint rejects Fulfillment even for the table owner');

-- ---- T-ROLE-08: the last active Owner cannot be removed, demoted, or deactivated ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is(public.revoke_staff('00000000-0000-4000-8000-000000000001', 'self') ->> 'error', 'last_owner',
  'T-ROLE-08: the last Owner cannot be revoked');
select is(public.set_staff_role('00000000-0000-4000-8000-000000000001', 'admin', 'self') ->> 'error', 'last_owner',
  'T-ROLE-08: the last Owner cannot be demoted');
select is(public.set_user_status('00000000-0000-4000-8000-000000000001', 'deactivated', 'self') ->> 'error', 'last_owner',
  'T-ROLE-08: the last Owner cannot be deactivated');
select is((select count(*)::int from public.audit_events where action = 'staff_role.last_owner_protected'), 3,
  'T-ROLE-08: each blocked last-Owner change is audited (spec 03 §11)');
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'owner', 'second owner') ->> 'ok', 'true',
  'T-ROLE-08: a second Owner can be appointed');
select is(public.revoke_staff('00000000-0000-4000-8000-000000000001', 'handover') ->> 'ok', 'true',
  'T-ROLE-08: with another active Owner, an Owner can be revoked');
reset role;

-- ---- T-AUTH-10: a signed-out session (row deleted) is denied before access-token expiry ----
do $$
declare
  v_sid uuid;
begin
  v_sid := pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', interval '1 minute');
  reset role;
  delete from auth.sessions where id = v_sid;  -- what signOut({scope:'global'}) does (spike S-06)
  set local role authenticated;
end;
$$;
select is(public.set_staff_role('00000000-0000-4000-8000-000000000002', 'owner', 'x') ->> 'error', 'forbidden',
  'T-AUTH-10: staff functions reject a JWT whose session no longer exists');
select is((public.auth_context() ->> 'session_active')::boolean, false,
  'T-AUTH-10: auth_context reports the session as inactive');
reset role;

select * from finish();
rollback;
