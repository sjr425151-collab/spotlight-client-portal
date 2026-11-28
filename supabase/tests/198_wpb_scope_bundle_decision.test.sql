-- AUTH-022 (PWP-2), OI-132 (Owner, 2026-11-28, option (a)): the issuance eligibility decision table.
-- Issuance requires BOTH an eligible bundle (F1: newest sealed, verifying, not withdrawn, activated
-- for a non-fixture bundle) AND the AUTH-018 interim scope gate (current_package_scope resolves) at
-- the bundle's pinned scope version. Every other combination refuses with scope_definition_missing,
-- an audit row and no state change, with no fallback to an older bundle or scope version.
--
-- Bundle states: eligible, unactivated_newer (sealed, never approved or activated), withdrawn,
-- integrity (a component no longer verifies). Scope states: current_matching, newer_inactive (a newer
-- version loaded, not activated), tampered (the pinned version's rows altered), withdrawn, missing
-- (no scope rows). Each cell builds its state through the AUTH-021 and AUTH-018 Owner functions only
-- (synthetic content; the agreement holds only a synthetic heading and the approved 04 §3.1 clause),
-- inside a subtransaction that is rolled back, so the cells are independent.
-- Seed: Owner …01, Admin …02, Project A …a0. Synthetic data only; everything is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(21);

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
    'session_id', v_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.owner_ok(p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb;
begin
  perform pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
  execute p_sql into v;
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'setup refused: % -> %', p_sql, v;
  end if;
  return v;
end;
$$;
create function pg_temp.scope_sha(p_key text, p_version integer, p_items text[]) returns text language sql as $$
  select encode(extensions.digest(convert_to('spotlight.package_scope.v1|k' || octet_length(p_key) || ':' || p_key
    || '|v' || p_version || '|n' || cardinality(p_items)
    || (select string_agg('|p' || o || ':' || octet_length(t) || ':' || t, '' order by o)
          from unnest(p_items) with ordinality u (t, o)), 'UTF8'), 'sha256'), 'hex')
$$;
-- A synthetic scope version: approved, loaded and (optionally) activated through the AUTH-018 functions.
create function pg_temp.syn_scope(p_pkg text, p_activate boolean) returns integer language plpgsql as $$
declare
  v_v integer := (select coalesce(max(v), 0) + 1 from (
                    select max(scope_version) v from private.billing_package_scope where package_key = p_pkg
                    union all select max(scope_version) from private.billing_package_scope_versions where package_key = p_pkg) x);
  v_items text[] := array['PGTAP SYNTHETIC SCOPE ITEM 198-A ' || v_v, 'PGTAP SYNTHETIC SCOPE ITEM 198-B ' || v_v];
begin
  perform pg_temp.owner_ok(format('select public.record_package_scope_approval(%L, %s, %L, %L, %L)', p_pkg, v_v,
    pg_temp.scope_sha(p_pkg, v_v, v_items), 'PGTAP-198-' || v_v, repeat('e', 64)));
  perform pg_temp.owner_ok(format('select public.load_package_scope_version(%L, %s, %L::text[])', p_pkg, v_v, v_items));
  if p_activate then
    perform pg_temp.owner_ok(format('select public.activate_package_scope_version(%L, %s)', p_pkg, v_v));
  end if;
  return v_v;
end;
$$;
-- A synthetic bundle pinning a scope version: instruments, agreement, sealing and (optionally)
-- approval and activation, through the AUTH-021 and WP-B Owner functions.
create function pg_temp.syn_bundle(p_pkg text, p_scope_version integer, p_activate boolean) returns uuid
language plpgsql as $$
declare
  v_kind text;
  v_ver integer;
  v_body text;
  v_ids jsonb := '{}';
  v jsonb;
begin
  foreach v_kind in array array['package_specification', 'maintenance_specification', 'shared_terms'] loop
    v_ver := coalesce((select max(i.instrument_version) from private.contract_instrument_versions i
                        where i.kind = v_kind and i.package_key is not distinct from
                          case when v_kind = 'package_specification' then p_pkg end), 0) + 1;
    v_body := 'PGTAP SYNTHETIC ' || v_kind || ' (198)';
    v := pg_temp.owner_ok(format('select public.create_contract_instrument_version(%L, %L, %s, %L, %L, %L::text[], %L)',
      v_kind, case when v_kind = 'package_specification' then p_pkg end, v_ver, 'PGTAP SYNTHETIC', v_body,
      array['S1', 'S2'], private.contract_instrument_sha256(v_kind,
        case when v_kind = 'package_specification' then p_pkg end, v_ver, 'PGTAP SYNTHETIC', v_body, array['S1', 'S2'])));
    v_ids := v_ids || jsonb_build_object(v_kind, v ->> 'instrument_id');
  end loop;
  v := pg_temp.owner_ok(format('select public.create_agreement_version(%L, %L, date %L, %L)', 'pgtap-198',
    'PGTAP SYNTHETIC AGREEMENT (198)' || E'\n\n' || private.final_payment_clause(), '2026-11-01', 'PGTAP-198-AGR'));
  v_ids := v_ids || jsonb_build_object('agreement', v ->> 'agreement_version_id');
  perform pg_temp.owner_ok(format('select public.approve_agreement_version(%L)', v_ids ->> 'agreement'));
  v := pg_temp.owner_ok(format('select public.seal_contract_bundle(%L, %L, %L, %L, %L, %L, %s, %L::jsonb)', p_pkg,
    'PGTAP SYNTHETIC BUNDLE (198)', v_ids ->> 'agreement', v_ids ->> 'package_specification',
    v_ids ->> 'maintenance_specification', v_ids ->> 'shared_terms', p_scope_version, '["S1", "S2"]'));
  if p_activate then
    perform pg_temp.owner_ok(format('select public.record_contract_bundle_approval(%L, %L, %L, %L)', v ->> 'bundle_id',
      v ->> 'bundle_sha256', 'PGTAP-198-LEGAL', repeat('e', 64)));
    perform pg_temp.owner_ok(format('select public.activate_contract_bundle(%L)', v ->> 'bundle_id'));
  end if;
  return (v ->> 'bundle_id')::uuid;
end;
$$;
-- One cell: build the state, issue as the Admin, record the outcome, then roll the subtransaction
-- back so the next cell starts from the seeded state.
create function pg_temp.cell(p_bundle text, p_scope text) returns jsonb language plpgsql as $$
declare
  c_project constant uuid := '20000000-0000-4000-8000-0000000000a0';
  c_pkg constant text := 'advanced';
  v_s integer;
  v_b uuid;
  v_mark bigint;
  v_before integer;
  v jsonb;
  v_out jsonb;
begin
  begin
    v_s := pg_temp.syn_scope(c_pkg, true);
    v_b := pg_temp.syn_bundle(c_pkg, v_s, p_bundle <> 'unactivated_newer');
    if p_bundle = 'withdrawn' then
      perform pg_temp.owner_ok(format('select public.withdraw_contract_bundle(%L, %L, %L)', v_b,
        'Synthetic withdrawal (198)', 'PGTAP-198-WD'));
    elsif p_bundle = 'integrity' then
      alter table private.contract_instrument_versions disable trigger contract_instrument_versions_append_only;
      update private.contract_instrument_versions set body = body || ' (tampered)'
       where id = (select package_instrument_id from private.contract_bundles where id = v_b);
      alter table private.contract_instrument_versions enable trigger contract_instrument_versions_append_only;
    end if;
    if p_scope = 'newer_inactive' then
      perform pg_temp.syn_scope(c_pkg, false);
    elsif p_scope = 'tampered' then
      alter table private.billing_package_scope disable trigger billing_package_scope_append_only;
      update private.billing_package_scope set item_text = item_text || ' (tampered)'
       where package_key = c_pkg and scope_version = v_s and position = 1;
      alter table private.billing_package_scope enable trigger billing_package_scope_append_only;
    elsif p_scope = 'withdrawn' then
      perform pg_temp.owner_ok(format('select public.withdraw_package_scope_version(%L, %s)', c_pkg, v_s));
    elsif p_scope = 'missing' then
      alter table private.billing_package_scope disable trigger billing_package_scope_append_only;
      delete from private.billing_package_scope where package_key = c_pkg;
      alter table private.billing_package_scope enable trigger billing_package_scope_append_only;
    end if;
    v_mark := (select coalesce(max(id), 0) from public.audit_events);
    v_before := (select count(*) from public.order_summaries where project_id = c_project);
    perform pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
    v := public.issue_order_summary(c_project, c_pkg);
    reset role;
    v_out := jsonb_build_object('ok', coalesce((v ->> 'ok')::boolean, false), 'error', v ->> 'error',
      'refusal_audited', exists (select 1 from public.audit_events e where e.id > v_mark
        and e.project_id = c_project and e.action = 'order_summary.bundle_unavailable'
        and e.summary ->> 'reason' = 'missing_scope_definition'),
      'summaries_added', (select count(*) from public.order_summaries where project_id = c_project) - v_before,
      'pinned', (select scope_version = v_s and contract_bundle_id = v_b from public.order_summaries
                  where project_id = c_project and status = 'presented'));
    raise exception using errcode = 'P0099', message = v_out::text;
  exception when sqlstate 'P0099' then
    return sqlerrm::jsonb;
  end;
end;
$$;
create function pg_temp.refused(p_bundle text, p_scope text) returns boolean language sql as $$
  select (r ->> 'ok')::boolean = false and r ->> 'error' = 'scope_definition_missing'
     and (r ->> 'refusal_audited')::boolean and (r ->> 'summaries_added')::int = 0
  from (select pg_temp.cell(p_bundle, p_scope) r) x
$$;

-- The one eligible cell.
select ok((select (r ->> 'ok')::boolean and (r ->> 'summaries_added')::int = 1 and (r ->> 'pinned')::boolean
             and not (r ->> 'refusal_audited')::boolean
           from (select pg_temp.cell('eligible', 'current_matching') r) x),
  'OI-132: eligible bundle × current matching scope → issued, pinning that bundle and scope version');
-- Every other cell refuses, audited, with no state change and no fallback.
select ok(pg_temp.refused('eligible', 'newer_inactive'), 'OI-132: eligible bundle × newer inactive scope → refused');
select ok(pg_temp.refused('eligible', 'tampered'), 'OI-132: eligible bundle × tampered scope → refused');
select ok(pg_temp.refused('eligible', 'withdrawn'), 'OI-132: eligible bundle × withdrawn scope → refused');
select ok(pg_temp.refused('eligible', 'missing'), 'OI-132: eligible bundle × missing scope → refused');
select ok(pg_temp.refused('unactivated_newer', 'current_matching'), 'OI-132: unactivated newer bundle × current scope → refused');
select ok(pg_temp.refused('unactivated_newer', 'newer_inactive'), 'OI-132: unactivated newer bundle × newer inactive scope → refused');
select ok(pg_temp.refused('unactivated_newer', 'tampered'), 'OI-132: unactivated newer bundle × tampered scope → refused');
select ok(pg_temp.refused('unactivated_newer', 'withdrawn'), 'OI-132: unactivated newer bundle × withdrawn scope → refused');
select ok(pg_temp.refused('unactivated_newer', 'missing'), 'OI-132: unactivated newer bundle × missing scope → refused');
select ok(pg_temp.refused('withdrawn', 'current_matching'), 'OI-132: withdrawn bundle × current scope → refused');
select ok(pg_temp.refused('withdrawn', 'newer_inactive'), 'OI-132: withdrawn bundle × newer inactive scope → refused');
select ok(pg_temp.refused('withdrawn', 'tampered'), 'OI-132: withdrawn bundle × tampered scope → refused');
select ok(pg_temp.refused('withdrawn', 'withdrawn'), 'OI-132: withdrawn bundle × withdrawn scope → refused');
select ok(pg_temp.refused('withdrawn', 'missing'), 'OI-132: withdrawn bundle × missing scope → refused');
select ok(pg_temp.refused('integrity', 'current_matching'), 'OI-132: integrity-failed bundle × current scope → refused');
select ok(pg_temp.refused('integrity', 'newer_inactive'), 'OI-132: integrity-failed bundle × newer inactive scope → refused');
select ok(pg_temp.refused('integrity', 'tampered'), 'OI-132: integrity-failed bundle × tampered scope → refused');
select ok(pg_temp.refused('integrity', 'withdrawn'), 'OI-132: integrity-failed bundle × withdrawn scope → refused');
select ok(pg_temp.refused('integrity', 'missing'), 'OI-132: integrity-failed bundle × missing scope → refused');
-- The cells left nothing behind (each subtransaction was rolled back).
select is((select count(*)::int from public.order_summaries where project_id = '20000000-0000-4000-8000-0000000000a0'), 0,
  'OI-132: the decision table changed no order summary');

select * from finish();
rollback;
