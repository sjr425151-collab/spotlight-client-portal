-- WP-B (AUTH-010, OI-93): Owner conflict decisions and financial applications. Covers the
-- AUTH-010 "Verification" row in the database: the records are private and insert-only and the
-- four U-2 functions are Owner-only; one decision per event, refused when it can never apply; a
-- decision alone never clears; every outcome (posted, represented, awaiting_evidence,
-- permanently_unsupported; operational_failure as a prior row, and live in the integration test);
-- S1 refunds, S2 disputes and S0 citations by exact entry; overlapping events and recognition under
-- another project; mixed charge.refunded events and whole-step rollback; idempotent
-- attempt_request_id; the 60-second interval, the fingerprint rule, the tenth attempt; oi93.fp.v1
-- stability and sensitivity per input class; re-verified block clearing; isolation. Real
-- concurrency, the client abort and the U-4 timeouts: tests/integration/oi93-conflict-decision.test.ts.
-- Synthetic data only; no Stripe request.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(151);

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

-- AUTH-010 helpers. Owner calls run at aal2 with fresh MFA and a live session.
create function pg_temp.owner(p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
  execute p_sql into v;
  reset role;
  return v;
end;
$$;
create function pg_temp.eid(p_stripe_event_id text) returns bigint language sql as $$
  select id from public.webhook_events where stripe_event_id = p_stripe_event_id;
$$;
create function pg_temp.decide(p_evt text, p_project uuid) returns jsonb language sql as $$
  select pg_temp.owner(format('select public.record_financial_conflict_decision(%s, %L, %L::jsonb, %L)',
    pg_temp.eid(p_evt), p_project, '{"stripe_dashboard_review": "synthetic reference"}', 'Owner reviewed the provider evidence'));
$$;
create function pg_temp.attempt(p_decision uuid, p_request uuid) returns jsonb language sql as $$
  select pg_temp.owner(format('select public.retry_financial_conflict_application(%L, %L, %L)', p_decision, p_request,
    'Apply the recorded decision'));
$$;
create function pg_temp.dec(p_evt text) returns uuid language sql as $$
  select d.id from private.financial_conflict_decisions d where d.webhook_event_id = pg_temp.eid(p_evt);
$$;
create function pg_temp.fp(p_evt text) returns text language sql as $$
  select private.financial_conflict_fingerprint(pg_temp.dec(p_evt));
$$;
create function pg_temp.apps(p_evt text) returns text language sql as $$
  select coalesce(string_agg(a.attempt_no || ':' || a.outcome || coalesce(':' || a.terminal_reason, ''), ',' order by a.attempt_no), '')
    from private.financial_conflict_applications a where a.webhook_event_id = pg_temp.eid(p_evt);
$$;
create function pg_temp.cleared(p_evt text) returns boolean language sql as $$
  select private.financial_conflict_cleared(pg_temp.eid(p_evt));
$$;
-- Earlier durable attempts (fixture rows written directly, as the time rules need past attempts).
create function pg_temp.past_attempt(p_evt text, p_no integer, p_outcome text, p_fp text, p_age interval) returns void
language sql as $$
  insert into private.financial_conflict_applications (decision_id, webhook_event_id, project_id, attempt_no,
    attempt_request_id, category, outcome, terminal_reason, fingerprint, reason, requested_by, created_at)
  select d.id, d.webhook_event_id, d.project_id, p_no, gen_random_uuid(), 'S1', p_outcome,
         case when p_no = 10 and p_outcome not in ('posted', 'represented') then 'exhausted' end, p_fp,
         'earlier attempt (fixture)', '00000000-0000-4000-8000-000000000001', now() - p_age
    from private.financial_conflict_decisions d where d.webhook_event_id = pg_temp.eid(p_evt);
$$;
-- A refund event that names a payment intent, optionally a charge and an invoice.
create function pg_temp.refund_evt(p_id text, p_type text, p_re text, p_amount bigint, p_pi text, p_charge text, p_invoice text,
  p_offset integer, p_decision uuid default null, p_status text default 'succeeded') returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, p_type, jsonb_strip_nulls(jsonb_build_object('id', p_re, 'object', 'refund',
    'amount', p_amount, 'currency', 'usd', 'status', p_status, 'payment_intent', p_pi, 'charge', p_charge, 'invoice', p_invoice))
    || jsonb_build_object('metadata', case when p_decision is null then '{}'::jsonb
                                           else jsonb_build_object('refund_decision_id', p_decision) end), p_offset));
$$;
create function pg_temp.charge_refunded(p_id text, p_charge text, p_pi text, p_invoice text, p_refunds jsonb, p_offset integer)
returns jsonb language sql as $$
  select pg_temp.deliver(pg_temp.evt(p_id, 'charge.refunded', jsonb_build_object('id', p_charge, 'object', 'charge',
    'payment_intent', p_pi, 'invoice', p_invoice, 'refunds', jsonb_build_object('data', p_refunds)), p_offset));
$$;
create function pg_temp.re(p_id text, p_amount bigint) returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'object', 'refund', 'amount', p_amount, 'currency', 'usd', 'status', 'succeeded',
    'metadata', '{}'::jsonb);
$$;
create function pg_temp.req(p_k text) returns uuid language plpgsql as $$
begin
  insert into ids values (p_k, gen_random_uuid()::text) on conflict (k) do nothing;
  return pg_temp.pid(p_k);
end;
$$;
-- A renewal invoice paid through real events (posts the renewal charge's maintenance obligation).
create function pg_temp.renewal(p_project uuid, p_tag text, p_pi text, p_offset integer) returns jsonb language plpgsql as $$
begin
  perform pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'subs0001', 'customer.subscription.created', jsonb_build_object(
    'id', 'sub_' || p_tag || '00000', 'object', 'subscription', 'status', 'active', 'customer', 'cus_T' || p_tag || '00000',
    'metadata', jsonb_build_object('project_id', p_project)), p_offset));
  return pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'renew001', 'invoice.paid', jsonb_build_object('id', 'in_' || p_tag || 'renew01',
    'object', 'invoice', 'billing_reason', 'subscription_cycle', 'currency', 'usd', 'amount_paid', 9900,
    'customer', 'cus_T' || p_tag || '00000', 'subscription', 'sub_' || p_tag || '00000', 'payment_intent', p_pi,
    'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
      'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))), p_offset + 1));
end;
$$;
create function pg_temp.renewal_ob(p_tag text) returns uuid language sql as $$
  select id from public.payment_obligations where charge_key = 'renewal:in_' || p_tag || 'renew01';
$$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

-- Projects through the real workflow: each paid at checkout (its initial charge's obligations are
-- posted); A, C and J also have their initial invoice linked.
insert into ids select 'pa', pg_temp.paid_project('CFA', null)::text;
insert into ids select 'pb', pg_temp.paid_project('CFB', null)::text;
insert into ids select 'pc', pg_temp.paid_project('CFC', null)::text;
insert into ids select 'pd', pg_temp.paid_project('CFD', null)::text;
insert into ids select 'pf', pg_temp.paid_project('CFF', null)::text;
insert into ids select 'pg', pg_temp.paid_project('CFG', null)::text;
insert into ids select 'ph', pg_temp.paid_project('CFH', null)::text;
insert into ids select 'pj', pg_temp.paid_project('CFJ', null)::text;
insert into ids select 'pk', pg_temp.paid_project('CFK', null)::text;
select pg_temp.initial_invoice(pg_temp.pid('pa'), 'CFA');
select pg_temp.initial_invoice(pg_temp.pid('pc'), 'CFC');
select pg_temp.initial_invoice(pg_temp.pid('pj'), 'CFJ');
-- Recorded payment links of renewal charges whose obligations are not posted yet (the renewal
-- invoice not yet paid): the authoritative relationship exists, the money does not.
insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id) values
  ('ch_CFBfake0001', pg_temp.pid('pb'), 'renewal', null, 'in_CFBrenew01'),
  ('pi_CFDfake0001', pg_temp.pid('pd'), 'renewal', null, 'in_CFDrenew01'),
  ('ch_CFJfake0001', pg_temp.pid('pj'), 'renewal', null, 'in_CFJrenew01');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'dA', public.record_refund_decision(pg_temp.pid('pa'), 500, 'Partial refund of the deposit',
  jsonb_build_array(jsonb_build_object('obligation_id', pg_temp.ob(pg_temp.pid('pa'), 'development_deposit'), 'amount_cents', 500)))
  ->> 'refund_decision_id';
insert into ids select 'dC', public.record_refund_decision(pg_temp.pid('pc'), 500, 'Refund for project C',
  jsonb_build_array(jsonb_build_object('obligation_id', pg_temp.ob(pg_temp.pid('pc'), 'development_deposit'), 'amount_cents', 500)))
  ->> 'refund_decision_id';
reset role;
select ok(pg_temp.ob(pg_temp.pid('pa'), 'development_deposit') is not null and pg_temp.ob(pg_temp.pid('pc'), 'development_deposit') is not null
  and not exists (select 1 from public.payment_obligations where charge_key like 'renewal:in_CF%renew01')
  and (select stripe_invoice_id from public.checkout_sessions where project_id = pg_temp.pid('pb')) = 'in_CFB00000',
  'fixtures: the initial charges hold posted obligations; the linked renewal charges do not yet');

-- ---------------------------------------------------------------------------
-- 1. Records and functions: private, insert-only, Owner-only (U-2), isolation
-- ---------------------------------------------------------------------------
select ok(not exists (
    select 1 from unnest(array['private.financial_conflict_decisions', 'private.financial_conflict_applications',
      'private.financial_conflict_effects', 'private.financial_conflict_application_entries']) t(n)
     cross join unnest(array['anon', 'authenticated', 'service_role']) r(r)
     cross join unnest(array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger']) p(p)
     where has_table_privilege(r.r, t.n, p.p)),
  'the four AUTH-010 tables grant nothing to anon, authenticated or service_role');
select ok((select count(*) = 8 from pg_trigger g join pg_class c on c.oid = g.tgrelid join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'private' and not g.tgisinternal and c.relname in ('financial_conflict_decisions',
              'financial_conflict_applications', 'financial_conflict_effects', 'financial_conflict_application_entries')
              and g.tgname ~ '_(insert_only|no_truncate)$'),
  'each table has its insert-only and no-truncate triggers');
select is((select array_agg(p.oid::regprocedure::text order by p.oid::regprocedure::text) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('record_financial_conflict_decision', 'retry_financial_conflict_application',
             'financial_conflict_attempt_status', 'financial_conflict_events')
             and not p.prosecdef and p.proconfig @> array['search_path=""', 'lock_timeout=5s']
             and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('public', p.oid, 'execute')),
  array['financial_conflict_attempt_status(uuid)', 'financial_conflict_events()',
        'record_financial_conflict_decision(bigint,uuid,jsonb,text)', 'retry_financial_conflict_application(uuid,uuid,text)'],
  'U-2, I-1 (b): the four wrappers with the exact signatures: INVOKER, empty search_path, 5 s lock_timeout, authenticated only');
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'private' and p.proname in ('record_financial_conflict_decision', 'retry_financial_conflict_application',
             'financial_conflict_attempt_status', 'financial_conflict_events')
             and p.prosecdef and p.proconfig = array['search_path=""']
             and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute')
             and not has_function_privilege('service_role', p.oid, 'execute') and not has_function_privilege('public', p.oid, 'execute')),
  array['financial_conflict_attempt_status', 'financial_conflict_events', 'record_financial_conflict_decision',
        'retry_financial_conflict_application'],
  'U-2, I-1 (b), (c): the private functions are SECURITY DEFINER with an empty search_path, executable by authenticated only (the wrapper''s caller), never anon, service_role or PUBLIC');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname in ('apply_refund_for_project', 'apply_dispute_for_project', 'charge_refunded_objects',
     'financial_conflict_scope', 'financial_conflict_classify', 'oi93_canonical_json', 'financial_conflict_fingerprint',
     'financial_conflict_effect_type', 'financial_conflict_application_verified', 'financial_conflict_cleared',
     'financial_conflict_attempt_summary')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('service_role', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))),
  'the internal functions are executable by no API role');

-- ---------------------------------------------------------------------------
-- 2. S1 posted: a refund on A's charge naming B's invoice; exactly A holds the obligations
-- ---------------------------------------------------------------------------
select is(pg_temp.refund_evt('evt_CFpost000001', 'refund.updated', 're_CFpost000001', 500, 'pi_CFAinit01', 'ch_CFBfake0001', null, 10,
  pg_temp.pid('dA')) ->> 'reason', 'attribution_conflict', 'a refund on A''s payment intent and B''s recorded charge is a conflict');
select ok(pg_temp.g(pg_temp.pid('pa')) = '(f,f)' and pg_temp.blocking(pg_temp.pid('pb')) -> 'G2' ? 'quarantined_event',
  'every candidate is blocked before any decision');

-- Decisions: refusals first (no row), then the valid one.
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.record_financial_conflict_decision(pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', 'admin') ->> 'error',
  'forbidden', 'Admin cannot record a decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.record_financial_conflict_decision(pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', 'sales') ->> 'error',
  'forbidden', 'Sales cannot record a decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is(public.record_financial_conflict_decision(pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', 'client') ->> 'error',
  'forbidden', 'a client cannot record a decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', false);
select is(public.record_financial_conflict_decision(pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', 'stale') ->> 'error',
  'forbidden', 'the Owner without fresh MFA cannot record a decision');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal1', true);
select is(public.record_financial_conflict_decision(pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', 'aal1') ->> 'error',
  'forbidden', 'the Owner at aal1 cannot record a decision');
reset role;
select is(pg_temp.owner(format('select public.record_financial_conflict_decision(%s, %L, %L::jsonb, %L)',
  pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', '   ')) ->> 'error', 'reason_required', 'a reason is required');
select is(pg_temp.owner(format('select public.record_financial_conflict_decision(%s, %L, %L::jsonb, %L)',
  pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{}', 'no evidence')) ->> 'error', 'evidence_invalid',
  'evidence references are required');
select is(pg_temp.decide('evt_CFpost000001', pg_temp.pid('pc')) ->> 'error', 'not_a_candidate',
  'a project that is not a recorded candidate cannot be chosen');
select is(pg_temp.decide('evt_CFpost000001', pg_temp.pid('pb')) ->> 'error', 'conflict_unsupported',
  'a candidate that does not hold the obligations is refused (one decision per event)');
select is((select count(*)::int from private.financial_conflict_decisions where webhook_event_id = pg_temp.eid('evt_CFpost000001')), 0,
  'refusals record no decision');
select ok((pg_temp.decide('evt_CFpost000001', pg_temp.pid('pa')) ->> 'ok')::boolean, 'the Owner records the decision for A');
select ok((select category = 'financial' and reason = 'Owner reviewed the provider evidence' and project_id = pg_temp.pid('pa')
             and summary ->> 'decision_id' = pg_temp.dec('evt_CFpost000001')::text
             and summary -> 'candidate_project_ids' ? pg_temp.pid('pb')::text
           from public.audit_events where action = 'financial_conflict.decision_recorded'
             and target_id = pg_temp.eid('evt_CFpost000001')::text),
  'U-1: financial_conflict.decision_recorded, financial, with the reason and every candidate');
select is(pg_temp.decide('evt_CFpost000001', pg_temp.pid('pa')) ->> 'error', 'already_decided', 'one decision per event');
select ok(pg_temp.g(pg_temp.pid('pa')) = '(f,f)' and pg_temp.blocking(pg_temp.pid('pb')) -> 'G2' ? 'quarantined_event'
  and not pg_temp.cleared('evt_CFpost000001'),
  'a decision alone never clears a block');

-- Attempts: refused callers, then the application.
insert into ids select 'dec_post', pg_temp.dec('evt_CFpost000001')::text;
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select is(public.retry_financial_conflict_application(pg_temp.pid('dec_post'), gen_random_uuid(), 'admin') ->> 'error',
  'forbidden', 'Admin cannot apply a decision');
reset role;
select is(pg_temp.owner(format('select public.retry_financial_conflict_application(%L, %L, %L)', pg_temp.dec('evt_CFpost000001'),
  gen_random_uuid(), '')) ->> 'error', 'reason_required', 'an attempt needs a reason');
insert into ids select 'r_post', pg_temp.attempt(pg_temp.dec('evt_CFpost000001'), pg_temp.req('q_post'))::text;
select is((select v::jsonb #>> '{attempt,outcome}' from ids where k = 'r_post'), 'posted', 'S1: the application is posted');
select ok((select l.project_id = pg_temp.pid('pa') and l.obligation_id = pg_temp.ob(pg_temp.pid('pa'), 'development_deposit')
             and l.amount_cents = -500 and l.webhook_event_id = pg_temp.eid('evt_CFpost000001') and l.source = 'webhook'
           from public.ledger_entries l where l.stripe_object_id = 're_CFpost000001')
  and (select project_id = pg_temp.pid('pa') and refund_decision_id = pg_temp.pid('dA') from public.refunds
        where stripe_refund_id = 're_CFpost000001'),
  'posted through the existing ledger rules: the recorded allocation, under A, from the verified event');
select ok((select count(*) = 1 and bool_and(x.role = 'new' and x.project_id = pg_temp.pid('pa')) from private.financial_conflict_application_entries x
            join private.financial_conflict_applications a on a.id = x.application_id
           where a.webhook_event_id = pg_temp.eid('evt_CFpost000001'))
  and (select count(*) = 1 from private.financial_conflict_effects f where f.stripe_object_id = 're_CFpost000001'
         and f.effect_type = 'refund' and f.amount_cents = 500 and f.project_id = pg_temp.pid('pa')),
  'the entry is recorded as new and the effect is recognized once (provider object, effect type, amount)');
select ok((pg_temp.evt_row('evt_CFpost000001')).processing_status = 'quarantined'
  and (pg_temp.evt_row('evt_CFpost000001')).project_id is null
  and (pg_temp.evt_row('evt_CFpost000001')).quarantine_reason = 'attribution_conflict',
  'the original event stays immutable and quarantined (no guard transition)');
select ok(pg_temp.cleared('evt_CFpost000001') and not (pg_temp.blocking(pg_temp.pid('pb'))::text like '%quarantined_event%')
  and not coalesce(pg_temp.blocking(pg_temp.pid('pa'))::text like '%quarantined_event%', false),
  'block clearing: the re-verified application clears the block for every candidate');
select ok((select category = 'financial' and summary ->> 'outcome' = 'posted' and reason = 'Apply the recorded decision'
           from public.audit_events where action = 'financial_conflict.attempt_recorded'
             and summary ->> 'attempt_request_id' = pg_temp.pid('q_post')::text),
  'U-1: financial_conflict.attempt_recorded, financial, with the outcome and the reason');
-- Idempotency and terminal success.
select ok((pg_temp.attempt(pg_temp.dec('evt_CFpost000001'), pg_temp.pid('q_post')) ->> 'existing')::boolean
  and pg_temp.apps('evt_CFpost000001') = '1:posted'
  and (select count(*) = 1 from public.ledger_entries where stripe_object_id = 're_CFpost000001'),
  'the same attempt_request_id returns the recorded attempt and adds nothing');
select is(pg_temp.attempt(pg_temp.dec('evt_CFpost000001'), gen_random_uuid()) ->> 'error', 'already_applied',
  'a new attempt after success is refused');
select ok(pg_temp.apps('evt_CFpost000001') = '1:posted'
  and (select summary ->> 'refusal' = 'already_applied' and category = 'financial' from public.audit_events
        where action = 'financial_conflict.attempt_refused' order by id desc limit 1),
  'the refusal writes no attempt row and is audited as financial_conflict.attempt_refused');

-- Attempt status (unknown-outcome recovery) and the conflict list.
select ok((select s ->> 'status' = 'recorded' and (s ->> 'conclusive')::boolean and s #>> '{attempt,outcome}' = 'posted'
           from (select pg_temp.owner(format('select public.financial_conflict_attempt_status(%L)', pg_temp.pid('q_post'))) s) x),
  'status of a committed attempt: recorded, conclusive');
select ok((select s ->> 'status' = 'not_recorded' and not (s ->> 'conclusive')::boolean
           from (select pg_temp.owner(format('select public.financial_conflict_attempt_status(%L)', gen_random_uuid())) s) x),
  'status of an unknown request: not recorded, and not conclusive (a missing record is not a rollback)');
select ok((select (e ->> 'cleared')::boolean and e #>> '{decision,project_id}' = pg_temp.pid('pa')::text
             and jsonb_array_length(e -> 'candidates') = 2 and jsonb_array_length(e -> 'attempts') = 1
           from jsonb_array_elements(pg_temp.owner('select public.financial_conflict_events()') -> 'events') e
          where (e ->> 'webhook_event_id')::bigint = pg_temp.eid('evt_CFpost000001')),
  'financial_conflict_events lists the event, its candidates, decision, attempts and clearing');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2', true);
select ok(public.financial_conflict_events() ->> 'error' = 'forbidden'
  and public.financial_conflict_attempt_status(pg_temp.pid('q_post')) ->> 'error' = 'forbidden',
  'Admin cannot read the conflict list or an attempt status');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok(public.financial_conflict_events() ->> 'error' = 'forbidden'
  and not (public.project_billing_status(pg_temp.pid('pb'))::text like '%' || pg_temp.pid('pa')::text || '%'),
  'a client cannot read the conflict list and sees no other project');
reset role;
set local role anon;
select throws_ok($$ select public.financial_conflict_events() $$, '42501', null, 'anon cannot call the functions');
reset role;

-- OI-120: is_owner() is NULL (not false) for a caller with no staff role, so every guard is
-- NULL-safe. Each of the four functions refuses every non-Owner caller, a fresh-MFA client and a
-- revoked former Owner included, and an Owner without fresh MFA.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, reauthentication_token, phone_change, phone_change_token)
values ('00000000-0000-0000-0000-000000000000', '00000000-0000-4000-8000-0000000000f1', 'authenticated', 'authenticated',
  'former.owner@example.test', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(),
  '', '', '', '', '', '', '', '');
insert into public.profiles (id, email, full_name)
values ('00000000-0000-4000-8000-0000000000f1', 'former.owner@example.test', 'Former Owner');
insert into public.staff_roles (user_id, role, status, revoked_at, reason)
values ('00000000-0000-4000-8000-0000000000f1', 'owner', 'revoked', now(), 'former staff (fixture)');
create function pg_temp.all_forbidden() returns boolean language sql as $$
  select public.record_financial_conflict_decision(pg_temp.eid('evt_CFpost000001'), pg_temp.pid('pa'), '{"r": 1}', 'x') ->> 'error' = 'forbidden'
     and public.retry_financial_conflict_application(pg_temp.pid('dec_post'), gen_random_uuid(), 'x') ->> 'error' = 'forbidden'
     and public.financial_conflict_attempt_status(pg_temp.pid('q_post')) ->> 'error' = 'forbidden'
     and public.financial_conflict_events() ->> 'error' = 'forbidden';
$$;
grant execute on function pg_temp.all_forbidden() to authenticated;
create function pg_temp.forbidden_for(p_uid uuid, p_aal text, p_fresh boolean) returns boolean language plpgsql as $$
declare
  v boolean;
begin
  perform pg_temp.act_as(p_uid, p_aal, p_fresh);
  v := pg_temp.all_forbidden();
  reset role;
  return v;
end;
$$;
select ok(pg_temp.forbidden_for('00000000-0000-4000-8000-0000000000a1', 'aal2', true),
  'OI-120: a client with a verified factor, fresh TOTP and a live session is refused by all four functions');
select ok(pg_temp.forbidden_for('00000000-0000-4000-8000-0000000000f1', 'aal2', true),
  'OI-120: a revoked former Owner with fresh MFA is refused by all four functions');
select ok(pg_temp.forbidden_for('00000000-0000-4000-8000-000000000002', 'aal2', true),
  'Admin with fresh MFA is refused by all four functions');
select ok(pg_temp.forbidden_for('00000000-0000-4000-8000-000000000005', 'aal2', true),
  'Sales with fresh MFA is refused by all four functions');
select ok(pg_temp.forbidden_for('00000000-0000-4000-8000-000000000001', 'aal2', false),
  'the Owner without fresh MFA is refused by all four functions');
select is((select count(*)::int from private.financial_conflict_applications where webhook_event_id = pg_temp.eid('evt_CFpost000001')), 1,
  'the refused callers recorded nothing');

-- ---------------------------------------------------------------------------
-- 3. S0 represented: the effect is already in the ledger under A; overlapping events cite it
-- ---------------------------------------------------------------------------
select is(pg_temp.refund_evt('evt_CFs0norm0001', 'refund.created', 're_CFs00000001', 100, 'pi_CFAinit01', null, null, 20) ->> 'status',
  'processed', 'the refund is first processed normally for A');
insert into ids select 'g_a1', pg_temp.g(pg_temp.pid('pa'));
select is(pg_temp.refund_evt('evt_CFs0conf0001', 'refund.updated', 're_CFs00000001', 100, 'pi_CFAinit01', 'ch_CFBfake0001', null, 21)
  ->> 'reason', 'attribution_conflict', 'a later event for the same refund names B''s recorded charge: conflict');
select is((pg_temp.decide('evt_CFs0conf0001', pg_temp.pid('pb')) -> 'classification' -> 'objects' -> 0 ->> 'reason'),
  'recognized_under_other_project', 'choosing B is refused: the effect is recognized under another project');
select ok((pg_temp.decide('evt_CFs0conf0001', pg_temp.pid('pa')) ->> 'ok')::boolean, 'decision for A');
select is(pg_temp.attempt(pg_temp.dec('evt_CFs0conf0001'), pg_temp.req('q_s0a')) #>> '{attempt,outcome}', 'represented',
  'S0: an effect already in the ledger under the chosen project is represented');
select ok((select count(*) = 1 and bool_and(x.role = 'cited' and x.webhook_event_id_ok) from (
             select x.role, l.webhook_event_id = pg_temp.eid('evt_CFs0norm0001') as webhook_event_id_ok
               from private.financial_conflict_application_entries x
               join private.financial_conflict_applications a on a.id = x.application_id
               join public.ledger_entries l on l.id = x.ledger_entry_id
              where a.webhook_event_id = pg_temp.eid('evt_CFs0conf0001')) x)
  and (select count(*) = 1 from public.ledger_entries where stripe_object_id = 're_CFs00000001'),
  'S0: the exact existing entry is cited; no money is created, moved or re-recognized');
select ok(pg_temp.cleared('evt_CFs0conf0001') and (select v from ids where k = 'g_a1') = pg_temp.g(pg_temp.pid('pa')),
  'the represented application clears the block; A''s gates are as before the conflicting event');
select is(pg_temp.refund_evt('evt_CFs0conf0002', 'charge.refund.updated', 're_CFs00000001', 100, 'pi_CFAinit01', 'ch_CFBfake0001', null, 22)
  ->> 'reason', 'attribution_conflict', 'an overlapping third event for the same refund is also a conflict');
select pg_temp.decide('evt_CFs0conf0002', pg_temp.pid('pa'));
select is(pg_temp.attempt(pg_temp.dec('evt_CFs0conf0002'), pg_temp.req('q_s0b')) #>> '{attempt,outcome}', 'represented',
  'any number of events may cite a recognized effect');
select ok((select count(*) = 1 from private.financial_conflict_effects where stripe_object_id = 're_CFs00000001')
  and (select array_agg(distinct x.effect_id) from private.financial_conflict_application_entries x
         join private.financial_conflict_applications a on a.id = x.application_id
        where a.webhook_event_id in (pg_temp.eid('evt_CFs0conf0001'), pg_temp.eid('evt_CFs0conf0002'))) =
      (select array_agg(id) from private.financial_conflict_effects where stripe_object_id = 're_CFs00000001'),
  'one recognition per effect key, cited by both events with the same exact entry');
select ok((select bool_and(l.webhook_event_id = pg_temp.eid('evt_CFs0norm0001') and x.role = 'cited')
             and bool_and(f.recognized_by_application_id = (select id from private.financial_conflict_applications
                                                              where attempt_request_id = pg_temp.pid('q_s0a')))
           from private.financial_conflict_effects f
           join private.financial_conflict_application_entries x on x.effect_id = f.id
           join public.ledger_entries l on l.id = x.ledger_entry_id
          where f.stripe_object_id = 're_CFs00000001'),
  'I-6: the recognition''s provenance is its cited entries'' source event (the normal refund event), recognized once');

-- ---------------------------------------------------------------------------
-- 4. charge.refunded: new and represented refunds in one step; a failure rolls the step back
-- ---------------------------------------------------------------------------
select is(pg_temp.charge_refunded('evt_CFmix000001', 'ch_CFBfake0001', 'pi_CFAinit01', null,
  jsonb_build_array(pg_temp.re('re_CFs00000001', 100), pg_temp.re('re_CFmix000001', 200)), 30) ->> 'reason', 'attribution_conflict',
  'a charge.refunded event with a represented and a new refund is a conflict');
select pg_temp.decide('evt_CFmix000001', pg_temp.pid('pa'));
select is(pg_temp.attempt(pg_temp.dec('evt_CFmix000001'), pg_temp.req('q_mix')) #>> '{attempt,outcome}', 'posted',
  'any new refund: posted');
select is((select string_agg(x.stripe_object_id || ':' || x.role, ',' order by x.stripe_object_id) from private.financial_conflict_application_entries x
            join private.financial_conflict_applications a on a.id = x.application_id
           where a.webhook_event_id = pg_temp.eid('evt_CFmix000001')),
  're_CFmix000001:new,re_CFs00000001:cited', 'roles new and cited in one application');
select is(pg_temp.charge_refunded('evt_CFrbk000001', 'ch_CFBfake0001', 'pi_CFAinit01', null,
  jsonb_build_array(pg_temp.re('re_CFrbk000001', 300), pg_temp.re('re_CFrbk000002', 9999999)), 31) ->> 'reason', 'attribution_conflict',
  'a charge.refunded event whose second refund exceeds the charge is a conflict');
select pg_temp.decide('evt_CFrbk000001', pg_temp.pid('pa'));
insert into ids select 'r_rbk', pg_temp.attempt(pg_temp.dec('evt_CFrbk000001'), pg_temp.req('q_rbk'))::text;
select is((select v::jsonb #>> '{attempt,outcome}' from ids where k = 'r_rbk'), 'permanently_unsupported',
  'any unsupported refund: the outcome is permanently_unsupported');
select ok((select count(*) = 0 from public.ledger_entries where stripe_object_id in ('re_CFrbk000001', 're_CFrbk000002'))
  and (select count(*) = 0 from public.refunds where stripe_refund_id in ('re_CFrbk000001', 're_CFrbk000002'))
  and (select count(*) = 0 from private.financial_conflict_effects where stripe_object_id like 're_CFrbk%'),
  'whole-step rollback: nothing of the first refund is kept');
select is((select string_agg(o ->> 'object_id' || ':' || (o ->> 'result'), ',' order by (o ->> 'ord')::int)
             from ids, jsonb_array_elements(v::jsonb #> '{attempt,detail,objects}') o where k = 'r_rbk'),
  're_CFrbk000001:processed,re_CFrbk000002:quarantined:reversal_exceeds_charge', 'the detail is per refund');
select ok(not pg_temp.cleared('evt_CFrbk000001') and pg_temp.g(pg_temp.pid('pa')) = '(f,f)',
  'a failed attempt never clears the block');
select is(pg_temp.attempt(pg_temp.dec('evt_CFrbk000001'), gen_random_uuid()) ->> 'error', 'permanently_unsupported',
  'permanently_unsupported is terminal');

-- ---------------------------------------------------------------------------
-- 5. S2 disputes: opened, then won (cited and new)
-- ---------------------------------------------------------------------------
select is(pg_temp.deliver(pg_temp.evt('evt_CFdsp000001', 'charge.dispute.created', jsonb_build_object('id', 'dp_CFdsp000001',
  'object', 'dispute', 'amount', 2000, 'currency', 'usd', 'status', 'needs_response', 'charge', 'ch_CFBfake0001',
  'payment_intent', 'pi_CFAinit01'), 40)) ->> 'reason', 'attribution_conflict',
  'a dispute on A''s payment intent and B''s recorded charge is a conflict');
select pg_temp.decide('evt_CFdsp000001', pg_temp.pid('pa'));
select is(pg_temp.attempt(pg_temp.dec('evt_CFdsp000001'), pg_temp.req('q_dsp1')) #>> '{attempt,category}', 'S2', 'S2 category');
select ok((select project_id = pg_temp.pid('pa') and status = 'needs_response' from public.disputes where stripe_dispute_id = 'dp_CFdsp000001')
  and (select bool_and(project_id = pg_temp.pid('pa')) and sum(amount_cents) = -2000 from public.ledger_entries
        where stripe_object_id = 'dp_CFdsp000001' and entry_type = 'dispute_opened')
  and pg_temp.apps('evt_CFdsp000001') = '1:posted' and pg_temp.cleared('evt_CFdsp000001'),
  'S2: the dispute and its withdrawal are posted under A by the existing rules');
select is(pg_temp.deliver(pg_temp.evt('evt_CFdsp000002', 'charge.dispute.closed', jsonb_build_object('id', 'dp_CFdsp000001',
  'object', 'dispute', 'amount', 2000, 'currency', 'usd', 'status', 'won', 'charge', 'ch_CFBfake0001',
  'payment_intent', 'pi_CFAinit01'), 41)) ->> 'reason', 'attribution_conflict', 'the won event is also a conflict');
select pg_temp.decide('evt_CFdsp000002', pg_temp.pid('pa'));
select is(pg_temp.attempt(pg_temp.dec('evt_CFdsp000002'), pg_temp.req('q_dsp2')) #>> '{attempt,outcome}', 'posted',
  'the reinstatement is posted');
select is((select string_agg(distinct f.effect_type || ':' || x.role, ',') from private.financial_conflict_application_entries x
            join private.financial_conflict_applications a on a.id = x.application_id
            join private.financial_conflict_effects f on f.id = x.effect_id
           where a.webhook_event_id = pg_temp.eid('evt_CFdsp000002')),
  'dispute_opened:cited,dispute_won:new', 'the withdrawal is cited and the reinstatement is new');

-- ---------------------------------------------------------------------------
-- 6. The unsupported list (classifier)
-- ---------------------------------------------------------------------------
select is(pg_temp.refund_evt('evt_CFsev000001', 'refund.updated', 're_CFsev000001', 100, 'pi_CFAinit01', null, 'in_CFC00000', 50)
  ->> 'reason', 'attribution_conflict', 'A''s payment intent and C''s invoice: both hold obligations');
select ok(pg_temp.decide('evt_CFsev000001', pg_temp.pid('pa')) #>> '{classification,objects,0,reason}' = 'obligations_several_projects'
  and pg_temp.decide('evt_CFsev000001', pg_temp.pid('pc')) #>> '{classification,objects,0,reason}' = 'obligations_several_projects'
  and pg_temp.dec('evt_CFsev000001') is null,
  'unsupported: obligations under several projects (no decision recorded)');
select is(pg_temp.refund_evt('evt_CFrdc000001', 'refund.updated', 're_CFrdc000001', 500, 'pi_CFAinit01', 'ch_CFBfake0001', null, 51,
  pg_temp.pid('dC')) ->> 'reason', 'attribution_conflict', 'a refund naming C''s refund decision');
select is(pg_temp.decide('evt_CFrdc000001', pg_temp.pid('pa')) #>> '{classification,objects,0,reason}', 'refund_decision_other_project',
  'unsupported: a refund decision whose project differs');
select is(pg_temp.refund_evt('evt_CFamt000001', 'refund.created', 're_CFamt000001', 100, 'pi_CFAinit01', null, null, 52) ->> 'status',
  'processed', 'a normal refund');
select is(pg_temp.refund_evt('evt_CFamt000002', 'refund.updated', 're_CFamt000001', 150, 'pi_CFAinit01', null, null, 53) ->> 'reason',
  'refund_amount_changed', 'its amount changes: quarantined for another reason');
select is(pg_temp.decide('evt_CFamt000002', pg_temp.pid('pa')) ->> 'error', 'not_eligible',
  'unsupported: another quarantine reason cannot be decided');
select is(private.financial_conflict_classify(jsonb_populate_record(pg_temp.evt_row('evt_CFsev000001'),
  '{"livemode": true}'::jsonb), pg_temp.pid('pa')) ->> 'reason', 'livemode_mismatch', 'unsupported: a livemode failure');
select is(private.financial_conflict_classify(jsonb_populate_record(pg_temp.evt_row('evt_CFsev000001'),
  '{"event_type": "invoice.paid"}'::jsonb), pg_temp.pid('pa')) ->> 'reason', 'event_type_unsupported',
  'unsupported: another event type');
select is(private.financial_conflict_classify(jsonb_populate_record(pg_temp.evt_row('evt_CFsev000001'),
  jsonb_build_object('payload', jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('object', 'refund',
    'amount', 100, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_CFAinit01'))))), pg_temp.pid('pa'))
  #>> '{objects,0,reason}', 'unresolvable_reference', 'unsupported: an unresolvable reference');
select is(private.financial_conflict_classify(jsonb_populate_record(pg_temp.evt_row('evt_CFsev000001'),
  jsonb_build_object('payload', jsonb_build_object('data', jsonb_build_object('object', jsonb_build_object('id', 're_CFsev000001',
    'object', 'refund', 'amount', 100, 'currency', 'eur', 'status', 'succeeded', 'payment_intent', 'pi_CFAinit01'))))),
  pg_temp.pid('pa')) #>> '{objects,0,reason}', 'invalid_object', 'unsupported: a validity failure');

-- ---------------------------------------------------------------------------
-- 7. Not yet resolvable, awaiting_evidence, the 60-second interval, the fingerprint rule, the tenth
--    attempt, and a second holder appearing after the decision
-- ---------------------------------------------------------------------------
-- I-4: no candidate holds the obligations yet (B's and D's recorded renewal charges): the decision
-- is refused, with no row, and the refusal is audited durably (Amendment 2).
select is(pg_temp.refund_evt('evt_CFnyr000001', 'refund.updated', 're_CFnyr000001', 700, 'pi_CFDfake0001', 'ch_CFBfake0001',
  null, 59) ->> 'reason', 'attribution_conflict', 'a conflict where no candidate holds obligations yet');
select is(pg_temp.decide('evt_CFnyr000001', pg_temp.pid('pd')) ->> 'error', 'not_yet_resolvable',
  'I-4: obligations under no project: refused as not yet resolvable');
select ok(pg_temp.dec('evt_CFnyr000001') is null
  and (select count(*) = 1 and bool_and(a.category = 'financial' and a.project_id = pg_temp.pid('pd')
             and a.summary ->> 'refusal' = 'not_yet_resolvable' and a.summary ->> 'classifier_reason' = 'obligations_missing'
             and a.summary ->> 'chosen_project_id' = pg_temp.pid('pd')::text and not a.summary ? 'evidence'
             and a.reason = 'Owner reviewed the provider evidence')
         from public.audit_events a where a.action = 'financial_conflict.decision_refused'
          and a.target_id = pg_temp.eid('evt_CFnyr000001')::text),
  'Amendment 2: no decision row; one durable financial_conflict.decision_refused (event, chosen project, classifier reason, no evidence)');
select ok((select count(*) = 2 from public.audit_events a where a.action = 'financial_conflict.decision_refused'
            and a.target_id = pg_temp.eid('evt_CFsev000001')::text and a.summary ->> 'classifier_reason' = 'obligations_several_projects')
  and (select count(*) = 1 from public.audit_events a where a.action = 'financial_conflict.decision_refused'
         and a.target_id = pg_temp.eid('evt_CFpost000001')::text and a.summary ->> 'refusal' = 'not_a_candidate'),
  'Amendment 2: unsupported and non-candidate choices are audited as refused decisions too');

-- D: D's checkout invoice (D holds the obligations) and B's recorded charge; D's payment is not
-- linked yet, so the application has an evidence gap at attempt time.
select is(pg_temp.refund_evt('evt_CFawd000001', 'refund.updated', 're_CFawd000001', 700, 'pi_CFDinit01', 'ch_CFBfake0001',
  'in_CFD00000', 60) ->> 'reason', 'attribution_conflict', 'D: a conflict that only D can resolve');
select ok((pg_temp.decide('evt_CFawd000001', pg_temp.pid('pd')) ->> 'ok')::boolean, 'the decision for D is recorded');
select is(pg_temp.attempt(pg_temp.dec('evt_CFawd000001'), pg_temp.req('q_awd')) #>> '{attempt,outcome}', 'awaiting_evidence',
  'D''s charge is not linked yet: awaiting_evidence');
select ok((select count(*) = 0 from public.refunds where stripe_refund_id = 're_CFawd000001') and not pg_temp.cleared('evt_CFawd000001'),
  'nothing is kept and the block stays');
select ok((select r ->> 'error' = 'retry_too_soon' and r ->> 'retry_after' is not null
           from (select pg_temp.attempt(pg_temp.dec('evt_CFawd000001'), gen_random_uuid()) r) x)
  and pg_temp.apps('evt_CFawd000001') = '1:awaiting_evidence',
  'at most one attempt per decision per 60 seconds (refused, no row)');
select is(pg_temp.attempt(pg_temp.dec('evt_CFpost000001'), pg_temp.pid('q_awd')) ->> 'error', 'attempt_request_id_reused',
  'an attempt_request_id belongs to one decision');

-- F: an earlier awaiting_evidence attempt with the current fingerprint.
select is(pg_temp.refund_evt('evt_CFawf000001', 'refund.updated', 're_CFawf000001', 700, 'pi_CFFinit01', 'ch_CFBfake0001',
  'in_CFF00000', 61) ->> 'reason', 'attribution_conflict', 'F: the same shape');
select pg_temp.decide('evt_CFawf000001', pg_temp.pid('pf'));
select pg_temp.past_attempt('evt_CFawf000001', 1, 'awaiting_evidence', pg_temp.fp('evt_CFawf000001'), interval '5 minutes');
select is(pg_temp.attempt(pg_temp.dec('evt_CFawf000001'), gen_random_uuid()) ->> 'error', 'evidence_unchanged',
  'after awaiting_evidence a retry needs a changed fingerprint');
insert into ids select 'fp_f0', pg_temp.fp('evt_CFawf000001');
select pg_temp.initial_invoice(pg_temp.pid('pf'), 'CFF');
select isnt(pg_temp.fp('evt_CFawf000001'), (select v from ids where k = 'fp_f0'), 'the linked payment changes the fingerprint');
select is(pg_temp.attempt(pg_temp.dec('evt_CFawf000001'), pg_temp.req('q_awf')) #>> '{attempt,outcome}', 'posted',
  'with the new evidence the retry is posted');
select ok(pg_temp.apps('evt_CFawf000001') = '1:awaiting_evidence,2:posted' and pg_temp.cleared('evt_CFawf000001')
  and (select project_id = pg_temp.pid('pf') from public.refunds where stripe_refund_id = 're_CFawf000001'),
  'the second durable attempt is posted under F and clears the block');

-- G: nine earlier operational failures with the current fingerprint.
select is(pg_temp.refund_evt('evt_CFawg000001', 'refund.updated', 're_CFawg000001', 700, 'pi_CFGinit01', 'ch_CFBfake0001',
  'in_CFG00000', 62) ->> 'reason', 'attribution_conflict', 'G: the same shape');
select pg_temp.decide('evt_CFawg000001', pg_temp.pid('pg'));
select pg_temp.past_attempt('evt_CFawg000001', n, 'operational_failure', pg_temp.fp('evt_CFawg000001'), interval '5 minutes')
  from generate_series(1, 9) n;
select is(pg_temp.attempt(pg_temp.dec('evt_CFawg000001'), pg_temp.req('q_awg')) #>> '{attempt,attempt_no}', '10',
  'after operational_failure a retry is allowed whatever the fingerprint');
select ok((select outcome = 'awaiting_evidence' and terminal_reason = 'exhausted' and fingerprint ~ '^[0-9a-f]{64}$'
           from private.financial_conflict_applications where attempt_request_id = pg_temp.pid('q_awg')),
  'the tenth non-success row is exhausted; its outcome and evidence are kept');
select is(pg_temp.attempt(pg_temp.dec('evt_CFawg000001'), gen_random_uuid()) ->> 'error', 'attempts_exhausted',
  'no eleventh attempt');
select throws_ok($$ select pg_temp.past_attempt('evt_CFawg000001', 11, 'operational_failure', repeat('0', 64), interval '1 hour') $$,
  '23514', null, 'at most 10 durable attempt rows');

-- H: decided while only H holds the obligations; then J's recorded charge is paid.
select is(pg_temp.refund_evt('evt_CFawh000001', 'refund.updated', 're_CFawh000001', 700, 'pi_CFHinit01', 'ch_CFJfake0001',
  'in_CFH00000', 63) ->> 'reason', 'attribution_conflict', 'H: H''s checkout invoice and J''s recorded renewal charge');
select ok((pg_temp.decide('evt_CFawh000001', pg_temp.pid('ph')) ->> 'ok')::boolean, 'the decision for H is recorded');
select is(pg_temp.renewal(pg_temp.pid('pj'), 'CFJ', 'pi_CFJrenew01', 66) ->> 'status', 'processed',
  'J''s renewal is paid: J now holds that charge''s obligation');
select is(pg_temp.attempt(pg_temp.dec('evt_CFawh000001'), pg_temp.req('q_awh')) #>> '{attempt,detail,objects,0,reason}',
  'obligations_several_projects', 'the attempt re-classifies under the locks: the obligations are now under two projects');
select is(pg_temp.apps('evt_CFawh000001'), '1:permanently_unsupported', 'permanently_unsupported');

-- K: an event that already carried a project (item 1 as well as item 7). Attributed to K by its
-- checkout invoice and deferred (K's payment intent is not linked yet); a recorded charge of B then
-- appears; the retry finds two projects and quarantines, keeping K's association.
select is(pg_temp.refund_evt('evt_CFawk000001', 'refund.updated', 're_CFawk000001', 400, 'pi_CFKinit01', 'ch_CFKbfake01',
  'in_CFK00000', 70) ->> 'status', 'deferred', 'K: attributed to K, charge evidence incomplete: deferred');
insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
values ('ch_CFKbfake01', pg_temp.pid('pb'), 'renewal', null, 'in_CFKbrenew01');
select pg_temp.svc($$ select public.run_billing_job('webhook_backfill') $$);
select ok((pg_temp.evt_row('evt_CFawk000001')).quarantine_reason = 'attribution_conflict'
  and (pg_temp.evt_row('evt_CFawk000001')).project_id = pg_temp.pid('pk'),
  'the event keeps K''s association');
select pg_temp.decide('evt_CFawk000001', pg_temp.pid('pk'));
select pg_temp.initial_invoice(pg_temp.pid('pk'), 'CFK');
select ok(pg_temp.blocking(pg_temp.pid('pk')) -> 'G2' ? 'quarantined_event',
  'K is blocked through its own quarantined event (items 1 and 7)');
select is(pg_temp.attempt(pg_temp.dec('evt_CFawk000001'), pg_temp.req('q_awk')) #>> '{attempt,outcome}', 'posted',
  'K: posted under K''s initial charge');
select ok(pg_temp.cleared('evt_CFawk000001')
  and not coalesce(pg_temp.blocking(pg_temp.pid('pk'))::text like '%quarantined_event%', false),
  'block clearing covers item 1 (the event''s own project) as well as item 7');

-- I-5: a pending refund implies no money effect: posted with zero entries, the expectation recorded.
select is(pg_temp.refund_evt('evt_CFpnd000001', 'refund.created', 're_CFpnd000001', 250, 'pi_CFAinit01', 'ch_CFBfake0001', null, 73,
  null, 'pending') ->> 'reason', 'attribution_conflict', 'a pending refund on A''s charge and B''s recorded charge');
select pg_temp.decide('evt_CFpnd000001', pg_temp.pid('pa'));
insert into ids select 'r_pnd', pg_temp.attempt(pg_temp.dec('evt_CFpnd000001'), pg_temp.req('q_pnd'))::text;
select ok((select v::jsonb #>> '{attempt,outcome}' = 'posted' and v::jsonb #>> '{attempt,detail,expected,0,expected_effect}' = 'none'
             and (v::jsonb #>> '{attempt,cleared}')::boolean from ids where k = 'r_pnd')
  and (select count(*) = 0 from public.ledger_entries where stripe_object_id = 're_CFpnd000001')
  and (select project_id = pg_temp.pid('pa') and status = 'pending' from public.refunds where stripe_refund_id = 're_CFpnd000001'),
  'I-5: no expected money effect: posted with zero entries, recorded under A, expectation kept');

-- ---------------------------------------------------------------------------
-- 7A. Amendment 1 (OI-121): payment.refund_recorded keys on the normal path
-- ---------------------------------------------------------------------------
select is(pg_temp.charge_refunded('evt_CFdup000001', 'ch_CFAdup000001', 'pi_CFAinit01', null,
  jsonb_build_array(pg_temp.re('re_CFdup000001', 110), pg_temp.re('re_CFdup000002', 120)), 80) ->> 'status', 'processed',
  'OI-121: a charge.refunded event with two refunds is processed');
select is((select string_agg(l.stripe_object_id || ':' || l.amount_cents, ',' order by l.stripe_object_id) from public.ledger_entries l
            where l.stripe_object_id like 're_CFdup%'), 're_CFdup000001:-110,re_CFdup000002:-120',
  'each refund in the event is posted exactly once');
select is((select string_agg(d.dedupe_key, ',' order by d.dedupe_key) from public.domain_events d
            where d.event_type = 'payment.refund_recorded' and d.subject_id like 're_CFdup%'),
  'payment.refund_recorded:evt_CFdup000001:re_CFdup000001,payment.refund_recorded:evt_CFdup000001:re_CFdup000002',
  'charge.refunded keys each refund''s domain event by the refund');
select ok((pg_temp.charge_refunded('evt_CFdup000001', 'ch_CFAdup000001', 'pi_CFAinit01', null,
  jsonb_build_array(pg_temp.re('re_CFdup000001', 110), pg_temp.re('re_CFdup000002', 120)), 80) ->> 'duplicate')::boolean
  and (select count(*) = 2 from public.ledger_entries l where l.stripe_object_id like 're_CFdup%'),
  'a replay of the event is a duplicate and adds no financial entry');
select is((select d.dedupe_key from public.domain_events d where d.event_type = 'payment.refund_recorded'
            and d.subject_id = 're_CFs00000001' order by d.id limit 1), 'payment.refund_recorded:evt_CFs0norm0001',
  'refund.* events keep their key');
-- The same refund across refund.* and charge.refunded events, in both arrival orders: one financial
-- recognition each.
select pg_temp.refund('evt_CFord100001', 're_CFord100001', 130, 'pi_CFAinit01', 'succeeded', null, 81);
select pg_temp.charge_refunded('evt_CFord100002', 'ch_CFAord100001', 'pi_CFAinit01', null,
  jsonb_build_array(pg_temp.re('re_CFord100001', 130), pg_temp.re('re_CFord100002', 140)), 82);
select pg_temp.charge_refunded('evt_CFord200001', 'ch_CFAord200001', 'pi_CFAinit01', null,
  jsonb_build_array(pg_temp.re('re_CFord200001', 150), pg_temp.re('re_CFord200002', 160)), 83);
select pg_temp.refund_evt('evt_CFord200002', 'refund.updated', 're_CFord200001', 150, 'pi_CFAinit01', null, null, 84);
select is((select string_agg(x.k, ',' order by x.k) from (
            select l.stripe_object_id || ':' || count(*) || ':' || sum(l.amount_cents) as k from public.ledger_entries l
             where l.stripe_object_id like 're_CFord%' group by l.stripe_object_id) x),
  're_CFord100001:1:-130,re_CFord100002:1:-140,re_CFord200001:1:-150,re_CFord200002:1:-160',
  'refund.* then charge.refunded, and charge.refunded then refund.*: each refund is recognized once');
select ok((select bool_and(w.processing_status = 'processed') from public.webhook_events w
            where w.stripe_event_id in ('evt_CFord100001', 'evt_CFord100002', 'evt_CFord200001', 'evt_CFord200002')),
  'all four events are processed');

-- ---------------------------------------------------------------------------
-- 8. oi93.fp.v1: canonical JSON, stability, sensitivity per input class (on D)
-- ---------------------------------------------------------------------------
select is(private.oi93_canonical_json('{"b": [1, {"z": null, "a": "x"}], "a": true, "é": "ü"}'::jsonb),
  '{"a":true,"b":[1,{"a":"x","z":null}],"é":"ü"}', 'canonical JSON: sorted keys, no whitespace, explicit nulls, UTF-8');
select is(private.oi93_canonical_json('{"b": 1, "aa": 2}'::jsonb), '{"aa":2,"b":1}',
  'canonical JSON sorts keys by code point (not by jsonb''s length-first order)');
select is(private.oi93_canonical_json('{"a":1,"b":2}'::jsonb), private.oi93_canonical_json('{ "b" : 2 , "a" : 1 }'::jsonb),
  'canonical JSON is independent of key order and whitespace');
select is(length(pg_temp.fp('evt_CFawd000001')), 64, 'the fingerprint is a SHA-256 hex digest');
insert into ids select 'fp0', pg_temp.fp('evt_CFawd000001');
select pg_temp.owner('select public.financial_conflict_events()');
select pg_temp.owner(format('select public.financial_conflict_attempt_status(%L)', pg_temp.pid('q_awd')));
select pg_temp.attempt(pg_temp.dec('evt_CFawd000001'), gen_random_uuid()); -- refused (audited only)
select private.notify_owner('webhook.quarantined', 'fp-stability-check', pg_temp.pid('pd'), null, '{}'::jsonb);
select pg_temp.past_attempt('evt_CFawd000001', 2, 'operational_failure', repeat('0', 64), interval '0');
select is(pg_temp.fp('evt_CFawd000001'), (select v from ids where k = 'fp0'),
  'stable: reads, audits, notifications and attempt rows do not change it');
create function pg_temp.fp_changed(p_k text) returns boolean language plpgsql as $$
declare
  v_now text := pg_temp.fp('evt_CFawd000001');
  v_changed boolean := v_now is distinct from (select v from ids where k = 'fp0');
begin
  update ids set v = v_now where k = 'fp0';
  return v_changed;
end;
$$;
insert into private.financial_event_project_candidates (webhook_event_id, project_id, source, stripe_ref)
values (pg_temp.eid('evt_CFawd000001'), pg_temp.pid('pc'), 'payment_link', 'ch_CFBfake0001');
select ok(pg_temp.fp_changed('candidates'), 'sensitive: candidates');
insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
values ('ch_CFDextra001', pg_temp.pid('pd'), 'renewal', null, 'in_CFD00000');
select ok(pg_temp.fp_changed('links'), 'sensitive: payment links');
select pg_temp.initial_invoice(pg_temp.pid('pd'), 'CFD');
select ok(pg_temp.fp_changed('initial_link'), 'sensitive: the payment link the initial invoice records');
select is(pg_temp.refund('evt_CFDnorm00001', 're_CFDnorm00001', 300, 'pi_CFDinit01', 'succeeded', null, 69) ->> 'status',
  'processed', 'an unrelated refund on D''s initial charge is posted');
select ok(pg_temp.fp_changed('obligations'), 'sensitive: obligations and balances');
-- A ledger entry for the event's own refund on a charge outside the scope: only the ledger class changes.
insert into public.ledger_entries (project_id, entry_type, amount_cents, source, webhook_event_id, stripe_object_type,
  stripe_object_id, holding_charge_key, dedupe_key)
values (pg_temp.pid('pd'), 'refund', -1, 'webhook', pg_temp.eid('evt_CFDnorm00001'), 'refund', 're_CFawd000001',
  'renewal:in_CFZother01', 're_CFawd000001:refund:fixture');
select ok(pg_temp.fp_changed('ledger'), 'sensitive: ledger entries alone');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select public.record_refund_decision(pg_temp.pid('pd'), 100, 'A decision on D''s initial charge',
  jsonb_build_array(jsonb_build_object('obligation_id', pg_temp.ob(pg_temp.pid('pd'), 'development_deposit'), 'amount_cents', 100)));
reset role;
select ok(pg_temp.fp_changed('refund_decisions'), 'sensitive: refund decisions');
insert into public.refunds (stripe_refund_id, project_id, stripe_charge_ref, amount_cents, currency, status, last_event_created)
values ('re_CFawd000001', pg_temp.pid('pd'), 'pi_CFDinit01', 700, 'usd', 'pending', now());
select ok(pg_temp.fp_changed('refunds'), 'sensitive: the refund row');
insert into private.financial_conflict_effects (stripe_object_id, effect_type, amount_cents, project_id, recognized_by_application_id)
select 're_CFawd000001', 'refund', 700, pg_temp.pid('pd'), id from private.financial_conflict_applications
 where attempt_request_id = pg_temp.pid('q_awd');
select ok(pg_temp.fp_changed('effects'), 'sensitive: effect recognitions');
select isnt(pg_temp.fp('evt_CFawf000001'), pg_temp.fp('evt_CFawg000001'), 'sensitive: the decision and event');

-- ---------------------------------------------------------------------------
-- 9. Block clearing needs a re-verified application; insert-only records
-- ---------------------------------------------------------------------------
-- A fabricated "posted" row citing an unrelated historical entry (A's deposit charge) never clears.
select is(pg_temp.refund_evt('evt_CFfab000001', 'refund.updated', 're_CFfab000001', 100, 'pi_CFAinit01', 'ch_CFBfake0001', null, 70)
  ->> 'reason', 'attribution_conflict', 'another conflict on A''s charge');
select pg_temp.decide('evt_CFfab000001', pg_temp.pid('pa'));
insert into ids values ('fab', gen_random_uuid()::text);
insert into private.financial_conflict_applications (id, decision_id, webhook_event_id, project_id, attempt_no, attempt_request_id,
  category, outcome, fingerprint, reason, requested_by)
select pg_temp.pid('fab'), pg_temp.dec('evt_CFfab000001'), pg_temp.eid('evt_CFfab000001'), pg_temp.pid('pa'), 1, gen_random_uuid(),
  'S1', 'represented', repeat('0', 64), 'fabricated (fixture)', '00000000-0000-4000-8000-000000000001';
insert into private.financial_conflict_effects (id, stripe_object_id, effect_type, amount_cents, project_id, recognized_by_application_id)
values (pg_temp.req('fab_effect'), 're_CFfab000001', 'refund', 25900, pg_temp.pid('pa'), pg_temp.pid('fab'));
insert into private.financial_conflict_application_entries (application_id, ledger_entry_id, effect_id, role, project_id,
  stripe_object_id, entry_type, amount_cents, currency, obligation_id, holding_charge_key)
select pg_temp.pid('fab'), l.id, pg_temp.pid('fab_effect'), 'cited', l.project_id, 're_CFfab000001', l.entry_type, l.amount_cents,
       l.currency, pg_temp.ob(pg_temp.pid('pa'), 'development_deposit'), null
  from public.ledger_entries l where l.id = (select charge_entry_id from public.payment_obligations
                                              where id = pg_temp.ob(pg_temp.pid('pa'), 'development_deposit'));
select ok(not pg_temp.cleared('evt_CFfab000001') and pg_temp.g(pg_temp.pid('pa')) = '(f,f)',
  'an unrelated historical entry never satisfies clearance');
-- I-6: an entry already recorded for another recognition (a corrupted fixture: another object's
-- recognition holding this refund's entry) is never recognized again.
insert into private.financial_conflict_effects (id, stripe_object_id, effect_type, amount_cents, project_id, recognized_by_application_id)
values (pg_temp.req('fab_other'), 're_CFotherfab01', 'refund', 100, pg_temp.pid('pa'), pg_temp.pid('fab'));
insert into private.financial_conflict_application_entries (application_id, ledger_entry_id, effect_id, role, project_id,
  stripe_object_id, entry_type, amount_cents, currency, obligation_id, holding_charge_key)
select pg_temp.pid('fab'), l.id, pg_temp.pid('fab_other'), 'cited', l.project_id, l.stripe_object_id, l.entry_type, l.amount_cents,
       l.currency, l.obligation_id, l.holding_charge_key
  from public.ledger_entries l where l.stripe_object_id = 're_CFamt000001';
select is(pg_temp.refund_evt('evt_CFamt000003', 'refund.updated', 're_CFamt000001', 100, 'pi_CFAinit01', 'ch_CFBfake0001', null, 74)
  ->> 'reason', 'attribution_conflict', 'a conflicting event for a refund whose entry another recognition holds');
select pg_temp.decide('evt_CFamt000003', pg_temp.pid('pa'));
select is(pg_temp.attempt(pg_temp.dec('evt_CFamt000003'), pg_temp.req('q_amt3')) #>> '{attempt,detail,reason}', 'recognition_mismatch',
  'I-6: entries that already belong to another recognition are never recognized again');
select throws_ok($$ update private.financial_conflict_decisions set reason = 'changed' $$, '42501', null, 'decisions cannot be updated');
select throws_ok($$ delete from private.financial_conflict_applications $$, '42501', null, 'attempts cannot be deleted');
select throws_ok($$ update private.financial_conflict_effects set amount_cents = 0 $$, '42501', null, 'recognitions cannot be updated');
select throws_ok($$ delete from private.financial_conflict_application_entries $$, '42501', null, 'application entries cannot be deleted');
-- S0 exact match: a recognized effect whose ledger entries are no longer exactly the recognized
-- IDs (a second entry for the same refund appears) is never cited.
insert into public.ledger_entries (project_id, entry_type, amount_cents, source, webhook_event_id, stripe_object_type,
  stripe_object_id, holding_charge_key, dedupe_key)
select pg_temp.pid('pa'), 'refund', -100, 'webhook', pg_temp.eid('evt_CFs0norm0001'), 'refund', 're_CFs00000001',
       (select 'initial:' || id from public.checkout_sessions where project_id = pg_temp.pid('pa')), 're_CFs00000001:refund:fixture';
select is(pg_temp.refund_evt('evt_CFs0conf0003', 'charge.refund.updated', 're_CFs00000001', 100, 'pi_CFAinit01', 'ch_CFBfake0001', null, 72)
  ->> 'reason', 'attribution_conflict', 'another event for the recognized refund');
select pg_temp.decide('evt_CFs0conf0003', pg_temp.pid('pa'));
select is(pg_temp.attempt(pg_temp.dec('evt_CFs0conf0003'), pg_temp.req('q_s0c')) #>> '{attempt,detail,reason}', 'recognition_mismatch',
  'S0: a citation needs the exact recognized ledger entry IDs and amount');
-- The deferred references (recognitions and entries recorded before their application row) hold.
select lives_ok($$ set constraints all immediate $$, 'every recognition and entry references a recorded application');
select throws_ok($$ truncate private.financial_conflict_decisions cascade $$, '42501', null, 'the records cannot be truncated');

-- I-5 fail-closed (fault injection, last in this file): with apply_reversal replaced, inside this
-- rolled-back transaction, by one that reports success and posts nothing, a succeeded refund that
-- posts nothing is never recorded as posted.
select is(pg_temp.refund_evt('evt_CFflt000001', 'refund.updated', 're_CFflt000001', 90, 'pi_CFAinit01', 'ch_CFBfake0001', null, 90)
  ->> 'reason', 'attribution_conflict', 'a succeeded refund in conflict');
select pg_temp.decide('evt_CFflt000001', pg_temp.pid('pa'));
create or replace function private.apply_reversal(e public.webhook_events, p_link private.stripe_payment_links,
  p_type public.ledger_entry_type, p_object_type text, p_object_id text, p_amount bigint, p_decision_id uuid) returns text
language plpgsql security definer set search_path = '' as $$ begin return 'processed'; end; $$;
select is(pg_temp.attempt(pg_temp.dec('evt_CFflt000001'), pg_temp.req('q_flt')) #>> '{attempt,detail,reason}', 'expected_effect_missing',
  'I-5: a succeeded refund that posts nothing fails closed (permanently_unsupported, nothing kept)');
select ok(not pg_temp.cleared('evt_CFflt000001') and (select count(*) = 0 from public.refunds where stripe_refund_id = 're_CFflt000001'),
  'the block stays and the whole step rolled back');

select * from finish();
rollback;
