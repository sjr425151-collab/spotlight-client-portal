-- WP-H (AUTH-006 Amendments 1 and 2): the release-approval cross-check in
-- private.consume_release_approved before final-balance initiation (04 §10.2; OI-92).
-- Every project reaches a verified deposit through the real WP-B workflow, then WP-C's real
-- intake, release_preview and approve_preview. Positive cases consume WP-C's own
-- release.approved emission. Negative cases that WP-C cannot produce are SYNTHETIC TEST EMISSIONS,
-- labelled where they are written; they exercise the consumer's defenses and never stand in for
-- WP-C's approve_preview, which is unchanged. Each event is consumed individually, in the order
-- shown. Two-connection concurrency is in tests/integration/wph-hardening.test.ts.
-- Synthetic events and recorded mock results only (OI-63); no Stripe.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(47);

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
  -- AUTH-009 (setup): a claim's one-time token is stored test-locally and confirmed as the
  -- executor does, and is removed from the result.
  if v ? 'claim_token' then
    insert into claim_tokens values ((v ->> 'id')::uuid, (v ->> 'claim_token')::uuid);
    perform public.confirm_outbound_dispatch((v ->> 'id')::uuid, (v ->> 'claim_token')::uuid);
    v := v - 'claim_token';
  end if;
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
-- AUTH-009 (setup): the one-time claim tokens, kept test-locally; never printed or asserted.
create temporary table claim_tokens (request_id uuid primary key, token uuid not null) on commit drop;
grant all on claim_tokens to service_role;
create function pg_temp.token(p_request_id uuid) returns uuid language sql as $$
  select token from claim_tokens where request_id = p_request_id;
$$;
grant execute on function pg_temp.token(uuid) to service_role;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k; $$;
grant execute on function pg_temp.id(text) to authenticated, service_role;

-- A project paid through the real workflow (as in 130): order summary (Owner), acceptance and
-- Checkout (client A), recorded mock results, a verified checkout.session.completed, and, when
-- p_card is set, the server's re-read of the card.
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
  insert into public.project_memberships (project_id, user_id) values (v_project, '00000000-0000-4000-8000-0000000000a1');
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
  if p_card is not null then
    perform pg_temp.svc(format('select public.record_payment_method_lookup(%L, %L, %L, %L, false, %L)', 'initial', v_cs,
      p_card, 'cus_T' || p_tag || '00000', true));
  end if;
  return v_project;
end;
$$;
-- The initial invoice (as in 180): links the payment intent that refunds and disputes name.
create function pg_temp.initial_invoice(p_project uuid, p_tag text) returns jsonb language plpgsql as $$
declare
  v_cs public.checkout_sessions%rowtype;
begin
  select * into v_cs from public.checkout_sessions where project_id = p_project;
  return pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'initinv0', 'invoice.paid', jsonb_build_object('id', 'in_' || p_tag || '00000',
    'object', 'invoice', 'billing_reason', 'subscription_create', 'currency', 'usd', 'amount_paid', 25900,
    'customer', 'cus_T' || p_tag || '00000', 'payment_intent', 'pi_' || p_tag || 'init01',
    'parent', jsonb_build_object('subscription_details', jsonb_build_object('subscription', 'sub_' || p_tag || '00000',
      'metadata', jsonb_build_object('project_id', p_project, 'checkout_record_id', v_cs.id))),
    'lines', jsonb_build_object('data', jsonb_build_array(
      jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HxK5j4r4WkVPkRUJ4gnZ')),
      jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe')))))));
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
-- WP-C's real release_preview (staff, aal2) and approve_preview (the project's client).
create function pg_temp.release(p_project uuid, p_sha text) returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
  v := public.release_preview(p_project, p_sha, 'dpl_wph_' || left(p_sha, 8), 'https://preview.example.test/wph', '{}');
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: release_preview failed: %', v;
  end if;
  return (v ->> 'release_id')::uuid;
end;
$$;
create function pg_temp.approve(p_release uuid) returns uuid language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
  v := public.approve_preview(p_release);
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: approve_preview failed: %', v;
  end if;
  return (v ->> 'approval_id')::uuid;
end;
$$;
-- WP-C's own release.approved emission for a release (approve_preview emits once per release).
create function pg_temp.wpc_event(p_release uuid) returns bigint language sql as $$
  select id from public.domain_events where event_type = 'release.approved' and dedupe_key = 'release.approved:' || p_release;
$$;
-- SYNTHETIC TEST EMISSION (consumer defense only): an event WP-C would never emit, written through
-- the WP-0 writer in WP-C's payload shape.
create function pg_temp.synthetic(p_project uuid, p_release uuid, p_approval uuid, p_number integer, p_sha text, p_key text)
returns bigint language sql as $$
  select private.emit_domain_event('release.approved', p_project, 'preview_release', p_release::text,
    jsonb_build_object('release_id', p_release, 'release_number', p_number, 'approval_id', p_approval, 'commit_sha', p_sha),
    'release.approved:synthetic:' || p_key);
$$;
create function pg_temp.consume(p_event bigint) returns text language sql as $$
  select private.consume_release_approved(p_event);
$$;
create function pg_temp.detail(p_event bigint) returns text language sql as $$
  select detail from private.event_consumptions where consumer = 'wpb.final_balance_invoice' and domain_event_id = p_event;
$$;
-- Obligations and final-balance creates for a project (both must stay zero on every rejection).
create function pg_temp.charges(p_project uuid) returns integer language sql as $$
  select ((select count(*) from public.final_balance_invoices where project_id = p_project)
        + (select count(*) from public.outbound_stripe_requests where project_id = p_project
            and purpose = 'final_balance_invoice_create'))::integer;
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

-- ---------------------------------------------------------------------------
-- 1. Positive: the current, approved release (04 §10.2)
-- ---------------------------------------------------------------------------
insert into ids select 'p_ok', pg_temp.ready('XOKAY')::text;
insert into ids select 'r_ok', pg_temp.release(pg_temp.id('p_ok'), repeat('a', 40))::text;
insert into ids select 'a_ok', pg_temp.approve(pg_temp.id('r_ok'))::text;
select ok((select payload ->> 'approval_id' = (select v from ids where k = 'a_ok')
              and payload ->> 'release_number' = '1' and payload ->> 'commit_sha' = repeat('a', 40)
           from public.domain_events where id = pg_temp.wpc_event(pg_temp.id('r_ok'))),
  'WP-C''s approve_preview emits release.approved with the release number, commit SHA, and approval');
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_ok'))), 'created',
  '04 §10.2: the approval of the current release creates the obligation');
select ok((select release_id = pg_temp.id('r_ok') and approval_id = pg_temp.id('a_ok') from public.final_balance_invoices
            where project_id = pg_temp.id('p_ok'))
  and pg_temp.charges(pg_temp.id('p_ok')) = 2,
  'one obligation for that release and approval, and one outbound create');

-- ---------------------------------------------------------------------------
-- 2. Negative: missing release, other project, other approval, mismatched number or SHA
-- ---------------------------------------------------------------------------
insert into ids select 'p_none', pg_temp.ready('XNONE')::text;
insert into ids select 'p_neg', pg_temp.ready('XNEGA')::text;
insert into ids select 'r_neg', pg_temp.release(pg_temp.id('p_neg'), repeat('b', 40))::text;
insert into ids select 'a_neg', pg_temp.approve(pg_temp.id('r_neg'))::text;
-- SYNTHETIC TEST EMISSIONS (consumer defense); WP-C never emits any of these.
insert into ids select 'e_missing', pg_temp.synthetic(pg_temp.id('p_none'), gen_random_uuid(), gen_random_uuid(), 1,
  repeat('b', 40), 'missing')::text;
insert into ids select 'e_project', pg_temp.synthetic(pg_temp.id('p_none'), pg_temp.id('r_neg'), pg_temp.id('a_neg'), 1,
  repeat('b', 40), 'other-project')::text;
insert into ids select 'e_appr_other', pg_temp.synthetic(pg_temp.id('p_neg'), pg_temp.id('r_neg'), pg_temp.id('a_ok'), 1,
  repeat('b', 40), 'other-approval')::text;
insert into ids select 'e_appr_none', pg_temp.synthetic(pg_temp.id('p_neg'), pg_temp.id('r_neg'), gen_random_uuid(), 1,
  repeat('b', 40), 'no-approval')::text;
insert into ids select 'e_number', pg_temp.synthetic(pg_temp.id('p_neg'), pg_temp.id('r_neg'), pg_temp.id('a_neg'), 2,
  repeat('b', 40), 'number')::text;
insert into ids select 'e_sha', pg_temp.synthetic(pg_temp.id('p_neg'), pg_temp.id('r_neg'), pg_temp.id('a_neg'), 1,
  repeat('c', 40), 'sha')::text;
insert into ids select 'e_shape', pg_temp.synthetic(pg_temp.id('p_neg'), pg_temp.id('r_neg'), pg_temp.id('a_neg'), null,
  null, 'no-version')::text;
select is(pg_temp.consume((select v::bigint from ids where k = 'e_missing')), 'rejected', 'a missing release is rejected');
select is(pg_temp.detail((select v::bigint from ids where k = 'e_missing')), 'release_not_found', 'detail: release_not_found');
select is(pg_temp.consume((select v::bigint from ids where k = 'e_project')), 'rejected',
  'another project''s release is rejected (the release row binds the project)');
select is(pg_temp.detail((select v::bigint from ids where k = 'e_project')), 'release_not_found', 'detail: release_not_found');
select is(pg_temp.consume((select v::bigint from ids where k = 'e_appr_other')), 'rejected',
  'an approval of another release is rejected');
select is(pg_temp.detail((select v::bigint from ids where k = 'e_appr_other')), 'approval_not_found', 'detail: approval_not_found');
select is(pg_temp.consume((select v::bigint from ids where k = 'e_appr_none')), 'rejected', 'an unrecorded approval is rejected');
select is(pg_temp.detail((select v::bigint from ids where k = 'e_appr_none')), 'approval_not_found', 'detail: approval_not_found');
select is(pg_temp.consume((select v::bigint from ids where k = 'e_number')), 'rejected', 'a mismatched release number is rejected');
select is(pg_temp.detail((select v::bigint from ids where k = 'e_number')), 'release_version_mismatch',
  'detail: release_version_mismatch (number)');
select is(pg_temp.consume((select v::bigint from ids where k = 'e_sha')), 'rejected', 'a mismatched commit SHA is rejected');
select is(pg_temp.detail((select v::bigint from ids where k = 'e_sha')), 'release_version_mismatch',
  'detail: release_version_mismatch (SHA)');
select is(pg_temp.consume((select v::bigint from ids where k = 'e_shape')), 'rejected',
  'an event without a release number and commit SHA is rejected');
select is(pg_temp.charges(pg_temp.id('p_none')) + pg_temp.charges(pg_temp.id('p_neg')), 0,
  'no obligation and no outbound request for any rejected event');
select ok((select count(*) = 7 from public.audit_events where action = 'release_approval.rejected'
            and target_id in (select v from ids where k like 'e\_%'))
  and (select count(*) = 7 from public.notification_outbox where notification_type = 'payment.final_balance_blocked'
            and idempotency_key in (select 'payment.final_balance_blocked:' || v || ':1' from ids where k like 'e\_%')),
  'each rejection is audited and notified to the Owner');
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_neg'))), 'created',
  'WP-C''s own event for that release still creates the obligation');
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_neg'))), 'already_consumed', 'idempotency is unchanged');

-- ---------------------------------------------------------------------------
-- 3. Negative: superseded and withdrawn releases
-- ---------------------------------------------------------------------------
insert into ids select 'p_sup', pg_temp.ready('XSUPR')::text;
insert into ids select 'r_sup1', pg_temp.release(pg_temp.id('p_sup'), repeat('d', 40))::text;
insert into ids select 'a_sup1', pg_temp.approve(pg_temp.id('r_sup1'))::text;
insert into ids select 'r_sup2', pg_temp.release(pg_temp.id('p_sup'), repeat('e', 40))::text;
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_sup1'))), 'rejected',
  'an approval of a release superseded before consumption is rejected');
select is(pg_temp.detail(pg_temp.wpc_event(pg_temp.id('r_sup1'))), 'release_superseded', 'detail: release_superseded');
select is(pg_temp.charges(pg_temp.id('p_sup')), 0, 'no obligation and no outbound request for a superseded release');
insert into ids select 'a_sup2', pg_temp.approve(pg_temp.id('r_sup2'))::text;
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_sup2'))), 'created', 'the current release''s approval creates it');

insert into ids select 'p_wdr', pg_temp.ready('XWDRN')::text;
insert into ids select 'r_wdr', pg_temp.release(pg_temp.id('p_wdr'), repeat('f', 40))::text;
insert into ids select 'a_wdr', pg_temp.approve(pg_temp.id('r_wdr'))::text;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((public.withdraw_preview(pg_temp.id('r_wdr'), 'Withdrawn for the test') ->> 'ok')::boolean, true,
  'WP-C withdraws the approved release');
reset role;
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_wdr'))), 'rejected',
  'an approval of a release withdrawn before consumption is rejected');
select is(pg_temp.detail(pg_temp.wpc_event(pg_temp.id('r_wdr'))), 'release_withdrawn', 'detail: release_withdrawn');
select is(pg_temp.charges(pg_temp.id('p_wdr')), 0, 'no obligation and no outbound request for a withdrawn release');

-- ---------------------------------------------------------------------------
-- 4. Negative: archived project (OI-92(b))
-- ---------------------------------------------------------------------------
insert into ids select 'p_arc', pg_temp.ready('XARCH')::text;
insert into ids select 'r_arc', pg_temp.release(pg_temp.id('p_arc'), repeat('1', 40))::text;
insert into ids select 'a_arc', pg_temp.approve(pg_temp.id('r_arc'))::text;
update public.projects set archived_at = now() where id = pg_temp.id('p_arc'); -- fixture, as the table owner
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_arc'))), 'rejected', 'an archived project is ineligible');
select is(pg_temp.detail(pg_temp.wpc_event(pg_temp.id('r_arc'))), 'project_archived', 'detail: project_archived');
select is(pg_temp.charges(pg_temp.id('p_arc')), 0, 'no obligation and no outbound request for an archived project');

-- ---------------------------------------------------------------------------
-- 5. Negative: an anomaly that fails G2 (OI-92(d)): an N1(a) attribution conflict
-- ---------------------------------------------------------------------------
insert into ids select 'p_g2', pg_temp.ready('XGTWO')::text;
insert into ids select 'p_gx', pg_temp.paid_project('XGOTH', null)::text;
select pg_temp.initial_invoice(pg_temp.id('p_g2'), 'XGTWO');
insert into ids select 'r_g2', pg_temp.release(pg_temp.id('p_g2'), repeat('2', 40))::text;
insert into ids select 'a_g2', pg_temp.approve(pg_temp.id('r_g2'))::text;
-- A refund whose payment intent is this project's and whose invoice is another project's.
select is(pg_temp.deliver(pg_temp.evt('evt_XGTWOconf01', 'refund.updated', jsonb_build_object('id', 're_XGTWOconf01',
  'object', 'refund', 'amount', 1200, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_XGTWOinit01',
  'invoice', 'in_XGOTH00000', 'metadata', '{}'::jsonb), 10)) ->> 'reason', 'attribution_conflict',
  'the conflicting refund is quarantined');
select ok(not (private.project_financial_status(pg_temp.id('p_g2'))).deposit_verified,
  'the anomaly-aware G2 fails for the project');
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_g2'))), 'rejected', 'a G2 anomaly makes the approval ineligible');
select is(pg_temp.detail(pg_temp.wpc_event(pg_temp.id('r_g2'))), 'deposit_gate_blocked', 'detail: deposit_gate_blocked');
select is(pg_temp.charges(pg_temp.id('p_g2')), 0, 'no obligation and no outbound request under a G2 anomaly');

-- ---------------------------------------------------------------------------
-- 6. C-4 (AUTH-006 Amendment 2): a G4-listed quarantined event, then the authorized resolution
-- ---------------------------------------------------------------------------
-- No card at Checkout; setup-mode recovery (as in 130). A recovery session that reports a charge
-- is quarantined; it concerns the final-balance authorization, so it is listed for G4 only.
insert into ids select 'p_g4', pg_temp.paid_project('XGFOR', null)::text;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'rec', public.begin_payment_method_recovery(pg_temp.id('p_g4')) ->> 'recovery_session_id';
reset role;
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select id from public.outbound_stripe_requests
  where domain_record_id = pg_temp.id('rec'))));
select pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', ''cs_test_XGFORrec01'', false, 200, null, %2$L)',
  (select id from public.outbound_stripe_requests where domain_record_id = pg_temp.id('rec')),
  '{"url": "https://checkout.stripe.com/c/pay/cs_test_XGFORrec01"}'));
select is(pg_temp.deliver(pg_temp.evt('evt_XGFORcharged', 'checkout.session.completed', jsonb_build_object('id', 'cs_test_XGFORrec01',
  'object', 'checkout.session', 'mode', 'setup', 'amount_total', 100, 'customer', 'cus_TXGFOR00000', 'setup_intent', 'seti_XGFOR0001',
  'metadata', jsonb_build_object('project_id', pg_temp.id('p_g4'), 'recovery_session_id', pg_temp.id('rec'))))) ->> 'reason',
  'recovery_session_charged', 'a recovery session that reports a charge is quarantined');
select pg_temp.deliver(pg_temp.evt('evt_XGFORcomplete', 'checkout.session.completed', jsonb_build_object('id', 'cs_test_XGFORrec01',
  'object', 'checkout.session', 'mode', 'setup', 'customer', 'cus_TXGFOR00000', 'setup_intent', 'seti_XGFOR0001',
  'metadata', jsonb_build_object('project_id', pg_temp.id('p_g4'), 'recovery_session_id', pg_temp.id('rec')))));
select pg_temp.svc(format('select public.record_payment_method_lookup(''recovery'', %L, ''pm_XGFORcard02'', ''cus_TXGFOR00000'', false, true)',
  pg_temp.id('rec')));
select pg_temp.accept_intake(pg_temp.id('p_g4'));
select is((private.project_financial_status(pg_temp.id('p_g4'))).evidence -> 'blocking_anomalies',
  '{"G2": [], "G4": ["quarantined_event"]}'::jsonb, 'the quarantined event is listed for G4 only');
insert into ids select 'r_g4a', pg_temp.release(pg_temp.id('p_g4'), repeat('4', 40))::text;
insert into ids select 'a_g4a', pg_temp.approve(pg_temp.id('r_g4a'))::text;
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_g4a'))), 'rejected',
  'C-4: an anomaly listed for G4 makes the approval ineligible');
select is(pg_temp.detail(pg_temp.wpc_event(pg_temp.id('r_g4a'))), 'balance_gate_anomaly', 'C-4: detail balance_gate_anomaly');
select is(pg_temp.charges(pg_temp.id('p_g4')), 0, 'C-4: the G4 rejection creates no obligation and no outbound request');
-- The Owner's authorized reconciliation (aal2, fresh MFA, a reason): it records the review and
-- re-derives the gates from all the evidence.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is((public.resolve_quarantined_event((select id from public.webhook_events where stripe_event_id = 'evt_XGFORcharged'),
  'Reviewed: setup session reported a charge') -> 'gates' -> 'blocking_anomalies'), '{"G2": [], "G4": []}'::jsonb,
  'C-4: after the authorized resolution no anomaly is listed for G4');
reset role;
insert into ids select 'r_g4b', pg_temp.release(pg_temp.id('p_g4'), repeat('5', 40))::text;
insert into ids select 'a_g4b', pg_temp.approve(pg_temp.id('r_g4b'))::text;
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_g4b'))), 'created',
  'C-4: after the authorized resolution, a valid approval proceeds');
select is(pg_temp.charges(pg_temp.id('p_g4')), 2, 'C-4: exactly one obligation and one outbound create');

-- ---------------------------------------------------------------------------
-- 7. Negative: the fulfillment interface not implemented (last: it replaces the interface for
-- the rest of this rolled-back transaction)
-- ---------------------------------------------------------------------------
insert into ids select 'p_nif', pg_temp.ready('XNIFC')::text;
insert into ids select 'r_nif', pg_temp.release(pg_temp.id('p_nif'), repeat('6', 40))::text;
insert into ids select 'a_nif', pg_temp.approve(pg_temp.id('r_nif'))::text;
create or replace function private.project_fulfillment_status(p_project_id uuid) returns private.project_fulfillment_status
language sql stable security definer set search_path = '' as $$
  select row(p_project_id, 1::smallint, false, 'locked'::public.intake_state, false, null::uuid, false, null::uuid,
    false, false, '{}'::public.hold_type[], '{}'::jsonb, false, null::uuid, null::timestamptz)::private.project_fulfillment_status;
$$;
select is(pg_temp.consume(pg_temp.wpc_event(pg_temp.id('r_nif'))), 'rejected',
  'an unimplemented fulfillment interface fails closed');
select is(pg_temp.detail(pg_temp.wpc_event(pg_temp.id('r_nif'))), 'fulfillment_interface_not_ready',
  'detail: fulfillment_interface_not_ready');
select is(pg_temp.charges(pg_temp.id('p_nif')), 0, 'no obligation and no outbound request without the interface');

select * from finish();
rollback;
