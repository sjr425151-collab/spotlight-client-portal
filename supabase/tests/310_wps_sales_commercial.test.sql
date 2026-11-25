-- WP-S: Sales Representative commercial workflows (03 §4.1, §13; 04 §4; OI-77, OI-78, OI-83,
-- OI-84; A2, A5; AUTH-005 environment-isolation amendment). T-SALES-04 to T-SALES-08,
-- T-SALES-10, T-SALES-13, T-SALES-14, T-SALES-17 to T-SALES-19, T-SALES-21, T-SALES-24,
-- T-SALES-26 to T-SALES-36 (serial parts; the concurrent parts run in the integration suite).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(157);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false)
returns uuid language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform pg_temp.use_session(p_uid, v_sid, p_aal, p_fresh);
  return v_sid;
end;
$$;
-- Re-enters an EXISTING session (the same JWT claims), as a later request of that session.
create function pg_temp.use_session(p_uid uuid, p_sid uuid, p_aal text default 'aal2', p_fresh boolean default false)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', p_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  set local role authenticated;
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
  if p_role is not null then
    insert into public.profiles (id, email, full_name) values (p_id, p_email, 'Synthetic ' || p_email);
    insert into public.staff_roles (user_id, role) values (p_id, p_role);
  end if;
end;
$$;
create temp table ids (k text primary key, v text);
grant select, insert, update on ids to authenticated, service_role;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;
create temp table mark as select coalesce(max(id), 0) as last_id from public.audit_events;
grant select on mark to authenticated, service_role;
create function pg_temp.audits(p_action text) returns integer language sql as $$
  select count(*)::int from public.audit_events where id > (select last_id from mark) and action = p_action
$$;

-- S1 = seeded Sales, S2 = second Sales; client users are created as they are invited.
select pg_temp.new_user('41000000-0000-4000-8000-000000000002', 'sales.b@example.test', 'sales');

-- ===========================================================================
-- T-SALES-04: atomic customer, project, and self-assignment creation, audited
-- ===========================================================================
insert into ids select 's1', pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
insert into ids select 'c1', public.sales_create_customer_project('Alpha Dental LLC', 'Alpha Dental', 'Alpha website');
update ids set v = (v::jsonb ->> 'project_id') where k = 'c1';
reset role;
select isnt(pg_temp.id('c1'), null, 'T-SALES-04: a Sales Representative creates a customer and project');
select is((select b.created_by from public.projects p join public.client_businesses b on b.id = p.client_business_id
  where p.id = pg_temp.id('c1')), '00000000-0000-4000-8000-000000000005'::uuid, 'T-SALES-04: the business is created by the representative');
select is((select created_by from public.projects where id = pg_temp.id('c1')), '00000000-0000-4000-8000-000000000005'::uuid,
  'T-SALES-04: the project is created by the representative');
select is((select count(*)::int from public.project_sales_assignments where project_id = pg_temp.id('c1')
  and sales_user_id = '00000000-0000-4000-8000-000000000005' and assigned_by = '00000000-0000-4000-8000-000000000005' and active), 1,
  'T-SALES-04: the creator is assigned automatically, by itself');
select is((select array_agg(event order by id) from public.project_sales_assignment_history where project_id = pg_temp.id('c1')),
  array['created'], 'T-SALES-04: the assignment history records the creation');
select is((select array_agg(action order by action) from public.audit_events where id > (select last_id from mark)
  and project_id = pg_temp.id('c1') and actor_role = 'sales'),
  array['project.created', 'sales_assignment.created', 'sales.customer_created'],
  'T-SALES-04: project, customer, and assignment audit events are written with the Sales actor');
select is(pg_temp.audits('client_business.created'), 1, 'T-SALES-04: the business creation is audited');

-- ===========================================================================
-- T-SALES-17: atomic creation (duplicate, invalid input, injected failure)
-- ===========================================================================
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.sales_create_customer_project('Alpha Dental LLC', 'Alpha Dental', 'Alpha website') ->> 'existing', 'true',
  'T-SALES-17: a duplicate request returns the existing set');
select is(public.sales_create_customer_project('Beta LLC', 'Beta', repeat('x', 201)) ->> 'error', 'invalid_input',
  'T-SALES-17: invalid input is rejected');
reset role;
select is((select count(*)::int from public.client_businesses where legal_name in ('Alpha Dental LLC', 'Beta LLC')), 1,
  'T-SALES-17: neither the duplicate nor the invalid request created a business');
create function pg_temp.fail_assignment() returns trigger language plpgsql as $$
begin
  raise exception 'injected failure';
end;
$$;
create trigger pgtap_fail_assignment before insert on public.project_sales_assignments
  for each row execute function pg_temp.fail_assignment();
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select throws_ok($$ select public.sales_create_customer_project('Gamma LLC', 'Gamma', 'Gamma site') $$, 'P0001', 'injected failure',
  'T-SALES-17: a failure at the assignment step fails the whole operation');
reset role;
drop trigger pgtap_fail_assignment on public.project_sales_assignments;
select is((select count(*)::int from public.client_businesses where legal_name = 'Gamma LLC')
  + (select count(*)::int from public.projects where name = 'Gamma site'), 0,
  'T-SALES-17: the injected failure left no customer and no project');

-- S2 and its own customer
insert into ids select 's2', pg_temp.act_as('41000000-0000-4000-8000-000000000002', 'aal2', true);
insert into ids select 'c2', public.sales_create_customer_project('Bravo Roofing LLC', 'Bravo', 'Bravo website') ->> 'project_id';
reset role;

-- ===========================================================================
-- T-SALES-05 / T-SALES-21: isolation between representatives and from unassigned projects
-- ===========================================================================
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is((select array_agg(c ->> 'project_id') from jsonb_array_elements(public.sales_list_customers() -> 'customers') c),
  array[pg_temp.id('c1')::text], 'T-SALES-05: the customer list holds only the own active assignment');
select is(public.sales_project_progress(pg_temp.id('c2')) ->> 'error', 'not_found',
  'T-SALES-21: representative A cannot read representative B''s customer');
select is(public.sales_project_progress('20000000-0000-4000-8000-0000000000a0') ->> 'error', 'not_found',
  'T-SALES-05: an unassigned project is indistinguishable from a missing one');
select is(public.create_invitation('client', 'x.client@example.test', 'X', pg_temp.id('c2')) ->> 'error', 'forbidden',
  'T-SALES-05: no invitation to another representative''s project');
select is(public.issue_order_summary(pg_temp.id('c2'), 'essential') ->> 'error', 'forbidden',
  'T-SALES-19: no order summary for an unassigned project');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential') ->> 'error', 'forbidden',
  'T-SALES-19: no order summary for a project of another customer');
reset role;

-- ===========================================================================
-- T-SALES-07: client invitations to the assigned project only
-- ===========================================================================
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'inv1', public.create_invitation('client', 'alpha.owner@example.test', 'Alpha Owner', pg_temp.id('c1'));
update ids set v = v::jsonb ->> 'invitation_id' where k = 'inv1';
reset role;
select isnt(pg_temp.id('inv1'), null, 'T-SALES-07: a Sales Representative invites a client contact to its project');
select is((select created_by from public.invitations where id = pg_temp.id('inv1')), '00000000-0000-4000-8000-000000000005'::uuid,
  'T-SALES-07: the invitation is attributed to the representative');
select is((select actor_role from public.audit_events where id > (select last_id from mark) and action = 'invitation.created'
  and target_id = pg_temp.id('inv1')::text), 'sales', 'T-SALES-07: invitation.created keeps its name, with the Sales actor role');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.create_invitation('client', 'admin@example.test', 'Admin', pg_temp.id('c1')) ->> 'error', 'invalid_recipient',
  'T-SALES-07: never to the address of a user with an active staff role');
reset role;
select is(pg_temp.audits('invitation.create_rejected'), 1, 'T-SALES-07: the rejected recipient is audited');

-- ===========================================================================
-- T-SALES-24: client-role separation
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.create_invitation('client', 'sales.b@example.test', 'Sales B', '20000000-0000-4000-8000-0000000000a0') ->> 'error',
  'invalid_recipient', 'T-SALES-24: the Owner cannot address a client invitation to a Sales Representative');
reset role;
select is(pg_temp.audits('invitation.create_rejected'), 2, 'T-SALES-24: the attempt is audited');
-- A client invitation that was pending before its addressee became a Sales Representative.
select pg_temp.new_user('41000000-0000-4000-8000-000000000003', 'late.sales@example.test', 'admin');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'late', public.create_invitation('client', 'late.sales@example.test', 'Late', '20000000-0000-4000-8000-0000000000a0');
select is(public.set_staff_role('41000000-0000-4000-8000-000000000003', 'sales', 'now sales') ->> 'ok', 'true',
  'setup: the addressee becomes a Sales Representative');
reset role;
select pg_temp.act_as('41000000-0000-4000-8000-000000000003', 'aal2', true);
select is(public.accept_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'late'),
  (select v::jsonb ->> 'token' from ids where k = 'late')) ->> 'error', 'invalid',
  'T-SALES-24: a Sales Representative cannot accept a client invitation by link');
select is(public.accept_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'late'), null) ->> 'error', 'invalid',
  'T-SALES-24: a Sales Representative cannot accept a client invitation in the portal');
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and action = 'invitation.accept_failed' and summary ->> 'reason' = 'sales_role'), 2,
  'T-SALES-24: both refused acceptances are audited with the sales_role reason');
select is((select count(*)::int from public.project_memberships where user_id = '41000000-0000-4000-8000-000000000003'), 0,
  'T-SALES-24: no membership was created');
-- A Sales staff invitation accepted by a user with an active membership.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'ca_sales', public.create_invitation('staff', 'client.a@example.test', 'Client A', null, 'sales') ->> 'invitation_id';
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.accept_invitation(pg_temp.id('ca_sales'), null) ->> 'error', 'invalid',
  'T-SALES-24: a client with an active membership cannot accept a Sales staff invitation');
reset role;
select is(private.staff_role_of('00000000-0000-4000-8000-0000000000a1'), null, 'T-SALES-24: the client gained no staff role');
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and action = 'invitation.accept_failed' and summary ->> 'reason' = 'client_membership'), 1,
  'T-SALES-24: the refused staff acceptance is audited');
-- The Owner cannot set the Sales role on a user with an active membership.
select pg_temp.new_user('41000000-0000-4000-8000-000000000004', 'member.admin@example.test', 'admin');
insert into public.project_memberships (project_id, user_id) values ('20000000-0000-4000-8000-0000000000b0', '41000000-0000-4000-8000-000000000004');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.set_staff_role('41000000-0000-4000-8000-000000000004', 'sales', 'x') ->> 'error', 'client_membership',
  'T-SALES-24: the Owner cannot give the Sales role to a user with an active membership');
reset role;
select is(pg_temp.audits('staff_role.sales_assignment_rejected'), 1, 'T-SALES-24: the rejected role change is audited');
select is(private.staff_role_of('41000000-0000-4000-8000-000000000004'), 'admin'::public.staff_role, 'T-SALES-24: the role is unchanged');

-- ===========================================================================
-- T-SALES-06 / T-SALES-31: package key only; derived scope; empty notes; fail closed
-- ===========================================================================
select is((select array_agg(a order by o) from unnest((select proargnames from pg_proc
  where oid = 'public.issue_order_summary(uuid, text, jsonb, text, text)'::regprocedure)) with ordinality x(a, o)),
  array['p_project_id', 'p_package_key', 'p_scope_items', 'p_project_notes', 'p_change_reason'],
  'T-SALES-06: the RPC accepts no amount, price, quantity, discount, or term (signature unchanged)');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('c1'), 'essential', '["Ten free pages"]'::jsonb) ->> 'error', 'scope_not_allowed',
  'T-SALES-19: a supplied scope item is rejected');
select is(public.issue_order_summary(pg_temp.id('c1'), 'essential', '[]'::jsonb, 'Includes SEO') ->> 'error', 'notes_not_allowed',
  'T-SALES-19: a supplied project note is rejected');
select is(public.issue_order_summary(pg_temp.id('c1'), 'essential', '[]'::jsonb, '') ->> 'error', 'notes_not_allowed',
  'T-SALES-19: even an empty project note is rejected');
insert into ids select 'os1', public.issue_order_summary(pg_temp.id('c1'), 'essential', '[]'::jsonb, null, 'Initial order') ->> 'order_summary_id';
reset role;
select is((select array_agg(summary ->> 'reason' order by id) from public.audit_events where id > (select last_id from mark)
  and action = 'sales.order_summary_rejected'), array['scope_input', 'notes_input', 'notes_input'],
  'T-SALES-31: each rejected input is audited with its reason kind only');
select isnt(pg_temp.id('os1'), null, 'T-SALES-06: the representative issues the order summary by package key');
select is((select scope_items from public.order_summaries where id = pg_temp.id('os1')),
  (select jsonb_agg(item_text order by position) from private.billing_package_scope where package_key = 'essential' and scope_version = 1),
  'T-SALES-31: the scope items equal the current package scope definition');
select is((select project_notes from public.order_summaries where id = pg_temp.id('os1')), null,
  'T-SALES-31: the project notes are empty');
select is((select (package_total_cents, deposit_cents, balance_cents, maintenance_monthly_cents)::text
  from public.order_summaries where id = pg_temp.id('os1')), '(80000,16000,64000,9900)',
  'T-SALES-06: pricing comes from the catalog: one 20% deposit plus $99/month maintenance');
select is((select issued_by from public.order_summaries where id = pg_temp.id('os1')), '00000000-0000-4000-8000-000000000005'::uuid,
  'T-SALES-06: issued_by records the representative');
select is((select snapshot_sha256 from public.order_summaries where id = pg_temp.id('os1')),
  (select private.sha256_hex(private.order_summary_snapshot(o)::text) from public.order_summaries o where o.id = pg_temp.id('os1')),
  'T-SALES-31: the snapshot hash covers the derived scope');
select is((select summary ->> 'scope_version' from public.audit_events where id > (select last_id from mark)
  and action = 'order_summary.issued' and target_id = pg_temp.id('os1')::text and actor_role = 'sales'), '1',
  'T-SALES-31: the scope version is recorded in the order_summary.issued audit metadata');
-- Missing definition fails closed.
delete from private.billing_package_scope where package_key = 'advanced';
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('c1'), 'advanced', '[]'::jsonb, null, 'Upgrade') ->> 'error', 'scope_definition_missing',
  'T-SALES-31: a package without a scope definition fails closed');
reset role;
select is(pg_temp.audits('sales.order_summary_rejected'), 4, 'T-SALES-31: the fail-closed rejection is audited');
-- A5: a new scope version never alters an issued summary.
create temp table os1_before as select scope_items, snapshot_sha256 from public.order_summaries where id = pg_temp.id('os1');
insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture) values
  ('essential', 2, 1, 'TEST FIXTURE — NOT A DELIVERABLE (essential v2 item 1)', true),
  ('essential', 2, 2, 'TEST FIXTURE — NOT A DELIVERABLE (essential v2 item 2)', true);
select is((select (scope_items, snapshot_sha256)::text from public.order_summaries where id = pg_temp.id('os1')),
  (select (scope_items, snapshot_sha256)::text from os1_before),
  'T-SALES-31 (A5): a later scope version leaves the issued snapshot and hash unchanged');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'os2', public.issue_order_summary(pg_temp.id('c1'), 'essential', '[]'::jsonb, null, 'Refresh scope') ->> 'order_summary_id';
reset role;
select is((select scope_items from public.order_summaries where id = pg_temp.id('os2')),
  '["TEST FIXTURE — NOT A DELIVERABLE (essential v2 item 1)", "TEST FIXTURE — NOT A DELIVERABLE (essential v2 item 2)"]'::jsonb,
  'T-SALES-31: a new Sales summary before acceptance copies the new version');
select is((select status::text from public.order_summaries where id = pg_temp.id('os1')), 'superseded',
  'T-SALES-31: the earlier summary is superseded, not changed');
select is((select summary ->> 'scope_version' from public.audit_events where id > (select last_id from mark)
  and action = 'order_summary.issued' and target_id = pg_temp.id('os2')::text), '2', 'T-SALES-31: the new version is recorded');
-- Owner and Admin keep scope and notes (T-SALES-31, T-SALES-13).
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.issue_order_summary('20000000-0000-4000-8000-0000000000b0', 'professional', '["Custom scope"]'::jsonb, 'Staff note') ->> 'ok',
  'true', 'T-SALES-31: an Admin still enters scope items and project notes');
reset role;
select is((select (scope_items, project_notes)::text from public.order_summaries
  where project_id = '20000000-0000-4000-8000-0000000000b0' and status = 'presented'), '("[""Custom scope""]","Staff note")',
  'T-SALES-31: the Admin''s scope and note are stored as supplied');

-- ===========================================================================
-- T-SALES-30 / T-SALES-08 / T-SALES-34: commercial progress view
-- ===========================================================================
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'prog', public.sales_project_progress(pg_temp.id('c1'))::text;
reset role;
select is((select (v::jsonb #>> '{order_summary,package_total_cents}') || '/' || (v::jsonb #>> '{order_summary,deposit_cents}')
  || '/' || (v::jsonb #>> '{order_summary,balance_cents}') from ids where k = 'prog'), '80000/16000/64000',
  'T-SALES-30: the assigned representative sees the agreed total, deposit, and balance');
select is((select array_agg(x order by x) from ids, jsonb_object_keys(ids.v::jsonb -> 'progress') x where ids.k = 'prog'),
  array['agreement_effective', 'agreement_state', 'billing_operational_hold', 'deposit_requirement_satisfied',
        'final_balance_requirement_satisfied', 'intake_state', 'preview_approved', 'publication_eligible'],
  'T-SALES-08: progress holds derived states only');
select is((select v ~* '(ledger|invoice|refund|dispute|paid_|amount_paid|payment_intent|token|failed_attempts|stripe)' from ids where k = 'prog'),
  false, 'T-SALES-08: no payment, ledger, refund, dispute, token, or attempt data in the progress view');
select is((select array_agg(x order by x) from ids, jsonb_array_elements(ids.v::jsonb -> 'pending_invitations') i, jsonb_object_keys(i) x
  where ids.k = 'prog'), array['email', 'expires_at', 'full_name', 'id', 'sent_at', 'status'],
  'T-SALES-34: pending invitations carry only the minimum fields');
select is((select jsonb_array_length(v::jsonb -> 'pending_invitations') from ids where k = 'prog'), 1,
  'T-SALES-34: exactly the assigned project''s pending client invitation');
select pg_temp.use_session('41000000-0000-4000-8000-000000000002', pg_temp.id('s2'), 'aal2', true);
select is(public.sales_project_progress(pg_temp.id('c1')) ->> 'error', 'not_found',
  'T-SALES-30: an unassigned representative sees nothing');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select package_total_cents from public.order_summaries where id = pg_temp.id('os2')), 80000,
  'T-SALES-30: an Admin sees the agreed total');
select throws_ok($$ select * from private.billing_package_scope $$, '42501', null, 'An Admin has no access to the scope table either');
reset role;

-- ===========================================================================
-- T-SALES-33: resend is revoke then reissue (Sales; Owner and Admin below)
-- ===========================================================================
-- The plaintext token of inv1 is not stored; issue a fresh invitation to know its token.
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'inv2', public.create_invitation('client', 'alpha.owner@example.test', 'Alpha Owner', pg_temp.id('c1'));
select is(public.revoke_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv2')) ->> 'ok', 'true',
  'T-SALES-33: step 1, the representative revokes the pending invitation');
insert into ids select 'inv3', public.create_invitation('client', 'alpha.owner@example.test', 'Alpha Owner', pg_temp.id('c1'));
reset role;
select isnt((select v::jsonb ->> 'token' from ids where k = 'inv3'), (select v::jsonb ->> 'token' from ids where k = 'inv2'),
  'T-SALES-33: step 2, the new invitation has a new token');
select cmp_ok((select expires_at from public.invitations where id = (select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv3')),
  '>=', (select expires_at from public.invitations where id = (select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv2')),
  'T-SALES-33: the new invitation has a new expiry');
select pg_temp.as_service();
select is(public.check_invitation_link((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv2'),
  (select v::jsonb ->> 'token' from ids where k = 'inv2')) ->> 'ok', 'false', 'T-SALES-33: the previous link no longer checks');
select is(public.check_invitation_link((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv3'),
  (select v::jsonb ->> 'token' from ids where k = 'inv3')) ->> 'ok', 'true', 'T-SALES-33: the new link checks');
reset role;
select is((select count(*)::int from public.invitations where email = 'alpha.owner@example.test' and status = 'pending'), 1,
  'T-SALES-33: exactly one usable invitation per address');
select cmp_ok((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and action in ('invitation.revoked', 'invitation.created') and actor_role = 'sales'), '>=', 3,
  'T-SALES-33: both steps are audited with the Sales actor');
-- An issuance failure after the revocation leaves no usable invitation.
insert into private.rate_limits (bucket, window_start, count)
values ('sales-invite:00000000-0000-4000-8000-000000000005',
  to_timestamp(floor(extract(epoch from now()) / 3600) * 3600), 29)
on conflict (bucket, window_start) do update set count = 29;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.revoke_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv3')) ->> 'ok', 'true',
  'T-SALES-33: the revocation uses the last allowed operation');
select is(public.create_invitation('client', 'alpha.owner@example.test', 'Alpha Owner', pg_temp.id('c1')) ->> 'error', 'rate_limited',
  'T-SALES-29: the reissue beyond the per-user limit returns the standard failure');
reset role;
select is((select count(*)::int from public.invitations where email = 'alpha.owner@example.test' and status = 'pending'), 0,
  'T-SALES-33: after a failed reissue no usable invitation remains (the old one stays revoked)');
select is(pg_temp.audits('sales.rate_limited'), 1, 'T-SALES-29: the rate-limited invitation operation is audited');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.revoke_invitation(pg_temp.id('inv1')) ->> 'error', 'not_found',
  'T-SALES-29: a limited revoke is refused too (inv1 was already revoked by the resend)');
reset role;
delete from private.rate_limits where bucket = 'sales-invite:00000000-0000-4000-8000-000000000005';
-- The other representative's bucket was unaffected throughout.
select pg_temp.use_session('41000000-0000-4000-8000-000000000002', pg_temp.id('s2'), 'aal2', true);
insert into ids select 'inv_b', public.create_invitation('client', 'bravo.owner@example.test', 'Bravo Owner', pg_temp.id('c2'));
select is((select v::jsonb ->> 'ok' from ids where k = 'inv_b'), 'true', 'T-SALES-29: another representative''s bucket is unaffected');
select is(public.revoke_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv3')) ->> 'error', 'not_found',
  'T-SALES-33: an unassigned representative cannot revoke');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.revoke_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv_b')) ->> 'error', 'not_found',
  'T-SALES-33: representative A cannot revoke representative B''s invitation');
-- Re-invite for the acceptance tests below.
insert into ids select 'inv4', public.create_invitation('client', 'alpha.owner@example.test', 'Alpha Owner', pg_temp.id('c1'));
reset role;

-- ===========================================================================
-- T-SALES-29: customer-creation rate limit, per user
-- ===========================================================================
create function pg_temp.burst(p_n integer) returns text[] language plpgsql as $$
declare
  v text[] := '{}';
begin
  for i in 1..p_n loop
    v := v || coalesce(public.sales_create_customer_project('Burst ' || i || ' LLC', null, 'Burst site') ->> 'error', 'ok');
  end loop;
  return v;
end;
$$;
grant execute on function pg_temp.burst(integer) to authenticated;
select pg_temp.use_session('41000000-0000-4000-8000-000000000002', pg_temp.id('s2'), 'aal2', true);
select is((pg_temp.burst(10))[10], 'rate_limited', 'T-SALES-29: customer creation beyond 10 per hour is rate limited');
reset role;
select is(pg_temp.audits('sales.rate_limited'), 2, 'T-SALES-29: the rate-limited creation is audited');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'c3', public.sales_create_customer_project('Charlie Spa LLC', 'Charlie', 'Charlie website') ->> 'project_id';
reset role;
select isnt(pg_temp.id('c3'), null, 'T-SALES-29: representative A can still create (separate bucket)');

-- ===========================================================================
-- T-SALES-32 (serial): no Sales replacement after acceptance; Owner path unchanged
-- ===========================================================================
select pg_temp.new_user('41000000-0000-4000-8000-0000000000c1', 'alpha.owner@example.test');
select pg_temp.act_as('41000000-0000-4000-8000-0000000000c1');
select is(public.accept_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv4'),
  (select v::jsonb ->> 'token' from ids where k = 'inv4')) ->> 'ok', 'true', 'setup: the client accepts the representative''s invitation');
insert into ids select 'acc', public.accept_agreement(pg_temp.id('os2'), true, true, 'Alex Alpha', 'Alpha Dental LLC', 'Owner', true) ->> 'acceptance_id';
reset role;
select isnt(pg_temp.id('acc'), null, 'setup: the client accepts the Sales-issued order summary');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('c1'), 'essential', '[]'::jsonb, null, 'Change after acceptance') ->> 'error',
  'replacement_after_acceptance', 'T-SALES-32: a Sales replacement by direct RPC after acceptance is rejected');
reset role;
select is((select count(*)::int from public.audit_events where id > (select last_id from mark)
  and action = 'sales.order_summary_rejected' and summary ->> 'reason' = 'after_acceptance'), 1, 'T-SALES-32: the rejection is audited');
select is((select status::text from public.order_summaries where id = pg_temp.id('os2')), 'presented',
  'T-SALES-32: the accepted summary is untouched');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'os3', public.issue_order_summary(pg_temp.id('c1'), 'essential', '["Owner scope"]'::jsonb, null, 'Owner correction') ->> 'order_summary_id';
reset role;
select isnt(pg_temp.id('os3'), null, 'T-SALES-32: the Owner replacement workflow is unchanged');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('c1'), 'essential', '[]'::jsonb, null, 'Again') ->> 'error',
  'replacement_after_acceptance', 'T-SALES-32: any earlier acceptance on the project keeps blocking Sales');
reset role;

-- ===========================================================================
-- T-SALES-24 (functions): client-only paths deny a Sales Representative even with a
-- membership row inserted directly by a fixture.
-- ===========================================================================
insert into public.project_memberships (project_id, user_id) values (pg_temp.id('c3'), '00000000-0000-4000-8000-000000000005');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
insert into ids select 'os_c3', public.issue_order_summary(pg_temp.id('c3'), 'essential') ->> 'order_summary_id';
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.accept_agreement(pg_temp.id('os_c3'), true, true, 'Sam Sales', 'Charlie Spa LLC', 'Rep', true) ->> 'ok', 'false',
  'T-SALES-24: agreement acceptance denies a Sales Representative holding a fixture membership');
select is(public.begin_initial_checkout(pg_temp.id('c3')) ->> 'ok', 'false', 'T-SALES-24: Checkout start is denied');
select is(public.revoke_payment_authorization(pg_temp.id('c3'), 'x') ->> 'ok', 'false', 'T-SALES-24: payment-authorization revocation is denied');
select is(public.submit_cancellation_request(pg_temp.id('c3')) ->> 'ok', 'false', 'T-SALES-24: cancellation request is denied');
select is(public.save_intake_draft(pg_temp.id('c3'), '{}'::jsonb) ->> 'ok', 'false', 'T-SALES-24: intake is denied');
select is(public.project_billing_status(pg_temp.id('c3')) ->> 'ok', 'false', 'T-SALES-24: the client billing status is denied');
reset role;
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
reset role;
select is(private.wpc_is_client_member(pg_temp.id('c3')), false,
  'T-SALES-24: the WP-C client check (which gates preview approval) denies the representative');
select is((select count(*)::int from public.agreement_acceptances where project_id = pg_temp.id('c3')), 0,
  'T-SALES-24: no acceptance was recorded');
-- Escalated (proposed issue WPS-P1, ID to be allocated by Main), not asserted: Phase 2 and WP-B READ policies use
-- private.is_project_member(), which AUTH-005 does not allow WP-S to change, so a membership
-- row inserted directly by the migration owner exposes those rows (projects,
-- client_businesses, the own membership, and WP-B rows keyed on is_project_member). No API
-- path can create such a membership for a Sales Representative (proven above). Reported as
-- a diagnostic only, so it is neither hidden nor counted as a pass.
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select diag('WPS-P1: rows readable by a Sales Representative holding a fixture membership: projects='
  || (select count(*) from public.projects) || ', client_businesses=' || (select count(*) from public.client_businesses)
  || ', order_summaries=' || (select count(*) from public.order_summaries));
reset role;
update public.project_memberships set status = 'revoked', revoked_at = now()
 where user_id = '00000000-0000-4000-8000-000000000005';

-- ===========================================================================
-- T-SALES-10 / T-SALES-28 / T-SALES-27 / T-SALES-35 / T-SALES-26 / T-SALES-14 / T-SALES-18
-- ===========================================================================
-- Project c3: S1 issues the summary (replace the Owner's) and invites a client; then the
-- Owner ends S1's assignment while S1's earlier session is still valid.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.issue_order_summary(pg_temp.id('c3'), 'signature', '["Owner scope"]'::jsonb, null, 'Switch package') ->> 'ok', 'true',
  'setup: an Owner summary on c3');
reset role;
-- Owner replaced; set up a fresh Sales summary on a new project c4 instead (no acceptance there).
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'c4', public.sales_create_customer_project('Delta Clinic LLC', 'Delta', 'Delta website') ->> 'project_id';
insert into ids select 'os4', public.issue_order_summary(pg_temp.id('c4'), 'professional') ->> 'order_summary_id';
insert into ids select 'inv5', public.create_invitation('client', 'delta.owner@example.test', 'Delta Owner', pg_temp.id('c4'));
reset role;
select isnt(pg_temp.id('os4'), null, 'setup: a Sales-issued summary on c4');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.assign_sales_representative(pg_temp.id('c4'), '41000000-0000-4000-8000-000000000002', 'Territory change') ->> 'ok', 'true',
  'T-SALES-10: the Owner reassigns the project');
insert into ids select 'asg_c1', (select id::text from public.project_sales_assignments where project_id = pg_temp.id('c1') and active);
select is(public.end_sales_assignment(pg_temp.id('asg_c1'), 'Left the account') ->> 'ok', 'true',
  'T-SALES-28: the Owner ends an assignment');
reset role;
select is(pg_temp.audits('sales_assignment.reassigned'), 1, 'T-SALES-10: the reassignment is audited');
select is(pg_temp.audits('sales_assignment.ended'), 1, 'T-SALES-28: the end is audited');
select is((select array_agg(event || ':' || right(sales_user_id::text, 4) order by id) from public.project_sales_assignment_history
  where project_id = pg_temp.id('c4')), array['created:0005', 'ended:0005', 'created:0002'],
  'T-SALES-28: the append-only history keeps every step');
select is((select issued_by from public.order_summaries where id = pg_temp.id('os4')), '00000000-0000-4000-8000-000000000005'::uuid,
  'T-SALES-10: reassignment does not change issued_by');
select is((select signer_user_id from public.agreement_acceptances where id = pg_temp.id('acc')), '41000000-0000-4000-8000-0000000000c1'::uuid,
  'T-SALES-10: nor the acceptance actor');
-- The former representative's EXISTING session (authenticated before the change):
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is((select array_agg(c ->> 'project_id' order by c ->> 'project_id') from jsonb_array_elements(public.sales_list_customers() -> 'customers') c),
  (select array_agg(x order by x) from unnest(array[pg_temp.id('c3')::text]) x),
  'T-SALES-28: ended and reassigned projects disappear from the former representative''s list');
select is(public.sales_project_progress(pg_temp.id('c4')) ->> 'error', 'not_found', 'T-SALES-26: progress is denied on the next call');
select is(public.sales_project_progress(pg_temp.id('c1')) ->> 'error', 'not_found', 'T-SALES-26: also on the ended assignment');
select is(public.revoke_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv5')) ->> 'error', 'not_found',
  'T-SALES-27: the former representative cannot revoke its earlier invitation');
select is(public.create_invitation('client', 'delta.owner@example.test', 'Delta Owner', pg_temp.id('c4')) ->> 'error', 'forbidden',
  'T-SALES-35: nor reissue it');
select is(public.issue_order_summary(pg_temp.id('c4'), 'professional', '[]'::jsonb, null, 'Replace') ->> 'error', 'forbidden',
  'T-SALES-35: nor replace its order summary');
select is((select count(*)::int from public.project_sales_assignments where not active), 0,
  'T-SALES-28: ended assignments are hidden from the former representative');
reset role;
select is((select status::text from public.invitations where id = (select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv5')),
  'pending', 'T-SALES-27: the invitation stays pending');
-- Owner and Admin keep visibility and management.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select count(*)::int from public.invitations where project_id = pg_temp.id('c4') and status = 'pending'), 1,
  'T-SALES-27: an Admin lists the pending invitation');
select is((select count(*)::int from public.project_sales_assignment_history where project_id = pg_temp.id('c4')), 3,
  'T-SALES-28: an Admin reads the history');
reset role;
-- The client accepts the representative's invitation and order summary after the assignment ended.
select pg_temp.new_user('41000000-0000-4000-8000-0000000000d1', 'delta.owner@example.test');
select pg_temp.act_as('41000000-0000-4000-8000-0000000000d1');
select is(public.accept_invitation((select (v::jsonb ->> 'invitation_id')::uuid from ids where k = 'inv5'),
  (select v::jsonb ->> 'token' from ids where k = 'inv5')) ->> 'ok', 'true', 'T-SALES-27: the invitation is still acceptable');
select is(public.accept_agreement(pg_temp.id('os4'), true, true, 'Dana Delta', 'Delta Clinic LLC', 'Owner', true) ->> 'ok', 'true',
  'T-SALES-35: the Sales-issued order summary is still acceptable');
reset role;
select is((select issued_by from public.order_summaries where id = pg_temp.id('os4')), '00000000-0000-4000-8000-000000000005'::uuid,
  'T-SALES-35: issued_by is unchanged');
-- T-SALES-14 / T-SALES-18: revoking the role ends access in the same session immediately.
select pg_temp.use_session('41000000-0000-4000-8000-000000000002', pg_temp.id('s2'), 'aal2', true);
select is(public.sales_project_progress(pg_temp.id('c4')) ->> 'ok', 'true', 'setup: the new representative sees c4');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.revoke_staff('41000000-0000-4000-8000-000000000002', 'Left the company') ->> 'ok', 'true', 'setup: the Owner revokes the Sales role');
reset role;
select pg_temp.use_session('41000000-0000-4000-8000-000000000002', pg_temp.id('s2'), 'aal2', true);
select is(public.sales_project_progress(pg_temp.id('c4')) ->> 'error', 'not_found',
  'T-SALES-18: the same session is denied immediately after the role is revoked');
select is(public.sales_list_customers() ->> 'error', 'forbidden', 'T-SALES-14: every Sales function denies it');
reset role;
-- T-SALES-26: no Sales decision reads a JWT claim beyond sub, session_id, aal, amr.
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('is_sales', 'sales_assigned', 'sales_create_customer_project',
    'sales_list_customers', 'sales_project_progress', 'assign_sales_representative', 'end_sales_assignment')
    and p.prosrc ~ 'auth\.jwt'), 0, 'T-SALES-26: the Sales functions read no JWT claim directly (only through the Phase 2 helpers)');
select is((select count(*)::int from public.project_sales_assignment_history), (select count(*)::int from public.project_sales_assignment_history),
  'T-SALES-28: history count is stable');
select throws_ok($$ update public.project_sales_assignment_history set reason = 'x' $$, '42501', null,
  'T-SALES-28: history rows are immutable');

-- ===========================================================================
-- T-SALES-13: Owner and Admin perform every §4.1 capability with their own accounts
-- ===========================================================================
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is(public.create_invitation('client', 'b.second@example.test', 'B Second', '20000000-0000-4000-8000-0000000000b0') ->> 'ok', 'true',
  'T-SALES-13: an Admin invites a client to any project');
select is(public.sales_project_progress('20000000-0000-4000-8000-0000000000b0') ->> 'ok', 'true',
  'T-SALES-13: an Admin reads commercial progress for any project');
select is(public.assign_sales_representative('20000000-0000-4000-8000-0000000000b0', '00000000-0000-4000-8000-000000000005') ->> 'ok', 'true',
  'T-SALES-13: an Admin assigns a representative');
select is(public.sales_create_customer_project('Admin LLC', 'Admin', 'Admin site') ->> 'error', 'forbidden',
  'Staff create customers through their own path, not the Sales function');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
select is(public.revoke_invitation((select id from public.invitations where email = 'b.second@example.test' and status = 'pending')) ->> 'ok',
  'true', 'T-SALES-33: Owner resend step 1 (revoke)');
select is(public.create_invitation('client', 'b.second@example.test', 'B Second', '20000000-0000-4000-8000-0000000000b0') ->> 'ok', 'true',
  'T-SALES-33: Owner resend step 2 (reissue)');
select is(public.assign_sales_representative(pg_temp.id('c1'), '41000000-0000-4000-8000-000000000002') ->> 'error', 'not_sales_representative',
  'Only an active Sales Representative can be assigned');
reset role;

-- ===========================================================================
-- T-SALES-36: fixture isolation with the environment allowlist
-- ===========================================================================
select throws_ok($$ insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  values ('prestige', 9, 1, 'Unlabeled item', true) $$, '23514', null, 'T-SALES-36: a fixture row without the label is rejected');
select throws_ok($$ insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  values ('prestige', 9, 1, 'TEST FIXTURE — NOT A DELIVERABLE (unflagged)', false) $$, '23514', null,
  'T-SALES-36: an unflagged row carrying the label is rejected');
select throws_ok($$ update private.billing_package_scope set is_test_fixture = false where package_key = 'prestige' $$, '23514', null,
  'T-SALES-36: clearing the flag on a labeled row is rejected (update)');
select throws_ok($$ update private.billing_package_scope set item_text = 'Relabeled' where package_key = 'prestige' and position = 1 $$, '23514', null,
  'T-SALES-36: removing the label from a fixture row is rejected (update)');
create function pg_temp.scope_rows(p_key text) returns integer language sql as $$ select count(*)::int from private.current_package_scope(p_key) $$;
-- staging
update private.environment_settings set app_env = 'staging';
select is(private.app_environment(), 'staging', 'setup: classified staging');
select throws_ok($$ insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  values ('prestige', 9, 1, 'TEST FIXTURE — NOT A DELIVERABLE (staging)', true) $$, '42501', null,
  'T-SALES-36: a fixture row is rejected under staging');
select is(pg_temp.scope_rows('prestige'), 0, 'T-SALES-36: fixtures inserted under development are not returned under staging');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
insert into ids select 'c5', public.sales_create_customer_project('Echo LLC', 'Echo', 'Echo website') ->> 'project_id';
select is(public.issue_order_summary(pg_temp.id('c5'), 'prestige') ->> 'error', 'scope_definition_missing',
  'T-SALES-36: Sales issuance fails closed under staging');
reset role;
-- preview
update private.environment_settings set app_env = 'preview';
select throws_ok($$ insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  values ('prestige', 9, 1, 'TEST FIXTURE — NOT A DELIVERABLE (preview)', true) $$, '42501', null,
  'T-SALES-36: a fixture row is rejected under preview');
select is(pg_temp.scope_rows('prestige'), 0, 'T-SALES-36: no fixture is returned under preview');
-- missing classification (read as production)
delete from private.environment_settings;
select is(private.app_environment(), 'production', 'setup: no classification reads as production');
select throws_ok($$ insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  values ('prestige', 9, 1, 'TEST FIXTURE — NOT A DELIVERABLE (prod)', true) $$, '42501', null,
  'T-SALES-36: a fixture row is rejected when the classification is missing');
select is(pg_temp.scope_rows('prestige'), 0, 'T-SALES-36: no fixture is returned when the classification is missing');
select is(pg_temp.scope_rows('essential'), 0, 'T-SALES-36: not even the newest fixture version');
select pg_temp.use_session('00000000-0000-4000-8000-000000000005', pg_temp.id('s1'), 'aal2', true);
select is(public.issue_order_summary(pg_temp.id('c5'), 'essential') ->> 'error', 'scope_definition_missing',
  'T-SALES-36: Sales issuance fails closed when the classification is missing');
reset role;
-- A non-fixture row still resolves anywhere (synthetic, inside this rolled-back transaction).
insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
values ('signature', 7, 1, 'PGTAP SYNTHETIC NON-FIXTURE ROW (rolled back)', false);
select is(pg_temp.scope_rows('signature'), 1, 'T-SALES-36: non-fixture rows are not affected by the allowlist');
delete from private.billing_package_scope where scope_version = 7;
-- development and test
insert into private.environment_settings (app_env) values ('test');
select is(pg_temp.scope_rows('prestige'), 3, 'T-SALES-36: under test, fixtures resolve');
select lives_ok($$ insert into private.billing_package_scope (package_key, scope_version, position, item_text, is_test_fixture)
  values ('prestige', 9, 1, 'TEST FIXTURE — NOT A DELIVERABLE (test)', true) $$, 'T-SALES-36: under test, a fixture inserts');
update private.environment_settings set app_env = 'development';
select is(pg_temp.scope_rows('prestige'), 1, 'T-SALES-36: under development, the newest fixture version resolves');
-- API roles cannot read or write the classification.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select throws_ok($$ select * from private.environment_settings $$, '42501', null, 'T-SALES-36: authenticated cannot read the classification');
select throws_ok($$ update private.environment_settings set app_env = 'test' $$, '42501', null, 'T-SALES-36: authenticated cannot write it');
reset role;
select pg_temp.as_service();
select throws_ok($$ select * from private.environment_settings $$, '42501', null, 'T-SALES-36: service_role cannot read the classification');
select throws_ok($$ update private.environment_settings set app_env = 'test' $$, '42501', null, 'T-SALES-36: service_role cannot write it');
select throws_ok($$ select * from private.billing_package_scope $$, '42501', null, 'T-SALES-36: service_role cannot read scope definitions');
reset role;

select * from finish();
rollback;
