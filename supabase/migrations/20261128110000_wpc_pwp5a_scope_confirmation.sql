-- WP-C PWP-5a (AUTH-023; OI-111; OD-14, OD-15): project-specific scope confirmation, the
-- authorized signer's acknowledgment, staff operational notes and the preview-release gate
-- (05 §3A; 03 §4; T-LC-19, T-LC-20; T-LC-16 preserved).
--
-- 1. public.scope_confirmations: immutable, hashed versions (spotlight.scope_confirmation.v1).
--    Owner or Admin records one after intake is accepted_by_staff, for the project's effective
--    order summary, bound by its id and snapshot_sha256 (v1 or v2 alike). A version records the
--    client's requirements (with the accepted intake submission it rests on), the confirmed
--    fulfillment selections and references to separately authorized amendments. A change is a
--    new version; nothing is ever edited.
-- 2. public.scope_confirmation_acknowledgments: insert-only. Only the authorized signer (the
--    client who accepted the effective order summary, still an active member, with a verified
--    email) acknowledges the exact current version, by its content hash; the acknowledgment and
--    the "unchecked by default" checkbox must both be explicit. Audited.
-- 3. public.project_operational_notes: staff-only (Owner, Admin), append-only, outside every
--    contractual snapshot. Never a contractual obligation.
-- 4. The gate: private.release_preview (one hunk) refuses every actor unless the latest
--    confirmation version is still bound to the current effective order summary, verifies, and
--    is acknowledged. It runs after the release:<project> lock, which recording and
--    acknowledging also take, so the three serialize. Any new version needs a new
--    acknowledgment (OD-14). There is no override, bypass or "on behalf of the client" path.
-- 5. private.operational_queue (one hunk): awaiting_scope_acknowledgment, for a current version
--    the authorized signer has not acknowledged yet. (A project with none shows its scope state on
--    its staff page; the release gate refuses either way.)
--
-- Never touched (T-LC-20): order summaries, their hashes, the accepted price, the ledger, any
-- payment or WP-B object; AUTH-021 and AUTH-022 objects. No entitlement check against a package
-- specification (SLM-CPS-002). Every other line of both replaced functions is byte-identical to
-- 20261124140200; create or replace keeps their ACLs. Guards are NULL-safe (OI-120).

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table public.scope_confirmations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  version integer not null check (version >= 1),
  order_summary_id uuid not null references public.order_summaries (id) on delete restrict,
  order_summary_sha256 text not null check (order_summary_sha256 ~ '^[0-9a-f]{64}$'),
  intake_submission_id uuid not null references public.intake_submissions (id) on delete restrict,
  client_requirements text not null check (char_length(btrim(client_requirements)) between 1 and 4000),
  fulfillment_selections jsonb not null check (jsonb_typeof(fulfillment_selections) = 'array'
    and jsonb_array_length(fulfillment_selections) between 1 and 50),
  amendment_references jsonb not null default '[]'::jsonb check (jsonb_typeof(amendment_references) = 'array'
    and jsonb_array_length(amendment_references) <= 20),
  canonicalization text not null default 'spotlight.scope_confirmation.v1'
    check (canonicalization = 'spotlight.scope_confirmation.v1'),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  constraint scope_confirmations_version_unique unique (project_id, version)
);
create trigger scope_confirmations_insert_only before update or delete on public.scope_confirmations
  for each row execute function private.wpc_insert_only();

create table public.scope_confirmation_acknowledgments (
  id uuid primary key default gen_random_uuid(),
  confirmation_id uuid not null unique references public.scope_confirmations (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  confirmation_sha256 text not null check (confirmation_sha256 ~ '^[0-9a-f]{64}$'),
  order_summary_id uuid not null references public.order_summaries (id) on delete restrict,
  signer_user_id uuid not null references public.profiles (id),
  signer_verified_email text not null check (char_length(signer_verified_email) between 3 and 320),
  acknowledged boolean not null check (acknowledged),
  checkbox_unchecked_by_default boolean not null check (checkbox_unchecked_by_default),
  ip text check (ip is null or char_length(ip) <= 100),
  user_agent text check (user_agent is null or char_length(user_agent) <= 300),
  request_id text check (request_id is null or char_length(request_id) <= 100),
  acknowledged_at timestamptz not null default now()
);
create trigger scope_confirmation_acknowledgments_insert_only before update or delete
  on public.scope_confirmation_acknowledgments for each row execute function private.wpc_insert_only();

create table public.project_operational_notes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  note text not null check (char_length(btrim(note)) between 1 and 4000),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);
create trigger project_operational_notes_insert_only before update or delete on public.project_operational_notes
  for each row execute function private.wpc_insert_only();

create index scope_confirmations_project_idx on public.scope_confirmations (project_id, version desc);
create index scope_confirmation_acknowledgments_project_idx on public.scope_confirmation_acknowledgments (project_id);
create index project_operational_notes_project_idx on public.project_operational_notes (project_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. Hash, effective summary, signer and state
-- ---------------------------------------------------------------------------
-- spotlight.scope_confirmation.v1: every field length-prefixed, in a fixed order, so no two
-- different confirmations share a canonical text.
create function private.scope_confirmation_canonical(c public.scope_confirmations) returns text
language sql immutable set search_path = '' as $$
  select 'spotlight.scope_confirmation.v1'
    || '|p' || c.project_id::text || '|v' || c.version::text
    || '|o' || c.order_summary_id::text || '|h' || c.order_summary_sha256
    || '|i' || c.intake_submission_id::text
    || '|r' || octet_length(c.client_requirements) || ':' || c.client_requirements
    || '|s' || jsonb_array_length(c.fulfillment_selections)
    || coalesce((select string_agg('|s' || x.i || ':' || octet_length(x.v) || ':' || x.v, '' order by x.i)
                   from jsonb_array_elements_text(c.fulfillment_selections) with ordinality x(v, i)), '')
    || '|a' || jsonb_array_length(c.amendment_references)
    || coalesce((select string_agg('|a' || x.i || ':' || octet_length(x.v) || ':' || x.v, '' order by x.i)
                   from jsonb_array_elements_text(c.amendment_references) with ordinality x(v, i)), '');
$$;

create function private.scope_confirmation_verifies(c public.scope_confirmations) returns boolean
language sql immutable set search_path = '' as $$
  select c.id is not null
     and c.content_sha256 = encode(extensions.digest(convert_to(private.scope_confirmation_canonical(c), 'UTF8'),
                                                      'sha256'), 'hex');
$$;

-- The project's effective order summary (WP-B's derived agreement state; read only).
create function private.scope_effective_order_summary(p_project_id uuid) returns public.order_summaries
language plpgsql stable security definer set search_path = '' as $$
declare
  v_state record;
  v_summary public.order_summaries;
begin
  select * into v_state from private.project_agreement_state(p_project_id);
  if v_state.state is distinct from 'effective' or v_state.order_summary_id is null then
    return null;
  end if;
  select * into v_summary from public.order_summaries where id = v_state.order_summary_id;
  return v_summary;
end;
$$;

-- The authorized signer: the client who accepted the effective order summary.
create function private.scope_authorized_signer(p_project_id uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select a.signer_user_id from public.agreement_acceptances a
   where a.order_summary_id = (private.scope_effective_order_summary(p_project_id)).id;
$$;

-- The latest confirmation version of a project.
create function private.current_scope_confirmation(p_project_id uuid) returns public.scope_confirmations
language sql stable security definer set search_path = '' as $$
  select * from public.scope_confirmations c where c.project_id = p_project_id order by c.version desc limit 1;
$$;

-- none: no version; stale: the latest version no longer matches the current effective order
-- summary (id and hash) or fails its hash; unacknowledged; acknowledged (by the signer, of this
-- exact version's hash). Only 'acknowledged' lets a preview be released.
create function private.scope_confirmation_state(p_project_id uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  c public.scope_confirmations;
  s public.order_summaries;
  a public.scope_confirmation_acknowledgments;
begin
  c := private.current_scope_confirmation(p_project_id);
  if c.id is null then
    return 'none';
  end if;
  s := private.scope_effective_order_summary(p_project_id);
  if s.id is null or s.id <> c.order_summary_id or s.snapshot_sha256 <> c.order_summary_sha256
     or not private.scope_confirmation_verifies(c) then
    return 'stale';
  end if;
  select * into a from public.scope_confirmation_acknowledgments x where x.confirmation_id = c.id;
  if a.id is null or a.confirmation_sha256 <> c.content_sha256 or a.order_summary_id <> c.order_summary_id
     or a.signer_user_id is distinct from private.scope_authorized_signer(p_project_id) then
    return 'unacknowledged';
  end if;
  return 'acknowledged';
end;
$$;

-- The release gate's refusal code, or null.
create function private.scope_confirmation_gate(p_project_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case private.scope_confirmation_state(p_project_id)
    when 'acknowledged' then null
    when 'none' then 'scope_confirmation_required'
    when 'stale' then 'scope_confirmation_stale'
    else 'scope_acknowledgment_required' end;
$$;

-- RLS helper: the id of a project's latest version (a policy cannot query its own table). It
-- answers only for staff or a member of that project, so it reveals nothing about other projects.
create function private.current_scope_confirmation_id(p_project_id uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select case when private.can_access_project(p_project_id)
              then (private.current_scope_confirmation(p_project_id)).id end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Record a confirmation version (Owner or Admin, aal2, live session)
-- ---------------------------------------------------------------------------
create function private.record_scope_confirmation(p_project_id uuid, p_client_requirements text,
  p_fulfillment_selections text[], p_amendment_references text[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_code text;
  v_summary public.order_summaries;
  v_intake uuid;
  v_prev public.scope_confirmations;
  v_new public.scope_confirmations;
  v_sel jsonb;
  v_amd jsonb;
begin
  -- NULL-safe (OI-120). Owner or Admin only: wpc_is_staff_aal2 is is_staff (owner, admin; never
  -- Sales) at aal2 in a live session.
  if private.wpc_is_staff_aal2() is not true then
    return private.fail('forbidden');
  end if;
  if not exists (select 1 from public.projects where id = p_project_id and archived_at is null) then
    return private.fail('not_found');
  end if;
  if private.wpc_text_ok(p_client_requirements, 4000) is not true
     or coalesce(cardinality(p_fulfillment_selections), 0) not between 1 and 50
     or array_position(p_fulfillment_selections, null) is not null
     or exists (select 1 from unnest(p_fulfillment_selections) x(v) where private.wpc_text_ok(x.v, 500) is not true)
     or coalesce(cardinality(p_amendment_references), 0) > 20
     or array_position(coalesce(p_amendment_references, '{}'), null) is not null
     or exists (select 1 from unnest(coalesce(p_amendment_references, '{}')) x(v)
                 where x.v !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,99}$') then
    return private.fail('invalid_input');
  end if;
  -- The same lock as release_preview and the acknowledgment: the three serialize.
  perform pg_advisory_xact_lock(hashtextextended('release:' || p_project_id::text, 0));
  if private.intake_state_of(p_project_id) <> 'accepted_by_staff' then
    v_code := 'intake_not_accepted';
  else
    v_summary := private.scope_effective_order_summary(p_project_id);
    if v_summary.id is null then
      v_code := 'agreement_not_effective';
    end if;
  end if;
  if v_code is null then
    select s.id into v_intake from public.intake_submissions s
     where s.project_id = p_project_id and s.status = 'submitted' order by s.version desc limit 1;
    select coalesce(jsonb_agg(btrim(x.v) order by x.i), '[]'::jsonb) into v_sel
      from unnest(p_fulfillment_selections) with ordinality x(v, i);
    select coalesce(jsonb_agg(x.v order by x.i), '[]'::jsonb) into v_amd
      from unnest(coalesce(p_amendment_references, '{}')) with ordinality x(v, i);
    v_prev := private.current_scope_confirmation(p_project_id);
    if v_prev.id is not null and v_prev.order_summary_id = v_summary.id
       and v_prev.order_summary_sha256 = v_summary.snapshot_sha256 and v_prev.intake_submission_id = v_intake
       and v_prev.client_requirements = btrim(p_client_requirements) and v_prev.fulfillment_selections = v_sel
       and v_prev.amendment_references = v_amd then
      v_code := 'confirmation_unchanged';
    end if;
  end if;
  if v_code is not null then
    perform private.record_audit_event('scope_confirmation.rejected', 'projects', p_project_id::text, p_project_id,
      null, jsonb_build_object('reason', v_code));
    return private.fail(v_code);
  end if;

  v_new.id := gen_random_uuid();
  v_new.project_id := p_project_id;
  v_new.version := coalesce(v_prev.version, 0) + 1;
  v_new.order_summary_id := v_summary.id;
  v_new.order_summary_sha256 := v_summary.snapshot_sha256;
  v_new.intake_submission_id := v_intake;
  v_new.client_requirements := btrim(p_client_requirements);
  v_new.fulfillment_selections := v_sel;
  v_new.amendment_references := v_amd;
  v_new.content_sha256 := encode(extensions.digest(convert_to(private.scope_confirmation_canonical(v_new), 'UTF8'),
                                                    'sha256'), 'hex');
  insert into public.scope_confirmations (id, project_id, version, order_summary_id, order_summary_sha256,
    intake_submission_id, client_requirements, fulfillment_selections, amendment_references, content_sha256, created_by)
  values (v_new.id, v_new.project_id, v_new.version, v_new.order_summary_id, v_new.order_summary_sha256,
    v_new.intake_submission_id, v_new.client_requirements, v_new.fulfillment_selections, v_new.amendment_references,
    v_new.content_sha256, (select auth.uid()));
  perform private.record_audit_event('scope_confirmation.recorded', 'scope_confirmations', v_new.id::text, p_project_id,
    null, jsonb_build_object('version', v_new.version, 'content_sha256', v_new.content_sha256,
      'order_summary_id', v_new.order_summary_id, 'order_summary_sha256', v_new.order_summary_sha256,
      'selections', jsonb_array_length(v_sel), 'amendment_references', jsonb_array_length(v_amd),
      'supersedes', v_prev.id));
  return jsonb_build_object('ok', true, 'confirmation_id', v_new.id, 'version', v_new.version,
    'content_sha256', v_new.content_sha256);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Acknowledge the exact current version (the authorized signer only)
-- ---------------------------------------------------------------------------
create function private.acknowledge_scope_confirmation(p_confirmation_id uuid, p_content_sha256 text,
  p_acknowledged boolean, p_checkbox_unchecked_by_default boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_project uuid;
  c public.scope_confirmations;
  v_current public.scope_confirmations;
  v_summary public.order_summaries;
  v_existing public.scope_confirmation_acknowledgments;
  v_email text;
  v_code text;
  v_id uuid;
begin
  select x.project_id into v_project from public.scope_confirmations x where x.id = p_confirmation_id;
  -- NULL-safe (OI-120): a client member of the project, never staff (wpc_is_client_member).
  if v_project is null or private.wpc_is_client_member(v_project) is not true then
    return private.fail('not_found');
  end if;
  if p_acknowledged is not true or p_checkbox_unchecked_by_default is not true then
    return private.fail('explicit_acknowledgment_required');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || v_project::text, 0));
  select * into c from public.scope_confirmations where id = p_confirmation_id;
  select * into v_existing from public.scope_confirmation_acknowledgments where confirmation_id = c.id;
  if v_existing.id is not null and v_existing.signer_user_id = v_uid then
    return jsonb_build_object('ok', true, 'existing', true, 'acknowledgment_id', v_existing.id);
  end if;
  v_current := private.current_scope_confirmation(v_project);
  v_summary := private.scope_effective_order_summary(v_project);
  if private.scope_authorized_signer(v_project) is distinct from v_uid then
    v_code := 'not_authorized_signer';
  elsif v_current.id is distinct from c.id then
    v_code := 'confirmation_superseded';
  elsif v_summary.id is null or v_summary.id <> c.order_summary_id or v_summary.snapshot_sha256 <> c.order_summary_sha256
        or not private.scope_confirmation_verifies(c) then
    v_code := 'confirmation_stale';
  elsif p_content_sha256 is distinct from c.content_sha256 then
    v_code := 'confirmation_changed';
  elsif v_existing.id is not null then
    v_code := 'already_acknowledged';
  else
    select lower(u.email) into v_email from auth.users u where u.id = v_uid and u.email_confirmed_at is not null;
    if v_email is null then
      v_code := 'email_not_verified';
    end if;
  end if;
  if v_code is not null then
    perform private.record_audit_event('scope_confirmation.acknowledgment_rejected', 'scope_confirmations', c.id::text,
      v_project, null, jsonb_build_object('reason', v_code, 'version', c.version));
    return private.fail(v_code);
  end if;
  insert into public.scope_confirmation_acknowledgments (confirmation_id, project_id, confirmation_sha256,
    order_summary_id, signer_user_id, signer_verified_email, acknowledged, checkbox_unchecked_by_default, ip,
    user_agent, request_id)
  values (c.id, v_project, c.content_sha256, c.order_summary_id, v_uid, v_email, true, true,
    left(coalesce(private.request_header('x-client-ip'), private.request_header('x-forwarded-for')), 100),
    left(private.request_header('user-agent'), 300), left(private.request_header('x-request-id'), 100))
  returning id into v_id;
  perform private.record_audit_event('scope_confirmation.acknowledged', 'scope_confirmations', c.id::text, v_project,
    null, jsonb_build_object('acknowledgment_id', v_id, 'version', c.version, 'content_sha256', c.content_sha256,
      'order_summary_id', c.order_summary_id));
  return jsonb_build_object('ok', true, 'existing', false, 'acknowledgment_id', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Operational notes (Owner or Admin; append-only; outside every snapshot)
-- ---------------------------------------------------------------------------
create function private.record_operational_note(p_project_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if private.wpc_is_staff_aal2() is not true then
    return private.fail('forbidden');
  end if;
  if not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('not_found');
  end if;
  if private.wpc_text_ok(p_note, 4000) is not true then
    return private.fail('invalid_input');
  end if;
  insert into public.project_operational_notes (project_id, note, created_by)
  values (p_project_id, btrim(p_note), (select auth.uid()))
  returning id into v_id;
  -- The note text stays in the staff-only table; the audit event never carries it.
  perform private.record_audit_event('operational_note.recorded', 'project_operational_notes', v_id::text, p_project_id);
  return jsonb_build_object('ok', true, 'note_id', v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Status for the staff page and the client portal
-- ---------------------------------------------------------------------------
-- Staff (Owner, Admin) and client members of the project. Members see only the current version.
create function private.scope_confirmation_status(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  c public.scope_confirmations;
  a public.scope_confirmation_acknowledgments;
  v_staff boolean := coalesce(private.wpc_is_staff_aal2(), false);
begin
  if not v_staff and private.wpc_is_client_member(p_project_id) is not true then
    return private.fail('not_found');
  end if;
  c := private.current_scope_confirmation(p_project_id);
  select * into a from public.scope_confirmation_acknowledgments x where x.confirmation_id = c.id;
  return jsonb_build_object('ok', true, 'state', private.scope_confirmation_state(p_project_id),
    'confirmation', case when c.id is null then null else jsonb_build_object('id', c.id, 'version', c.version,
      'content_sha256', c.content_sha256, 'client_requirements', c.client_requirements,
      'fulfillment_selections', c.fulfillment_selections, 'amendment_references', c.amendment_references,
      'created_at', c.created_at) end,
    'acknowledged_at', a.acknowledged_at,
    'is_authorized_signer', not v_staff and private.scope_authorized_signer(p_project_id) is not distinct from (select auth.uid())
                            and (select auth.uid()) is not null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The release gate (one hunk)
-- ---------------------------------------------------------------------------
create or replace function private.release_preview(
  p_project_id uuid, p_commit_sha text, p_deployment_id text, p_preview_url text, p_asset_upload_ids uuid[],
  p_release_note text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_number integer;
  v_id uuid;
  v_bad integer;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  if not exists (select 1 from public.projects where id = p_project_id and archived_at is null) then
    return private.fail('not_found');
  end if;
  if private.intake_state_of(p_project_id) <> 'accepted_by_staff' then
    return private.fail('intake_not_accepted');
  end if;
  -- Only available assets of this project may be incorporated (T-UP-05).
  select count(*) into v_bad from unnest(coalesce(p_asset_upload_ids, '{}')) a(id)
   where not exists (select 1 from public.asset_uploads u
                      where u.id = a.id and u.project_id = p_project_id and u.status = 'available');
  if v_bad > 0 then
    return private.fail('asset_not_available');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || p_project_id::text, 0));
  -- AUTH-023 (OI-111, T-LC-19): after the release lock, which recording and acknowledging a
  -- scope confirmation also take, the current version must be acknowledged by the authorized
  -- signer. Every actor is refused otherwise; there is no override.
  if private.scope_confirmation_gate(p_project_id) is not null then
    perform private.record_audit_event('preview.release_rejected', 'projects', p_project_id::text, p_project_id, null,
      jsonb_build_object('reason', private.scope_confirmation_gate(p_project_id)));
    return private.fail(private.scope_confirmation_gate(p_project_id));
  end if;
  select coalesce(max(release_number), 0) + 1 into v_number from public.preview_releases where project_id = p_project_id;
  insert into public.preview_releases (project_id, release_number, commit_sha, deployment_id, preview_url,
    release_note, released_by)
  values (p_project_id, v_number, lower(p_commit_sha), p_deployment_id, p_preview_url, nullif(btrim(p_release_note), ''),
    (select auth.uid()))
  returning id into v_id;
  insert into public.preview_release_assets (release_id, upload_id, project_id)
  select distinct v_id, a.id, p_project_id from unnest(coalesce(p_asset_upload_ids, '{}')) a(id);
  update public.asset_uploads set used = true, used_at = now()
   where id = any (coalesce(p_asset_upload_ids, '{}')) and not used;
  -- A new release supersedes earlier ones for approval and invalidates any pending
  -- authorization (05 §6; 06 §3; T-PUB-05).
  perform private.invalidate_authorizations(p_project_id, 'new_release');
  perform private.record_audit_event('preview.released', 'preview_releases', v_id::text, p_project_id, null,
    jsonb_build_object('release_number', v_number, 'commit_sha', lower(p_commit_sha), 'assets',
      cardinality(coalesce(p_asset_upload_ids, '{}'))));
  if v_number > 1 then
    perform private.record_audit_event('preview.superseded', 'preview_releases',
      (select id::text from public.preview_releases where project_id = p_project_id and release_number = v_number - 1),
      p_project_id, null, jsonb_build_object('superseded_by', v_id));
  end if;
  perform private.enqueue_notification('preview.released', 'preview.released:' || v_id || ':1', 'preview_released', 1,
    p_project_id, null, '{}', array['client']::public.notification_recipient_role[],
    jsonb_build_object('release_id', v_id, 'release_number', v_number));
  return jsonb_build_object('ok', true, 'release_id', v_id, 'release_number', v_number);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. The operational queue (one hunk)
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
      -- A client revision request stops the schedule (05 §7.1).
      if not exists (select 1 from public.preview_revision_requests q where q.release_id = v_release.id) then
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
-- 9. Wrappers, privileges and Row Level Security
-- ---------------------------------------------------------------------------
create function public.record_scope_confirmation(p_project_id uuid, p_client_requirements text,
  p_fulfillment_selections text[], p_amendment_references text[]) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_scope_confirmation(p_project_id, p_client_requirements, p_fulfillment_selections,
    p_amendment_references);
$$;
create function public.acknowledge_scope_confirmation(p_confirmation_id uuid, p_content_sha256 text,
  p_acknowledged boolean, p_checkbox_unchecked_by_default boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.acknowledge_scope_confirmation(p_confirmation_id, p_content_sha256, p_acknowledged,
    p_checkbox_unchecked_by_default);
$$;
create function public.record_operational_note(p_project_id uuid, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_operational_note(p_project_id, p_note);
$$;
create function public.scope_confirmation_status(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$
  select private.scope_confirmation_status(p_project_id);
$$;

-- Internal helpers: no API role.
revoke all on function
  private.scope_confirmation_canonical(public.scope_confirmations),
  private.scope_confirmation_verifies(public.scope_confirmations),
  private.scope_effective_order_summary(uuid),
  private.scope_authorized_signer(uuid),
  private.current_scope_confirmation(uuid),
  private.scope_confirmation_state(uuid),
  private.scope_confirmation_gate(uuid)
from public, anon, authenticated, service_role;
-- The RLS helper is evaluated in the caller's policies, so authenticated needs it (it returns an id only).
revoke all on function private.current_scope_confirmation_id(uuid) from public, anon, service_role;
grant execute on function private.current_scope_confirmation_id(uuid) to authenticated;
-- The four entry points re-authorize the caller inside (as release_preview): authenticated only.
revoke all on function
  private.record_scope_confirmation(uuid, text, text[], text[]),
  public.record_scope_confirmation(uuid, text, text[], text[]),
  private.acknowledge_scope_confirmation(uuid, text, boolean, boolean),
  public.acknowledge_scope_confirmation(uuid, text, boolean, boolean),
  private.record_operational_note(uuid, text),
  public.record_operational_note(uuid, text),
  private.scope_confirmation_status(uuid),
  public.scope_confirmation_status(uuid)
from public, anon, authenticated, service_role;
grant execute on function
  private.record_scope_confirmation(uuid, text, text[], text[]),
  public.record_scope_confirmation(uuid, text, text[], text[]),
  private.acknowledge_scope_confirmation(uuid, text, boolean, boolean),
  public.acknowledge_scope_confirmation(uuid, text, boolean, boolean),
  private.record_operational_note(uuid, text),
  public.record_operational_note(uuid, text),
  private.scope_confirmation_status(uuid),
  public.scope_confirmation_status(uuid)
to authenticated;

revoke all on table public.scope_confirmations, public.scope_confirmation_acknowledgments,
  public.project_operational_notes from public, anon, authenticated, service_role;
grant select on table public.scope_confirmations, public.scope_confirmation_acknowledgments,
  public.project_operational_notes to authenticated;

alter table public.scope_confirmations enable row level security;
alter table public.scope_confirmation_acknowledgments enable row level security;
alter table public.project_operational_notes enable row level security;

-- OD-15: staff (Owner, Admin) read every version; client members read the current version only;
-- Sales read nothing (is_staff and is_project_member both exclude every Sales role).
create policy scope_confirmations_select on public.scope_confirmations for select to authenticated
  using ((select private.is_staff())
         or (private.is_project_member(project_id) and id = private.current_scope_confirmation_id(project_id)));
create policy scope_confirmation_acknowledgments_select on public.scope_confirmation_acknowledgments
  for select to authenticated using (private.can_access_project(project_id));
create policy project_operational_notes_select on public.project_operational_notes for select to authenticated
  using ((select private.is_staff()));

do $$
declare
  t text;
begin
  foreach t in array array['scope_confirmations', 'scope_confirmation_acknowledgments', 'project_operational_notes'] loop
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated
         using (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))
         with check (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))',
      t || '_staff_aal2', t);
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated
         using ((select private.is_active_user())) with check ((select private.is_active_user()))',
      t || '_active_user', t);
  end loop;
end;
$$;
