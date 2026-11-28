-- WP-C AUTH-026 (OI-131), PR 2: the parameterized private variants used by the staff operational
-- queue are exactly equivalent to the existing helpers when given the caller's precomputed
-- financial status, preserve each helper's exception path when that evaluation failed, and
-- are executable by no API role; operational_queue keeps its layers, grants and volatility.
-- (Queue output equivalence, item for item, and the evaluation counts are proven in
-- tests/integration/wpc-oi131-queue.test.ts.)
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(18);

-- Fixtures (rolled back): a current release for Project A; a submitted, then accepted intake
-- for Project B; a third project with a submitted intake awaiting review.
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by, released_at)
values ('37000000-0000-4000-8000-0000000000a1', '20000000-0000-4000-8000-0000000000a0', 1, repeat('7', 40), 'dpl_oi131_a1',
        'https://preview-a.example.test/oi131', '00000000-0000-4000-8000-000000000002', now() - interval '4 days');
insert into public.intake_submissions (id, project_id, version, status, content, created_by, submitted_by, submitted_at)
values ('37100000-0000-4000-8000-0000000000b0', '20000000-0000-4000-8000-0000000000b0', 1, 'submitted', '{}',
        '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', now());
insert into public.intake_reviews (project_id, submission_id, decision, reviewed_by) values
  ('20000000-0000-4000-8000-0000000000b0', '37100000-0000-4000-8000-0000000000b0', 'accepted', '00000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claims', json_build_object('sub', '00000000-0000-4000-8000-000000000001',
  'role', 'authenticated')::text, true);
insert into public.projects (id, client_business_id, name, created_by)
select '20000000-0000-4000-8000-0000000000c0', client_business_id, 'OI-131 third project', '00000000-0000-4000-8000-000000000001'
  from public.projects where id = '20000000-0000-4000-8000-0000000000a0';
insert into public.intake_submissions (id, project_id, version, status, content, created_by, submitted_by, submitted_at)
values ('37100000-0000-4000-8000-0000000000c0', '20000000-0000-4000-8000-0000000000c0', 1, 'submitted', '{}',
        '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', now());

-- Each project's precomputed status, exactly as the queue now passes it.
create temp table fin as
  select p.id as project_id, to_jsonb(private.project_financial_status(p.id)) as status from public.projects p;

-- ---------------------------------------------------------------------------
-- 1. Equivalence with the existing helpers (every project in the database)
-- ---------------------------------------------------------------------------
select ok((select count(*) >= 3 from fin), 'the fixtures give at least three projects');
select ok((select bool_and(private.wpc_intake_unlocked_from(f.project_id, f.status) = private.wpc_intake_unlocked(f.project_id))
             from fin f),
  'wpc_intake_unlocked_from equals wpc_intake_unlocked for every project');
select ok((select bool_and(private.intake_state_from(f.project_id, f.status) = private.intake_state_of(f.project_id))
             from fin f),
  'intake_state_from equals intake_state_of for every project');
select is((select array_agg(private.intake_state_from(f.project_id, f.status)::text order by f.project_id) from fin f
            where f.project_id in ('20000000-0000-4000-8000-0000000000a0', '20000000-0000-4000-8000-0000000000b0',
                                   '20000000-0000-4000-8000-0000000000c0')),
  (select array_agg(private.intake_state_of(p)::text order by p)
     from unnest(array['20000000-0000-4000-8000-0000000000a0', '20000000-0000-4000-8000-0000000000b0',
                       '20000000-0000-4000-8000-0000000000c0']::uuid[]) p),
  'the fixtures reach the locked or open, accepted and submitted branches identically');
select ok((select bool_and(to_jsonb(private.project_fulfillment_status_from(f.project_id, f.status))
                           = to_jsonb(private.project_fulfillment_status(f.project_id))) from fin f),
  'project_fulfillment_status_from equals project_fulfillment_status for every project');
select ok((select bool_and(private.evaluate_publication_gates_from(f.project_id, (private.current_release(f.project_id)).id,
                             f.status, false)
                           = private.evaluate_publication_gates(f.project_id, (private.current_release(f.project_id)).id))
             from fin f where (private.current_release(f.project_id)).id is not null),
  'evaluate_publication_gates_from equals evaluate_publication_gates for every project with a release');
select ok(private.evaluate_publication_gates_from('20000000-0000-4000-8000-0000000000a0', '37000000-0000-4000-8000-0000000000a1',
            (select status from fin where project_id = '20000000-0000-4000-8000-0000000000a0'), false)
          = private.evaluate_publication_gates('20000000-0000-4000-8000-0000000000a0', '37000000-0000-4000-8000-0000000000a1'),
  'and for the fixture release on Project A');

-- ---------------------------------------------------------------------------
-- 2. The failure path of each helper is preserved
-- ---------------------------------------------------------------------------
select is(private.wpc_intake_unlocked_from('20000000-0000-4000-8000-0000000000a0', null), false,
  'a failed evaluation (null status) keeps intake locked, as the original exception path does');
select is((private.project_fulfillment_status_from('20000000-0000-4000-8000-0000000000a0', null)).intake_state::text,
  private.intake_state_from('20000000-0000-4000-8000-0000000000a0', null)::text,
  'a failed evaluation reaches the fulfillment status only through the intake state, as in the original');
select is(private.intake_state_from('20000000-0000-4000-8000-0000000000c0', null)::text, 'submitted',
  'a submitted intake is reported whatever the financial evaluation');
select is((select g ->> 'reason' from jsonb_array_elements(
             private.evaluate_publication_gates_from('20000000-0000-4000-8000-0000000000a0',
               '37000000-0000-4000-8000-0000000000a1', null, true) -> 'gates') g where g ->> 'gate' = 'G1'),
  'unavailable', 'a failed evaluation gives the original''s unavailable reason at G1');
select ok(not coalesce((private.evaluate_publication_gates_from('20000000-0000-4000-8000-0000000000a0',
             '37000000-0000-4000-8000-0000000000a1', null, true) ->> 'eligible')::boolean, false),
  'and the release is not eligible');

-- ---------------------------------------------------------------------------
-- 3. Catalog: layers, grants, volatility (acceptance 6 and 7)
-- ---------------------------------------------------------------------------
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'private' and p.proname in ('wpc_intake_unlocked_from', 'intake_state_from',
                         'evaluate_publication_gates_from', 'project_fulfillment_status_from')
                         and (has_function_privilege('authenticated', p.oid, 'execute')
                           or has_function_privilege('anon', p.oid, 'execute')
                           or has_function_privilege('service_role', p.oid, 'execute'))),
  'the new helpers: no API-role execute');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname in ('wpc_intake_unlocked_from', 'intake_state_from',
              'evaluate_publication_gates_from', 'project_fulfillment_status_from')
              and p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']), 4,
  'the new helpers are SECURITY DEFINER, STABLE, with an empty search_path');
select ok((select p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
             and has_function_privilege('authenticated', p.oid, 'execute')
             and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('service_role', p.oid, 'execute')
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname = 'operational_queue'),
  'private.operational_queue keeps SECURITY DEFINER, STABLE, its empty search_path and its grants');
select ok((select not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
             and has_function_privilege('authenticated', p.oid, 'execute')
             and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('service_role', p.oid, 'execute')
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'operational_queue'),
  'public.operational_queue is unchanged (SECURITY INVOKER, STABLE, authenticated only)');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname in ('wpc_intake_unlocked', 'intake_state_of', 'evaluate_publication_gates',
              'project_fulfillment_status')),
  4, 'the existing helpers still exist with one signature each');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'private' and p.proname = 'operational_queue'
                         and (p.prosrc ~* 'project_financial_status|project_financial_anomalies|gate_anomalies'
                              or p.prosrc ~* 'lock\s+table|for\s+update|for\s+share|pg_advisory')),
  'the queue evaluates no per-project financial function and takes no lock');

select * from finish();
rollback;
