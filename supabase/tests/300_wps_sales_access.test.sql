-- WP-S: Sales Representative role, access boundaries, and the enumerated regressions
-- (03 §3, §4, §4.1, §13; AUTH-005). T-SALES-01, T-SALES-02, T-SALES-03, T-SALES-09,
-- T-SALES-11, T-SALES-15, T-SALES-16, T-SALES-20, T-SALES-22, T-SALES-23, T-SALES-25.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(113);

-- Sessions: aal, fresh TOTP, and session age (12-hour staff rule) are explicit.
create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false,
  p_age interval default interval '0')
returns uuid language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal)
  values (v_sid, p_uid, now() - p_age, now() - p_age, p_aal::auth.aal_level);
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
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
create function pg_temp.new_user(p_id uuid, p_email text, p_role public.staff_role default null) returns void
language plpgsql as $$
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, email_change_token_current, reauthentication_token, phone_change,
    phone_change_token)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email, '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '');
  insert into public.profiles (id, email, full_name) values (p_id, p_email, 'Synthetic ' || p_email);
  if p_role is not null then
    insert into public.staff_roles (user_id, role) values (p_id, p_role);
  end if;
end;
$$;

-- Row counts of every application table, read as the migration owner (side-effect check).
create function pg_temp.table_counts() returns jsonb language plpgsql as $$
declare
  r record;
  v jsonb := '{}'::jsonb;
  n bigint;
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind in ('r', 'p') and c.relname <> 'audit_events' order by 1 loop
    execute format('select count(*) from public.%I', r.relname) into n;
    v := v || jsonb_build_object(r.relname, n);
  end loop;
  return v;
end;
$$;

-- Calls one exposed RPC with type-derived arguments (every uuid is p_uuid) and reports whether
-- it refused: raised, returned nothing, or returned only null / false / {"ok": false} values.
create function pg_temp.rpc_refused(p_oid oid, p_uuid uuid) returns boolean language plpgsql as $$
declare
  v_args text;
  v_result jsonb;
begin
  select coalesce(string_agg(case
      when t = 'uuid'::regtype then quote_literal(p_uuid) || '::uuid'
      when t = 'uuid[]'::regtype then 'array[' || quote_literal(p_uuid) || ']::uuid[]'
      when t in ('text'::regtype, 'extensions.citext'::regtype) then '''x'''
      when t = 'text[]'::regtype then '''{}''::text[]'
      when t = 'jsonb'::regtype then '''{}''::jsonb'
      when t = 'boolean'::regtype then 'true'
      when t in ('smallint'::regtype, 'integer'::regtype, 'bigint'::regtype, 'numeric'::regtype) then '1'
      when t = 'date'::regtype then 'current_date'
      when t = 'timestamptz'::regtype then 'now()'
      when t = 'interval'::regtype then '''1 hour''::interval'
      when exists (select 1 from pg_enum e where e.enumtypid = t)
        then quote_literal((select e.enumlabel from pg_enum e where e.enumtypid = t order by e.enumsortorder limit 1))
             || '::' || format_type(t, null)
      else 'null::' || format_type(t, null) end, ', ' order by ord), '')
    into v_args
  from pg_proc p, unnest(p.proargtypes::oid[]) with ordinality a(t, ord) where p.oid = p_oid;
  execute format('select coalesce(jsonb_agg(to_jsonb(r)), ''[]''::jsonb) from %s(%s) r',
                 p_oid::regproc, coalesce(v_args, '')) into v_result;
  -- A scalar result is the element itself; a table result is an object of columns.
  return not exists (
    select 1 from jsonb_array_elements(v_result) e
    where not (e = 'null'::jsonb or e = 'false'::jsonb or e = '[]'::jsonb or e = '{}'::jsonb
               or (jsonb_typeof(e) = 'object' and e ->> 'ok' = 'false')
               or (jsonb_typeof(e) = 'object' and not exists (
                     select 1 from jsonb_each(e) c(k, val)
                     where not (val = 'null'::jsonb or val = 'false'::jsonb)))));
exception
  when others then
    return true;
end;
$$;
grant execute on function pg_temp.rpc_refused(oid, uuid) to authenticated;

create temp table ids (k text primary key, v text);
grant select, insert on ids to authenticated, service_role;

-- Fixed identities: S1 (seeded Sales), S2 (second Sales), owner, admin, client A.
select pg_temp.new_user('40000000-0000-4000-8000-000000000002', 'sales.two@example.test', 'sales');

-- ===========================================================================
-- T-SALES-22 / T-SALES-02: helper results per role
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(private.is_staff(), true, 'T-SALES-22: is_staff() is still true for the Owner');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(private.is_staff(), true, 'T-SALES-22: is_staff() is still true for an Admin');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(private.is_staff(), false, 'T-SALES-22: is_staff() is false (not null) for a client');
select is(private.is_sales(), false, 'T-SALES-02: is_sales() is false for a client');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(private.is_staff(), false, 'T-SALES-02: is_staff() is false for a Sales Representative');
select is(private.is_owner(), false, 'T-SALES-02: is_owner() is false for a Sales Representative');
reset role;
-- wpc_is_staff_aal2() has no API grant; evaluated as the owner with the same claims.
select is(private.wpc_is_staff_aal2(), false, 'T-SALES-02: wpc_is_staff_aal2() is false for a Sales Representative');
set local role authenticated;
select is(private.can_access_project('20000000-0000-4000-8000-0000000000a0'), false,
  'T-SALES-02: can_access_project() is false for a Sales Representative');
select is(private.is_sales(), true, 'is_sales() is true for a Sales Representative at aal2 in a live session');
select is((public.auth_context() ->> 'staff_role'), 'sales', 'auth_context reports the sales role');
-- Setup: S1 creates its own customer project (assigned automatically; T-SALES-04 in 310).
insert into ids select 'ps1', public.sales_create_customer_project('Sales One Customer LLC', 'Sales One', 'Sales One website') ->> 'project_id';
select isnt((select v from ids where k = 'ps1'), null, 'setup: S1 created an assigned project');
select is(private.sales_assigned((select v::uuid from ids where k = 'ps1')), true, 'sales_assigned() is true for the own project');
select is(private.sales_assigned('20000000-0000-4000-8000-0000000000a0'), false,
  'sales_assigned() is false for an unassigned project');
reset role;

-- ===========================================================================
-- T-SALES-02: enumerated regression over every exposed staff-only RPC (Phase 2, WP-0,
-- WP-B, WP-C). Called as a Sales Representative at aal2 with fresh MFA, with the ID of the
-- representative's OWN assigned project for every uuid argument. Every call must refuse
-- and nothing may be written. Excluded: WP-S functions and the three functions AUTH-005
-- opens to Sales (tested in 310), and auth_context (the caller's own context).
-- ===========================================================================
create temp table before_counts as select pg_temp.table_counts() as c;
create temp table enumerated (name text, refused boolean);
grant select, insert on enumerated to authenticated;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
insert into enumerated
select p.proname, pg_temp.rpc_refused(p.oid, (select v::uuid from ids where k = 'ps1'))
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
  and p.proname not in ('auth_context', 'create_invitation', 'revoke_invitation', 'issue_order_summary',
    'sales_create_customer_project', 'assign_sales_representative', 'end_sales_assignment',
    'sales_list_customers', 'sales_project_progress');
reset role;
select cmp_ok((select count(*)::int from enumerated), '>=', 60,
  'T-SALES-02: the enumeration covers the complete exposed staff surface');
select is((select array_agg(name order by name) from enumerated where not refused), null,
  'T-SALES-02: every exposed staff-only RPC refuses a Sales Representative on its own assigned project');
select is(pg_temp.table_counts(), (select c from before_counts),
  'T-SALES-02: the enumerated calls wrote no row to any application table');

-- Positive control: the same harness reports the Owner's calls as NOT refused, so the
-- refusals above are real denials, not artifacts of the generated arguments.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(pg_temp.rpc_refused('public.project_status(uuid)'::regprocedure, (select v::uuid from ids where k = 'ps1')),
  false, 'T-SALES-02 control: the Owner reads the project status');
select is(pg_temp.rpc_refused('public.get_intake_state(uuid)'::regprocedure, (select v::uuid from ids where k = 'ps1')),
  false, 'T-SALES-02 control: the Owner reads the intake state');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(pg_temp.rpc_refused('public.get_intake_state(uuid)'::regprocedure, (select v::uuid from ids where k = 'ps1')),
  true, 'T-SALES-02: the representative cannot read the intake state of its own project');
reset role;

-- Static: apart from the objects AUTH-005 names, no definer function mentions the Sales role.
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosrc ~ '''sales'''
    and p.proname not in ('create_invitation', 'revoke_invitation', 'accept_invitation', 'set_staff_role',
      'issue_order_summary', 'is_sales', 'assign_sales_representative', 'end_sales_assignment',
      -- OI-85 integrity triggers (CURRENT-STATE §12, C2 and C3): they only refuse.
      'project_memberships_sales_separation', 'staff_roles_sales_separation')), null,
  'T-SALES-02: only the AUTH-005 objects grant anything to the Sales role');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosrc ~ 'is_staff\(\)' and p.prosrc ~ '''sales'''
    and p.proname not in ('create_invitation', 'revoke_invitation', 'issue_order_summary',
      'assign_sales_representative', 'end_sales_assignment')), 0,
  'T-SALES-02: no staff-only (is_staff) function was widened to Sales');

-- ===========================================================================
-- T-SALES-23: direct access, enumerated over every exposed table and view
-- ===========================================================================
create function pg_temp.visible_violations(p_self uuid, p_allow_assignments boolean) returns text[]
language plpgsql as $$
declare
  r record;
  n bigint;
  v text[] := '{}';
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') order by 1 loop
    begin
      execute format('select count(*) from public.%I where %s', r.relname, case r.relname
        when 'profiles' then format('id <> %L', p_self)
        when 'staff_roles' then format('user_id <> %L', p_self)
        when 'project_sales_assignments' then
          case when p_allow_assignments then format('not (sales_user_id = %L and active)', p_self) else 'true' end
        else 'true' end) into n;
    exception when insufficient_privilege then
      n := 0;
    end;
    if n > 0 then
      v := v || r.relname::text;
    end if;
  end loop;
  return v;
end;
$$;
grant execute on function pg_temp.visible_violations(uuid, boolean) to authenticated;

select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal1');
select is(pg_temp.visible_violations('00000000-0000-4000-8000-000000000005', false), '{}'::text[],
  'T-SALES-23: at aal1 a Sales Representative reads no row of any exposed table or view beyond its own identity rows');
select is((select count(*)::int from public.project_sales_assignments), 0,
  'T-SALES-23: at aal1 a Sales Representative does not even read its own assignments');
select is((select count(*)::int from public.profiles), 1, 'T-SALES-23: at aal1 it reads its own profile');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(pg_temp.visible_violations('00000000-0000-4000-8000-000000000005', true), '{}'::text[],
  'T-SALES-23: at aal2 a Sales Representative reads no row of any exposed table or view beyond its own identity and active assignment rows');
select is((select count(*)::int from public.project_sales_assignments), 1,
  'T-SALES-23: at aal2 it reads exactly its own active assignment');
select is((select count(*)::int from public.projects), 0, 'T-SALES-23: no project row, not even the assigned one');
select is((select count(*)::int from public.order_summaries), 0, 'T-SALES-23: no order-summary row');
select is((select count(*)::int from public.invitations), 0, 'T-SALES-23: no invitation row');
select is((select count(*)::int from public.audit_events), 0, 'T-SALES-23: no audit row');
select is((select count(*)::int from public.project_sales_assignment_history), 0, 'T-SALES-23: no assignment history row');

-- Writes: for every table, insert, update, and delete as the Sales Representative.
create function pg_temp.write_violations() returns text[] language plpgsql as $$
declare
  r record;
  n bigint;
  v text[] := '{}';
begin
  for r in select c.relname, (select a.attname from pg_attribute a where a.attrelid = c.oid and a.attnum > 0
                                and not a.attisdropped order by a.attnum limit 1) as col
           from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind in ('r', 'p') order by 1 loop
    begin
      execute format('update public.%I set %I = %I', r.relname, r.col, r.col);
      get diagnostics n = row_count;
      if n > 0 then v := v || ('update:' || r.relname); end if;
    exception when others then null;
    end;
    begin
      execute format('delete from public.%I', r.relname);
      get diagnostics n = row_count;
      if n > 0 then v := v || ('delete:' || r.relname); end if;
    exception when others then null;
    end;
    begin
      execute format('insert into public.%I default values', r.relname);
      v := v || ('insert:' || r.relname);
    exception when others then null;
    end;
  end loop;
  return v;
end;
$$;
grant execute on function pg_temp.write_violations() to authenticated;
select is(pg_temp.write_violations(), '{}'::text[], 'T-SALES-23: at aal2 a Sales Representative writes no row of any table');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal1');
select is(pg_temp.write_violations(), '{}'::text[], 'T-SALES-23: at aal1 a Sales Representative writes no row of any table');
reset role;
select is(pg_temp.table_counts(), (select c from before_counts),
  'T-SALES-23: the table counts are unchanged after every write attempt');
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select throws_ok($$ insert into public.client_businesses (legal_name, display_name) values ('Direct LLC', 'Direct') $$,
  '42501', null, 'T-SALES-23: a Sales Representative cannot create a business directly (no table policy)');
reset role;

-- ===========================================================================
-- T-SALES-24 (OI-85): authorization holds INDEPENDENTLY of the integrity triggers.
-- Controlled local/CI-only inconsistent-data fixture: the C2 trigger is disabled by name,
-- as the migration owner, only around this insert, inside this rolled-back transaction.
-- ===========================================================================
insert into storage.objects (bucket_id, name) values ('project-assets',
  '20000000-0000-4000-8000-0000000000a0/assets/52000000-0000-4000-8000-0000000000a1');
insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
  original_name, status, quarantine_path, released_path, size_bytes, sha256, released_sha256, released_bytes,
  completed_at, uploaded_by)
values ('52000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', gen_random_uuid(), 1, 'logo',
  'image/png', 100, 'f.png', 'available', 'quarantine/20000000-0000-4000-8000-0000000000a0/52000000-0000-4000-8000-0000000000a1',
  '20000000-0000-4000-8000-0000000000a0/assets/52000000-0000-4000-8000-0000000000a1', 100, repeat('5', 64), repeat('5', 64),
  100, now(), '00000000-0000-4000-8000-0000000000a1');
alter table public.project_memberships disable trigger project_memberships_sales_separation;
insert into public.project_memberships (project_id, user_id) values
  ((select v::uuid from ids where k = 'ps1'), '00000000-0000-4000-8000-000000000005'),
  ('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000005');
alter table public.project_memberships enable trigger project_memberships_sales_separation;
select is((select count(*)::int from public.project_memberships m join public.staff_roles s on s.user_id = m.user_id
  where m.status = 'active' and s.status = 'active' and s.role = 'sales'), 2,
  'T-SALES-24 fixture: inconsistent Sales memberships exist (inside this transaction only)');
select is((select tgenabled::text from pg_trigger where tgname = 'project_memberships_sales_separation'), 'O',
  'T-SALES-24 fixture: the trigger is enabled again before any assertion');
create temp table fixture_counts as select pg_temp.table_counts() as c;

-- Positive control: the real client of Project A is authorized on the same records.
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.record_asset_access('52000000-0000-4000-8000-0000000000a1') ->> 'ok', 'true',
  'T-SALES-24 control: the client is authorized to download the released file');
select is(public.project_status('20000000-0000-4000-8000-0000000000a0') ->> 'ok', 'true',
  'T-SALES-24 control: the client reads the project status');
select is((select count(*)::int from public.projects where id = '20000000-0000-4000-8000-0000000000a0'), 1,
  'T-SALES-24 control: the client reads its project row');
reset role;
create temp table control_counts as select pg_temp.table_counts() as c;

select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(private.is_project_member('20000000-0000-4000-8000-0000000000a0'), false,
  'T-SALES-24 (C1): is_project_member is false for a Sales Representative holding a membership');
select is(private.can_access_project('20000000-0000-4000-8000-0000000000a0'), false,
  'T-SALES-24 (C1): so can_access_project is false');
select is((select count(*)::int from public.projects), 0, 'T-SALES-24: no project row');
select is((select count(*)::int from public.client_businesses), 0, 'T-SALES-24: no business row');
select is((select count(*)::int from public.order_summaries), 0, 'T-SALES-24: no order-summary row');
select is((select count(*)::int from public.agreement_versions), 0, 'T-SALES-24: no agreement-version row');
select is((select count(*)::int from public.agreement_acceptances), 0, 'T-SALES-24: no acceptance row');
select is((select count(*)::int from public.asset_uploads), 0, 'T-SALES-24: no upload row');
select is((select count(*)::int from public.intake_submissions) + (select count(*)::int from public.intake_reviews), 0,
  'T-SALES-24: no intake row');
select is((select count(*)::int from public.preview_releases), 0, 'T-SALES-24: no release row');
select is((select count(*)::int from storage.objects), 0, 'T-SALES-24: no storage object');
select is(public.record_asset_access('52000000-0000-4000-8000-0000000000a1') ->> 'ok', 'false',
  'T-SALES-24: released-file download authorization is refused');
select is(public.project_status('20000000-0000-4000-8000-0000000000a0') ->> 'ok', 'false',
  'T-SALES-24: project_status is refused');
select is(public.get_intake_state('20000000-0000-4000-8000-0000000000a0'), null, 'T-SALES-24: the intake state is refused');
-- Every exposed table and view: only the own identity rows (profile, staff role, own active
-- assignments, and the fixture's own membership rows, readable through the unchanged Phase 2
-- policy project_memberships_select) are visible.
create function pg_temp.fixture_violations(p_self uuid) returns text[] language plpgsql as $$
declare
  r record;
  n bigint;
  v text[] := '{}';
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm') order by 1 loop
    begin
      execute format('select count(*) from public.%I where %s', r.relname, case r.relname
        when 'profiles' then format('id <> %L', p_self)
        when 'staff_roles' then format('user_id <> %L', p_self)
        when 'project_memberships' then format('user_id <> %L', p_self)
        when 'project_sales_assignments' then format('not (sales_user_id = %L and active)', p_self)
        else 'true' end) into n;
    exception when insufficient_privilege then
      n := 0;
    end;
    if n > 0 then
      v := v || r.relname::text;
    end if;
  end loop;
  return v;
end;
$$;
grant execute on function pg_temp.fixture_violations(uuid) to authenticated;
select is(pg_temp.fixture_violations('00000000-0000-4000-8000-000000000005'), '{}'::text[],
  'T-SALES-24: with a membership, a Sales Representative still reads no client-only row of any table or view');
create temp table enumerated_fixture (name text, refused boolean);
grant select, insert on enumerated_fixture to authenticated;
insert into enumerated_fixture
select p.proname, pg_temp.rpc_refused(p.oid, '20000000-0000-4000-8000-0000000000a0')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
  and p.proname not in ('auth_context', 'create_invitation', 'revoke_invitation', 'issue_order_summary',
    'sales_create_customer_project', 'assign_sales_representative', 'end_sales_assignment',
    'sales_list_customers', 'sales_project_progress');
insert into enumerated_fixture
select p.proname || ':own', pg_temp.rpc_refused(p.oid, (select v::uuid from ids where k = 'ps1'))
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
  and p.proname not in ('auth_context', 'create_invitation', 'revoke_invitation', 'issue_order_summary',
    'sales_create_customer_project', 'assign_sales_representative', 'end_sales_assignment',
    'sales_list_customers', 'sales_project_progress');
reset role;
select is((select array_agg(name order by name) from enumerated_fixture where not refused), null,
  'T-SALES-24: with a membership, every exposed RPC still refuses the Sales Representative (Project A and its own project)');
select is(pg_temp.table_counts(), (select c from control_counts),
  'T-SALES-24: the refused calls wrote no row to any application table');
select is((select count(*)::int from public.audit_events where action = 'upload.accessed'
  and actor_user_id = '00000000-0000-4000-8000-000000000005'), 0, 'T-SALES-24: no download access was recorded for the representative');
update public.project_memberships set status = 'revoked', revoked_at = now()
 where user_id = '00000000-0000-4000-8000-000000000005';

-- ===========================================================================
-- T-SALES-11: no project-assets storage access, including the assigned project's path
-- ===========================================================================
insert into storage.objects (bucket_id, name) values
  ('project-assets', (select v from ids where k = 'ps1') || '/approved/logo.png'),
  ('project-assets', '20000000-0000-4000-8000-0000000000a0/approved/logo.png');
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is((select count(*)::int from storage.objects), 0, 'T-SALES-11: a Sales Representative reads no storage object');
select is(private.can_access_project_path((select v from ids where k = 'ps1') || '/approved/logo.png'), false,
  'T-SALES-11: the assigned project path is not accessible');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('project-assets', %L) $$,
  (select v from ids where k = 'ps1') || '/approved/upload.png'), '42501', null,
  'T-SALES-11: a Sales Representative cannot write a storage object');
reset role;

-- ===========================================================================
-- T-SALES-01: only the Owner with fresh MFA invites or assigns the Sales role
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.create_invitation('staff', 'sales.three@example.test', 'Sales Three', null, 'sales') ->> 'error', 'forbidden',
  'T-SALES-01: the Owner without fresh MFA cannot invite a Sales Representative');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.create_invitation('staff', 'sales.three@example.test', 'Sales Three', null, 'sales') ->> 'error', 'forbidden',
  'T-SALES-01: an Admin cannot invite a Sales Representative');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.create_invitation('staff', 'sales.three@example.test', 'Sales Three', null, 'sales') ->> 'error', 'forbidden',
  'T-SALES-01: a Sales Representative cannot invite staff');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'inv_s3', public.create_invitation('staff', 'sales.three@example.test', 'Sales Three', null, 'sales') ->> 'invitation_id';
select isnt((select v from ids where k = 'inv_s3'), null, 'T-SALES-01: the Owner with fresh MFA invites a Sales Representative');
select is(public.create_invitation('staff', 'ful@example.test', 'F', null, 'fulfillment') ->> 'error', 'role_not_assignable',
  'T-SALES-01: fulfillment stays unassignable');
reset role;
select pg_temp.new_user('40000000-0000-4000-8000-000000000003', 'sales.three@example.test');
select pg_temp.act_as('40000000-0000-4000-8000-000000000003');
select is(public.accept_invitation((select v::uuid from ids where k = 'inv_s3'), null) ->> 'ok', 'true',
  'T-SALES-01: the invitee accepts the Sales invitation');
select is(public.accept_invitation((select v::uuid from ids where k = 'inv_s3'), null) ->> 'error', 'invalid',
  'T-SALES-15: a reused (already accepted) staff invitation is refused');
reset role;
select is(private.staff_role_of('40000000-0000-4000-8000-000000000003'), 'sales'::public.staff_role,
  'T-SALES-01: the accepted invitation grants exactly the Sales role');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.set_staff_role('40000000-0000-4000-8000-000000000003', 'admin', 'promote') ->> 'ok', 'true',
  'T-SALES-01: the Owner with fresh MFA can change a Sales Representative to Admin');
select is(public.set_staff_role('40000000-0000-4000-8000-000000000003', 'sales', 'back to sales') ->> 'ok', 'true',
  'T-SALES-01: the Owner with fresh MFA can assign the Sales role');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.set_staff_role('40000000-0000-4000-8000-000000000003', 'admin', 'x') ->> 'error', 'forbidden',
  'T-SALES-01: role changes need fresh MFA');
reset role;

-- ===========================================================================
-- T-SALES-15: privilege escalation
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.set_staff_role('00000000-0000-4000-8000-000000000005', 'owner', 'self') ->> 'error', 'forbidden',
  'T-SALES-15: a Sales Representative cannot promote itself');
select is(public.set_staff_role('40000000-0000-4000-8000-000000000002', 'admin', 'x') ->> 'error', 'forbidden',
  'T-SALES-15: a Sales Representative cannot change another role');
select is(public.revoke_staff('40000000-0000-4000-8000-000000000002', 'x') ->> 'error', 'forbidden',
  'T-SALES-15: a Sales Representative cannot revoke staff');
select throws_ok($$ insert into public.staff_roles (user_id, role) values ('40000000-0000-4000-8000-000000000002', 'owner') $$,
  '42501', null, 'T-SALES-15: no direct staff_roles insert');
select throws_ok($$ update public.staff_roles set role = 'owner' where user_id = '00000000-0000-4000-8000-000000000005' $$,
  '42501', null, 'T-SALES-15: no direct staff_roles update, even of its own row');
select throws_ok($$ select private.record_audit_event('forged.action') $$, '42501', null,
  'T-SALES-15: internal audit writer is not callable');
select throws_ok($$ select private.emit_domain_event('order_summary.issued', null, 'x', 'x', '{}', 'x') $$, '42501', null,
  'T-SALES-15: internal domain-event writer is not callable');
select throws_ok(format($$ select private.project_financial_status(%L) $$, (select v from ids where k = 'ps1')), '42501', null,
  'T-SALES-15: the financial gate interface is not callable');
select throws_ok($$ select * from private.current_package_scope('essential') $$, '42501', null,
  'T-SALES-15: the package scope definition is not readable');
select throws_ok($$ select * from private.billing_package_scope $$, '42501', null,
  'T-SALES-15: the package scope table is not readable');
select throws_ok($$ select private.consume_rate_limit('sales-invite:x', 1, interval '1 hour') $$, '42501', null,
  'T-SALES-15: the rate limiter is not callable');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'inv_forged', public.create_invitation('staff', 'new.owner@example.test', 'New Owner', null, 'owner') ->> 'invitation_id';
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.accept_invitation((select v::uuid from ids where k = 'inv_forged'), null) ->> 'error', 'invalid',
  'T-SALES-15: a staff invitation addressed to someone else cannot be accepted');
select is(public.accept_invitation((select v::uuid from ids where k = 'inv_forged'), repeat('A', 43)) ->> 'error', 'invalid',
  'T-SALES-15: a forged token is refused');
reset role;
select is(private.staff_role_of('00000000-0000-4000-8000-000000000005'), 'sales'::public.staff_role,
  'T-SALES-15: the representative still holds only the Sales role');

-- ===========================================================================
-- T-SALES-16: assignment manipulation
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select throws_ok(format($$ insert into public.project_sales_assignments (project_id, sales_user_id, assigned_by)
  values ('20000000-0000-4000-8000-0000000000a0', %L, %L) $$, '00000000-0000-4000-8000-000000000005',
  '00000000-0000-4000-8000-000000000005'), '42501', null, 'T-SALES-16: no direct assignment insert');
select throws_ok($$ update public.project_sales_assignments set active = false $$, '42501', null,
  'T-SALES-16: no direct assignment update');
select throws_ok($$ delete from public.project_sales_assignments $$, '42501', null, 'T-SALES-16: no direct assignment delete');
select throws_ok($$ insert into public.project_sales_assignment_history (assignment_id, project_id, sales_user_id, event)
  select id, project_id, sales_user_id, 'created' from public.project_sales_assignments $$, '42501', null,
  'T-SALES-16: no direct history insert');
create temp table mark16 as select coalesce(max(id), 0) as last_id from public.audit_events;
grant select on mark16 to authenticated;
select is(public.assign_sales_representative('20000000-0000-4000-8000-0000000000a0', '00000000-0000-4000-8000-000000000005') ->> 'error',
  'forbidden', 'T-SALES-16: self-assignment to an existing project is rejected');
select is(public.assign_sales_representative((select v::uuid from ids where k = 'ps1'), '40000000-0000-4000-8000-000000000002') ->> 'error',
  'forbidden', 'T-SALES-16: assigning another representative is rejected');
select is(public.end_sales_assignment((select id from public.project_sales_assignments limit 1)) ->> 'error', 'forbidden',
  'T-SALES-16: ending its own assignment is rejected');
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark16)
  and action = 'sales_assignment.change_rejected' and actor_role = 'sales'), 3,
  'T-SALES-16: every rejected assignment change is audited with the Sales actor role');
select is((select count(*)::int from public.project_sales_assignments where sales_user_id = '00000000-0000-4000-8000-000000000005'), 1,
  'T-SALES-16: the assignments are unchanged');
select pg_temp.as_service();
select throws_ok($$ update public.project_sales_assignments set active = false $$, '42501', null,
  'T-SALES-16: service_role cannot write assignments either');
reset role;
select throws_ok($$ delete from public.project_sales_assignment_history $$, '42501', null,
  'T-SALES-28: history rows cannot be deleted, even by the migration owner');

-- ===========================================================================
-- T-SALES-09: no administrative, financial, fulfillment, or publication authority
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.place_billing_hold((select v::uuid from ids where k = 'ps1'), 'owner_manual_hold', 'x') ->> 'ok', 'false',
  'T-SALES-09: cannot place a billing hold on its own project');
select is(public.revoke_membership((select v::uuid from ids where k = 'ps1'), 'x') ->> 'error', 'forbidden',
  'T-SALES-09: cannot revoke memberships');
select is(public.set_user_status('00000000-0000-4000-8000-0000000000a1', 'deactivated', 'x') ->> 'error', 'forbidden',
  'T-SALES-09: cannot deactivate users');
reset role;

-- ===========================================================================
-- T-SALES-03 / T-SALES-20: every Sales function requires aal2 and a live staff session
-- ===========================================================================
create function pg_temp.sales_calls_refused() returns text[] language plpgsql as $$
declare
  v text[] := '{}';
  v_ps1 uuid := (select ids.v::uuid from ids where ids.k = 'ps1');
begin
  if public.sales_list_customers() ->> 'ok' = 'true' then v := v || 'sales_list_customers'::text; end if;
  if public.sales_project_progress(v_ps1) ->> 'ok' = 'true' then v := v || 'sales_project_progress'::text; end if;
  if public.sales_create_customer_project('Weak LLC', 'Weak', 'Weak site') ->> 'ok' = 'true' then
    v := v || 'sales_create_customer_project'::text; end if;
  if public.create_invitation('client', 'weak.client@example.test', 'Weak', v_ps1) ->> 'ok' = 'true' then
    v := v || 'create_invitation'::text; end if;
  if public.issue_order_summary(v_ps1, 'essential') ->> 'ok' = 'true' then v := v || 'issue_order_summary'::text; end if;
  return v;
end;
$$;
grant execute on function pg_temp.sales_calls_refused() to authenticated;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal1');
select is(pg_temp.sales_calls_refused(), '{}'::text[], 'T-SALES-03: every Sales function refuses an aal1 session');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true, interval '13 hours');
select is(pg_temp.sales_calls_refused(), '{}'::text[], 'T-SALES-20: every Sales function refuses a session past the 12-hour staff limit');
reset role;
select set_config('request.jwt.claims', jsonb_build_object('sub', '00000000-0000-4000-8000-000000000005', 'role', 'authenticated',
  'aal', 'aal2', 'session_id', gen_random_uuid())::text, true);
set local role authenticated;
select is(pg_temp.sales_calls_refused(), '{}'::text[], 'T-SALES-20: every Sales function refuses a revoked (deleted) session');
reset role;
update public.profiles set status = 'deactivated' where id = '40000000-0000-4000-8000-000000000002';
select pg_temp.act_as('40000000-0000-4000-8000-000000000002', 'aal2', true);
select is(private.is_sales(), false, 'T-SALES-20: a deactivated Sales Representative is not an authorized Sales caller');
select is(public.sales_list_customers() ->> 'error', 'forbidden', 'T-SALES-20: a deactivated representative is refused');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1', 'aal1');
select is(pg_temp.sales_calls_refused(), '{}'::text[], 'T-SALES-21: a client cannot use any Sales function');
reset role;
select is((select count(*)::int from public.client_businesses where legal_name = 'Weak LLC'), 0,
  'T-SALES-20: no weak session created anything');

-- ===========================================================================
-- T-SALES-25: server-reported actors that require staff reject a Sales Representative
-- ===========================================================================
select pg_temp.as_service();
select is(public.record_live_verification(gen_random_uuid(), '00000000-0000-4000-8000-000000000005', 'b', true, true, true, true) ->> 'error',
  'forbidden', 'T-SALES-25: record_live_verification rejects a Sales requester');
select is(public.record_live_verification(gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'b', true, true, true, true) ->> 'error',
  'not_found', 'T-SALES-25: the same call with the Owner as requester passes the actor check');
reset role;

-- Catalog (T-TEN-05, T-TEN-06 for the new objects)
select is((select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname in ('project_sales_assignments', 'project_sales_assignment_history')), true,
  'T-TEN-05: both new tables have RLS');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef and p.proname like 'sales%'), 0,
  'T-TEN-06: the public Sales wrappers are SECURITY INVOKER');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.prosecdef
    and p.proname in ('is_sales', 'sales_assigned', 'current_package_scope', 'sales_create_customer_project',
      'assign_sales_representative', 'end_sales_assignment', 'sales_list_customers', 'sales_project_progress')
    and not coalesce(p.proconfig @> array['search_path=""'], false)), 0,
  'T-TEN-06: every new definer function has search_path = ''''');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and (p.proname like 'sales%' or p.proname in ('is_sales', 'current_package_scope',
    'assign_sales_representative', 'end_sales_assignment'))
    and (has_function_privilege('anon', p.oid, 'execute'))), 0,
  'T-TEN-06: anon executes no Sales function');

select * from finish();
rollback;
