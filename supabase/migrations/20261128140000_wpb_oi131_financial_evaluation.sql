-- AUTH-026 (OI-131), WP-B financial component: an ADDITIVE, set-based financial evaluation for the
-- staff operational queue. Decision: OI-131 (Owner, 2026-11-28). Reserved migration.
--
-- Root cause (measured locally, 295 active projects; pg_stat_xact_user_functions, track_functions
-- = all): one operational_queue call took 8.66 s. private.project_financial_status ran 542 times;
-- private.project_financial_anomalies 1,084 times (7.6 s); private.financial_conflict_cleared
-- 15,176 times (5.9 s). Branch 7 of project_financial_anomalies tests every candidate webhook event
-- for every project evaluated, so the conflict functions run (events x evaluations) times.
--
-- This migration adds one private helper. It returns, for each requested project, exactly the row
-- private.project_financial_status returns, computed from ONE set-based anomaly pass:
--   - financial_conflict_cleared is evaluated once per distinct relevant event (it is a STABLE
--     function of the event id alone), not once per event per project per gate;
--   - each project's status is assembled from the same sub-functions project_financial_status uses,
--     in the same order, with the G2 and G4 anomaly kinds that gate_anomalies would return.
-- Per-project failure never fails the call: a project whose evaluation would raise gets
-- failed = true and a null status. If the set-based anomaly pass itself raises, the helper falls
-- back, for that call, to the existing per-project function with the same per-project handling.
--
-- Unchanged (byte-identical, keeping every caller): project_financial_status, gate_anomalies,
-- project_financial_anomalies, the financial conflict functions and every other WP-B function. No
-- financial calculation, classification, authorization boundary, timeout, grant or RLS policy
-- changes. No API role may execute the helper; WP-C's operational_queue (AUTH-026 PR 2) calls it as
-- a definer. STABLE; it takes no lock.
--
-- Indexes (only where the analysis showed unindexed per-project scans; pg_stat_xact_user_tables at
-- 1,000 synthetic projects after ANALYZE): checkout_sessions was sequentially scanned 1,104 times
-- (717,600 rows read) by the deposit-state lookup, which no existing index serves (the only project
-- index is partial, on open initial sessions); reconciliation_mismatches, billing_holds,
-- payment_authorizations and final_balance_invoices were scanned once or twice per project for lack
-- of a full project index. The indexes change no query result, only the access path.

create index checkout_sessions_project_kind_idx
  on public.checkout_sessions (project_id, kind, created_at desc, attempt desc);
create index reconciliation_mismatches_project_idx on public.reconciliation_mismatches (project_id);
create index billing_holds_project_idx on public.billing_holds (project_id);
create index payment_authorizations_project_idx on public.payment_authorizations (project_id);
create index final_balance_invoices_project_idx on public.final_balance_invoices (project_id);

create function private.financial_evaluation_for_projects(p_project_ids uuid[])
returns table (project_id uuid, status private.project_financial_status, failed boolean)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_id uuid;
  v_map jsonb := '{}'::jsonb;
  v_set_ok boolean := true;
  v_g2 text[];
  v_g4 text[];
  v_agreement record;
  v_deposit public.deposit_state;
  v_balance public.final_balance_state;
  v_holds public.hold_type[];
  v_digest text;
  v_auth_state text;
begin
  -- 1. The set-based anomaly pass: the eight branches of project_financial_anomalies, for every
  --    requested project at once, reduced to the per-gate kind arrays gate_anomalies returns.
  begin
    with ids as (
      select distinct u as pid from unnest(p_project_ids) u where u is not null
    ),
    candidate_events as materialized (
      select distinct c.webhook_event_id as id
        from private.financial_event_project_candidates c
        join public.webhook_events w on w.id = c.webhook_event_id
       where exists (select 1 from ids where ids.pid = w.project_id)
          or exists (select 1 from private.financial_event_project_candidates c2
                      join ids on ids.pid = c2.project_id where c2.webhook_event_id = w.id)
    ),
    quarantined_events as materialized (
      select w.id from public.webhook_events w join ids on ids.pid = w.project_id
       where w.processing_status = 'quarantined' and w.quarantine_resolved_at is null
    ),
    cleared as materialized (
      select e.id, private.financial_conflict_cleared(e.id) as is_cleared
        from (select id from candidate_events union select id from quarantined_events) e
    ),
    anomalies as (
      -- 1. Quarantined events, attributed through the charge they concern.
      select w.project_id as pid, 'quarantined_event' as kind,
             private.charge_kind_gates(private.event_charge_kinds(w)) as gates
        from public.webhook_events w
        join quarantined_events q on q.id = w.id
        join cleared c on c.id = w.id
       where not c.is_cleared
      union all
      -- 2. Open reconciliation items.
      select m.project_id, 'reconciliation_mismatch', case
               when m.kind = 'deposit_snapshot' then array['G2']
               when m.kind in ('balance_snapshot', 'charged_after_halt') then array['G4']
               when m.kind in ('unmatched_refund', 'unmatched_dispute') then private.charge_key_gates(m.charge_key)
               else array['G2', 'G4'] end
        from public.reconciliation_mismatches m join ids on ids.pid = m.project_id
       where m.resolved_at is null
      union all
      -- 3. Ambiguous outbound requests, by the charge their record belongs to.
      select o.project_id, 'ambiguous_request', case
               when o.purpose = 'checkout_session_create' then array['G2']
               when o.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto', 'recovery_session_create')
                 then array['G4']
               else array['G2', 'G4'] end
        from public.outbound_stripe_requests o join ids on ids.pid = o.project_id
       where o.status = 'ambiguous'
      union all
      -- 4. A failed automatic-collection stop; already_paid alone is not an anomaly.
      select o.project_id, 'automatic_stop_failed', array['G4']
        from public.outbound_stripe_requests o join ids on ids.pid = o.project_id
       where o.purpose = 'final_balance_invoice_disable_auto' and o.status = 'failed'
         and coalesce(o.error_code, '') <> 'already_paid'
      union all
      -- 5. A charge after halted collection that the Owner has not reviewed.
      select f.project_id, 'charged_after_halt', array['G4']
        from public.final_balance_invoices f join ids on ids.pid = f.project_id
       where f.charged_after_halt
         and not exists (select 1 from public.reconciliation_mismatches m where m.kind = 'charged_after_halt'
                           and m.charge_key = 'final_balance:' || f.id::text and m.resolved_at is not null)
      union all
      -- 6. Reversals Stripe reports that the ledger has not posted (per project, as before).
      select ids.pid, 'unposted_reversal', u.gates
        from ids cross join lateral private.unposted_reversals(ids.pid) u
      union all
      -- 7. An event with conflicting authoritative projects blocks G2 and G4 for every candidate
      --    project and for the project the event carries, unless a re-verified Owner conflict
      --    application cleared it.
      select p.pid, 'quarantined_event', array['G2', 'G4']
        from public.webhook_events w
        join candidate_events ce on ce.id = w.id
        join cleared c on c.id = w.id
        cross join lateral (
          select w.project_id as pid
          union
          select c3.project_id from private.financial_event_project_candidates c3 where c3.webhook_event_id = w.id
        ) p
        join ids on ids.pid = p.pid
       where not c.is_cleared
      union all
      -- 8. A stop the Owner reconciled as absent, with no later authoritative attempt.
      select o.project_id, 'automatic_stop_unresolved', array['G4']
        from public.outbound_stripe_requests o
        join ids on ids.pid = o.project_id
        join public.final_balance_invoices f on f.id = o.domain_record_id
       where o.purpose = 'final_balance_invoice_disable_auto'
         and o.domain_record_type = 'final_balance_invoice' and o.status = 'reconciled_absent' and f.status <> 'paid'
         and not exists (select 1 from public.outbound_stripe_requests r
                          where r.domain_record_type = o.domain_record_type and r.domain_record_id = o.domain_record_id
                            and r.purpose = o.purpose and r.attempt > o.attempt
                            and r.status in ('succeeded', 'reconciled_present'))
    )
    select coalesce(jsonb_object_agg(g.pid::text, jsonb_build_object('G2', to_jsonb(g.g2), 'G4', to_jsonb(g.g4))), '{}'::jsonb)
      into v_map
      from (select a.pid,
                   coalesce(array_agg(distinct a.kind order by a.kind) filter (where 'G2' = any (a.gates)), '{}') as g2,
                   coalesce(array_agg(distinct a.kind order by a.kind) filter (where 'G4' = any (a.gates)), '{}') as g4
              from anomalies a group by a.pid) g;
  exception when others then
    v_set_ok := false;
  end;

  -- 2. One row per distinct requested id (null included), each in its own failure scope.
  for v_id in select distinct u from unnest(p_project_ids) u loop
    project_id := v_id;
    if not v_set_ok then
      -- Fallback: the existing per-project function, with the same per-project handling.
      begin
        status := private.project_financial_status(v_id);
        failed := false;
      exception when others then
        status := null;
        failed := true;
      end;
      return next;
      continue;
    end if;
    begin
      -- The same sub-functions, in the same order, as private.project_financial_status; G2 and G4
      -- are the kinds gate_anomalies returns for this project (empty when it has none).
      select * into v_agreement from private.project_agreement_state(v_id);
      v_deposit := private.project_deposit_state(v_id);
      v_balance := private.project_final_balance_state(v_id);
      v_holds := private.project_active_billing_holds(v_id);
      v_auth_state := private.payment_authorization_state(v_id);
      v_g2 := coalesce((select array_agg(x order by o) from jsonb_array_elements_text(v_map -> v_id::text -> 'G2')
                          with ordinality t (x, o)), '{}');
      v_g4 := coalesce((select array_agg(x order by o) from jsonb_array_elements_text(v_map -> v_id::text -> 'G4')
                          with ordinality t (x, o)), '{}');
      select private.sha256_hex(coalesce(string_agg(l.entry_id::text, ',' order by l.id), ''))
        into v_digest from public.ledger_entries l where l.project_id = v_id;
      status := row(
        v_id, 3::smallint, true,
        v_deposit, private.project_deposit_verified(v_id) and cardinality(v_g2) = 0,
        v_balance, private.project_balance_verified(v_id) and cardinality(v_g4) = 0, v_balance = 'settled_by_adjustment',
        v_holds,
        jsonb_build_object('order_summary_id', v_agreement.order_summary_id, 'acceptance_id', v_agreement.acceptance_id,
          'ledger_digest', v_digest, 'calendar_version', private.calendar_version(), 'evaluated_at', now(),
          'blocking_anomalies', jsonb_build_object('G2', to_jsonb(v_g2), 'G4', to_jsonb(v_g4))),
        v_agreement.state, v_agreement.state = 'effective',
        v_auth_state = 'active', v_auth_state
      )::private.project_financial_status;
      failed := false;
    exception when others then
      status := null;
      failed := true;
    end;
    return next;
  end loop;
end;
$$;

revoke all on function private.financial_evaluation_for_projects(uuid[]) from public, anon, authenticated, service_role;
