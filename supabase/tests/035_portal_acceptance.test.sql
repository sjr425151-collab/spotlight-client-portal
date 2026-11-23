-- In-portal acceptance for signed-in users (spec 03 §6.1 step 2; 03A S-06). Tokenless, email-bound.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(8);

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

-- Owner invites existing client B to Project A, and someone else to Project A.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
insert into vars select 'inv_b', public.create_invitation('client', 'client.b@example.test', 'Client B', '20000000-0000-4000-8000-0000000000a0')::text;
insert into vars select 'inv_other', public.create_invitation('client', 'other@example.test', 'Other', '20000000-0000-4000-8000-0000000000a0')::text;
reset role;

-- Client B sees only their own pending invitation.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.invitations), 1, 'A signed-in client sees only invitations addressed to their verified email');
select is(public.accept_invitation(((select v from vars where k = 'inv_other')::jsonb ->> 'invitation_id')::uuid, null) ->> 'error', 'invalid',
  'Tokenless acceptance of an invitation for another email is rejected');
reset role;
select is((select failed_attempts from public.invitations where id = ((select v from vars where k = 'inv_other')::jsonb ->> 'invitation_id')::uuid), 0,
  'A tokenless email mismatch is not counted as a token guess (no lockout of the real invitee)');
select is((select count(*)::int from public.audit_events where occurred_at >= now() and action = 'invitation.accept_failed' and summary ->> 'via' = 'portal'), 1,
  'The rejected tokenless attempt is audited');

select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.accept_invitation(((select v from vars where k = 'inv_b')::jsonb ->> 'invitation_id')::uuid, null) ->> 'ok', 'true',
  'A signed-in client accepts their own pending invitation without the link token');
select is((select count(*)::int from public.projects), 2, 'Client B now sees both Project A and Project B');
select is(public.accept_invitation(((select v from vars where k = 'inv_b')::jsonb ->> 'invitation_id')::uuid, null) ->> 'error', 'invalid',
  'The accepted invitation cannot be accepted again');
reset role;
select is((select count(*)::int from public.project_memberships
  where user_id = '00000000-0000-4000-8000-0000000000b1' and status = 'active'), 2,
  'Exactly one new active membership was created');

select * from finish();
rollback;
