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
-- anomaly share adds unresolved financial-integrity items through the real paths available in a
-- local database: a quarantined event (an amount that does not match the snapshot) and an open
-- reconciliation item. Synthetic data only; local and CI only; nothing persists.
--
-- REPRESENTATIVE MIX (per 100 active projects; rationale in CURRENT-STATE, AUTH-026 record):
--   20 lead or intake only (no order summary)          early pipeline
--   15 order summary presented, not accepted           proposals out
--   10 accepted, deposit pending (Checkout started)    awaiting payment
--   45 deposit verified (paid; in production)          the bulk of a running portfolio
--   10 paid with an unresolved financial anomaly       exceptions an Owner must clear
-- HEAVY MIX: every project paid, half of them with an anomaly (the worst case).

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
create function pg_temp.oi131_deliver(p_id text, p_type text, p_obj jsonb) returns jsonb language plpgsql as $$
declare
  v_ingest jsonb;
  v_result jsonb;
begin
  perform pg_temp.oi131_as_service();
  v_ingest := public.ingest_stripe_event(jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type,
    'api_version', '2026-09-30.endive', 'livemode', false, 'created', extract(epoch from now())::bigint,
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
create function pg_temp.oi131_project(p_tag text, p_state text) returns uuid language plpgsql as $$
declare
  v_business uuid;
  v_project uuid;
  v_os uuid;
  v_acc uuid;
  v_cs uuid;
  v_req record;
  v_tok uuid;
  v_amount integer;
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
  -- Paid: the verified deposit. The anomaly state pays with a mismatched amount instead, which the
  -- real processing quarantines (an unresolved G2 integrity item).
  v_amount := case when p_state = 'anomaly' then 12345 else 25900 end;
  perform pg_temp.oi131_deliver('evt_' || p_tag || 'chk', 'checkout.session.completed', jsonb_build_object(
    'id', 'cs_test_' || p_tag, 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
    'amount_total', v_amount, 'payment_status', 'paid', 'customer', 'cus_T' || p_tag,
    'subscription', 'sub_' || p_tag, 'invoice', 'in_' || p_tag,
    'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
    'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
      'checkout_record_id', v_cs)));
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
    perform pg_temp.oi131_project('P' || v_run || lpad(v_i::text, 6, '0'), v_state);
    v_counts := jsonb_set(v_counts, array[v_state], to_jsonb(coalesce((v_counts ->> v_state)::int, 0) + 1));
  end loop;
  return v_counts;
end;
$$;
