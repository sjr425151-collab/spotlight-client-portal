-- WP-C PWP-5b (AUTH-024; OI-110, OI-45; OD-16): inactivity reconciliation. Releases created after
-- this migration follow the revised 05 §7.1 procedure, counted in America/Detroit calendar days
-- from the current released preview (02 §13); releases that exist when it runs keep the
-- implemented day 3/7/14 outreach and day-21 hold unchanged.
--
-- 1. private.inactivity_legacy_releases: the id of every release that exists when this migration
--    runs. Populated here only; no API role can read or write it and no function writes it, so a
--    release can never be moved onto the earlier (day-21) schedule through the API.
-- 2. public.inactivity_milestones: staff-recorded (R1, OI-68; OD-16), insert-only, staff-read
--    milestones for the revised procedure: day 3 courtesy reminder (non-contractual), day 7
--    reminder and Admin notification, day 14 formal notice and preview-estimate suspension, day 30
--    rescheduling decision, day 60 individual review. Recording a milestone has no financial,
--    contractual, approval, publication, forfeiture, cancellation or published-site effect
--    (OI-45; 05 §5). Each is a record only; nothing else reads the rescheduling decision.
-- 3. private.place_approval_hold (create or replace; two hunks): for a revised-schedule release,
--    the day-30 administrative suspension is the existing approval_nonresponsive_hold, eligible
--    at day 30 after the recorded day-14 formal notice, with every 05 §7.2 protection unchanged.
--    The earlier-schedule path is unchanged.
-- 4. private.operational_queue (create or replace; two hunks): revised-schedule items; the
--    earlier-schedule items are unchanged.
--
-- Never touched: approvals, releases, payments, the ledger, subscriptions, published sites,
-- AUTH-021, AUTH-022 and AUTH-023 objects. Contractual consequence wording waits for DEP-03.
-- Every other line of both replaced functions is byte-identical to their last definitions
-- (20261124140200, 20261128110000); create or replace keeps their ACLs. Guards are NULL-safe
-- (OI-120).

-- ---------------------------------------------------------------------------
-- 1. Releases on the earlier schedule
-- ---------------------------------------------------------------------------
create table private.inactivity_legacy_releases (
  release_id uuid primary key references public.preview_releases (id) on delete restrict,
  recorded_at timestamptz not null default now()
);
insert into private.inactivity_legacy_releases (release_id) select r.id from public.preview_releases r;
create trigger inactivity_legacy_releases_insert_only before update or delete on private.inactivity_legacy_releases
  for each row execute function private.wpc_insert_only();
revoke all on table private.inactivity_legacy_releases from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Milestone records
-- ---------------------------------------------------------------------------
create table public.inactivity_milestones (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  milestone text not null check (milestone in ('courtesy_reminder', 'reminder', 'admin_notified', 'formal_notice',
    'estimate_suspension', 'rescheduling_decision', 'individual_review')),
  channel text not null check (channel in ('email', 'phone', 'sms', 'video_call', 'in_person', 'portal', 'other')),
  occurred_on date not null,
  summary text not null check (char_length(btrim(summary)) between 1 and 2000),
  recorded_by uuid not null references public.profiles (id),
  recorded_at timestamptz not null default now(),
  unique (release_id, milestone)
);
create index inactivity_milestones_project_idx on public.inactivity_milestones (project_id);
create trigger inactivity_milestones_insert_only before update or delete on public.inactivity_milestones
  for each row execute function private.wpc_insert_only();

-- ---------------------------------------------------------------------------
-- 3. Helpers (no API role)
-- ---------------------------------------------------------------------------
-- Calendar days in America/Detroit between two instants (02 §13): local dates, never 24-hour periods.
create function private.detroit_days_between(p_from timestamptz, p_to timestamptz) returns integer
language sql stable set search_path = '' as $$
  select ((p_to at time zone 'America/Detroit')::date - (p_from at time zone 'America/Detroit')::date);
$$;
create function private.inactivity_schedule(p_release_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when p_release_id is null then null
    when exists (select 1 from private.inactivity_legacy_releases l where l.release_id = p_release_id) then 'v1_day21'
    else 'v2_7_14_30_60'
  end;
$$;
create function private.inactivity_milestone_day(p_milestone text) returns integer
language sql immutable set search_path = '' as $$
  select case p_milestone
    when 'courtesy_reminder' then 3 when 'reminder' then 7 when 'admin_notified' then 7
    when 'formal_notice' then 14 when 'estimate_suspension' then 14
    when 'rescheduling_decision' then 30 when 'individual_review' then 60
  end;
$$;
create function private.inactivity_milestone_recorded(p_release_id uuid, p_milestone text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.inactivity_milestones m where m.release_id = p_release_id and m.milestone = p_milestone);
$$;

-- ---------------------------------------------------------------------------
-- 4. Recording a milestone: Owner or Admin at aal2 (as record_outreach), the current release on
--    the revised schedule only, not before the milestone's day, and not after a client response
--    (approval or revision request) has stopped the schedule. Takes the release:<project> lock,
--    then the release row FOR UPDATE, so it serializes with approval (same lock), a revision
--    request (its foreign key takes FOR KEY SHARE on the release row) and withdrawal (row lock).
-- ---------------------------------------------------------------------------
create function private.record_inactivity_milestone(
  p_release_id uuid, p_milestone text, p_channel text, p_occurred_on date, p_summary text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
  v_release public.preview_releases;
  v_day integer;
  v_id uuid;
begin
  if private.wpc_is_staff_aal2() is not true then
    return private.fail('forbidden');
  end if;
  v_day := private.inactivity_milestone_day(p_milestone);
  if v_day is null or p_channel is null
     or p_channel not in ('email', 'phone', 'sms', 'video_call', 'in_person', 'portal', 'other') then
    return private.fail('invalid_input');
  end if;
  if private.wpc_text_ok(p_summary, 2000) is not true then
    return private.fail('summary_required');
  end if;
  select r.project_id into v_project from public.preview_releases r where r.id = p_release_id;
  if v_project is null then
    return private.fail('not_found');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || v_project::text, 0));
  select * into v_release from public.preview_releases where id = p_release_id for update;
  if (private.current_release(v_release.project_id)).id is distinct from v_release.id then
    return private.fail('not_current_release');
  end if;
  if private.inactivity_schedule(v_release.id) is distinct from 'v2_7_14_30_60' then
    return private.fail('earlier_schedule');
  end if;
  if exists (select 1 from public.preview_approvals a where a.release_id = v_release.id)
     or exists (select 1 from public.preview_revision_requests q where q.release_id = v_release.id) then
    return private.fail('schedule_stopped');
  end if;
  if private.detroit_days_since(v_release.released_at) < v_day then
    return private.fail('too_early');
  end if;
  if p_occurred_on is null or p_occurred_on < (v_release.released_at at time zone 'America/Detroit')::date + v_day
     or p_occurred_on > (now() at time zone 'America/Detroit')::date then
    return private.fail('invalid_date');
  end if;
  if p_milestone in ('estimate_suspension', 'rescheduling_decision')
     and not private.inactivity_milestone_recorded(v_release.id, 'formal_notice') then
    return private.fail('formal_notice_required');
  end if;
  if private.inactivity_milestone_recorded(v_release.id, p_milestone) then
    return private.fail('already_recorded');
  end if;
  insert into public.inactivity_milestones (project_id, release_id, milestone, channel, occurred_on, summary, recorded_by)
  values (v_release.project_id, v_release.id, p_milestone, p_channel, p_occurred_on, btrim(p_summary), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('inactivity.' || p_milestone || '_recorded', 'inactivity_milestones', v_id::text,
    v_release.project_id, null,
    jsonb_build_object('release_id', v_release.id, 'channel', p_channel, 'occurred_on', p_occurred_on, 'day', v_day));
  return jsonb_build_object('ok', true, 'milestone_id', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. The day-30 administrative suspension (05 §7.2): two hunks, see the header.
-- ---------------------------------------------------------------------------
create or replace function private.place_approval_hold(p_project_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_evidence uuid[];
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  if not private.wpc_text_ok(p_reason, 1000) then
    return private.fail('reason_required');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || p_project_id::text, 0));
  v_release := private.current_release(p_project_id);
  if v_release.id is null then
    return private.fail('no_current_release');
  end if;
  if exists (select 1 from public.preview_approvals where release_id = v_release.id) then
    return private.fail('release_approved');
  end if;
  if private.inactivity_schedule(v_release.id) = 'v1_day21' then
  if private.detroit_days_since(v_release.released_at) < 21 then
    return private.fail('too_early');
  end if;
  if not exists (select 1 from public.approval_outreach_records
                  where release_id = v_release.id and kind = 'personal_followup') then
    return private.fail('outreach_required');
  end if;
  else
    -- AUTH-024 (05 §7.1, §7.2; OI-110): day 30, following the recorded day-14 formal notice.
    if private.detroit_days_since(v_release.released_at) < 30 then
      return private.fail('too_early');
    end if;
    if not private.inactivity_milestone_recorded(v_release.id, 'formal_notice') then
      return private.fail('formal_notice_required');
    end if;
  end if;
  if exists (select 1 from public.approval_holds where project_id = p_project_id and cleared_at is null) then
    return private.fail('hold_active');
  end if;
  if private.inactivity_schedule(v_release.id) = 'v1_day21' then
  select array_agg(o.id order by o.occurred_on, o.id) into v_evidence
    from public.approval_outreach_records o where o.release_id = v_release.id;
  else
    select array_agg(m.id order by m.occurred_on, m.id) into v_evidence
      from public.inactivity_milestones m where m.release_id = v_release.id;
  end if;
  insert into public.approval_holds (project_id, release_id, placed_by, reason, outreach_evidence_ids)
  values (p_project_id, v_release.id, (select auth.uid()), btrim(p_reason), v_evidence)
  returning id into v_id;
  perform private.record_audit_event('approval_hold.placed', 'approval_holds', v_id::text, p_project_id, btrim(p_reason),
    jsonb_build_object('release_id', v_release.id, 'outreach_evidence_ids', to_jsonb(v_evidence),
      'actor_role', private.staff_role_of((select auth.uid()))));
  perform private.enqueue_notification('approval_hold.placed', 'approval_hold.placed:' || v_id || ':1',
    'approval_hold_placed', 1, p_project_id, null, '{}',
    array['client', 'owner', 'admin']::public.notification_recipient_role[], jsonb_build_object('hold_id', v_id));
  return jsonb_build_object('ok', true, 'hold_id', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. The queue (05 §9): two hunks, see the header.
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
begin
  if not private.wpc_is_staff_aal2() then
    return;
  end if;
  v_owner := private.is_owner();
  for p in select pr.id, pr.name from public.projects pr where pr.archived_at is null order by pr.created_at loop
    v_state := private.intake_state_of(p.id);
    v_release := private.current_release(p.id);
    v_approved := v_release.id is not null and exists (select 1 from public.preview_approvals a where a.release_id = v_release.id);
    v_days := case when v_release.id is not null then private.detroit_days_since(v_release.released_at) end;
    begin
      v_fin := to_jsonb(private.project_financial_status(p.id));
    exception when others then v_fin := null;
    end;
    v_fin_ok := coalesce((v_fin is not null and v_fin -> 'implemented' = 'true'::jsonb), false);

    -- Payment-derived queues, as requirement satisfied / unsatisfied only (OI-72).
    if v_fin_ok and v_fin ->> 'agreement_state' in ('accepted_pending_payment', 'effective')
       and v_fin -> 'deposit_verified' is distinct from 'true'::jsonb then
      return next jsonb_build_object('queue', 'awaiting_deposit', 'project_id', p.id, 'project_name', p.name,
        'detail', jsonb_build_object('deposit_requirement', 'unsatisfied'));
    end if;
    if v_state in ('open', 'changes_requested') and private.wpc_intake_unlocked(p.id) then
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
      v_gates := private.evaluate_publication_gates(p.id, v_release.id);
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

-- ---------------------------------------------------------------------------
-- 7. Wrapper, privileges and Row Level Security
-- ---------------------------------------------------------------------------
create function public.record_inactivity_milestone(p_release_id uuid, p_milestone text, p_channel text,
  p_occurred_on date, p_summary text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_inactivity_milestone(p_release_id, p_milestone, p_channel, p_occurred_on, p_summary);
$$;

revoke all on function
  private.detroit_days_between(timestamptz, timestamptz),
  private.inactivity_schedule(uuid),
  private.inactivity_milestone_day(text),
  private.inactivity_milestone_recorded(uuid, text)
from public, anon, authenticated, service_role;
revoke all on function
  private.record_inactivity_milestone(uuid, text, text, date, text),
  public.record_inactivity_milestone(uuid, text, text, date, text)
from public, anon, authenticated, service_role;
grant execute on function
  private.record_inactivity_milestone(uuid, text, text, date, text),
  public.record_inactivity_milestone(uuid, text, text, date, text)
to authenticated;

revoke all on table public.inactivity_milestones from public, anon, authenticated, service_role;
grant select on table public.inactivity_milestones to authenticated;
alter table public.inactivity_milestones enable row level security;
create policy inactivity_milestones_select on public.inactivity_milestones for select to authenticated
  using ((select private.is_staff()));
create policy inactivity_milestones_staff_aal2 on public.inactivity_milestones as restrictive for all to authenticated
  using (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))
  with check (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())));
create policy inactivity_milestones_active_user on public.inactivity_milestones as restrictive for all to authenticated
  using ((select private.is_active_user())) with check ((select private.is_active_user()));
