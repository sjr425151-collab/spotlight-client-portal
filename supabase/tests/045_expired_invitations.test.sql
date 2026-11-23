-- OI-54 condition (Owner, 2026-11-23): with no cleanup job, an expired invitation is still
-- rejected at every authentication and acceptance boundary. Rows stay status = 'pending'.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(13);

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

-- Owner invites a new email and existing client B; both invitations are then expired by time
-- only. No job runs, so their status stays 'pending'.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
insert into vars select 'new', public.create_invitation('client', 'expired.new@example.test', 'Expired New', '20000000-0000-4000-8000-0000000000a0')::text;
insert into vars select 'b', public.create_invitation('client', 'client.b@example.test', 'Client B', '20000000-0000-4000-8000-0000000000a0')::text;
reset role;
-- Exactly at the expiry instant counts as expired (expires_at <= now()).
update public.invitations set expires_at = now()
 where id = ((select v from vars where k = 'new')::jsonb ->> 'invitation_id')::uuid;
update public.invitations set expires_at = now() - interval '1 day'
 where id = ((select v from vars where k = 'b')::jsonb ->> 'invitation_id')::uuid;

select is((select count(*)::int from public.invitations
  where id in (((select v from vars where k = 'new')::jsonb ->> 'invitation_id')::uuid,
               ((select v from vars where k = 'b')::jsonb ->> 'invitation_id')::uuid)
    and status = 'pending'), 2, 'Precondition: expired rows are not marked by any cleanup (status still pending)');

-- 1. Auth user provisioning (before-user-created hook)
select is(private.hook_before_user_created('{"user": {"email": "expired.new@example.test"}}'::jsonb) -> 'error' ->> 'http_code', '403',
  'Hook: an email whose only invitation expired cannot be provisioned as an Auth user');

-- 2. Invitation link pre-check (page view, code verification, "send me a new code")
set local role service_role;
select is(public.check_invitation_link(((select v from vars where k = 'new')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'new')::jsonb ->> 'token') ->> 'error', 'invalid',
  'Link check: the correct token for an expired invitation is rejected');
reset role;
select is((select summary ->> 'reason' from public.audit_events where occurred_at >= now() and action = 'invitation.link_check_failed'
  and target_id = (select v from vars where k = 'new')::jsonb ->> 'invitation_id' order by id desc limit 1), 'expired',
  'Link check: the rejection is audited with reason expired');

-- 3. Acceptance with the link token by the matching, verified user
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('00000000-0000-0000-0000-000000000000', '30000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
  'expired.new@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
select pg_temp.act_as('30000000-0000-4000-8000-000000000001');
select is(public.accept_invitation(((select v from vars where k = 'new')::jsonb ->> 'invitation_id')::uuid,
  (select v from vars where k = 'new')::jsonb ->> 'token') ->> 'error', 'invalid',
  'Link acceptance: an expired invitation is rejected for the right user with the right token');
select is((select count(*)::int from public.projects), 0, 'Link acceptance: no project access was granted');
reset role;
select is((select count(*)::int from public.profiles where id = '30000000-0000-4000-8000-000000000001'), 0,
  'Link acceptance: no profile was created');

-- 4. In-portal (tokenless) acceptance and invitee visibility
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.invitations), 0, 'RLS: an invitee cannot see an expired invitation');
select is(public.accept_invitation(((select v from vars where k = 'b')::jsonb ->> 'invitation_id')::uuid, null) ->> 'error', 'invalid',
  'Portal acceptance: an expired invitation is rejected without a token');
select is((select count(*)::int from public.projects where id = '20000000-0000-4000-8000-0000000000a0'), 0,
  'Portal acceptance: client B did not gain Project A');
reset role;
select is((select count(*)::int from public.audit_events where occurred_at >= now() and action = 'invitation.accept_failed'
  and summary ->> 'reason' = 'expired'), 2, 'Both rejected acceptances are audited with reason expired');

-- 5. Expired invitations do not count toward the per-project pending limit
select is((select count(*)::int from public.invitations
  where project_id = '20000000-0000-4000-8000-0000000000a0' and status = 'pending' and expires_at > now()
    and id in (((select v from vars where k = 'new')::jsonb ->> 'invitation_id')::uuid,
               ((select v from vars where k = 'b')::jsonb ->> 'invitation_id')::uuid)), 0,
  'Expired rows are excluded by the same time-based predicate used for the pending limit');
select is((select status::text from public.invitations
  where id = ((select v from vars where k = 'b')::jsonb ->> 'invitation_id')::uuid), 'pending',
  'Rejection never depends on, or changes, the cleanup status');

select * from finish();
rollback;
