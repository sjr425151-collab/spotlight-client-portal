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
-- private.project_financial_status returns (to_jsonb byte for byte), computed in ONE set-based pass
-- over every requested project:
--   - the eight branches of project_financial_anomalies, with financial_conflict_cleared evaluated
--     once per distinct relevant event (a STABLE function of the event id alone), not once per
--     event per project per gate, reduced to the G2 and G4 kind arrays gate_anomalies returns;
--   - the components project_financial_status reads (agreement, deposit and final-balance states and
--     their verification, active billing holds, payment authorization state, ledger digest), each a
--     set-based copy of the per-project function's own expression;
--   - each project's row is then assembled in the same field order as project_financial_status.
-- Per-project failure never fails the call: a project whose evaluation would raise gets
-- failed = true and a null status. If the set pass itself raises, the helper falls back, for that
-- call, to the existing per-project function with that same per-project handling, so the results
-- and failure flags are those of the per-project function exactly. A null id always takes that path.
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
  v_dep jsonb := '{}'::jsonb;
  v_comp jsonb := '{}'::jsonb;
  v_c jsonb;
  v_deposit_verified boolean;
  v_set_ok boolean := true;
  v_g2 text[];
  v_g4 text[];
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
    -- private.reversal_observations and private.unposted_reversals, for every requested project.
    reversal_obs as (
      select w.project_id as pid, x.o ->> 'id' as object_id, x.o ->> 'object' as object_kind, x.o ->> 'status' as status,
             private.charge_kind_gates(private.object_charge_kinds(w.project_id, array[x.o ->> 'charge', x.o ->> 'payment_intent'], null)) as gates,
             w.stripe_created_at as observed_at
        from public.webhook_events w
        join ids on ids.pid = w.project_id
       cross join lateral (
         select w.payload #> '{data,object}' as o where w.payload #>> '{data,object,object}' in ('refund', 'dispute')
         union all
         select r || jsonb_build_object('charge', w.payload #>> '{data,object,id}')
           from jsonb_array_elements(case when w.payload #>> '{data,object,object}' = 'charge'
                                               and jsonb_typeof(w.payload #> '{data,object,refunds,data}') = 'array'
                                          then w.payload #> '{data,object,refunds,data}' else '[]'::jsonb end) r) x
       where w.processing_status <> 'ignored' and x.o ->> 'id' is not null
      union all
      select m.project_id, m.stripe_object_id, case when m.kind = 'unmatched_refund' then 'refund' else 'dispute' end, m.observed_status,
             private.charge_key_gates(m.charge_key), m.detected_at
        from public.reconciliation_mismatches m
        join ids on ids.pid = m.project_id
       where m.kind in ('unmatched_refund', 'unmatched_dispute')
    ),
    unposted as (
      select l.pid, l.object_id, l.gates
        from (select distinct on (r.pid, r.object_id) r.*
                from reversal_obs r
               order by r.pid, r.object_id, r.observed_at desc,
                        (r.status in ('succeeded', 'needs_response', 'under_review', 'lost')) desc) l
       where ((l.object_kind = 'refund' and l.status = 'succeeded')
              or (l.object_kind = 'dispute' and l.status in ('needs_response', 'under_review', 'lost')))
         and not exists (select 1 from public.ledger_entries e where e.project_id = l.pid
                           and e.stripe_object_id = l.object_id and e.entry_type in ('refund', 'dispute_opened'))
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
      select u.pid, 'unposted_reversal', u.gates from unposted u
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
    -- private.project_deposit_state and private.project_deposit_verified, for every requested project.
    select coalesce(jsonb_object_agg(d.pid::text, jsonb_build_object('state', d.state,
             'verified', d.state = 'verified' and private.holding_balance_cents(d.charge_key) = 0)), '{}'::jsonb)
      into v_dep
      from (select i.pid, ob.charge_key,
                   case when ob.id is not null then
                          case when exists (select 1 from public.ledger_entries x
                                              join public.disputes dd on dd.stripe_dispute_id = x.stripe_object_id
                                             where x.entry_type = 'dispute_opened'
                                               and (x.obligation_id = ob.id or x.holding_charge_key = ob.charge_key)
                                               and (private.dispute_is_open(dd.status) or dd.status = 'lost'))
                                 then 'disputed'
                               when ob.original_cents + coalesce((select sum(l.amount_cents) from public.ledger_entries l
                                                                  where l.obligation_id = ob.id), 0) <= 0
                                 then 'refunded'
                               else 'verified' end
                        else coalesce((select case when cs.status in ('expired', 'failed') or cs.payment_status = 'failed'
                                                     then 'failed' else 'pending' end
                                         from public.checkout_sessions cs
                                        where cs.project_id = i.pid and cs.kind = 'initial'
                                        order by cs.created_at desc, cs.attempt desc limit 1), 'not_started') end as state
              from (select distinct u as pid from unnest(p_project_ids) u where u is not null) i
              left join lateral (select o.* from public.payment_obligations o
                                  where o.project_id = i.pid and o.kind = 'development_deposit'
                                  order by o.created_at limit 1) ob on true) d;
    -- The remaining components, as the per-project functions compute them: project_agreement_state
    -- (with project_deposit_ever_verified), project_final_balance_state and project_balance_verified,
    -- project_active_billing_holds, payment_authorization_state, and the ledger digest.
    select coalesce(jsonb_object_agg(c.pid::text, jsonb_build_object(
             'ag_state', c.ag_state, 'ag_os', c.os_id, 'ag_acc', c.acc_id,
             'fbs', c.fbs, 'bv', c.fbs = 'verified' and not c.paid_holding,
             'holds', to_jsonb(c.holds), 'auth', c.auth, 'digest', c.digest)), '{}'::jsonb)
      into v_comp
      from (select i.pid, sp.os_id, sp.acc_id,
                   case when sp.os_id is null then 'not_presented'
                        when sp.acc_id is null then
                          case when ev.ever and exists (select 1 from public.agreement_acceptances a
                                                          join public.order_summaries os on os.id = a.order_summary_id
                                                         where os.project_id = i.pid and os.status = 'superseded')
                               then 'reacceptance_required' else 'presented' end
                        when ev.ever then 'effective' else 'accepted_pending_payment' end as ag_state,
                   case when fb.id is null then 'not_due'
                        when fb.status = 'paid' then
                          case when fo.id is null then 'pending'
                               when exists (select 1 from public.ledger_entries x
                                              join public.disputes dd on dd.stripe_dispute_id = x.stripe_object_id
                                             where x.entry_type = 'dispute_opened'
                                               and (x.obligation_id = fo.id or x.holding_charge_key = fo.charge_key)
                                               and (private.dispute_is_open(dd.status) or dd.status = 'lost'))
                                 then 'disputed'
                               when fo.original_cents + coalesce((select sum(l.amount_cents) from public.ledger_entries l
                                                                  where l.obligation_id = fo.id), 0) < fo.original_cents
                                 then 'refunded'
                               else 'verified' end
                        when fb.status in ('open', 'action_required') then 'pending'
                        when fb.status = 'payment_failed' then 'failed'
                        else 'due' end as fbs,
                   exists (select 1 from public.final_balance_invoices f where f.project_id = i.pid and f.status = 'paid'
                             and private.holding_balance_cents('final_balance:' || f.id::text) <> 0) as paid_holding,
                   (select coalesce(array_agg(distinct h.hold_type order by h.hold_type), '{}')
                      from public.billing_holds h where h.project_id = i.pid and h.cleared_at is null) as holds,
                   coalesce((select a.status::text from public.payment_authorizations a where a.project_id = i.pid
                              order by (a.status <> 'revoked') desc, a.created_at desc limit 1), 'none') as auth,
                   (select private.sha256_hex(coalesce(string_agg(l.entry_id::text, ',' order by l.id), ''))
                      from public.ledger_entries l where l.project_id = i.pid) as digest
              from (select distinct u as pid from unnest(p_project_ids) u where u is not null) i
              left join lateral (select os.id as os_id,
                                        (select a.id from public.agreement_acceptances a where a.order_summary_id = os.id) as acc_id
                                   from public.order_summaries os
                                  where os.project_id = i.pid and os.status = 'presented') sp on true
              cross join lateral (select exists (select 1 from public.ledger_entries le where le.project_id = i.pid
                                                   and le.entry_type = 'deposit_charge') as ever) ev
              left join lateral (select f.* from public.final_balance_invoices f
                                  where f.project_id = i.pid and f.status <> 'void' order by f.created_at desc limit 1) fb on true
              left join lateral (select o.* from public.payment_obligations o
                                  where o.charge_key = 'final_balance:' || fb.id::text and o.kind = 'development_balance') fo on true) c;
  exception when others then
    v_set_ok := false;
  end;

  -- 2. One row per distinct requested id (null included), each in its own failure scope.
  for v_id in select distinct u from unnest(p_project_ids) u loop
    project_id := v_id;
    if not v_set_ok or v_id is null then
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
      -- The fields of private.project_financial_status, in its order, from the set pass; G2 and G4
      -- are the kinds gate_anomalies returns for this project (empty when it has none).
      v_c := v_comp -> v_id::text;
      v_deposit := (v_dep -> v_id::text ->> 'state')::public.deposit_state;
      v_deposit_verified := (v_dep -> v_id::text ->> 'verified')::boolean;
      v_balance := (v_c ->> 'fbs')::public.final_balance_state;
      v_holds := coalesce((select array_agg(x::public.hold_type order by o) from jsonb_array_elements_text(v_c -> 'holds')
                             with ordinality t (x, o)), '{}');
      v_auth_state := v_c ->> 'auth';
      v_g2 := coalesce((select array_agg(x order by o) from jsonb_array_elements_text(v_map -> v_id::text -> 'G2')
                          with ordinality t (x, o)), '{}');
      v_g4 := coalesce((select array_agg(x order by o) from jsonb_array_elements_text(v_map -> v_id::text -> 'G4')
                          with ordinality t (x, o)), '{}');
      v_digest := v_c ->> 'digest';
      status := row(
        v_id, 3::smallint, true,
        v_deposit, v_deposit_verified and cardinality(v_g2) = 0,
        v_balance, (v_c ->> 'bv')::boolean and cardinality(v_g4) = 0, v_balance = 'settled_by_adjustment',
        v_holds,
        jsonb_build_object('order_summary_id', (v_c ->> 'ag_os')::uuid, 'acceptance_id', (v_c ->> 'ag_acc')::uuid,
          'ledger_digest', v_digest, 'calendar_version', private.calendar_version(), 'evaluated_at', now(),
          'blocking_anomalies', jsonb_build_object('G2', to_jsonb(v_g2), 'G4', to_jsonb(v_g4))),
        (v_c ->> 'ag_state')::public.agreement_state, v_c ->> 'ag_state' = 'effective',
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
