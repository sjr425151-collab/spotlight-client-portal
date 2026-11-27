-- WP-C (AUTH-015, OI-114): controlled recovery after a failed deployment or a failed live
-- verification (06 §8.1, "Publication failure after successful payment"; Owner decisions D1 to D4).
--
-- 0. private.wpc_publication_recovered (new helper, no API role): whether a deployment has been
--    recovered, i.e. has its append-only publication.recovery_opened audit event (option B, M-1).
-- 1. private.reopen_failed_publication (new; Owner, aal2, live session, fresh MFA, a reason):
--    for the project's LATEST deployment of its CURRENT release, when that deployment failed or
--    its latest live verification failed, it closes the deployment's publication authorization
--    (the single permitted invalidation, reason failed_publication_recovery) and audits the
--    recovery. An authorization a gate failure already closed (gates_failed, gates_failed_at_start)
--    keeps that invalidation, and the recovery is recorded by its audit event alone. It issues
--    nothing, deploys nothing and evaluates no gate: the Owner then runs the normal
--    authorize_publication (G1 to G8, including G2 and G4) and start_deployment, which re-evaluates
--    every gate; the new deployment needs its own live verification (D3, two steps).
-- 2. private.authorize_publication: one hunk. When the project's latest deployment is of this
--    release and has not been recovered, the release is refused (recovery_required) instead of
--    being silently superseded or re-issued (D1, M-1). A different release still supersedes as
--    before. A release whose latest verification passed cannot be recovered, so it cannot be
--    redeployed (D4).
-- 3. private.record_live_verification: one hunk. The deployment row is read FOR SHARE, and a
--    deployment whose authorization was closed by a recovery is refused (deployment_closed), so a
--    late verification never counts after a recovery.
-- Every other line of both replaced functions is byte-identical to 20261124140200; create or
-- replace keeps their ACLs. No table, column, index, policy or trigger change; no DML.

-- 0. Whether a deployment has been recovered (option B, M-1). The durable record is the
--    append-only publication.recovery_opened audit event for that deployment: a recovery of a
--    deployment whose authorization a gate failure already closed cannot close it again (one
--    invalidation per authorization), so the event, not the authorization, is the marker.
create function private.wpc_publication_recovered(p_deployment_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.audit_events e
     where e.action = 'publication.recovery_opened' and e.target_type = 'publication_deployments'
       and e.target_id = p_deployment_id::text
  );
$$;
revoke all on function private.wpc_publication_recovered(uuid) from public, anon, authenticated, service_role;

-- 1. Recovery
create function private.reopen_failed_publication(p_deployment_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
  v_dep public.publication_deployments;
  v_auth public.publication_authorizations;
  v_latest uuid;
  v_current public.preview_releases;
  v_ver public.deployment_verifications;
  v_failure text;
  v_detail text;
  v_incidents jsonb;
begin
  -- NULL-safe (OI-120): private.is_owner() is NULL, not false, for a non-staff caller.
  if (private.is_owner() and private.is_aal2() and private.session_is_active()) is not true then
    return private.fail('forbidden');
  end if;
  select d.project_id into v_project from public.publication_deployments d where d.id = p_deployment_id;
  if private.mfa_is_fresh() is not true then
    perform private.record_audit_event('publication.recovery_rejected', 'publication_deployments', p_deployment_id::text,
      v_project, null, jsonb_build_object('reason', 'reauthentication_required'));
    return private.fail('reauthentication_required');
  end if;
  if private.wpc_text_ok(p_reason, 1000) is not true then
    return private.fail('reason_required');
  end if;
  if v_project is null then
    return private.fail('not_found');
  end if;
  -- WP-C's per-project release lock (release, approve, authorize, start), then the deployment row
  -- (FOR UPDATE, which conflicts with record_live_verification's FOR SHARE), then its authorization.
  perform pg_advisory_xact_lock(hashtextextended('release:' || v_project::text, 0));
  select * into v_dep from public.publication_deployments where id = p_deployment_id for update;
  select * into v_auth from public.publication_authorizations where id = v_dep.authorization_id for update;
  if private.wpc_publication_recovered(v_dep.id) then
    return jsonb_build_object('ok', true, 'existing', true, 'authorization_id', v_auth.id);
  end if;
  -- Fresh statements after the locks.
  select d.id into v_latest from public.publication_deployments d where d.project_id = v_project
   order by d.seq desc limit 1;
  v_current := private.current_release(v_project);
  -- An authorization a gate failure closed (gates_failed, gates_failed_at_start) after a failed
  -- deployment is still recoverable (M-1): otherwise the release could be re-authorized with no
  -- recovery record. Any other closure (superseded, a new or withdrawn release) is not.
  if v_auth.invalidated_at is not null
     and v_auth.invalidated_reason not in ('gates_failed', 'gates_failed_at_start') then
    v_detail := 'authorization_closed';
  elsif v_latest is distinct from v_dep.id then
    v_detail := 'not_latest_deployment';
  elsif v_current.id is distinct from v_dep.release_id then
    v_detail := 'release_not_current';
  elsif v_dep.outcome = 'started' then
    v_detail := 'deployment_in_progress';
  elsif v_dep.outcome = 'failed' then
    v_failure := 'deployment_failed';
  else
    select * into v_ver from public.deployment_verifications x where x.deployment_id = v_dep.id
     order by x.seq desc limit 1;
    if v_ver.id is null then
      v_detail := 'live_unverified';
    elsif v_ver.verified then
      v_detail := 'live_verified';
    else
      v_failure := 'verification_failed';
    end if;
  end if;
  if v_failure is null then
    perform private.record_audit_event('publication.recovery_rejected', 'publication_deployments', v_dep.id::text,
      v_project, null, jsonb_build_object('reason', 'not_recoverable', 'detail', v_detail));
    return jsonb_build_object('ok', false, 'error', 'not_recoverable', 'detail', v_detail);
  end if;
  if v_auth.invalidated_at is null then
    update public.publication_authorizations
       set invalidated_at = now(), invalidated_reason = 'failed_publication_recovery'
     where id = v_auth.id;
    perform private.record_audit_event('publication.authorization_invalidated', 'publication_authorizations',
      v_auth.id::text, v_project, null, jsonb_build_object('reason', 'failed_publication_recovery'));
  end if;
  select coalesce(jsonb_agg(i.id order by i.opened_at, i.id), '[]'::jsonb) into v_incidents
    from public.publication_incidents i where i.deployment_id = v_dep.id and i.resolved_at is null;
  perform private.record_audit_event('publication.recovery_opened', 'publication_deployments', v_dep.id::text,
    v_project, btrim(p_reason), jsonb_build_object('authorization_id', v_auth.id, 'release_id', v_dep.release_id,
      'failure', v_failure, 'incident_ids', v_incidents,
      'authorization_closed_by', coalesce(v_auth.invalidated_reason, 'failed_publication_recovery')));
  return jsonb_build_object('ok', true, 'existing', false, 'authorization_id', v_auth.id);
end;
$$;

create function public.reopen_failed_publication(p_deployment_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.reopen_failed_publication(p_deployment_id, p_reason); $$;

-- Owner-only: granted to authenticated (the function re-authorizes the caller), as
-- authorize_publication and resolve_incident; never anon, PUBLIC or the server role.
revoke all on function
  private.reopen_failed_publication(uuid, text), public.reopen_failed_publication(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function
  private.reopen_failed_publication(uuid, text), public.reopen_failed_publication(uuid, text)
to authenticated;

-- 2. Authorization (one hunk)
create or replace function private.authorize_publication(p_project_id uuid, p_release_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_existing public.publication_authorizations;
  v_id uuid;
begin
  if not (private.is_owner() and private.is_aal2() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if not private.mfa_is_fresh() then
    perform private.record_audit_event('publication.authorization_rejected', 'preview_releases', p_release_id::text,
      p_project_id, null, jsonb_build_object('reason', 'reauthentication_required'));
    return private.fail('reauthentication_required');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || p_project_id::text, 0));
  -- Always evaluated, even when an authorization already exists: a pending authorization is
  -- never returned on stale evidence, and a failing gate invalidates it (06 §3).
  v_result := private.evaluate_publication_gates(p_project_id, p_release_id);
  if not coalesce((v_result ->> 'eligible')::boolean, false) then
    perform private.invalidate_authorizations(p_project_id, 'gates_failed');
    perform private.record_audit_event('publication.authorization_rejected', 'preview_releases', p_release_id::text,
      p_project_id, null, jsonb_build_object('failing_gates', private.failing_gates(v_result)));
    return jsonb_build_object('ok', false, 'error', 'gates_failed', 'failing_gates', private.failing_gates(v_result));
  end if;
  select * into v_existing from public.publication_authorizations
   where project_id = p_project_id and invalidated_at is null;
  if found and v_existing.release_id = p_release_id
     and not exists (select 1 from public.publication_deployments where authorization_id = v_existing.id) then
    return jsonb_build_object('ok', true, 'authorization_id', v_existing.id, 'existing', true);
  end if;
  -- AUTH-015 (OI-114, D1, D4; M-1): if the project's latest deployment is of this release and has
  -- not been recovered, the release is not authorized again. This covers the used authorization
  -- that is still active (a failed, unverified or verified deployment) and one a gate failure
  -- closed after a failed deployment. A new authorization follows only the Owner's explicit
  -- recovery (reopen_failed_publication); never silently.
  if exists (select 1 from (select d.id, d.release_id from public.publication_deployments d
                             where d.project_id = p_project_id order by d.seq desc limit 1) l
              where l.release_id = p_release_id and not private.wpc_publication_recovered(l.id)) then
    perform private.record_audit_event('publication.authorization_rejected', 'preview_releases', p_release_id::text,
      p_project_id, null, jsonb_build_object('reason', 'recovery_required'));
    return private.fail('recovery_required');
  end if;
  -- One active authorization per project: an earlier one (already used or for another
  -- release) is closed before the new one is issued.
  if v_existing.id is not null then
    update public.publication_authorizations set invalidated_at = now(), invalidated_reason = 'superseded'
     where id = v_existing.id;
  end if;
  insert into public.publication_authorizations (project_id, release_id, gate_result, authorized_by)
  values (p_project_id, p_release_id, private.gate_snapshot(v_result), (select auth.uid()))
  returning id into v_id;
  perform private.emit_domain_event('publication.authorized', p_project_id, 'publication_authorization', v_id::text,
    jsonb_build_object('release_id', p_release_id), 'publication.authorized:' || v_id);
  perform private.record_audit_event('publication.authorized', 'publication_authorizations', v_id::text, p_project_id,
    null, jsonb_build_object('release_id', p_release_id));
  return jsonb_build_object('ok', true, 'authorization_id', v_id, 'existing', false);
end;
$$;

-- 3. Live verification (one hunk)
create or replace function private.record_live_verification(
  p_deployment_id uuid, p_requested_by uuid, p_served_build_id text, p_http_ok boolean, p_tls_ok boolean,
  p_key_pages_ok boolean, p_forms_ok boolean
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.publication_deployments;
  v_matches boolean;
  v_verified boolean;
  v_id uuid;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  -- OI-78 (amended): only an Owner or Admin may be the requester, whatever other staff
  -- roles exist now or later.
  if coalesce(private.staff_role_of(p_requested_by)::text, '') not in ('owner', 'admin') then
    return private.fail('forbidden');
  end if;
  -- AUTH-015 (OI-114): FOR SHARE serializes with reopen_failed_publication (FOR UPDATE), so a
  -- verification either commits before a recovery or sees it and is refused.
  select * into v from public.publication_deployments where id = p_deployment_id for share;
  if not found or v.outcome <> 'succeeded' then
    return private.fail('not_found');
  end if;
  if exists (select 1 from public.publication_authorizations a
              where a.id = v.authorization_id and a.invalidated_reason = 'failed_publication_recovery') then
    return private.fail('deployment_closed');
  end if;
  v_matches := coalesce(lower(btrim(p_served_build_id)) = v.commit_sha, false);
  v_verified := v_matches and coalesce(p_http_ok, false) and coalesce(p_tls_ok, false)
    and coalesce(p_key_pages_ok, false) and coalesce(p_forms_ok, false);
  insert into public.deployment_verifications (deployment_id, project_id, served_build_id, http_ok, tls_ok,
    key_pages_ok, forms_ok, build_matches, verified, requested_by)
  values (v.id, v.project_id, left(p_served_build_id, 100), coalesce(p_http_ok, false), coalesce(p_tls_ok, false),
    coalesce(p_key_pages_ok, false), coalesce(p_forms_ok, false), v_matches, v_verified, p_requested_by)
  returning id into v_id;
  insert into public.audit_events (actor_user_id, actor_role, action, category, target_type, target_id, project_id,
    request_id, summary)
  values (p_requested_by, private.staff_role_of(p_requested_by)::text, 'deployment.verification_recorded', 'general',
    'publication_deployments', v.id::text, v.project_id, left(private.request_header('x-request-id'), 100),
    jsonb_build_object('verified', v_verified, 'build_matches', v_matches));
  if v_verified then
    perform private.enqueue_notification('publication.live', 'publication.live:' || v.id || ':1', 'publication_live', 1,
      v.project_id, null, '{}', array['client', 'owner']::public.notification_recipient_role[],
      jsonb_build_object('deployment_id', v.id, 'release_id', v.release_id));
  else
    insert into public.publication_incidents (project_id, deployment_id, severity, kind, summary)
    values (v.project_id, v.id, 'sev2', 'verification_failed',
      case when not v_matches then 'Served build does not match the authorized release' else 'Live verification failed' end);
    perform private.enqueue_notification('publication.verification_failed',
      'publication.verification_failed:' || v_id || ':1', 'publication_failed', 1, v.project_id, null, '{}',
      array['owner']::public.notification_recipient_role[], jsonb_build_object('deployment_id', v.id));
  end if;
  return jsonb_build_object('ok', true, 'verified', v_verified, 'build_matches', v_matches);
end;
$$;
