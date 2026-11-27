-- WP-B (AUTH-010; Owner grant 2026-11-27): OI-93 conflict decisions, part 2 of 2: the Owner
-- functions, the application attempt, block clearing and the project_financial_anomalies
-- replacement. Decision: OI-93; AUTHORIZATIONS AUTH-010 (design rows, grant, U-1 to U-4).
--
-- Owner-facing functions (U-2; names and signatures fixed): each a private SECURITY DEFINER
-- function with search_path='' that checks Owner, aal2 (implied by fresh MFA), fresh MFA, a live
-- session and, where it takes one, a reason; each with an INVOKER public wrapper granted to
-- authenticated only, which sets the 5-second lock_timeout for the whole call:
--   record_financial_conflict_decision(p_webhook_event_id bigint, p_project_id uuid, p_evidence jsonb, p_reason text)
--   retry_financial_conflict_application(p_decision_id uuid, p_attempt_request_id uuid, p_reason text)
--   financial_conflict_attempt_status(p_attempt_request_id uuid)
--   financial_conflict_events()
-- The statement limit through the API is the effective 8 seconds of the authenticated and
-- authenticator role settings (U-4); no role or connection setting changes.
--
-- Attempt rules (AUTH-010 "Attempts", "Unknown outcomes"):
-- - every application attempt, the first included, is an Owner action with a unique
--   attempt_request_id; the same id is idempotent: it waits for any attempt in flight under that
--   id and returns the recorded row, or runs the attempt if none was recorded;
-- - lock order: the attempt-request advisory lock, the decision row, the event row, then the
--   merged reversal order inside the extracted path (refund or dispute row, the charge advisory
--   lock, refund_decisions). No AUTH-009 lock (payment authorization, final-balance invoice,
--   outbound request) is taken;
-- - refused with no attempt row (audited financial_conflict.attempt_refused): already applied;
--   permanently unsupported; 10 attempts recorded; within 60 seconds of the last attempt; after
--   awaiting_evidence with an unchanged oi93.fp.v1 fingerprint. After operational_failure a retry
--   is allowed whatever the fingerprint;
-- - one protected step (a subtransaction): classification, the extracted path for every object,
--   the post-check under the locks, the effect recognitions and the application entries. Any
--   unsupported or awaiting object, or any failed proof, rolls the whole step back; the outcome is
--   the most severe; the detail is per object. Clearing re-verifies every application against the
--   ledger as it is then (financial_conflict_cleared);
-- - the tenth non-success row carries terminal_reason 'exhausted'.
--
-- Block clearing (AUTH-010 "Block clearing"): only a posted or represented application whose
-- every new or cited entry re-verifies (financial_conflict_application_verified). A decision
-- alone, or a failed or interrupted attempt, never clears a block. Items 1 and 7 of
-- project_financial_anomalies exclude a cleared event; every other item is byte-identical to
-- 20261127120000 (item 8 included).
--
-- Unchanged: webhook_events_guard, apply_reversal, the ledger rules, process_stripe_event,
-- resolve_quarantined_event. Forward-only (T-MIG-02); merged migrations are not edited.

-- ---------------------------------------------------------------------------
-- 1. Effect types and re-verification
-- ---------------------------------------------------------------------------
-- The effect a reversal ledger entry records; null for any other entry. A refund entry with a
-- positive amount is the mirror of a refund that failed after succeeding (mirror_reversal).
create function private.financial_conflict_effect_type(p_entry_type public.ledger_entry_type, p_amount bigint) returns text
language sql immutable set search_path = '' as $$
  select case
    when p_entry_type = 'refund' and p_amount < 0 then 'refund'
    when p_entry_type = 'refund' and p_amount > 0 then 'refund_reversed'
    when p_entry_type in ('dispute_opened', 'dispute_won', 'dispute_lost') then p_entry_type::text end;
$$;

-- Re-verifies a successful application against the ledger as it is now: the decision and event
-- relationship, the project, every recorded entry (provider object, effect type, amount,
-- currency, obligation or holding target, role), every effect recognition (project, key, exact
-- ledger entry IDs, amount) and completeness (every reversal entry the event posted is recorded).
create function private.financial_conflict_application_verified(p_application_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_app private.financial_conflict_applications%rowtype;
  v_dec private.financial_conflict_decisions%rowtype;
  v_evt public.webhook_events%rowtype;
  v_ids text[];
  v_kind text;
begin
  select * into v_app from private.financial_conflict_applications where id = p_application_id;
  if not found or v_app.outcome not in ('posted', 'represented') then
    return false;
  end if;
  select * into v_dec from private.financial_conflict_decisions where id = v_app.decision_id;
  select * into v_evt from public.webhook_events where id = v_app.webhook_event_id;
  if v_dec.id is null or v_evt.id is null or v_dec.webhook_event_id <> v_evt.id or v_dec.project_id <> v_app.project_id
     or not exists (select 1 from private.financial_event_project_candidates c
                     where c.webhook_event_id = v_evt.id and c.project_id = v_app.project_id) then
    return false;
  end if;
  select coalesce(array_agg(x), '{}') into v_ids
    from jsonb_array_elements_text(private.financial_conflict_scope(v_evt) -> 'object_ids') x;
  if cardinality(v_ids) = 0 then
    return false;
  end if;
  v_kind := case when v_app.category = 'S1' then 'refund' when v_app.category = 'S2' then 'dispute' end;
  -- Every object of the event is recorded under the chosen project.
  if v_kind is null
     or (v_kind = 'refund' and exists (select 1 from unnest(v_ids) i where not exists (
           select 1 from public.refunds r where r.stripe_refund_id = i and r.project_id = v_app.project_id)))
     or (v_kind = 'dispute' and exists (select 1 from unnest(v_ids) i where not exists (
           select 1 from public.disputes d where d.stripe_dispute_id = i and d.project_id = v_app.project_id))) then
    return false;
  end if;
  -- Every recorded entry matches the ledger exactly.
  if exists (
       select 1 from private.financial_conflict_application_entries x
         left join public.ledger_entries l on l.id = x.ledger_entry_id
         left join private.financial_conflict_effects f on f.id = x.effect_id
         left join public.payment_obligations o on o.id = x.obligation_id
        where x.application_id = v_app.id
          and (l.id is null or f.id is null
               or x.project_id <> v_app.project_id or l.project_id <> x.project_id or f.project_id <> x.project_id
               or l.stripe_object_id is distinct from x.stripe_object_id or not (x.stripe_object_id = any (v_ids))
               or f.stripe_object_id <> x.stripe_object_id
               or l.entry_type <> x.entry_type or l.amount_cents <> x.amount_cents or l.currency <> x.currency
               or f.effect_type is distinct from private.financial_conflict_effect_type(l.entry_type, l.amount_cents)
               or l.obligation_id is distinct from x.obligation_id or l.holding_charge_key is distinct from x.holding_charge_key
               or (x.obligation_id is not null and o.project_id is distinct from x.project_id)
               or (x.role = 'new') <> (l.webhook_event_id is not distinct from v_evt.id))) then
    return false;
  end if;
  -- Every effect the application touched: the application records exactly the effect's ledger
  -- entries as recognized (same IDs), and their amount is the effect's amount.
  if exists (
       select 1 from (select distinct x.effect_id from private.financial_conflict_application_entries x
                       where x.application_id = v_app.id) e
         join private.financial_conflict_effects f on f.id = e.effect_id
        where (select array_agg(x.ledger_entry_id order by x.ledger_entry_id) from private.financial_conflict_application_entries x
                where x.application_id = v_app.id and x.effect_id = f.id)
              is distinct from
              (select array_agg(x.ledger_entry_id order by x.ledger_entry_id) from private.financial_conflict_application_entries x
                where x.application_id = f.recognized_by_application_id and x.effect_id = f.id)
           or f.amount_cents <> (select abs(sum(l.amount_cents)) from private.financial_conflict_application_entries x
                                   join public.ledger_entries l on l.id = x.ledger_entry_id
                                  where x.application_id = f.recognized_by_application_id and x.effect_id = f.id)) then
    return false;
  end if;
  -- Completeness: every reversal entry this event posted is recorded as new.
  if exists (select 1 from public.ledger_entries l
              where l.webhook_event_id = v_evt.id
                and private.financial_conflict_effect_type(l.entry_type, l.amount_cents) is not null
                and not exists (select 1 from private.financial_conflict_application_entries x
                                 where x.application_id = v_app.id and x.ledger_entry_id = l.id and x.role = 'new')) then
    return false;
  end if;
  return v_app.outcome = case when exists (select 1 from private.financial_conflict_application_entries x
                                            where x.application_id = v_app.id and x.role = 'new')
                                    or not exists (select 1 from private.financial_conflict_application_entries x
                                                    where x.application_id = v_app.id)
                              then 'posted' else 'represented' end;
end;
$$;

-- An event's candidate blocks clear only through a re-verified successful application.
create function private.financial_conflict_cleared(p_webhook_event_id bigint) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.financial_conflict_applications a
                  where a.webhook_event_id = p_webhook_event_id and a.outcome in ('posted', 'represented')
                    and private.financial_conflict_application_verified(a.id));
$$;

-- ---------------------------------------------------------------------------
-- 2. Recording a decision
-- ---------------------------------------------------------------------------
create function private.record_financial_conflict_decision(p_webhook_event_id bigint, p_project_id uuid, p_evidence jsonb,
  p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_evt public.webhook_events%rowtype;
  v_class jsonb;
  v_id uuid;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  if char_length(btrim(p_reason)) > 1000 then
    return private.fail('reason_too_long');
  end if;
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb
     or octet_length(p_evidence::text) > 16384 then
    return private.fail('evidence_invalid');
  end if;
  select * into v_evt from public.webhook_events where id = p_webhook_event_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if exists (select 1 from private.financial_conflict_decisions d where d.webhook_event_id = v_evt.id) then
    return private.fail('already_decided');
  end if;
  if v_evt.processing_status <> 'quarantined' or v_evt.quarantine_reason is distinct from 'attribution_conflict'
     or not exists (select 1 from private.financial_event_project_candidates c where c.webhook_event_id = v_evt.id) then
    return private.fail('not_eligible');
  end if;
  if not exists (select 1 from private.financial_event_project_candidates c
                  where c.webhook_event_id = v_evt.id and c.project_id = p_project_id) then
    return private.fail('not_a_candidate');
  end if;
  -- One decision per event, so a choice that can never be applied is refused, not recorded.
  v_class := private.financial_conflict_classify(v_evt, p_project_id);
  if v_class ->> 'outcome' = 'permanently_unsupported' then
    return private.fail('conflict_unsupported') || jsonb_build_object('classification', v_class);
  end if;
  insert into private.financial_conflict_decisions (webhook_event_id, project_id, evidence, reason, decided_by)
  values (v_evt.id, p_project_id, p_evidence, btrim(p_reason), (select auth.uid()))
  returning id into v_id;
  perform private.audit_financial('financial_conflict.decision_recorded', 'webhook_event', v_evt.id::text, p_project_id,
    jsonb_build_object('decision_id', v_id, 'stripe_event_id', v_evt.stripe_event_id,
      'candidate_project_ids', (select jsonb_agg(distinct c.project_id) from private.financial_event_project_candidates c
                                 where c.webhook_event_id = v_evt.id),
      'classification', v_class ->> 'outcome'), btrim(p_reason));
  return jsonb_build_object('ok', true, 'decision_id', v_id, 'classification', v_class);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The application attempt
-- ---------------------------------------------------------------------------
create function private.financial_conflict_attempt_summary(p_app private.financial_conflict_applications) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p_app.id, 'decision_id', p_app.decision_id, 'webhook_event_id', p_app.webhook_event_id,
    'project_id', p_app.project_id, 'attempt_no', p_app.attempt_no, 'attempt_request_id', p_app.attempt_request_id,
    'category', p_app.category, 'outcome', p_app.outcome, 'terminal_reason', p_app.terminal_reason,
    'fingerprint', p_app.fingerprint, 'detail', p_app.detail, 'created_at', p_app.created_at,
    'cleared', private.financial_conflict_cleared(p_app.webhook_event_id));
$$;

create function private.retry_financial_conflict_application(p_decision_id uuid, p_attempt_request_id uuid, p_reason text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_dec private.financial_conflict_decisions%rowtype;
  v_evt public.webhook_events%rowtype;
  v_app private.financial_conflict_applications%rowtype;
  v_last private.financial_conflict_applications%rowtype;
  v_count integer;
  v_refusal text;
  v_fp text;
  v_no integer;
  v_app_id uuid := gen_random_uuid();
  v_class jsonb;
  v_kind text;
  v_category text;
  v_outcome text;
  v_detail jsonb := '{}'::jsonb;
  v_objects jsonb := '[]'::jsonb;
  v_o jsonb;
  v_ord bigint;
  v_result text;
  v_obj_outcome text;
  v_effect record;
  v_f private.financial_conflict_effects%rowtype;
  v_effect_id uuid;
  v_any_new boolean := false;
  v_recorded bigint[];
  v_state text;
  v_constraint text;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  if char_length(btrim(p_reason)) > 1000 then
    return private.fail('reason_too_long');
  end if;
  if p_attempt_request_id is null then
    return private.fail('attempt_request_id_required');
  end if;
  -- Idempotency: a request with this id waits for any attempt in flight under it, then returns
  -- the recorded row. financial_conflict_attempt_status reads the same lock without waiting.
  perform pg_advisory_xact_lock(hashtextextended('wpb:oi93:attempt:' || p_attempt_request_id::text, 0));
  select * into v_app from private.financial_conflict_applications where attempt_request_id = p_attempt_request_id;
  if found then
    if v_app.decision_id <> p_decision_id then
      return private.fail('attempt_request_id_reused');
    end if;
    return jsonb_build_object('ok', true, 'existing', true, 'attempt', private.financial_conflict_attempt_summary(v_app));
  end if;
  -- Lock order: decision row, then the event row (serializes every attempt on the decision).
  select * into v_dec from private.financial_conflict_decisions where id = p_decision_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  select * into v_evt from public.webhook_events where id = v_dec.webhook_event_id for update;
  select count(*)::int into v_count from private.financial_conflict_applications a where a.decision_id = v_dec.id;
  select * into v_last from private.financial_conflict_applications a where a.decision_id = v_dec.id
   order by a.attempt_no desc limit 1;
  if exists (select 1 from private.financial_conflict_applications a
              where a.decision_id = v_dec.id and a.outcome in ('posted', 'represented')) then
    v_refusal := 'already_applied';
  elsif exists (select 1 from private.financial_conflict_applications a
                 where a.decision_id = v_dec.id and a.outcome = 'permanently_unsupported') then
    v_refusal := 'permanently_unsupported';
  elsif v_count >= 10 then
    v_refusal := 'attempts_exhausted';
  elsif v_last.id is not null and v_last.created_at > now() - interval '60 seconds' then
    v_refusal := 'retry_too_soon';
  else
    v_fp := private.financial_conflict_fingerprint(v_dec.id);
    if v_last.outcome = 'awaiting_evidence' and v_last.fingerprint = v_fp then
      v_refusal := 'evidence_unchanged';
    end if;
  end if;
  if v_refusal is not null then
    perform private.audit_financial('financial_conflict.attempt_refused', 'webhook_event', v_evt.id::text, v_dec.project_id,
      jsonb_build_object('decision_id', v_dec.id, 'attempt_request_id', p_attempt_request_id, 'refusal', v_refusal,
        'attempts', v_count), btrim(p_reason));
    return private.fail(v_refusal) || jsonb_build_object('attempts', v_count,
      'retry_after', case when v_refusal = 'retry_too_soon' then v_last.created_at + interval '60 seconds' end);
  end if;
  v_no := v_count + 1;

  -- The protected step: everything below is kept only if the application fully succeeds.
  begin
    v_class := private.financial_conflict_classify(v_evt, v_dec.project_id);
    v_category := v_class ->> 'category';
    v_kind := case v_category when 'S1' then 'refund' when 'S2' then 'dispute' end;
    if v_class ->> 'outcome' is not null then
      v_outcome := v_class ->> 'outcome';
      v_detail := jsonb_build_object('stage', 'classification', 'reason', v_class ->> 'reason', 'objects', v_class -> 'objects');
      raise exception using errcode = 'WPBC1', message = v_outcome;
    end if;
    -- The extracted per-project path, once per object (each refund of a charge.refunded event).
    for v_o, v_ord in select x.o, x.i from jsonb_array_elements(private.financial_conflict_scope(v_evt) -> 'objects')
                        with ordinality x(o, i) order by x.i loop
      if v_kind = 'refund' then
        v_result := private.apply_refund_for_project(v_evt, v_o, v_dec.project_id);
      else
        v_result := private.apply_dispute_for_project(v_evt, v_o, v_dec.project_id);
      end if;
      v_obj_outcome := case when v_result = 'processed' then null
                            when v_result = 'deferred' then 'awaiting_evidence'
                            else 'permanently_unsupported' end;
      v_objects := v_objects || jsonb_build_array(jsonb_build_object('ord', v_ord, 'object_id', v_o ->> 'id',
        'result', v_result, 'outcome', v_obj_outcome));
      if v_obj_outcome = 'permanently_unsupported' then
        v_outcome := 'permanently_unsupported';
      elsif v_obj_outcome = 'awaiting_evidence' and v_outcome is null then
        v_outcome := 'awaiting_evidence';
      end if;
    end loop;
    if v_outcome is not null then
      v_detail := jsonb_build_object('stage', 'application', 'objects', v_objects);
      raise exception using errcode = 'WPBC1', message = v_outcome;
    end if;
    -- Post-check under the locks: nothing of these objects is under another project.
    if exists (select 1 from public.ledger_entries l
                where l.stripe_object_id in (select o ->> 'object_id' from jsonb_array_elements(v_objects) o)
                  and l.project_id <> v_dec.project_id) then
      v_outcome := 'permanently_unsupported';
      v_detail := jsonb_build_object('stage', 'post_check', 'reason', 'recognized_under_other_project', 'objects', v_objects);
      raise exception using errcode = 'WPBC1', message = v_outcome;
    end if;
    -- Effects: one recognition per effect key; a recognized effect is cited by exact match.
    for v_effect in
      select l.stripe_object_id as object_id, private.financial_conflict_effect_type(l.entry_type, l.amount_cents) as effect_type,
             abs(sum(l.amount_cents)) as amount, array_agg(l.id order by l.id) as ids,
             array_agg(l.id order by l.id) filter (where l.webhook_event_id is not distinct from v_evt.id) as new_ids
        from public.ledger_entries l
       where l.stripe_object_id in (select o ->> 'object_id' from jsonb_array_elements(v_objects) o)
         and private.financial_conflict_effect_type(l.entry_type, l.amount_cents) is not null
       group by 1, 2 order by 1, 2
    loop
      select * into v_f from private.financial_conflict_effects f
       where f.stripe_object_id = v_effect.object_id and f.effect_type = v_effect.effect_type;
      if found then
        select array_agg(x.ledger_entry_id order by x.ledger_entry_id) into v_recorded
          from private.financial_conflict_application_entries x
         where x.application_id = v_f.recognized_by_application_id and x.effect_id = v_f.id;
        if v_f.project_id <> v_dec.project_id or v_f.amount_cents <> v_effect.amount
           or v_recorded is distinct from v_effect.ids or v_effect.new_ids is not null then
          v_outcome := 'permanently_unsupported';
          v_detail := jsonb_build_object('stage', 'recognition', 'reason', 'recognition_mismatch',
            'object_id', v_effect.object_id, 'effect_type', v_effect.effect_type, 'objects', v_objects);
          raise exception using errcode = 'WPBC1', message = v_outcome;
        end if;
        v_effect_id := v_f.id;
      else
        insert into private.financial_conflict_effects (stripe_object_id, effect_type, amount_cents, project_id,
          recognized_by_application_id)
        values (v_effect.object_id, v_effect.effect_type, v_effect.amount, v_dec.project_id, v_app_id)
        returning id into v_effect_id;
      end if;
      v_any_new := v_any_new or v_effect.new_ids is not null;
      insert into private.financial_conflict_application_entries (application_id, ledger_entry_id, effect_id, role,
        project_id, stripe_object_id, entry_type, amount_cents, currency, obligation_id, holding_charge_key)
      select v_app_id, l.id, v_effect_id,
             case when l.webhook_event_id is not distinct from v_evt.id then 'new' else 'cited' end,
             l.project_id, l.stripe_object_id, l.entry_type, l.amount_cents, l.currency, l.obligation_id, l.holding_charge_key
        from public.ledger_entries l where l.id = any (v_effect.ids);
    end loop;
    -- All represented: represented. Any new (or no money effect at all): posted.
    v_outcome := case when v_any_new or not exists (select 1 from private.financial_conflict_application_entries x
                                                     where x.application_id = v_app_id)
                      then 'posted' else 'represented' end;
    v_detail := jsonb_build_object('stage', 'complete', 'objects', v_objects);
    insert into private.financial_conflict_applications (id, decision_id, webhook_event_id, project_id, attempt_no,
      attempt_request_id, category, outcome, fingerprint, detail, reason, requested_by)
    values (v_app_id, v_dec.id, v_evt.id, v_dec.project_id, v_no, p_attempt_request_id, v_category, v_outcome, v_fp,
      v_detail, btrim(p_reason), (select auth.uid()));
  exception
    when sqlstate 'WPBC1' then
      null; -- v_outcome and v_detail survive the rollback of the protected step
    when others then
      -- Transient or unexpected: nothing of the step is kept; only the SQLSTATE and constraint
      -- are recorded (no message text, which could carry values).
      get stacked diagnostics v_state = returned_sqlstate, v_constraint = constraint_name;
      v_outcome := 'operational_failure';
      v_detail := jsonb_build_object('stage', 'operational', 'sqlstate', v_state, 'constraint', nullif(v_constraint, ''));
  end;
  if v_outcome not in ('posted', 'represented') then
    v_app_id := gen_random_uuid();
    insert into private.financial_conflict_applications (id, decision_id, webhook_event_id, project_id, attempt_no,
      attempt_request_id, category, outcome, terminal_reason, fingerprint, detail, reason, requested_by)
    values (v_app_id, v_dec.id, v_evt.id, v_dec.project_id, v_no, p_attempt_request_id, v_category, v_outcome,
      case when v_no = 10 then 'exhausted' end, v_fp, v_detail, btrim(p_reason), (select auth.uid()));
  end if;
  select * into v_app from private.financial_conflict_applications where id = v_app_id;
  perform private.audit_financial('financial_conflict.attempt_recorded', 'webhook_event', v_evt.id::text, v_dec.project_id,
    jsonb_build_object('decision_id', v_dec.id, 'application_id', v_app.id, 'attempt_request_id', p_attempt_request_id,
      'attempt_no', v_app.attempt_no, 'outcome', v_app.outcome, 'terminal_reason', v_app.terminal_reason,
      'category', v_app.category), btrim(p_reason));
  return jsonb_build_object('ok', true, 'existing', false, 'attempt', private.financial_conflict_attempt_summary(v_app));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Reads: attempt status and the conflict list
-- ---------------------------------------------------------------------------
-- Read-only. 'recorded' is conclusive. 'in_progress' (an attempt under this id holds its lock)
-- and 'not_recorded' are not: a missing record alone does not establish a rollback, and the
-- same attempt_request_id stays idempotent.
create function private.financial_conflict_attempt_status(p_attempt_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_app private.financial_conflict_applications%rowtype;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if p_attempt_request_id is null then
    return private.fail('attempt_request_id_required');
  end if;
  if not pg_try_advisory_xact_lock_shared(hashtextextended('wpb:oi93:attempt:' || p_attempt_request_id::text, 0)) then
    return jsonb_build_object('ok', true, 'status', 'in_progress', 'conclusive', false);
  end if;
  select * into v_app from private.financial_conflict_applications where attempt_request_id = p_attempt_request_id;
  if not found then
    return jsonb_build_object('ok', true, 'status', 'not_recorded', 'conclusive', false);
  end if;
  return jsonb_build_object('ok', true, 'status', 'recorded', 'conclusive', true,
    'attempt', private.financial_conflict_attempt_summary(v_app));
end;
$$;

-- Every event with recorded conflict candidates, for the Owner's conflict screen.
create function private.financial_conflict_events() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  return jsonb_build_object('ok', true, 'events', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'webhook_event_id', w.id, 'stripe_event_id', w.stripe_event_id, 'event_type', w.event_type,
      'object_id', w.object_id, 'stripe_created_at', w.stripe_created_at, 'received_at', w.received_at,
      'processing_status', w.processing_status, 'quarantine_reason', w.quarantine_reason,
      'quarantine_resolved_at', w.quarantine_resolved_at,
      'candidates', (select coalesce(jsonb_agg(jsonb_build_object('project_id', c.project_id, 'project_name', p.name,
                        'sources', c.sources, 'classification',
                        (private.financial_conflict_classify(w, c.project_id) - 'objects'))
                        order by c.project_id), '[]'::jsonb)
                       from (select x.project_id, jsonb_agg(x.source order by x.source) as sources
                               from private.financial_event_project_candidates x where x.webhook_event_id = w.id
                              group by x.project_id) c
                       join public.projects p on p.id = c.project_id),
      'decision', (select jsonb_build_object('id', d.id, 'project_id', d.project_id, 'evidence', d.evidence,
                      'reason', d.reason, 'decided_at', d.decided_at)
                     from private.financial_conflict_decisions d where d.webhook_event_id = w.id),
      'attempts', (select coalesce(jsonb_agg(jsonb_build_object('attempt_no', a.attempt_no,
                      'attempt_request_id', a.attempt_request_id, 'outcome', a.outcome, 'terminal_reason', a.terminal_reason,
                      'category', a.category, 'created_at', a.created_at) order by a.attempt_no), '[]'::jsonb)
                     from private.financial_conflict_applications a where a.webhook_event_id = w.id),
      'retry_after', (select max(a.created_at) + interval '60 seconds' from private.financial_conflict_applications a
                       where a.webhook_event_id = w.id),
      'cleared', private.financial_conflict_cleared(w.id))
      order by w.id), '[]'::jsonb)
      from public.webhook_events w
     where exists (select 1 from private.financial_event_project_candidates c where c.webhook_event_id = w.id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. project_financial_anomalies: items 1 and 7 exclude a cleared event (from 20261127120000)
-- ---------------------------------------------------------------------------
create or replace function private.project_financial_anomalies(p_project_id uuid) returns table (kind text, gates text[])
language sql stable security definer set search_path = '' as $$
  -- 1. Quarantined events, attributed through the charge they concern.
  select 'quarantined_event', private.charge_kind_gates(private.event_charge_kinds(w))
    from public.webhook_events w
   where w.project_id = p_project_id and w.processing_status = 'quarantined' and w.quarantine_resolved_at is null
     -- AUTH-010: an event applied through a re-verified Owner conflict application is cleared.
     and not private.financial_conflict_cleared(w.id)
  union all
  -- 2. Open reconciliation items.
  select 'reconciliation_mismatch', case
           when m.kind = 'deposit_snapshot' then array['G2']
           when m.kind in ('balance_snapshot', 'charged_after_halt') then array['G4']
           when m.kind in ('unmatched_refund', 'unmatched_dispute') then private.charge_key_gates(m.charge_key)
           else array['G2', 'G4'] end
    from public.reconciliation_mismatches m
   where m.project_id = p_project_id and m.resolved_at is null
  union all
  -- 3. Ambiguous outbound requests, by the charge their record belongs to.
  select 'ambiguous_request', case
           when o.purpose = 'checkout_session_create' then array['G2']
           when o.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto', 'recovery_session_create')
             then array['G4']
           else array['G2', 'G4'] end
    from public.outbound_stripe_requests o
   where o.project_id = p_project_id and o.status = 'ambiguous'
  union all
  -- 4. A failed automatic-collection stop; already_paid alone is not an anomaly.
  select 'automatic_stop_failed', array['G4']
    from public.outbound_stripe_requests o
   where o.project_id = p_project_id and o.purpose = 'final_balance_invoice_disable_auto' and o.status = 'failed'
     and coalesce(o.error_code, '') <> 'already_paid'
  union all
  -- 5. A charge after halted collection that the Owner has not reviewed (its item resolved).
  select 'charged_after_halt', array['G4']
    from public.final_balance_invoices f
   where f.project_id = p_project_id and f.charged_after_halt
     and not exists (select 1 from public.reconciliation_mismatches m where m.kind = 'charged_after_halt'
                       and m.charge_key = 'final_balance:' || f.id::text and m.resolved_at is not null)
  union all
  -- 6. Reversals Stripe reports that the ledger has not posted.
  select 'unposted_reversal', u.gates from private.unposted_reversals(p_project_id) u
  union all
  -- 7. N1(a) (Amendment 1): an event with conflicting authoritative projects blocks G2 and G4 for
  -- every candidate project, and for any project the event already carried. The Owner's review
  -- never clears it (OI-93). AUTH-010: only a re-verified posted or represented Owner conflict
  -- application clears it; a decision alone, or a failed or interrupted attempt, never does.
  select 'quarantined_event', array['G2', 'G4']
    from public.webhook_events w
   where exists (select 1 from private.financial_event_project_candidates c where c.webhook_event_id = w.id)
     and (w.project_id = p_project_id
          or exists (select 1 from private.financial_event_project_candidates c
                      where c.webhook_event_id = w.id and c.project_id = p_project_id))
     and not private.financial_conflict_cleared(w.id)
  union all
  -- 8. AUTH-009 (automatic-stop reconciliation): a stop the Owner reconciled as absent did not
  -- establish that automatic collection ceased, so G4 stays blocked, unless verified payment
  -- of that invoice makes further collection impossible. Only this item is cleared by payment.
  select 'automatic_stop_unresolved', array['G4']
    from public.outbound_stripe_requests o
    join public.final_balance_invoices f on f.id = o.domain_record_id
   where o.project_id = p_project_id and o.purpose = 'final_balance_invoice_disable_auto'
     and o.domain_record_type = 'final_balance_invoice' and o.status = 'reconciled_absent' and f.status <> 'paid'
     -- S1 (Owner, 2026-11-26): a later attempt (the Owner's controlled retry) that Stripe confirmed,
     -- or that the Owner reconciled as present, is authoritative evidence of cessation.
     and not exists (select 1 from public.outbound_stripe_requests r
                      where r.domain_record_type = o.domain_record_type and r.domain_record_id = o.domain_record_id
                        and r.purpose = o.purpose and r.attempt > o.attempt
                        and r.status in ('succeeded', 'reconciled_present'));
$$;

-- ---------------------------------------------------------------------------
-- 6. Wrappers and privileges (U-2)
-- ---------------------------------------------------------------------------
-- The wrappers carry the 5-second lock_timeout for the whole call (the private functions they
-- call inherit it); the private functions re-authorize the caller.
create function public.record_financial_conflict_decision(p_webhook_event_id bigint, p_project_id uuid, p_evidence jsonb,
  p_reason text) returns jsonb
language sql security invoker set search_path = '' set lock_timeout = '5s' as $$
  select private.record_financial_conflict_decision(p_webhook_event_id, p_project_id, p_evidence, p_reason);
$$;
create function public.retry_financial_conflict_application(p_decision_id uuid, p_attempt_request_id uuid, p_reason text)
returns jsonb
language sql security invoker set search_path = '' set lock_timeout = '5s' as $$
  select private.retry_financial_conflict_application(p_decision_id, p_attempt_request_id, p_reason);
$$;
create function public.financial_conflict_attempt_status(p_attempt_request_id uuid) returns jsonb
language sql security invoker set search_path = '' set lock_timeout = '5s' as $$
  select private.financial_conflict_attempt_status(p_attempt_request_id);
$$;
create function public.financial_conflict_events() returns jsonb
language sql security invoker set search_path = '' set lock_timeout = '5s' as $$
  select private.financial_conflict_events();
$$;

revoke all on function
  private.financial_conflict_effect_type(public.ledger_entry_type, bigint),
  private.financial_conflict_application_verified(uuid),
  private.financial_conflict_cleared(bigint),
  private.financial_conflict_attempt_summary(private.financial_conflict_applications)
from public, anon, authenticated, service_role;
-- Owner-only: granted to authenticated (each re-authorizes the caller inside), as
-- retry_final_balance_stop; never anon, PUBLIC or the server role.
revoke all on function
  private.record_financial_conflict_decision(bigint, uuid, jsonb, text),
  public.record_financial_conflict_decision(bigint, uuid, jsonb, text),
  private.retry_financial_conflict_application(uuid, uuid, text),
  public.retry_financial_conflict_application(uuid, uuid, text),
  private.financial_conflict_attempt_status(uuid),
  public.financial_conflict_attempt_status(uuid),
  private.financial_conflict_events(),
  public.financial_conflict_events()
from public, anon, authenticated, service_role;
grant execute on function
  private.record_financial_conflict_decision(bigint, uuid, jsonb, text),
  public.record_financial_conflict_decision(bigint, uuid, jsonb, text),
  private.retry_financial_conflict_application(uuid, uuid, text),
  public.retry_financial_conflict_application(uuid, uuid, text),
  private.financial_conflict_attempt_status(uuid),
  public.financial_conflict_attempt_status(uuid),
  private.financial_conflict_events(),
  public.financial_conflict_events()
to authenticated;
