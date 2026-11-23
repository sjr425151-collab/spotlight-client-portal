-- Invitation lifecycle (spec 03 §6.1; T-AUTH-02, T-AUTH-06, T-AUTH-07, T-AUTH-08, T-AUTH-12 hook).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(30);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_totp_age interval default null)
returns void language plpgsql as $$
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
  if p_totp_age is not null then
    v_amr := v_amr || jsonb_build_array(jsonb_build_object('method', 'totp',
               'timestamp', extract(epoch from now() - p_totp_age)::bigint));
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', p_uid, 'role', 'authenticated', 'aal', p_aal, 'amr', v_amr, 'session_id', v_sid)::text, true);
  set local role authenticated;
end;
$$;

-- Synthetic auth users for invitees (confirmed unless stated).
create function pg_temp.new_user(p_email text, p_confirmed boolean default true) returns uuid
language plpgsql as $$
declare v_id uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email, '',
    case when p_confirmed then now() end, '{"provider":"email","providers":["email"]}', '{}', now(), now());
  return v_id;
end;
$$;

create temp table vars (k text primary key, v text);
grant all on vars to authenticated, service_role;

-- Owner (aal2, fresh MFA) creates client and staff invitations.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
insert into vars select 'inv1', public.create_invitation('client', '  New.Client@Example.test ', 'New Client', '20000000-0000-4000-8000-0000000000a0')::text;
insert into vars select 'inv_expired', public.create_invitation('client', 'late@example.test', 'Late Client', '20000000-0000-4000-8000-0000000000a0')::text;
insert into vars select 'inv_revoked', public.create_invitation('client', 'gone@example.test', 'Gone Client', '20000000-0000-4000-8000-0000000000a0')::text;
insert into vars select 'inv_staff', public.create_invitation('staff', 'new.admin@example.test', 'New Admin', null, 'admin')::text;
select ok((select (v::jsonb ->> 'ok')::boolean from vars where k = 'inv1'), 'Owner can create a client invitation');
select ok((select (v::jsonb ->> 'ok')::boolean from vars where k = 'inv_staff'), 'Owner with fresh MFA can create a staff invitation');
select is(public.revoke_invitation(((select v from vars where k = 'inv_revoked')::jsonb ->> 'invitation_id')::uuid) ->> 'ok', 'true',
  'Owner can revoke a pending invitation');
reset role;

select is((select email::text from public.invitations where id = ((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid),
  'new.client@example.test', 'Invitation email is normalized (trimmed, lower-cased)');
select is((select length((select v from vars where k = 'inv1')::jsonb ->> 'token')), 43,
  'Invitation token is 256 bits (43 base64url characters)');
select is((select token_hash from public.invitations where id = ((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid),
  extensions.digest((select v from vars where k = 'inv1')::jsonb ->> 'token', 'sha256'),
  'Only the SHA-256 hash of the token is stored');

update public.invitations set expires_at = now() - interval '1 second'
 where id = ((select v from vars where k = 'inv_expired')::jsonb ->> 'invitation_id')::uuid;

insert into vars values ('u_new', pg_temp.new_user('new.client@example.test')::text);
insert into vars values ('u_late', pg_temp.new_user('late@example.test')::text);
insert into vars values ('u_gone', pg_temp.new_user('gone@example.test')::text);
insert into vars values ('u_unconfirmed', pg_temp.new_user('new.admin@example.test', false)::text);

-- ---- Pre-sign-in link check (service role only) ----
set local role service_role;
select is(public.check_invitation_link(((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv1')::jsonb ->> 'token') ->> 'email', 'new.client@example.test',
  'A valid invitation link resolves to its email for the server');
select is(public.check_invitation_link(((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid, 'wrong') ->> 'error', 'invalid',
  'A wrong token in the link is rejected');
reset role;
select is((select failed_attempts from public.invitations where id = ((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid), 1,
  'T-AUTH-08: the wrong link token incremented failed_attempts');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select throws_ok($$ select public.check_invitation_link(gen_random_uuid(), 'x') $$, '42501', null,
  'check_invitation_link is not callable by end users');
reset role;

-- ---- T-AUTH-07: another signed-in user cannot accept it ----
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.accept_invitation(((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv1')::jsonb ->> 'token') ->> 'error', 'invalid',
  'T-AUTH-07: a user whose verified email differs cannot accept');
reset role;
select is((select count(*)::int from public.project_memberships where user_id = '00000000-0000-4000-8000-0000000000b1'
  and project_id = '20000000-0000-4000-8000-0000000000a0'), 0, 'T-AUTH-07: no membership was created');

-- ---- T-AUTH-08: tampered token ----
select pg_temp.act_as(((select v from vars where k = 'u_new'))::uuid);
select is(public.accept_invitation(((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid, 'tampered-token') ->> 'error', 'invalid',
  'T-AUTH-08: a tampered token is rejected');
-- ---- Valid acceptance ----
select is(public.accept_invitation(((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv1')::jsonb ->> 'token') ->> 'ok', 'true',
  'The invited user (verified email matches) accepts with the correct token');
select results_eq($$ select id from public.projects $$, $$ values ('20000000-0000-4000-8000-0000000000a0'::uuid) $$,
  'The new client immediately sees only their invited project');
-- ---- T-AUTH-06: replay ----
select is(public.accept_invitation(((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv1')::jsonb ->> 'token') ->> 'error', 'invalid',
  'T-AUTH-06: replaying an accepted token fails');
reset role;
select is((select count(*)::int from public.project_memberships where user_id = ((select v from vars where k = 'u_new'))::uuid), 1,
  'T-AUTH-06: exactly one membership exists after replay');
select is((select status::text from public.invitations where id = ((select v from vars where k = 'inv1')::jsonb ->> 'invitation_id')::uuid), 'accepted',
  'Invitation is marked accepted');
select is((select full_name from public.profiles where id = ((select v from vars where k = 'u_new'))::uuid), 'New Client',
  'A profile is created from the invitation');

-- ---- T-AUTH-02: expired and revoked invitations ----
select pg_temp.act_as(((select v from vars where k = 'u_late'))::uuid);
select is(public.accept_invitation(((select v from vars where k = 'inv_expired')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv_expired')::jsonb ->> 'token') ->> 'error', 'invalid',
  'T-AUTH-02: an expired invitation cannot be accepted');
reset role;
select pg_temp.act_as(((select v from vars where k = 'u_gone'))::uuid);
select is(public.accept_invitation(((select v from vars where k = 'inv_revoked')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv_revoked')::jsonb ->> 'token') ->> 'error', 'invalid',
  'T-AUTH-02: a revoked invitation cannot be accepted');
reset role;
select is((select count(*)::int from public.project_memberships
  where user_id in (((select v from vars where k = 'u_late'))::uuid, ((select v from vars where k = 'u_gone'))::uuid)), 0,
  'T-AUTH-02: no membership for expired or revoked invitations');
select is((select count(*)::int from public.audit_events where occurred_at >= now() and action = 'invitation.accept_failed'
  and summary ->> 'reason' in ('expired', 'revoked', 'email_mismatch', 'token_mismatch', 'already_accepted')), 5,
  'T-AUTH-02/06/07/08: every failed acceptance is audited with its reason');

-- ---- Unconfirmed email cannot accept (staff invitation) ----
select pg_temp.act_as(((select v from vars where k = 'u_unconfirmed'))::uuid);
select is(public.accept_invitation(((select v from vars where k = 'inv_staff')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv_staff')::jsonb ->> 'token') ->> 'error', 'invalid',
  'An unconfirmed email cannot accept an invitation');
reset role;
update auth.users set email_confirmed_at = now() where id = ((select v from vars where k = 'u_unconfirmed'))::uuid;
select pg_temp.act_as(((select v from vars where k = 'u_unconfirmed'))::uuid);
select is(public.accept_invitation(((select v from vars where k = 'inv_staff')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv_staff')::jsonb ->> 'token') ->> 'ok', 'true',
  'After email confirmation, the staff invitee accepts');
reset role;
select is((select role::text from public.staff_roles where user_id = ((select v from vars where k = 'u_unconfirmed'))::uuid), 'admin',
  'The staff invitation grants exactly the intended Admin role');

-- ---- Attempt lockout ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
insert into vars select 'inv_lock', public.create_invitation('client', 'locked@example.test', 'Locked', '20000000-0000-4000-8000-0000000000b0')::text;
reset role;
update public.invitations set failed_attempts = 10 where id = ((select v from vars where k = 'inv_lock')::jsonb ->> 'invitation_id')::uuid;
insert into vars values ('u_lock', pg_temp.new_user('locked@example.test')::text);
select pg_temp.act_as(((select v from vars where k = 'u_lock'))::uuid);
select is(public.accept_invitation(((select v from vars where k = 'inv_lock')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'inv_lock')::jsonb ->> 'token') ->> 'error', 'invalid',
  'T-AUTH-08: after 10 failed attempts even the correct token is refused');
reset role;

-- ---- T-AUTH-12: before-user-created hook ----
select is(private.hook_before_user_created('{"user":{"email":"LOCKED@example.test"}}'::jsonb), '{}'::jsonb,
  'T-AUTH-12: the hook allows an email with a pending invitation (case-insensitive)');
select is(private.hook_before_user_created('{"user":{"email":"stranger@example.test"}}'::jsonb) -> 'error' ->> 'http_code', '403',
  'T-AUTH-12: the hook rejects an email without a pending invitation');
select is(private.hook_before_user_created('{"user":{"email":"late@example.test"}}'::jsonb) -> 'error' ->> 'http_code', '403',
  'T-AUTH-12: the hook rejects an email whose invitation has expired');

select * from finish();
rollback;
