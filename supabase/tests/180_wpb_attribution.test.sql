-- WP-H (AUTH-006 and Amendment 1), N1(a): attribution of refunds and disputes at receipt.
-- Covers the Amendment 1 acceptance for N1(a): refund-decision attribution (valid, forged,
-- mismatched charge); payment-link and invoice-link attribution; conflict quarantine with no
-- project set and the exact candidate set recorded once; replay; a later link neither re-points
-- nor clears; unattributable events stay deferred; every candidate fails G2 and G4; the Owner's
-- review re-checks and audits every candidate and the block persists; unrelated anomalies and
-- unposted_reversal still block; candidate rows are immutable and unreadable; Admin, Sales and
-- clients see booleans only. T-PAY-32 and the B1 assertions (140, 160) are unchanged.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(46);

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
create function pg_temp.approve(p_project uuid, p_n integer) returns bigint language sql as $$
  select private.emit_domain_event('release.approved', p_project, 'preview_release',
    ('30000000-0000-4000-8000-' || lpad(p_n::text, 12, '0')), jsonb_build_object('approval_id',
    ('40000000-0000-4000-8000-' || lpad(p_n::text, 12, '0'))), 'release.approved:t130:' || p_project || ':' || p_n);
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

-- The charge ledger helpers.
create function pg_temp.ob(p_project uuid, p_kind text) returns uuid language sql as $$
  select id from public.payment_obligations where project_id = p_project and kind = p_kind::public.obligation_kind
  order by created_at desc limit 1;
$$;
create function pg_temp.refund(p_id text, p_re text, p_amount bigint, p_pi text, p_status text default 'succeeded',
  p_decision uuid default null, p_offset integer default 0) returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'refund.created', jsonb_build_object('id', p_re, 'object', 'refund', 'amount', p_amount,
    'currency', 'usd', 'status', p_status, 'payment_intent', p_pi,
    'metadata', case when p_decision is null then '{}'::jsonb else jsonb_build_object('refund_decision_id', p_decision) end), p_offset));
$$;
create function pg_temp.dispute(p_id text, p_dp text, p_amount bigint, p_pi text, p_status text, p_offset integer default 0)
returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'charge.dispute.' || case when p_status in ('won', 'lost') then 'closed' else 'created' end,
    jsonb_build_object('id', p_dp, 'object', 'dispute', 'amount', p_amount, 'currency', 'usd', 'status', p_status,
      'payment_intent', p_pi), p_offset));
$$;
grant execute on function pg_temp.ob(uuid, text) to authenticated;
-- The initial invoice (links the payment intent used by refunds and disputes).
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


create function pg_temp.g(p_project uuid) returns text language sql as $$
  select row(s.deposit_verified, s.balance_verified_or_settled)::text from private.project_financial_status(p_project) s;
$$;
create function pg_temp.blocking(p_project uuid) returns jsonb language sql as $$
  select (private.project_financial_status(p_project)).evidence -> 'blocking_anomalies';
$$;
create function pg_temp.evt_row(p_stripe_event_id text) returns public.webhook_events language sql as $$
  select * from public.webhook_events where stripe_event_id = p_stripe_event_id;
$$;
create function pg_temp.cands(p_stripe_event_id text) returns text language sql as $$
  select coalesce(string_agg(c.project_id::text || '/' || c.source, ',' order by c.project_id, c.source), '')
    from private.financial_event_project_candidates c
    join public.webhook_events w on w.id = c.webhook_event_id where w.stripe_event_id = p_stripe_event_id;
$$;
create function pg_temp.pid(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- Two paid projects through the real workflow, each with its initial invoice linked.
insert into ids select 'pa', pg_temp.paid_project('ATTA', null)::text;
insert into ids select 'pb', pg_temp.paid_project('ATTB', null)::text;
select pg_temp.initial_invoice(pg_temp.pid('pa'), 'ATTA');
select pg_temp.initial_invoice(pg_temp.pid('pb'), 'ATTB');
insert into ids select 'ka', 'initial:' || id from public.checkout_sessions where project_id = pg_temp.pid('pa');
insert into ids select 'kb', 'initial:' || id from public.checkout_sessions where project_id = pg_temp.pid('pb');
select is(pg_temp.g(pg_temp.pid('pa')) || pg_temp.g(pg_temp.pid('pb')), '(t,f)(t,f)', 'both deposits verified (G2 passes)');

-- ---------------------------------------------------------------------------
-- 1. Refund-decision attribution: valid, forged, mismatched charge
-- ---------------------------------------------------------------------------
-- A renewal charge for A (a second charge of the same project), through real events.
select pg_temp.deliver(pg_temp.evt('evt_ATTAsub0001', 'customer.subscription.created', jsonb_build_object('id', 'sub_ATTA00000',
  'object', 'subscription', 'status', 'active', 'customer', 'cus_TATTA00000', 'metadata', jsonb_build_object('project_id', pg_temp.pid('pa')))));
select is(pg_temp.deliver(pg_temp.evt('evt_ATTArenew001', 'invoice.paid', jsonb_build_object('id', 'in_ATTArenew01', 'object', 'invoice',
  'billing_reason', 'subscription_cycle', 'currency', 'usd', 'amount_paid', 9900, 'customer', 'cus_TATTA00000',
  'subscription', 'sub_ATTA00000', 'payment_intent', 'pi_ATTArenew01',
  'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))))) ->> 'status',
  'processed', 'A also has a paid renewal charge');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'dv', public.record_refund_decision(pg_temp.pid('pa'), 1000, 'Partial refund agreed',
  jsonb_build_array(jsonb_build_object('obligation_id', (select id from public.payment_obligations where project_id = pg_temp.pid('pa')
    and kind = 'development_deposit'), 'amount_cents', 1000))) ->> 'refund_decision_id';
insert into ids select 'dbb', public.record_refund_decision(pg_temp.pid('pb'), 1000, 'Refund for project B',
  jsonb_build_array(jsonb_build_object('obligation_id', (select id from public.payment_obligations where project_id = pg_temp.pid('pb')
    and kind = 'development_deposit'), 'amount_cents', 1000))) ->> 'refund_decision_id';
insert into ids select 'dmis', public.record_refund_decision(pg_temp.pid('pa'), 500, 'Renewal refund',
  jsonb_build_array(jsonb_build_object('obligation_id', (select id from public.payment_obligations where project_id = pg_temp.pid('pa')
    and charge_key = 'renewal:in_ATTArenew01'), 'amount_cents', 500))) ->> 'refund_decision_id';
reset role;
select ok((select charge_key from public.refund_decisions where id = pg_temp.pid('dv')) = (select v from ids where k = 'ka')
  and (select charge_key from public.refund_decisions where id = pg_temp.pid('dbb')) = (select v from ids where k = 'kb')
  and (select charge_key from public.refund_decisions where id = pg_temp.pid('dmis')) = 'renewal:in_ATTArenew01',
  'three real decisions: A initial charge, B initial charge, A renewal charge');
select ok(exists (select 1 from private.financial_event_attribution(
    jsonb_build_object('id', 're_ATTvalid0001', 'object', 'refund', 'payment_intent', 'pi_ATTAinit01'), pg_temp.pid('dv')) c
    where c.source = 'refund_decision' and c.project_id = pg_temp.pid('pa')),
  'N1(a): a decision whose charge_key matches the event''s charge counts');
select ok(not exists (select 1 from private.financial_event_attribution(
    jsonb_build_object('id', 're_ATTforg00001', 'object', 'refund', 'payment_intent', 'pi_ATTAinit01'), pg_temp.pid('dbb')) c
    where c.source = 'refund_decision'),
  'N1(a): a forged reference to another project''s decision never counts');
select ok(not exists (select 1 from private.financial_event_attribution(
    jsonb_build_object('id', 're_ATTmism00001', 'object', 'refund', 'payment_intent', 'pi_ATTAinit01'), pg_temp.pid('dmis')) c
    where c.source = 'refund_decision'),
  'N1(a): a decision for another charge of the same project never counts');
select ok(not exists (select 1 from private.financial_event_attribution(
    jsonb_build_object('id', 're_ATTnone00001', 'object', 'refund', 'metadata', jsonb_build_object('refund_decision_id', pg_temp.pid('dv'))),
    pg_temp.pid('dv'))),
  'N1(a): a decision reference without the charge''s identifiers (metadata alone) attributes nothing');
select is(pg_temp.refund('evt_ATTvalid0001', 're_ATTvalid0001', 1000, 'pi_ATTAinit01', 'succeeded', pg_temp.pid('dv')) ->> 'status',
  'processed', 'a refund naming the valid decision is processed');
select ok((select refund_decision_id = pg_temp.pid('dv') from public.refunds where stripe_refund_id = 're_ATTvalid0001')
  and (select matched_refund_id = 're_ATTvalid0001' from public.refund_decisions where id = pg_temp.pid('dv'))
  and (select o.kind = 'development_deposit' from public.ledger_entries l join public.payment_obligations o on o.id = l.obligation_id
         where l.stripe_object_id = 're_ATTvalid0001'),
  'N1(a): the valid decision is stored, matched, and allocates exactly as recorded');
select is(pg_temp.refund('evt_ATTforg00001', 're_ATTforg00001', 1000, 'pi_ATTAinit01', 'succeeded', pg_temp.pid('dbb'), 1) ->> 'status',
  'processed', 'a refund naming a forged decision is attributed through its payment link only');
select ok((select project_id = pg_temp.pid('pa') and refund_decision_id is null from public.refunds where stripe_refund_id = 're_ATTforg00001')
  and (select matched_refund_id is null from public.refund_decisions where id = pg_temp.pid('dbb')),
  'N1(a): the forged decision is neither stored on the refund nor matched');
select is(pg_temp.refund('evt_ATTmism00001', 're_ATTmism00001', 500, 'pi_ATTAinit01', 'succeeded', pg_temp.pid('dmis'), 2) ->> 'status',
  'processed', 'a refund naming a decision for another charge is processed');
select ok((select refund_decision_id is null from public.refunds where stripe_refund_id = 're_ATTmism00001')
  and (select matched_refund_id is null from public.refund_decisions where id = pg_temp.pid('dmis')),
  'N1(a): the mismatched decision is neither stored nor matched');

-- ---------------------------------------------------------------------------
-- 2. Link and invoice attribution; unattributable events
-- ---------------------------------------------------------------------------
select ok(exists (select 1 from private.financial_event_attribution(
    jsonb_build_object('id', 'dp_ATTlink00001', 'object', 'dispute', 'payment_intent', 'pi_ATTBinit01'), null) c
    where c.project_id = pg_temp.pid('pb') and c.source = 'payment_link'),
  'N1(a): a payment link attributes the event');
select ok(exists (select 1 from private.financial_event_attribution(
    jsonb_build_object('id', 'ch_ATTinvo00001', 'object', 'charge', 'invoice', 'in_ATTB00000'), null) c
    where c.project_id = pg_temp.pid('pb') and c.source in ('checkout_session', 'payment_link')),
  'N1(a): an invoice link (checkout session) attributes the event');
select is(pg_temp.refund('evt_ATTunat00001', 're_ATTunat00001', 700, 'pi_ATTnobody01') ->> 'status', 'deferred',
  'N1(a): an unattributable refund stays deferred');
select ok((pg_temp.evt_row('evt_ATTunat00001')).project_id is null and pg_temp.cands('evt_ATTunat00001') = '',
  'N1(a): it gets no invented project and no candidates; kept for reconciliation');

-- ---------------------------------------------------------------------------
-- 3. Conflicting authoritative projects
-- ---------------------------------------------------------------------------
-- A refund whose payment intent is project A's and whose invoice is project B's.
select is(pg_temp.deliver(pg_temp.evt('evt_ATTconf00001', 'refund.updated', jsonb_build_object('id', 're_ATTconf00001',
  'object', 'refund', 'amount', 1200, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_ATTAinit01',
  'invoice', 'in_ATTB00000', 'metadata', '{}'::jsonb), 10)) ->> 'reason', 'attribution_conflict',
  'N1(a): two authoritative projects quarantine the event as attribution_conflict');
select ok((pg_temp.evt_row('evt_ATTconf00001')).project_id is null
  and (pg_temp.evt_row('evt_ATTconf00001')).processing_status = 'quarantined',
  'no project is set on the conflicting event');
select is(pg_temp.cands('evt_ATTconf00001'),
  (select string_agg(c.project_id::text || '/' || c.source, ',' order by c.project_id, c.source)
     from private.financial_event_attribution(jsonb_build_object('id', 're_ATTconf00001', 'object', 'refund',
       'payment_intent', 'pi_ATTAinit01', 'invoice', 'in_ATTB00000'), null) c),
  'the recorded candidates are exactly the handler''s set');
select is((select count(*)::int from private.financial_event_project_candidates c
           where c.webhook_event_id = (pg_temp.evt_row('evt_ATTconf00001')).id), 3,
  'recorded once: A by payment link, B by payment link and checkout session');
select is((select count(*)::int from public.refunds where stripe_refund_id = 're_ATTconf00001')
  + (select count(*)::int from public.ledger_entries where stripe_object_id = 're_ATTconf00001'), 0,
  'no allocation, refund record or ledger entry from a conflict');
select is(pg_temp.deliver(pg_temp.evt('evt_ATTconf00001', 'refund.updated', jsonb_build_object('id', 're_ATTconf00001',
  'object', 'refund', 'amount', 1200, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_ATTAinit01',
  'invoice', 'in_ATTB00000', 'metadata', '{}'::jsonb), 10)) ->> 'duplicate', 'true', 'a replay is a duplicate');
select is((select count(*)::int from private.financial_event_project_candidates c
           where c.webhook_event_id = (pg_temp.evt_row('evt_ATTconf00001')).id), 3, 'the replay adds nothing');
select ok(pg_temp.g(pg_temp.pid('pa')) = '(f,f)' and pg_temp.g(pg_temp.pid('pb')) = '(f,f)',
  'N1(a): every candidate project fails G2 and G4');
select ok(pg_temp.blocking(pg_temp.pid('pa')) -> 'G2' ? 'quarantined_event' and pg_temp.blocking(pg_temp.pid('pa')) -> 'G4' ? 'quarantined_event'
  and pg_temp.blocking(pg_temp.pid('pb')) -> 'G2' ? 'quarantined_event' and pg_temp.blocking(pg_temp.pid('pb')) -> 'G4' ? 'quarantined_event',
  'the blocking kind is the existing quarantined_event (no new anomaly kind)');
select ok(not (pg_temp.blocking(pg_temp.pid('pa'))::text like '%' || pg_temp.pid('pb')::text || '%')
  and not ((private.project_financial_status(pg_temp.pid('pa'))).evidence::text like '%' || pg_temp.pid('pb')::text || '%'),
  'no candidate project ID appears in the gate evidence');
select ok((select summary -> 'candidate_project_ids' ? pg_temp.pid('pa')::text and summary -> 'candidate_project_ids' ? pg_temp.pid('pb')::text
           from public.audit_events where action = 'webhook.quarantined' and target_id = (pg_temp.evt_row('evt_ATTconf00001')).id::text)
  and (select category from public.audit_events where action = 'webhook.quarantined'
         and target_id = (pg_temp.evt_row('evt_ATTconf00001')).id::text) = 'financial',
  'the candidates appear in the Owner-only financial audit');

-- A later link neither re-points nor clears.
insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
values ('ch_ATTlater0001', pg_temp.pid('pa'), 'initial', split_part((select v from ids where k = 'ka'), ':', 2)::uuid, 'in_ATTA00000')
on conflict do nothing;
select pg_temp.svc($$ select public.run_billing_job('webhook_backfill') $$);
select ok((pg_temp.evt_row('evt_ATTconf00001')).project_id is null and (pg_temp.evt_row('evt_ATTconf00001')).processing_status = 'quarantined'
  and pg_temp.g(pg_temp.pid('pb')) = '(f,f)',
  'N1(a): a later link neither re-points the event nor clears the block');

-- Previous association preserved: attributed to A by invoice only (deferred), then a
-- conflicting payment link to B appears; the retry quarantines without re-pointing.
select is(pg_temp.deliver(pg_temp.evt('evt_ATTprev00002', 'refund.updated', jsonb_build_object('id', 're_ATTprev00002',
  'object', 'refund', 'amount', 300, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_ATTprevpi02',
  'invoice', 'in_ATTA00000', 'metadata', '{}'::jsonb), 20)) ->> 'status', 'deferred',
  'attributed to A by its invoice only: project set, charge evidence incomplete, deferred');
select is((pg_temp.evt_row('evt_ATTprev00002')).project_id, pg_temp.pid('pa'), 'the established project is A');
insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
values ('pi_ATTprevpi02', pg_temp.pid('pb'), 'initial', split_part((select v from ids where k = 'kb'), ':', 2)::uuid, 'in_ATTB00000');
select pg_temp.svc($$ select public.run_billing_job('webhook_backfill') $$);
select ok((pg_temp.evt_row('evt_ATTprev00002')).processing_status = 'quarantined'
  and (pg_temp.evt_row('evt_ATTprev00002')).quarantine_reason = 'attribution_conflict'
  and (pg_temp.evt_row('evt_ATTprev00002')).project_id = pg_temp.pid('pa'),
  'N1(a): the retry finds a second project, quarantines, and never re-points the previous association');

-- Resolution: records the review, re-checks and audits every candidate; the block persists.
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'res', public.resolve_quarantined_event((pg_temp.evt_row('evt_ATTconf00001')).id,
  'Reviewed: Stripe data inconsistent, both projects to be checked')::text;
reset role;
select ok((select (v::jsonb ->> 'ok')::boolean from ids where k = 'res')
  and (select jsonb_array_length(v::jsonb -> 'candidates') from ids where k = 'res') = 2,
  'the review is recorded and every candidate is re-checked');
select is((select count(*)::int from public.audit_events where action = 'quarantine.resolved'
           and target_id = (pg_temp.evt_row('evt_ATTconf00001')).id::text and summary ? 'gates'), 3,
  'each candidate is audited with its fresh evaluation (plus the event record)');
select ok((pg_temp.evt_row('evt_ATTconf00001')).quarantine_resolved_at is not null
  and pg_temp.g(pg_temp.pid('pa')) = '(f,f)' and pg_temp.g(pg_temp.pid('pb')) = '(f,f)',
  'OI-93: after the review the candidate blocks persist for every project');

-- Unrelated anomalies and unposted reversals still block independently.
select ok(pg_temp.blocking(pg_temp.pid('pa')) -> 'G2' ? 'unposted_reversal',
  'the deferred, unposted refund attributed to A still blocks as unposted_reversal');

-- The same design in handle_dispute and handle_charge_refunded: a charge recorded for B whose
-- payment intent is A's.
insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
values ('ch_ATTBcharge01', pg_temp.pid('pb'), 'initial', split_part((select v from ids where k = 'kb'), ':', 2)::uuid, 'in_ATTB00000');
select is(pg_temp.deliver(pg_temp.evt('evt_ATTdisp00001', 'charge.dispute.created', jsonb_build_object('id', 'dp_ATTdisp00001',
  'object', 'dispute', 'amount', 2000, 'currency', 'usd', 'status', 'needs_response', 'charge', 'ch_ATTBcharge01',
  'payment_intent', 'pi_ATTAinit01'), 30)) ->> 'reason', 'attribution_conflict',
  'N1(a): a dispute with conflicting authoritative projects is quarantined (handle_dispute)');
select ok((pg_temp.evt_row('evt_ATTdisp00001')).project_id is null
  and pg_temp.cands('evt_ATTdisp00001') like '%' || pg_temp.pid('pa')::text || '/payment_link%'
  and pg_temp.cands('evt_ATTdisp00001') like '%' || pg_temp.pid('pb')::text || '/payment_link%'
  and (select count(*) = 0 from public.disputes where stripe_dispute_id = 'dp_ATTdisp00001'),
  'no project set, both candidates recorded, no dispute record');
select is(pg_temp.deliver(pg_temp.evt('evt_ATTchrg00001', 'charge.refunded', jsonb_build_object('id', 'ch_ATTBcharge01',
  'object', 'charge', 'payment_intent', 'pi_ATTAinit01', 'invoice', 'in_ATTB00000', 'refunds', jsonb_build_object('data',
    jsonb_build_array(jsonb_build_object('id', 're_ATTchrg00001', 'object', 'refund', 'amount', 400, 'currency', 'usd',
      'status', 'succeeded', 'metadata', '{}'::jsonb)))), 31)) ->> 'reason', 'attribution_conflict',
  'N1(a): charge.refunded passes the charge''s identifiers to every refund (handle_charge_refunded)');
select ok((pg_temp.evt_row('evt_ATTchrg00001')).project_id is null
  and pg_temp.cands('evt_ATTchrg00001') like '%' || pg_temp.pid('pa')::text || '%'
  and pg_temp.cands('evt_ATTchrg00001') like '%' || pg_temp.pid('pb')::text || '%'
  and (select count(*) = 0 from public.refunds where stripe_refund_id = 're_ATTchrg00001'),
  'no project set, both candidates recorded, no refund record');

-- ---------------------------------------------------------------------------
-- 4. Candidate evidence is immutable and private; non-Owners see booleans only
-- ---------------------------------------------------------------------------
select throws_ok($$ update private.financial_event_project_candidates set source = 'payment_link' $$, '42501', null,
  'candidate rows cannot be updated');
select throws_ok($$ delete from private.financial_event_project_candidates $$, '42501', null,
  'candidate rows cannot be deleted');
select throws_ok($$ truncate private.financial_event_project_candidates $$, '42501', null,
  'candidate rows cannot be truncated');
select ok(not has_table_privilege('authenticated', 'private.financial_event_project_candidates', 'select')
  and not has_table_privilege('service_role', 'private.financial_event_project_candidates', 'select')
  and not has_table_privilege('anon', 'private.financial_event_project_candidates', 'select')
  and not has_function_privilege('authenticated', 'private.financial_event_attribution(jsonb, uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.financial_event_attribution(jsonb, uuid)', 'execute'),
  'no API role can read candidates or call the helper');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select results_eq($$ select deposit_requirement_satisfied, final_balance_requirement_satisfied, owner_intervention_required
    from public.operational_payment_states(array[pg_temp.pid('pb')]) $$,
  $$ values (false, false, true) $$, 'Admin sees derived booleans only for a candidate project');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok(not (public.project_billing_status(pg_temp.pid('pb'))::text like '%' || pg_temp.pid('pa')::text || '%'),
  'the client billing status names no other candidate project');
reset role;

select * from finish();
rollback;
