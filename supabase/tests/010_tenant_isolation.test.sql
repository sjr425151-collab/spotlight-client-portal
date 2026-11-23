-- Cross-tenant isolation with real RLS (spec 03 §8-§9; T-TEN-01, T-TEN-02, T-TEN-03, T-AUTH-03, T-AUTH-09).
-- Seed: client A (…a1) is a member of Project A only; client B (…b1) of Project B only.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(26);

-- Impersonation helper: real session row + JWT claims, then SET LOCAL ROLE.
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

-- Storage fixtures (synthetic paths only).
insert into storage.objects (bucket_id, name) values
  ('project-assets', '20000000-0000-4000-8000-0000000000a0/brand/logo.png'),
  ('project-assets', '20000000-0000-4000-8000-0000000000b0/brand/logo.png'),
  ('project-assets', 'not-a-project/readme.txt');

select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');

-- T-TEN-01: reads
select results_eq($$ select id from public.projects $$,
  $$ values ('20000000-0000-4000-8000-0000000000a0'::uuid) $$,
  'T-TEN-01: client A sees only Project A in projects');
select results_eq($$ select id from public.client_businesses $$,
  $$ values ('10000000-0000-4000-8000-0000000000a0'::uuid) $$,
  'T-TEN-01: client A sees only Business A in client_businesses');
-- Assertions test the isolation property, not seed counts, so they hold on a used database.
select is((select count(*)::int from public.project_memberships
  where project_id = '20000000-0000-4000-8000-0000000000b0' and user_id <> '00000000-0000-4000-8000-0000000000a1'), 0,
  'T-TEN-01: client A sees no other user''s Project B memberships');
select is((select count(*)::int from public.project_memberships where user_id <> '00000000-0000-4000-8000-0000000000a1'), 0,
  'T-TEN-01: client A sees only their own membership rows');
select is((select count(*)::int from public.profiles where id = '00000000-0000-4000-8000-0000000000b1'), 0,
  'T-TEN-01: client A cannot read client B profile');
select is((select count(*)::int from public.staff_roles), 0, 'T-TEN-01: client A sees no staff roles');
select is((select count(*)::int from public.invitations), 0, 'T-TEN-01: client A sees no invitations addressed to others');
select is((select count(*)::int from public.audit_events), 0, 'T-TEN-01: client A sees no audit events');

-- T-TEN-03: storage
select is((select count(*)::int from storage.objects where bucket_id = 'project-assets'
  and name not like '20000000-0000-4000-8000-0000000000a0/%'), 0,
  'T-TEN-03: client A lists only Project A objects (malformed paths denied, not errors)');
select ok(exists(select 1 from storage.objects where name = '20000000-0000-4000-8000-0000000000a0/brand/logo.png'),
  'T-TEN-03: client A can read their own Project A object');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('project-assets', '20000000-0000-4000-8000-0000000000b0/x.png') $$,
  '42501', null, 'T-TEN-03: client A cannot write objects (no upload policy in Phase 2)');

-- T-TEN-02: writes
select throws_ok($$ insert into public.projects (client_business_id, name) values ('10000000-0000-4000-8000-0000000000b0', 'x') $$,
  '42501', null, 'T-TEN-02: client A cannot insert a project');
select throws_ok($$ insert into public.client_businesses (legal_name, display_name) values ('x', 'x') $$,
  '42501', null, 'T-TEN-02: client A cannot insert a business');
select lives_ok($$ update public.projects set name = 'hijacked' where id = '20000000-0000-4000-8000-0000000000b0' $$,
  'T-TEN-02: update of Project B is filtered by RLS (no error, no rows)');
select lives_ok($$ update public.client_businesses set display_name = 'hijacked' where id = '10000000-0000-4000-8000-0000000000b0' $$,
  'T-TEN-02: update of Business B is filtered by RLS (no error, no rows)');
select throws_ok($$ delete from public.projects where id = '20000000-0000-4000-8000-0000000000b0' $$,
  '42501', null, 'T-TEN-02: client A cannot delete projects');
select throws_ok($$ insert into public.project_memberships (project_id, user_id) values ('20000000-0000-4000-8000-0000000000b0', '00000000-0000-4000-8000-0000000000a1') $$,
  '42501', null, 'T-TEN-02: client A cannot grant themselves a Project B membership');
select throws_ok($$ update public.project_memberships set status = 'active' $$,
  '42501', null, 'T-TEN-02: client A cannot modify memberships');

reset role;
select is((select name from public.projects where id = '20000000-0000-4000-8000-0000000000b0'), 'Project B website',
  'T-TEN-02: Project B is unchanged');
select is((select display_name from public.client_businesses where id = '10000000-0000-4000-8000-0000000000b0'), 'Business B',
  'T-TEN-02: Business B is unchanged');

-- Client B mirror check
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select results_eq($$ select id from public.projects $$,
  $$ values ('20000000-0000-4000-8000-0000000000b0'::uuid) $$, 'T-TEN-01: client B sees only Project B');
select is((select count(*)::int from storage.objects where bucket_id = 'project-assets'
  and name not like '20000000-0000-4000-8000-0000000000b0/%'), 0, 'T-TEN-03: client B lists only Project B objects');
reset role;

-- T-AUTH-03: membership revocation takes effect on the next query with the same, unexpired JWT.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select count(*)::int from public.projects), 1, 'T-AUTH-03: before revocation client A sees Project A');
reset role;
update public.project_memberships set status = 'revoked', revoked_at = now()
 where user_id = '00000000-0000-4000-8000-0000000000a1';
select set_config('role', 'authenticated', true);
select is((select count(*)::int from public.projects), 0, 'T-AUTH-03: after revocation the same claims see no project');
reset role;

-- T-AUTH-09: deactivation is effective immediately.
update public.project_memberships set status = 'active', revoked_at = null
 where user_id = '00000000-0000-4000-8000-0000000000b1';
update public.profiles set status = 'deactivated' where id = '00000000-0000-4000-8000-0000000000b1';
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is((select count(*)::int from public.projects), 0, 'T-AUTH-09: a deactivated client sees no projects');
select is((select count(*)::int from storage.objects where bucket_id = 'project-assets'), 0,
  'T-AUTH-09: a deactivated client sees no project objects');
reset role;

select * from finish();
rollback;
