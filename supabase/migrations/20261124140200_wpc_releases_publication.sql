-- WP-C (3 of 3): preview releases, client approvals, outreach and the approval hold, QA,
-- security and domain evidence, the single publication gate evaluator, Owner publication
-- authorization, staff-assisted deployment records, derived queues, and the WP-C gate
-- interface (05 §6-§9; 06 §2-§9; 01 §7; OI-71; OI-72; AUTH-001).
--
-- Rules for this file:
-- - Creates only new WP-C objects, plus the two changes the WP-0 contract assigns to WP-C:
--   additive attributes on private.project_fulfillment_status (OI-71 item 2: domain_ready,
--   domain_check_id, domain_checked_at; contract_version 1 -> 2) and the body of
--   private.project_fulfillment_status (same signature and return type).
-- - Never writes a WP-B table. Financial gate inputs are read only through
--   private.project_financial_status, as JSON, so WP-B can add attributes (G1) without a
--   coordinated change here; an attribute that is missing or not a boolean fails closed.
-- - No override, force, skip, or alternative publication route exists (06 §2; T-PUB-04).
--   Every gate fails closed on missing, invalid, unavailable, or stale evidence.

-- ---------------------------------------------------------------------------
-- 1. Preview releases (05 §6) and internal drafts
-- ---------------------------------------------------------------------------
-- Internal drafts: staff-only notes about unreleased builds. They never supersede a release
-- and never affect an approval (T-LC-07).
create table public.preview_drafts (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  note text check (note is null or char_length(note) <= 1000),
  recorded_by uuid not null references public.profiles (id),
  recorded_at timestamptz not null default now()
);
create index preview_drafts_project_idx on public.preview_drafts (project_id);
create trigger preview_drafts_insert_only before update or delete on public.preview_drafts
  for each row execute function private.wpc_insert_only();

-- R1 (OI-68): staff record a release of a build they deployed to a protected preview. The
-- record is immutable once released; only withdrawal (with a reason) may be added.
create table public.preview_releases (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  release_number integer not null check (release_number >= 1),
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  deployment_id text not null check (deployment_id ~ '^[A-Za-z0-9_-]{1,100}$'),
  preview_url text not null check (preview_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?(/[^[:space:]]*)?$' and char_length(preview_url) <= 500),
  release_note text check (release_note is null or char_length(release_note) <= 2000),
  released_by uuid not null references public.profiles (id),
  released_at timestamptz not null default now(),
  withdrawn_at timestamptz,
  withdrawn_by uuid references public.profiles (id),
  withdrawn_reason text,
  unique (project_id, release_number),
  constraint preview_releases_withdrawal_shape check (
    (withdrawn_at is null and withdrawn_by is null and withdrawn_reason is null)
    or (withdrawn_at is not null and withdrawn_by is not null and char_length(btrim(withdrawn_reason)) between 1 and 1000))
);
create index preview_releases_project_idx on public.preview_releases (project_id, release_number desc);

create function private.preview_releases_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'preview releases are not deleted' using errcode = '42501';
  end if;
  if old.withdrawn_at is not null
     or (new.id, new.project_id, new.release_number, new.commit_sha, new.deployment_id, new.preview_url,
         new.release_note, new.released_by, new.released_at)
        is distinct from
        (old.id, old.project_id, old.release_number, old.commit_sha, old.deployment_id, old.preview_url,
         old.release_note, old.released_by, old.released_at) then
    raise exception 'a released preview is immutable; only a withdrawal may be recorded' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger preview_releases_guard before update or delete on public.preview_releases
  for each row execute function private.preview_releases_guard();

-- Asset manifest: the assets incorporated into a release. Insert-only; marks each asset
-- version used, irreversibly (05 §4; OI-42; T-UP-10).
create table public.preview_release_assets (
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  upload_id uuid not null references public.asset_uploads (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  primary key (release_id, upload_id)
);
create index preview_release_assets_upload_idx on public.preview_release_assets (upload_id);
create trigger preview_release_assets_insert_only before update or delete on public.preview_release_assets
  for each row execute function private.wpc_insert_only();

-- The current release is the latest one. A withdrawn latest release leaves the project with
-- no current release: withdrawal never revives a superseded release.
create function private.current_release(p_project_id uuid) returns public.preview_releases
language sql stable security definer set search_path = '' as $$
  select r.* from public.preview_releases r
  where r.project_id = p_project_id and r.withdrawn_at is null
    and r.release_number = (select max(x.release_number) from public.preview_releases x where x.project_id = p_project_id);
$$;

-- ---------------------------------------------------------------------------
-- 2. Approvals and revision requests (05 §7-§8)
-- ---------------------------------------------------------------------------
create table public.preview_approvals (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  user_id uuid not null references public.profiles (id),
  approved_at timestamptz not null default now(),
  comment text check (comment is null or char_length(comment) <= 2000),
  ip text check (ip is null or char_length(ip) <= 100),
  user_agent text check (user_agent is null or char_length(user_agent) <= 300),
  unique (release_id, user_id)
);
create index preview_approvals_project_idx on public.preview_approvals (project_id);
create trigger preview_approvals_insert_only before update or delete on public.preview_approvals
  for each row execute function private.wpc_insert_only();

create table public.preview_revision_requests (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  user_id uuid not null references public.profiles (id),
  requested_at timestamptz not null default now(),
  comments text not null check (char_length(btrim(comments)) between 1 and 4000)
);
create index preview_revision_requests_project_idx on public.preview_revision_requests (project_id, requested_at);
create trigger preview_revision_requests_insert_only before update or delete on public.preview_revision_requests
  for each row execute function private.wpc_insert_only();

-- Staff scope classification of a revision request (05 §8): one insert-only decision.
create table public.revision_classifications (
  revision_request_id uuid primary key references public.preview_revision_requests (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  scope text not null check (scope in ('in_scope', 'out_of_scope')),
  note text check (note is null or char_length(note) <= 1000),
  classified_by uuid not null references public.profiles (id),
  classified_at timestamptz not null default now()
);
create trigger revision_classifications_insert_only before update or delete on public.revision_classifications
  for each row execute function private.wpc_insert_only();

-- ---------------------------------------------------------------------------
-- 3. Outreach (05 §7.1) and the approval hold (05 §7.2)
-- ---------------------------------------------------------------------------
create table public.approval_outreach_records (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  kind text not null check (kind in ('reminder_1', 'reminder_2', 'admin_notified', 'personal_followup')),
  channel text not null check (channel in ('email', 'phone', 'sms', 'video_call', 'in_person', 'portal', 'other')),
  occurred_on date not null,
  summary text not null check (char_length(btrim(summary)) between 1 and 2000),
  recorded_by uuid not null references public.profiles (id),
  recorded_at timestamptz not null default now()
);
create index approval_outreach_release_idx on public.approval_outreach_records (release_id, kind);
create trigger approval_outreach_insert_only before update or delete on public.approval_outreach_records
  for each row execute function private.wpc_insert_only();

create table public.approval_holds (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  hold_type public.hold_type not null default 'approval_nonresponsive_hold'
    check (hold_type = 'approval_nonresponsive_hold'),
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  placed_by uuid not null references public.profiles (id),
  placed_at timestamptz not null default now(),
  reason text not null check (char_length(btrim(reason)) between 1 and 1000),
  outreach_evidence_ids uuid[] not null check (cardinality(outreach_evidence_ids) >= 1),
  cleared_at timestamptz,
  cleared_by uuid references public.profiles (id),
  clear_reason text,
  clearing_response_type text check (clearing_response_type is null or clearing_response_type in ('approval', 'revision_request')),
  clearing_response_id uuid,
  constraint approval_holds_clear_shape check (
    (cleared_at is null and cleared_by is null and clear_reason is null and clearing_response_id is null)
    or (cleared_at is not null and cleared_by is not null and char_length(btrim(clear_reason)) between 1 and 1000))
);
create unique index approval_holds_one_active on public.approval_holds (project_id) where cleared_at is null;

create function private.approval_holds_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'approval holds are not deleted' using errcode = '42501';
  end if;
  if old.cleared_at is not null
     or (new.id, new.project_id, new.hold_type, new.release_id, new.placed_by, new.placed_at, new.reason,
         new.outreach_evidence_ids)
        is distinct from
        (old.id, old.project_id, old.hold_type, old.release_id, old.placed_by, old.placed_at, old.reason,
         old.outreach_evidence_ids) then
    raise exception 'an approval hold record is immutable except for its single clearance' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger approval_holds_guard before update or delete on public.approval_holds
  for each row execute function private.approval_holds_guard();

create table public.approval_hold_resumption_decisions (
  id uuid primary key default gen_random_uuid(),
  hold_id uuid not null references public.approval_holds (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  decision text not null check (decision in ('resume_development', 'proceed_to_final_payment', 'remain_held')),
  note text check (note is null or char_length(note) <= 1000),
  decided_by uuid not null references public.profiles (id),
  decided_at timestamptz not null default now()
);
create trigger approval_hold_resumption_insert_only before update or delete on public.approval_hold_resumption_decisions
  for each row execute function private.wpc_insert_only();

-- A qualifying client response (05 §7.2): an explicit approval or revision request on the
-- current release by an authorized client, after the hold was placed.
create function private.hold_client_response(p_hold public.approval_holds,
  out response_type text, out response_id uuid, out responded_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select x.t, x.id, x.at from (
    select 'approval'::text t, a.id, a.approved_at at from public.preview_approvals a
     where a.project_id = p_hold.project_id and a.approved_at >= p_hold.placed_at
       and a.release_id = (select r.id from private.current_release(p_hold.project_id) r)
    union all
    select 'revision_request', q.id, q.requested_at from public.preview_revision_requests q
     where q.project_id = p_hold.project_id and q.requested_at >= p_hold.placed_at
       and q.release_id = (select r.id from private.current_release(p_hold.project_id) r)
  ) x order by x.at limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 4. QA, security, and domain evidence (06 §5-§7)
-- ---------------------------------------------------------------------------
create function private.qa_mandatory_areas() returns text[]
language sql immutable set search_path = '' as $$
  select array['functional', 'responsive', 'branding_content', 'performance', 'accessibility', 'security',
               'domain_operational', 'monitoring_rollback'];
$$;
create function private.security_checklist_keys() returns text[]
language sql immutable set search_path = '' as $$
  select array['https_hsts', 'security_headers', 'no_exposed_secrets', 'dependency_scan', 'form_abuse_protection',
               'no_debug_endpoints', 'admin_surfaces_protected'];
$$;

-- items: [{ "key": text, "area": one of the mandatory areas, "result": "pass" | "fail" |
-- "not_applicable", "evidence": optional text }]. Every mandatory area must be covered.
create function private.qa_items_valid(p_items jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) between 1 and 200
     and octet_length(p_items::text) <= 32768
     and not exists (
       select 1 from jsonb_array_elements(p_items) i
       where jsonb_typeof(i) <> 'object'
          or coalesce(i ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,60}$'
          or not (coalesce(i ->> 'area', '') = any (private.qa_mandatory_areas()))
          or coalesce(i ->> 'result', '') not in ('pass', 'fail', 'not_applicable')
          or (i ? 'evidence' and (jsonb_typeof(i -> 'evidence') <> 'string' or char_length(i ->> 'evidence') > 500))
          or exists (select 1 from jsonb_object_keys(i) k where k not in ('key', 'area', 'result', 'evidence')))
     and not exists (
       select 1 from unnest(private.qa_mandatory_areas()) a
       where not exists (select 1 from jsonb_array_elements(p_items) i where i ->> 'area' = a));
$$;

create table public.qa_results (
  id uuid primary key default gen_random_uuid(),
  -- Insertion order: "latest" always means the highest seq, never a timestamp tie.
  seq bigint generated always as identity unique,
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  checklist_version text not null check (checklist_version ~ '^[A-Za-z0-9._-]{1,40}$'),
  items jsonb not null check (private.qa_items_valid(items)),
  recorded_by uuid not null references public.profiles (id),
  recorded_at timestamptz not null default now()
);
create index qa_results_release_idx on public.qa_results (release_id, recorded_at desc);
create trigger qa_results_insert_only before update or delete on public.qa_results
  for each row execute function private.wpc_insert_only();

-- The only permitted G5 exception (06 §2; OI-33): Owner-approved, performance items only,
-- for one release, with the measured values and a reason.
create table public.qa_performance_exceptions (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  measured_values jsonb not null check (
    jsonb_typeof(measured_values) = 'object' and measured_values <> '{}'::jsonb and octet_length(measured_values::text) <= 4096),
  reason text not null check (char_length(btrim(reason)) between 1 and 1000),
  approved_by uuid not null references public.profiles (id),
  approved_at timestamptz not null default now()
);
create index qa_performance_exceptions_release_idx on public.qa_performance_exceptions (release_id);
create trigger qa_performance_exceptions_insert_only before update or delete on public.qa_performance_exceptions
  for each row execute function private.wpc_insert_only();

-- items: [{ "key": one of the checklist keys or another snake_case key, "severity":
-- "critical" | "high" | "medium" | "low", "result": "pass" | "fail" | "not_applicable",
-- "evidence": optional }]. Every starting checklist key (06 §7) must be present.
create function private.security_items_valid(p_items jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_items) = 'array' and jsonb_array_length(p_items) between 1 and 200
     and octet_length(p_items::text) <= 32768
     and not exists (
       select 1 from jsonb_array_elements(p_items) i
       where jsonb_typeof(i) <> 'object'
          or coalesce(i ->> 'key', '') !~ '^[a-z][a-z0-9_]{0,60}$'
          or coalesce(i ->> 'severity', '') not in ('critical', 'high', 'medium', 'low')
          or coalesce(i ->> 'result', '') not in ('pass', 'fail', 'not_applicable')
          or (i ? 'evidence' and (jsonb_typeof(i -> 'evidence') <> 'string' or char_length(i ->> 'evidence') > 500))
          or exists (select 1 from jsonb_object_keys(i) k where k not in ('key', 'severity', 'result', 'evidence')))
     and not exists (
       select 1 from unnest(private.security_checklist_keys()) k
       where not exists (select 1 from jsonb_array_elements(p_items) i where i ->> 'key' = k));
$$;

create table public.security_check_results (
  id uuid primary key default gen_random_uuid(),
  -- Insertion order: "latest" always means the highest seq, never a timestamp tie.
  seq bigint generated always as identity unique,
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  checklist_version text not null check (checklist_version ~ '^[A-Za-z0-9._-]{1,40}$'),
  items jsonb not null check (private.security_items_valid(items)),
  recorded_by uuid not null references public.profiles (id),
  recorded_at timestamptz not null default now()
);
create index security_check_results_release_idx on public.security_check_results (release_id, recorded_at desc);
create trigger security_check_results_insert_only before update or delete on public.security_check_results
  for each row execute function private.wpc_insert_only();

create table public.domain_readiness_checks (
  id uuid primary key default gen_random_uuid(),
  -- Insertion order: "latest" always means the highest seq, never a timestamp tie.
  seq bigint generated always as identity unique,
  project_id uuid not null references public.projects (id) on delete restrict,
  domain text not null check (domain ~ '^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$' and char_length(domain) <= 253),
  dns_points_to_target boolean not null,
  tls_valid boolean not null,
  redirect_policy_ok boolean not null,
  registrant_in_client_name boolean,
  third_party_charges_disclosed boolean not null,
  spotlight_registered boolean not null,
  registration_date date,
  registrar_expiry date,
  notes text check (notes is null or char_length(notes) <= 1000),
  checked_at timestamptz not null default now(),
  recorded_by uuid not null references public.profiles (id),
  constraint domain_readiness_registration_shape check (
    not spotlight_registered or (registration_date is not null and registrar_expiry is not null
                                 and registrar_expiry > registration_date))
);
create index domain_readiness_project_idx on public.domain_readiness_checks (project_id, checked_at desc);
create trigger domain_readiness_insert_only before update or delete on public.domain_readiness_checks
  for each row execute function private.wpc_insert_only();

-- 06 §5 [PROPOSED] freshness window.
create function private.domain_freshness_window() returns interval
language sql immutable set search_path = '' as $$ select interval '24 hours' $$;

create function private.domain_check_passed(c public.domain_readiness_checks) returns boolean
language sql immutable set search_path = '' as $$
  select c.dns_points_to_target and c.tls_valid and c.redirect_policy_ok and c.third_party_charges_disclosed
     and coalesce(c.registrant_in_client_name, true);
$$;

-- ---------------------------------------------------------------------------
-- 5. Client site targets, publication authorization, deployments (06 §3-§4, §8-§9)
-- ---------------------------------------------------------------------------
-- Each client website deploys to its own isolated target (OI-32; T-PUB-15). A target
-- reference belongs to exactly one project. No credential is stored here.
create table public.client_site_targets (
  project_id uuid primary key references public.projects (id) on delete restrict,
  target_ref text not null unique check (target_ref ~ '^[a-z0-9][a-z0-9_-]{2,99}$'),
  registered_by uuid not null references public.profiles (id),
  registered_at timestamptz not null default now()
);
create trigger client_site_targets_insert_only before update or delete on public.client_site_targets
  for each row execute function private.wpc_insert_only();

create table public.publication_authorizations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  gate_result jsonb not null check (jsonb_typeof(gate_result) = 'object' and octet_length(gate_result::text) <= 16384),
  authorized_by uuid not null references public.profiles (id),
  authorized_at timestamptz not null default now(),
  invalidated_at timestamptz,
  invalidated_reason text check (invalidated_reason is null or invalidated_reason ~ '^[a-z_]{1,60}$'),
  constraint publication_authorizations_invalidation_shape check ((invalidated_at is null) = (invalidated_reason is null))
);
create unique index publication_authorizations_one_active on public.publication_authorizations (project_id)
  where invalidated_at is null;

create function private.publication_authorizations_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'publication authorizations are not deleted' using errcode = '42501';
  end if;
  if old.invalidated_at is not null
     or (new.id, new.project_id, new.release_id, new.gate_result, new.authorized_by, new.authorized_at)
        is distinct from (old.id, old.project_id, old.release_id, old.gate_result, old.authorized_by, old.authorized_at) then
    raise exception 'a publication authorization is immutable except for its single invalidation' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger publication_authorizations_guard before update or delete on public.publication_authorizations
  for each row execute function private.publication_authorizations_guard();

create table public.publication_deployments (
  id uuid primary key default gen_random_uuid(),
  -- Insertion order: "latest" always means the highest seq, never a timestamp tie.
  seq bigint generated always as identity unique,
  authorization_id uuid not null unique references public.publication_authorizations (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  release_id uuid not null references public.preview_releases (id) on delete restrict,
  commit_sha text not null check (commit_sha ~ '^[0-9a-f]{40}$'),
  target_ref text not null,
  start_gate_result jsonb not null check (jsonb_typeof(start_gate_result) = 'object' and octet_length(start_gate_result::text) <= 16384),
  rollback_deployment_id uuid references public.publication_deployments (id),
  started_by uuid not null references public.profiles (id),
  started_at timestamptz not null default now(),
  outcome text not null default 'started' check (outcome in ('started', 'succeeded', 'failed')),
  provider_deployment_id text check (provider_deployment_id is null or provider_deployment_id ~ '^[A-Za-z0-9_-]{1,100}$'),
  production_url text check (production_url is null or (production_url ~ '^https://[A-Za-z0-9.-]+(/[^[:space:]]*)?$' and char_length(production_url) <= 500)),
  failure_reason text check (failure_reason is null or char_length(failure_reason) <= 1000),
  recorded_by uuid references public.profiles (id),
  recorded_at timestamptz,
  constraint publication_deployments_outcome_shape check (
    (outcome = 'started' and recorded_at is null and recorded_by is null and provider_deployment_id is null)
    or (outcome = 'succeeded' and recorded_at is not null and recorded_by is not null
        and provider_deployment_id is not null and production_url is not null)
    or (outcome = 'failed' and recorded_at is not null and recorded_by is not null
        and char_length(btrim(failure_reason)) >= 1))
);
create index publication_deployments_project_idx on public.publication_deployments (project_id, started_at desc);

create function private.publication_deployments_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'deployment records are not deleted' using errcode = '42501';
  end if;
  if old.outcome <> 'started'
     or (new.id, new.authorization_id, new.project_id, new.release_id, new.commit_sha, new.target_ref,
         new.start_gate_result, new.rollback_deployment_id, new.started_by, new.started_at)
        is distinct from
        (old.id, old.authorization_id, old.project_id, old.release_id, old.commit_sha, old.target_ref,
         old.start_gate_result, old.rollback_deployment_id, old.started_by, old.started_at) then
    raise exception 'a deployment record takes exactly one outcome and is otherwise immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger publication_deployments_guard before update or delete on public.publication_deployments
  for each row execute function private.publication_deployments_guard();

-- Live verification (06 §9). Written only by the server verifier (service_role) after it
-- has authorized the staff caller, so staff cannot assert a result.
create table public.deployment_verifications (
  id uuid primary key default gen_random_uuid(),
  -- Insertion order: "latest" always means the highest seq, never a timestamp tie.
  seq bigint generated always as identity unique,
  deployment_id uuid not null references public.publication_deployments (id) on delete restrict,
  project_id uuid not null references public.projects (id) on delete restrict,
  served_build_id text check (served_build_id is null or char_length(served_build_id) <= 100),
  http_ok boolean not null,
  tls_ok boolean not null,
  key_pages_ok boolean not null,
  forms_ok boolean not null,
  build_matches boolean not null,
  verified boolean not null,
  requested_by uuid not null references public.profiles (id),
  checked_at timestamptz not null default now(),
  constraint deployment_verifications_verified check (
    verified = (http_ok and tls_ok and key_pages_ok and forms_ok and build_matches))
);
create index deployment_verifications_deployment_idx on public.deployment_verifications (deployment_id, checked_at desc);
create trigger deployment_verifications_insert_only before update or delete on public.deployment_verifications
  for each row execute function private.wpc_insert_only();

create table public.publication_incidents (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  deployment_id uuid references public.publication_deployments (id) on delete restrict,
  severity text not null check (severity in ('sev1', 'sev2', 'sev3')),
  kind text not null check (kind in ('deployment_failed', 'verification_failed')),
  summary text not null check (char_length(summary) between 1 and 1000),
  opened_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id),
  resolution text check (resolution is null or char_length(resolution) <= 2000),
  constraint publication_incidents_resolution_shape check (
    (resolved_at is null and resolved_by is null and resolution is null)
    or (resolved_at is not null and resolved_by is not null and char_length(btrim(resolution)) >= 1))
);
create index publication_incidents_project_idx on public.publication_incidents (project_id) where resolved_at is null;

create function private.publication_incidents_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'incidents are not deleted' using errcode = '42501';
  end if;
  if old.resolved_at is not null
     or (new.id, new.project_id, new.deployment_id, new.severity, new.kind, new.summary, new.opened_at)
        is distinct from (old.id, old.project_id, old.deployment_id, old.severity, old.kind, old.summary, old.opened_at) then
    raise exception 'an incident is immutable except for its single resolution' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger publication_incidents_guard before update or delete on public.publication_incidents
  for each row execute function private.publication_incidents_guard();

-- ---------------------------------------------------------------------------
-- 6. The WP-C gate interface (01 §7; OI-71 item 2)
-- ---------------------------------------------------------------------------
alter type private.project_fulfillment_status
  add attribute domain_ready boolean,
  add attribute domain_check_id uuid,
  add attribute domain_checked_at timestamptz;

-- QA passes when the latest QA result for the release has every blocking item passing,
-- except failed performance items covered by an Owner performance exception (06 §2; OI-33).
create function private.qa_result_passes(p_qa public.qa_results) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_qa.id is not null and not exists (
    select 1 from jsonb_array_elements(p_qa.items) i
    where i ->> 'result' = 'fail'
      and not (i ->> 'area' = 'performance' and exists (
        select 1 from public.qa_performance_exceptions e
        join public.staff_roles s on s.user_id = e.approved_by and s.role = 'owner'
        where e.release_id = p_qa.release_id)));
$$;

-- Security passes when the latest result has no failed critical or high item (06 §7). There
-- is no exception mechanism for security.
create function private.security_result_passes(p_sec public.security_check_results) returns boolean
language sql immutable set search_path = '' as $$
  select p_sec.id is not null and not exists (
    select 1 from jsonb_array_elements(p_sec.items) i
    where i ->> 'result' = 'fail' and i ->> 'severity' in ('critical', 'high'));
$$;

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
begin
  if not exists (select 1 from public.projects where id = p_project_id) then
    return row(p_project_id, 2::smallint, false, 'locked'::public.intake_state, false, null::uuid, false, null::uuid,
      false, false, '{}'::public.hold_type[], '{}'::jsonb, false, null::uuid, null::timestamptz
    )::private.project_fulfillment_status;
  end if;
  v_state := private.intake_state_of(p_project_id);
  v_release := private.current_release(p_project_id);
  if v_release.id is not null then
    select a.id into v_approval from public.preview_approvals a
     where a.release_id = v_release.id order by a.approved_at, a.id limit 1;
    select * into v_qa from public.qa_results q where q.release_id = v_release.id
     order by q.seq desc limit 1;
    select * into v_sec from public.security_check_results s where s.release_id = v_release.id
     order by s.seq desc limit 1;
  end if;
  select * into v_domain from public.domain_readiness_checks d where d.project_id = p_project_id
   order by d.seq desc limit 1;
  select coalesce(array_agg(h.hold_type), '{}'), coalesce(array_agg(h.id), '{}') into v_holds, v_hold_ids
    from public.approval_holds h where h.project_id = p_project_id and h.cleared_at is null;

  return row(
    p_project_id, 2::smallint, true,
    v_state, v_state = 'accepted_by_staff',
    v_release.id, v_approval is not null, v_approval,
    v_release.id is not null and private.qa_result_passes(v_qa),
    v_release.id is not null and private.security_result_passes(v_sec),
    v_holds,
    jsonb_build_object(
      'current_release_number', v_release.release_number,
      'current_release_commit_sha', v_release.commit_sha,
      'qa_result_id', v_qa.id, 'qa_release_id', v_qa.release_id,
      'security_result_id', v_sec.id, 'security_release_id', v_sec.release_id,
      'fulfillment_hold_ids', to_jsonb(v_hold_ids)),
    v_domain.id is not null and private.domain_check_passed(v_domain)
      and v_domain.checked_at > now() - private.domain_freshness_window(),
    v_domain.id, v_domain.checked_at
  )::private.project_fulfillment_status;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The single publication gate evaluator (06 §2; OI-71)
-- ---------------------------------------------------------------------------
-- Reads only the two gate interfaces. Returns the full structured result. Fails closed:
-- an interface that raises, returns another project, reports implemented = false, an
-- unsupported contract version, or a missing or non-boolean attribute fails every gate it
-- supplies, and G8 fails if either interface is not trustworthy.
create function private.gate_contract_minimums(out financial smallint, out fulfillment smallint)
language sql immutable set search_path = '' as $$ select 1::smallint, 2::smallint $$;

create function private.evaluate_publication_gates(p_project_id uuid, p_release_id uuid) returns jsonb
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
  begin
    v_fin := to_jsonb(private.project_financial_status(p_project_id));
  exception when others then
    v_fin := null; v_fin_error := 'unavailable';
  end;
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

-- OI-72: the stored and staff-visible form. Billing hold types and every financial detail
-- other than pass/fail and the G4 adjustment disclosure are reduced to derived states.
create function private.redact_gate_result(p_result jsonb, p_owner boolean) returns jsonb
language sql immutable set search_path = '' as $$
  select case when p_owner then p_result else
    p_result || jsonb_build_object('gates', (
      select coalesce(jsonb_agg(case when g ->> 'gate' = 'G8' then
          g - 'billing_holds' || jsonb_build_object('billing_related_hold',
            case when jsonb_typeof(g -> 'billing_holds') = 'array' then jsonb_array_length(g -> 'billing_holds') > 0 end)
        else g end order by o), '[]'::jsonb)
      from jsonb_array_elements(p_result -> 'gates') with ordinality t(g, o)))
  end;
$$;

-- Stored snapshot (authorizations, deployments): the redacted form for every reader.
create function private.gate_snapshot(p_result jsonb) returns jsonb
language sql immutable set search_path = '' as $$ select private.redact_gate_result(p_result, false); $$;

-- Staff report (Owner: full; Admin: derived states only).
create function private.publication_gate_report(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
begin
  if not private.wpc_is_staff_aal2() or not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('forbidden');
  end if;
  v_release := private.current_release(p_project_id);
  return jsonb_build_object('ok', true, 'result',
    private.redact_gate_result(private.evaluate_publication_gates(p_project_id, v_release.id), private.is_owner()));
end;
$$;

create function private.failing_gates(p_result jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('gate', g ->> 'gate', 'reason', g ->> 'reason') order by o), '[]'::jsonb)
  from jsonb_array_elements(p_result -> 'gates') with ordinality t(g, o)
  where not coalesce((g ->> 'passed')::boolean, false);
$$;

-- ---------------------------------------------------------------------------
-- 8. Staff and client actions
-- ---------------------------------------------------------------------------
create function private.invalidate_authorizations(p_project_id uuid, p_reason text, p_release_id uuid default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  r record;
begin
  for r in
    update public.publication_authorizations set invalidated_at = now(), invalidated_reason = p_reason
     where project_id = p_project_id and invalidated_at is null
       and (p_release_id is null or release_id = p_release_id)
       and not exists (select 1 from public.publication_deployments d
                        where d.authorization_id = publication_authorizations.id and d.outcome = 'succeeded')
    returning id
  loop
    perform private.record_audit_event('publication.authorization_invalidated', 'publication_authorizations',
      r.id::text, p_project_id, null, jsonb_build_object('reason', p_reason));
  end loop;
end;
$$;

create function private.release_preview(
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

create function private.record_preview_draft(p_project_id uuid, p_commit_sha text, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() or not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('forbidden');
  end if;
  insert into public.preview_drafts (project_id, commit_sha, note, recorded_by)
  values (p_project_id, lower(p_commit_sha), nullif(btrim(p_note), ''), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('preview.draft_recorded', 'preview_drafts', v_id::text, p_project_id);
  return jsonb_build_object('ok', true, 'draft_id', v_id);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.withdraw_preview(p_release_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.preview_releases;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  if not private.wpc_text_ok(p_reason, 1000) then
    return private.fail('reason_required');
  end if;
  select * into v from public.preview_releases where id = p_release_id and withdrawn_at is null for update;
  if not found then
    return private.fail('not_found');
  end if;
  update public.preview_releases set withdrawn_at = now(), withdrawn_by = (select auth.uid()), withdrawn_reason = btrim(p_reason)
   where id = v.id;
  perform private.invalidate_authorizations(v.project_id, 'release_withdrawn', v.id);
  perform private.record_audit_event('preview.withdrawn', 'preview_releases', v.id::text, v.project_id, btrim(p_reason),
    jsonb_build_object('release_number', v.release_number));
  return jsonb_build_object('ok', true);
end;
$$;

-- Client approval (05 §7). Clients only (staff can never approve: T-LC-09, T-ROLE-04); only
-- the current released preview, named explicitly; idempotent per user and release. The
-- first approval of a release emits release.approved exactly once (dedupe key per release).
create function private.approve_preview(p_release_id uuid, p_comment text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_current public.preview_releases;
  v_existing public.preview_approvals;
  v_id uuid;
  v_first boolean;
  v_hold public.approval_holds;
begin
  select * into v_release from public.preview_releases where id = p_release_id;
  if not found or not private.wpc_is_client_member(v_release.project_id) then
    return private.fail('forbidden');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || v_release.project_id::text, 0));
  v_current := private.current_release(v_release.project_id);
  select * into v_existing from public.preview_approvals where release_id = p_release_id and user_id = (select auth.uid());
  if found then
    return jsonb_build_object('ok', true, 'approval_id', v_existing.id, 'existing', true);
  end if;
  if v_current.id is distinct from v_release.id then
    return private.fail('release_superseded');
  end if;
  v_first := not exists (select 1 from public.preview_approvals where release_id = v_release.id);
  insert into public.preview_approvals (release_id, project_id, user_id, comment, ip, user_agent)
  values (v_release.id, v_release.project_id, (select auth.uid()), nullif(btrim(p_comment), ''),
    left(coalesce(private.request_header('x-client-ip'), private.request_header('x-forwarded-for')), 100),
    left(private.request_header('user-agent'), 300))
  returning id into v_id;
  perform private.record_audit_event('preview.approved', 'preview_approvals', v_id::text, v_release.project_id, null,
    jsonb_build_object('release_id', v_release.id, 'release_number', v_release.release_number));
  if v_first then
    perform private.emit_domain_event('release.approved', v_release.project_id, 'preview_release', v_release.id::text,
      jsonb_build_object('release_id', v_release.id, 'release_number', v_release.release_number,
        'approval_id', v_id, 'commit_sha', v_release.commit_sha),
      'release.approved:' || v_release.id);
    perform private.enqueue_notification('preview.approved', 'preview.approved:' || v_release.id || ':1',
      'preview_approved', 1, v_release.project_id, null, '{}', array['staff']::public.notification_recipient_role[],
      jsonb_build_object('release_id', v_release.id));
  end if;
  select * into v_hold from public.approval_holds where project_id = v_release.project_id and cleared_at is null;
  if found then
    perform private.record_audit_event('approval_hold.client_response', 'approval_holds', v_hold.id::text,
      v_release.project_id, null, jsonb_build_object('response', 'approval', 'response_id', v_id));
    perform private.enqueue_notification('approval_hold.client_response', 'approval_hold.client_response:' || v_id || ':1',
      'approval_hold_client_response', 1, v_release.project_id, null, '{}',
      array['admin', 'owner']::public.notification_recipient_role[], jsonb_build_object('hold_id', v_hold.id));
  end if;
  return jsonb_build_object('ok', true, 'approval_id', v_id, 'existing', false);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.request_revisions(p_release_id uuid, p_comments text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_id uuid;
  v_hold public.approval_holds;
begin
  select * into v_release from public.preview_releases where id = p_release_id;
  if not found or not private.wpc_is_client_member(v_release.project_id) then
    return private.fail('forbidden');
  end if;
  if (private.current_release(v_release.project_id)).id is distinct from v_release.id then
    return private.fail('release_superseded');
  end if;
  if not private.wpc_text_ok(p_comments, 4000) then
    return private.fail('invalid_input');
  end if;
  insert into public.preview_revision_requests (release_id, project_id, user_id, comments)
  values (v_release.id, v_release.project_id, (select auth.uid()), btrim(p_comments))
  returning id into v_id;
  perform private.record_audit_event('preview.revision_requested', 'preview_revision_requests', v_id::text,
    v_release.project_id, null, jsonb_build_object('release_id', v_release.id));
  select * into v_hold from public.approval_holds where project_id = v_release.project_id and cleared_at is null;
  if found then
    perform private.record_audit_event('approval_hold.client_response', 'approval_holds', v_hold.id::text,
      v_release.project_id, null, jsonb_build_object('response', 'revision_request', 'response_id', v_id));
    perform private.enqueue_notification('approval_hold.client_response', 'approval_hold.client_response:' || v_id || ':1',
      'approval_hold_client_response', 1, v_release.project_id, null, '{}',
      array['admin', 'owner']::public.notification_recipient_role[], jsonb_build_object('hold_id', v_hold.id));
  end if;
  return jsonb_build_object('ok', true, 'revision_request_id', v_id);
end;
$$;

create function private.classify_revision_request(p_revision_request_id uuid, p_scope text, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.preview_revision_requests;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v from public.preview_revision_requests where id = p_revision_request_id;
  if not found then
    return private.fail('not_found');
  end if;
  if exists (select 1 from public.revision_classifications where revision_request_id = v.id) then
    return private.fail('already_classified');
  end if;
  insert into public.revision_classifications (revision_request_id, project_id, scope, note, classified_by)
  values (v.id, v.project_id, p_scope, nullif(btrim(p_note), ''), (select auth.uid()));
  perform private.record_audit_event('preview.revision_classified', 'preview_revision_requests', v.id::text,
    v.project_id, null, jsonb_build_object('scope', p_scope));
  return jsonb_build_object('ok', true);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

-- Outreach records (05 §7.1, R1: staff perform and record).
create function private.record_outreach(
  p_release_id uuid, p_kind text, p_channel text, p_occurred_on date, p_summary text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v_release from public.preview_releases where id = p_release_id;
  if not found then
    return private.fail('not_found');
  end if;
  if (private.current_release(v_release.project_id)).id is distinct from v_release.id then
    return private.fail('not_current_release');
  end if;
  if p_occurred_on is null or p_occurred_on < (v_release.released_at at time zone 'America/Detroit')::date
     or p_occurred_on > (now() at time zone 'America/Detroit')::date then
    return private.fail('invalid_date');
  end if;
  insert into public.approval_outreach_records (project_id, release_id, kind, channel, occurred_on, summary, recorded_by)
  values (v_release.project_id, v_release.id, p_kind, p_channel, p_occurred_on, btrim(p_summary), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event(case p_kind
      when 'reminder_1' then 'approval.reminder_1_sent' when 'reminder_2' then 'approval.reminder_2_sent'
      when 'admin_notified' then 'approval.admin_notified' else 'approval.personal_followup_recorded' end,
    'approval_outreach_records', v_id::text, v_release.project_id, null,
    jsonb_build_object('release_id', v_release.id, 'channel', p_channel, 'occurred_on', p_occurred_on));
  return jsonb_build_object('ok', true, 'outreach_id', v_id);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

-- Day-21 approval hold (05 §7.2; OI-45). Owner or Admin, with a reason, day >= 21 for the
-- current release, after the documented day-14 personal follow-up. Placing it never creates
-- an approval and never touches billing (T-LC-11, T-LC-13).
create function private.place_approval_hold(p_project_id uuid, p_reason text) returns jsonb
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
  if private.detroit_days_since(v_release.released_at) < 21 then
    return private.fail('too_early');
  end if;
  if not exists (select 1 from public.approval_outreach_records
                  where release_id = v_release.id and kind = 'personal_followup') then
    return private.fail('outreach_required');
  end if;
  if exists (select 1 from public.approval_holds where project_id = p_project_id and cleared_at is null) then
    return private.fail('hold_active');
  end if;
  select array_agg(o.id order by o.occurred_on, o.id) into v_evidence
    from public.approval_outreach_records o where o.release_id = v_release.id;
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

-- Clear: the Owner at any time with a reason; an Admin only after a qualifying client
-- response (05 §7.2; T-ROLE-05).
create function private.clear_approval_hold(p_hold_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.approval_holds;
  v_resp record;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  if not private.wpc_text_ok(p_reason, 1000) then
    return private.fail('reason_required');
  end if;
  select * into v from public.approval_holds where id = p_hold_id and cleared_at is null for update;
  if not found then
    return private.fail('not_found');
  end if;
  select * into v_resp from private.hold_client_response(v);
  if not private.is_owner() and v_resp.response_id is null then
    perform private.record_audit_event('approval_hold.clear_rejected', 'approval_holds', v.id::text, v.project_id,
      btrim(p_reason), jsonb_build_object('reason', 'no_qualifying_client_response'));
    return private.fail('client_response_required');
  end if;
  update public.approval_holds
     set cleared_at = now(), cleared_by = (select auth.uid()), clear_reason = btrim(p_reason),
         clearing_response_type = v_resp.response_type, clearing_response_id = v_resp.response_id
   where id = v.id;
  perform private.record_audit_event('approval_hold.cleared', 'approval_holds', v.id::text, v.project_id, btrim(p_reason),
    jsonb_build_object('client_response_id', v_resp.response_id, 'actor_role', private.staff_role_of((select auth.uid()))));
  perform private.enqueue_notification('approval_hold.cleared', 'approval_hold.cleared:' || v.id || ':1',
    'approval_hold_cleared', 1, v.project_id, null, '{}',
    array['client', 'owner', 'admin']::public.notification_recipient_role[], jsonb_build_object('hold_id', v.id));
  return jsonb_build_object('ok', true);
end;
$$;

create function private.record_hold_resumption(p_hold_id uuid, p_decision text, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.approval_holds;
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v from public.approval_holds where id = p_hold_id;
  if not found then
    return private.fail('not_found');
  end if;
  insert into public.approval_hold_resumption_decisions (hold_id, project_id, decision, note, decided_by)
  values (v.id, v.project_id, p_decision, nullif(btrim(p_note), ''), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('approval_hold.resumption_decided', 'approval_holds', v.id::text, v.project_id,
    nullif(btrim(p_note), ''), jsonb_build_object('decision', p_decision));
  return jsonb_build_object('ok', true, 'decision_id', v_id);
exception
  when check_violation then
    return private.fail('invalid_input');
end;
$$;

-- QA, security, performance exception, and domain readiness evidence (06 §5-§7).
create function private.record_qa_result(p_release_id uuid, p_checklist_version text, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v_release from public.preview_releases where id = p_release_id and withdrawn_at is null;
  if not found then
    return private.fail('not_found');
  end if;
  insert into public.qa_results (release_id, project_id, checklist_version, items, recorded_by)
  values (v_release.id, v_release.project_id, p_checklist_version, p_items, (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('qa.recorded', 'qa_results', v_id::text, v_release.project_id, null,
    jsonb_build_object('release_id', v_release.id, 'checklist_version', p_checklist_version));
  return jsonb_build_object('ok', true, 'qa_result_id', v_id);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.approve_performance_exception(p_release_id uuid, p_measured_values jsonb, p_reason text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_id uuid;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  select * into v_release from public.preview_releases where id = p_release_id and withdrawn_at is null;
  if not found then
    return private.fail('not_found');
  end if;
  insert into public.qa_performance_exceptions (release_id, project_id, measured_values, reason, approved_by)
  values (v_release.id, v_release.project_id, p_measured_values, btrim(p_reason), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('qa.performance_exception_approved', 'qa_performance_exceptions', v_id::text,
    v_release.project_id, btrim(p_reason), jsonb_build_object('release_id', v_release.id, 'measured_values', p_measured_values));
  return jsonb_build_object('ok', true, 'exception_id', v_id);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.record_security_result(p_release_id uuid, p_checklist_version text, p_items jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v_release from public.preview_releases where id = p_release_id and withdrawn_at is null;
  if not found then
    return private.fail('not_found');
  end if;
  insert into public.security_check_results (release_id, project_id, checklist_version, items, recorded_by)
  values (v_release.id, v_release.project_id, p_checklist_version, p_items, (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('security_check.recorded', 'security_check_results', v_id::text,
    v_release.project_id, null, jsonb_build_object('release_id', v_release.id, 'checklist_version', p_checklist_version));
  return jsonb_build_object('ok', true, 'security_result_id', v_id);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.record_domain_check(
  p_project_id uuid, p_domain text, p_dns_ok boolean, p_tls_ok boolean, p_redirect_ok boolean,
  p_registrant_ok boolean, p_charges_disclosed boolean, p_spotlight_registered boolean,
  p_registration_date date, p_registrar_expiry date, p_notes text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() or not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('forbidden');
  end if;
  insert into public.domain_readiness_checks (project_id, domain, dns_points_to_target, tls_valid, redirect_policy_ok,
    registrant_in_client_name, third_party_charges_disclosed, spotlight_registered, registration_date,
    registrar_expiry, notes, recorded_by)
  values (p_project_id, lower(btrim(p_domain)), p_dns_ok, p_tls_ok, p_redirect_ok, p_registrant_ok, p_charges_disclosed,
    p_spotlight_registered, p_registration_date, p_registrar_expiry, nullif(btrim(p_notes), ''), (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('domain.readiness_recorded', 'domain_readiness_checks', v_id::text, p_project_id,
    null, jsonb_build_object('domain', lower(btrim(p_domain))));
  return jsonb_build_object('ok', true, 'domain_check_id', v_id);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

create function private.register_client_site_target(p_project_id uuid, p_target_ref text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('not_found');
  end if;
  if exists (select 1 from public.client_site_targets where project_id = p_project_id) then
    return private.fail('already_registered');
  end if;
  insert into public.client_site_targets (project_id, target_ref, registered_by)
  values (p_project_id, p_target_ref, (select auth.uid()));
  perform private.record_audit_event('client_site.target_registered', 'client_site_targets', p_project_id::text,
    p_project_id, null, jsonb_build_object('target_ref', p_target_ref));
  return jsonb_build_object('ok', true);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
  when unique_violation then
    return private.fail('target_in_use');
end;
$$;

-- Owner publication authorization (06 §3): Owner only, fresh reauthentication, all gates
-- passing for exactly one release. A rejection is audited with the failing gates.
create function private.authorize_publication(p_project_id uuid, p_release_id uuid) returns jsonb
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

-- Start deployment (06 §8.1 step 1, R1). Owner or Admin. Re-evaluates every gate against
-- the active authorization immediately before deployment; any failure blocks the start and
-- invalidates the authorization. Idempotent per authorization (T-PUB-10).
create function private.start_deployment(p_authorization_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_auth public.publication_authorizations;
  v_existing public.publication_deployments;
  v_release public.preview_releases;
  v_target public.client_site_targets;
  v_result jsonb;
  v_rollback uuid;
  v_id uuid;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v_auth from public.publication_authorizations where id = p_authorization_id;
  if not found then
    return private.fail('not_found');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('release:' || v_auth.project_id::text, 0));
  select * into v_existing from public.publication_deployments where authorization_id = v_auth.id;
  if found then
    return jsonb_build_object('ok', true, 'deployment_id', v_existing.id, 'existing', true);
  end if;
  if v_auth.invalidated_at is not null then
    perform private.record_audit_event('deployment.start_rejected', 'publication_authorizations', v_auth.id::text,
      v_auth.project_id, null, jsonb_build_object('reason', 'authorization_invalid'));
    return private.fail('authorization_invalid');
  end if;
  select * into v_target from public.client_site_targets where project_id = v_auth.project_id;
  if not found then
    perform private.record_audit_event('deployment.start_rejected', 'publication_authorizations', v_auth.id::text,
      v_auth.project_id, null, jsonb_build_object('reason', 'no_isolated_target'));
    return private.fail('no_isolated_target');
  end if;
  v_result := private.evaluate_publication_gates(v_auth.project_id, v_auth.release_id);
  if not coalesce((v_result ->> 'eligible')::boolean, false) then
    perform private.invalidate_authorizations(v_auth.project_id, 'gates_failed_at_start', v_auth.release_id);
    perform private.record_audit_event('deployment.start_rejected', 'publication_authorizations', v_auth.id::text,
      v_auth.project_id, null, jsonb_build_object('reason', 'gates_failed', 'failing_gates', private.failing_gates(v_result)));
    return jsonb_build_object('ok', false, 'error', 'gates_failed', 'failing_gates', private.failing_gates(v_result));
  end if;
  select * into v_release from public.preview_releases where id = v_auth.release_id;
  -- Rollback reference: the previous live_verified deployment (06 §8.1 step 5).
  select d.id into v_rollback from public.publication_deployments d
   where d.project_id = v_auth.project_id and d.outcome = 'succeeded'
     and (select x.verified from public.deployment_verifications x
           where x.deployment_id = d.id order by x.seq desc limit 1)
   order by d.seq desc limit 1;
  insert into public.publication_deployments (authorization_id, project_id, release_id, commit_sha, target_ref,
    start_gate_result, rollback_deployment_id, started_by)
  values (v_auth.id, v_auth.project_id, v_release.id, v_release.commit_sha, v_target.target_ref,
    private.gate_snapshot(v_result), v_rollback, (select auth.uid()))
  returning id into v_id;
  perform private.record_audit_event('deployment.started', 'publication_deployments', v_id::text, v_auth.project_id,
    null, jsonb_build_object('authorization_id', v_auth.id, 'release_id', v_release.id, 'commit_sha', v_release.commit_sha,
      'target_ref', v_target.target_ref, 'rollback_deployment_id', v_rollback));
  return jsonb_build_object('ok', true, 'deployment_id', v_id, 'existing', false, 'commit_sha', v_release.commit_sha,
    'target_ref', v_target.target_ref);
end;
$$;

-- Record deployment (06 §8.1 step 3). One outcome per deployment. A failure opens an
-- incident and an Owner queue item; nothing here touches payment state (T-PUB-18).
create function private.record_deployment_result(
  p_deployment_id uuid, p_succeeded boolean, p_provider_deployment_id text, p_production_url text, p_failure_reason text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.publication_deployments;
begin
  if not private.wpc_is_staff_aal2() then
    return private.fail('forbidden');
  end if;
  select * into v from public.publication_deployments where id = p_deployment_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if v.outcome <> 'started' then
    return private.fail('already_recorded');
  end if;
  update public.publication_deployments
     set outcome = case when p_succeeded then 'succeeded' else 'failed' end,
         provider_deployment_id = case when p_succeeded then p_provider_deployment_id end,
         production_url = case when p_succeeded then p_production_url end,
         failure_reason = case when p_succeeded then null else btrim(p_failure_reason) end,
         recorded_by = (select auth.uid()), recorded_at = now()
   where id = v.id;
  perform private.record_audit_event(case when p_succeeded then 'deployment.succeeded' else 'deployment.failed' end,
    'publication_deployments', v.id::text, v.project_id, null,
    jsonb_build_object('provider_deployment_id', case when p_succeeded then p_provider_deployment_id end));
  if not p_succeeded then
    insert into public.publication_incidents (project_id, deployment_id, severity, kind, summary)
    values (v.project_id, v.id, 'sev2', 'deployment_failed', left(btrim(p_failure_reason), 1000));
    perform private.record_audit_event('incident.opened', 'publication_deployments', v.id::text, v.project_id, null,
      jsonb_build_object('kind', 'deployment_failed'));
    perform private.enqueue_notification('publication.verification_failed', 'publication.deployment_failed:' || v.id || ':1',
      'publication_failed', 1, v.project_id, null, '{}', array['owner']::public.notification_recipient_role[],
      jsonb_build_object('deployment_id', v.id));
  end if;
  return jsonb_build_object('ok', true);
exception
  when check_violation or not_null_violation then
    return private.fail('invalid_input');
end;
$$;

-- Live verification (06 §9; T-PUB-06, T-PUB-08). service_role only: the server verifier
-- authorizes the staff caller, performs the checks, and reports them with the caller's
-- verified user ID. The served build identifier must equal the authorized release's commit.
create function private.record_live_verification(
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
  if private.staff_role_of(p_requested_by) is null then
    return private.fail('forbidden');
  end if;
  select * into v from public.publication_deployments where id = p_deployment_id;
  if not found or v.outcome <> 'succeeded' then
    return private.fail('not_found');
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

create function private.resolve_incident(p_incident_id uuid, p_resolution text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v public.publication_incidents;
begin
  if not (private.is_owner() and private.is_aal2() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if not private.wpc_text_ok(p_resolution, 2000) then
    return private.fail('reason_required');
  end if;
  select * into v from public.publication_incidents where id = p_incident_id and resolved_at is null for update;
  if not found then
    return private.fail('not_found');
  end if;
  update public.publication_incidents set resolved_at = now(), resolved_by = (select auth.uid()), resolution = btrim(p_resolution)
   where id = v.id;
  perform private.record_audit_event('incident.resolved', 'publication_incidents', v.id::text, v.project_id,
    btrim(p_resolution));
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Derived state for the client status page and the staff queue (05 §1, §9; OI-72)
-- ---------------------------------------------------------------------------
create function private.publication_state_of(p_project_id uuid) returns public.publication_state
language plpgsql stable security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_dep public.publication_deployments;
  v_ver public.deployment_verifications;
begin
  v_release := private.current_release(p_project_id);
  if exists (select 1 from public.publication_authorizations a where a.project_id = p_project_id
               and a.invalidated_at is null
               and not exists (select 1 from public.publication_deployments d where d.authorization_id = a.id)) then
    return 'authorized';
  end if;
  select * into v_dep from public.publication_deployments d where d.project_id = p_project_id
   and d.release_id = v_release.id order by d.seq desc limit 1;
  if v_dep.id is not null then
    if v_dep.outcome = 'started' then return 'deploying'; end if;
    if v_dep.outcome = 'failed' then return 'failed'; end if;
    select * into v_ver from public.deployment_verifications x where x.deployment_id = v_dep.id
     order by x.seq desc limit 1;
    if v_ver.id is null then return 'live_unverified'; end if;
    return case when v_ver.verified then 'live_verified' else 'failed' end;
  end if;
  if v_release.id is not null
     and coalesce((private.evaluate_publication_gates(p_project_id, v_release.id) ->> 'eligible')::boolean, false) then
    return 'eligible';
  end if;
  return 'not_eligible';
end;
$$;

-- The client's status page shows only authoritative, derived state (R1 item 11).
create function private.project_status(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_release public.preview_releases;
  v_hold boolean;
begin
  if not private.can_access_project(p_project_id) or not private.session_is_active()
     or (private.is_staff() and not private.is_aal2()) then
    return private.fail('not_found');
  end if;
  v_release := private.current_release(p_project_id);
  v_hold := exists (select 1 from public.approval_holds where project_id = p_project_id and cleared_at is null);
  return jsonb_build_object('ok', true,
    'intake_state', private.intake_state_of(p_project_id),
    'current_release', case when v_release.id is null then null else jsonb_build_object(
      'id', v_release.id, 'release_number', v_release.release_number, 'preview_url', v_release.preview_url,
      'released_at', v_release.released_at,
      'approved', exists (select 1 from public.preview_approvals a where a.release_id = v_release.id),
      'review_window_ends_on', null) end,
    'approval_hold', case when v_hold then 'Paused: awaiting your preview response' end,
    'publication_state', private.publication_state_of(p_project_id),
    'uploads', (select jsonb_build_object(
        'available', count(*) filter (where status = 'available'),
        'in_review', count(*) filter (where status in ('quarantined', 'scanning', 'processing')),
        'rejected', count(*) filter (where status = 'rejected'))
      from public.asset_uploads where project_id = p_project_id));
end;
$$;

-- Upload review SLA and domain expiry horizon for the queue (05 §9 [PROPOSED]; OI-73).
create function private.upload_review_sla() returns interval language sql immutable set search_path = '' as $$ select interval '24 hours' $$;
create function private.domain_expiry_horizon() returns integer language sql immutable set search_path = '' as $$ select 60 $$;

-- Derived operational queue (05 §9). Computed from records on every call; never stored.
-- OI-72: financial inputs appear only as derived states; billing hold types appear to the
-- Owner only, and to Admin as "billing-related operational hold".
create function private.operational_queue() returns setof jsonb
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
    if v_state in ('open', 'changes_requested') and private.wpc_deposit_verified(p.id) then
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
        'subject_id', u.id, 'detail', jsonb_build_object('status', u.status, 'code', coalesce(u.rejection_code, u.processing_note),
          'name', u.original_name))
      from public.asset_uploads u
      where u.project_id = p.id
        and ((u.status in ('quarantined', 'scanning', 'processing') and u.status_changed_at < now() - private.upload_review_sla())
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
-- 10. Exposed RPC wrappers (SECURITY INVOKER)
-- ---------------------------------------------------------------------------
create function public.release_preview(p_project_id uuid, p_commit_sha text, p_deployment_id text, p_preview_url text,
  p_asset_upload_ids uuid[], p_release_note text default null) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.release_preview(p_project_id, p_commit_sha, p_deployment_id, p_preview_url, p_asset_upload_ids, p_release_note);
$$;
create function public.record_preview_draft(p_project_id uuid, p_commit_sha text, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_preview_draft(p_project_id, p_commit_sha, p_note); $$;
create function public.withdraw_preview(p_release_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.withdraw_preview(p_release_id, p_reason); $$;
create function public.approve_preview(p_release_id uuid, p_comment text default null) returns jsonb
language sql security invoker set search_path = '' as $$ select private.approve_preview(p_release_id, p_comment); $$;
create function public.request_revisions(p_release_id uuid, p_comments text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.request_revisions(p_release_id, p_comments); $$;
create function public.classify_revision_request(p_revision_request_id uuid, p_scope text, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.classify_revision_request(p_revision_request_id, p_scope, p_note); $$;
create function public.record_outreach(p_release_id uuid, p_kind text, p_channel text, p_occurred_on date, p_summary text)
returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_outreach(p_release_id, p_kind, p_channel, p_occurred_on, p_summary); $$;
create function public.place_approval_hold(p_project_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.place_approval_hold(p_project_id, p_reason); $$;
create function public.clear_approval_hold(p_hold_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.clear_approval_hold(p_hold_id, p_reason); $$;
create function public.record_hold_resumption(p_hold_id uuid, p_decision text, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_hold_resumption(p_hold_id, p_decision, p_note); $$;
create function public.record_qa_result(p_release_id uuid, p_checklist_version text, p_items jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_qa_result(p_release_id, p_checklist_version, p_items); $$;
create function public.approve_performance_exception(p_release_id uuid, p_measured_values jsonb, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.approve_performance_exception(p_release_id, p_measured_values, p_reason); $$;
create function public.record_security_result(p_release_id uuid, p_checklist_version text, p_items jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_security_result(p_release_id, p_checklist_version, p_items); $$;
create function public.record_domain_check(p_project_id uuid, p_domain text, p_dns_ok boolean, p_tls_ok boolean,
  p_redirect_ok boolean, p_registrant_ok boolean, p_charges_disclosed boolean, p_spotlight_registered boolean,
  p_registration_date date, p_registrar_expiry date, p_notes text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_domain_check(p_project_id, p_domain, p_dns_ok, p_tls_ok, p_redirect_ok, p_registrant_ok,
    p_charges_disclosed, p_spotlight_registered, p_registration_date, p_registrar_expiry, p_notes);
$$;
create function public.register_client_site_target(p_project_id uuid, p_target_ref text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.register_client_site_target(p_project_id, p_target_ref); $$;
create function public.publication_gate_report(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.publication_gate_report(p_project_id); $$;
create function public.authorize_publication(p_project_id uuid, p_release_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.authorize_publication(p_project_id, p_release_id); $$;
create function public.start_deployment(p_authorization_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.start_deployment(p_authorization_id); $$;
create function public.record_deployment_result(p_deployment_id uuid, p_succeeded boolean, p_provider_deployment_id text,
  p_production_url text, p_failure_reason text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_deployment_result(p_deployment_id, p_succeeded, p_provider_deployment_id, p_production_url, p_failure_reason);
$$;
create function public.resolve_incident(p_incident_id uuid, p_resolution text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.resolve_incident(p_incident_id, p_resolution); $$;
create function public.project_status(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.project_status(p_project_id); $$;
create function public.operational_queue() returns setof jsonb
language sql stable security invoker set search_path = '' as $$ select private.operational_queue(); $$;
-- Server verifier (secret key only):
create function public.record_live_verification(p_deployment_id uuid, p_requested_by uuid, p_served_build_id text,
  p_http_ok boolean, p_tls_ok boolean, p_key_pages_ok boolean, p_forms_ok boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_live_verification(p_deployment_id, p_requested_by, p_served_build_id, p_http_ok, p_tls_ok,
    p_key_pages_ok, p_forms_ok);
$$;

-- ---------------------------------------------------------------------------
-- 11. Privileges
-- ---------------------------------------------------------------------------
do $$
declare
  f regprocedure;
begin
  -- Every function this migration created: no default EXECUTE for anyone.
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in ('preview_releases_guard', 'current_release', 'approval_holds_guard', 'hold_client_response',
        'qa_mandatory_areas', 'security_checklist_keys', 'qa_items_valid', 'security_items_valid',
        'domain_freshness_window', 'domain_check_passed', 'publication_authorizations_guard',
        'publication_deployments_guard', 'publication_incidents_guard', 'qa_result_passes', 'security_result_passes',
        'project_fulfillment_status', 'gate_contract_minimums', 'evaluate_publication_gates', 'redact_gate_result',
        'gate_snapshot', 'publication_gate_report', 'failing_gates', 'invalidate_authorizations', 'release_preview',
        'record_preview_draft', 'withdraw_preview', 'approve_preview', 'request_revisions', 'classify_revision_request',
        'record_outreach', 'place_approval_hold', 'clear_approval_hold', 'record_hold_resumption', 'record_qa_result',
        'approve_performance_exception', 'record_security_result', 'record_domain_check', 'register_client_site_target',
        'authorize_publication', 'start_deployment', 'record_deployment_result', 'record_live_verification',
        'resolve_incident', 'publication_state_of', 'project_status', 'upload_review_sla', 'domain_expiry_horizon',
        'operational_queue')
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end;
$$;

grant execute on function
  private.release_preview(uuid, text, text, text, uuid[], text), private.record_preview_draft(uuid, text, text),
  private.withdraw_preview(uuid, text), private.approve_preview(uuid, text), private.request_revisions(uuid, text),
  private.classify_revision_request(uuid, text, text), private.record_outreach(uuid, text, text, date, text),
  private.place_approval_hold(uuid, text), private.clear_approval_hold(uuid, text),
  private.record_hold_resumption(uuid, text, text), private.record_qa_result(uuid, text, jsonb),
  private.approve_performance_exception(uuid, jsonb, text), private.record_security_result(uuid, text, jsonb),
  private.record_domain_check(uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, date, date, text),
  private.register_client_site_target(uuid, text), private.publication_gate_report(uuid),
  private.authorize_publication(uuid, uuid), private.start_deployment(uuid),
  private.record_deployment_result(uuid, boolean, text, text, text), private.resolve_incident(uuid, text),
  private.project_status(uuid), private.operational_queue(),
  public.release_preview(uuid, text, text, text, uuid[], text), public.record_preview_draft(uuid, text, text),
  public.withdraw_preview(uuid, text), public.approve_preview(uuid, text), public.request_revisions(uuid, text),
  public.classify_revision_request(uuid, text, text), public.record_outreach(uuid, text, text, date, text),
  public.place_approval_hold(uuid, text), public.clear_approval_hold(uuid, text),
  public.record_hold_resumption(uuid, text, text), public.record_qa_result(uuid, text, jsonb),
  public.approve_performance_exception(uuid, jsonb, text), public.record_security_result(uuid, text, jsonb),
  public.record_domain_check(uuid, text, boolean, boolean, boolean, boolean, boolean, boolean, date, date, text),
  public.register_client_site_target(uuid, text), public.publication_gate_report(uuid),
  public.authorize_publication(uuid, uuid), public.start_deployment(uuid),
  public.record_deployment_result(uuid, boolean, text, text, text), public.resolve_incident(uuid, text),
  public.project_status(uuid), public.operational_queue()
to authenticated;

grant execute on function
  private.record_live_verification(uuid, uuid, text, boolean, boolean, boolean, boolean),
  public.record_live_verification(uuid, uuid, text, boolean, boolean, boolean, boolean)
to service_role;

-- Tables: SELECT through RLS; nobody writes directly.
do $$
declare
  t text;
  client_visible text[] := array['preview_releases', 'preview_release_assets', 'preview_approvals',
    'preview_revision_requests'];
  staff_only text[] := array['preview_drafts', 'revision_classifications', 'approval_outreach_records',
    'approval_holds', 'approval_hold_resumption_decisions', 'qa_results', 'qa_performance_exceptions',
    'security_check_results', 'domain_readiness_checks', 'client_site_targets', 'publication_authorizations',
    'publication_deployments', 'deployment_verifications', 'publication_incidents'];
begin
  foreach t in array client_visible || staff_only loop
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('revoke insert, update, delete, truncate, references, trigger on table public.%I from service_role', t);
    execute format('grant select on table public.%I to authenticated', t);
    execute format('alter table public.%I enable row level security', t);
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
  foreach t in array client_visible loop
    execute format('create policy %I on public.%I for select to authenticated using (private.can_access_project(project_id))',
      t || '_select', t);
  end loop;
  foreach t in array staff_only loop
    execute format('create policy %I on public.%I for select to authenticated using ((select private.is_staff()))',
      t || '_select', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Domain-event and audit registration (WP-C)
-- ---------------------------------------------------------------------------
-- release.approved and publication.authorized were registered by WP-0. No new event types.
