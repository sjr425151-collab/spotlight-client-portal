-- WP-B B1: financial integrity fails closed. Every unresolved financial-integrity anomaly
-- blocks the payment gate of the charge it concerns (G2 initial charge, G4 final-balance
-- charge, both when the charge cannot be told), through WP-B's interface and WP-C's single
-- publication gate evaluator. Resolution is only through the existing Owner-only, audited
-- functions and is a review record: the gates are re-derived from all the evidence, so a
-- reversal Stripe still reports keeps its gate blocked, and valid evidence lets it pass.
-- Everything runs through the real event, outbound, reconciliation and resolution paths.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(53);

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
    ('40000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))::uuid, 'release.approved:t160:' || p_project || ':' || p_n);
$$;
create temporary table ids (k text primary key, v text) on commit drop;
grant all on ids to authenticated, service_role;

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
    perform public.outbound_request_for_execution(v_req.id);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, 'succeeded', 'cus_T' || p_tag || '00000', false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, 'succeeded', 'cs_test_' || p_tag || '00000', false, 200, null,
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
    perform pg_temp.svc(format('select public.record_outbound_result(%L, ''succeeded'', %L, false, 200, null, ''{}'')', v_req,
      'in_' || p_tag || 'final01'));
  else
    perform pg_temp.svc(format('select public.record_outbound_result(%L, %L, null, null, null, ''network_timeout'', ''{}'')', v_req, p_outcome));
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
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1. Initial charge: excessive refund, malformed refund amount, dispute mismatch (G2)
-- ---------------------------------------------------------------------------
insert into ids select 'pi', pg_temp.paid_project('INIT', null)::text;
select pg_temp.initial_invoice((select v::uuid from ids where k = 'pi'), 'INIT');
select pg_temp.final_created((select v::uuid from ids where k = 'pi'), 'INIT', 1);
select pg_temp.deliver(pg_temp.evt('evt_INITfinpaid1', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'pi'), 'INIT'), 5));
select is(pg_temp.g((select v::uuid from ids where k = 'pi')), '(t,t)', 'baseline: G2 and G4 are satisfied by verified payments');

select is(pg_temp.refund('evt_INITrefbig01', 're_INITrefbig01', '30000', 'pi_INITinit01', 'succeeded', 10) ->> 'reason',
  'reversal_exceeds_charge', 'an excessive refund of the initial charge is quarantined');
select is(pg_temp.refund('evt_INITrefbad01', 're_INITrefbad01', '"12.5"', 'pi_INITinit01', 'succeeded', 11) ->> 'reason',
  'refund_invalid', 'a malformed refund amount is quarantined (never a processing error), attributed to its charge');
select is(pg_temp.dispute('evt_INITdspbad01', 'dp_INITdspbad01', '25900', 'pi_INITinit01', 'needs_response', 12, 'eur') ->> 'reason',
  'dispute_invalid', 'a dispute that does not match the charge is quarantined');
select is((select count(*)::integer from public.webhook_events where stripe_event_id in ('evt_INITrefbig01', 'evt_INITrefbad01', 'evt_INITdspbad01')
  and processing_status = 'quarantined' and project_id = (select v::uuid from ids where k = 'pi')), 3,
  'each quarantined event keeps its project attribution');
select is(pg_temp.g((select v::uuid from ids where k = 'pi')), '(f,t)',
  'B1: anomalies on the initial charge fail G2 only; G4 still passes');
select is(pg_temp.anomalies((select v::uuid from ids where k = 'pi')), '{"G2": ["quarantined_event", "unposted_reversal"], "G4": []}'::jsonb,
  'the blocking anomalies are named by kind, per gate');
select ok(not pg_temp.eligible((select v::uuid from ids where k = 'pi'))
  and pg_temp.gate((select v::uuid from ids where k = 'pi'), 'G2') = 'deposit_not_verified'
  and pg_temp.gate((select v::uuid from ids where k = 'pi'), 'G4') = 'passed',
  'B1: WP-C''s evaluator returns eligible = false with G2 deposit_not_verified');

-- Multiple simultaneous anomalies; a reversal that Stripe reports stays a block.
select is(pg_temp.owner_do(format('select public.resolve_quarantined_event(%s, %L)', pg_temp.evt_id('evt_INITrefbad01'),
  'Reviewed: the refund is real; amount to be confirmed with Stripe')) -> 'gates' ->> 'G2', 'false',
  'resolving one anomaly does not clear the others');
select pg_temp.owner_do(format('select public.resolve_quarantined_event(%s, %L)', pg_temp.evt_id('evt_INITrefbig01'), 'Reviewed with Stripe'));
select is(pg_temp.owner_do(format('select public.resolve_quarantined_event(%s, %L)', pg_temp.evt_id('evt_INITdspbad01'),
  'Reviewed: chargeback confirmed')) -> 'gates', '{"G2": false, "G4": true, "blocking_anomalies": {"G2": ["unposted_reversal"], "G4": []}}'::jsonb,
  'B1: after every quarantine is reviewed, the reversals Stripe reports still block G2 (resolution never erases a reversal)');
select ok(pg_temp.gate((select v::uuid from ids where k = 'pi'), 'G2') = 'deposit_not_verified'
  and (select count(*) = 0 from public.ledger_entries where project_id = (select v::uuid from ids where k = 'pi')
         and entry_type in ('refund', 'dispute_opened')),
  'the gate stays failed and no resolution posted anything');
select is((select count(*)::integer from public.audit_events where action = 'quarantine.resolved'
           and project_id = (select v::uuid from ids where k = 'pi') and summary ? 'gates'), 3,
  'each resolution is audited with the fresh evaluation');

-- Stripe's later evidence: both refunds failed and the dispute was won. G2 passes again.
select is(pg_temp.refund('evt_INITrefbig02', 're_INITrefbig01', '30000', 'pi_INITinit01', 'failed', 100) ->> 'status', 'processed',
  'Stripe later reports the excessive refund failed');
select is(pg_temp.refund('evt_INITrefbad02', 're_INITrefbad01', '1250', 'pi_INITinit01', 'canceled', 101) ->> 'status', 'processed',
  'and the malformed one canceled');
select is(pg_temp.g((select v::uuid from ids where k = 'pi')), '(f,t)', 'the dispute Stripe still reports keeps G2 blocked');
select is(pg_temp.dispute('evt_INITdspwon01', 'dp_INITdspbad01', '25900', 'pi_INITinit01', 'won', 102) ->> 'status', 'processed',
  'Stripe later reports the dispute won');
select ok(pg_temp.g((select v::uuid from ids where k = 'pi')) = '(t,t)'
  and pg_temp.anomalies((select v::uuid from ids where k = 'pi')) = '{"G2": [], "G4": []}'::jsonb
  and pg_temp.gate((select v::uuid from ids where k = 'pi'), 'G2') = 'passed',
  'B1: with every anomaly reviewed and valid evidence (funds back), G2 passes again');

-- ---------------------------------------------------------------------------
-- 2. Final-balance charge: excessive refund, malformed refund amount, dispute mismatch (G4)
-- ---------------------------------------------------------------------------
insert into ids select 'pf', pg_temp.paid_project('FINL', null)::text;
select pg_temp.initial_invoice((select v::uuid from ids where k = 'pf'), 'FINL');
select pg_temp.final_created((select v::uuid from ids where k = 'pf'), 'FINL', 2);
select pg_temp.deliver(pg_temp.evt('evt_FINLfinpaid1', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'pf'), 'FINL'), 5));
select is(pg_temp.g((select v::uuid from ids where k = 'pf')), '(t,t)', 'baseline: both gates pass');
select is(pg_temp.refund('evt_FINLrefbig01', 're_FINLrefbig01', '64001', 'pi_FINLfinal01', 'succeeded', 10) ->> 'reason',
  'reversal_exceeds_charge', 'an excessive refund of the final balance is quarantined');
select is(pg_temp.refund('evt_FINLrefbad01', 're_FINLrefbad01', '-500', 'pi_FINLfinal01', 'succeeded', 11) ->> 'reason',
  'refund_invalid', 'a negative refund amount on the final balance is quarantined');
select is(pg_temp.dispute('evt_FINLdspbad01', 'dp_FINLdspbad01', '"64000"', 'pi_FINLfinal01', 'needs_response', 12) ->> 'reason',
  'dispute_invalid', 'a malformed dispute on the final balance is quarantined');
select is(pg_temp.g((select v::uuid from ids where k = 'pf')), '(t,f)', 'B1: anomalies on the final-balance charge fail G4 only');
select ok(not pg_temp.eligible((select v::uuid from ids where k = 'pf'))
  and pg_temp.gate((select v::uuid from ids where k = 'pf'), 'G4') = 'balance_not_verified'
  and pg_temp.gate((select v::uuid from ids where k = 'pf'), 'G2') = 'passed',
  'B1: WP-C''s evaluator returns eligible = false with G4 balance_not_verified');
select pg_temp.owner_do(format('select public.resolve_quarantined_event(%s, %L)', id, 'Reviewed')) from public.webhook_events
 where stripe_event_id in ('evt_FINLrefbig01', 'evt_FINLrefbad01', 'evt_FINLdspbad01');
select ok(pg_temp.g((select v::uuid from ids where k = 'pf')) = '(t,f)'
  and pg_temp.anomalies((select v::uuid from ids where k = 'pf')) = '{"G2": [], "G4": ["unposted_reversal"]}'::jsonb
  and private.project_final_balance_state((select v::uuid from ids where k = 'pf')) = 'verified',
  'B1: reviewing them confirms the reversals Stripe reports; G4 stays blocked although the payment itself was verified');

-- ---------------------------------------------------------------------------
-- 3. Ambiguous final-balance invoice creation (G4), then valid evidence
-- ---------------------------------------------------------------------------
insert into ids select 'pa', pg_temp.paid_project('AMBG', null)::text;
insert into ids select 'ra', pg_temp.final_created((select v::uuid from ids where k = 'pa'), 'AMBG', 3, 'ambiguous')::text;
select ok(pg_temp.g((select v::uuid from ids where k = 'pa')) = '(t,f)'
  and pg_temp.anomalies((select v::uuid from ids where k = 'pa')) -> 'G4' = '["ambiguous_request"]'::jsonb,
  'B1: an ambiguous final-balance create blocks G4 only');
select is(pg_temp.owner_do(format('select public.reconcile_outbound_request(%L, true, %L, %L)', (select v from ids where k = 'ra'),
  'in_AMBGfinal01', 'Found in the Stripe Dashboard')) -> 'gates', '{"G2": true, "G4": false, "blocking_anomalies": {"G2": [], "G4": []}}'::jsonb,
  'reconciling it clears the anomaly, but G4 is re-derived: the invoice is not paid, so it still fails');
select is(pg_temp.gate((select v::uuid from ids where k = 'pa'), 'G4'), 'balance_not_verified', 'the evaluator agrees');
select is(pg_temp.deliver(pg_temp.evt('evt_AMBGfinpaid1', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'pa'), 'AMBG'), 5)) ->> 'status',
  'processed', 'the reconciled invoice is paid');
select is(pg_temp.g((select v::uuid from ids where k = 'pa')), '(t,t)', 'B1: valid payment evidence lets G4 pass after reconciliation');

-- ---------------------------------------------------------------------------
-- 4. Failed automatic-collection stop and charged_after_halt (G4); one does not clear the other
-- ---------------------------------------------------------------------------
insert into ids select 'ps', pg_temp.paid_project('STOP', 'pm_STOPcard01')::text;
select pg_temp.final_created((select v::uuid from ids where k = 'ps'), 'STOP', 4);
select pg_temp.deliver(pg_temp.evt('evt_STOPdetach01', 'payment_method.detached', jsonb_build_object('id', 'pm_STOPcard01', 'object', 'payment_method')));
insert into ids select 'rs', id::text from public.outbound_stripe_requests where project_id = (select v::uuid from ids where k = 'ps')
  and purpose = 'final_balance_invoice_disable_auto';
select pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select v from ids where k = 'rs')));
select is(pg_temp.svc(format('select public.record_outbound_result(%L, ''failed'', null, null, 400, ''invoice_not_editable'', ''{}'')',
  (select v from ids where k = 'rs'))) ->> 'status', 'failed', 'the request disabling automatic collection fails');
select ok(pg_temp.g((select v::uuid from ids where k = 'ps')) = '(t,f)'
  and pg_temp.anomalies((select v::uuid from ids where k = 'ps')) -> 'G4' = '["automatic_stop_failed"]'::jsonb,
  'B1: a failed automatic-collection stop blocks G4');
select is(pg_temp.deliver(pg_temp.evt('evt_STOPfinpaid1', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'ps'), 'STOP'), 5)) ->> 'status',
  'processed', 'Stripe charges the card anyway');
select ok((select charged_after_halt from public.final_balance_invoices where project_id = (select v::uuid from ids where k = 'ps'))
  and private.project_final_balance_state((select v::uuid from ids where k = 'ps')) = 'verified'
  and pg_temp.anomalies((select v::uuid from ids where k = 'ps')) -> 'G4' = '["automatic_stop_failed", "charged_after_halt", "reconciliation_mismatch"]'::jsonb,
  'B1: the charge after the halt is verified, yet G4 stays blocked by the failed stop and the unreviewed charge');
select is(pg_temp.owner_do(format('select public.resolve_reconciliation_mismatch(%L, %L)',
  (select id from public.reconciliation_mismatches where kind = 'charged_after_halt' and project_id = (select v::uuid from ids where k = 'ps')),
  'Reviewed: client confirmed the charge')) -> 'gates' -> 'blocking_anomalies' -> 'G4', '["automatic_stop_failed"]'::jsonb,
  'B1: reviewing the charge after the halt leaves the failed stop blocking G4');
select is(pg_temp.owner_do(format('select public.reconcile_outbound_request(%L, false, null, %L)', (select v from ids where k = 'rs'),
  'Invoice already paid in Stripe; nothing left to stop')) -> 'gates', '{"G2": true, "G4": true, "blocking_anomalies": {"G2": [], "G4": []}}'::jsonb,
  'reconciling the failed stop leaves no anomaly; the verified payment lets G4 pass');
select is((select status::text from public.outbound_stripe_requests where id = (select v::uuid from ids where k = 'rs')), 'reconciled_absent',
  'the stop request records the Owner''s reconciliation');

-- already_paid alone is not an anomaly: a stop dropped because the invoice was paid.
insert into ids select 'pp', pg_temp.paid_project('PAID', 'pm_PAIDcard01')::text;
select pg_temp.final_created((select v::uuid from ids where k = 'pp'), 'PAID', 5);
select pg_temp.deliver(pg_temp.evt('evt_PAIDfail0001', 'invoice.payment_failed', pg_temp.final_body((select v::uuid from ids where k = 'pp'), 'PAID'), 3));
select pg_temp.deliver(pg_temp.evt('evt_PAIDfinpaid1', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'pp'), 'PAID'), 5));
select is(pg_temp.svc(format('select public.outbound_request_for_execution(%L)', (select id from public.outbound_stripe_requests
  where project_id = (select v::uuid from ids where k = 'pp') and purpose = 'final_balance_invoice_disable_auto'))) ->> 'error', 'not_needed',
  'a stop for a paid invoice is dropped (already_paid)');
select is(pg_temp.g((select v::uuid from ids where k = 'pp')), '(t,t)', 'B1: an already_paid stop failure alone blocks nothing');

-- ---------------------------------------------------------------------------
-- 5. Open reconciliation mismatches and unmatched refund and dispute attribution
-- ---------------------------------------------------------------------------
insert into ids select 'pm', pg_temp.paid_project('MISM', null)::text;
select pg_temp.initial_invoice((select v::uuid from ids where k = 'pm'), 'MISM');
select pg_temp.final_created((select v::uuid from ids where k = 'pm'), 'MISM', 6);
select pg_temp.deliver(pg_temp.evt('evt_MISMfinpaid1', 'invoice.paid', pg_temp.final_body((select v::uuid from ids where k = 'pm'), 'MISM'), 5));
select is(pg_temp.reconcile((select v::uuid from ids where k = 'pm'), 't160-a', '{"charges_cents": 1, "refunds_cents": 0, "open_disputes": 0}'), 1,
  'a totals mismatch is recorded');
select ok(pg_temp.g((select v::uuid from ids where k = 'pm')) = '(f,f)'
  and not pg_temp.eligible((select v::uuid from ids where k = 'pm')),
  'B1: an open project-level mismatch (charge unknown) fails both G2 and G4');
select is(pg_temp.owner_do(format('select public.resolve_reconciliation_mismatch(%L, %L)',
  (select id from public.reconciliation_mismatches where project_id = (select v::uuid from ids where k = 'pm') and kind = 'charges_total'),
  'Stripe export confirms the ledger total')) -> 'gates', '{"G2": true, "G4": true, "blocking_anomalies": {"G2": [], "G4": []}}'::jsonb,
  'B1: the resolution re-derives both gates from valid evidence; they pass');
select is(pg_temp.reconcile((select v::uuid from ids where k = 'pm'), 't160-b', jsonb_build_object(
  'charges_cents', 89900, 'refunds_cents', 0, 'open_disputes', 0,
  'refunds', jsonb_build_array(
    jsonb_build_object('id', 're_MISMinit0001', 'amount', 500, 'status', 'succeeded', 'payment_intent', 'pi_MISMinit01'),
    jsonb_build_object('id', 're_MISMnolink01', 'amount', 700, 'status', 'succeeded', 'charge', 'ch_MISMunknown1')),
  'disputes', jsonb_build_array(
    jsonb_build_object('id', 'dp_MISMfinal001', 'amount', 64000, 'status', 'needs_response', 'payment_intent', 'pi_MISMfinal01')))), 3,
  'reconciliation records the three refund and dispute objects WP-B never received');
select results_eq(format($$ select stripe_object_id, kind, split_part(coalesce(charge_key, 'unknown:'), ':', 1)
    from public.reconciliation_mismatches where project_id = %L and stripe_object_id is not null order by stripe_object_id $$,
    (select v from ids where k = 'pm')),
  $$ values ('dp_MISMfinal001', 'unmatched_dispute', 'final_balance'), ('re_MISMinit0001', 'unmatched_refund', 'initial'),
            ('re_MISMnolink01', 'unmatched_refund', 'unknown') $$,
  'B1: each is attributed through its charge (initial, final balance, or unknown)');
select is(pg_temp.reconcile((select v::uuid from ids where k = 'pm'), 't160-c', jsonb_build_object(
  'charges_cents', 89900, 'refunds_cents', 0, 'open_disputes', 0,
  'disputes', jsonb_build_array(jsonb_build_object('id', 'dp_MISMfinal001', 'amount', 64000, 'status', 'needs_response',
    'payment_intent', 'pi_MISMfinal01')))), 0, 'a later run records the same object state once only');
select is(pg_temp.g((select v::uuid from ids where k = 'pm')), '(f,f)', 'B1: the unmatched objects block G2 and G4');
select pg_temp.owner_do(format('select public.resolve_reconciliation_mismatch(%L, %L)', id, 'Reviewed'))
  from public.reconciliation_mismatches where project_id = (select v::uuid from ids where k = 'pm') and stripe_object_id is not null
  and stripe_object_id <> 're_MISMnolink01';
select ok(pg_temp.anomalies((select v::uuid from ids where k = 'pm')) = '{"G2": ["reconciliation_mismatch", "unposted_reversal"], "G4": ["reconciliation_mismatch", "unposted_reversal"]}'::jsonb,
  'B1: resolving two items leaves the unattributed one blocking both gates, and the reviewed reversals still block their charges');
select is(pg_temp.owner_do(format('select public.resolve_reconciliation_mismatch(%L, %L)',
  (select id from public.reconciliation_mismatches where stripe_object_id = 're_MISMnolink01'), 'Reviewed')) -> 'gates' -> 'blocking_anomalies',
  '{"G2": ["unposted_reversal"], "G4": ["unposted_reversal"]}'::jsonb,
  'B1: after every review, refunds and disputes Stripe reports keep G2 and G4 blocked until they are posted or reversed');
select ok(pg_temp.gate((select v::uuid from ids where k = 'pm'), 'G2') = 'deposit_not_verified'
  and pg_temp.gate((select v::uuid from ids where k = 'pm'), 'G4') = 'balance_not_verified'
  and not pg_temp.eligible((select v::uuid from ids where k = 'pm')),
  'B1: the evaluator stays ineligible with both financial reasons');

-- ---------------------------------------------------------------------------
-- 6. Controls
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.resolve_reconciliation_mismatch((select id from public.reconciliation_mismatches limit 1), 'x') ->> 'error', 'forbidden',
  'Admin cannot resolve an anomaly');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.resolve_quarantined_event(pg_temp.evt_id('evt_FINLrefbig01'), 'x') ->> 'error', 'forbidden',
  'the Owner needs fresh MFA to resolve');
reset role;
select throws_ok($$ update public.reconciliation_mismatches set resolution = 'tamper' where resolved_at is not null $$, '42501', null,
  'B1: a reconciliation resolution is immutable, even for the table owner');
select throws_ok($$ update public.reconciliation_mismatches set resolved_at = null, resolved_by = null, resolution = null
  where resolved_at is not null $$, '42501', null, 'B1: a resolution can never be undone to re-open or hide an item');
select is((select array_agg(e.enumlabel::text order by e.enumsortorder) from pg_enum e where e.enumtypid = 'public.hold_type'::regtype),
  array['maintenance_payment_hold', 'approval_nonresponsive_hold', 'dispute_risk_hold', 'owner_manual_hold'],
  'B1 adds no hold type: anomalies block the gates directly, not through a new hold');

select * from finish();
rollback;
