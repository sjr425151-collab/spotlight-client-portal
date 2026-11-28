-- WP-C AUTH-026 (OI-131), PR 2: the staff operational queue evaluates every project's financial
-- status once per call, through WP-B's set-based private.financial_evaluation_for_projects
-- (PR 1, 20261128140000), instead of about three times per project.
--
-- 1. New private variants that take the caller's precomputed financial status (p_fin, the
--    exact to_jsonb(private.project_financial_status(p)), or null with p_fin_failed where that
--    evaluation raised): wpc_intake_unlocked_from, intake_state_from and
--    evaluate_publication_gates_from. Each is the existing helper's body with only its own
--    financial-status evaluation replaced by the parameter, preserving its exception path. The
--    existing helpers (wpc_intake_unlocked, intake_state_of, evaluate_publication_gates) keep
--    their signatures, bodies and callers.
-- 2. private.operational_queue (create or replace): one set-based evaluation per call, then
--    the variants above. Every other line is byte-identical to 20261128130000; the output is
--    the same item for item and in order. Still STABLE, SECURITY DEFINER, empty search_path,
--    no lock; create or replace keeps its grants.
--
-- No API role executes the new helpers. No financial function, calculation, authorization,
-- visibility (OI-72), role, RLS or timeout changes.

-- ---------------------------------------------------------------------------
-- 1. Parameterized variants (no API role)
-- ---------------------------------------------------------------------------
create function private.wpc_intake_unlocked_from(p_project_id uuid, p_fin jsonb) returns boolean
language sql stable security definer set search_path = '' as $$
  -- p_fin: to_jsonb(private.project_financial_status(p_project_id)) evaluated by the caller, or
  -- null where that evaluation raised (the original's exception path returns false).
  select coalesce(p_fin ->> 'project_id' = p_project_id::text
     and p_fin -> 'implemented' = 'true'::jsonb
     and p_fin -> 'deposit_verified' = 'true'::jsonb
     and p_fin -> 'payment_authorization_ready' = 'true'::jsonb, false);
$$;
create function private.intake_state_from(p_project_id uuid, p_fin jsonb) returns public.intake_state
language plpgsql stable security definer set search_path = '' as $$
declare
  v_latest uuid;
  v_decision text;
begin
  select s.id into v_latest from public.intake_submissions s
   where s.project_id = p_project_id and s.status = 'submitted'
   order by s.version desc limit 1;
  if v_latest is null then
    return case when private.wpc_intake_unlocked_from(p_project_id, p_fin)
                then 'open'::public.intake_state else 'locked'::public.intake_state end;
  end if;
  select r.decision into v_decision from public.intake_reviews r where r.submission_id = v_latest;
  return case v_decision
    when 'accepted' then 'accepted_by_staff'::public.intake_state
    when 'changes_requested' then 'changes_requested'::public.intake_state
    else 'submitted'::public.intake_state end;
end;
$$;
create function private.evaluate_publication_gates_from(p_project_id uuid, p_release_id uuid, p_fin jsonb,
  p_fin_failed boolean) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fin jsonb;
  v_ful jsonb;
  v_fin_ok boolean;
  v_ful_ok boolean;
  v_fin_error text;
  v_ful_error text;
  v_min record;
  v_gates jsonb := '[]'::jsonb;
  v_pass boolean;
  v_all boolean := true;
  v_billing jsonb;
  v_fulfillment jsonb;
begin
  select * into v_min from private.gate_contract_minimums();
  if p_fin_failed then
    v_fin := null; v_fin_error := 'unavailable';
  else
    v_fin := p_fin;
  end if;
  begin
    v_ful := to_jsonb(private.project_fulfillment_status(p_project_id));
  exception when others then
    v_ful := null; v_ful_error := 'unavailable';
  end;

  v_fin_ok := coalesce((v_fin is not null and v_fin ->> 'project_id' = p_project_id::text
    and v_fin -> 'implemented' = 'true'::jsonb
    and case when jsonb_typeof(v_fin -> 'contract_version') = 'number'
             then (v_fin ->> 'contract_version')::numeric >= v_min.financial else false end), false);
  v_ful_ok := coalesce((v_ful is not null and v_ful ->> 'project_id' = p_project_id::text
    and v_ful -> 'implemented' = 'true'::jsonb
    and case when jsonb_typeof(v_ful -> 'contract_version') = 'number'
             then (v_ful ->> 'contract_version')::numeric >= v_min.fulfillment else false end), false);
  v_fin_error := coalesce(v_fin_error, case when not v_fin_ok then 'financial_interface_not_ready' end);
  v_ful_error := coalesce(v_ful_error, case when not v_ful_ok then 'fulfillment_interface_not_ready' end);

  -- G1 valid agreement (WP-B attribute agreement_effective, OI-71 item 1).
  v_pass := coalesce((v_fin_ok and v_fin -> 'agreement_effective' = 'true'::jsonb), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G1', 'passed', v_pass, 'source', 'financial',
    'reason', case when v_pass then null when not v_fin_ok then v_fin_error
                   when not v_fin ? 'agreement_effective' then 'agreement_interface_missing'
                   else 'agreement_not_effective' end);
  v_all := v_all and v_pass;

  -- G2 verified deposit.
  v_pass := coalesce((v_fin_ok and v_fin -> 'deposit_verified' = 'true'::jsonb), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G2', 'passed', v_pass, 'source', 'financial',
    'reason', case when v_pass then null when not v_fin_ok then v_fin_error else 'deposit_not_verified' end);
  v_all := v_all and v_pass;

  -- G3 approval of the current release, and that release is the one being published.
  v_pass := coalesce((v_ful_ok and p_release_id is not null
    and v_ful ->> 'current_release_id' = p_release_id::text
    and v_ful -> 'current_release_approved' = 'true'::jsonb
    and jsonb_typeof(v_ful -> 'current_release_approval_id') = 'string'), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G3', 'passed', v_pass, 'source', 'fulfillment',
    'reason', case when v_pass then null when not v_ful_ok then v_ful_error
                   when v_ful ->> 'current_release_id' is distinct from p_release_id::text then 'not_current_release'
                   else 'release_not_approved' end,
    'evidence', jsonb_build_object('release_id', p_release_id, 'approval_id', v_ful -> 'current_release_approval_id'));
  v_all := v_all and v_pass;

  -- G4 verified final balance, disclosing any adjustment.
  v_pass := coalesce((v_fin_ok and v_fin -> 'balance_verified_or_settled' = 'true'::jsonb
    and jsonb_typeof(v_fin -> 'balance_settled_by_adjustment') = 'boolean'), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G4', 'passed', v_pass, 'source', 'financial',
    'reason', case when v_pass then null when not v_fin_ok then v_fin_error else 'balance_not_verified' end,
    'settled_by_adjustment', case when v_pass then v_fin -> 'balance_settled_by_adjustment' end);
  v_all := v_all and v_pass;

  -- G5 QA passed for this release.
  v_pass := coalesce((v_ful_ok and v_ful -> 'qa_passed' = 'true'::jsonb
    and v_ful -> 'evidence' ->> 'qa_release_id' = p_release_id::text), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G5', 'passed', v_pass, 'source', 'fulfillment',
    'reason', case when v_pass then null when not v_ful_ok then v_ful_error
                   when v_ful -> 'evidence' ->> 'qa_release_id' is distinct from p_release_id::text then 'no_qa_for_release'
                   else 'qa_failed' end,
    'evidence', jsonb_build_object('qa_result_id', v_ful -> 'evidence' -> 'qa_result_id'));
  v_all := v_all and v_pass;

  -- G6 domain readiness within the freshness window (re-checked here: stale evidence fails).
  v_pass := coalesce((v_ful_ok and v_ful -> 'domain_ready' = 'true'::jsonb
    and case when jsonb_typeof(v_ful -> 'domain_checked_at') = 'string'
             then (v_ful ->> 'domain_checked_at')::timestamptz > now() - private.domain_freshness_window() else false end), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G6', 'passed', v_pass, 'source', 'fulfillment',
    'reason', case when v_pass then null when not v_ful_ok then v_ful_error
                   when jsonb_typeof(v_ful -> 'domain_check_id') <> 'string' then 'no_domain_check'
                   when (v_ful ->> 'domain_checked_at')::timestamptz <= now() - private.domain_freshness_window() then 'domain_check_stale'
                   else 'domain_not_ready' end,
    'evidence', jsonb_build_object('domain_check_id', v_ful -> 'domain_check_id', 'checked_at', v_ful -> 'domain_checked_at'));
  v_all := v_all and v_pass;

  -- G7 security checks passed for this release.
  v_pass := coalesce((v_ful_ok and v_ful -> 'security_passed' = 'true'::jsonb
    and v_ful -> 'evidence' ->> 'security_release_id' = p_release_id::text), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G7', 'passed', v_pass, 'source', 'fulfillment',
    'reason', case when v_pass then null when not v_ful_ok then v_ful_error
                   when v_ful -> 'evidence' ->> 'security_release_id' is distinct from p_release_id::text then 'no_security_for_release'
                   else 'security_failed' end,
    'evidence', jsonb_build_object('security_result_id', v_ful -> 'evidence' -> 'security_result_id'));
  v_all := v_all and v_pass;

  -- G8 holds cleared: the union of both hold lists, fail closed (OI-71 item 3).
  v_billing := case when v_fin_ok and jsonb_typeof(v_fin -> 'active_billing_holds') = 'array'
                    then v_fin -> 'active_billing_holds' end;
  v_fulfillment := case when v_ful_ok and jsonb_typeof(v_ful -> 'active_fulfillment_holds') = 'array'
                        then v_ful -> 'active_fulfillment_holds' end;
  v_pass := coalesce((v_billing is not null and v_fulfillment is not null
    and jsonb_array_length(v_billing) = 0 and jsonb_array_length(v_fulfillment) = 0), false);
  v_gates := v_gates || jsonb_build_object('gate', 'G8', 'passed', v_pass, 'source', 'both',
    'reason', case when v_pass then null
                   when v_billing is null then coalesce(v_fin_error, 'billing_holds_unavailable')
                   when v_fulfillment is null then coalesce(v_ful_error, 'fulfillment_holds_unavailable')
                   else 'active_hold' end,
    'billing_holds', coalesce(v_billing, 'null'::jsonb),
    'fulfillment_holds', coalesce(v_fulfillment, 'null'::jsonb));
  v_all := v_all and v_pass;

  return jsonb_build_object(
    'project_id', p_project_id, 'release_id', p_release_id, 'eligible', coalesce(v_all, false),
    'evaluated_at', now(),
    'contracts', jsonb_build_object('financial', v_fin -> 'contract_version', 'fulfillment', v_ful -> 'contract_version'),
    'gates', v_gates);
exception
  -- Anything unexpected (for example a malformed attribute) fails every gate.
  when others then
    return jsonb_build_object(
      'project_id', p_project_id, 'release_id', p_release_id, 'eligible', false, 'evaluated_at', now(),
      'error', 'evaluation_failed',
      'gates', (select jsonb_agg(jsonb_build_object('gate', g, 'passed', false, 'reason', 'evaluation_failed') order by g)
                from unnest(array['G1', 'G2', 'G3', 'G4', 'G5', 'G6', 'G7', 'G8']) g));
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The queue: one financial evaluation per call
-- ---------------------------------------------------------------------------
create or replace function private.operational_queue() returns setof jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_owner boolean;
  p record;
  v_release public.preview_releases;
  v_days integer;
  v_approved boolean;
  v_state public.intake_state;
  v_fin jsonb;
  v_fin_ok boolean;
  v_gates jsonb;
  v_hold public.approval_holds;
  v_resp record;
  item jsonb;
  v_eval jsonb;
  v_fin_failed boolean;
begin
  if not private.wpc_is_staff_aal2() then
    return;
  end if;
  v_owner := private.is_owner();
  -- AUTH-026 (OI-131): one set-based financial evaluation per call (WP-B), never per project.
  select coalesce(jsonb_object_agg(e.project_id::text,
           jsonb_build_object('status', case when e.failed then null else to_jsonb(e.status) end, 'failed', e.failed)),
         '{}'::jsonb)
    into v_eval
    from private.financial_evaluation_for_projects(
           array(select pr.id from public.projects pr where pr.archived_at is null)) e;
  for p in select pr.id, pr.name from public.projects pr where pr.archived_at is null order by pr.created_at loop
    v_fin_failed := coalesce((v_eval -> p.id::text ->> 'failed')::boolean, true);
    v_fin := case when v_fin_failed then null else v_eval -> p.id::text -> 'status' end;
    v_state := private.intake_state_from(p.id, v_fin);
    v_release := private.current_release(p.id);
    v_approved := v_release.id is not null and exists (select 1 from public.preview_approvals a where a.release_id = v_release.id);
    v_days := case when v_release.id is not null then private.detroit_days_since(v_release.released_at) end;
    v_fin_ok := coalesce((v_fin is not null and v_fin -> 'implemented' = 'true'::jsonb), false);

    -- Payment-derived queues, as requirement satisfied / unsatisfied only (OI-72).
    if v_fin_ok and v_fin ->> 'agreement_state' in ('accepted_pending_payment', 'effective')
       and v_fin -> 'deposit_verified' is distinct from 'true'::jsonb then
      return next jsonb_build_object('queue', 'awaiting_deposit', 'project_id', p.id, 'project_name', p.name,
        'detail', jsonb_build_object('deposit_requirement', 'unsatisfied'));
    end if;
    if v_state in ('open', 'changes_requested') and private.wpc_intake_unlocked_from(p.id, v_fin) then
      return next jsonb_build_object('queue', 'intake_pending', 'project_id', p.id, 'project_name', p.name,
        'detail', jsonb_build_object('intake_state', v_state));
    end if;
    if v_state = 'submitted' then
      return next jsonb_build_object('queue', 'intake_review', 'project_id', p.id, 'project_name', p.name,
        'subject_id', (select s.id from public.intake_submissions s where s.project_id = p.id and s.status = 'submitted'
                        order by s.version desc limit 1));
    end if;
    if v_state = 'accepted_by_staff' and v_release.id is null then
      return next jsonb_build_object('queue', 'in_development', 'project_id', p.id, 'project_name', p.name);
    end if;
    -- AUTH-023 (05 §3A): an unacknowledged current scope confirmation awaits the authorized signer.
    if private.scope_confirmation_state(p.id) = 'unacknowledged' then
      return next jsonb_build_object('queue', 'awaiting_scope_acknowledgment', 'project_id', p.id, 'project_name', p.name,
        'subject_id', (private.current_scope_confirmation(p.id)).id,
        'detail', jsonb_build_object('version', (private.current_scope_confirmation(p.id)).version));
    end if;

    if v_release.id is not null and not v_approved then
      return next jsonb_build_object('queue', 'awaiting_client_approval', 'project_id', p.id, 'project_name', p.name,
        'subject_id', v_release.id, 'detail', jsonb_build_object('release_number', v_release.release_number, 'day', v_days));
      -- AUTH-024 (05 §7.1, §9; OI-110, OD-16): a release created after 20261128130000 follows the
      -- 3/7/14/30/60 procedure. Staff perform and record every milestone (R1, OI-68); none has a
      -- financial, contractual, approval or publication effect. A client response stops it.
      if private.inactivity_schedule(v_release.id) = 'v2_7_14_30_60'
         and not exists (select 1 from public.preview_revision_requests q where q.release_id = v_release.id) then
        if v_days >= 3 and not private.inactivity_milestone_recorded(v_release.id, 'courtesy_reminder') then
          return next jsonb_build_object('queue', 'approval_outreach_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('outreach', 'courtesy_reminder', 'due_day', 3,
              'day', v_days, 'schedule', 'v2'),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 3);
        end if;
        if v_days >= 7 and not private.inactivity_milestone_recorded(v_release.id, 'reminder') then
          return next jsonb_build_object('queue', 'approval_outreach_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('outreach', 'reminder', 'due_day', 7,
              'day', v_days, 'schedule', 'v2'),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 7);
        end if;
        if v_days >= 7 and not private.inactivity_milestone_recorded(v_release.id, 'admin_notified') then
          return next jsonb_build_object('queue', 'approval_outreach_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('outreach', 'admin_notified', 'due_day', 7,
              'day', v_days, 'schedule', 'v2'),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 7);
        end if;
        if v_days >= 14 and (not private.inactivity_milestone_recorded(v_release.id, 'formal_notice')
                             or not private.inactivity_milestone_recorded(v_release.id, 'estimate_suspension')) then
          return next jsonb_build_object('queue', 'inactivity_formal_notice_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('day', v_days,
              'formal_notice', private.inactivity_milestone_recorded(v_release.id, 'formal_notice'),
              'estimate_suspension', private.inactivity_milestone_recorded(v_release.id, 'estimate_suspension')),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 14);
        end if;
        if v_days >= 30 and private.inactivity_milestone_recorded(v_release.id, 'formal_notice')
           and not exists (select 1 from public.approval_holds h where h.project_id = p.id and h.cleared_at is null) then
          return next jsonb_build_object('queue', 'inactivity_suspension_eligible', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('day', v_days));
        end if;
        if v_days >= 60 and not private.inactivity_milestone_recorded(v_release.id, 'individual_review') then
          return next jsonb_build_object('queue', 'inactivity_review_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('day', v_days),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 60);
        end if;
      end if;
      -- A client revision request stops the schedule (05 §7.1).
      if not exists (select 1 from public.preview_revision_requests q where q.release_id = v_release.id)
         and private.inactivity_schedule(v_release.id) = 'v1_day21' then
        if v_days >= 3 and not exists (select 1 from public.approval_outreach_records o
                                        where o.release_id = v_release.id and o.kind = 'reminder_1') then
          return next jsonb_build_object('queue', 'approval_outreach_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('outreach', 'reminder_1', 'due_day', 3, 'day', v_days),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 3);
        end if;
        if v_days >= 7 and not exists (select 1 from public.approval_outreach_records o
                                        where o.release_id = v_release.id and o.kind = 'reminder_2') then
          return next jsonb_build_object('queue', 'approval_outreach_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('outreach', 'reminder_2', 'due_day', 7, 'day', v_days),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 7);
        end if;
        if v_days >= 7 and not exists (select 1 from public.approval_outreach_records o
                                        where o.release_id = v_release.id and o.kind = 'admin_notified') then
          return next jsonb_build_object('queue', 'approval_outreach_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('outreach', 'admin_notified', 'due_day', 7, 'day', v_days),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 7);
        end if;
        if v_days >= 14 and not exists (select 1 from public.approval_outreach_records o
                                         where o.release_id = v_release.id and o.kind = 'personal_followup') then
          return next jsonb_build_object('queue', 'approval_followup_due', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('day', v_days),
            'due_on', (v_release.released_at at time zone 'America/Detroit')::date + 14);
        end if;
        if v_days >= 21 and exists (select 1 from public.approval_outreach_records o
                                     where o.release_id = v_release.id and o.kind = 'personal_followup')
           and not exists (select 1 from public.approval_holds h where h.project_id = p.id and h.cleared_at is null) then
          return next jsonb_build_object('queue', 'approval_hold_eligible', 'project_id', p.id, 'project_name', p.name,
            'subject_id', v_release.id, 'detail', jsonb_build_object('day', v_days));
        end if;
      end if;
    end if;

    select * into v_hold from public.approval_holds h where h.project_id = p.id and h.cleared_at is null;
    if v_hold.id is not null then
      select * into v_resp from private.hold_client_response(v_hold);
      if v_resp.response_id is not null and not exists (
           select 1 from public.approval_hold_resumption_decisions d
            where d.hold_id = v_hold.id and d.decided_at >= v_resp.responded_at) then
        return next jsonb_build_object('queue', 'approval_hold_review', 'project_id', p.id, 'project_name', p.name,
          'subject_id', v_hold.id, 'detail', jsonb_build_object('response', v_resp.response_type));
      end if;
    end if;

    if v_approved and v_fin_ok and v_fin -> 'balance_verified_or_settled' is distinct from 'true'::jsonb then
      return next jsonb_build_object('queue', 'awaiting_final_payment', 'project_id', p.id, 'project_name', p.name,
        'detail', jsonb_build_object('final_balance_requirement', 'unsatisfied'));
    end if;

    if v_release.id is not null then
      v_gates := private.evaluate_publication_gates_from(p.id, v_release.id, v_fin, v_fin_failed);
      if coalesce((v_gates ->> 'eligible')::boolean, false)
         and not exists (select 1 from public.publication_authorizations a where a.project_id = p.id
                          and a.release_id = v_release.id and a.invalidated_at is null) then
        return next jsonb_build_object('queue', 'ready_for_publication_review', 'project_id', p.id,
          'project_name', p.name, 'subject_id', v_release.id, 'detail', jsonb_build_object('publication_eligible', true));
      end if;
    end if;

    -- Blocked by hold: fulfillment holds by type; billing holds by type for the Owner only.
    if v_hold.id is not null then
      return next jsonb_build_object('queue', 'blocked_by_hold', 'project_id', p.id, 'project_name', p.name,
        'detail', jsonb_build_object('hold', 'approval_nonresponsive_hold', 'kind', 'fulfillment'));
    end if;
    if v_fin_ok and jsonb_typeof(v_fin -> 'active_billing_holds') = 'array'
       and jsonb_array_length(v_fin -> 'active_billing_holds') > 0 then
      return next jsonb_build_object('queue', 'blocked_by_hold', 'project_id', p.id, 'project_name', p.name,
        'detail', case when v_owner
          then jsonb_build_object('holds', v_fin -> 'active_billing_holds', 'kind', 'billing')
          else jsonb_build_object('hold', 'billing_related_operational_hold', 'kind', 'billing',
                                  'owner_intervention_required', true) end);
    end if;

    for item in
      select jsonb_build_object('queue', 'publication_verification_failed', 'project_id', p.id, 'project_name', p.name,
        'subject_id', i.id, 'detail', jsonb_build_object('kind', i.kind, 'severity', i.severity, 'opened_at', i.opened_at))
      from public.publication_incidents i where i.project_id = p.id and i.resolved_at is null
    loop
      return next item;
    end loop;

    for item in
      select jsonb_build_object('queue', 'upload_review', 'project_id', p.id, 'project_name', p.name,
        'subject_id', u.id, 'detail', jsonb_build_object('status', u.status, 'code', coalesce(u.rejection_code, u.processing_note,
            case when u.scan_failures >= private.scan_max_attempts() then 'scan_retries_exhausted' end),
          'name', u.original_name))
      from public.asset_uploads u
      where u.project_id = p.id
        and ((u.status in ('quarantined', 'scanning', 'processing') and u.created_at < now() - private.upload_review_sla())
             or (u.status = 'quarantined' and u.scan_failures >= private.scan_max_attempts())
             or (u.status = 'processing' and u.processing_note is not null)
             or (u.status = 'rejected' and not exists (
                   select 1 from public.asset_uploads n where n.asset_id = u.asset_id and n.version > u.version)))
      union all
      select jsonb_build_object('queue', 'upload_review', 'project_id', p.id, 'project_name', p.name,
        'subject_id', e.id, 'detail', jsonb_build_object('exception_request', e.kind))
      from public.upload_exceptions e where e.project_id = p.id and e.status = 'requested'
    loop
      return next item;
    end loop;

    for item in
      select jsonb_build_object('queue', 'domain_expiries', 'project_id', p.id, 'project_name', p.name,
        'subject_id', d.id, 'due_on', d.registrar_expiry, 'detail', jsonb_build_object('domain', d.domain))
      from (select distinct on (c.domain) c.* from public.domain_readiness_checks c
             where c.project_id = p.id order by c.domain, c.seq desc) d
      where d.spotlight_registered
        and d.registrar_expiry <= (now() at time zone 'America/Detroit')::date + private.domain_expiry_horizon()
    loop
      return next item;
    end loop;
  end loop;
end;
$$;

revoke all on function
  private.wpc_intake_unlocked_from(uuid, jsonb),
  private.intake_state_from(uuid, jsonb),
  private.evaluate_publication_gates_from(uuid, uuid, jsonb, boolean)
from public, anon, authenticated, service_role;
