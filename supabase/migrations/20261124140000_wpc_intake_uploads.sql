-- WP-C (1 of 3): client intake and private uploads with quarantine (05 §3-§5; AUTH-001,
-- AUTH-004). Creates only new WP-C objects. No Phase 2 or WP-0 object is changed, and no
-- WP-B table is written.
--
-- Trust model:
-- - Every state change goes through a SECURITY DEFINER function in `private` that
--   re-authorizes the caller (03 §10). Tables grant SELECT only; RLS scopes every row to a
--   project the caller can access (03 §8-§9).
-- - Intake and uploads are locked until the deposit is verified. The deposit state is read
--   only through the approved WP-B interface `private.project_financial_status`, and the
--   read fails closed (05 §3; T-LC-01).
-- - Scan results are recorded only by the server with the secret key (JWT role
--   service_role). No client or staff path can record, alter, or self-certify a scan
--   (05 §5.3 rule 2; AUTH-004).
-- - Release from quarantine requires a clean scan of the exact stored bytes (sha256) by a
--   scanner permitted in this database's runtime environment. The only scanner is the
--   mocked one, and it is permitted only when `private.runtime_environment` says
--   development or test (seeded locally; never present in a hosted database). Real scanned
--   release needs DEP-07 and a new migration.

-- ---------------------------------------------------------------------------
-- 0. Runtime environment marker (fail closed: no row means "not a development database")
-- ---------------------------------------------------------------------------
create table private.runtime_environment (
  singleton boolean primary key default true check (singleton),
  app_env text not null check (app_env in ('development', 'test')),
  recorded_at timestamptz not null default now()
);
revoke all on table private.runtime_environment from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 1. Shared WP-C helpers
-- ---------------------------------------------------------------------------
-- Staff (Owner or Admin) at aal2 in a live session (03 §7).
create function private.wpc_is_staff_aal2() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_staff() and private.is_aal2() and private.session_is_active();
$$;

-- An active client member of the project, in a live session (03 §4 "M"). OI-78 (amended):
-- the caller must hold no staff role of any kind (`staff_role_of(...) is null`), so a
-- staff-role holder is never a client member however `private.is_staff()` is later defined.
create function private.wpc_is_client_member(p_project_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select (select auth.uid()) is not null
     and private.staff_role_of((select auth.uid())) is null
     and not exists (select 1 from public.staff_roles s
                      where s.user_id = (select auth.uid()) and s.status = 'active')
     and private.session_is_active()
     and private.is_project_member(p_project_id);
$$;

-- Deposit verified, read only through the approved WP-B interface (01 §7). Any error,
-- mismatch, or an unimplemented interface reads as "not verified" (fail closed).
create function private.wpc_deposit_verified(p_project_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  v := to_jsonb(private.project_financial_status(p_project_id));
  return v ->> 'project_id' = p_project_id::text
     and v -> 'implemented' = 'true'::jsonb
     and v -> 'deposit_verified' = 'true'::jsonb;
exception
  when others then
    return false;
end;
$$;

-- Intake precondition (05 §3; OI-74; T-LC-01): deposit verified AND a ready payment
-- authorization, both read only through the WP-B interface as JSON. A missing attribute,
-- a non-boolean value, an error, or an unimplemented interface keeps intake locked.
create function private.wpc_intake_unlocked(p_project_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
begin
  v := to_jsonb(private.project_financial_status(p_project_id));
  return coalesce(v ->> 'project_id' = p_project_id::text
     and v -> 'implemented' = 'true'::jsonb
     and v -> 'deposit_verified' = 'true'::jsonb
     and v -> 'payment_authorization_ready' = 'true'::jsonb, false);
exception
  when others then
    return false;
end;
$$;

-- Calendar days in America/Detroit between a timestamp's local date and today's local date
-- (02 §13: never 24-hour arithmetic on UTC).
create function private.detroit_days_since(p_at timestamptz) returns integer
language sql stable set search_path = '' as $$
  select ((now() at time zone 'America/Detroit')::date - (p_at at time zone 'America/Detroit')::date);
$$;

create function private.wpc_text_ok(p_value text, p_max integer) returns boolean
language sql immutable set search_path = '' as $$
  select p_value is not null and char_length(btrim(p_value)) between 1 and p_max;
$$;

-- ---------------------------------------------------------------------------
-- 2. Intake (05 §3)
-- ---------------------------------------------------------------------------
-- Field keys accepted in intake content. The required set is enforced on submission.
-- The list is [PROPOSED] in 05 §3 for Owner refinement; it mirrors src/domain/intake.ts.
create function private.intake_allowed_keys() returns text[]
language sql immutable set search_path = '' as $$
  select array['business_legal_name', 'business_display_name', 'contact_phone', 'contact_email',
               'address', 'service_areas', 'services_offered', 'brand_guidelines_notes',
               'style_references', 'color_preferences', 'pages_wanted', 'domain_status',
               'existing_domain', 'additional_notes'];
$$;
create function private.intake_required_keys() returns text[]
language sql immutable set search_path = '' as $$
  select array['business_legal_name', 'business_display_name', 'contact_phone', 'contact_email',
               'address', 'service_areas', 'services_offered', 'domain_status'];
$$;

-- Shape check for stored content: an object, bounded, only known keys, each value a
-- bounded string or an array of bounded strings.
create function private.intake_content_valid(p_content jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_content) = 'object'
     and octet_length(p_content::text) <= 32768
     and not exists (
       select 1 from jsonb_each(p_content) e
       where not (e.key = any (private.intake_allowed_keys()))
          or not (
            (jsonb_typeof(e.value) = 'string' and char_length(e.value #>> '{}') <= 2000)
            or (jsonb_typeof(e.value) = 'array' and jsonb_array_length(e.value) <= 50
                and not exists (
                  select 1 from jsonb_array_elements(e.value) a
                  where jsonb_typeof(a) <> 'string' or char_length(a #>> '{}') not between 1 and 300))
          )
     )
     and (not p_content ? 'domain_status' or p_content ->> 'domain_status' in ('existing', 'needs_domain'));
$$;

create function private.intake_content_complete(p_content jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select private.intake_content_valid(p_content)
     and not exists (
       select 1 from unnest(private.intake_required_keys()) k
       where not p_content ? k
          or (jsonb_typeof(p_content -> k) = 'string' and btrim(p_content ->> k) = '')
          or (jsonb_typeof(p_content -> k) = 'array' and jsonb_array_length(p_content -> k) = 0)
     )
     and (p_content ->> 'domain_status' <> 'existing' or coalesce(btrim(p_content ->> 'existing_domain'), '') <> '');
$$;

create table public.intake_submissions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  version integer not null check (version >= 1),
  status text not null default 'draft' check (status in ('draft', 'submitted')),
  source text not null default 'client' check (source in ('client', 'staff_correction')),
  content jsonb not null default '{}'::jsonb,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_by uuid references public.profiles (id),
  submitted_at timestamptz,
  correction_reason text,
  constraint intake_submissions_content_valid check (private.intake_content_valid(content)),
  constraint intake_submissions_submitted_shape check (
    (status = 'draft' and submitted_at is null and submitted_by is null)
    or (status = 'submitted' and submitted_at is not null and submitted_by is not null)),
  constraint intake_submissions_correction_shape check (
    (source = 'client' and correction_reason is null)
    or (source = 'staff_correction' and status = 'submitted' and char_length(btrim(correction_reason)) between 1 and 1000)),
  unique (project_id, version)
);
create unique index intake_submissions_one_draft on public.intake_submissions (project_id) where status = 'draft';
create index intake_submissions_project_idx on public.intake_submissions (project_id, version desc);

create table public.intake_reviews (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  submission_id uuid not null unique references public.intake_submissions (id) on delete restrict,
  decision text not null check (decision in ('accepted', 'changes_requested')),
  note text check (note is null or char_length(note) <= 2000),
  reviewed_by uuid not null references public.profiles (id),
  reviewed_at timestamptz not null default now(),
  constraint intake_reviews_note_required check (decision = 'accepted' or char_length(btrim(note)) >= 1)
);
create index intake_reviews_project_idx on public.intake_reviews (project_id);

-- A submitted version is immutable (T-LC-04). A draft may change only its content, or be
-- submitted once. Nothing is deleted.
create function private.intake_submissions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'intake submissions are not deleted' using errcode = '42501';
  end if;
  if old.status = 'submitted' then
    raise exception 'a submitted intake version is immutable' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.version, new.source, new.created_by, new.created_at, new.correction_reason)
     is distinct from
     (old.id, old.project_id, old.version, old.source, old.created_by, old.created_at, old.correction_reason) then
    raise exception 'intake identity columns are immutable' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger intake_submissions_guard before update or delete on public.intake_submissions
  for each row execute function private.intake_submissions_guard();

create function private.wpc_insert_only() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception '% is insert-only', tg_table_name using errcode = '42501';
end;
$$;
create trigger intake_reviews_insert_only before update or delete on public.intake_reviews
  for each row execute function private.wpc_insert_only();

-- Derived intake state (05 §2). Never stored.
create function private.intake_state_of(p_project_id uuid) returns public.intake_state
language plpgsql stable security definer set search_path = '' as $$
declare
  v_latest uuid;
  v_decision text;
begin
  select s.id into v_latest from public.intake_submissions s
   where s.project_id = p_project_id and s.status = 'submitted'
   order by s.version desc limit 1;
  if v_latest is null then
    return case when private.wpc_intake_unlocked(p_project_id)
                then 'open'::public.intake_state else 'locked'::public.intake_state end;
  end if;
  select r.decision into v_decision from public.intake_reviews r where r.submission_id = v_latest;
  return case v_decision
    when 'accepted' then 'accepted_by_staff'::public.intake_state
    when 'changes_requested' then 'changes_requested'::public.intake_state
    else 'submitted'::public.intake_state end;
end;
$$;

-- Save and resume (05 §3 autosave). Client members only, deposit verified, while intake is
-- open or changes were requested. One draft per project; the draft keeps its version.
create function private.save_intake_draft(p_project_id uuid, p_content jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_state public.intake_state;
  v_draft public.intake_submissions;
  v_version integer;
begin
  if not private.wpc_is_client_member(p_project_id) then
    return private.fail('forbidden');
  end if;
  if not private.wpc_intake_unlocked(p_project_id) then
    return private.fail('intake_locked');
  end if;
  v_state := private.intake_state_of(p_project_id);
  if v_state not in ('open', 'changes_requested') then
    return private.fail('intake_not_editable');
  end if;
  if not private.intake_content_valid(coalesce(p_content, '{}'::jsonb)) then
    return private.fail('invalid_input');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('intake:' || p_project_id::text, 0));
  select * into v_draft from public.intake_submissions
   where project_id = p_project_id and status = 'draft' for update;
  if found then
    update public.intake_submissions set content = p_content where id = v_draft.id;
    return jsonb_build_object('ok', true, 'draft_id', v_draft.id, 'version', v_draft.version);
  end if;
  select coalesce(max(version), 0) + 1 into v_version from public.intake_submissions where project_id = p_project_id;
  insert into public.intake_submissions (project_id, version, content, created_by)
  values (p_project_id, v_version, p_content, (select auth.uid()))
  returning * into v_draft;
  return jsonb_build_object('ok', true, 'draft_id', v_draft.id, 'version', v_draft.version);
end;
$$;

create function private.submit_intake(p_project_id uuid, p_draft_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_draft public.intake_submissions;
begin
  if not private.wpc_is_client_member(p_project_id) then
    return private.fail('forbidden');
  end if;
  if not private.wpc_intake_unlocked(p_project_id) then
    return private.fail('intake_locked');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('intake:' || p_project_id::text, 0));
  if private.intake_state_of(p_project_id) not in ('open', 'changes_requested') then
    return private.fail('intake_not_editable');
  end if;
  select * into v_draft from public.intake_submissions
   where id = p_draft_id and project_id = p_project_id and status = 'draft' for update;
  if not found then
    return private.fail('not_found');
  end if;
  if not private.intake_content_complete(v_draft.content) then
    return private.fail('incomplete');
  end if;
  update public.intake_submissions
     set status = 'submitted', submitted_at = now(), submitted_by = (select auth.uid())
   where id = v_draft.id;
  perform private.record_audit_event('intake.submitted', 'intake_submissions', v_draft.id::text, p_project_id,
    null, jsonb_build_object('version', v_draft.version));
  perform private.enqueue_notification('intake.submitted', 'intake.submitted:' || v_draft.id || ':1',
    'intake_submitted', 1, p_project_id, null, '{}', array['staff']::public.notification_recipient_role[],
    jsonb_build_object('submission_id', v_draft.id));
  return jsonb_build_object('ok', true, 'submission_id', v_draft.id, 'version', v_draft.version);
end;
$$;

-- Staff review of the latest submitted version (Owner or Admin, aal2).
create function private.review_intake(p_submission_id uuid, p_decision text, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_sub public.intake_submissions;
  v_latest uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  if p_decision not in ('accepted', 'changes_requested') then
    return private.fail('invalid_input');
  end if;
  select * into v_sub from public.intake_submissions where id = p_submission_id and status = 'submitted';
  if not found then
    return private.fail('not_found');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('intake:' || v_sub.project_id::text, 0));
  select id into v_latest from public.intake_submissions
   where project_id = v_sub.project_id and status = 'submitted' order by version desc limit 1;
  if v_latest <> v_sub.id or exists (select 1 from public.intake_reviews where submission_id = v_sub.id) then
    return private.fail('stale');
  end if;
  if p_decision = 'changes_requested' and not private.wpc_text_ok(p_note, 2000) then
    return private.fail('note_required');
  end if;
  insert into public.intake_reviews (project_id, submission_id, decision, note, reviewed_by)
  values (v_sub.project_id, v_sub.id, p_decision, nullif(btrim(p_note), ''), (select auth.uid()));
  perform private.record_audit_event(
    case p_decision when 'accepted' then 'intake.accepted' else 'intake.changes_requested' end,
    'intake_submissions', v_sub.id::text, v_sub.project_id, null, jsonb_build_object('version', v_sub.version));
  if p_decision = 'changes_requested' then
    perform private.enqueue_notification('intake.changes_requested', 'intake.changes_requested:' || v_sub.id || ':1',
      'intake_changes_requested', 1, v_sub.project_id, null, '{}', array['client']::public.notification_recipient_role[],
      jsonb_build_object('submission_id', v_sub.id));
  end if;
  return jsonb_build_object('ok', true);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

-- Audited staff correction (03 §4; OI-79 item 7): the Owner or an Admin corrects on the
-- client's behalf, with a required reason. Creates a new submitted version recording the
-- actor, time, and reason; the original submission and every earlier version are untouched
-- (T-LC-04, T-LC-17). The corrected version needs a staff review like any other.
create function private.correct_intake(p_project_id uuid, p_content jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_version integer;
  v_id uuid;
begin
  if not (private.wpc_is_staff_aal2() and private.staff_role_of((select auth.uid())) in ('owner', 'admin')) then
    return private.fail('forbidden');
  end if;
  if not private.wpc_text_ok(p_reason, 1000) then
    return private.fail('reason_required');
  end if;
  if not private.intake_content_complete(coalesce(p_content, '{}'::jsonb)) then
    return private.fail('incomplete');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('intake:' || p_project_id::text, 0));
  if not exists (select 1 from public.intake_submissions where project_id = p_project_id and status = 'submitted') then
    return private.fail('nothing_to_correct');
  end if;
  if exists (select 1 from public.intake_submissions where project_id = p_project_id and status = 'draft') then
    return private.fail('client_draft_open');
  end if;
  select max(version) + 1 into v_version from public.intake_submissions where project_id = p_project_id;
  insert into public.intake_submissions (project_id, version, status, source, content, created_by,
    submitted_by, submitted_at, correction_reason)
  values (p_project_id, v_version, 'submitted', 'staff_correction', p_content, (select auth.uid()),
    (select auth.uid()), now(), btrim(p_reason))
  returning id into v_id;
  perform private.record_audit_event('intake.edited_by_staff', 'intake_submissions', v_id::text, p_project_id,
    btrim(p_reason), jsonb_build_object('version', v_version));
  return jsonb_build_object('ok', true, 'submission_id', v_id, 'version', v_version);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Uploads, quarantine, and scanning (05 §4-§5)
-- ---------------------------------------------------------------------------
create type public.upload_category as enum (
  'logo', 'photo', 'brand_guidelines', 'business_document', 'video', 'other'
);
create type public.upload_status as enum (
  'uploading', 'failed_upload', 'quarantined', 'scanning', 'processing', 'available', 'rejected'
);

-- 05 §5.2 per-file limits. Sizes use decimal megabytes (1 MB = 1,000,000 bytes), the
-- reading approved in OI-79 item 1 (05 §5.4). Mirrors src/domain/uploads.ts (unit-tested).
create function private.upload_max_bytes(p_category public.upload_category, p_mime text) returns bigint
language sql immutable set search_path = '' as $$
  select case
    when p_category = 'logo' and p_mime in ('image/png', 'image/jpeg', 'image/webp', 'image/svg+xml') then 15000000
    when p_category = 'photo' and p_mime in ('image/jpeg', 'image/png', 'image/webp', 'image/heic') then 25000000
    when p_category = 'brand_guidelines' and p_mime = 'application/pdf' then 25000000
    when p_category = 'business_document' and p_mime in ('application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document') then 20000000
    when p_category = 'video' and p_mime in ('video/mp4', 'video/quicktime') then 250000000
  end::bigint;
$$;

-- 05 §5.1 quotas.
create function private.upload_quota_files() returns integer language sql immutable set search_path = '' as $$ select 100 $$;
create function private.upload_quota_bytes() returns bigint language sql immutable set search_path = '' as $$ select 2000000000::bigint $$;

-- Admin-approved exceptions (05 §5.1-§5.2): a non-standard file type ('other'), or extra
-- quota. Requested by a client member or staff; decided by staff with a reason. Audited.
create table public.upload_exceptions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  kind text not null check (kind in ('file_type', 'quota')),
  requested_mime text check (requested_mime is null or requested_mime ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$' and char_length(requested_mime) <= 100),
  max_bytes bigint check (max_bytes is null or max_bytes between 1 and 250000000),
  extra_files integer check (extra_files is null or extra_files between 1 and 1000),
  extra_bytes bigint check (extra_bytes is null or extra_bytes between 1 and 20000000000),
  justification text not null check (char_length(btrim(justification)) between 1 and 1000),
  status text not null default 'requested' check (status in ('requested', 'approved', 'denied')),
  requested_by uuid not null references public.profiles (id),
  requested_at timestamptz not null default now(),
  decided_by uuid references public.profiles (id),
  decided_at timestamptz,
  decision_reason text check (decision_reason is null or char_length(decision_reason) <= 1000),
  constraint upload_exceptions_shape check (
    (kind = 'file_type' and requested_mime is not null and max_bytes is not null and extra_files is null and extra_bytes is null)
    or (kind = 'quota' and requested_mime is null and max_bytes is null and (extra_files is not null or extra_bytes is not null))),
  constraint upload_exceptions_decision_shape check (
    (status = 'requested' and decided_at is null and decided_by is null)
    or (status <> 'requested' and decided_at is not null and decided_by is not null and char_length(btrim(decision_reason)) >= 1))
);
create index upload_exceptions_project_idx on public.upload_exceptions (project_id, status);

create function private.upload_exceptions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' or old.status <> 'requested' then
    raise exception 'upload exception decisions are final' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.kind, new.requested_mime, new.max_bytes, new.extra_files, new.extra_bytes,
      new.justification, new.requested_by, new.requested_at)
     is distinct from
     (old.id, old.project_id, old.kind, old.requested_mime, old.max_bytes, old.extra_files, old.extra_bytes,
      old.justification, old.requested_by, old.requested_at) then
    raise exception 'upload exception requests are immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger upload_exceptions_guard before update or delete on public.upload_exceptions
  for each row execute function private.upload_exceptions_guard();

create table public.asset_uploads (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  -- A logical asset groups its versions; a replacement is a new row (05 §4 versioning).
  asset_id uuid not null,
  version integer not null check (version >= 1),
  category public.upload_category not null,
  declared_mime text not null check (declared_mime ~ '^[a-z0-9.+-]+/[a-z0-9.+-]+$' and char_length(declared_mime) <= 100),
  declared_bytes bigint not null check (declared_bytes between 1 and 250000000),
  original_name text not null check (char_length(original_name) between 1 and 200 and original_name !~ '[/\\[:cntrl:]]'),
  exception_id uuid references public.upload_exceptions (id),
  status public.upload_status not null default 'uploading',
  quarantine_path text not null unique,
  released_path text unique,
  size_bytes bigint check (size_bytes is null or size_bytes between 1 and 250000000),
  sha256 text check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  detected_mime text check (detected_mime is null or char_length(detected_mime) <= 100),
  released_sha256 text check (released_sha256 is null or released_sha256 ~ '^[0-9a-f]{64}$'),
  released_bytes bigint check (released_bytes is null or released_bytes between 1 and 250000000),
  rejection_code text check (rejection_code is null or rejection_code ~ '^[a-z_]{1,60}$'),
  processing_note text check (processing_note is null or processing_note ~ '^[a-z_]{1,60}$'),
  used boolean not null default false,
  used_at timestamptz,
  uploaded_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  upload_expires_at timestamptz not null default (now() + interval '2 hours'),
  completed_at timestamptz,
  status_changed_at timestamptz not null default now(),
  purged_at timestamptz,
  -- Scan authority (05 §5.5). The current attempt is the only one whose results can move the
  -- upload toward release; failed attempts are bounded, with backoff after scanner errors.
  current_scan_attempt_id uuid,
  scan_failures integer not null default 0 check (scan_failures between 0 and 5),
  next_scan_at timestamptz,
  -- Processing re-read the stored quarantine object and confirmed its hash for this attempt.
  source_verified_attempt_id uuid,
  -- A malicious verdict for these bytes, at any time, blocks release permanently (05 §5.5 rule 3).
  malware_detected boolean not null default false,
  revoked_at timestamptz,
  unique (asset_id, version),
  constraint asset_uploads_paths check (
    quarantine_path = 'quarantine/' || project_id || '/' || id
    and (released_path is null or released_path = project_id || '/assets/' || id)),
  constraint asset_uploads_available_shape check (
    (status <> 'available' or (released_path is not null and released_sha256 is not null and released_bytes is not null))
    and ((released_path is null) = (released_sha256 is null) and (released_path is null) = (released_bytes is null))
    and (released_path is null or status in ('available', 'rejected'))),
  -- A released file can only leave `available` by revocation after a malicious verdict.
  constraint asset_uploads_revocation_shape check (
    (revoked_at is not null) = (released_path is not null and status = 'rejected')
    and (revoked_at is null or malware_detected)),
  constraint asset_uploads_rejected_shape check ((status = 'rejected') = (rejection_code is not null)),
  constraint asset_uploads_malware_shape check (not malware_detected or status = 'rejected'),
  constraint asset_uploads_used_shape check (used = (used_at is not null) and (not used or released_path is not null)),
  constraint asset_uploads_purge_shape check (purged_at is null or status = 'failed_upload')
);
create index asset_uploads_project_idx on public.asset_uploads (project_id, status);
create index asset_uploads_asset_idx on public.asset_uploads (asset_id, version desc);

-- Pipeline transitions (05 §5.3). Identity and content-binding columns never change; the
-- used flag never reverts (T-UP-10); nothing is deleted.
create function private.asset_uploads_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'asset uploads are not deleted' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.asset_id, new.version, new.category, new.declared_mime, new.declared_bytes,
      new.original_name, new.exception_id, new.quarantine_path, new.uploaded_by, new.created_at, new.upload_expires_at)
     is distinct from
     (old.id, old.project_id, old.asset_id, old.version, old.category, old.declared_mime, old.declared_bytes,
      old.original_name, old.exception_id, old.quarantine_path, old.uploaded_by, old.created_at, old.upload_expires_at) then
    raise exception 'asset upload identity columns are immutable' using errcode = '42501';
  end if;
  if old.sha256 is not null and new.sha256 is distinct from old.sha256
     or old.size_bytes is not null and new.size_bytes is distinct from old.size_bytes
     or old.released_path is not null and new.released_path is distinct from old.released_path
     or old.released_sha256 is not null and new.released_sha256 is distinct from old.released_sha256 then
    raise exception 'asset upload content binding is immutable' using errcode = '42501';
  end if;
  if old.used and not new.used then
    raise exception 'the used flag never reverts (OI-42)' using errcode = '42501';
  end if;
  if old.malware_detected and not new.malware_detected then
    raise exception 'a malware detection never reverts (05 §5.5)' using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    if not (
         (old.status = 'uploading' and new.status in ('failed_upload', 'quarantined'))
      or (old.status = 'quarantined' and new.status in ('rejected', 'scanning'))
      or (old.status = 'scanning' and new.status in ('rejected', 'processing', 'quarantined'))
      or (old.status = 'processing' and new.status in ('available', 'rejected', 'quarantined'))
      -- Revocation (05 §5.5 rule 3): only a malicious verdict takes a released file back.
      or (old.status = 'available' and new.status = 'rejected' and new.malware_detected
          and new.rejection_code = 'malware_detected')
    ) then
      raise exception 'invalid upload transition % -> %', old.status, new.status using errcode = '23514';
    end if;
    new.status_changed_at := now();
  end if;
  return new;
end;
$$;
create trigger asset_uploads_guard before update or delete on public.asset_uploads
  for each row execute function private.asset_uploads_guard();

-- Scan attempts (05 §5.5 rule 2). Each entry into `scanning` creates one, bound to the
-- server-computed hash of the stored quarantine object. Insert-only except for one closure.
create table public.upload_scan_attempts (
  id uuid primary key default gen_random_uuid(),
  seq bigint generated always as identity unique,
  upload_id uuid not null references public.asset_uploads (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  attempt_number integer not null check (attempt_number between 1 and 5),
  expected_sha256 text not null check (expected_sha256 ~ '^[0-9a-f]{64}$'),
  started_at timestamptz not null default now(),
  closed_at timestamptz,
  outcome text check (outcome in ('clean', 'malicious', 'error', 'scanner_not_permitted', 'hash_mismatch', 'invalid')),
  unique (upload_id, attempt_number),
  constraint upload_scan_attempts_closure check ((closed_at is null) = (outcome is null))
);
create index upload_scan_attempts_upload_idx on public.upload_scan_attempts (upload_id, seq desc);

create function private.upload_scan_attempts_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' or old.closed_at is not null
     or (new.id, new.seq, new.upload_id, new.project_id, new.attempt_number, new.expected_sha256, new.started_at)
        is distinct from
        (old.id, old.seq, old.upload_id, old.project_id, old.attempt_number, old.expected_sha256, old.started_at) then
    raise exception 'a scan attempt is immutable except for its single closure' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger upload_scan_attempts_guard before update or delete on public.upload_scan_attempts
  for each row execute function private.upload_scan_attempts_guard();

alter table public.asset_uploads
  add constraint asset_uploads_current_attempt_fk foreign key (current_scan_attempt_id) references public.upload_scan_attempts (id),
  add constraint asset_uploads_source_verified_fk foreign key (source_verified_attempt_id) references public.upload_scan_attempts (id);

-- Insert-only scan evidence. Written only by private.record_scan_result (service_role),
-- always after taking the upload row lock, so `seq` is the acceptance order per upload and
-- the lock is held until commit (05 §5.5 rule 1). Timestamps and UUIDs never decide
-- authority. Every result is kept; `authoritative` says whether it was allowed to act.
create table public.upload_scan_results (
  id uuid primary key default gen_random_uuid(),
  seq bigint generated always as identity unique,
  upload_id uuid not null references public.asset_uploads (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  attempt_id uuid references public.upload_scan_attempts (id),
  claimed_attempt_id uuid,
  scanner text not null check (scanner ~ '^[a-z][a-z0-9_]{1,40}$'),
  engine_version text not null check (char_length(engine_version) between 1 and 100),
  verdict text not null check (verdict in ('clean', 'malicious', 'error', 'invalid')),
  signature text check (signature is null or char_length(signature) <= 200),
  scanned_sha256 text not null check (scanned_sha256 ~ '^[0-9a-f]{64}$'),
  hash_matches boolean not null,
  authoritative boolean not null,
  disposition text not null check (disposition in (
    'clean_accepted', 'malicious_accepted', 'error_quarantined', 'scanner_not_permitted', 'hash_mismatch',
    'invalid_result', 'stale_attempt', 'duplicate', 'not_scanning', 'unknown_attempt')),
  scanned_at timestamptz not null default now(),
  constraint upload_scan_results_authority check (
    authoritative = (disposition in ('clean_accepted', 'malicious_accepted', 'error_quarantined',
                                     'scanner_not_permitted', 'hash_mismatch', 'invalid_result')))
);
create index upload_scan_results_upload_idx on public.upload_scan_results (upload_id, seq desc);
create index upload_scan_results_malicious_idx on public.upload_scan_results (scanned_sha256) where verdict = 'malicious';
create trigger upload_scan_results_insert_only before update or delete on public.upload_scan_results
  for each row execute function private.wpc_insert_only();

-- Malicious content (05 §5.5 rule 3; PR #19 review M1). The identity of malicious bytes is
-- the server-computed SHA-256 of the stored quarantine object (`asset_uploads.sha256`, from
-- the read-back in `complete_upload`), never a hash a scanner reports. One row per hash,
-- permanent, in `private`: no API role can read it, so no tenant learns another's content.
create table private.malicious_content (
  sha256 text primary key check (sha256 ~ '^[0-9a-f]{64}$'),
  first_upload_id uuid not null references public.asset_uploads (id) on delete restrict,
  detected_at timestamptz not null default now()
);
revoke all on table private.malicious_content from public, anon, authenticated, service_role;
create trigger malicious_content_insert_only before update or delete on private.malicious_content
  for each row execute function private.wpc_insert_only();

-- Content lock (M1). Every function that can make bytes available (`release_upload`) or
-- record a verdict about them (`record_scan_result`) takes this transaction-scoped lock on
-- the stored hash BEFORE the upload row lock, and holds it to commit. A malicious verdict
-- and a release of identical bytes therefore never interleave: whichever commits second
-- sees the other. One lock order everywhere (content, then row) rules out deadlock.
create function private.content_lock(p_sha256 text) returns void
language plpgsql set search_path = '' as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('wpc-content:' || p_sha256, 0));
end;
$$;

-- Durable deletion of revoked released objects (05 §5.5 rule 3; PR #19 review H1). The row
-- is inserted in the same transaction as the revocation, so a storage failure or a process
-- interruption leaves a pending row and never silently abandons an object. Attempts are
-- leased (an interrupted attempt's lease expires and the row is claimed again), bounded
-- (5 automatic attempts plus at most 10 Owner retries), audited, and failures alert the
-- Owner. Staff-visible only; clients never see it.
create table public.asset_object_deletions (
  id uuid primary key default gen_random_uuid(),
  upload_id uuid not null unique references public.asset_uploads (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  object_path text not null unique,
  reason text not null check (reason in ('malware_detected', 'identical_malicious_content')),
  status text not null default 'pending' check (status in ('pending', 'deleted', 'failed')),
  attempts integer not null default 0 check (attempts between 0 and 15),
  manual_retries integer not null default 0 check (manual_retries between 0 and 10),
  next_attempt_at timestamptz not null default now(),
  leased_until timestamptz,
  last_error text check (last_error is null or last_error ~ '^[a-z_]{1,60}$'),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint asset_object_deletions_path check (object_path = project_id || '/assets/' || upload_id),
  constraint asset_object_deletions_done check ((status = 'deleted') = (completed_at is not null)),
  constraint asset_object_deletions_bounded check (attempts <= 5 + manual_retries)
);
create index asset_object_deletions_due_idx on public.asset_object_deletions (next_attempt_at) where status = 'pending';

create function private.object_deletion_max_attempts() returns integer
language sql immutable set search_path = '' as $$ select 5 $$;

create function private.asset_object_deletions_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'deletion records are not deleted' using errcode = '42501';
  end if;
  if (new.id, new.upload_id, new.project_id, new.object_path, new.reason, new.created_at)
     is distinct from (old.id, old.upload_id, old.project_id, old.object_path, old.reason, old.created_at)
     or old.status = 'deleted'
     or new.attempts < old.attempts or new.manual_retries < old.manual_retries then
    raise exception 'invalid deletion record change' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger asset_object_deletions_guard before update or delete on public.asset_object_deletions
  for each row execute function private.asset_object_deletions_guard();

-- Scanners permitted to release a file from quarantine in this database (DEP-07). The
-- mocked scanner only in a development or test database. No production scanner exists.
create function private.scanner_permitted(p_scanner text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_scanner = 'mock_scanner'
     and exists (select 1 from private.runtime_environment where app_env in ('development', 'test'));
$$;

create function private.wpc_is_service_role() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select auth.jwt()) ->> 'role', '') = 'service_role';
$$;

-- Quota usage, counting every upload that still holds or may hold storage.
create function private.upload_quota_usage(p_project_id uuid, out files integer, out bytes bigint)
language sql stable security definer set search_path = '' as $$
  select count(*)::integer, coalesce(sum(coalesce(u.size_bytes, u.declared_bytes)), 0)::bigint
  from public.asset_uploads u
  where u.project_id = p_project_id and u.status not in ('failed_upload', 'rejected');
$$;

create function private.upload_quota_limits(p_project_id uuid, out files integer, out bytes bigint)
language sql stable security definer set search_path = '' as $$
  select private.upload_quota_files() + coalesce(sum(e.extra_files), 0)::integer,
         private.upload_quota_bytes() + coalesce(sum(e.extra_bytes), 0)::bigint
  from public.upload_exceptions e
  where e.project_id = p_project_id and e.kind = 'quota' and e.status = 'approved';
$$;

-- Reserves quota and creates the upload record before any byte is stored (05 §5.3 rule 7:
-- checked at issuance and again at completion, serialized per project). Returns the only
-- path the server may write: the project's quarantine area.
-- A refused upload request by an authorized caller is part of the project's upload history
-- (05 §4: upload and access history are audited): one `upload.refused` event, nothing
-- reserved. A caller without access to the project is refused before this and leaves no
-- record in that project.
create function private.refuse_upload(p_project_id uuid, p_code text, p_category public.upload_category,
  p_mime text, p_bytes bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.record_audit_event('upload.refused', 'projects', p_project_id::text, p_project_id, null,
    jsonb_build_object('code', p_code, 'category', p_category, 'declared_mime', left(p_mime, 100),
      'declared_bytes', p_bytes));
  return private.fail(p_code);
end;
$$;

create function private.request_upload(
  p_project_id uuid,
  p_category public.upload_category,
  p_mime text,
  p_bytes bigint,
  p_original_name text,
  p_replaces_asset_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_max bigint;
  v_exception uuid;
  v_usage record;
  v_limits record;
  v_id uuid := gen_random_uuid();
  v_asset uuid;
  v_version integer := 1;
  v_name text := left(regexp_replace(btrim(coalesce(p_original_name, '')), '[/\\[:cntrl:]]', '_', 'g'), 200);
begin
  if not (private.wpc_is_client_member(p_project_id)
          or (private.wpc_is_staff_aal2() and exists (select 1 from public.projects where id = p_project_id))) then
    return private.fail('forbidden');
  end if;
  if v_name = '' or p_bytes is null or p_bytes < 1 then
    return private.refuse_upload(p_project_id, 'invalid_input', p_category, p_mime, p_bytes);
  end if;
  if p_category = 'other' then
    select e.id, e.max_bytes into v_exception, v_max from public.upload_exceptions e
     where e.project_id = p_project_id and e.kind = 'file_type' and e.status = 'approved'
       and e.requested_mime = p_mime
     order by e.decided_at desc limit 1;
    if v_exception is null then
      return private.refuse_upload(p_project_id, 'type_exception_required', p_category, p_mime, p_bytes);
    end if;
  else
    v_max := private.upload_max_bytes(p_category, p_mime);
    if v_max is null then
      return private.refuse_upload(p_project_id, 'type_not_allowed', p_category, p_mime, p_bytes);
    end if;
  end if;
  if p_bytes > v_max then
    return private.refuse_upload(p_project_id, 'file_too_large', p_category, p_mime, p_bytes);
  end if;
  -- Preconditions after input validation, so a disallowed type or size is reported as such
  -- (both are refusals; neither order lets anything through).
  if not private.wpc_intake_unlocked(p_project_id) then
    return private.refuse_upload(p_project_id, 'intake_locked', p_category, p_mime, p_bytes);
  end if;
  if exists (select 1 from public.projects where id = p_project_id and archived_at is not null) then
    return private.refuse_upload(p_project_id, 'project_archived', p_category, p_mime, p_bytes);
  end if;

  perform pg_advisory_xact_lock(hashtextextended('uploads:' || p_project_id::text, 0));
  select * into v_usage from private.upload_quota_usage(p_project_id);
  select * into v_limits from private.upload_quota_limits(p_project_id);
  if v_usage.files + 1 > v_limits.files then
    return private.refuse_upload(p_project_id, 'quota_files', p_category, p_mime, p_bytes);
  end if;
  if v_usage.bytes + p_bytes > v_limits.bytes then
    return private.refuse_upload(p_project_id, 'quota_bytes', p_category, p_mime, p_bytes);
  end if;

  if p_replaces_asset_id is not null then
    select u.asset_id, max(u.version) + 1 into v_asset, v_version from public.asset_uploads u
     where u.asset_id = p_replaces_asset_id and u.project_id = p_project_id group by u.asset_id;
    if v_asset is null then
      return private.refuse_upload(p_project_id, 'not_found', p_category, p_mime, p_bytes);
    end if;
  else
    v_asset := gen_random_uuid();
  end if;

  insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
    original_name, exception_id, quarantine_path, uploaded_by)
  values (v_id, p_project_id, v_asset, v_version, p_category, p_mime, p_bytes, v_name, v_exception,
    'quarantine/' || p_project_id || '/' || v_id, (select auth.uid()));
  perform private.record_audit_event('upload.requested', 'asset_uploads', v_id::text, p_project_id, null,
    jsonb_build_object('category', p_category, 'declared_mime', p_mime, 'declared_bytes', p_bytes, 'version', v_version));
  return jsonb_build_object('ok', true, 'upload_id', v_id, 'asset_id', v_asset, 'version', v_version,
    'quarantine_path', 'quarantine/' || p_project_id || '/' || v_id, 'max_bytes', v_max);
exception
  when check_violation or invalid_text_representation then
    return private.refuse_upload(p_project_id, 'invalid_input', p_category, p_mime, p_bytes);
end;
$$;

-- Rejection with an audit record and actionable notifications to the client and staff
-- (05 §5.3 rule 2; OI-31). Internal: called by the service-role pipeline functions.
create function private.reject_upload_internal(p_upload public.asset_uploads, p_code text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.asset_uploads set status = 'rejected', rejection_code = p_code where id = p_upload.id;
  perform private.record_audit_event('upload.rejected', 'asset_uploads', p_upload.id::text, p_upload.project_id,
    null, jsonb_build_object('code', p_code, 'category', p_upload.category));
  perform private.enqueue_notification('upload.rejected', 'upload.rejected:' || p_upload.id || ':1',
    'upload_rejected', 1, p_upload.project_id, null, array[p_upload.uploaded_by],
    array['staff']::public.notification_recipient_role[],
    jsonb_build_object('upload_id', p_upload.id, 'code', p_code, 'guidance', 're_upload'));
end;
$$;

-- Server pipeline (service_role only). The server authorizes the uploader first, writes the
-- bytes to the quarantine path with the secret key, then reports what it stored.
create function private.complete_upload(p_upload_id uuid, p_size_bytes bigint, p_sha256 text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
  v_usage record;
  v_limits record;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.status <> 'uploading' then
    return private.fail('not_found');
  end if;
  if now() > v.upload_expires_at then
    update public.asset_uploads set status = 'failed_upload' where id = v.id;
    perform private.record_audit_event('upload.failed', 'asset_uploads', v.id::text, v.project_id, null,
      jsonb_build_object('code', 'expired'));
    return private.fail('expired');
  end if;
  if p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > v.declared_bytes
     or coalesce(p_sha256, '') !~ '^[0-9a-f]{64}$' then
    update public.asset_uploads set status = 'failed_upload' where id = v.id;
    perform private.record_audit_event('upload.failed', 'asset_uploads', v.id::text, v.project_id, null,
      jsonb_build_object('code', 'size_mismatch'));
    return private.fail('size_mismatch');
  end if;
  -- Completion re-check of the quota with the actual size (05 §5.3 rule 7).
  perform pg_advisory_xact_lock(hashtextextended('uploads:' || v.project_id::text, 0));
  select * into v_usage from private.upload_quota_usage(v.project_id);
  select * into v_limits from private.upload_quota_limits(v.project_id);
  if v_usage.bytes - v.declared_bytes + p_size_bytes > v_limits.bytes then
    update public.asset_uploads set status = 'failed_upload' where id = v.id;
    return private.fail('quota_bytes');
  end if;
  update public.asset_uploads
     set status = 'quarantined', size_bytes = p_size_bytes, sha256 = p_sha256, completed_at = now()
   where id = v.id;
  perform private.record_audit_event('upload.completed', 'asset_uploads', v.id::text, v.project_id, null,
    jsonb_build_object('size_bytes', p_size_bytes));
  return jsonb_build_object('ok', true, 'status', 'quarantined');
end;
$$;

create function private.fail_upload(p_upload_id uuid, p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.status <> 'uploading' then
    return private.fail('not_found');
  end if;
  update public.asset_uploads set status = 'failed_upload' where id = v.id;
  perform private.record_audit_event('upload.failed', 'asset_uploads', v.id::text, v.project_id, null,
    jsonb_build_object('code', left(coalesce(p_code, 'error'), 60)));
  return jsonb_build_object('ok', true);
end;
$$;

-- Bounded scan retries (05 §5.4 item 8): at most 5 attempts. After a scanner error the next
-- attempt waits, on the approved outbox schedule (07 §3: 1 min, 5 min, 30 min, 2 h, 12 h).
-- After the last failure the file stays quarantined and goes to the Upload review queue.
create function private.scan_max_attempts() returns integer language sql immutable set search_path = '' as $$ select 5 $$;
create function private.scan_retry_backoff(p_failures integer) returns interval
language sql immutable set search_path = '' as $$
  select (array[interval '1 minute', interval '5 minutes', interval '30 minutes', interval '2 hours',
                interval '12 hours'])[least(greatest(p_failures, 1), 5)];
$$;

-- Opens a new scan attempt and moves the upload to scanning (05 §5.5 rule 2). Internal.
create function private.open_scan_attempt(p_upload public.asset_uploads) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  insert into public.upload_scan_attempts (upload_id, project_id, attempt_number, expected_sha256)
  values (p_upload.id, p_upload.project_id,
          (select coalesce(max(a.attempt_number), 0) + 1 from public.upload_scan_attempts a where a.upload_id = p_upload.id),
          p_upload.sha256)
  returning id into v_id;
  update public.asset_uploads set status = 'scanning', current_scan_attempt_id = v_id, source_verified_attempt_id = null
   where id = p_upload.id;
  return v_id;
end;
$$;

-- Content validation result (magic bytes, polyglots; 05 §5.3 rule 1). A failure rejects;
-- a pass opens a scan attempt. The file stays in quarantine either way. A retry after a
-- failed attempt passes through here again (the server re-reads and re-validates the
-- stored object) and is refused while backing off or once the attempts are exhausted.
create function private.record_content_check(p_upload_id uuid, p_passed boolean, p_detected_mime text, p_code text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
  v_attempt uuid;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.status <> 'quarantined' or v.malware_detected then
    return private.fail('not_found');
  end if;
  -- Bytes already found malicious in any upload are rejected permanently (05 §5.5 rule 3).
  if exists (select 1 from private.malicious_content m where m.sha256 = v.sha256) then
    update public.asset_uploads set status = 'rejected', rejection_code = 'malware_detected', malware_detected = true
     where id = v.id;
    perform private.reject_upload_internal(v, 'malware_detected');
    return jsonb_build_object('ok', true, 'status', 'rejected');
  end if;
  if not coalesce(p_passed, false) then
    perform private.reject_upload_internal(v, coalesce(nullif(p_code, ''), 'content_invalid'));
    return jsonb_build_object('ok', true, 'status', 'rejected');
  end if;
  if v.scan_failures >= private.scan_max_attempts() then
    return private.fail('scan_retries_exhausted');
  end if;
  if v.next_scan_at is not null and v.next_scan_at > now() then
    return jsonb_build_object('ok', false, 'error', 'scan_backoff', 'next_scan_at', v.next_scan_at);
  end if;
  update public.asset_uploads set detected_mime = left(p_detected_mime, 100) where id = v.id;
  v_attempt := private.open_scan_attempt(v);
  return jsonb_build_object('ok', true, 'status', 'scanning', 'attempt_id', v_attempt);
end;
$$;

-- Revokes access to a released file after a malicious verdict for its bytes (05 §5.5 rule 3).
-- From this commit on, `record_asset_access` refuses the file, so the server-mediated
-- download route never reads it again; user JWTs can never read released objects at all
-- (`project_assets_released_server_read_only`). The pending deletion row is written in
-- the same transaction, so the object's deletion cannot be lost (H1). Every alert and
-- notification names only the affected upload in its own project (M1: no cross-tenant
-- information, even when the verdict came from another project's identical bytes).
create function private.revoke_released_upload(p_upload public.asset_uploads, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_deletion uuid;
begin
  update public.asset_uploads
     set status = 'rejected', rejection_code = 'malware_detected', malware_detected = true, revoked_at = now()
   where id = p_upload.id;
  insert into public.asset_object_deletions (upload_id, project_id, object_path, reason)
  values (p_upload.id, p_upload.project_id, p_upload.released_path, p_reason)
  on conflict (upload_id) do nothing
  returning id into v_deletion;
  perform private.record_audit_event('upload.access_revoked', 'asset_uploads', p_upload.id::text, p_upload.project_id,
    null, jsonb_build_object('reason', p_reason, 'used', p_upload.used, 'deletion_id', v_deletion));
  perform private.enqueue_notification('upload.access_revoked', 'upload.access_revoked:' || p_upload.id || ':1',
    'upload_access_revoked', 1, p_upload.project_id, null, '{}', array['owner']::public.notification_recipient_role[],
    jsonb_build_object('upload_id', p_upload.id, 'used', p_upload.used, 'reason', p_reason));
  perform private.enqueue_notification('upload.rejected', 'upload.rejected:' || p_upload.id || ':1',
    'upload_rejected', 1, p_upload.project_id, null, array[p_upload.uploaded_by],
    array['staff']::public.notification_recipient_role[],
    jsonb_build_object('upload_id', p_upload.id, 'code', 'malware_detected', 'guidance', 're_upload'));
  return v_deletion;
end;
$$;

-- Applies a malicious verdict to every upload holding the same stored bytes (M1), inside the
-- caller's transaction, which already holds the content lock for p_sha256:
--   - the hash is recorded permanently;
--   - every `available` upload with these bytes, in any project, is revoked, each with its
--     own pending deletion row;
--   - every non-final upload (quarantined, scanning, processing) with these bytes is
--     rejected and its open scan attempt closed;
--   - every already-rejected upload with these bytes is flagged, so it can never be released.
-- Uploads still `uploading` have no stored hash yet; they are rejected at their content
-- check (`record_content_check`), and release refuses them in any case.
create function private.apply_malicious_content(p_sha256 text, p_source_upload_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.asset_uploads;
  v_revoked uuid[] := '{}';
  v_rejected uuid[] := '{}';
  v_deletions uuid[] := '{}';
  v_deletion uuid;
begin
  insert into private.malicious_content (sha256, first_upload_id) values (p_sha256, p_source_upload_id)
  on conflict (sha256) do nothing;
  for r in select * from public.asset_uploads u where u.sha256 = p_sha256 and u.status = 'available'
            order by u.id for update loop
    v_deletion := private.revoke_released_upload(r,
      case when r.id = p_source_upload_id then 'malware_detected' else 'identical_malicious_content' end);
    v_revoked := v_revoked || r.id;
    if v_deletion is not null then
      v_deletions := v_deletions || v_deletion;
    end if;
  end loop;
  for r in select * from public.asset_uploads u where u.sha256 = p_sha256
              and u.status in ('quarantined', 'scanning', 'processing')
            order by u.id for update loop
    update public.upload_scan_attempts set closed_at = now(), outcome = 'malicious'
     where upload_id = r.id and closed_at is null;
    update public.asset_uploads set status = 'rejected', rejection_code = 'malware_detected', malware_detected = true
     where id = r.id;
    perform private.reject_upload_internal(r, 'malware_detected');
    v_rejected := v_rejected || r.id;
  end loop;
  update public.asset_uploads set malware_detected = true
   where sha256 = p_sha256 and status = 'rejected' and not malware_detected;
  return jsonb_build_object('revoked', to_jsonb(v_revoked), 'rejected', to_jsonb(v_rejected),
    'deletion_ids', to_jsonb(v_deletions));
end;
$$;

-- Scan evidence (service_role only; AUTH-004: no client self-certification), 05 §5.5.
--   1. The upload row is locked before anything is inserted, so `seq` is the acceptance order
--      and two submissions for one upload never interleave.
--   2. Only a result naming the upload's current, still-open attempt while it is `scanning`
--      may act. Results for an earlier or unknown attempt, duplicates, and results arriving
--      in any other state are stored as non-authoritative and change nothing.
--   3. Exception: `malicious` always acts, from any attempt, in any state but terminal
--      rejection or failure; a released file is revoked. Release is then blocked forever.
--   4. `error`, an unpermitted scanner, a hash that differs from the stored object, or an
--      unrecognized verdict closes the attempt and returns the file to quarantine; only a
--      clean result of a newer attempt can count after that.
create function private.record_scan_result(
  p_upload_id uuid, p_attempt_id uuid, p_scanner text, p_engine_version text, p_verdict text,
  p_scanned_sha256 text, p_signature text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
  v_attempt public.upload_scan_attempts;
  v_verdict text := case when p_verdict in ('clean', 'malicious', 'error') then p_verdict else 'invalid' end;
  v_hash_ok boolean;
  v_disposition text;
  v_outcome text;
  v_hash text;
  v_prior public.upload_status;
  v_applied jsonb;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  -- Content lock first, then the row lock (M1). The stored hash never changes once set.
  select u.sha256 into v_hash from public.asset_uploads u where u.id = p_upload_id;
  if v_hash is null then
    return private.fail('not_found');
  end if;
  perform private.content_lock(v_hash);
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.sha256 is distinct from v_hash then
    return private.fail('not_found');
  end if;
  select * into v_attempt from public.upload_scan_attempts where id = p_attempt_id and upload_id = v.id;
  v_hash_ok := coalesce(p_scanned_sha256 = v.sha256, false);

  -- Malware always wins (rule 3). The verdict applies to the stored bytes (`v.sha256`),
  -- whatever hash the scanner reported; the reported hash is kept as evidence only.
  if v_verdict = 'malicious' then
    insert into public.upload_scan_results (upload_id, project_id, attempt_id, claimed_attempt_id, scanner,
      engine_version, verdict, signature, scanned_sha256, hash_matches, authoritative, disposition)
    values (v.id, v.project_id, v_attempt.id, p_attempt_id, p_scanner, p_engine_version, 'malicious',
      left(p_signature, 200), coalesce(p_scanned_sha256, v.sha256), v_hash_ok, true, 'malicious_accepted');
    perform private.record_audit_event('upload.scan_recorded', 'asset_uploads', v.id::text, v.project_id, null,
      jsonb_build_object('scanner', p_scanner, 'verdict', 'malicious', 'attempt_id', p_attempt_id,
        'authoritative', true, 'prior_status', v.status, 'hash_matches', v_hash_ok));
    update public.upload_scan_attempts set closed_at = now(), outcome = 'malicious'
     where upload_id = v.id and closed_at is null;
    v_prior := v.status;
    v_applied := private.apply_malicious_content(v.sha256, v.id);
    return jsonb_build_object('ok', true, 'status', 'rejected', 'revoked', v_prior = 'available',
      'released_path', case when v_prior = 'available' then v.released_path end,
      'revoked_count', jsonb_array_length(v_applied -> 'revoked'),
      'rejected_count', jsonb_array_length(v_applied -> 'rejected'),
      'deletion_ids', v_applied -> 'deletion_ids');
  end if;

  -- Non-authoritative results (rule 2). A non-clean result for the current attempt still
  -- acts after that attempt's clean result while the file is not yet released (`processing`):
  -- a clean result followed by an error, an invalid result, a hash mismatch, or an
  -- unpermitted scanner returns the file to quarantine (T-UP-17). A repeated clean is a
  -- duplicate and never acts.
  v_disposition := case
    when v_attempt.id is null then 'unknown_attempt'
    when v_attempt.id is distinct from v.current_scan_attempt_id then 'stale_attempt'
    when v.status = 'scanning' and v_attempt.closed_at is null then null
    when v.status = 'processing' and not (v_verdict = 'clean' and v_hash_ok and private.scanner_permitted(p_scanner)) then null
    when v.status in ('scanning', 'processing') then 'duplicate'
    else 'not_scanning'
  end;
  if v_disposition is not null then
    insert into public.upload_scan_results (upload_id, project_id, attempt_id, claimed_attempt_id, scanner,
      engine_version, verdict, signature, scanned_sha256, hash_matches, authoritative, disposition)
    values (v.id, v.project_id, v_attempt.id, p_attempt_id, p_scanner, p_engine_version, v_verdict,
      left(p_signature, 200), coalesce(p_scanned_sha256, repeat('0', 64)), v_hash_ok, false, v_disposition);
    perform private.record_audit_event('upload.scan_recorded', 'asset_uploads', v.id::text, v.project_id, null,
      jsonb_build_object('scanner', p_scanner, 'verdict', v_verdict, 'attempt_id', p_attempt_id,
        'authoritative', false, 'disposition', v_disposition));
    return jsonb_build_object('ok', true, 'status', v.status, 'authoritative', false, 'disposition', v_disposition);
  end if;

  -- The current attempt (rules 4 and 5).
  v_disposition := case
    when not v_hash_ok then 'hash_mismatch'
    when v_verdict = 'invalid' then 'invalid_result'
    when v_verdict = 'error' then 'error_quarantined'
    when not private.scanner_permitted(p_scanner) then 'scanner_not_permitted'
    else 'clean_accepted'
  end;
  v_outcome := case v_disposition when 'clean_accepted' then 'clean' when 'error_quarantined' then 'error'
    when 'invalid_result' then 'invalid' else v_disposition end;
  insert into public.upload_scan_results (upload_id, project_id, attempt_id, claimed_attempt_id, scanner,
    engine_version, verdict, signature, scanned_sha256, hash_matches, authoritative, disposition)
  values (v.id, v.project_id, v_attempt.id, p_attempt_id, p_scanner, p_engine_version, v_verdict,
    left(p_signature, 200), coalesce(p_scanned_sha256, repeat('0', 64)), v_hash_ok, true, v_disposition);
  update public.upload_scan_attempts set closed_at = now(), outcome = v_outcome
   where id = v_attempt.id and closed_at is null;
  perform private.record_audit_event('upload.scan_recorded', 'asset_uploads', v.id::text, v.project_id, null,
    jsonb_build_object('scanner', p_scanner, 'verdict', v_verdict, 'attempt_id', p_attempt_id,
      'authoritative', true, 'disposition', v_disposition));

  if v_disposition = 'clean_accepted' then
    update public.asset_uploads set status = 'processing', scan_failures = 0, next_scan_at = null where id = v.id;
    return jsonb_build_object('ok', true, 'status', 'processing', 'authoritative', true);
  end if;
  update public.asset_uploads
     set status = 'quarantined', scan_failures = least(v.scan_failures + 1, private.scan_max_attempts()),
         next_scan_at = case when v_disposition = 'error_quarantined'
                             then now() + private.scan_retry_backoff(v.scan_failures + 1) end
   where id = v.id;
  if v_disposition = 'hash_mismatch' then
    return jsonb_build_object('ok', false, 'error', 'hash_mismatch', 'status', 'quarantined');
  end if;
  return jsonb_build_object('ok', true, 'status', 'quarantined', 'authoritative', true,
    'held', case when v_disposition = 'scanner_not_permitted' then 'scanner_not_permitted' end,
    'retries_exhausted', v.scan_failures + 1 >= private.scan_max_attempts());
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

-- The authoritative scan result for an upload: the last authoritative result by sequence.
create function private.authoritative_scan(p_upload_id uuid) returns public.upload_scan_results
language sql stable security definer set search_path = '' as $$
  select r.* from public.upload_scan_results r
  where r.upload_id = p_upload_id and r.authoritative
  order by r.seq desc limit 1;
$$;

-- Processing re-reads the stored quarantine object and reports its server-computed hash
-- before producing a derivative (05 §5.5 rule 5). A different hash means the stored object
-- changed after scanning: the upload is rejected and can never be released.
create function private.confirm_source_hash(p_upload_id uuid, p_sha256 text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.status <> 'processing' then
    return private.fail('not_found');
  end if;
  if p_sha256 is distinct from v.sha256 then
    perform private.reject_upload_internal(v, 'stored_object_changed');
    return jsonb_build_object('ok', false, 'error', 'stored_object_changed', 'status', 'rejected');
  end if;
  update public.asset_uploads set source_verified_attempt_id = v.current_scan_attempt_id where id = v.id;
  return jsonb_build_object('ok', true);
end;
$$;

-- Release (05 §5.5 rule 6). All of: status `processing`; the authoritative result (last by
-- sequence) is a clean result of the current attempt, by a permitted scanner, for the exact
-- stored bytes; processing confirmed the stored object's hash for that attempt; and no
-- malicious result has ever been recorded for these bytes, for this or any upload. The
-- released hash is computed by the server from the object it wrote to the released path.
create function private.release_upload(
  p_upload_id uuid, p_released_sha256 text, p_released_bytes bigint
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
  v_scan public.upload_scan_results;
  v_hash text;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  -- Content lock first, then the row lock (M1): a concurrent malicious verdict for identical
  -- bytes either commits first (and is seen below) or waits for this release and revokes it.
  select u.sha256 into v_hash from public.asset_uploads u where u.id = p_upload_id;
  if v_hash is null then
    return private.fail('not_found');
  end if;
  perform private.content_lock(v_hash);
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.status <> 'processing' or v.sha256 is distinct from v_hash then
    return private.fail('not_found');
  end if;
  v_scan := private.authoritative_scan(v.id);
  if v_scan.disposition is distinct from 'clean_accepted' or v_scan.verdict is distinct from 'clean'
     or v_scan.attempt_id is distinct from v.current_scan_attempt_id
     or v_scan.scanned_sha256 is distinct from v.sha256 or not v_scan.hash_matches
     or not private.scanner_permitted(v_scan.scanner) then
    return private.fail('scan_not_clean');
  end if;
  -- Known malicious bytes (by stored hash), any malicious result for this upload, or (kept
  -- from before, conservative) any malicious result that reported these bytes' hash.
  if v.malware_detected
     or exists (select 1 from private.malicious_content m where m.sha256 = v.sha256)
     or exists (select 1 from public.upload_scan_results m where m.verdict = 'malicious'
                 and (m.upload_id = v.id or m.scanned_sha256 = v.sha256)) then
    return private.fail('malware_detected');
  end if;
  if v.source_verified_attempt_id is distinct from v.current_scan_attempt_id then
    return private.fail('source_not_verified');
  end if;
  update public.asset_uploads
     set status = 'available', released_path = v.project_id || '/assets/' || v.id,
         released_sha256 = p_released_sha256, released_bytes = p_released_bytes
   where id = v.id;
  perform private.record_audit_event('upload.released', 'asset_uploads', v.id::text, v.project_id, null,
    jsonb_build_object('released_bytes', p_released_bytes, 'attempt_id', v.current_scan_attempt_id));
  return jsonb_build_object('ok', true, 'status', 'available',
    'released_path', v.project_id || '/assets/' || v.id);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.record_processing_outcome(p_upload_id uuid, p_outcome text, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  select * into v from public.asset_uploads where id = p_upload_id for update;
  if not found or v.status <> 'processing' then
    return private.fail('not_found');
  end if;
  if p_outcome = 'rejected' then
    perform private.reject_upload_internal(v, coalesce(nullif(p_note, ''), 'processing_failed'));
    return jsonb_build_object('ok', true, 'status', 'rejected');
  elsif p_outcome = 'held' then
    update public.asset_uploads set processing_note = left(p_note, 60) where id = v.id;
    return jsonb_build_object('ok', true, 'status', 'processing');
  end if;
  return private.fail('invalid_input');
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

-- Retention (05 §5.3; T-UP-07): uploads never completed expire to failed_upload, and
-- failed uploads are purged after 7 days. Returns the quarantine paths whose objects the
-- server then deletes. Service role only (scheduled job in R2; manual or test in R1).
create function private.purge_failed_uploads() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_paths text[] := '{}';
  r record;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  update public.asset_uploads set status = 'failed_upload'
   where status = 'uploading' and upload_expires_at < now();
  for r in
    update public.asset_uploads set purged_at = now()
     where status = 'failed_upload' and purged_at is null and status_changed_at < now() - interval '7 days'
    returning id, project_id, quarantine_path
  loop
    perform private.record_audit_event('upload.purged', 'asset_uploads', r.id::text, r.project_id);
    v_paths := v_paths || r.quarantine_path;
  end loop;
  return jsonb_build_object('ok', true, 'paths', to_jsonb(v_paths));
end;
$$;

-- Records a download of an available asset (05 §4: access history is audited). The caller
-- must be able to access the project; only available assets are ever served.
create function private.record_asset_access(p_upload_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.asset_uploads;
begin
  select * into v from public.asset_uploads where id = p_upload_id;
  if not found or not private.can_access_project(v.project_id) or not private.session_is_active()
     or (private.is_staff() and not private.is_aal2()) then
    return private.fail('not_found');
  end if;
  if v.status <> 'available' then
    return private.fail('not_available');
  end if;
  perform private.record_audit_event('upload.accessed', 'asset_uploads', v.id::text, v.project_id);
  return jsonb_build_object('ok', true, 'released_path', v.released_path, 'mime',
    coalesce(v.detected_mime, v.declared_mime), 'name', v.original_name);
end;
$$;

-- Deletion of revoked released objects (H1). The server claims due rows, deletes each object
-- with the secret key, confirms it is gone, and reports the outcome here.
--   claim:  a lease of 5 minutes per row and one counted attempt. A row whose lease expired
--           without an outcome was interrupted; it is claimed again (last_error
--           'interrupted'), and once its attempts are spent it fails and alerts the Owner.
--   report: `deleted` is accepted from any attempt (deleting is idempotent and the object's
--           absence was confirmed); a failure counts only for the current attempt, backs
--           off on the 07 §3 schedule, alerts the Owner, and after the last attempt fails
--           the row until an Owner retry.
create function private.object_deletion_failed_internal(p_row public.asset_object_deletions, p_error text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_exhausted boolean := p_row.attempts >= private.object_deletion_max_attempts() + p_row.manual_retries;
begin
  update public.asset_object_deletions
     set status = case when v_exhausted then 'failed' else 'pending' end,
         last_error = p_error, leased_until = null,
         next_attempt_at = case when v_exhausted then next_attempt_at
                                else now() + private.scan_retry_backoff(p_row.attempts) end
   where id = p_row.id;
  perform private.record_audit_event('upload.object_deletion_failed', 'asset_object_deletions', p_row.id::text,
    p_row.project_id, null, jsonb_build_object('upload_id', p_row.upload_id, 'attempt', p_row.attempts,
      'error', p_error, 'exhausted', v_exhausted));
  perform private.enqueue_notification('upload.object_deletion_failed',
    'upload.object_deletion_failed:' || p_row.id || ':' || p_row.attempts,
    'upload_object_deletion_failed', 1, p_row.project_id, null, '{}', array['owner']::public.notification_recipient_role[],
    jsonb_build_object('deletion_id', p_row.id, 'upload_id', p_row.upload_id, 'attempt', p_row.attempts,
      'exhausted', v_exhausted));
end;
$$;

create function private.claim_object_deletions(p_ids uuid[] default null, p_limit integer default 10) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.asset_object_deletions;
  v_claimed jsonb := '[]'::jsonb;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  -- Interrupted on their last attempt: fail and alert (never left pending forever).
  for r in select * from public.asset_object_deletions d
            where d.status = 'pending' and d.leased_until < now()
              and d.attempts >= private.object_deletion_max_attempts() + d.manual_retries
              and (p_ids is null or d.id = any(p_ids))
            for update skip locked loop
    perform private.object_deletion_failed_internal(r, 'interrupted');
  end loop;
  for r in select * from public.asset_object_deletions d
            where d.status = 'pending' and d.next_attempt_at <= now()
              and (d.leased_until is null or d.leased_until < now())
              and d.attempts < private.object_deletion_max_attempts() + d.manual_retries
              and (p_ids is null or d.id = any(p_ids))
            order by d.created_at
            limit least(greatest(coalesce(p_limit, 10), 1), 50)
            for update skip locked loop
    update public.asset_object_deletions
       set attempts = attempts + 1, leased_until = now() + interval '5 minutes',
           last_error = case when r.leased_until is not null then 'interrupted' else last_error end
     where id = r.id;
    v_claimed := v_claimed || jsonb_build_object('id', r.id, 'object_path', r.object_path, 'attempt', r.attempts + 1);
  end loop;
  return jsonb_build_object('ok', true, 'claimed', v_claimed);
end;
$$;

create function private.record_object_deletion(p_deletion_id uuid, p_attempt integer, p_deleted boolean, p_error text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.asset_object_deletions;
begin
  if not private.wpc_is_service_role() then
    return private.fail('forbidden');
  end if;
  select * into r from public.asset_object_deletions where id = p_deletion_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if r.status = 'deleted' then
    return jsonb_build_object('ok', true, 'status', 'deleted', 'already', true);
  end if;
  if coalesce(p_deleted, false) then
    update public.asset_object_deletions
       set status = 'deleted', completed_at = now(), leased_until = null, last_error = null
     where id = r.id;
    perform private.record_audit_event('upload.object_deleted', 'asset_object_deletions', r.id::text, r.project_id,
      null, jsonb_build_object('upload_id', r.upload_id, 'attempt', p_attempt, 'reason', r.reason));
    return jsonb_build_object('ok', true, 'status', 'deleted');
  end if;
  if r.status <> 'pending' or p_attempt is distinct from r.attempts or r.leased_until is null then
    return jsonb_build_object('ok', false, 'error', 'stale_attempt', 'status', r.status);
  end if;
  perform private.object_deletion_failed_internal(r,
    case when coalesce(p_error, '') ~ '^[a-z_]{1,60}$' then p_error else 'storage_error' end);
  return jsonb_build_object('ok', true, 'status',
    (select d.status from public.asset_object_deletions d where d.id = r.id));
end;
$$;

-- Owner retry of a pending or failed deletion (H1), until hosted scheduling exists (DEP-17).
-- Owner at aal2 with a live session; audited; at most 10 per object, each allowing one more
-- attempt. Refused while an attempt holds a live lease.
create function private.retry_object_deletion(p_deletion_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r public.asset_object_deletions;
begin
  if not (private.is_owner() and private.is_aal2() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  select * into r from public.asset_object_deletions where id = p_deletion_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if r.status = 'deleted' then
    return private.fail('already_deleted');
  end if;
  if r.leased_until is not null and r.leased_until >= now() then
    return private.fail('deletion_in_progress');
  end if;
  if r.manual_retries >= 10 then
    return private.fail('retry_limit');
  end if;
  update public.asset_object_deletions
     set status = 'pending', manual_retries = manual_retries + 1, next_attempt_at = now()
   where id = r.id;
  perform private.record_audit_event('upload.object_deletion_retried', 'asset_object_deletions', r.id::text,
    r.project_id, null, jsonb_build_object('upload_id', r.upload_id, 'manual_retry', r.manual_retries + 1,
      'prior_status', r.status));
  return jsonb_build_object('ok', true, 'deletion_id', r.id);
end;
$$;

create function private.request_upload_exception(
  p_project_id uuid, p_kind text, p_requested_mime text, p_max_bytes bigint,
  p_extra_files integer, p_extra_bytes bigint, p_justification text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not (private.wpc_is_client_member(p_project_id)
          or (private.wpc_is_staff_aal2() and exists (select 1 from public.projects where id = p_project_id))) then
    return private.fail('forbidden');
  end if;
  insert into public.upload_exceptions (project_id, kind, requested_mime, max_bytes, extra_files, extra_bytes,
    justification, requested_by)
  values (p_project_id, p_kind, p_requested_mime, p_max_bytes, p_extra_files, p_extra_bytes,
    btrim(p_justification), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('upload.exception_requested', 'upload_exceptions', v_id::text, p_project_id,
    null, jsonb_build_object('kind', p_kind));
  return jsonb_build_object('ok', true, 'exception_id', v_id);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.decide_upload_exception(p_exception_id uuid, p_approve boolean, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.upload_exceptions;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  if not private.wpc_text_ok(p_reason, 1000) then
    return private.fail('reason_required');
  end if;
  select * into v from public.upload_exceptions where id = p_exception_id and status = 'requested' for update;
  if not found then
    return private.fail('not_found');
  end if;
  update public.upload_exceptions
     set status = case when p_approve then 'approved' else 'denied' end,
         decided_by = (select auth.uid()), decided_at = now(), decision_reason = btrim(p_reason)
   where id = v.id;
  perform private.record_audit_event('upload.exception_decided', 'upload_exceptions', v.id::text, v.project_id,
    btrim(p_reason), jsonb_build_object('kind', v.kind, 'approved', p_approve));
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Exposed RPC wrappers (SECURITY INVOKER; definer code stays in private)
-- ---------------------------------------------------------------------------
create function public.save_intake_draft(p_project_id uuid, p_content jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.save_intake_draft(p_project_id, p_content); $$;
create function public.submit_intake(p_project_id uuid, p_draft_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.submit_intake(p_project_id, p_draft_id); $$;
create function public.review_intake(p_submission_id uuid, p_decision text, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.review_intake(p_submission_id, p_decision, p_note); $$;
create function public.correct_intake(p_project_id uuid, p_content jsonb, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.correct_intake(p_project_id, p_content, p_reason); $$;
create function public.get_intake_state(p_project_id uuid) returns public.intake_state
language sql stable security invoker set search_path = '' as $$
  select case when private.can_access_project(p_project_id) then private.intake_state_of(p_project_id) end;
$$;
create function public.request_upload(p_project_id uuid, p_category public.upload_category, p_mime text,
  p_bytes bigint, p_original_name text, p_replaces_asset_id uuid default null) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.request_upload(p_project_id, p_category, p_mime, p_bytes, p_original_name, p_replaces_asset_id);
$$;
create function public.record_asset_access(p_upload_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_asset_access(p_upload_id); $$;
create function public.request_upload_exception(p_project_id uuid, p_kind text, p_requested_mime text,
  p_max_bytes bigint, p_extra_files integer, p_extra_bytes bigint, p_justification text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.request_upload_exception(p_project_id, p_kind, p_requested_mime, p_max_bytes, p_extra_files,
    p_extra_bytes, p_justification);
$$;
create function public.decide_upload_exception(p_exception_id uuid, p_approve boolean, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.decide_upload_exception(p_exception_id, p_approve, p_reason); $$;
-- Server pipeline (secret key only):
create function public.complete_upload(p_upload_id uuid, p_size_bytes bigint, p_sha256 text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.complete_upload(p_upload_id, p_size_bytes, p_sha256); $$;
create function public.fail_upload(p_upload_id uuid, p_code text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.fail_upload(p_upload_id, p_code); $$;
create function public.record_content_check(p_upload_id uuid, p_passed boolean, p_detected_mime text, p_code text)
returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_content_check(p_upload_id, p_passed, p_detected_mime, p_code); $$;
create function public.record_scan_result(p_upload_id uuid, p_attempt_id uuid, p_scanner text, p_engine_version text,
  p_verdict text, p_scanned_sha256 text, p_signature text default null) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_scan_result(p_upload_id, p_attempt_id, p_scanner, p_engine_version, p_verdict, p_scanned_sha256,
    p_signature);
$$;
create function public.confirm_source_hash(p_upload_id uuid, p_sha256 text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.confirm_source_hash(p_upload_id, p_sha256); $$;
create function public.record_processing_outcome(p_upload_id uuid, p_outcome text, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_processing_outcome(p_upload_id, p_outcome, p_note); $$;
create function public.release_upload(p_upload_id uuid, p_released_sha256 text, p_released_bytes bigint) returns jsonb
language sql security invoker set search_path = '' as $$ select private.release_upload(p_upload_id, p_released_sha256, p_released_bytes); $$;
create function public.purge_failed_uploads() returns jsonb
language sql security invoker set search_path = '' as $$ select private.purge_failed_uploads(); $$;
create function public.claim_object_deletions(p_ids uuid[] default null, p_limit integer default 10) returns jsonb
language sql security invoker set search_path = '' as $$ select private.claim_object_deletions(p_ids, p_limit); $$;
create function public.record_object_deletion(p_deletion_id uuid, p_attempt integer, p_deleted boolean, p_error text)
returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_object_deletion(p_deletion_id, p_attempt, p_deleted, p_error); $$;
create function public.retry_object_deletion(p_deletion_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.retry_object_deletion(p_deletion_id); $$;

-- ---------------------------------------------------------------------------
-- 5. Privileges
-- ---------------------------------------------------------------------------
revoke all on function
  private.wpc_is_staff_aal2(), private.wpc_is_client_member(uuid), private.wpc_deposit_verified(uuid), private.wpc_intake_unlocked(uuid),
  private.detroit_days_since(timestamptz), private.wpc_text_ok(text, integer),
  private.intake_allowed_keys(), private.intake_required_keys(), private.intake_content_valid(jsonb),
  private.intake_content_complete(jsonb), private.intake_submissions_guard(), private.wpc_insert_only(),
  private.intake_state_of(uuid), private.save_intake_draft(uuid, jsonb), private.submit_intake(uuid, uuid),
  private.review_intake(uuid, text, text), private.correct_intake(uuid, jsonb, text),
  private.upload_max_bytes(public.upload_category, text), private.upload_quota_files(), private.upload_quota_bytes(),
  private.upload_exceptions_guard(), private.asset_uploads_guard(), private.scanner_permitted(text),
  private.wpc_is_service_role(), private.upload_quota_usage(uuid), private.upload_quota_limits(uuid),
  private.request_upload(uuid, public.upload_category, text, bigint, text, uuid),
  private.reject_upload_internal(public.asset_uploads, text),
  private.complete_upload(uuid, bigint, text), private.fail_upload(uuid, text),
  private.record_content_check(uuid, boolean, text, text),
  private.record_scan_result(uuid, uuid, text, text, text, text, text),
  private.release_upload(uuid, text, bigint), private.record_processing_outcome(uuid, text, text),
  private.purge_failed_uploads(), private.record_asset_access(uuid),
  private.scan_max_attempts(), private.scan_retry_backoff(integer),
  private.open_scan_attempt(public.asset_uploads), private.revoke_released_upload(public.asset_uploads, text),
  private.content_lock(text), private.apply_malicious_content(text, uuid),
  private.refuse_upload(uuid, text, public.upload_category, text, bigint),
  private.object_deletion_max_attempts(), private.asset_object_deletions_guard(),
  private.object_deletion_failed_internal(public.asset_object_deletions, text),
  private.claim_object_deletions(uuid[], integer), private.record_object_deletion(uuid, integer, boolean, text),
  private.retry_object_deletion(uuid),
  private.authoritative_scan(uuid), private.confirm_source_hash(uuid, text), private.upload_scan_attempts_guard(),
  private.request_upload_exception(uuid, text, text, bigint, integer, bigint, text),
  private.decide_upload_exception(uuid, boolean, text)
from public, anon, authenticated, service_role;
revoke all on function
  public.save_intake_draft(uuid, jsonb), public.submit_intake(uuid, uuid), public.review_intake(uuid, text, text),
  public.correct_intake(uuid, jsonb, text), public.get_intake_state(uuid),
  public.request_upload(uuid, public.upload_category, text, bigint, text, uuid), public.record_asset_access(uuid),
  public.request_upload_exception(uuid, text, text, bigint, integer, bigint, text),
  public.decide_upload_exception(uuid, boolean, text),
  public.complete_upload(uuid, bigint, text), public.fail_upload(uuid, text),
  public.record_content_check(uuid, boolean, text, text),
  public.record_scan_result(uuid, uuid, text, text, text, text, text), public.record_processing_outcome(uuid, text, text),
  public.release_upload(uuid, text, bigint), public.purge_failed_uploads(), public.confirm_source_hash(uuid, text),
  public.claim_object_deletions(uuid[], integer), public.record_object_deletion(uuid, integer, boolean, text),
  public.retry_object_deletion(uuid)
from public, anon, authenticated, service_role;

-- End-user actions (authenticated): each definer function re-authorizes the caller.
grant execute on function
  private.save_intake_draft(uuid, jsonb), private.submit_intake(uuid, uuid), private.review_intake(uuid, text, text),
  private.correct_intake(uuid, jsonb, text), private.intake_state_of(uuid),
  private.request_upload(uuid, public.upload_category, text, bigint, text, uuid), private.record_asset_access(uuid),
  private.request_upload_exception(uuid, text, text, bigint, integer, bigint, text),
  private.decide_upload_exception(uuid, boolean, text),
  public.save_intake_draft(uuid, jsonb), public.submit_intake(uuid, uuid), public.review_intake(uuid, text, text),
  public.correct_intake(uuid, jsonb, text), public.get_intake_state(uuid),
  public.request_upload(uuid, public.upload_category, text, bigint, text, uuid), public.record_asset_access(uuid),
  public.request_upload_exception(uuid, text, text, bigint, integer, bigint, text),
  public.decide_upload_exception(uuid, boolean, text),
  private.retry_object_deletion(uuid), public.retry_object_deletion(uuid)
to authenticated;

-- Pipeline (service_role only; each function also refuses any other JWT role).
grant execute on function
  private.complete_upload(uuid, bigint, text), private.fail_upload(uuid, text),
  private.record_content_check(uuid, boolean, text, text),
  private.record_scan_result(uuid, uuid, text, text, text, text, text), private.record_processing_outcome(uuid, text, text),
  private.release_upload(uuid, text, bigint), private.purge_failed_uploads(), private.confirm_source_hash(uuid, text),
  public.complete_upload(uuid, bigint, text), public.fail_upload(uuid, text),
  public.record_content_check(uuid, boolean, text, text),
  public.record_scan_result(uuid, uuid, text, text, text, text, text), public.record_processing_outcome(uuid, text, text),
  public.release_upload(uuid, text, bigint), public.purge_failed_uploads(), public.confirm_source_hash(uuid, text),
  private.claim_object_deletions(uuid[], integer), private.record_object_deletion(uuid, integer, boolean, text),
  public.claim_object_deletions(uuid[], integer), public.record_object_deletion(uuid, integer, boolean, text)
to service_role;

-- Tables: SELECT through RLS only; nobody writes directly (definer functions only).
revoke all on table public.intake_submissions, public.intake_reviews, public.upload_exceptions,
  public.asset_uploads, public.upload_scan_results, public.upload_scan_attempts, public.asset_object_deletions
  from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on table public.intake_submissions,
  public.intake_reviews, public.upload_exceptions, public.asset_uploads, public.upload_scan_results,
  public.upload_scan_attempts, public.asset_object_deletions from service_role;
grant select on table public.intake_submissions, public.intake_reviews, public.upload_exceptions,
  public.asset_uploads to authenticated;
-- Scan evidence is staff-visible only.
grant select on table public.upload_scan_results, public.upload_scan_attempts to authenticated;
-- Deletion tracking is staff-visible only.
grant select on table public.asset_object_deletions to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Row Level Security (03 §8-§9)
-- ---------------------------------------------------------------------------
alter table public.intake_submissions enable row level security;
alter table public.intake_reviews enable row level security;
alter table public.upload_exceptions enable row level security;
alter table public.asset_uploads enable row level security;
alter table public.upload_scan_results enable row level security;
alter table public.upload_scan_attempts enable row level security;
alter table public.asset_object_deletions enable row level security;

create policy intake_submissions_select on public.intake_submissions for select to authenticated
  using (private.can_access_project(project_id));
create policy intake_reviews_select on public.intake_reviews for select to authenticated
  using (private.can_access_project(project_id));
create policy upload_exceptions_select on public.upload_exceptions for select to authenticated
  using (private.can_access_project(project_id));
create policy asset_uploads_select on public.asset_uploads for select to authenticated
  using (private.can_access_project(project_id));
create policy upload_scan_results_select on public.upload_scan_results for select to authenticated
  using ((select private.is_staff()));
create policy upload_scan_attempts_select on public.upload_scan_attempts for select to authenticated
  using ((select private.is_staff()));
create policy asset_object_deletions_select on public.asset_object_deletions for select to authenticated
  using ((select private.is_staff()));

do $$
declare
  t text;
begin
  foreach t in array array['intake_submissions', 'intake_reviews', 'upload_exceptions', 'asset_uploads',
                           'upload_scan_results', 'upload_scan_attempts', 'asset_object_deletions'] loop
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
