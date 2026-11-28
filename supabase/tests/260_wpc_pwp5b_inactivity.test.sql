-- WP-C PWP-5b inactivity reconciliation (AUTH-024; OI-110, OI-45; OD-16; 05 §7.1, §7.2, §9; 02 §13):
-- T-LC-18, the day-30 administrative suspension with every 05 §7.2 protection, the calendar-day
-- rule across both America/Detroit daylight-saving transitions, the earlier-schedule path for
-- releases that existed before 20261128130000, isolation, and the catalog and privilege layers.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(85);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1') returns void language plpgsql as $$
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
    'session_id', v_sid, 'amr', jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)))::text, true);
  set local role authenticated;
end;
$$;
grant execute on function pg_temp.act_as(uuid, text) to authenticated, service_role;

-- Fixture ids.
create temp table ids (k text primary key, v text);
grant select on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated;
insert into ids values
  ('a', '20000000-0000-4000-8000-0000000000a0'), ('b', '20000000-0000-4000-8000-0000000000b0'),
  ('owner', '00000000-0000-4000-8000-000000000001'), ('admin', '00000000-0000-4000-8000-000000000002'),
  ('sales', '00000000-0000-4000-8000-000000000005'),
  ('ca', '00000000-0000-4000-8000-0000000000a1'), ('cb', '00000000-0000-4000-8000-0000000000b1'),
  ('ra1', '36000000-0000-4000-8000-0000000000a1'), ('rb1', '36000000-0000-4000-8000-0000000000b1'),
  ('rb2', '36000000-0000-4000-8000-0000000000b2'), ('rb3', '36000000-0000-4000-8000-0000000000b3');

-- Calls as a given user; each returns the function's jsonb result.
create function pg_temp.milestone(p_uid uuid, p_aal text, p_release uuid, p_milestone text, p_on date,
  p_channel text default 'email', p_summary text default 'Recorded') returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.act_as(p_uid, p_aal);
  v := public.record_inactivity_milestone(p_release, p_milestone, p_channel, p_on, p_summary);
  reset role;
  return v;
end;
$$;
create function pg_temp.admin_ms(p_release uuid, p_milestone text, p_day integer) returns jsonb language sql as $$
  select pg_temp.milestone('00000000-0000-4000-8000-000000000002', 'aal2', p_release, p_milestone,
    ((select released_at from public.preview_releases where id = p_release) at time zone 'America/Detroit')::date + p_day);
$$;
create function pg_temp.hold(p_project uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  v := public.place_approval_hold(p_project, 'No response after the formal notice');
  reset role;
  return v;
end;
$$;
-- The derived queue for one project, approval and inactivity items only, as queue[:detail].
create function pg_temp.queue(p_project uuid) returns text[] language plpgsql as $$
declare v text[];
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  select array_agg(q ->> 'queue' || coalesce(':' || (q -> 'detail' ->> 'outreach'), '')
                   order by q ->> 'queue' || coalesce(':' || (q -> 'detail' ->> 'outreach'), '')) into v
    from public.operational_queue() q
   where q ->> 'project_id' = p_project::text
     and (q ->> 'queue' like 'approval_%' or q ->> 'queue' like 'inactivity_%'
          or q ->> 'queue' in ('awaiting_client_approval', 'blocked_by_hold'));
  reset role;
  return v;
end;
$$;
-- No financial, contractual, approval or publication effect (OI-45; T-LC-18).
create function pg_temp.effects_fingerprint() returns text language sql as $$
  select md5(concat_ws('|',
    (select count(*) from public.preview_approvals), (select count(*) from public.publication_authorizations),
    (select count(*) from public.publication_deployments), (select count(*) from public.ledger_entries),
    (select count(*) from public.payment_obligations), (select count(*) from public.payment_authorizations),
    (select count(*) from public.payment_authorization_events), (select count(*) from public.outbound_stripe_requests),
    (select count(*) from public.final_balance_invoices), (select count(*) from public.subscriptions),
    (select count(*) from public.service_terminations), (select count(*) from public.termination_notices),
    (select count(*) from public.refunds), (select coalesce(string_agg(to_jsonb(s)::text, ',' order by to_jsonb(s)::text), '')
                                              from public.subscriptions s),
    (select coalesce(string_agg(to_jsonb(r)::text, ',' order by r.id), '') from public.preview_releases r)));
$$;
create function pg_temp.local_at(p_day_offset integer, p_time time) returns timestamptz language sql as $$
  select (((now() at time zone 'America/Detroit')::date + p_day_offset) + p_time) at time zone 'America/Detroit';
$$;

-- Releases (fixture rows, written as the table owner after the migration, so on the revised schedule).
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by, released_at)
values (pg_temp.id('ra1'), pg_temp.id('a'), 1, repeat('e', 40), 'dpl_pwp5b_a1', 'https://preview-a.example.test',
        pg_temp.id('admin'), now() - interval '61 days'),
       (pg_temp.id('rb1'), pg_temp.id('b'), 1, repeat('f', 40), 'dpl_pwp5b_b1', 'https://preview-b.example.test',
        pg_temp.id('admin'), pg_temp.local_at(-10, '12:00'));
insert into ids values ('fp0', pg_temp.effects_fingerprint());

-- ---------------------------------------------------------------------------
-- 1. Catalog, privileges and the earlier-schedule snapshot (design condition 1)
-- ---------------------------------------------------------------------------
select ok(not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r
                       where has_table_privilege(r, 'private.inactivity_legacy_releases', 'select, insert, update, delete, truncate, references, trigger')),
  'no API role holds any privilege on private.inactivity_legacy_releases');
select is((select coalesce(array_agg(a.privilege_type::text order by a.privilege_type), '{}')
             from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
            where c.oid = 'private.inactivity_legacy_releases'::regclass
              and a.grantee in (select oid from pg_roles where rolname in ('anon', 'authenticated', 'service_role'))
               or (c.oid = 'private.inactivity_legacy_releases'::regclass and a.grantee = 0)), '{}'::text[],
  'its ACL names no API role and nothing for PUBLIC');
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'private') and p.prosrc ilike '%inactivity_legacy_releases%'),
  array['inactivity_schedule'], 'the only function that refers to it reads it (no function writes it)');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname in ('public', 'private')
              and p.prosrc ~* 'insert\s+into\s+private\.inactivity_legacy_releases'), 0,
  'no function inserts into it');
select is(private.inactivity_schedule(pg_temp.id('ra1')), 'v2_7_14_30_60', 'a release created after the migration is on the revised schedule');
select is(private.inactivity_schedule(null), null, 'no release has no schedule');
select ok((select relrowsecurity from pg_class where oid = 'public.inactivity_milestones'::regclass),
  'RLS is enabled on inactivity_milestones');
select is((select array_agg(policyname::text || ':' || permissive || ':' || cmd order by policyname) from pg_policies
            where schemaname = 'public' and tablename = 'inactivity_milestones'),
  array['inactivity_milestones_active_user:RESTRICTIVE:ALL', 'inactivity_milestones_select:PERMISSIVE:SELECT',
        'inactivity_milestones_staff_aal2:RESTRICTIVE:ALL'],
  'a staff select policy plus the restrictive staff-aal2 and active-user policies; no permissive write policy');
select ok(not has_table_privilege('authenticated', 'public.inactivity_milestones', 'insert, update, delete')
          and not has_table_privilege('anon', 'public.inactivity_milestones', 'select')
          and not has_table_privilege('service_role', 'public.inactivity_milestones', 'insert, update, delete'),
  'no API role writes inactivity_milestones directly; anon cannot read it');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'private' and p.proname in ('detroit_days_between', 'inactivity_schedule',
                         'inactivity_milestone_day', 'inactivity_milestone_recorded')
                         and (has_function_privilege('authenticated', p.oid, 'execute')
                           or has_function_privilege('anon', p.oid, 'execute')
                           or has_function_privilege('service_role', p.oid, 'execute'))),
  'internal helpers: no API-role execute');
select ok((select count(*) = 1 and bool_and(not p.prosecdef and p.proconfig = array['search_path=""']
             and has_function_privilege('authenticated', p.oid, 'execute')
             and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('service_role', p.oid, 'execute'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname = 'record_inactivity_milestone'),
  'public wrapper: SECURITY INVOKER, search_path empty, execute by authenticated only');
select ok((select count(*) = 1 and bool_and(p.prosecdef and p.proconfig = array['search_path=""']
             and has_function_privilege('authenticated', p.oid, 'execute')
             and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('service_role', p.oid, 'execute'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname = 'record_inactivity_milestone'),
  'private implementation: SECURITY DEFINER, search_path empty, execute by authenticated only');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname in ('public', 'private') and p.prosrc ilike '%inactivity_milestones%'
                         and p.prosrc ~* '(insert\s+into\s+public\.preview_approvals|ledger_entries|payment_|subscriptions|publication_deployments|publication_authorizations)'
                         and p.proname in ('record_inactivity_milestone', 'inactivity_milestone_recorded')),
  'OI-45: the milestone functions reference no approval, financial, subscription or publication table');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname in ('public', 'private') and p.prosrc ilike '%rescheduling_decision%'
                         and p.proname not in ('record_inactivity_milestone', 'inactivity_milestone_day')),
  'Q6: no code reads the rescheduling decision (it has no effect)');

-- ---------------------------------------------------------------------------
-- 2. Calendar days in America/Detroit across both transitions (02 §13)
-- ---------------------------------------------------------------------------
select is(private.detroit_days_between('2027-03-13 23:30 America/Detroit', '2027-03-14 23:30 America/Detroit'), 1,
  'spring forward 2027-03-14: 23 elapsed hours across the transition are one calendar day');
select is(private.detroit_days_between('2027-03-14 00:30 America/Detroit', '2027-03-14 23:59 America/Detroit'), 0,
  'spring forward: the same local date is day 0');
select is(private.detroit_days_between('2026-10-31 23:30 America/Detroit', '2026-11-01 23:30 America/Detroit'), 1,
  'fall back 2026-11-01: 25 elapsed hours across the transition are one calendar day');
select is(private.detroit_days_between('2026-11-01 00:30 America/Detroit', '2026-11-01 23:30 America/Detroit'), 0,
  'fall back: 24 elapsed hours within one local date are day 0, never one 24-hour day');
select is(private.detroit_days_between('2026-11-02 03:30+00', '2026-11-02 05:30+00'), 1,
  'two hours across local midnight are one calendar day (the UTC date does not count)');
select is(private.detroit_days_between('2027-02-12 12:00 America/Detroit', '2027-03-14 12:00 America/Detroit'), 30,
  'day 30 across spring forward is the release date + 30 local days');
select is(private.detroit_days_between(now() - interval '5 days', now()), private.detroit_days_since(now() - interval '5 days'),
  'the helper agrees with the existing detroit_days_since');

-- ---------------------------------------------------------------------------
-- 3. T-LC-18 on Project A, release 1 at day 61 (revised schedule)
-- ---------------------------------------------------------------------------
select is(pg_temp.queue(pg_temp.id('a')),
  array['approval_outreach_due:admin_notified', 'approval_outreach_due:courtesy_reminder', 'approval_outreach_due:reminder',
        'awaiting_client_approval', 'inactivity_formal_notice_due', 'inactivity_review_due'],
  'the revised queue at day 61: day 3, 7, 14 and 60 items due; no earlier-schedule item; no suspension eligibility yet');
set local role anon;
select throws_ok($$select public.record_inactivity_milestone('36000000-0000-4000-8000-0000000000a1', 'courtesy_reminder',
  'email', current_date, 'x')$$, '42501', null, 'anon cannot call record_inactivity_milestone');
reset role;
set local role service_role;
select throws_ok($$select public.record_inactivity_milestone('36000000-0000-4000-8000-0000000000a1', 'courtesy_reminder',
  'email', current_date, 'x')$$, '42501', null, 'service_role cannot call record_inactivity_milestone');
reset role;
select is(pg_temp.milestone(pg_temp.id('sales'), 'aal2', pg_temp.id('ra1'), 'courtesy_reminder', current_date) ->> 'error',
  'forbidden', 'Sales cannot record a milestone');
select is(pg_temp.milestone(pg_temp.id('ca'), 'aal1', pg_temp.id('ra1'), 'courtesy_reminder', current_date) ->> 'error',
  'forbidden', 'a client cannot record a milestone');
select is(pg_temp.milestone(pg_temp.id('admin'), 'aal1', pg_temp.id('ra1'), 'courtesy_reminder', current_date) ->> 'error',
  'forbidden', 'staff need aal2');
select is(pg_temp.milestone(pg_temp.id('admin'), 'aal2', pg_temp.id('ra1'), 'auto_approval', current_date) ->> 'error',
  'invalid_input', 'an unknown milestone is refused');
select is(pg_temp.milestone(pg_temp.id('admin'), 'aal2', pg_temp.id('ra1'), 'courtesy_reminder', current_date, 'fax') ->> 'error',
  'invalid_input', 'an unknown channel is refused');
select is(pg_temp.milestone(pg_temp.id('admin'), 'aal2', pg_temp.id('ra1'), 'courtesy_reminder', current_date, 'email', ' ') ->> 'error',
  'summary_required', 'a summary is required');
select is(pg_temp.admin_ms(pg_temp.id('ra1'), 'courtesy_reminder', 2) ->> 'error', 'invalid_date',
  'a milestone cannot be dated before its day');
select is(pg_temp.milestone(pg_temp.id('admin'), 'aal2', pg_temp.id('ra1'), 'courtesy_reminder',
  (now() at time zone 'America/Detroit')::date + 1) ->> 'error', 'invalid_date', 'nor in the future');
select is(pg_temp.admin_ms(pg_temp.id('ra1'), 'estimate_suspension', 14) ->> 'error', 'formal_notice_required',
  'the estimate suspension follows the formal notice');
select is(pg_temp.hold(pg_temp.id('a')) ->> 'error', 'formal_notice_required',
  'day 30 is not enough: the suspension follows the recorded day-14 formal notice');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'courtesy_reminder', 3) ->> 'ok')::boolean, 'day-3 courtesy reminder recorded');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'reminder', 7) ->> 'ok')::boolean, 'day-7 reminder recorded');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'admin_notified', 7) ->> 'ok')::boolean, 'day-7 Admin notification recorded');
select is(pg_temp.queue(pg_temp.id('a')),
  array['awaiting_client_approval', 'inactivity_formal_notice_due', 'inactivity_review_due'],
  'the outreach items clear only for the milestones recorded');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'formal_notice', 14) ->> 'ok')::boolean, 'day-14 formal notice recorded');
select is(pg_temp.queue(pg_temp.id('a')),
  array['awaiting_client_approval', 'inactivity_formal_notice_due', 'inactivity_review_due', 'inactivity_suspension_eligible'],
  'after the formal notice: suspension eligible at day 30+; the estimate suspension is still due');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'estimate_suspension', 14) ->> 'ok')::boolean,
  'day-14 preview-estimate suspension recorded');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'rescheduling_decision', 30) ->> 'ok')::boolean,
  'day-30 rescheduling decision recorded');
select ok((pg_temp.admin_ms(pg_temp.id('ra1'), 'individual_review', 60) ->> 'ok')::boolean, 'day-60 individual review recorded');
select is(pg_temp.admin_ms(pg_temp.id('ra1'), 'reminder', 8) ->> 'error', 'milestone_already_recorded', 'each milestone is recorded once');
select is(pg_temp.queue(pg_temp.id('a')), array['awaiting_client_approval', 'inactivity_suspension_eligible'],
  'every milestone recorded: only the day-30 eligibility remains');
select is(pg_temp.effects_fingerprint(), (select v from ids where k = 'fp0'),
  'T-LC-18: no milestone approves, charges, publishes, forfeits, cancels or changes a release');
select is((select array_agg(action order by action) from public.audit_events
            where project_id = pg_temp.id('a') and action like 'inactivity.%'),
  array['inactivity.admin_notified_recorded', 'inactivity.courtesy_reminder_recorded', 'inactivity.estimate_suspension_recorded',
        'inactivity.formal_notice_recorded', 'inactivity.individual_review_recorded', 'inactivity.reminder_recorded',
        'inactivity.rescheduling_decision_recorded'], 'every milestone is audited');
select ok(not exists (select 1 from public.audit_events where project_id = pg_temp.id('a') and action like 'inactivity.%'
                       and (summary::text ilike '%Recorded%' or reason is not null)),
  'no audit event carries the milestone summary');

-- The day-30 administrative suspension: the existing approval hold, every 05 §7.2 protection kept.
select ok((pg_temp.hold(pg_temp.id('a')) ->> 'ok')::boolean, 'Admin places the day-30 administrative suspension');
select is(pg_temp.hold(pg_temp.id('a')) ->> 'error', 'hold_active', 'only one active hold per project');
select is((select cardinality(outreach_evidence_ids) from public.approval_holds where project_id = pg_temp.id('a')), 7,
  'the hold cites the recorded milestones as its evidence');
select is((private.project_fulfillment_status(pg_temp.id('a'))).active_fulfillment_holds,
  array['approval_nonresponsive_hold']::public.hold_type[], 'it is a fulfillment hold, never a billing hold');
select is(pg_temp.queue(pg_temp.id('a')), array['awaiting_client_approval', 'blocked_by_hold'],
  'the eligibility item clears once the suspension is placed');
select is(pg_temp.effects_fingerprint(), (select v from ids where k = 'fp0'),
  'OI-45: the suspension approves nothing, charges nothing, publishes nothing and cancels nothing');
select pg_temp.act_as(pg_temp.id('ca'));
select is((select count(*)::int from public.preview_releases where project_id = pg_temp.id('a')), 1,
  'OI-45: the client keeps preview access during the suspension');
select is(public.project_status(pg_temp.id('a')) ->> 'approval_hold', 'Paused: awaiting your preview response',
  'it is shown to the client as a pause, never as a billing status');
select ok((public.approve_preview(pg_temp.id('ra1')) ->> 'ok')::boolean, 'OI-45: the client can still approve');
reset role;
select ok((private.project_fulfillment_status(pg_temp.id('a'))).current_release_approved,
  'an approval made during the suspension is a valid G3 input');
select is(pg_temp.admin_ms(pg_temp.id('ra1'), 'reminder', 8) ->> 'error', 'schedule_stopped',
  'an approval stops the schedule');

-- ---------------------------------------------------------------------------
-- 4. Project B: too early, a revision request stops the schedule, a new release restarts it
-- ---------------------------------------------------------------------------
select is(pg_temp.admin_ms(pg_temp.id('rb1'), 'formal_notice', 14) ->> 'error', 'milestone_too_early',
  'a milestone is refused before its day (day 10 < 14)');
select is(pg_temp.hold(pg_temp.id('b')) ->> 'error', 'suspension_too_early', 'the suspension is refused before day 30');
select ok((pg_temp.admin_ms(pg_temp.id('rb1'), 'courtesy_reminder', 3) ->> 'ok')::boolean, 'day-3 courtesy reminder recorded on B');
select is(pg_temp.queue(pg_temp.id('b')),
  array['approval_outreach_due:admin_notified', 'approval_outreach_due:reminder', 'awaiting_client_approval'],
  'B at day 10: the day-7 items are due');
select pg_temp.act_as(pg_temp.id('cb'));
select ok((public.request_revisions(pg_temp.id('rb1'), 'Please change the header') ->> 'ok')::boolean, 'B''s client requests revisions');
reset role;
select is(pg_temp.queue(pg_temp.id('b')), array['awaiting_client_approval'], 'a revision request stops the schedule');
select is(pg_temp.admin_ms(pg_temp.id('rb1'), 'reminder', 7) ->> 'error', 'schedule_stopped',
  'no milestone is recorded after a client response');
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by, released_at)
values (pg_temp.id('rb2'), pg_temp.id('b'), 2, repeat('1', 40), 'dpl_pwp5b_b2', 'https://preview-b.example.test/2',
        pg_temp.id('admin'), pg_temp.local_at(-3, '23:59'));
select is(pg_temp.queue(pg_temp.id('b')), array['approval_outreach_due:courtesy_reminder', 'awaiting_client_approval'],
  'a new release restarts the schedule (released at 23:59 three local days ago: day 3, under 72 hours)');
select is(pg_temp.admin_ms(pg_temp.id('rb1'), 'reminder', 7) ->> 'error', 'not_current_release',
  'milestones are recorded for the current release only');
select ok((pg_temp.admin_ms(pg_temp.id('rb2'), 'courtesy_reminder', 3) ->> 'ok')::boolean,
  'the restarted schedule counts calendar days, not 24-hour periods');

-- ---------------------------------------------------------------------------
-- 5. A release that existed before the migration keeps the earlier schedule unchanged
-- ---------------------------------------------------------------------------
-- (Test-only: the snapshot row is written as the table owner inside this rolled-back
-- transaction; no API role can write it, section 1.)
insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by, released_at)
values (pg_temp.id('rb3'), pg_temp.id('b'), 3, repeat('2', 40), 'dpl_pwp5b_b3', 'https://preview-b.example.test/3',
        pg_temp.id('admin'), now() - interval '22 days');
insert into private.inactivity_legacy_releases (release_id) values (pg_temp.id('rb3'));
select is(private.inactivity_schedule(pg_temp.id('rb3')), 'v1_day21', 'the snapshot keeps the release on the earlier schedule');
select throws_ok($$update private.inactivity_legacy_releases set recorded_at = now()$$, '42501', null,
  'the snapshot is insert-only (update refused)');
select throws_ok($$delete from private.inactivity_legacy_releases$$, '42501', null,
  'the snapshot is insert-only (delete refused)');
select is(pg_temp.queue(pg_temp.id('b')),
  array['approval_followup_due', 'approval_outreach_due:admin_notified', 'approval_outreach_due:reminder_1',
        'approval_outreach_due:reminder_2', 'awaiting_client_approval'],
  'the earlier-schedule queue at day 22 is unchanged (no revised-schedule item)');
select is(pg_temp.admin_ms(pg_temp.id('rb3'), 'courtesy_reminder', 3) ->> 'error', 'earlier_schedule',
  'revised milestones are refused for an earlier-schedule release');
select is(pg_temp.hold(pg_temp.id('b')) ->> 'error', 'outreach_required',
  'the earlier day-21 hold path is unchanged: it still needs the personal follow-up');
select pg_temp.act_as(pg_temp.id('admin'), 'aal2');
select ok((public.record_outreach(pg_temp.id('rb3'), 'personal_followup', 'phone',
  ((now() - interval '8 days') at time zone 'America/Detroit')::date, 'Called') ->> 'ok')::boolean,
  'the earlier-schedule outreach record still works');
reset role;
select ok((pg_temp.hold(pg_temp.id('b')) ->> 'ok')::boolean, 'and the day-21 hold is placed as before (day 22)');

-- ---------------------------------------------------------------------------
-- 6. Isolation (OD-15 pattern: staff only)
-- ---------------------------------------------------------------------------
create function pg_temp.rows_as(p_uid uuid, p_aal text) returns integer language plpgsql as $$
declare v integer;
begin
  perform pg_temp.act_as(p_uid, p_aal);
  select count(*)::int into v from public.inactivity_milestones;
  reset role;
  return v;
end;
$$;
select is(pg_temp.rows_as(pg_temp.id('admin'), 'aal2'), 9, 'staff read every milestone');
select is(pg_temp.rows_as(pg_temp.id('ca'), 'aal1'), 0, 'client A reads no milestone, even of its own project');
select is(pg_temp.rows_as(pg_temp.id('cb'), 'aal1'), 0, 'client B reads no milestone');
select is(pg_temp.rows_as(pg_temp.id('sales'), 'aal2'), 0, 'Sales reads no milestone');
select is(pg_temp.rows_as(pg_temp.id('admin'), 'aal1'), 0, 'staff at aal1 read nothing (restrictive policy)');
select pg_temp.act_as(pg_temp.id('admin'), 'aal2');
select throws_ok(format($$insert into public.inactivity_milestones (project_id, release_id, milestone, channel, occurred_on,
  summary, recorded_by) values (%L, %L, 'reminder', 'email', current_date, 'x', %L)$$,
  pg_temp.id('b'), pg_temp.id('rb2'), pg_temp.id('admin')), '42501', null, 'staff cannot insert a milestone directly');
select throws_ok($$insert into private.inactivity_legacy_releases (release_id) values (gen_random_uuid())$$, '42501', null,
  'and no API role can write the earlier-schedule snapshot');
reset role;
select throws_ok($$update public.inactivity_milestones set summary = 'changed'$$, '42501', null,
  'milestones are insert-only (even for the table owner)');

select * from finish();
rollback;
