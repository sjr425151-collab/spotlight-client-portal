-- Live session limits, live MFA factors, and session termination (spec 03 §6.2, §7;
-- T-AUTH-09, T-AUTH-10). Interim limits pending OI-50: staff 12 h inactivity and a 7-day
-- time-box; clients 7 days inactivity.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(12);

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

-- Ages the caller's current session (as postgres, then back to the caller's role).
create function pg_temp.age_session(p_created interval, p_activity interval) returns void
language plpgsql as $$
declare v_sid uuid := (current_setting('request.jwt.claims')::jsonb ->> 'session_id')::uuid;
begin
  reset role;
  update auth.sessions
     set created_at = now() - p_created, updated_at = now() - p_activity,
         refreshed_at = (now() - p_activity) at time zone 'UTC'
   where id = v_sid;
  set local role authenticated;
end;
$$;
grant execute on function pg_temp.age_session(interval, interval) to authenticated;

-- Staff (Admin) sessions
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', interval '1 minute');
select ok(private.session_is_active(), 'A fresh staff session is active');
select pg_temp.age_session(interval '6 days', interval '11 hours');
select ok(private.session_is_active(), 'Staff: 11 hours idle within the 7-day time-box is active');
select pg_temp.age_session(interval '6 days', interval '13 hours');
select ok(not private.session_is_active(), 'Staff: more than 12 hours idle ends the session');
select pg_temp.age_session(interval '8 days', interval '1 minute');
select ok(not private.session_is_active(), 'Staff: the 7-day time-box ends the session even when active');
select is((select count(*)::int from public.projects), 0, 'An expired staff session reads no projects (restrictive policy)');
reset role;

-- Client sessions
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select pg_temp.age_session(interval '30 days', interval '6 days');
select ok(private.session_is_active(), 'Client: 6 days idle is still active (no time-box)');
select pg_temp.age_session(interval '30 days', interval '8 days');
select ok(not private.session_is_active(), 'Client: more than 7 days idle ends the session');
reset role;

-- Live MFA factor check (spec 03 §7 "Factor removal")
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', interval '1 minute');
select ok(private.is_aal2(), 'aal2 with a verified factor counts as aal2');
reset role;
delete from auth.mfa_factors where user_id = '00000000-0000-4000-8000-000000000002';
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal1');
reset role;
set local role authenticated;
select set_config('request.jwt.claims', jsonb_set(current_setting('request.jwt.claims')::jsonb, '{aal}', '"aal2"')::text, true);
select ok(not private.is_aal2(), 'An aal2 token whose factor was reset no longer counts as aal2');
select is((select count(*)::int from public.projects), 0, 'Staff with a reset factor read nothing until they re-enroll');
reset role;

-- Deactivation terminates sessions (spec 03 §6.2)
insert into auth.sessions (id, user_id, created_at, updated_at, aal)
values (gen_random_uuid(), '00000000-0000-4000-8000-0000000000b1', now(), now(), 'aal1');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is(public.set_user_status('00000000-0000-4000-8000-0000000000b1', 'deactivated', 'test') ->> 'ok', 'true',
  'Staff can deactivate a client user');
reset role;
select is((select count(*)::int from auth.sessions where user_id = '00000000-0000-4000-8000-0000000000b1'), 0,
  'Deactivation deleted every session of the user (refresh tokens die with them)');

select * from finish();
rollback;
