-- Append-only audit log (spec 03 §11; T-AUD-01, T-AUD-02, T-AUD-03).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(16);

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

create temp table vars (k text primary key, v text);
grant all on vars to authenticated, service_role;
create temp table mark as select coalesce(max(id), 0) as last_id from public.audit_events;
grant select on mark to authenticated, service_role;

-- ---- T-AUD-01: exactly one event per privileged action, attributed to the actor ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', interval '1 minute');
insert into public.client_businesses (legal_name, display_name) values ('Audit Test LLC', 'Audit Test');
reset role;
insert into vars select 'biz', id::text from public.client_businesses where legal_name = 'Audit Test LLC';
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and action = 'client_business.created' and target_id = (select v from vars where k = 'biz')), 1,
  'T-AUD-01: creating a business writes exactly one client_business.created event');
select is((select actor_user_id::text || '|' || actor_role || '|' || actor_aal from public.audit_events
  where id > (select last_id from mark) and action = 'client_business.created'),
  '00000000-0000-4000-8000-000000000002|admin|aal2', 'T-AUD-01: the event records actor, role, and AAL');

select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', interval '1 minute');
select is(public.revoke_membership((select id from public.project_memberships
  where user_id = '00000000-0000-4000-8000-0000000000b1' and status = 'active'), 'synthetic reason') ->> 'ok', 'true',
  'Admin revokes a client membership');
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action = 'membership.revoked'), 1,
  'T-AUD-01: revoking a membership writes exactly one membership.revoked event');
select is((select reason || '|' || project_id::text from public.audit_events where id > (select last_id from mark) and action = 'membership.revoked'),
  'synthetic reason|20000000-0000-4000-8000-0000000000b0', 'T-AUD-01: the event carries the reason and project scope');

select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select is(public.set_user_status('00000000-0000-4000-8000-0000000000a1', 'deactivated', 'synthetic deactivation') ->> 'ok', 'true',
  'Owner deactivates a client');
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action like 'user.%'), 1,
  'T-AUD-01: deactivation writes exactly one user.* event');
select is((select reason from public.audit_events where id > (select last_id from mark) and action = 'user.deactivated'),
  'synthetic deactivation', 'T-AUD-01: the deactivation reason is recorded on that single event');

-- ---- T-AUD-03: invitation tokens and hashes never reach the audit log ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
insert into vars select 'inv', public.create_invitation('client', 'audit.secret@example.test', 'Audit Secret', '20000000-0000-4000-8000-0000000000a0')::text;
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and (summary::text like '%' || ((select v from vars where k = 'inv')::jsonb ->> 'token') || '%'
       or coalesce(reason, '') like '%' || ((select v from vars where k = 'inv')::jsonb ->> 'token') || '%')), 0,
  'T-AUD-03: the plaintext invitation token is not in any audit event');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and summary::text like '%token_hash%' and summary::text like '%\\x%'), 0,
  'T-AUD-03: token hashes are not in any audit event');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark) and action = 'invitation.created'), 1,
  'T-AUD-01: creating an invitation writes exactly one invitation.created event');

-- ---- T-AUD-02: append-only for every role ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', interval '1 minute');
select throws_ok($$ update public.audit_events set action = 'tampered' $$, '42501', null,
  'T-AUD-02: the Owner cannot update audit events');
select throws_ok($$ delete from public.audit_events $$, '42501', null,
  'T-AUD-02: the Owner cannot delete audit events');
reset role;
set local role service_role;
select throws_ok($$ update public.audit_events set action = 'tampered' $$, '42501', null,
  'T-AUD-02: service_role cannot update audit events');
reset role;
select throws_ok($$ delete from public.audit_events where id = (select max(id) from public.audit_events) $$, '42501',
  'audit_events is append-only', 'T-AUD-02: even the table owner is blocked by the append-only trigger');
select throws_ok($$ truncate public.audit_events $$, '42501', 'audit_events is append-only',
  'T-AUD-02: truncate is blocked');

select * from finish();
rollback;
