-- WP-H (AUTH-006): OI-86 and OI-87 (04 §4, 03 §4; R1-HANDOFFS §1 items 1 and 2).
-- OI-86's concurrency proof is in tests/integration/wph-hardening.test.ts and the T-SALES-32
-- true race; this file checks the deployed definition. OI-87: order_summaries.change_reason is
-- not readable by any API user; every other column and every policy is unchanged.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(22);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false, p_otp_fresh boolean default false)
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
    'session_id', v_sid, 'amr',
      case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp', 'timestamp', extract(epoch from now())::bigint))
           when p_otp_fresh then jsonb_build_array(jsonb_build_object('method', 'otp', 'timestamp', extract(epoch from now())::bigint))
           else jsonb_build_array(jsonb_build_object('method', 'otp', 'timestamp', extract(epoch from now())::bigint - 3600)) end)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
create function pg_temp.svc(p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_service();
  execute p_sql into v;
  reset role;
  return v;
end;
$$;
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- OI-86: the deployed issue_order_summary locks the project row FOR NO KEY UPDATE
-- ---------------------------------------------------------------------------
select ok(pg_get_functiondef('private.issue_order_summary(uuid, text, jsonb, text, text)'::regprocedure)
            like '%from public.projects where id = p_project_id and archived_at is null for no key update;%',
  'OI-86: the project row is locked FOR NO KEY UPDATE');
select ok(pg_get_functiondef('private.issue_order_summary(uuid, text, jsonb, text, text)'::regprocedure)
            not like '%from public.projects where id = p_project_id and archived_at is null for update;%',
  'OI-86: the former FOR UPDATE project lock is gone');
select ok(pg_get_functiondef('private.issue_order_summary(uuid, text, jsonb, text, text)'::regprocedure)
            like '%where project_id = p_project_id and status = ''presented'' for update;%',
  'OI-86: the order-summary row lock that decides the acceptance race is unchanged');
select ok(has_function_privilege('authenticated', 'public.issue_order_summary(uuid, text, jsonb, text, text)', 'execute')
  and not has_function_privilege('anon', 'private.issue_order_summary(uuid, text, jsonb, text, text)', 'execute'),
  'OI-86: grants are unchanged (CREATE OR REPLACE)');

-- ---------------------------------------------------------------------------
-- OI-87: column privileges
-- ---------------------------------------------------------------------------
select ok(not has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'select'),
  'OI-87: authenticated cannot select order_summaries.change_reason');
select ok(not has_table_privilege('authenticated', 'public.order_summaries', 'select'),
  'OI-87: no table-level select remains for authenticated');
select is((select count(*)::int from information_schema.columns c where c.table_schema = 'public'
             and c.table_name = 'order_summaries' and c.column_name <> 'change_reason'
             and not has_column_privilege('authenticated', 'public.order_summaries', c.column_name, 'select')), 0,
  'OI-87: every other column is still readable by authenticated');
select ok(not has_column_privilege('anon', 'public.order_summaries', 'change_reason', 'select')
  and not has_table_privilege('anon', 'public.order_summaries', 'select'), 'OI-87: anon reads nothing');
select ok(has_table_privilege('service_role', 'public.order_summaries', 'select'),
  'OI-87: the server keeps its existing read (service_role unchanged)');
select ok(not has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'insert')
  and not has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'update'),
  'OI-87: no write privilege is granted');
select is((select array_agg(polname::text order by polname) from pg_policy where polrelid = 'public.order_summaries'::regclass),
  array['order_summaries_active_user', 'order_summaries_select', 'order_summaries_staff_aal2'],
  'OI-87: the order_summaries policies are unchanged');

-- A summary issued with a change reason (Owner), on Project A, whose client is client A.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'os1', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential',
  '["Website"]'::jsonb, null, 'Internal note: discount discussed by phone') ->> 'order_summary_id';
reset role;
select ok((select v from ids where k = 'os1') is not null, 'the Owner issues a summary with a change reason');
select is((select change_reason from public.order_summaries where id = (select v::uuid from ids where k = 'os1')),
  'Internal note: discount discussed by phone', 'the reason is stored on the row (migration owner view)');

-- The client: the same rows and every contractual column, never the reason.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select results_eq($$ select id::text, package_key, package_total_cents, deposit_cents, balance_cents, scope_items::text,
    business_legal_name, status::text from public.order_summaries where id = (select v::uuid from ids where k = 'os1') $$,
  $$ select v, 'essential', 80000, 16000, 64000, '["Website"]', 'Synthetic Business A LLC', 'presented'
       from ids where k = 'os1' $$,
  'OI-87: the client reads its summary and every contractual column');
select throws_ok($$ select change_reason from public.order_summaries $$, '42501', null,
  'OI-87: the client cannot read change_reason');
select throws_ok($$ select * from public.order_summaries $$, '42501', null,
  'OI-87: select * is refused, so no query can return the reason by accident');
select is((select count(*)::int from public.agreement_versions v
           where exists (select 1 from public.order_summaries os where os.agreement_version_id = v.id
                           and os.id = (select v::uuid from ids where k = 'os1'))), 1,
  'OI-87: the agreement_versions policy built on order_summaries still admits the client');
select is((select count(*)::int from public.audit_events where reason is not null), 0,
  'the client reads no audit reason either');
reset role;

-- Staff: the same column restriction; the reason is available through the staff audit trail.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select throws_ok($$ select change_reason from public.order_summaries $$, '42501', null,
  'OI-87: an Admin cannot read change_reason from the table either');
select is((select reason from public.audit_events where action = 'order_summary.issued'
           and target_id = (select v from ids where k = 'os1')),
  'Internal note: discount discussed by phone', 'OI-87: an Admin reads the reason in the staff audit trail');
select ok((select count(*) = 1 from public.order_summaries where id = (select v::uuid from ids where k = 'os1')),
  'OI-87: an Admin still reads the row (OI-83 agreed pricing)');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is((select reason from public.audit_events where action = 'order_summary.issued'
           and target_id = (select v from ids where k = 'os1')),
  'Internal note: discount discussed by phone', 'OI-87: the Owner reads the reason in the staff audit trail');
reset role;

select * from finish();
rollback;
