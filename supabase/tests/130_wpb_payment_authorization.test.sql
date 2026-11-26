-- WP-B: payment authorization, setup-mode recovery, revocation, and automatic final-balance
-- collection (04 §8, §8.1, §8.2, §10; OI-74, OI-75), including the races between
-- revocation or card detachment and an automatic charge.
-- Covers: T-PAY-13, T-PAY-14, T-PAY-18 to T-PAY-26, T-LC-01 (WP-B side, through WP-C's
-- real intake check). Synthetic events and recorded mock results only (OI-63); no Stripe.
-- Each scenario runs on its own project (client A is a member of every one).
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(79);

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
create function pg_temp.consume() returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v := private.consume_release_approvals(50);
  perform set_config('request.jwt.claims', '', true);
  return v;
end;
$$;
-- AUTH-006 Amendment 2 (revision 2): WP-C-valid release and approval records for the
-- release.approved consumer. The release is recorded by the active Admin (WP-C release_preview is
-- staff-only) and the approval by the project's own non-staff client member (WP-C approve_preview);
-- the test fails unless WP-C's project_fulfillment_status reports both as current. SYNTHETIC TEST
-- EMISSION: the event is written through the WP-0 writer in WP-C's payload shape to exercise the
-- consumer; it never stands in for WP-C's approve_preview, which is unchanged.
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
create function pg_temp.approve(p_project uuid, p_n integer) returns bigint language sql as $$
  select pg_temp.genuine_release_approved(p_project, ('30000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid,
    ('40000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid, 'release.approved:t130:' || p_project || ':' || p_n);
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

-- A project paid through the real workflow: order summary (Owner), acceptance and Checkout
-- (client A), recorded mock results, a verified checkout.session.completed, and, when
-- p_card is set, the server's re-read of the card (attached or not).
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
      case when p_card = 'detached' then 'pm_' || p_tag || 'card01' else p_card end, 'cus_T' || p_tag || '00000',
      p_card <> 'detached'));
  end if;
  return v_project;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Establishment (04 §8, §8.1; T-PAY-18, T-LC-01)
-- ---------------------------------------------------------------------------
insert into ids select 'p_none', pg_temp.paid_project('NONE', null)::text;
select ok(private.project_deposit_verified((select v::uuid from ids where k = 'p_none'))
  and not (private.project_financial_status((select v::uuid from ids where k = 'p_none'))).payment_authorization_ready
  and not private.wpc_intake_unlocked((select v::uuid from ids where k = 'p_none')),
  'T-PAY-18 / T-LC-01: a verified deposit alone (a redirect, a webhook, no card re-read) leaves intake locked');
select is((select count(*)::integer from public.payment_authorizations where project_id = (select v::uuid from ids where k = 'p_none')), 0,
  'T-PAY-18: nothing but the server''s re-read of the card creates an authorization');
select is(pg_temp.svc($$ select public.payment_method_lookups_due() $$) #>> '{initial,0,stripe_checkout_session_id}',
  'cs_test_NONE00000', 'the verified Checkout is listed for the card re-read (invariant 5)');

insert into ids select 'p_det', pg_temp.paid_project('DETA', 'detached')::text;
select ok(not (private.project_financial_status((select v::uuid from ids where k = 'p_det'))).payment_authorization_ready
  and (select payment_method_reusable = false from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p_det'))
  and private.payment_authorization_state((select v::uuid from ids where k = 'p_det')) = 'none'
  and exists (select 1 from public.notification_outbox where notification_type = 'payment.method_recovery_required'),
  'T-PAY-18: a card not attached to the client business''s Customer creates no authorization and offers recovery');

insert into ids select 'p_ok', pg_temp.paid_project('OKAY', 'pm_OKAYcard01')::text;
select ok((select status = 'active' and stripe_payment_method_id = 'pm_OKAYcard01' and authorized_balance_cents = 64000
             and acceptance_id is not null and order_summary_id is not null and evidence_webhook_event_id is not null
           from public.payment_authorizations where project_id = (select v::uuid from ids where k = 'p_ok')),
  '04 §8.1: an active authorization references the acceptance, the snapshot balance, and the verified event');
select ok((private.project_financial_status((select v::uuid from ids where k = 'p_ok'))).payment_authorization_ready
  and (private.project_financial_status((select v::uuid from ids where k = 'p_ok'))).payment_authorization_state = 'active'
  and (private.project_financial_status((select v::uuid from ids where k = 'p_ok'))).contract_version = 3
  and private.wpc_intake_unlocked((select v::uuid from ids where k = 'p_ok')),
  'T-LC-01: deposit verified and an active authorization unlock WP-C intake through the interface');
select is((select count(*)::integer from public.payment_authorization_events e join public.payment_authorizations a on a.id = e.payment_authorization_id
           where a.project_id = (select v::uuid from ids where k = 'p_ok') and e.event = 'established'), 1, 'the history records the establishment');
select is(pg_temp.svc(format('select public.record_payment_method_lookup(''initial'', %L, ''pm_OTHERcard9'', ''cus_TOKAY00000'', false, true)',
  (select id from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p_ok')))) ->> 'already', 'true',
  'a repeated re-read changes nothing');
select is(pg_temp.svc(format('select public.record_payment_method_lookup(''initial'', %L, ''pm_X1234567'', ''cus_TNONE00000'', true, true)',
  (select id from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p_none')))) ->> 'error', 'livemode_mismatch',
  'a live-mode re-read is refused outside production');
select ok(not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'payment_authorizations'
  and column_name ~ '(card|last4|brand|exp|cvc|number)'), '04 §8.1: no card data, brand, or last four digits is stored');

-- ---------------------------------------------------------------------------
-- 2. Isolation and visibility (T-PAY-23, OI-72)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((select count(*)::integer from public.payment_authorizations) + (select count(*)::integer from public.payment_authorization_events)
  + (select count(*)::integer from public.recovery_sessions), 0, 'T-PAY-23: Admin reads no authorization or recovery record');
select is((select payment_recovery_required from public.operational_payment_states(array[(select v::uuid from ids where k = 'p_none')])), true,
  'T-PAY-23 / OI-72: Admin sees only the derived state (payment recovery required)');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(public.begin_payment_method_recovery((select v::uuid from ids where k = 'p_none')) ->> 'error', 'not_found',
  'T-PAY-23: another tenant cannot start recovery for this project');
select is(public.revoke_payment_authorization((select v::uuid from ids where k = 'p_ok'), 'x') ->> 'error', 'not_found',
  'T-PAY-23: another tenant cannot revoke this authorization');
select is((select count(*)::integer from public.payment_authorizations), 0, 'T-PAY-23: another tenant reads nothing');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.begin_payment_method_recovery((select v::uuid from ids where k = 'p_none')) ->> 'error', 'not_found',
  'staff cannot start a client''s recovery');
reset role;

-- ---------------------------------------------------------------------------
-- 3. Card-only Checkout and setup-mode recovery (T-PAY-24, T-PAY-20)
-- ---------------------------------------------------------------------------
select ok((select bool_and(request_params -> 'allowed_payment_method_types' = '["card"]'::jsonb)
           from public.outbound_stripe_requests where purpose = 'checkout_session_create'),
  'T-PAY-24: every initial Checkout Session is created card only');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'rec1', public.begin_payment_method_recovery((select v::uuid from ids where k = 'p_none')) ->> 'recovery_session_id';
select is(public.begin_payment_method_recovery((select v::uuid from ids where k = 'p_none')) ->> 'recovery_session_id',
  (select v from ids where k = 'rec1'), 'a double click returns the same open recovery session');
select is(public.begin_payment_method_recovery((select v::uuid from ids where k = 'p_ok')) ->> 'error', 'authorization_active',
  'no recovery while the authorization is active');
reset role;
select ok((select request_params ->> 'mode' = 'setup' and request_params -> 'allowed_payment_method_types' = '["card"]'::jsonb
             and not request_params ? 'line_items' and not request_params ? 'payment_intent_data'
           from public.outbound_stripe_requests where domain_record_id = (select v::uuid from ids where k = 'rec1')),
  'T-PAY-24 / T-PAY-20: recovery is a setup-mode, card-only session with no line items: it never charges');
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select id from public.outbound_stripe_requests
  where domain_record_id = (select v::uuid from ids where k = 'rec1')))) ->> 'customer', 'cus_TNONE00000',
  'recovery uses the client business''s existing Customer');
select is(pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', ''cs_test_RECV00001'', false, 200, null, %2$L)',
  (select id from public.outbound_stripe_requests where domain_record_id = (select v::uuid from ids where k = 'rec1')),
  '{"url": "https://checkout.stripe.com/c/pay/cs_test_RECV00001"}')) ->> 'status', 'succeeded', 'the recovery session opens');
select is(pg_temp.deliver(pg_temp.evt('evt_RECVcharged1', 'checkout.session.completed', jsonb_build_object('id', 'cs_test_RECV00001',
  'object', 'checkout.session', 'mode', 'setup', 'amount_total', 100, 'customer', 'cus_TNONE00000', 'setup_intent', 'seti_RECV000001',
  'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p_none'), 'recovery_session_id', (select v from ids where k = 'rec1'))))) ->> 'reason',
  'recovery_session_charged', 'T-PAY-20: a recovery session that reports a charge is quarantined');
select is(pg_temp.deliver(pg_temp.evt('evt_RECVcomplete', 'checkout.session.completed', jsonb_build_object('id', 'cs_test_RECV00001',
  'object', 'checkout.session', 'mode', 'setup', 'customer', 'cus_TNONE00000', 'setup_intent', 'seti_RECV000001',
  'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p_none'), 'recovery_session_id', (select v from ids where k = 'rec1'))))) ->> 'status',
  'processed', 'the setup-mode completion is processed');
select ok(not (private.project_financial_status((select v::uuid from ids where k = 'p_none'))).payment_authorization_ready,
  'invariant 5: the completion event alone does not activate a card; the server re-reads it first');
select is(pg_temp.svc(format('select public.record_payment_method_lookup(''recovery'', %L, ''pm_NONEcard02'', ''cus_TNONE00000'', false, true)',
  (select v from ids where k = 'rec1'))) ->> 'applied', 'true', 'the verified replacement card is applied');
select ok((private.project_financial_status((select v::uuid from ids where k = 'p_none'))).payment_authorization_ready
  and private.wpc_intake_unlocked((select v::uuid from ids where k = 'p_none')),
  'T-PAY-20: the recovered card makes the authorization active and unlocks intake');

-- ---------------------------------------------------------------------------
-- 4. Automatic collection on approval (T-PAY-13, T-PAY-21, T-PAY-26)
-- ---------------------------------------------------------------------------
select pg_temp.approve((select v::uuid from ids where k = 'p_ok'), n) from generate_series(1, 5) n;
select is((select count(*)::integer from jsonb_array_elements(pg_temp.consume() -> 'results') r where r ->> 'outcome' = 'created'), 1,
  'T-PAY-21: five approvals (repeats and revisions) create exactly one obligation');
select ok((select count(*) = 1 from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_ok'))
  and (select count(*) = 1 from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_ok')
         and purpose = 'final_balance_invoice_create'),
  'T-PAY-21: exactly one outbound request row and one final-balance invoice');
insert into ids select 'fbi_ok', id::text from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_ok');
insert into ids select 'req_ok', id::text from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_ok')
  and purpose = 'final_balance_invoice_create';
select ok((select collection_mode = 'automatic' and default_payment_method_id = 'pm_OKAYcard01' and amount_cents = 64000
           from public.final_balance_invoices where id = (select v::uuid from ids where k = 'fbi_ok'))
  and (select request_params ->> 'collection_method' = 'charge_automatically' and request_params -> 'auto_advance' = 'true'::jsonb
         and request_params ->> 'default_payment_method' = 'pm_OKAYcard01'
         and request_params -> 'lines' = '[{"price": "price_1Uf5HyK5j4r4WkVPfrkvOv7h", "quantity": 1}]'::jsonb
       from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_ok')),
  'T-PAY-13 / T-PAY-26: automatic collection names the authorization''s card explicitly, sets auto_advance, single balance line');
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'req_ok'))) ->> 'purpose',
  'final_balance_invoice_create', 'the executor claims the automatic create');
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'req_ok'))) ->> 'error',
  'already_claimed', 'T-PAY-21: a concurrent executor cannot send it again');
select is(pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', ''in_OKAYfinal01'', false, 200, null, %2$L)',
  (select v from ids where k = 'req_ok'), '{"hosted_invoice_url": "https://invoice.stripe.com/i/acct_test/in_OKAYfinal01"}')) ->> 'status',
  'succeeded', 'the automatically collected invoice is created');
create temporary table inv (k text primary key, body jsonb) on commit drop;
grant all on inv to service_role;
insert into inv select 'ok', jsonb_build_object('id', 'in_OKAYfinal01', 'object', 'invoice', 'billing_reason', 'manual', 'currency', 'usd',
  'amount_paid', 64000, 'customer', 'cus_TOKAY00000', 'default_payment_method', 'pm_OKAYcard01', 'payment_intent', 'pi_OKAYfinal01',
  'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p_ok'),
    'order_summary_id', (select order_summary_id from public.final_balance_invoices where id = (select v::uuid from ids where k = 'fbi_ok')),
    'final_balance_invoice_id', (select v from ids where k = 'fbi_ok')),
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
    'pricing', jsonb_build_object('price_details', jsonb_build_object('price', 'price_1Uf5HyK5j4r4WkVPfrkvOv7h'))))));
select is(pg_temp.deliver(pg_temp.evt('evt_OKAYwrongpm1', 'invoice.paid', (select body from inv where k = 'ok')
  || '{"default_payment_method": "pm_SOMEONEELSE"}', 10)) ->> 'reason', 'payment_method_mismatch',
  'T-PAY-26: a payment on any card other than the authorization''s is quarantined');
select is(pg_temp.deliver(pg_temp.evt('evt_OKAYfail0001', 'invoice.payment_failed', (select body from inv where k = 'ok'), 20)) ->> 'status',
  'processed', 'T-PAY-14: a failed automatic charge is processed');
select ok(private.project_final_balance_state((select v::uuid from ids where k = 'p_ok')) = 'failed'
  and private.payment_authorization_state((select v::uuid from ids where k = 'p_ok')) = 'payment_method_unavailable'
  and not private.project_balance_verified((select v::uuid from ids where k = 'p_ok'))
  and (select count(*) = 1 from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_ok')),
  'T-PAY-14: the balance stays unverified (G4 blocks publication), the card is unavailable, and no new invoice exists');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.project_billing_status((select v::uuid from ids where k = 'p_ok')) ->> 'final_invoice_url',
  'https://invoice.stripe.com/i/acct_test/in_OKAYfinal01', 'T-PAY-14: the same invoice''s hosted page is the completion path');
reset role;
select is(pg_temp.deliver(pg_temp.evt('evt_OKAYaction01', 'invoice.payment_action_required', (select body from inv where k = 'ok'), 30)) ->> 'status',
  'processed', 'T-PAY-14: authentication required is processed');
select is(private.project_final_balance_state((select v::uuid from ids where k = 'p_ok'))::text, 'pending',
  'the invoice awaits completion on its hosted page');
select is(pg_temp.deliver(pg_temp.evt('evt_OKAYpaid0001', 'invoice.paid', (select body from inv where k = 'ok'), 40)) ->> 'status',
  'processed', 'T-PAY-13: the verified invoice.paid is processed');
select ok(private.project_balance_verified((select v::uuid from ids where k = 'p_ok'))
  and (select count(*) = 1 from public.ledger_entries where project_id = (select v::uuid from ids where k = 'p_ok')
         and entry_type = 'balance_charge' and amount_cents = 64000),
  'T-PAY-13 / T-PAY-26: the balance is verified only from the webhook, for exactly the authorized snapshot balance');
select is(pg_temp.deliver(pg_temp.evt('evt_OKAYfail0002', 'invoice.payment_failed', (select body from inv where k = 'ok'), 5)) ->> 'status',
  'ignored', 'T-ARC-03: a late failure after payment is ignored');

-- AUTH-006 Amendment 2, Disposition B1: a legitimate Owner reconciliation of the T-PAY-26 quarantined
-- payment through the existing audited procedure (Owner, aal2, fresh MFA, live session, a reason). It records
-- the review and re-derives the gates from all the evidence; no anomaly rule changes and nothing is bypassed.
-- Afterwards no anomaly is listed for G4, which the release-approval cross-check requires (04 §10.2).
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true, true);
select public.resolve_quarantined_event((select id from public.webhook_events where stripe_event_id = 'evt_OKAYwrongpm1'),
  'Reviewed: payment on another card');
reset role;
-- T-PAY-22: after a verified final payment, nothing creates, retries, or re-attempts a charge.
select pg_temp.approve((select v::uuid from ids where k = 'p_ok'), 6);
select is(pg_temp.consume() #>> '{results,0,outcome}', 'duplicate_obligation', 'T-PAY-22: a later approval creates nothing');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.retry_final_balance_invoice((select v::uuid from ids where k = 'fbi_ok'), 'redeploy') ->> 'error', 'not_retryable',
  'T-PAY-22: a paid invoice can never be retried');
reset role;
select is((select count(*)::integer from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_ok')
  and status = 'pending' and purpose = 'final_balance_invoice_create'), 0, 'T-PAY-22: no outbound charge request is pending after payment');
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select id from public.outbound_stripe_requests
  where project_id = (select v::uuid from ids where k = 'p_ok') and purpose = 'final_balance_invoice_disable_auto'))) ->> 'error',
  'not_needed', 'the stop request queued after the failed charge is dropped once the invoice is paid');
select ok(not (select charged_after_halt from public.final_balance_invoices where id = (select v::uuid from ids where k = 'fbi_ok')),
  'a hosted-page completion after a failed automatic charge is the expected path, not an Owner review item');
select is(private.project_final_balance_state((select v::uuid from ids where k = 'p_ok'))::text, 'verified', 'T-PAY-22: the paid state is kept');

-- ---------------------------------------------------------------------------
-- 5. Revocation (T-PAY-25, T-PAY-19)
-- ---------------------------------------------------------------------------
insert into ids select 'p_rev', pg_temp.paid_project('REVK', 'pm_REVKcard01')::text;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.record_payment_authorization_revocation((select v::uuid from ids where k = 'p_rev'), 'x') ->> 'error', 'forbidden',
  'Admin cannot record a revocation');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1', 'aal1', false, false);
select is(public.revoke_payment_authorization((select v::uuid from ids where k = 'p_rev'), 'Changing banks') ->> 'error',
  'reauthentication_required', 'T-PAY-25: client revocation needs fresh reauthentication');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1', 'aal1', false, true);
select is(public.revoke_payment_authorization((select v::uuid from ids where k = 'p_rev'), 'Changing banks') ->> 'ok', 'true',
  'T-PAY-25: the authorized signer revokes with fresh reauthentication');
select is(public.revoke_payment_authorization((select v::uuid from ids where k = 'p_rev'), 'again') ->> 'existing', 'true',
  'a repeated revocation changes nothing');
reset role;
select ok((select status = 'revoked' and revocation_source = 'client' and revoked_at is not null
           from public.payment_authorizations where project_id = (select v::uuid from ids where k = 'p_rev'))
  and exists (select 1 from public.audit_events where action = 'payment_authorization.revoked' and category = 'financial')
  and exists (select 1 from public.notification_outbox where notification_type = 'payment.authorization_revoked' and recipient_roles = '{owner}')
  and private.project_owner_intervention_required((select v::uuid from ids where k = 'p_rev')),
  'T-PAY-25: the revocation is recorded, audited, and opens an Owner review item');
select throws_ok(format($$ update public.payment_authorizations set status = 'active' where project_id = %L $$, (select v from ids where k = 'p_rev')),
  '42501', null, 'T-PAY-25: a revoked authorization is final in the database');
select is(pg_temp.deliver(pg_temp.evt('evt_REVKdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_REVKcard01', 'object', 'payment_method'))) ->> 'status',
  'ignored', 'T-PAY-25: a late event about the revoked card changes nothing');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.begin_payment_method_recovery((select v::uuid from ids where k = 'p_rev')) ->> 'error', 'new_acceptance_required',
  '04 §8.1: re-establishing after revocation needs a new acceptance first');
reset role;
select is(private.payment_authorization_state((select v::uuid from ids where k = 'p_rev')), 'revoked', 'T-PAY-25: still revoked');
select pg_temp.approve((select v::uuid from ids where k = 'p_rev'), 7);
select is(pg_temp.consume() #>> '{results,0,outcome}', 'created', 'the approval still creates the single obligation');
select ok((select collection_mode = 'hosted_only' and default_payment_method_id is null from public.final_balance_invoices
           where project_id = (select v::uuid from ids where k = 'p_rev'))
  and (select request_params -> 'auto_advance' = 'false'::jsonb and not request_params ? 'default_payment_method'
       from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_rev') and purpose = 'final_balance_invoice_create'),
  'T-PAY-19 / T-PAY-25: after revocation no automatic attempt is made; the invoice is payable only on its hosted page');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.review_authorization_revocation((select v::uuid from ids where k = 'p_rev'), 'Client will pay on the hosted page') ->> 'ok',
  'true', 'the Owner records the revocation review');
reset role;

-- ---------------------------------------------------------------------------
-- 6. Races with automatic collection (04 §8.1, §10)
-- ---------------------------------------------------------------------------
-- (a) Revocation before the automatic create is sent: the claim supersedes it with a
--     hosted-only attempt on the same invoice record; no automatic charge is ever sent.
insert into ids select 'p_ra', pg_temp.paid_project('RACA', 'pm_RACAcard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'p_ra'), 8);
select pg_temp.consume();
insert into ids select 'req_ra', id::text from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_ra')
  and purpose = 'final_balance_invoice_create';
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.record_payment_authorization_revocation((select v::uuid from ids where k = 'p_ra'), 'Written notice from the client') ->> 'ok',
  'true', 'the Owner records a revocation received in writing');
reset role;
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'req_ra'))) ->> 'error',
  'superseded', 'race (a): the claim refuses to send the automatic charge');
select ok((select status = 'failed' and error_code = 'authorization_changed' from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'req_ra'))
  and (select count(*) = 1 from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_ra')
         and purpose = 'final_balance_invoice_create' and status = 'pending' and request_params -> 'auto_advance' = 'false'::jsonb)
  and (select count(*) = 1 from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_ra')
         and collection_mode = 'hosted_only'),
  'race (a): one hosted-only attempt replaces it, on the same single invoice record');

-- (b) Card detached while the automatic create is in flight: when its result arrives, a
--     request disabling automatic collection is queued for the invoice that now exists.
insert into ids select 'p_rb', pg_temp.paid_project('RACB', 'pm_RACBcard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'p_rb'), 9);
select pg_temp.consume();
insert into ids select 'req_rb', id::text from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_rb')
  and purpose = 'final_balance_invoice_create';
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'req_rb'))) ->> 'purpose',
  'final_balance_invoice_create', 'race (b): the automatic create is claimed and in flight');
select is(pg_temp.deliver(pg_temp.evt('evt_RACBdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_RACBcard01', 'object', 'payment_method'))) ->> 'status',
  'processed', 'race (b): the card is detached meanwhile');
select ok(private.payment_authorization_state((select v::uuid from ids where k = 'p_rb')) = 'payment_method_unavailable'
  and (select automatic_stop_required and collection_mode = 'hosted_only' from public.final_balance_invoices
       where project_id = (select v::uuid from ids where k = 'p_rb')),
  'T-PAY-20: detachment makes the authorization unavailable and halts automatic collection');
select is(pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', ''in_RACBfinal01'', false, 200, null, ''{}'')',
  (select v from ids where k = 'req_rb'))) ->> 'status', 'succeeded', 'race (b): the in-flight create completes');
insert into ids select 'stop_rb', id::text from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_rb')
  and purpose = 'final_balance_invoice_disable_auto';
select ok((select status = 'pending' and request_params ->> 'invoice' = 'in_RACBfinal01' and request_params -> 'auto_advance' = 'false'::jsonb
           from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'stop_rb')),
  'race (b): a request disabling automatic collection is queued for that invoice');
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'stop_rb'))) ->> 'purpose',
  'final_balance_invoice_disable_auto', 'the stop request is executed');
select is(pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', ''in_RACBfinal01'', false, 200, null, ''{}'')',
  (select v from ids where k = 'stop_rb'))) ->> 'status', 'succeeded', 'automatic collection is disabled');
-- Stripe charged before the stop took effect: the payment is verified (Stripe is
-- authoritative), and goes to Owner review.
select is(pg_temp.deliver(pg_temp.evt('evt_RACBpaid0001', 'invoice.paid', jsonb_build_object('id', 'in_RACBfinal01', 'object', 'invoice',
  'billing_reason', 'manual', 'currency', 'usd', 'amount_paid', 64000, 'customer', 'cus_TRACB00000', 'default_payment_method', 'pm_RACBcard01',
  'metadata', jsonb_build_object('project_id', (select v from ids where k = 'p_rb'),
    'order_summary_id', (select order_summary_id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_rb')),
    'final_balance_invoice_id', (select id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_rb'))),
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HyK5j4r4WkVPfrkvOv7h'))))), 50)) ->> 'status',
  'processed', 'race (b): a charge that landed before the stop is processed');
select ok(private.project_balance_verified((select v::uuid from ids where k = 'p_rb'))
  and (select charged_after_halt from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'p_rb'))
  and exists (select 1 from public.notification_outbox where notification_type = 'payment.charged_after_halt')
  and private.project_owner_intervention_required((select v::uuid from ids where k = 'p_rb')),
  'race (b): it is verified exactly once and flagged for Owner review');

-- (c) Detachment after the automatic invoice exists: the stop request is queued at once.
insert into ids select 'p_rc', pg_temp.paid_project('RACC', 'pm_RACCcard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'p_rc'), 10);
select pg_temp.consume();
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select id from public.outbound_stripe_requests
  where project_id = (select v::uuid from ids where k = 'p_rc') and purpose = 'final_balance_invoice_create')));
select pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', ''in_RACCfinal01'', false, 200, null, ''{}'')',
  (select id from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_rc') and purpose = 'final_balance_invoice_create')));
select is(pg_temp.deliver(pg_temp.evt('evt_RACCdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_RACCcard01', 'object', 'payment_method'))) ->> 'status',
  'processed', 'race (c): detachment after the invoice exists is processed');
select is((select count(*)::integer from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_rc')
  and purpose = 'final_balance_invoice_disable_auto' and status = 'pending' and request_params ->> 'invoice' = 'in_RACCfinal01'), 1,
  'race (c): one stop request is queued immediately');
select is(pg_temp.deliver(pg_temp.evt('evt_RACCdetach02', 'payment_method.detached', jsonb_build_object('id', 'pm_RACCcard01', 'object', 'payment_method'))) ->> 'status',
  'processed', 'a replayed detachment is processed');
select is((select count(*)::integer from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'p_rc')
  and purpose = 'final_balance_invoice_disable_auto'), 1, 'a replayed detachment queues nothing more');
select throws_ok(format($$ update public.final_balance_invoices set collection_mode = 'automatic' where project_id = %L $$,
  (select v from ids where k = 'p_rc')), '42501', null, 'automatic collection can never be re-enabled on a halted invoice');

-- ---------------------------------------------------------------------------
-- 7. OI-75: the maintenance subscription's payment method is never written
-- ---------------------------------------------------------------------------
select is_empty($$ select id from public.outbound_stripe_requests
                   where request_params ?| array['subscription', 'default_source', 'invoice_settings']
                      or (purpose <> 'final_balance_invoice_create' and request_params ? 'default_payment_method') $$,
  'T-PAY-20 / OI-75: no outbound request writes a subscription, a Customer default, or an invoice setting; only the final-balance invoice names a card');
select is_empty($$ select unnest(enum_range(null::public.outbound_request_purpose))::text p
                   except select unnest(array['customer_create', 'checkout_session_create', 'final_balance_invoice_create',
                     'recovery_session_create', 'final_balance_invoice_disable_auto']) $$,
  'T-PAY-24 / OI-75: the only Stripe writes are these five purposes (no PaymentIntent, charge, or subscription update)');

select * from finish();
rollback;
