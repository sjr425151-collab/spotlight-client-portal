-- AUTH-026 (OI-131): test-only synthetic population harness for the staff operational queue.
-- Not a pgTAP file: it lives outside supabase/tests, so neither `supabase test db` nor
-- scripts/run-db-tests.sh collects it. Load it with psql inside a
-- transaction that the caller rolls back; it only defines pg_temp functions:
--
--   begin;
--   \i tests/perf/oi131_synthetic_projects.sql
--   select pg_temp.oi131_populate(1000);                  -- representative mix (default)
--   select pg_temp.oi131_populate(1000, 'heavy');         -- worst case: every project state-heavy
--   ... measure (see pg_temp.oi131_measure below) ...
--   rollback;
--
-- Every state is built through the real WP-B and WP-C functions (the 190 pattern): Owner-issued
-- order summaries, client acceptance and Checkout, claimed, confirmed and recorded mock outbound
-- results, and a verified synthetic checkout.session.completed (OI-63: no Stripe request). The
-- anomaly share adds an unresolved financial-integrity item through the real path (the 190
-- pattern): the initial invoice is recorded, then a refund arrives whose payment intent is this
-- project's and whose invoice is an earlier paid project's, which processing quarantines as an
-- N1(a) attribution conflict. Both candidate projects are then blocked (G2 and G4) until the Owner
-- decides it, and the conflict functions run for that event: the root cause's heavy path.
-- Synthetic data only; local and CI only; nothing persists.
--
-- REPRESENTATIVE MIX (per 100 active projects; rationale in CURRENT-STATE, AUTH-026 record):
--   20 lead or intake only (no order summary)          early pipeline
--   15 order summary presented, not accepted           proposals out
--   10 accepted, deposit pending (Checkout started)    awaiting payment
--   45 deposit verified (paid; in production)          the bulk of a running portfolio
--   10 paid with an unresolved attribution conflict     exceptions an Owner must clear (each also
--                                                      blocks the paid project it names)
-- HEAVY MIX: every project paid, half of them raising a conflict that names the other half (the
-- worst case: every project blocked, every conflict evaluated).

create function pg_temp.oi131_act_as(p_uid uuid, p_aal text default 'aal1') returns void language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'oi131-perf', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)))::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.oi131_as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end;
$$;
create function pg_temp.oi131_deliver(p_id text, p_type text, p_obj jsonb, p_offset integer default 0) returns jsonb
language plpgsql as $$
declare
  v_ingest jsonb;
  v_result jsonb;
begin
  perform pg_temp.oi131_as_service();
  v_ingest := public.ingest_stripe_event(jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type,
    'api_version', '2026-09-30.endive', 'livemode', false, 'created', extract(epoch from now())::bigint + p_offset,
    'data', jsonb_build_object('object', p_obj)), repeat('c', 64));
  if not coalesce((v_ingest ->> 'ok')::boolean, false) then
    reset role;
    return v_ingest;
  end if;
  v_result := public.process_stripe_event((v_ingest ->> 'webhook_event_id')::bigint);
  reset role;
  return v_result;
end;
$$;

-- One synthetic project in the given state. p_tag is alphanumeric (Stripe-format identifiers).
create function pg_temp.oi131_project(p_tag text, p_state text, p_other_tag text default null) returns uuid
language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
  v_os uuid;
  v_acc uuid;
  v_cs uuid;
  v_req record;
  v_tok uuid;
  v_r jsonb;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('Perf ' || p_tag || ' LLC', 'Perf ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'Perf ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '00000000-0000-4000-8000-0000000000a1');
  if p_state = 'lead' then
    return v_project;
  end if;
  perform pg_temp.oi131_act_as('00000000-0000-4000-8000-000000000001', 'aal2');
  v_r := public.issue_order_summary(v_project, 'essential');
  v_os := (v_r ->> 'order_summary_id')::uuid;
  reset role;
  if v_os is null then
    raise exception 'harness: issuance failed for %: %', p_tag, v_r;
  end if;
  if p_state = 'presented' then
    return v_project;
  end if;
  perform pg_temp.oi131_act_as('00000000-0000-4000-8000-0000000000a1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'Perf ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
  v_cs := (public.begin_initial_checkout(v_project) ->> 'checkout_session_id')::uuid;
  reset role;
  if v_cs is null then
    raise exception 'harness: checkout failed for %', p_tag;
  end if;
  perform pg_temp.oi131_as_service();
  for v_req in select id, purpose from public.outbound_stripe_requests where project_id = v_project
               order by (purpose = 'customer_create') desc loop
    v_tok := (public.outbound_request_for_execution(v_req.id) ->> 'claim_token')::uuid;
    perform public.confirm_outbound_dispatch(v_req.id, v_tok);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cus_T' || p_tag, false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cs_test_' || p_tag, false, 200, null,
        jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_' || p_tag));
    end if;
  end loop;
  reset role;
  if p_state = 'accepted' then
    return v_project;
  end if;
  -- Paid: the verified deposit (the 190 pattern).
  v_r := pg_temp.oi131_deliver('evt_' || p_tag || 'chk', 'checkout.session.completed', jsonb_build_object(
    'id', 'cs_test_' || p_tag, 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
    'amount_total', 25900, 'payment_status', 'paid', 'customer', 'cus_T' || p_tag,
    'subscription', 'sub_' || p_tag, 'invoice', 'in_' || p_tag,
    'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
    'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
      'checkout_record_id', v_cs)));
  if v_r ->> 'status' is distinct from 'processed' then
    raise exception 'harness: payment failed for %: %', p_tag, v_r;
  end if;
  if p_state = 'paid' then
    return v_project;
  end if;
  -- Anomaly: the initial invoice records the payment intent; then a refund naming this project's
  -- payment intent and another project's invoice is quarantined as an attribution conflict.
  if p_other_tag is null then
    raise exception 'harness: an anomaly project needs another paid project';
  end if;
  perform pg_temp.oi131_deliver('evt_' || p_tag || 'inv', 'invoice.paid', jsonb_build_object('id', 'in_' || p_tag,
    'object', 'invoice', 'billing_reason', 'subscription_create', 'currency', 'usd', 'amount_paid', 25900,
    'customer', 'cus_T' || p_tag, 'payment_intent', 'pi_' || p_tag || 'init',
    'parent', jsonb_build_object('subscription_details', jsonb_build_object('subscription', 'sub_' || p_tag,
      'metadata', jsonb_build_object('project_id', v_project, 'checkout_record_id', v_cs))),
    'lines', jsonb_build_object('data', jsonb_build_array(
      jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HxK5j4r4WkVPkRUJ4gnZ')),
      jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))));
  v_r := pg_temp.oi131_deliver('evt_' || p_tag || 'conf', 'refund.updated', jsonb_build_object('id', 're_' || p_tag || 'conf',
    'object', 'refund', 'amount', 1200, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', 'pi_' || p_tag || 'init',
    'invoice', 'in_' || p_other_tag, 'metadata', '{}'::jsonb), 10);
  if v_r ->> 'reason' is distinct from 'attribution_conflict' then
    raise exception 'harness: the conflict was not quarantined for %: %', p_tag, v_r;
  end if;
  return v_project;
end;
$$;

-- Populate p_count active projects with the given mix. Returns the per-state counts.
create function pg_temp.oi131_populate(p_count integer, p_mix text default 'representative') returns jsonb
language plpgsql as $$
declare
  v_i integer;
  v_slot integer;
  v_state text;
  v_counts jsonb := '{}'::jsonb;
  v_run text := substr(replace(gen_random_uuid()::text, '-', ''), 1, 6);
  v_tag text;
  v_paid text[] := '{}';
begin
  if p_mix not in ('representative', 'heavy') then
    raise exception 'harness: unknown mix %', p_mix;
  end if;
  for v_i in 1 .. p_count loop
    v_slot := (v_i - 1) % 100;
    v_state := case
      when p_mix = 'heavy' then case when v_slot % 2 = 0 then 'paid' else 'anomaly' end
      when v_slot < 20 then 'lead'
      when v_slot < 35 then 'presented'
      when v_slot < 45 then 'accepted'
      when v_slot < 90 then 'paid'
      else 'anomaly' end;
    -- The local rate limits apply per user; the harness clears them between projects.
    delete from private.rate_limits;
    v_tag := 'P' || v_run || lpad(v_i::text, 6, '0');
    -- An anomaly names a distinct earlier paid project where one is available (spread, not one hub).
    perform pg_temp.oi131_project(v_tag, v_state,
      case when cardinality(v_paid) > 0 then v_paid[cardinality(v_paid) - ((v_i / 2) % cardinality(v_paid))] end);
    if v_state = 'paid' then
      v_paid := v_paid || v_tag;
    end if;
    v_counts := jsonb_set(v_counts, array[v_state], to_jsonb(coalesce((v_counts ->> v_state)::int, 0) + 1));
    -- The population is one transaction, so autovacuum never sees it: without fresh statistics the
    -- plans of the real functions, chosen for near-empty tables, degrade quadratically as the
    -- tables grow. ANALYZE (which sees this transaction's own rows) refreshes them periodically.
    if v_i % 250 = 0 then
      analyze public.projects, public.client_businesses, public.project_memberships, public.order_summaries,
        public.agreement_acceptances, public.checkout_sessions, public.outbound_stripe_requests,
        public.webhook_events, public.ledger_entries, public.payment_obligations, public.audit_events,
        private.financial_event_project_candidates;
      raise notice 'oi131 harness: % of % projects', v_i, p_count;
    end if;
  end loop;
  return v_counts;
end;
$$;
