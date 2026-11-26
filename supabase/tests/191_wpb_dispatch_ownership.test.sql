-- WP-B (AUTH-009, OI-91): dispatch ownership, confirmation and lock order. The claim token (A2),
-- dispatch confirmation (A3), recording order and outcomes (A1, R1: pending, token, livemode,
-- confirmation; unconfirmed and late results; resubmission), legacy claims and the guard, the
-- eligibility re-check at confirmation, automatic-stop reconciliation, OI-92(e) detection, and the
-- signatures, privileges and function settings. The two-connection lock-order proofs are in
-- tests/integration/oi91-dispatch-revocation.test.ts. Synthetic data only; no Stripe request.
-- Claim tokens are test-local: they are never printed, returned by a helper or asserted by value.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(71);

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
    ('40000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid, 'release.approved:t191:' || p_project || ':' || p_n);
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



-- Links the initial charge's payment intent (as Stripe's initial invoice.paid does).
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
-- The final-balance invoice body Stripe would send for a project (hosted or automatic).
create function pg_temp.final_body(p_project uuid, p_tag text) returns jsonb language sql as $$
  select jsonb_build_object('id', 'in_' || p_tag || 'final01', 'object', 'invoice', 'billing_reason', 'manual', 'currency', 'usd',
    'amount_paid', f.amount_cents, 'customer', 'cus_T' || p_tag || '00000', 'payment_intent', 'pi_' || p_tag || 'final01',
    'default_payment_method', f.default_payment_method_id,
    'metadata', jsonb_build_object('project_id', p_project, 'order_summary_id', f.order_summary_id, 'final_balance_invoice_id', f.id),
    'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
      'price', jsonb_build_object('id', 'price_1Uf5HyK5j4r4WkVPfrkvOv7h')))))
  from public.final_balance_invoices f where f.project_id = p_project;
$$;
-- Approval → the single invoice create (claimed and recorded with p_outcome).
create function pg_temp.final_created(p_project uuid, p_tag text, p_n integer, p_outcome text default 'succeeded')
returns uuid language plpgsql as $$
declare
  v_req uuid;
begin
  perform pg_temp.approve(p_project, p_n);
  perform pg_temp.consume();
  select id into v_req from public.outbound_stripe_requests where project_id = p_project and purpose = 'final_balance_invoice_create'
   and status = 'pending';
  perform pg_temp.svc(format('select public.outbound_request_for_execution(%L)', v_req));
  if p_outcome = 'succeeded' then
    perform pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), ''succeeded'', %2$L, false, 200, null, ''{}'')', v_req,
      'in_' || p_tag || 'final01'));
  else
    perform pg_temp.svc(format('select public.record_outbound_result(%1$L, pg_temp.token(%1$L), %2$L, null, null, null, ''network_timeout'', ''{}'')', v_req, p_outcome));
  end if;
  return v_req;
end;
$$;
create function pg_temp.refund(p_id text, p_re text, p_amount jsonb, p_pi text, p_status text default 'succeeded',
  p_offset integer default 0, p_currency text default 'usd') returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'refund.updated', jsonb_build_object('id', p_re, 'object', 'refund', 'amount', p_amount,
    'currency', p_currency, 'status', p_status, 'payment_intent', p_pi, 'metadata', '{}'::jsonb), p_offset));
$$;
create function pg_temp.dispute(p_id text, p_dp text, p_amount jsonb, p_pi text, p_status text, p_offset integer default 0,
  p_currency text default 'usd') returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'charge.dispute.' || case when p_status in ('won', 'lost') then 'closed' else 'created' end,
    jsonb_build_object('id', p_dp, 'object', 'dispute', 'amount', p_amount, 'currency', p_currency, 'status', p_status,
      'payment_intent', p_pi), p_offset));
$$;
-- WP-B's interface for G2 and G4, and WP-C's evaluator result for a gate ('passed' or its reason).
create function pg_temp.g(p_project uuid) returns text language sql as $$
  select row(s.deposit_verified, s.balance_verified_or_settled)::text from private.project_financial_status(p_project) s;
$$;
create function pg_temp.anomalies(p_project uuid) returns jsonb language sql as $$
  select (private.project_financial_status(p_project)).evidence -> 'blocking_anomalies';
$$;
create function pg_temp.gate(p_project uuid, p_gate text) returns text language sql as $$
  select case when (g ->> 'passed')::boolean then 'passed' else g ->> 'reason' end
    from jsonb_array_elements(private.evaluate_publication_gates(p_project, null) -> 'gates') g where g ->> 'gate' = p_gate;
$$;
create function pg_temp.eligible(p_project uuid) returns boolean language sql as $$
  select (private.evaluate_publication_gates(p_project, null) ->> 'eligible')::boolean;
$$;
create function pg_temp.owner_do(p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
  execute p_sql into v;
  reset role;
  return v;
end;
$$;
create function pg_temp.evt_id(p_stripe_event_id text) returns bigint language sql as $$
  select id from public.webhook_events where stripe_event_id = p_stripe_event_id;
$$;
create function pg_temp.fbi(p_project uuid) returns uuid language sql as $$
  select id from public.final_balance_invoices where project_id = p_project;
$$;
create function pg_temp.reconcile(p_project uuid, p_key text, p_stripe jsonb) returns integer language plpgsql as $$
declare
  v_run uuid;
  v integer;
begin
  perform pg_temp.as_service();
  v_run := public.start_reconciliation_run('mocked_gateway', p_key);
  v := public.record_project_reconciliation(v_run, p_project, p_stripe);
  perform public.complete_reconciliation_run(v_run);
  reset role;
  return v;
end;
$$;
-- AUTH-009 helpers. A claim without confirmation keeps its token test-locally; confirm and
-- record take the token by reference. No helper returns or prints a token.
create function pg_temp.claim_only(p_request_id uuid) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_service();
  v := public.outbound_request_for_execution(p_request_id);
  if v ? 'claim_token' then
    insert into claim_tokens values (p_request_id, (v ->> 'claim_token')::uuid);
  end if;
  reset role;
  return v - 'claim_token';
end;
$$;
create function pg_temp.confirm(p_request_id uuid, p_token uuid) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_service();
  v := public.confirm_outbound_dispatch(p_request_id, p_token);
  reset role;
  return v;
end;
$$;
create function pg_temp.rec(p_request_id uuid, p_token uuid, p_outcome text, p_object text, p_livemode boolean,
  p_http integer, p_code text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.as_service();
  v := public.record_outbound_result(p_request_id, p_token, p_outcome, p_object, p_livemode, p_http, p_code, '{}');
  reset role;
  return v;
end;
$$;
-- A project whose Customer and Checkout creates are pending and unclaimed.
create function pg_temp.checkout_project(p_tag text) returns uuid language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
  v_os uuid;
  v_acc uuid;
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
  perform public.begin_initial_checkout(v_project);
  reset role;
  return v_project;
end;
$$;
create function pg_temp.req(p_project uuid, p_purpose text) returns uuid language sql as $$
  select id from public.outbound_stripe_requests where project_id = p_project and purpose::text = p_purpose
   order by attempt desc limit 1;
$$;
create function pg_temp.notes(p_type text, p_key text) returns integer language sql as $$
  select count(*)::int from public.notification_outbox where notification_type = p_type and idempotency_key like p_key || '%';
$$;
-- Fabricated claimed requests (fixtures only): a chosen claim time, the hash of a known token or
-- none (a claim made before AUTH-009). Inserted directly; the guard governs updates.
create function pg_temp.fabricate(p_project uuid, p_claimed_ago interval, p_token uuid, p_confirmed boolean) returns uuid
language sql as $$
  insert into public.outbound_stripe_requests (purpose, project_id, domain_record_type, domain_record_id, attempt,
    idempotency_key, claimed_at, claim_token_sha256, dispatch_confirmed_at)
  values ('customer_create', p_project, 'client_business', gen_random_uuid(), 1,
    'wpb-customer-' || gen_random_uuid()::text || '-a1', now() - p_claimed_ago,
    case when p_token is not null then encode(sha256(convert_to(p_token::text, 'UTF8')), 'hex') end,
    case when p_confirmed then now() - p_claimed_ago + interval '10 seconds' end)
  returning id;
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1. Signatures and privileges (A1, A3; grant: privileges)
-- ---------------------------------------------------------------------------
select ok(to_regprocedure('private.record_outbound_result(uuid, text, text, boolean, integer, text, jsonb)') is null
  and to_regprocedure('public.record_outbound_result(uuid, text, text, boolean, integer, text, jsonb)') is null,
  'the obsolete seven-argument record_outbound_result signatures are dropped');
select is((select array_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' order by n.nspname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.proname = 'record_outbound_result'),
  array['private.record_outbound_result(p_request_id uuid, p_claim_token uuid, p_outcome text, p_stripe_object_id text, p_livemode boolean, p_http_status integer, p_error_code text, p_details jsonb)',
        'public.record_outbound_result(p_request_id uuid, p_claim_token uuid, p_outcome text, p_stripe_object_id text, p_livemode boolean, p_http_status integer, p_error_code text, p_details jsonb)'],
  'A1: the claim token is the second parameter, of type uuid; no other overload exists');
select is((select array_agg(n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' order by n.nspname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.proname = 'confirm_outbound_dispatch'),
  array['private.confirm_outbound_dispatch(p_request_id uuid, p_claim_token uuid)',
        'public.confirm_outbound_dispatch(p_request_id uuid, p_claim_token uuid)'],
  'A3: confirm_outbound_dispatch(uuid, uuid), private and its wrapper');
select is((select array_agg(p.oid::regprocedure::text || ':' || r.rolname order by p.oid::regprocedure::text, r.rolname)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join (values ('service_role'), ('authenticated'), ('anon')) r(rolname)
  where n.nspname in ('public', 'private') and p.proname in ('record_outbound_result', 'confirm_outbound_dispatch')
    and has_function_privilege(r.rolname, p.oid, 'execute')),
  array['confirm_outbound_dispatch(uuid,uuid):service_role', 'private.confirm_outbound_dispatch(uuid,uuid):service_role',
        'private.record_outbound_result(uuid,uuid,text,text,boolean,integer,text,jsonb):service_role',
        'record_outbound_result(uuid,uuid,text,text,boolean,integer,text,jsonb):service_role'],
  'the new signatures are executable by service_role only (not authenticated, not anon)');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('public', 'private') and p.proname in ('record_outbound_result', 'confirm_outbound_dispatch',
    'note_final_balance_release_change') and has_function_privilege('public', p.oid, 'execute')),
  'PUBLIC executes none of them');
select ok(not has_function_privilege('service_role', 'private.note_final_balance_release_change(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.note_final_balance_release_change(uuid)', 'execute')
  and not has_function_privilege('anon', 'private.note_final_balance_release_change(uuid)', 'execute')
  and to_regprocedure('public.note_final_balance_release_change(uuid)') is null,
  'the release-change detection is internal: no wrapper, no API role');
select ok(has_function_privilege('authenticated', 'public.reconcile_outbound_request(uuid, boolean, text, text)', 'execute')
  and has_function_privilege('authenticated', 'private.reconcile_outbound_request(uuid, boolean, text, text)', 'execute')
  and not has_function_privilege('anon', 'public.reconcile_outbound_request(uuid, boolean, text, text)', 'execute'),
  'grant: reconcile_outbound_request keeps its authenticated grant (Owner and fresh MFA are checked inside)');
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('outbound_request_for_execution', 'confirm_outbound_dispatch',
    'record_outbound_result', 'reconcile_outbound_request', 'handle_invoice_failed', 'handle_final_balance_paid',
    'note_final_balance_release_change', 'record_project_reconciliation', 'project_financial_anomalies')
    and p.prosecdef and 'search_path=""' = any(p.proconfig)),
  array['confirm_outbound_dispatch', 'handle_final_balance_paid', 'handle_invoice_failed', 'note_final_balance_release_change',
        'outbound_request_for_execution', 'project_financial_anomalies', 'reconcile_outbound_request',
        'record_outbound_result', 'record_project_reconciliation'],
  'every changed and new private function is SECURITY DEFINER with an empty search_path');
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and 'lock_timeout=5s' = any(p.proconfig)),
  array['confirm_outbound_dispatch', 'outbound_request_for_execution', 'reconcile_outbound_request', 'record_outbound_result'],
  'engineering default: the four dispatch functions wait at most 5 seconds for a lock');
select ok((select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
  from pg_attribute a where a.attrelid = 'public.outbound_stripe_requests'::regclass
    and a.attname in ('claim_token_sha256', 'dispatch_confirmed_at') and not a.attisdropped)
  = 'claim_token_sha256:text,dispatch_confirmed_at:timestamp with time zone',
  'the two set-once columns exist');

-- ---------------------------------------------------------------------------
-- 2. The claim token (A2)
-- ---------------------------------------------------------------------------
insert into ids select 'p1', pg_temp.checkout_project('TOKA')::text;
insert into ids select 'r1', pg_temp.req((select v::uuid from ids where k = 'p1'), 'customer_create')::text;
select pg_temp.as_service();
insert into claim_tokens select (select v::uuid from ids where k = 'r1'),
  (public.outbound_request_for_execution((select v::uuid from ids where k = 'r1')) ->> 'claim_token')::uuid;
reset role;
select ok((select o.claim_token_sha256 = encode(sha256(convert_to(t.token::text, 'UTF8')), 'hex') and o.claimed_at is not null
            and o.dispatch_confirmed_at is null
           from public.outbound_stripe_requests o join claim_tokens t on t.request_id = o.id where o.id = (select v::uuid from ids where k = 'r1')),
  'A2: the claim returns a token once; only its SHA-256 is stored');
select ok((select position(t.token::text in row_to_json(o)::text) = 0
           from public.outbound_stripe_requests o join claim_tokens t on t.request_id = o.id where o.id = (select v::uuid from ids where k = 'r1')),
  'the plaintext token is stored nowhere in the request row');
select ok((select (v ->> 'error') = 'already_claimed' and not (v ? 'claim_token')
           from pg_temp.claim_only((select v::uuid from ids where k = 'r1')) v),
  'a second claim is refused and returns no token');

-- ---------------------------------------------------------------------------
-- 3. Confirmation (A3)
-- ---------------------------------------------------------------------------
select is(pg_temp.confirm((select v::uuid from ids where k = 'r1'), gen_random_uuid()) ->> 'error', 'claim_token_mismatch',
  'a mismatched token never confirms');
select is(pg_temp.confirm((select v::uuid from ids where k = 'r1'), null) ->> 'error', 'claim_token_mismatch',
  'a missing token never confirms');
select ok((select dispatch_confirmed_at is null and status = 'pending' from public.outbound_stripe_requests
           where id = (select v::uuid from ids where k = 'r1'))
  and pg_temp.notes('outbound.claim_token_rejected', 'outbound.claim_token_rejected:' || (select v from ids where k = 'r1')) = 1,
  'nothing is confirmed, and the Owner is notified once for the request');
insert into ids select 'r1_conf', pg_temp.confirm((select v::uuid from ids where k = 'r1'), pg_temp.token((select v::uuid from ids where k = 'r1')))::text;
select ok((select (c ->> 'ok')::boolean and (c ->> 'confirmed')::boolean
            and (c ->> 'send_by')::timestamptz = o.dispatch_confirmed_at + interval '30 seconds'
            and (c ->> 'dispatch_confirmed_at')::timestamptz = o.dispatch_confirmed_at
           from (select v::jsonb c from ids where k = 'r1_conf') x,
                public.outbound_stripe_requests o where o.id = (select v::uuid from ids where k = 'r1')),
  'the matching token confirms once, with send_by 30 seconds after dispatch_confirmed_at');
insert into ids select 'r1_at', dispatch_confirmed_at::text from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'r1');
select is(pg_temp.confirm((select v::uuid from ids where k = 'r1'), pg_temp.token((select v::uuid from ids where k = 'r1'))) ->> 'error',
  'already_confirmed', 'a repeated confirmation is refused and never authorizes a second send');
select is((select dispatch_confirmed_at::text from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'r1')),
  (select v from ids where k = 'r1_at'), 'dispatch_confirmed_at is set once');
insert into ids select 'r1c', pg_temp.req((select v::uuid from ids where k = 'p1'), 'checkout_session_create')::text;
select is(pg_temp.confirm((select v::uuid from ids where k = 'r1c'), gen_random_uuid()) ->> 'error', 'not_claimed',
  'an unclaimed request cannot be confirmed');
select is(pg_temp.rec((select v::uuid from ids where k = 'r1c'), gen_random_uuid(), 'succeeded', 'cs_test_TOKA000001', false, 200, null) ->> 'error',
  'not_claimed', 'nor recorded');
select is(pg_temp.rec((select v::uuid from ids where k = 'r1'), pg_temp.token((select v::uuid from ids where k = 'r1')),
  'succeeded', 'cus_TTOKA00000', false, 200, null) ->> 'status', 'succeeded', 'the confirmed result is recorded');
select ok(exists (select 1 from public.stripe_customers c join public.projects p on p.client_business_id = c.client_business_id
  where p.id = (select v::uuid from ids where k = 'p1') and c.stripe_customer_id = 'cus_TTOKA00000'),
  'and applies its existing domain effect');

-- The confirmation window, legacy claims and the guard.
insert into ids select 'tw', gen_random_uuid()::text;
insert into ids select 'rw', pg_temp.fabricate((select v::uuid from ids where k = 'p1'), interval '6 minutes',
  (select v::uuid from ids where k = 'tw'), false)::text;
select is(pg_temp.confirm((select v::uuid from ids where k = 'rw'), (select v::uuid from ids where k = 'tw')) ->> 'error',
  'confirmation_window_expired', 'a claim older than the 5-minute confirmation window cannot be confirmed');
insert into ids select 'rl', pg_temp.fabricate((select v::uuid from ids where k = 'p1'), interval '11 minutes', null, false)::text;
select ok(pg_temp.confirm((select v::uuid from ids where k = 'rl'), gen_random_uuid()) ->> 'error' = 'legacy_claim'
  and pg_temp.rec((select v::uuid from ids where k = 'rl'), gen_random_uuid(), 'succeeded', 'cus_TLEGACY0001', false, 200, null) ->> 'error' = 'legacy_claim',
  'a claim made before AUTH-009 (no token hash) can be neither confirmed nor recorded');
select throws_ok($$ update public.outbound_stripe_requests set claim_token_sha256 = repeat('a', 64)
  where id = (select v::uuid from ids where k = 'rl') $$, '42501', null, 'no token backfill: the hash is set only by the claim');
select throws_ok($$ update public.outbound_stripe_requests set dispatch_confirmed_at = now()
  where id = (select v::uuid from ids where k = 'rl') $$, '42501', null, 'a request without a token hash can never be confirmed');
select throws_ok($$ update public.outbound_stripe_requests set claim_token_sha256 = repeat('b', 64)
  where id = (select v::uuid from ids where k = 'r1') $$, '42501', null, 'the token hash is set once');
select throws_ok($$ update public.outbound_stripe_requests set dispatch_confirmed_at = now() - interval '1 second'
  where id = (select v::uuid from ids where k = 'r1') $$, '42501', null, 'the confirmation is set once');
select ok((pg_temp.svc('select public.run_billing_job(''outbound_requests'')') #>> '{result,marked_ambiguous}')::int >= 1,
  'the existing stale rule runs');
select is((select status::text || ':' || error_code from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'rl')),
  'ambiguous:stale_pending', 'the legacy claim goes through the existing stale rule to ambiguous and Owner reconciliation');

-- ---------------------------------------------------------------------------
-- 4. Recording (R1): pending, token, livemode, confirmation; late results; resubmission
-- ---------------------------------------------------------------------------
insert into ids select 'p2', pg_temp.checkout_project('TOKB')::text;
insert into ids select 'r2', pg_temp.req((select v::uuid from ids where k = 'p2'), 'customer_create')::text;
select pg_temp.claim_only((select v::uuid from ids where k = 'r2')) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'r2'), gen_random_uuid(), 'succeeded', 'cus_TTOKB00000', true, 200, null) ->> 'error',
  'claim_token_mismatch', 'the token is checked before livemode: a mismatched token is rejected');
select ok((select status = 'pending' from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'r2'))
  and pg_temp.notes('outbound.claim_token_rejected', 'outbound.claim_token_rejected:' || (select v from ids where k = 'r2')) = 1,
  'the rejected record changes nothing and notifies the Owner');
select is(pg_temp.rec((select v::uuid from ids where k = 'r2'), pg_temp.token((select v::uuid from ids where k = 'r2')),
  'succeeded', 'cus_TTOKB00000', true, 200, null) ->> 'error', 'livemode_mismatch',
  'livemode is checked before confirmation: the live-mode abort is unchanged for an unconfirmed result');
insert into ids select 'p3', pg_temp.checkout_project('TOKC')::text;
insert into ids select 'r3', pg_temp.req((select v::uuid from ids where k = 'p3'), 'customer_create')::text;
select pg_temp.claim_only((select v::uuid from ids where k = 'r3')) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'r3'), pg_temp.token((select v::uuid from ids where k = 'r3')),
  'succeeded', 'cus_TTOKC00000', false, 200, null), '{"ok": true, "reason": "unconfirmed_dispatch", "status": "ambiguous"}'::jsonb,
  'an unconfirmed success is recorded ambiguous (unconfirmed_dispatch)');
select ok((select status = 'ambiguous' and error_code = 'unconfirmed_dispatch' and stripe_object_id = 'cus_TTOKC00000'
             and http_status = 200 and livemode = false
           from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'r3'))
  and not exists (select 1 from public.stripe_customers c join public.projects p on p.client_business_id = c.client_business_id
                   where p.id = (select v::uuid from ids where k = 'p3')),
  'with its submitted evidence and no domain effect');
select ok(exists (select 1 from public.audit_events where action = 'outbound.request_ambiguous'
    and target_id = (select v from ids where k = 'r3') and summary ->> 'reason' = 'unconfirmed_dispatch'
    and summary ->> 'submitted_outcome' = 'succeeded')
  and pg_temp.notes('outbound.request_ambiguous', 'outbound.request_ambiguous:' || (select v from ids where k = 'r3')) = 1,
  'audited with the existing action and notified to the Owner');
select is((private.project_financial_status((select v::uuid from ids where k = 'p3'))).evidence -> 'blocking_anomalies' -> 'G2',
  '["ambiguous_request"]'::jsonb, 'it blocks the gate of the charge it concerns until the Owner reconciles it');

insert into ids select 'p4', pg_temp.checkout_project('TOKD')::text;
insert into ids select 'r4', pg_temp.req((select v::uuid from ids where k = 'p4'), 'customer_create')::text;
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'r4'))) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'r4'), pg_temp.token((select v::uuid from ids where k = 'r4')),
  'succeeded', 'cus_TTOKD00000', false, 200, null) ->> 'status', 'succeeded', 'a confirmed Customer create is recorded');
insert into ids select 'r4c', pg_temp.req((select v::uuid from ids where k = 'p4'), 'checkout_session_create')::text;
select pg_temp.claim_only((select v::uuid from ids where k = 'r4c')) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'r4c'), pg_temp.token((select v::uuid from ids where k = 'r4c')),
  'failed', null, null, 402, 'card_declined') ->> 'status', 'ambiguous', 'an unconfirmed failure is ambiguous too');
select is((select status::text from public.checkout_sessions where project_id = (select v::uuid from ids where k = 'p4')), 'creating',
  'and has no domain effect: the session is not closed as failed');
insert into ids select 'p5', pg_temp.checkout_project('TOKE')::text;
insert into ids select 'r5', pg_temp.req((select v::uuid from ids where k = 'p5'), 'customer_create')::text;
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'r5'))) ->> 'purpose';
select pg_temp.rec((select v::uuid from ids where k = 'r5'), pg_temp.token((select v::uuid from ids where k = 'r5')),
  'succeeded', 'cus_TTOKE00000', false, 200, null) ->> 'status';
insert into ids select 'r5c', pg_temp.req((select v::uuid from ids where k = 'p5'), 'checkout_session_create')::text;
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'r5c'))) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'r5c'), pg_temp.token((select v::uuid from ids where k = 'r5c')),
  'succeeded', 'cs_test_TOKE000001', false, 200, null) ->> 'status', 'succeeded', 'a confirmed Checkout Session create is recorded');
select ok((select (r ->> 'ok')::boolean and (r ->> 'replayed')::boolean and r ->> 'status' = 'succeeded'
           from pg_temp.rec((select v::uuid from ids where k = 'r5c'), pg_temp.token((select v::uuid from ids where k = 'r5c')),
             'succeeded', 'cs_test_TOKE000001', false, 200, null) r),
  'an identical resubmission returns the authoritative stored outcome');
select is((select count(*)::int from public.audit_events where action = 'checkout.session_created'
  and project_id = (select v::uuid from ids where k = 'p5')), 1, 'and applies nothing again');
select is(pg_temp.rec((select v::uuid from ids where k = 'r5c'), pg_temp.token((select v::uuid from ids where k = 'r5c')),
  'succeeded', 'cs_test_TOKE000001', false, 201, null) ->> 'error', 'not_pending', 'a different resubmission is refused');
select is(pg_temp.rec((select v::uuid from ids where k = 'r5c'), gen_random_uuid(),
  'succeeded', 'cs_test_TOKE000001', false, 200, null) ->> 'error', 'not_pending', 'a resubmission without the claim token is refused');

insert into ids select 'tl', gen_random_uuid()::text;
insert into ids select 'rlate', pg_temp.fabricate((select v::uuid from ids where k = 'p1'), interval '7 minutes',
  (select v::uuid from ids where k = 'tl'), true)::text;
select is(pg_temp.rec((select v::uuid from ids where k = 'rlate'), (select v::uuid from ids where k = 'tl'),
  'succeeded', 'cus_TLATE00001', false, 200, null), '{"ok": true, "reason": "late_result", "status": "ambiguous"}'::jsonb,
  'a confirmed success recorded after the 6-minute boundary is ambiguous (late_result)');
insert into ids select 'tf', gen_random_uuid()::text;
insert into ids select 'rfail', pg_temp.fabricate((select v::uuid from ids where k = 'p1'), interval '7 minutes',
  (select v::uuid from ids where k = 'tf'), true)::text;
select is(pg_temp.rec((select v::uuid from ids where k = 'rfail'), (select v::uuid from ids where k = 'tf'),
  'failed', null, null, null, 'dispatch_not_initiated') ->> 'status', 'failed',
  'a confirmed request the executor never sent is recorded failed (dispatch_not_initiated)');

-- ---------------------------------------------------------------------------
-- 5. Confirmation is necessary but not sufficient: eligibility is re-checked
-- ---------------------------------------------------------------------------
insert into ids select 'pv', pg_temp.paid_project('RVKC', 'pm_RVKCcard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'pv'), 11);
select pg_temp.consume();
insert into ids select 'rv', pg_temp.req((select v::uuid from ids where k = 'pv'), 'final_balance_invoice_create')::text;
select is(pg_temp.claim_only((select v::uuid from ids where k = 'rv')) -> 'params' -> 'auto_advance', 'true'::jsonb,
  'the automatic create is claimed');
select is(pg_temp.owner_do(format('select public.record_payment_authorization_revocation(%L, %L)', (select v from ids where k = 'pv'),
  'Client revoked by letter')) ->> 'ok', 'true', 'the authorization is revoked after the claim');
select ok((select c ->> 'error' = 'superseded' and (c ->> 'next_request_id')::uuid <> (select v::uuid from ids where k = 'rv')
           from pg_temp.confirm((select v::uuid from ids where k = 'rv'), pg_temp.token((select v::uuid from ids where k = 'rv'))) c),
  'confirmation re-checks the authorization: the automatic create is never confirmed');
select ok((select o.status = 'failed' and o.error_code = 'authorization_changed' and o.dispatch_confirmed_at is null
           from public.outbound_stripe_requests o where o.id = (select v::uuid from ids where k = 'rv'))
  and (select f.collection_mode = 'hosted_only' from public.final_balance_invoices f where f.project_id = (select v::uuid from ids where k = 'pv'))
  and (select o.status = 'pending' and o.request_params -> 'auto_advance' = 'false'::jsonb and not (o.request_params ? 'default_payment_method')
         from public.outbound_stripe_requests o where o.project_id = (select v::uuid from ids where k = 'pv')
          and o.purpose = 'final_balance_invoice_create' and o.attempt = 2),
  'the deterministic hosted-only replacement is queued instead');

insert into ids select 'pq', pg_temp.paid_project('STPQ', 'pm_STPQcard01')::text;
select pg_temp.final_created((select v::uuid from ids where k = 'pq'), 'STPQ', 12);
select pg_temp.deliver(pg_temp.evt('evt_STPQfail0001', 'invoice.payment_failed', pg_temp.final_body((select v::uuid from ids where k = 'pq'), 'STPQ'), 3));
insert into ids select 'rq', pg_temp.req((select v::uuid from ids where k = 'pq'), 'final_balance_invoice_disable_auto')::text;
select pg_temp.claim_only((select v::uuid from ids where k = 'rq')) ->> 'purpose';
select pg_temp.deliver(pg_temp.evt('evt_STPQpaid0001', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'pq'), 'STPQ'), 5));
select is(pg_temp.confirm((select v::uuid from ids where k = 'rq'), pg_temp.token((select v::uuid from ids where k = 'rq'))) ->> 'error',
  'not_needed', 'a stop claimed before the invoice was paid is not confirmed once it is paid');
select ok((select status = 'failed' and error_code = 'already_paid' from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'rq'))
  and pg_temp.g((select v::uuid from ids where k = 'pq')) = '(t,t)', 'it is dropped as already_paid, which blocks nothing');

-- ---------------------------------------------------------------------------
-- 6. Automatic-stop reconciliation (approved direction)
-- ---------------------------------------------------------------------------
insert into ids select 'ps', pg_temp.paid_project('STPU', 'pm_STPUcard01')::text;
select pg_temp.final_created((select v::uuid from ids where k = 'ps'), 'STPU', 13);
select pg_temp.deliver(pg_temp.evt('evt_STPUdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_STPUcard01', 'object', 'payment_method')));
insert into ids select 'rs', pg_temp.req((select v::uuid from ids where k = 'ps'), 'final_balance_invoice_disable_auto')::text;
select pg_temp.claim_only((select v::uuid from ids where k = 'rs')) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'rs'), pg_temp.token((select v::uuid from ids where k = 'rs')),
  'succeeded', 'in_STPUfinal01', false, 200, null) ->> 'reason', 'unconfirmed_dispatch', 'an unconfirmed stop success stays ambiguous');
select ok(not exists (select 1 from public.audit_events where action = 'balance.automatic_collection_disabled'
    and project_id = (select v::uuid from ids where k = 'ps'))
  and pg_temp.anomalies((select v::uuid from ids where k = 'ps')) -> 'G4' = '["ambiguous_request"]'::jsonb
  and pg_temp.notes('outbound.request_ambiguous', 'outbound.request_ambiguous:' || (select v from ids where k = 'rs')) = 1,
  'it has no domain effect, blocks G4 and notifies the Owner');
select is(pg_temp.owner_do(format('select public.reconcile_outbound_request(%L, false, null, %L)', (select v from ids where k = 'rs'),
  'Stripe shows automatic collection still on')) -> 'gates' -> 'blocking_anomalies' -> 'G4', '["automatic_stop_unresolved"]'::jsonb,
  'a stop reconciled absent keeps G4 blocked: cessation is not established');
select is(pg_temp.deliver(pg_temp.evt('evt_STPUpaid0001', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'ps'), 'STPU'), 5)) ->> 'status',
  'processed', 'Stripe charges the card');
select is(pg_temp.anomalies((select v::uuid from ids where k = 'ps')) -> 'G4', '["charged_after_halt", "reconciliation_mismatch"]'::jsonb,
  'verified payment clears only the stop-specific item; the unreviewed charge after the halt still blocks G4');

insert into ids select 'pf', pg_temp.paid_project('STPF', 'pm_STPFcard01')::text;
select pg_temp.final_created((select v::uuid from ids where k = 'pf'), 'STPF', 14);
select pg_temp.deliver(pg_temp.evt('evt_STPFdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_STPFcard01', 'object', 'payment_method')));
insert into ids select 'rf', pg_temp.req((select v::uuid from ids where k = 'pf'), 'final_balance_invoice_disable_auto')::text;
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'rf'))) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'rf'), pg_temp.token((select v::uuid from ids where k = 'rf')),
  'failed', null, null, 400, 'invoice_not_editable') ->> 'status', 'failed', 'a confirmed stop fails');
select is(pg_temp.owner_do(format('select public.reconcile_outbound_request(%L, false, null, %L)', (select v from ids where k = 'rf'),
  'Not stopped in Stripe')) -> 'gates', '{"G2": true, "G4": false, "blocking_anomalies": {"G2": [], "G4": ["automatic_stop_unresolved"]}}'::jsonb,
  'a failed stop reconciled absent on an unpaid invoice keeps G4 blocked');

insert into ids select 'pp', pg_temp.paid_project('STPP', 'pm_STPPcard01')::text;
select pg_temp.final_created((select v::uuid from ids where k = 'pp'), 'STPP', 15);
select pg_temp.deliver(pg_temp.evt('evt_STPPdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_STPPcard01', 'object', 'payment_method')));
insert into ids select 'rp', pg_temp.req((select v::uuid from ids where k = 'pp'), 'final_balance_invoice_disable_auto')::text;
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'rp'))) ->> 'purpose';
select is(pg_temp.rec((select v::uuid from ids where k = 'rp'), pg_temp.token((select v::uuid from ids where k = 'rp')),
  'ambiguous', null, null, null, 'network_timeout') ->> 'status', 'ambiguous', 'a confirmed stop times out');
select is(pg_temp.owner_do(format('select public.reconcile_outbound_request(%L, true, %L, %L)', (select v from ids where k = 'rp'),
  'in_STPPfinal01', 'Stripe shows automatic collection off')) -> 'gates' -> 'blocking_anomalies' -> 'G4', '[]'::jsonb,
  'authoritative evidence of cessation (reconciled present) clears the stop item');

-- ---------------------------------------------------------------------------
-- 7. OI-92(e): withdrawal or supersession after initiation (the obligation stands)
-- ---------------------------------------------------------------------------
insert into ids select 'pr', pg_temp.paid_project('RELS', 'pm_RELScard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'pr'), 16);
select pg_temp.consume();
select pg_temp.approve((select v::uuid from ids where k = 'pr'), 17);
insert into ids select 'rr', pg_temp.req((select v::uuid from ids where k = 'pr'), 'final_balance_invoice_create')::text;
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'rr'))) ->> 'purpose',
  'final_balance_invoice_create', 'a superseded originating release does not stop the claim: the obligation stands');
select ok(pg_temp.notes('final_balance.release_changed', 'final_balance.release_changed:' || pg_temp.fbi((select v::uuid from ids where k = 'pr'))) = 1
  and (select payload_ref ->> 'reason' from public.notification_outbox where notification_type = 'final_balance.release_changed'
        and project_id = (select v::uuid from ids where k = 'pr')) = 'superseded'
  and (select release_id from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'pr'))
      = '30000000-0000-4000-8000-000000000016',
  'the Owner is notified once that the release was superseded; the invoice keeps its release');
select pg_temp.reconcile((select v::uuid from ids where k = 'pr'), 'it191-rels', '{"charges_cents": 25900, "refunds_cents": 0, "open_disputes": 0}');
select is(pg_temp.notes('final_balance.release_changed', 'final_balance.release_changed:' || pg_temp.fbi((select v::uuid from ids where k = 'pr'))), 1,
  'the project reconciliation detects it again without a second notification');

insert into ids select 'pw', pg_temp.paid_project('RELW', 'pm_RELWcard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'pw'), 18);
select pg_temp.consume();
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select is((public.withdraw_preview('30000000-0000-4000-8000-000000000018', 'Withdrawn after initiation') ->> 'ok')::boolean, true,
  'WP-C withdraws the release after the final-balance obligation was initiated');
reset role;
select is(pg_temp.reconcile((select v::uuid from ids where k = 'pw'), 'it191-relw', '{"charges_cents": 25900, "refunds_cents": 0, "open_disputes": 0}'), 0,
  'the project reconciliation runs');
select ok(pg_temp.notes('final_balance.release_changed', 'final_balance.release_changed:' || pg_temp.fbi((select v::uuid from ids where k = 'pw'))) = 1
  and (select payload_ref ->> 'reason' from public.notification_outbox where notification_type = 'final_balance.release_changed'
        and project_id = (select v::uuid from ids where k = 'pw')) = 'withdrawn'
  and (select status = 'creating' from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'pw')),
  'it notifies the Owner once that the release was withdrawn; the obligation stands');
insert into ids select 'pc', pg_temp.paid_project('RELC', 'pm_RELCcard01')::text;
select pg_temp.approve((select v::uuid from ids where k = 'pc'), 19);
select pg_temp.consume();
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)',
  pg_temp.req((select v::uuid from ids where k = 'pc'), 'final_balance_invoice_create'))) ->> 'purpose';
select is(pg_temp.reconcile((select v::uuid from ids where k = 'pc'), 'it191-relc', '{"charges_cents": 25900, "refunds_cents": 0, "open_disputes": 0}'), 0,
  'control: a current release');
select is((select count(*)::int from public.notification_outbox where notification_type = 'final_balance.release_changed'
  and project_id = (select v::uuid from ids where k = 'pc')), 0, 'control: no release-change notification while the release is current');

select * from finish();
rollback;
