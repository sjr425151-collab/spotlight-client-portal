-- WP-C PWP-5a (AUTH-023; OI-111; OD-14, OD-15): scope confirmation versions, the authorized
-- signer's acknowledgment, staff operational notes and the preview-release gate (05 §3A).
-- T-LC-19, T-LC-20, T-LC-16 (kept), isolation for every new table, and the catalog.
-- Every project reaches a verified deposit and an effective agreement through the real WP-B
-- workflow, and accepted intake through WP-C's real functions (the helpers are 190's).
-- Two-connection races are in tests/integration/wpc-pwp5a-scope-race.test.ts. Synthetic data only.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(86);

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
-- AUTH-023 helpers
-- ---------------------------------------------------------------------------
create function pg_temp.try_release(p_project uuid, p_uid uuid default '00000000-0000-4000-8000-000000000002')
returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as(p_uid, 'aal2', true);
  v := public.release_preview(p_project, repeat('e', 40), 'dpl_pwp5a', 'https://preview.example.test/pwp5a', '{}');
  reset role;
  return v;
end;
$$;
create function pg_temp.confirm(p_project uuid, p_req text, p_sel text[] default array['Five-page site', 'Contact form'],
  p_uid uuid default '00000000-0000-4000-8000-000000000002', p_aal text default 'aal2', p_fresh boolean default true)
returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as(p_uid, p_aal, p_fresh);
  v := public.record_scope_confirmation(p_project, p_req, p_sel, array['AMD-2026-001']);
  reset role;
  return v;
end;
$$;
create function pg_temp.ack(p_confirmation uuid, p_sha text default null,
  p_uid uuid default '00000000-0000-4000-8000-0000000000a1', p_ack boolean default true, p_box boolean default true)
returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as(p_uid);
  v := public.acknowledge_scope_confirmation(p_confirmation,
    coalesce(p_sha, (select content_sha256 from public.scope_confirmations where id = p_confirmation)), p_ack, p_box);
  reset role;
  return v;
end;
$$;
create function pg_temp.cur(p_project uuid) returns uuid language sql as $$
  select id from public.scope_confirmations where project_id = p_project order by version desc limit 1;
$$;
create function pg_temp.state(p_project uuid) returns text language sql as $$
  select private.scope_confirmation_state(p_project);
$$;
-- Everything T-LC-20 protects, for one project: order summaries (every column), acceptances,
-- the ledger, obligations and payment authorizations.
create function pg_temp.contract_fingerprint(p_project uuid) returns text language sql as $$
  select md5(coalesce((select string_agg(to_jsonb(o)::text, '|' order by o.id) from public.order_summaries o
                        where o.project_id = p_project), '')
    || coalesce((select string_agg(to_jsonb(a)::text, '|' order by a.id) from public.agreement_acceptances a
                  where a.project_id = p_project), '')
    || coalesce((select string_agg(to_jsonb(l)::text, '|' order by l.id) from public.ledger_entries l
                  where l.project_id = p_project), '')
    || coalesce((select string_agg(to_jsonb(p)::text, '|' order by p.id) from public.payment_obligations p
                  where p.project_id = p_project), ''));
$$;
create function pg_temp.audits(p_action text, p_project uuid) returns integer language sql as $$
  select count(*)::int from public.audit_events where action = p_action and project_id = p_project;
$$;
create function pg_temp.rows_as(p_uid uuid, p_aal text, p_table text, p_project uuid) returns integer
language plpgsql as $$
declare
  v integer;
begin
  perform pg_temp.act_as(p_uid, p_aal, true);
  execute format('select count(*)::int from public.%I where project_id = $1', p_table) into v using p_project;
  reset role;
  return v;
end;
$$;

-- Two paid projects with an effective agreement signed by client A and accepted intake; client B
-- becomes a second (non-signer) member of P only.
insert into ids select 'p', pg_temp.ready('S5P');
insert into ids select 'q', pg_temp.ready('S5Q');
insert into public.project_memberships (project_id, user_id) values (pg_temp.id('p'), '00000000-0000-4000-8000-0000000000b1');
-- A paid project whose intake is not yet accepted (T-LC-16 and the intake precondition).
insert into ids select 'u', pg_temp.paid_project('S5U', 'pm_S5Ucard01');

-- ---------------------------------------------------------------------------
-- 1. Preconditions and T-LC-16 (kept)
-- ---------------------------------------------------------------------------
select is(private.scope_authorized_signer(pg_temp.id('p')), '00000000-0000-4000-8000-0000000000a1'::uuid,
  'the authorized signer is the client who accepted the effective order summary');
select is(pg_temp.try_release(pg_temp.id('u')) ->> 'error', 'intake_not_accepted',
  'T-LC-16 (kept): before intake is accepted the release is refused for the intake reason');
select is(pg_temp.confirm(pg_temp.id('u'), 'Requirements') ->> 'error', 'intake_not_accepted',
  'a confirmation needs intake accepted_by_staff');
select ok((select summary ->> 'reason' = 'intake_not_accepted' from public.audit_events
            where action = 'scope_confirmation.rejected' and project_id = pg_temp.id('u') order by id desc limit 1),
  'the refused confirmation is audited');

-- ---------------------------------------------------------------------------
-- 2. T-LC-19: no release without a confirmation, for every actor
-- ---------------------------------------------------------------------------
select is(pg_temp.state(pg_temp.id('p')), 'none', 'state: no confirmation yet');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok(exists (select 1 from public.operational_queue() q where q ->> 'queue' = 'in_development'
                   and q ->> 'project_id' = pg_temp.id('p')::text)
  and not exists (select 1 from public.operational_queue() q where q ->> 'queue' like '%scope%'
                   and q ->> 'project_id' = pg_temp.id('p')::text),
  'before any confirmation the project stays in development, with no scope queue item');
reset role;
select is(pg_temp.try_release(pg_temp.id('p')) ->> 'error', 'scope_confirmation_required',
  'T-LC-19: the Admin cannot release without a scope confirmation');
select is(pg_temp.try_release(pg_temp.id('p'), '00000000-0000-4000-8000-000000000001') ->> 'error', 'scope_confirmation_required',
  'T-LC-19: neither can the Owner');
select is((select count(*)::int from public.preview_releases where project_id = pg_temp.id('p')), 0, 'no release row was written');
select is(pg_temp.audits('preview.release_rejected', pg_temp.id('p')), 2, 'both refusals are audited');

-- ---------------------------------------------------------------------------
-- 3. Recording a confirmation (OD-15: Owner and Admin only)
-- ---------------------------------------------------------------------------
select is(pg_temp.confirm(pg_temp.id('p'), 'Req', p_uid => '00000000-0000-4000-8000-000000000005') ->> 'error', 'forbidden',
  'OD-15: Sales cannot record a confirmation');
select is(pg_temp.confirm(pg_temp.id('p'), 'Req', p_uid => '00000000-0000-4000-8000-0000000000a1') ->> 'error', 'forbidden',
  'OD-15: a client (fresh MFA, aal2) cannot record a confirmation');
select is(pg_temp.confirm(pg_temp.id('p'), 'Req', p_aal => 'aal1', p_fresh => false) ->> 'error', 'forbidden',
  'the Admin at aal1 cannot record a confirmation');
update public.staff_roles set status = 'revoked' where user_id = '00000000-0000-4000-8000-000000000002';
select is(pg_temp.confirm(pg_temp.id('p'), 'Req') ->> 'error', 'forbidden',
  'OI-120: a revoked former Admin (fresh MFA) cannot record a confirmation');
update public.staff_roles set status = 'active' where user_id = '00000000-0000-4000-8000-000000000002';
select is(pg_temp.confirm(pg_temp.id('p'), '   ') ->> 'error', 'invalid_input', 'requirements are required');
select is(pg_temp.confirm(pg_temp.id('p'), 'Req', '{}'::text[]) ->> 'error', 'invalid_input', 'at least one selection is required');
select is(pg_temp.confirm(pg_temp.id('p'), 'Req', array[repeat('x', 501)]) ->> 'error', 'invalid_input', 'a selection is bounded');
select is((select count(*)::int from public.scope_confirmations where project_id = pg_temp.id('p')), 0,
  'no refused call wrote a confirmation');
insert into ids values ('fp0', pg_temp.contract_fingerprint(pg_temp.id('p')));
insert into ids select 'v1', pg_temp.confirm(pg_temp.id('p'), 'Needs online booking and a gallery') ->> 'confirmation_id';
select ok((select version = 1 and order_summary_id = (private.scope_effective_order_summary(pg_temp.id('p'))).id
                  and order_summary_sha256 = (private.scope_effective_order_summary(pg_temp.id('p'))).snapshot_sha256
                  and intake_submission_id is not null and created_by = '00000000-0000-4000-8000-000000000002'
             from public.scope_confirmations where id = pg_temp.id('v1')),
  'the Admin records version 1, bound to the effective order summary by id and snapshot hash');
select ok((select private.scope_confirmation_verifies(c) from public.scope_confirmations c where c.id = pg_temp.id('v1')),
  'version 1 verifies (spotlight.scope_confirmation.v1)');
select ok(exists (select 1 from public.audit_events where action = 'scope_confirmation.recorded' and target_id = pg_temp.id('v1')::text
                   and summary ->> 'version' = '1' and summary::text not like '%online booking%'),
  'the recording is audited without its text');
select is(pg_temp.confirm(pg_temp.id('p'), 'Needs online booking and a gallery') ->> 'error', 'confirmation_unchanged',
  'an identical confirmation is not a new version');
select is(pg_temp.state(pg_temp.id('p')), 'unacknowledged', 'state: unacknowledged');
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
select ok(exists (select 1 from public.operational_queue() q where q ->> 'queue' = 'awaiting_scope_acknowledgment'
                   and q ->> 'project_id' = pg_temp.id('p')::text)
,
  'the queue now shows the confirmation awaiting acknowledgment');
reset role;
select is(pg_temp.try_release(pg_temp.id('p')) ->> 'error', 'scope_acknowledgment_required',
  'T-LC-19: an unacknowledged confirmation does not let the Admin release');

-- ---------------------------------------------------------------------------
-- 4. The acknowledgment (the authorized signer only, the exact current version)
-- ---------------------------------------------------------------------------
select is(pg_temp.ack(pg_temp.id('v1'), p_uid => '00000000-0000-4000-8000-0000000000b1') ->> 'error', 'not_authorized_signer',
  'a member who is not the authorized signer cannot acknowledge');
select is(pg_temp.ack(pg_temp.id('v1'), p_uid => '00000000-0000-4000-8000-000000000002') ->> 'error', 'not_found',
  'no staff member can acknowledge on behalf of the client');
select is(pg_temp.ack(pg_temp.id('v1'), p_uid => '00000000-0000-4000-8000-000000000005') ->> 'error', 'not_found',
  'neither can Sales');
select is(pg_temp.ack(pg_temp.id('v1'), p_ack => false) ->> 'error', 'explicit_acknowledgment_required',
  'the acknowledgment must be affirmative');
select is(pg_temp.ack(pg_temp.id('v1'), p_box => false) ->> 'error', 'explicit_acknowledgment_required',
  'the checkbox must have been unchecked by default');
select is(pg_temp.ack(pg_temp.id('v1'), repeat('0', 64)) ->> 'error', 'confirmation_changed',
  'the acknowledgment binds the exact version hash');
update auth.users set email_confirmed_at = null where id = '00000000-0000-4000-8000-0000000000a1';
select is(pg_temp.ack(pg_temp.id('v1')) ->> 'error', 'email_not_verified', 'the signer needs a verified email');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-4000-8000-0000000000a1';
select is((select count(*)::int from public.scope_confirmation_acknowledgments where project_id = pg_temp.id('p')), 0,
  'no refused call wrote an acknowledgment');
select is((select string_agg(summary ->> 'reason', ',' order by id) from public.audit_events
            where action = 'scope_confirmation.acknowledgment_rejected' and project_id = pg_temp.id('p')),
  'not_authorized_signer,confirmation_changed,email_not_verified',
  'each refused acknowledgment past the caller checks is audited with its reason');
insert into ids select 'a1', pg_temp.ack(pg_temp.id('v1')) ->> 'acknowledgment_id';
select ok((select signer_user_id = '00000000-0000-4000-8000-0000000000a1' and acknowledged and checkbox_unchecked_by_default
                  and signer_verified_email = 'client.a@example.test'
                  and confirmation_sha256 = (select content_sha256 from public.scope_confirmations where id = pg_temp.id('v1'))
             from public.scope_confirmation_acknowledgments where id = pg_temp.id('a1')),
  'the signer acknowledges version 1: verified email, explicit checkbox, the exact hash');
select ok((pg_temp.ack(pg_temp.id('v1')) ->> 'existing')::boolean, 'a repeat returns the existing acknowledgment');
select is(pg_temp.state(pg_temp.id('p')), 'acknowledged', 'state: acknowledged');
select is(pg_temp.contract_fingerprint(pg_temp.id('p')), (select v from ids where k = 'fp0'),
  'T-LC-20: confirming and acknowledging changed no order summary, hash, price, acceptance, ledger entry or obligation');
insert into ids select 'r1', pg_temp.try_release(pg_temp.id('p')) ->> 'release_id';
select isnt(pg_temp.id('r1'), null, 'T-LC-19: with the current version acknowledged, the Admin releases the preview');

-- ---------------------------------------------------------------------------
-- 5. OD-14: any new version needs renewed acknowledgment
-- ---------------------------------------------------------------------------
insert into ids select 'v2', pg_temp.confirm(pg_temp.id('p'), 'Needs online booking, a gallery and a blog',
  p_uid => '00000000-0000-4000-8000-000000000001') ->> 'confirmation_id';
select ok((select version = 2 and created_by = '00000000-0000-4000-8000-000000000001' from public.scope_confirmations
            where id = pg_temp.id('v2')), 'the Owner records version 2');
select is(pg_temp.ack(pg_temp.id('v1')) ->> 'existing', 'true', 'version 1 keeps its acknowledgment (never edited)');
select is(pg_temp.try_release(pg_temp.id('p'), '00000000-0000-4000-8000-000000000001') ->> 'error', 'scope_acknowledgment_required',
  'OD-14: after a new version, even the Owner cannot release until it is acknowledged');
insert into ids select 'v3', pg_temp.confirm(pg_temp.id('p'), 'Needs online booking, a gallery, a blog and a map')
  ->> 'confirmation_id';
select is(pg_temp.ack(pg_temp.id('v2')) ->> 'error', 'confirmation_superseded', 'a superseded version cannot be acknowledged');
select ok((pg_temp.ack(pg_temp.id('v3')) ->> 'ok')::boolean, 'the signer acknowledges version 3');
select isnt(pg_temp.try_release(pg_temp.id('p')) ->> 'release_id', null, 'the next release succeeds');
select is(pg_temp.contract_fingerprint(pg_temp.id('p')), (select v from ids where k = 'fp0'),
  'T-LC-20: three versions and two acknowledgments still changed nothing contractual or financial');

-- ---------------------------------------------------------------------------
-- 6. Integrity: a tampered version or acknowledgment never passes the gate
-- ---------------------------------------------------------------------------
set local session_replication_role = replica;
update public.scope_confirmations set client_requirements = 'TAMPERED' where id = pg_temp.id('v3');
set local session_replication_role = origin;
select is(pg_temp.state(pg_temp.id('p')), 'stale', 'a tampered version fails its hash (stale)');
select is(pg_temp.try_release(pg_temp.id('p')) ->> 'error', 'scope_confirmation_stale', 'and blocks the release (no fallback)');
select is(pg_temp.ack(pg_temp.id('v3')) ->> 'existing', 'true', 'its earlier acknowledgment is kept but does not count');
insert into ids select 'v4', pg_temp.confirm(pg_temp.id('p'), 'Needs online booking, a gallery, a blog and a map')
  ->> 'confirmation_id';
select ok((select version = 4 from public.scope_confirmations where id = pg_temp.id('v4')),
  'a stale version is replaced by a new one (not edited)');
select ok((pg_temp.ack(pg_temp.id('v4')) ->> 'ok')::boolean, 'the signer acknowledges version 4');

-- ---------------------------------------------------------------------------
-- 7. Immutability and append-only records
-- ---------------------------------------------------------------------------
select throws_ok($$ update public.scope_confirmations set client_requirements = 'x' $$, '42501', null,
  'confirmation versions cannot be updated');
select throws_ok($$ delete from public.scope_confirmations $$, '42501', null, 'confirmation versions cannot be deleted');
select throws_ok($$ update public.scope_confirmation_acknowledgments set signer_user_id = null $$, '42501', null,
  'acknowledgments cannot be updated');
select throws_ok($$ delete from public.scope_confirmation_acknowledgments $$, '42501', null, 'acknowledgments cannot be deleted');

-- ---------------------------------------------------------------------------
-- 8. Operational notes (OD-15: Owner and Admin; staff-only; append-only)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'n1', public.record_operational_note(pg_temp.id('p'), 'Client prefers calls after 3pm') ->> 'note_id';
reset role;
select isnt(pg_temp.id('n1'), null, 'the Admin records an operational note');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select ok((public.record_operational_note(pg_temp.id('p'), 'Owner note') ->> 'ok')::boolean, 'so does the Owner');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-000000000005', 'aal2', true);
select is(public.record_operational_note(pg_temp.id('p'), 'x') ->> 'error', 'forbidden', 'OD-15: Sales cannot write notes');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1', 'aal2', true);
select is(public.record_operational_note(pg_temp.id('p'), 'x') ->> 'error', 'forbidden', 'nor can a client');
reset role;
select ok(exists (select 1 from public.audit_events where action = 'operational_note.recorded' and target_id = pg_temp.id('n1')::text
                   and summary::text not like '%3pm%' and coalesce(reason, '') not like '%3pm%'),
  'the note is audited without its text');
select throws_ok($$ update public.project_operational_notes set note = 'x' $$, '42501', null, 'notes are append-only');
select is(pg_temp.contract_fingerprint(pg_temp.id('p')), (select v from ids where k = 'fp0'),
  'notes stay outside every contractual snapshot (T-LC-20)');

-- ---------------------------------------------------------------------------
-- 9. Isolation and visibility (every new table)
-- ---------------------------------------------------------------------------
insert into ids select 'qv1', pg_temp.confirm(pg_temp.id('q'), 'Q requirements') ->> 'confirmation_id';
select is(pg_temp.rows_as('00000000-0000-4000-8000-0000000000a1', 'aal1', 'scope_confirmations', pg_temp.id('p')), 1,
  'OD-15: a client member reads only the current version (one row of four)');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select is((select id from public.scope_confirmations where project_id = pg_temp.id('p')), pg_temp.id('v4'),
  'and it is the current version');
reset role;
select is(pg_temp.rows_as('00000000-0000-4000-8000-000000000002', 'aal2', 'scope_confirmations', pg_temp.id('p')), 4,
  'staff read every version');
select is(pg_temp.rows_as('00000000-0000-4000-8000-0000000000b1', 'aal1', 'scope_confirmations', pg_temp.id('q')), 0,
  'isolation: client B (member of P only) reads no confirmation of Q');
select is(pg_temp.rows_as('00000000-0000-4000-8000-0000000000b1', 'aal1', 'scope_confirmation_acknowledgments', pg_temp.id('q')), 0,
  'isolation: nor any acknowledgment of Q');
select is(pg_temp.rows_as('00000000-0000-4000-8000-0000000000b1', 'aal1', 'scope_confirmation_acknowledgments', pg_temp.id('p')), 3,
  'a member of P reads P''s acknowledgments');
select is(pg_temp.rows_as('00000000-0000-4000-8000-0000000000a1', 'aal1', 'project_operational_notes', pg_temp.id('p')), 0,
  'clients read no operational note');
select is(pg_temp.rows_as('00000000-0000-4000-8000-000000000002', 'aal2', 'project_operational_notes', pg_temp.id('p')), 2,
  'staff read the notes');
select is(pg_temp.rows_as('00000000-0000-4000-8000-000000000005', 'aal2', 'scope_confirmations', pg_temp.id('p'))
        + pg_temp.rows_as('00000000-0000-4000-8000-000000000005', 'aal2', 'scope_confirmation_acknowledgments', pg_temp.id('p'))
        + pg_temp.rows_as('00000000-0000-4000-8000-000000000005', 'aal2', 'project_operational_notes', pg_temp.id('p')), 0,
  'OD-15: Sales reads nothing from any of the three tables');
select pg_temp.act_as('00000000-0000-4000-8000-0000000000b1');
select is(private.current_scope_confirmation_id(pg_temp.id('q')), null,
  'the RLS helper reveals nothing about a project the caller cannot access');
select is(public.scope_confirmation_status(pg_temp.id('q')) ->> 'error', 'not_found', 'nor does the status function');
select is((public.scope_confirmation_status(pg_temp.id('p')) ->> 'is_authorized_signer')::boolean, false,
  'the status tells a non-signer member that they cannot acknowledge');
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
select ok((public.scope_confirmation_status(pg_temp.id('p')) ->> 'is_authorized_signer')::boolean
  and public.scope_confirmation_status(pg_temp.id('p')) ->> 'state' = 'acknowledged',
  'the signer sees the current version as acknowledged');
reset role;

-- ---------------------------------------------------------------------------
-- 10. Catalog
-- ---------------------------------------------------------------------------
select is((select count(*)::int from pg_class c where c.relnamespace = 'public'::regnamespace and c.relrowsecurity
            and c.relname in ('scope_confirmations', 'scope_confirmation_acknowledgments', 'project_operational_notes')), 3,
  'RLS is enabled on the three new tables');
select is((select count(*)::int from pg_policies p where p.schemaname = 'public' and p.permissive = 'RESTRICTIVE'
            and p.tablename in ('scope_confirmations', 'scope_confirmation_acknowledgments', 'project_operational_notes')
            and p.policyname in (p.tablename || '_staff_aal2', p.tablename || '_active_user')), 6,
  'each carries the restrictive staff-aal2 and active-user policies');
select is((select count(*)::int from pg_policies p where p.schemaname = 'public' and p.permissive = 'PERMISSIVE' and p.cmd <> 'SELECT'
            and p.tablename in ('scope_confirmations', 'scope_confirmation_acknowledgments', 'project_operational_notes')), 0,
  'no permissive write policy exists');
select ok(not exists (select 1 from unnest(array['scope_confirmations', 'scope_confirmation_acknowledgments',
                        'project_operational_notes']) t
                       where has_table_privilege('authenticated', 'public.' || t, 'insert, update, delete')
                          or has_table_privilege('anon', 'public.' || t, 'select')
                          or has_table_privilege('service_role', 'public.' || t, 'insert, update, delete')),
  'no API role can write a new table directly; anon cannot read one');
select is((select count(*)::int from pg_attribute a where a.attname = 'project_id' and a.attnotnull
            and a.attrelid in ('public.scope_confirmations'::regclass, 'public.scope_confirmation_acknowledgments'::regclass,
                               'public.project_operational_notes'::regclass)), 3, 'every new table carries a non-null project_id');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'private' and p.proname in ('scope_confirmation_canonical', 'scope_confirmation_verifies',
                         'scope_effective_order_summary', 'scope_authorized_signer', 'current_scope_confirmation',
                         'scope_confirmation_state', 'scope_confirmation_gate')
                         and (has_function_privilege('authenticated', p.oid, 'execute')
                           or has_function_privilege('anon', p.oid, 'execute')
                           or has_function_privilege('service_role', p.oid, 'execute'))),
  'the internal helpers are executable by no API role');
select ok(not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname in ('public', 'private')
                         and p.proname ~ 'scope|acknowledg|operational_note'
                         and p.proname ~ '(bypass|override|waive|force|on_behalf|skip)'),
  'T-LC-19: no bypass, override or on-behalf function exists');
select ok((select bool_and(p.prosecdef and p.proconfig = array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname in ('record_scope_confirmation', 'acknowledge_scope_confirmation',
              'record_operational_note', 'scope_confirmation_status')),
  'the four entry points are security definer with an empty search_path');
-- Owner verification clarification 3 (B-1c): both layers.
select ok((select count(*) = 4 and bool_and(not p.prosecdef and p.proconfig = array['search_path=""'])
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('record_scope_confirmation', 'acknowledge_scope_confirmation',
              'record_operational_note', 'scope_confirmation_status')),
  'each public wrapper is security invoker with an empty search_path');
select ok((select count(*) = 4 and bool_and(has_function_privilege('authenticated', p.oid, 'execute')
                     and not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('service_role', p.oid, 'execute'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('record_scope_confirmation', 'acknowledge_scope_confirmation',
              'record_operational_note', 'scope_confirmation_status')),
  'each public wrapper is executable by authenticated only');
select ok((select count(*) = 4 and bool_and(not has_function_privilege('anon', p.oid, 'execute')
                     and not has_function_privilege('service_role', p.oid, 'execute'))
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname in ('record_scope_confirmation', 'acknowledge_scope_confirmation',
              'record_operational_note', 'scope_confirmation_status')),
  'no private implementation is executable by anon, service_role or PUBLIC');

select * from finish();
rollback;
