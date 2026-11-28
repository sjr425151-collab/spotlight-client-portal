-- WP-C (AUTH-013, OI-113): authoritative approval identification in
-- private.project_fulfillment_status (migration 20261127110000).
--
-- current_release_approval_id is the approval named by the current release's canonical
-- release.approved event (dedupe key 'release.approved:<release id>'), under six conditions:
-- (1) the canonical key; (2) event_type release.approved; (3) subject_type preview_release;
-- (4) subject_id the current release; (5) project_id the project; (6) the named approval (as
-- text) belongs to that release and project. No timestamp fallback: missing or inconsistent
-- canonical evidence means not approved, fails G3, and lets WP-H's unchanged consumer create no
-- obligation, no outbound request and no collection authorization.
--
-- Projects reach a verified deposit through the real WP-B workflow and an accepted intake
-- through WP-C's real intake, then use WP-C's real release_preview and approve_preview. States
-- WP-C never produces (an approval without its canonical event, a defective canonical event, a
-- backdated approval) are SYNTHETIC TEST RECORDS, labelled where they are written; they never
-- stand in for approve_preview, which is unchanged. The two-client races are in
-- tests/integration/wpc-oi113-approval-race.test.ts. Synthetic data only; no Stripe.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(67);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false)
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
create function pg_temp.evt(p_id text, p_type text, p_obj jsonb, p_offset integer default 0)
returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type, 'api_version', '2026-09-30.endive',
    'livemode', false, 'created', extract(epoch from now())::bigint + p_offset, 'data', jsonb_build_object('object', p_obj));
$$;
grant execute on function pg_temp.evt(text, text, jsonb, integer) to service_role;
create function pg_temp.deliver(p_event jsonb) returns jsonb language plpgsql as $$
declare
  v_ingest jsonb;
  v_result jsonb;
begin
  perform pg_temp.as_service();
  v_ingest := public.ingest_stripe_event(p_event, repeat('c', 64));
  if not (v_ingest ->> 'ok')::boolean then
    reset role;
    return v_ingest;
  end if;
  v_result := public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  reset role;
  return v_result || jsonb_build_object('duplicate', v_ingest -> 'duplicate');
end;
$$;
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k; $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;
create function pg_temp.ev(p_k text) returns bigint language sql as $$ select v::bigint from ids where k = p_k; $$;

-- A project paid through the real workflow (as in 190): order summary (Owner), acceptance and
-- Checkout (client A), recorded mock results, a verified checkout.session.completed, and the
-- server's re-read of the card. Client B is also a member, so two clients can approve.
create function pg_temp.paid_project(p_tag text, p_card text) returns uuid language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
  v_os uuid;
  v_acc uuid;
  v_cs uuid;
  v_req record;
  v_tok uuid;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('Biz ' || p_tag || ' LLC', 'Biz ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'Project ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '00000000-0000-4000-8000-0000000000a1'),
    (v_project, '00000000-0000-4000-8000-0000000000b1');
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2');
  v_os := (public.issue_order_summary(v_project, 'essential', '[]'::jsonb) ->> 'order_summary_id')::uuid;
  reset role;
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'Biz ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
  v_cs := (public.begin_initial_checkout(v_project) ->> 'checkout_session_id')::uuid;
  reset role;
  perform pg_temp.as_service();
  for v_req in select id, purpose from public.outbound_stripe_requests where project_id = v_project
               order by (purpose = 'customer_create') desc loop
    -- AUTH-009 (setup): claim, confirm with the one-time token, then record with it.
    v_tok := (public.outbound_request_for_execution(v_req.id) ->> 'claim_token')::uuid;
    perform public.confirm_outbound_dispatch(v_req.id, v_tok);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cus_T' || p_tag || '00000', false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cs_test_' || p_tag || '00000', false, 200, null,
        jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_' || p_tag || '00000'));
    end if;
  end loop;
  reset role;
  perform pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'checkout0', 'checkout.session.completed', jsonb_build_object(
    'id', 'cs_test_' || p_tag || '00000', 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
    'amount_total', 25900, 'payment_status', 'paid', 'customer', 'cus_T' || p_tag || '00000',
    'subscription', 'sub_' || p_tag || '00000', 'invoice', 'in_' || p_tag || '00000',
    'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
    'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
      'checkout_record_id', v_cs))));
  perform pg_temp.svc(format('select public.record_payment_method_lookup(%L, %L, %L, %L, false, %L)', 'initial', v_cs,
    p_card, 'cus_T' || p_tag || '00000', true));
  return v_project;
end;
$$;
-- WP-C's real intake: the client saves and submits complete content; the Admin accepts it.
create function pg_temp.accept_intake(p_project uuid) returns void language plpgsql as $$
declare
  v_draft uuid;
  v_sub uuid;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v_draft := (public.save_intake_draft(p_project, jsonb_build_object('business_legal_name', 'Synthetic LLC',
    'business_display_name', 'Synthetic', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
    'address', '1 Test Street', 'service_areas', 'Test City', 'services_offered', 'Testing',
    'domain_status', 'needs_domain')) ->> 'draft_id')::uuid;
  v_sub := (public.submit_intake(p_project, v_draft) ->> 'submission_id')::uuid;
  reset role;
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  if not (public.review_intake(v_sub, 'accepted', 'Accepted') ->> 'ok')::boolean then
    raise exception 'fixture: intake for % was not accepted', p_project;
  end if;
  reset role;
end;
$$;
-- A project ready for a release: verified deposit, active card, accepted intake.
create function pg_temp.ready(p_tag text) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  v := pg_temp.paid_project(p_tag, 'pm_' || p_tag || 'card01');
  perform pg_temp.accept_intake(v);
  return v;
end;
$$;
-- WP-C's real release_preview (staff, aal2), approve_preview (a client member) and withdraw_preview.
-- AUTH-023 (setup only, OD-11(ii)): before a release, the project's current scope confirmation,
-- recorded by the Admin and acknowledged by its authorized signer, unless already acknowledged.
create function pg_temp.scope_ready(p_project uuid) returns void language plpgsql as $scope$
declare
  v jsonb;
  c public.scope_confirmations;
  v_signer uuid;
begin
  if private.scope_confirmation_state(p_project) = 'acknowledged' then
    return;
  end if;
  if private.scope_confirmation_state(p_project) in ('none', 'stale') then
    perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
    v := public.record_scope_confirmation(p_project, 'Synthetic client requirements', array['Synthetic selection'], '{}');
    reset role;
    if not coalesce((v ->> 'ok')::boolean, false) then
      raise exception 'fixture: record_scope_confirmation failed: %', v;
    end if;
  end if;
  c := private.current_scope_confirmation(p_project);
  v_signer := private.scope_authorized_signer(p_project);
  perform pg_temp.act_as(v_signer);
  v := public.acknowledge_scope_confirmation(c.id, c.content_sha256, true, true);
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: acknowledge_scope_confirmation failed: %', v;
  end if;
end;
$scope$;
create function pg_temp.release(p_project uuid, p_sha text) returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.scope_ready(p_project);
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  v := public.release_preview(p_project, p_sha, 'dpl_oi113_' || left(p_sha, 8), 'https://preview.example.test/oi113', '{}');
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: release_preview failed: %', v;
  end if;
  return (v ->> 'release_id')::uuid;
end;
$$;
create function pg_temp.approve(p_release uuid, p_user uuid default '00000000-0000-4000-8000-0000000000a1')
returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as(p_user);
  v := public.approve_preview(p_release);
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: approve_preview failed: %', v;
  end if;
  return v;
end;
$$;
-- SYNTHETIC TEST RECORD: an approval row written without approve_preview, so without its canonical
-- event (a state WP-C never produces).
create function pg_temp.bare_approval(p_release uuid, p_project uuid, p_user uuid,
  p_at timestamptz default now()) returns uuid language sql as $$
  insert into public.preview_approvals (release_id, project_id, user_id, approved_at)
  values (p_release, p_project, p_user, p_at) returning id;
$$;
-- WP-C's canonical release.approved event for a release, by its key alone.
create function pg_temp.canonical(p_release uuid) returns bigint language sql as $$
  select id from public.domain_events where dedupe_key = 'release.approved:' || p_release;
$$;
-- SYNTHETIC TEST EMISSION through the WP-0 writer: any type, subject, project, payload and key.
create function pg_temp.emit(p_type text, p_project uuid, p_subject_type text, p_subject text, p_release uuid,
  p_approval text, p_key text, p_payload jsonb default null) returns bigint language sql as $$
  select private.emit_domain_event(p_type, p_project, p_subject_type, p_subject,
    coalesce(p_payload, jsonb_build_object('release_id', r.id, 'release_number', r.release_number,
      'approval_id', p_approval, 'commit_sha', r.commit_sha)), p_key)
  from public.preview_releases r where r.id = p_release;
$$;
-- A well-formed release.approved naming an approval, under a non-canonical key.
create function pg_temp.noncanonical(p_project uuid, p_release uuid, p_approval uuid, p_tag text) returns bigint
language sql as $$
  select pg_temp.emit('release.approved', p_project, 'preview_release', p_release::text, p_release, p_approval::text,
    'release.approved:synthetic:' || p_tag);
$$;
-- The interface's verdict for the current release, as 'approved:approval_id'.
create function pg_temp.appr(p_project uuid) returns text language sql as $$
  select coalesce(s.current_release_approved::text, 'null') || ':' || coalesce(s.current_release_approval_id::text, 'null')
  from private.project_fulfillment_status(p_project) s;
$$;
-- G3 for the current release, through the single gate evaluator.
create function pg_temp.g3(p_project uuid) returns text language sql as $$
  select case when (g ->> 'passed')::boolean then 'passed' else g ->> 'reason' end
  from jsonb_array_elements(private.evaluate_publication_gates(p_project, (private.current_release(p_project)).id) -> 'gates') g
  where g ->> 'gate' = 'G3';
$$;
create function pg_temp.consume(p_event bigint) returns text language sql as $$
  select private.consume_release_approved(p_event);
$$;
create function pg_temp.detail(p_event bigint) returns text language sql as $$
  select detail from private.event_consumptions where consumer = 'wpb.final_balance_invoice' and domain_event_id = p_event;
$$;
-- Obligations, final-balance creates, balance-due events and collection authorizations.
create function pg_temp.effects(p_project uuid) returns text language sql as $$
  select (select count(*) from public.final_balance_invoices where project_id = p_project) || '/'
      || (select count(*) from public.outbound_stripe_requests where project_id = p_project
            and purpose = 'final_balance_invoice_create') || '/'
      || (select count(*) from public.domain_events where project_id = p_project and event_type = 'payment.balance_due') || '/'
      || (select count(*) from public.audit_events where project_id = p_project and action = 'balance.collection_authorized');
$$;
-- A rejection is audited and notified to the Owner.
create function pg_temp.rejection_recorded(p_event bigint) returns boolean language sql as $$
  select exists (select 1 from public.audit_events where action = 'release_approval.rejected' and target_id = p_event::text)
     and exists (select 1 from public.notification_outbox where notification_type = 'payment.final_balance_blocked'
                  and idempotency_key = 'payment.final_balance_blocked:' || p_event || ':1');
$$;
-- The fixture helper exactly as in pgTAP 120, 130, 150 and 160 (AUTH-013 fixture moves 1 to 4).
create function pg_temp.genuine_release_approved(p_project uuid, p_release uuid, p_approval uuid, p_key text) returns bigint
language plpgsql as $$
declare
  v_rel public.preview_releases%rowtype;
  v_ful private.project_fulfillment_status;
  v_first boolean;
  v_event bigint;
  v_canon public.domain_events%rowtype;
begin
  select * into v_rel from public.preview_releases where id = p_release;
  if not found then
    insert into public.preview_releases (id, project_id, release_number, commit_sha, deployment_id, preview_url, released_by)
    values (p_release, p_project,
      coalesce((select max(r.release_number) from public.preview_releases r where r.project_id = p_project), 0) + 1,
      substr(encode(sha256(convert_to(p_release::text, 'UTF8')), 'hex'), 1, 40),
      'dpl_' || substr(replace(p_release::text, '-', ''), 1, 24), 'https://preview.example.test/' || p_release,
      (select s.user_id from public.staff_roles s where s.role = 'admin' and s.status = 'active' order by s.user_id limit 1))
    returning * into v_rel;
  end if;
  -- OI-113 (AUTH-013 fixture integrity): only a call that creates the release's first approval
  -- emits WP-C's canonical event (as approve_preview does); later calls use the supplied
  -- non-canonical key. A canonical event is never fabricated, replaced or repaired.
  v_first := not exists (select 1 from public.preview_approvals where release_id = v_rel.id);
  if not exists (select 1 from public.preview_approvals where id = p_approval) then
    insert into public.preview_approvals (id, release_id, project_id, user_id)
    values (p_approval, v_rel.id, v_rel.project_id, (select m.user_id from public.project_memberships m
      where m.project_id = v_rel.project_id and private.staff_role_of(m.user_id) is null order by m.user_id limit 1));
  end if;
  if not v_first and p_key = 'release.approved:' || p_release::text then
    raise exception 'fixture: canonical key % is reserved for the first approval of release %', p_key, p_release;
  end if;
  v_event := private.emit_domain_event('release.approved', p_project, 'preview_release', p_release::text,
    jsonb_build_object('release_id', v_rel.id, 'release_number', v_rel.release_number, 'approval_id', p_approval,
      'commit_sha', v_rel.commit_sha),
    case when v_first then 'release.approved:' || p_release::text else p_key end);
  -- (a) Exactly one canonical event (dedupe_key is unique), of the right type, subject and
  --     project, naming an approval of this release and project, and naming p_approval when
  --     this call created the release's first approval.
  select * into v_canon from public.domain_events where dedupe_key = 'release.approved:' || p_release::text;
  if v_canon.id is null or v_canon.event_type <> 'release.approved' or v_canon.subject_type <> 'preview_release'
     or v_canon.subject_id <> p_release::text or v_canon.project_id is distinct from p_project
     or not exists (select 1 from public.preview_approvals a where a.id::text = v_canon.payload ->> 'approval_id'
                     and a.release_id = p_release and a.project_id = p_project)
     or (v_first and v_canon.payload ->> 'approval_id' is distinct from p_approval::text) then
    raise exception 'fixture: release % has no consistent canonical release.approved event', p_release;
  end if;
  -- (b) The fulfillment interface reports this release and approval as current.
  v_ful := private.project_fulfillment_status(p_project);
  if v_ful.current_release_id is distinct from p_release or v_ful.current_release_approval_id is distinct from p_approval then
    raise exception 'fixture: release % / approval % is not WP-C current (current %, recorded %)',
      p_release, p_approval, v_ful.current_release_id, v_ful.current_release_approval_id;
  end if;
  return v_event;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. R1 and RP: WP-C's own approval, a second client's approval, replay
-- ---------------------------------------------------------------------------
insert into ids select 'p1', pg_temp.ready('QONE')::text;
insert into ids select 'r1', pg_temp.release(pg_temp.id('p1'), repeat('1', 40))::text;
insert into ids select 'a1', pg_temp.approve(pg_temp.id('r1')) ->> 'approval_id';
select is(pg_temp.appr(pg_temp.id('p1')), 'true:' || pg_temp.id('a1'),
  'R1: an approval through approve_preview is the current release''s approval');
select is((select payload ->> 'approval_id' from public.domain_events where id = pg_temp.canonical(pg_temp.id('r1'))),
  pg_temp.id('a1')::text, 'R1: the reported approval is the one the canonical release.approved event names');
select is(pg_temp.g3(pg_temp.id('p1')), 'passed', 'R1: G3 passes for the canonically approved current release');
insert into ids select 'b1', pg_temp.approve(pg_temp.id('r1'), '00000000-0000-4000-8000-0000000000b1') ->> 'approval_id';
select is((select count(*)::int from public.domain_events where event_type = 'release.approved'
            and subject_id = pg_temp.id('r1')::text), 1,
  'RP: a second client''s approve_preview on the same release emits no second release.approved');
select is(pg_temp.appr(pg_temp.id('p1')), 'true:' || pg_temp.id('a1'),
  'RP: the second client''s approval does not change the identification');
select ok((pg_temp.approve(pg_temp.id('r1')) ->> 'existing')::boolean
  and (select count(*) = 1 from public.domain_events where event_type = 'release.approved' and subject_id = pg_temp.id('r1')::text),
  'RP: a repeat approve_preview returns the existing approval and emits nothing');
select is(pg_temp.consume(pg_temp.canonical(pg_temp.id('r1'))), 'created',
  'WP-H''s unchanged consumer creates the obligation from the canonical event');
select is(pg_temp.effects(pg_temp.id('p1')), '1/1/1/1',
  'one obligation, one final_balance_invoice_create, one payment.balance_due, one balance.collection_authorized');
select is(pg_temp.consume(pg_temp.canonical(pg_temp.id('r1'))), 'already_consumed', 'RP: replay is already_consumed');
select is(pg_temp.effects(pg_temp.id('p1')), '1/1/1/1', 'RP: replay adds nothing');

-- ---------------------------------------------------------------------------
-- 2. R2 (PR #35 B-1) and RA (WP-S F-1, refinement A)
-- ---------------------------------------------------------------------------
insert into ids select 'p2', pg_temp.ready('QTWO')::text;
insert into ids select 'r2', pg_temp.release(pg_temp.id('p2'), repeat('2', 40))::text;
insert into ids select 'a2', pg_temp.approve(pg_temp.id('r2')) ->> 'approval_id';
-- SYNTHETIC TEST RECORD: client B's approval with an earlier approved_at than A's, as when B's
-- transaction began first but took the release lock second (approved_at is the transaction start).
insert into ids select 'b2', pg_temp.bare_approval(pg_temp.id('r2'), pg_temp.id('p2'), '00000000-0000-4000-8000-0000000000b1',
  now() - interval '1 minute')::text;
select ok((select approved_at from public.preview_approvals where id = pg_temp.id('b2'))
        < (select approved_at from public.preview_approvals where id = pg_temp.id('a2')),
  'R2: the second-locked approval has the earlier approved_at (the B-1 ordering)');
select is(pg_temp.appr(pg_temp.id('p2')), 'true:' || pg_temp.id('a2'),
  'R2: the interface reports the approval the canonical event names, not the earliest approved_at');
-- RA: a well-formed non-canonical event naming the second approver's approval is consumed
-- BEFORE any valid event has created an obligation.
insert into ids select 'e_f1', pg_temp.noncanonical(pg_temp.id('p2'), pg_temp.id('r2'), pg_temp.id('b2'), 'f1')::text;
select is(pg_temp.effects(pg_temp.id('p2')), '0/0/0/0', 'RA: no obligation exists before the non-canonical event is consumed');
select is(pg_temp.consume(pg_temp.ev('e_f1')), 'rejected', 'RA: the event naming the second approver is rejected');
select is(pg_temp.detail(pg_temp.ev('e_f1')), 'approval_mismatch', 'RA: detail approval_mismatch');
select ok(pg_temp.rejection_recorded(pg_temp.ev('e_f1')), 'RA: the rejection is audited and notified to the Owner');
select is(pg_temp.effects(pg_temp.id('p2')), '0/0/0/0',
  'RA: no obligation, no outbound request, no balance-due event, no collection authorization');
select is(pg_temp.consume(pg_temp.canonical(pg_temp.id('r2'))), 'created', 'RA: the canonical event then creates the obligation');
select ok((select approval_id = pg_temp.id('a2') and release_id = pg_temp.id('r2') from public.final_balance_invoices
            where project_id = pg_temp.id('p2')) and pg_temp.effects(pg_temp.id('p2')) = '1/1/1/1',
  'RA: exactly one obligation, for the canonical approval');

-- ---------------------------------------------------------------------------
-- 3. R3, R4/C1, R5: no canonical event, only a non-canonical one, a later non-canonical one
-- ---------------------------------------------------------------------------
insert into ids select 'p3', pg_temp.ready('QTHREE')::text;
insert into ids select 'r3', pg_temp.release(pg_temp.id('p3'), repeat('3', 40))::text;
insert into ids select 'a3', pg_temp.bare_approval(pg_temp.id('r3'), pg_temp.id('p3'), '00000000-0000-4000-8000-0000000000a1')::text;
select is(pg_temp.appr(pg_temp.id('p3')), 'false:null', 'R3: an approval without a canonical event is not approved');
select is(pg_temp.g3(pg_temp.id('p3')), 'release_not_approved', 'R3: G3 fails');
insert into ids select 'e_r4', pg_temp.noncanonical(pg_temp.id('p3'), pg_temp.id('r3'), pg_temp.id('a3'), 'r4')::text;
select is(pg_temp.appr(pg_temp.id('p3')), 'false:null',
  'R4 / C1: a valid release.approved under a non-canonical key does not approve the release');
select is(pg_temp.g3(pg_temp.id('p3')), 'release_not_approved', 'R4 / C1: G3 fails');
select is(pg_temp.consume(pg_temp.ev('e_r4')), 'rejected', 'RC (R3, R4, C1): the event is rejected');
select is(pg_temp.detail(pg_temp.ev('e_r4')), 'approval_mismatch', 'RC (R3, R4, C1): detail approval_mismatch');
select ok(pg_temp.rejection_recorded(pg_temp.ev('e_r4')) and pg_temp.effects(pg_temp.id('p3')) = '0/0/0/0',
  'RC (R3, R4, C1): audited and notified; no obligation, outbound request or collection authorization');

insert into ids select 'p5', pg_temp.ready('QFIVE')::text;
insert into ids select 'r5', pg_temp.release(pg_temp.id('p5'), repeat('5', 40))::text;
insert into ids select 'a5', pg_temp.approve(pg_temp.id('r5')) ->> 'approval_id';
insert into ids select 'b5', pg_temp.approve(pg_temp.id('r5'), '00000000-0000-4000-8000-0000000000b1') ->> 'approval_id';
insert into ids select 'e_r5', pg_temp.noncanonical(pg_temp.id('p5'), pg_temp.id('r5'), pg_temp.id('b5'), 'r5-later')::text;
select is(pg_temp.appr(pg_temp.id('p5')), 'true:' || pg_temp.id('a5'),
  'R5: a later non-canonical event naming another approval never changes the identification');

-- ---------------------------------------------------------------------------
-- 4. C2 to C6: a canonical-key event that fails one condition. One project; each case is a
-- new current release with a SYNTHETIC approval (no canonical event from approve_preview) and
-- a SYNTHETIC canonical-key event. Each case consumes the defective event and a well-formed
-- non-canonical event naming the approval before the next release supersedes it.
-- ---------------------------------------------------------------------------
insert into ids select 'pc', pg_temp.ready('QCASES')::text;
create function pg_temp.case_release(p_case text, p_sha text) returns void language plpgsql as $$
begin
  insert into ids select 'r_' || p_case, pg_temp.release(pg_temp.id('pc'), p_sha)::text;
  insert into ids select 'a_' || p_case, pg_temp.bare_approval(pg_temp.id('r_' || p_case), pg_temp.id('pc'),
    '00000000-0000-4000-8000-0000000000a1')::text;
  insert into ids select 'n_' || p_case, pg_temp.noncanonical(pg_temp.id('pc'), pg_temp.id('r_' || p_case),
    pg_temp.id('a_' || p_case), p_case)::text;
end;
$$;
-- The case verdict: interface, G3, and WP-H's consumption of both events.
create function pg_temp.case_verdict(p_case text) returns text language sql as $$
  select pg_temp.appr(pg_temp.id('pc')) || ' ' || pg_temp.g3(pg_temp.id('pc')) || ' '
      || pg_temp.consume(pg_temp.ev('c_' || p_case)) || ' '
      || pg_temp.consume(pg_temp.ev('n_' || p_case)) || '/' || pg_temp.detail(pg_temp.ev('n_' || p_case));
$$;

-- C2: another event type under the canonical key.
select pg_temp.case_release('c2', repeat('c', 39) || '2');
insert into ids select 'c_c2', pg_temp.emit('publication.authorized', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c2')::text, pg_temp.id('r_c2'), pg_temp.id('a_c2')::text, 'release.approved:' || pg_temp.id('r_c2'))::text;
select is(pg_temp.case_verdict('c2'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C2: a canonical-key event of another type: not approved, G3 fails, both events rejected');
-- C3: another subject type.
select pg_temp.case_release('c3', repeat('c', 39) || '3');
insert into ids select 'c_c3', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_approval',
  pg_temp.id('r_c3')::text, pg_temp.id('r_c3'), pg_temp.id('a_c3')::text, 'release.approved:' || pg_temp.id('r_c3'))::text;
select is(pg_temp.case_verdict('c3'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C3: a canonical-key event with another subject type: not approved, G3 fails, both events rejected');
-- C4: another subject (the previous, superseded release).
select pg_temp.case_release('c4', repeat('c', 39) || '4');
insert into ids select 'c_c4', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c3')::text, pg_temp.id('r_c4'), pg_temp.id('a_c4')::text, 'release.approved:' || pg_temp.id('r_c4'))::text;
select is(pg_temp.case_verdict('c4'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C4: a canonical-key event whose subject is another release: not approved, G3 fails, both events rejected');
-- C5: another project.
select pg_temp.case_release('c5', repeat('c', 39) || '5');
insert into ids select 'c_c5', pg_temp.emit('release.approved', pg_temp.id('p3'), 'preview_release',
  pg_temp.id('r_c5')::text, pg_temp.id('r_c5'), pg_temp.id('a_c5')::text, 'release.approved:' || pg_temp.id('r_c5'))::text;
select is(pg_temp.case_verdict('c5'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C5: a canonical-key event of another project: not approved, G3 fails, both events rejected');
-- C6a: the payload names an approval of another release (the previous release of this project).
select pg_temp.case_release('c6a', repeat('c', 38) || '6a');
insert into ids select 'c_c6a', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c6a')::text, pg_temp.id('r_c6a'), pg_temp.id('a_c5')::text, 'release.approved:' || pg_temp.id('r_c6a'))::text;
select is(pg_temp.case_verdict('c6a'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C6a: the payload names an approval of another release: not approved, G3 fails, both events rejected');
-- C6b: the payload names an approval row of this release recorded under another project
-- (SYNTHETIC TEST RECORD: preview_approvals has no constraint tying project_id to the release).
select pg_temp.case_release('c6b', repeat('c', 38) || '6b');
insert into ids select 'x_c6b', pg_temp.bare_approval(pg_temp.id('r_c6b'), pg_temp.id('p3'),
  '00000000-0000-4000-8000-0000000000b1')::text;
insert into ids select 'c_c6b', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c6b')::text, pg_temp.id('r_c6b'), pg_temp.id('x_c6b')::text, 'release.approved:' || pg_temp.id('r_c6b'))::text;
select is(pg_temp.case_verdict('c6b'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C6b: the payload names an approval of another project: not approved, G3 fails, both events rejected');
-- C6c: the payload names an unrecorded approval, names none, or names a non-UUID.
select pg_temp.case_release('c6c', repeat('c', 38) || 'c1');
insert into ids select 'c_c6c', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c6c')::text, pg_temp.id('r_c6c'), gen_random_uuid()::text, 'release.approved:' || pg_temp.id('r_c6c'))::text;
select is(pg_temp.case_verdict('c6c'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C6c: the payload names an unrecorded approval: not approved, G3 fails, both events rejected');
select pg_temp.case_release('c6d', repeat('c', 38) || 'c2');
insert into ids select 'c_c6d', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c6d')::text, pg_temp.id('r_c6d'), null, 'release.approved:' || pg_temp.id('r_c6d'),
  jsonb_build_object('release_id', pg_temp.id('r_c6d'), 'release_number', 7))::text;
select is(pg_temp.case_verdict('c6d'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C6c: the payload names no approval: not approved, G3 fails, both events rejected');
select pg_temp.case_release('c6e', repeat('c', 38) || 'c3');
insert into ids select 'c_c6e', pg_temp.emit('release.approved', pg_temp.id('pc'), 'preview_release',
  pg_temp.id('r_c6e')::text, pg_temp.id('r_c6e'), 'not-a-uuid', 'release.approved:' || pg_temp.id('r_c6e'))::text;
select is(pg_temp.case_verdict('c6e'), 'false:null release_not_approved rejected rejected/approval_mismatch',
  'C6c: the payload names a non-UUID: not approved (no cast error), G3 fails, both events rejected');
select ok(pg_temp.effects(pg_temp.id('pc')) = '0/0/0/0' and pg_temp.effects(pg_temp.id('p3')) = '0/0/0/0'
  and (select bool_and(pg_temp.rejection_recorded(v::bigint)) from ids where k like 'c\_c%' or k like 'n\_c%'),
  'RC (C2 to C6): every rejection is audited and notified; no obligation, outbound request or collection authorization');
select is((select count(*)::int from ids where k like 'c\_c%' or k like 'n\_c%'), 18, 'RC: 18 events consumed in section 4');

-- ---------------------------------------------------------------------------
-- 5. W and S: withdrawal and supersession (unchanged)
-- ---------------------------------------------------------------------------
insert into ids select 'pw', pg_temp.ready('QWITH')::text;
insert into ids select 'rw', pg_temp.release(pg_temp.id('pw'), repeat('7', 40))::text;
insert into ids select 'aw', pg_temp.approve(pg_temp.id('rw')) ->> 'approval_id';
select is(pg_temp.appr(pg_temp.id('pw')), 'true:' || pg_temp.id('aw'), 'W: approved before withdrawal');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok((public.withdraw_preview(pg_temp.id('rw'), 'Synthetic withdrawal') ->> 'ok')::boolean, 'W: the Admin withdraws the release');
reset role;
select ok((select current_release_id is null and not current_release_approved and current_release_approval_id is null
           from private.project_fulfillment_status(pg_temp.id('pw'))),
  'W: a withdrawn latest release has no current release and no approval');

insert into ids select 'ps', pg_temp.ready('QSUPER')::text;
insert into ids select 'rs1', pg_temp.release(pg_temp.id('ps'), repeat('8', 40))::text;
insert into ids select 'as1', pg_temp.approve(pg_temp.id('rs1')) ->> 'approval_id';
insert into ids select 'rs2', pg_temp.release(pg_temp.id('ps'), repeat('9', 40))::text;
select ok((select current_release_id = pg_temp.id('rs2') and not current_release_approved and current_release_approval_id is null
           from private.project_fulfillment_status(pg_temp.id('ps'))),
  'S: a superseding release has no canonical event yet and is not approved');
insert into ids select 'as2', pg_temp.approve(pg_temp.id('rs2')) ->> 'approval_id';
select is(pg_temp.appr(pg_temp.id('ps')), 'true:' || pg_temp.id('as2'),
  'S: its own approve_preview approves it, with its own approval');
select is(pg_temp.consume(pg_temp.canonical(pg_temp.id('rs1'))), 'rejected', 'S: the superseded release''s event is rejected');
select is(pg_temp.detail(pg_temp.canonical(pg_temp.id('rs1'))), 'release_superseded', 'S: detail release_superseded (unchanged)');

-- ---------------------------------------------------------------------------
-- 6. H1 to H5: the fixture helper's integrity rule
-- ---------------------------------------------------------------------------
create function pg_temp.plain_project(p_tag text) returns uuid language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('Helper ' || p_tag || ' LLC', 'Helper ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'Helper ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '00000000-0000-4000-8000-0000000000a1');
  return v_project;
end;
$$;
-- A release recorded the way the helper records one, with no approval yet.
create function pg_temp.helper_release(p_project uuid) returns uuid language sql as $$
  insert into public.preview_releases (project_id, release_number, commit_sha, deployment_id, preview_url, released_by)
  select p_project, coalesce((select max(r.release_number) from public.preview_releases r where r.project_id = p_project), 0) + 1,
    substr(encode(sha256(convert_to(gen_random_uuid()::text, 'UTF8')), 'hex'), 1, 40), 'dpl_helper',
    'https://preview.example.test/helper',
    (select s.user_id from public.staff_roles s where s.role = 'admin' and s.status = 'active' order by s.user_id limit 1)
  returning id;
$$;
create function pg_temp.helper_call(p_project text, p_release text, p_approval text, p_key text) returns text
language sql as $$
  select format('select pg_temp.genuine_release_approved(%L, %L, %L, %L)', pg_temp.id(p_project), pg_temp.id(p_release),
    pg_temp.id(p_approval), p_key);
$$;

-- H4: the helper creating a release's first approval emits exactly one canonical event naming it.
insert into ids select 'ph4', pg_temp.plain_project('H4')::text;
insert into ids values ('rh4', gen_random_uuid()::text), ('ah4', gen_random_uuid()::text);
insert into ids select 'eh4', pg_temp.genuine_release_approved(pg_temp.id('ph4'), pg_temp.id('rh4'), pg_temp.id('ah4'),
  'release.approved:' || pg_temp.id('ah4'))::text;
select ok((select count(*) = 1 from public.domain_events where event_type = 'release.approved' and subject_id = pg_temp.id('rh4')::text)
  and (select dedupe_key = 'release.approved:' || pg_temp.id('rh4') and payload ->> 'approval_id' = pg_temp.id('ah4')::text
       from public.domain_events where id = pg_temp.ev('eh4')),
  'H4: a first approval emits exactly one event, with the canonical key, naming it');
select is(pg_temp.appr(pg_temp.id('ph4')), 'true:' || pg_temp.id('ah4'), 'H4: the interface reports it current');
-- A later call for the same, existing approval keeps the supplied non-canonical key.
insert into ids select 'eh4r', pg_temp.genuine_release_approved(pg_temp.id('ph4'), pg_temp.id('rh4'), pg_temp.id('ah4'),
  'release.approved:redelivery:h4')::text;
select ok((select dedupe_key = 'release.approved:redelivery:h4' from public.domain_events where id = pg_temp.ev('eh4r'))
  and pg_temp.appr(pg_temp.id('ph4')) = 'true:' || pg_temp.id('ah4'),
  'H4: a later call for the existing first approval emits only the supplied non-canonical key');

-- H1: an existing approval with no canonical event: the helper raises and repairs nothing.
insert into ids select 'ph1', pg_temp.plain_project('H1')::text;
insert into ids select 'rh1', pg_temp.helper_release(pg_temp.id('ph1'))::text;
insert into ids select 'ah1', pg_temp.bare_approval(pg_temp.id('rh1'), pg_temp.id('ph1'), '00000000-0000-4000-8000-0000000000a1')::text;
select throws_like(pg_temp.helper_call('ph1', 'rh1', 'ah1', 'release.approved:synthetic:h1'),
  'fixture: release ' || pg_temp.id('rh1') || ' has no consistent canonical release.approved event',
  'H1: the helper raises for an existing approval with no canonical event (check (a))');
select ok(pg_temp.canonical(pg_temp.id('rh1')) is null
  and not exists (select 1 from public.domain_events where dedupe_key = 'release.approved:synthetic:h1'),
  'H1: no canonical event was fabricated, and nothing was emitted');
select is(pg_temp.appr(pg_temp.id('ph1')), 'false:null', 'H1: the interface reports not approved');

-- H2: an existing approval whose canonical event is inconsistent: the helper raises.
insert into ids select 'ph2', pg_temp.plain_project('H2')::text;
insert into ids select 'rh2a', pg_temp.helper_release(pg_temp.id('ph2'))::text;
insert into ids select 'ah2a', pg_temp.bare_approval(pg_temp.id('rh2a'), pg_temp.id('ph2'), '00000000-0000-4000-8000-0000000000a1')::text;
insert into ids select 'rh2', pg_temp.helper_release(pg_temp.id('ph2'))::text;
insert into ids select 'ah2', pg_temp.bare_approval(pg_temp.id('rh2'), pg_temp.id('ph2'), '00000000-0000-4000-8000-0000000000a1')::text;
-- SYNTHETIC: the canonical event names an approval of another release.
insert into ids select 'eh2', pg_temp.emit('release.approved', pg_temp.id('ph2'), 'preview_release', pg_temp.id('rh2')::text, pg_temp.id('rh2'),
  pg_temp.id('ah2a')::text, 'release.approved:' || pg_temp.id('rh2'))::text;
select throws_like(pg_temp.helper_call('ph2', 'rh2', 'ah2', 'release.approved:synthetic:h2'),
  'fixture: release ' || pg_temp.id('rh2') || ' has no consistent canonical release.approved event',
  'H2: the helper raises when the canonical event names another release''s approval (check (a))');
select is(pg_temp.appr(pg_temp.id('ph2')), 'false:null', 'H2: the interface reports not approved');
insert into ids select 'ph2b', pg_temp.plain_project('H2B')::text;
insert into ids select 'rh2b', pg_temp.helper_release(pg_temp.id('ph2b'))::text;
insert into ids select 'ah2b', pg_temp.bare_approval(pg_temp.id('rh2b'), pg_temp.id('ph2b'), '00000000-0000-4000-8000-0000000000a1')::text;
-- SYNTHETIC: the canonical event names the right approval but another project.
insert into ids select 'eh2b', pg_temp.emit('release.approved', pg_temp.id('ph2'), 'preview_release', pg_temp.id('rh2b')::text, pg_temp.id('rh2b'),
  pg_temp.id('ah2b')::text, 'release.approved:' || pg_temp.id('rh2b'))::text;
select throws_like(pg_temp.helper_call('ph2b', 'rh2b', 'ah2b', 'release.approved:synthetic:h2b'),
  'fixture: release ' || pg_temp.id('rh2b') || ' has no consistent canonical release.approved event',
  'H2: the helper raises when the canonical event belongs to another project (check (a))');
select is(pg_temp.appr(pg_temp.id('ph2b')), 'false:null', 'H2: the interface reports not approved');

-- H3: the canonical key is reserved for the first approval.
select throws_like(pg_temp.helper_call('ph4', 'rh4', 'ah4', 'release.approved:' || pg_temp.id('rh4')),
  'fixture: canonical key release.approved:' || pg_temp.id('rh4') || ' is reserved for the first approval of release %',
  'H3: the helper refuses the canonical key for an existing approval');
select is((select count(*)::int from public.domain_events where event_type = 'release.approved'
            and subject_id = pg_temp.id('rh4')::text), 2, 'H3: no event was emitted (the H4 event and its re-delivery only)');

-- H5: check (b): a consistent canonical event for a release that is not current still raises.
insert into ids select 'ph5', pg_temp.plain_project('H5')::text;
insert into ids select 'rh5', pg_temp.helper_release(pg_temp.id('ph5'))::text;
insert into ids select 'rh5n', pg_temp.helper_release(pg_temp.id('ph5'))::text;
insert into ids values ('ah5', gen_random_uuid()::text);
select throws_like(pg_temp.helper_call('ph5', 'rh5', 'ah5', 'release.approved:synthetic:h5'),
  'fixture: release ' || pg_temp.id('rh5') || ' / approval ' || pg_temp.id('ah5') || ' is not WP-C current%',
  'H5: the helper raises unless the interface reports the release and approval as current (check (b))');

-- ---------------------------------------------------------------------------
-- 7. G: static emission guard; RD: historical evidence; X: shape, ACL and version
-- ---------------------------------------------------------------------------
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosrc ~* 'emit_domain_event\s*\(\s*''release\.approved'''),
  array['approve_preview'], 'G: approve_preview is the only database function that emits release.approved');
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.prosrc ~* 'insert\s+into\s+public\.domain_events'),
  array['emit_domain_event'], 'G: only the WP-0 writer inserts into domain_events');
select ok((select indisunique from pg_index i join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
           where i.indrelid = 'public.domain_events'::regclass and a.attname = 'dedupe_key' and i.indnatts = 1),
  'Invariant: dedupe_key is unique, so at most one canonical event exists per release');
select is((select array_agg(t.tgname::text order by t.tgname) from pg_trigger t
  where not t.tgisinternal and t.tgrelid in ('public.domain_events'::regclass, 'private.event_consumptions'::regclass,
    'public.publication_authorizations'::regclass, 'public.preview_approvals'::regclass)),
  array['domain_events_no_truncate', 'domain_events_no_update_delete', 'event_consumptions_guard',
        'preview_approvals_insert_only', 'publication_authorizations_guard'],
  'RD: events, consumptions, approvals and publication evidence stay protected against change');
select ok((select provolatile = 's' and prosecdef and proconfig = array['search_path=""']
           from pg_proc where oid = 'private.project_fulfillment_status(uuid)'::regprocedure),
  'RD / X: the interface is stable (it cannot write, replay or re-emit), security definer, empty search_path');
select is((select outcome from private.event_consumptions where consumer = 'wpb.final_balance_invoice'
            and domain_event_id = pg_temp.canonical(pg_temp.id('r1'))), 'created',
  'RD: re-evaluating the interface leaves a consumed event''s outcome unchanged');
select is(
  (select array_agg(a.attname::text order by a.attnum) from pg_attribute a
   where a.attrelid = 'private.project_fulfillment_status'::regclass and a.attnum > 0 and not a.attisdropped),
  array['project_id', 'contract_version', 'implemented', 'intake_state', 'intake_accepted', 'current_release_id',
        'current_release_approved', 'current_release_approval_id', 'qa_passed', 'security_passed',
        'active_fulfillment_holds', 'evidence', 'domain_ready', 'domain_check_id', 'domain_checked_at'],
  'X: the interface composite is unchanged');
select ok(not has_function_privilege('anon', 'private.project_fulfillment_status(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.project_fulfillment_status(uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.project_fulfillment_status(uuid)', 'execute'),
  'X: no API role can execute the interface');
select ok((select contract_version = 2 and implemented from private.project_fulfillment_status(pg_temp.id('p1'))),
  'X: contract_version is 2 and the interface is implemented');

select * from finish();
rollback;
