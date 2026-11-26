-- WP-C (AUTH-013, OI-113): authoritative approval identification in the WP-C gate interface.
--
-- private.project_fulfillment_status is its current definition (20261124140200) with one
-- change: the selection of the current release's approval. Everything else is byte-identical:
-- the signature, the return composite, contract_version 2, language, volatility, security
-- definer, search_path, and every other line of the body. `create or replace` preserves the
-- ACL. No other function, table, index, grant or policy is created or changed.
--
-- The authoritative approval is the one named by the release's canonical release.approved
-- event. WP-C's approve_preview emits that event exactly once, in the same transaction as the
-- first approval inserted under the per-project release advisory lock, with the unique
-- deduplication key 'release.approved:<release id>'. Before this change the interface took the
-- earliest approved_at, which is the inserting transaction's start time and can name a
-- different approval than the event under concurrency (PR #35 B-1), so WP-H's strict equality
-- check failed closed (approval_mismatch) on a legitimate approval.
--
-- All six conditions must hold; at most one event matches because dedupe_key is unique.
-- There is no timestamp fallback: missing or inconsistent canonical evidence means the current
-- release is not approved (current_release_approved = v_approval is not null, unchanged).
-- Existing rows are untouched: no domain event, approval, consumption record or publication
-- evidence is written, replayed or re-emitted by this migration.

create or replace function private.project_fulfillment_status(p_project_id uuid)
returns private.project_fulfillment_status
language plpgsql stable security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_approval uuid;
  v_qa public.qa_results;
  v_sec public.security_check_results;
  v_domain public.domain_readiness_checks;
  v_holds public.hold_type[];
  v_hold_ids uuid[];
  v_state public.intake_state;
  v_revoked_assets boolean := false;
begin
  if not exists (select 1 from public.projects where id = p_project_id) then
    return row(p_project_id, 2::smallint, false, 'locked'::public.intake_state, false, null::uuid, false, null::uuid,
      false, false, '{}'::public.hold_type[], '{}'::jsonb, false, null::uuid, null::timestamptz
    )::private.project_fulfillment_status;
  end if;
  v_state := private.intake_state_of(p_project_id);
  v_release := private.current_release(p_project_id);
  if v_release.id is not null then
    -- OI-113: the approval named by the canonical release.approved event, with all six conditions.
    select a.id into v_approval
      from public.domain_events e
      join public.preview_approvals a
        on a.id::text = e.payload ->> 'approval_id'                    -- (6) the named approval,
       and a.release_id = v_release.id and a.project_id = p_project_id --     of this release and project
     where e.dedupe_key = 'release.approved:' || v_release.id::text    -- (1) the canonical key (unique)
       and e.event_type = 'release.approved'                           -- (2)
       and e.subject_type = 'preview_release'                          -- (3)
       and e.subject_id = v_release.id::text                           -- (4)
       and e.project_id = p_project_id;                                -- (5)
    select * into v_qa from public.qa_results q where q.release_id = v_release.id
     order by q.seq desc limit 1;
    select * into v_sec from public.security_check_results s where s.release_id = v_release.id
     order by s.seq desc limit 1;
    v_revoked_assets := exists (select 1 from public.preview_release_assets m
      join public.asset_uploads u on u.id = m.upload_id
      where m.release_id = v_release.id and u.status <> 'available');
  end if;
  select * into v_domain from public.domain_readiness_checks d where d.project_id = p_project_id
   order by d.seq desc limit 1;
  select coalesce(array_agg(h.hold_type), '{}'), coalesce(array_agg(h.id), '{}') into v_holds, v_hold_ids
    from public.approval_holds h where h.project_id = p_project_id and h.cleared_at is null;

  return row(
    p_project_id, 2::smallint, true,
    v_state, v_state = 'accepted_by_staff',
    v_release.id, v_approval is not null, v_approval,
    -- 06 §6 "approved assets only": a release whose manifest holds an asset that is no longer
    -- available (for example revoked after a late malicious verdict) fails G5.
    v_release.id is not null and private.qa_result_passes(v_qa) and not v_revoked_assets,
    v_release.id is not null and private.security_result_passes(v_sec),
    v_holds,
    jsonb_build_object(
      'current_release_number', v_release.release_number,
      'current_release_commit_sha', v_release.commit_sha,
      'qa_result_id', v_qa.id, 'qa_release_id', v_qa.release_id,
      'security_result_id', v_sec.id, 'security_release_id', v_sec.release_id,
      'fulfillment_hold_ids', to_jsonb(v_hold_ids),
      'release_assets_unavailable', v_revoked_assets),
    v_domain.id is not null and private.domain_check_passed(v_domain)
      and v_domain.checked_at > now() - private.domain_freshness_window(),
    v_domain.id, v_domain.checked_at
  )::private.project_fulfillment_status;
end;
$$;
