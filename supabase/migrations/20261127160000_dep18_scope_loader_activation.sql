-- DEP-18 R1 interim scope loading and activation (AUTH-018; Decision 8a, Owner 2026-11-27;
-- 04 §4A "R1 interim scope loading and activation"; FD-05; OI-106).
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02).
-- - Infrastructure only. No package content, approval evidence or activation is added here: every
--   function below takes its content and identifiers as parameters from an Owner-authenticated
--   caller (FD-05; no migration is a contractual-content path).
-- - Adds only the AUTH-018 objects: two append-only tables, four Owner-only fresh-MFA functions with
--   security-invoker wrappers, and a new body for private.current_package_scope(text) (same
--   arguments and result). AUTH-007 sealing is reused unchanged: versions are still created only
--   through the AUTH-007 sealing function, called once below, inside load_package_scope_version.
-- - Four distinct steps (04 §4A item 1): legal approval, loading and sealing, activation, issuance
--   eligibility. Loading never activates. No production or hosted eligibility exists here.
-- - No item text is ever written to an audit record, returned in an error, or raised.
--
-- Serialization: every governance function takes a per-package eligibility advisory lock
-- exclusively, then the existing per-package sealing lock (the key the AUTH-007 sealing function
-- takes, so loading serializes with it). The resolver takes only the eligibility lock, shared, held
-- until commit; it never waits on plain AUTH-007 version sealing, so readers are not blocked by a
-- version under construction. The resolver is volatile, so that it reads only after its lock is
-- granted (a withdrawal committed while issuance waited is seen). Issuance holds the project row and
-- then the shared eligibility lock; governance holds only the two package locks, always in the order
-- eligibility then sealing, and the sealing function alone takes only the sealing lock: no cycle.
--
-- Refusals return {"ok": false, "error": <code>} after writing their audit event, so the event is
-- committed with the call (an event rolled back by an exception would not count).
--
-- The reader guarantee above assumes READ COMMITTED (the PostgREST default).
-- Audit targets are built only from a validated package key and the integer version ('invalid'
-- otherwise), so no refusal can write caller-supplied text into the immutable audit log.

-- ---------------------------------------------------------------------------
-- 1. Legal approval records (04 §4A item 2): one per (package, version); append-only
-- ---------------------------------------------------------------------------
-- The canonical content hash includes the version number, so an approval binds the package, the
-- version and the exact content. Hash equality alone never establishes legal approval: the record
-- carries a non-sensitive approval reference and the hash of the evidence held outside Git (§4B).
create table private.billing_package_scope_approvals (
  package_key text not null references private.billing_packages (package_key),
  scope_version integer not null check (scope_version >= 1),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  approval_reference text not null check (approval_reference ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'),
  evidence_sha256 text not null check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_by uuid not null,
  recorded_at timestamptz not null default now(),
  primary key (package_key, scope_version)
);
revoke all on table private.billing_package_scope_approvals from public, anon, authenticated, service_role;
create trigger billing_package_scope_approvals_append_only
  before update or delete on private.billing_package_scope_approvals
  for each row execute function private.insert_only();
create trigger billing_package_scope_approvals_no_truncate
  before truncate on private.billing_package_scope_approvals
  for each statement execute function private.audit_events_immutable();

-- ---------------------------------------------------------------------------
-- 2. Eligibility events (04 §4A items 4, 5 and 7): activation per classification, withdrawal
-- ---------------------------------------------------------------------------
-- The resolver reads this table, so it stores the approved hash itself and has no foreign key to
-- the approvals. An activation exists only for development and test (no hosted or production
-- eligibility in this interim mechanism). A withdrawal of a version in any classification makes
-- that version unresolvable everywhere, permanently.
create table private.billing_package_scope_eligibility (
  package_key text not null,
  scope_version integer not null,
  event text not null check (event in ('activated', 'withdrawn')),
  classification text not null
    check (classification in ('development', 'test', 'preview', 'staging', 'production')),
  approved_sha256 text not null check (approved_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_by uuid not null,
  recorded_at timestamptz not null default now(),
  constraint billing_package_scope_eligibility_pkey primary key (package_key, scope_version, event, classification),
  constraint billing_package_scope_eligibility_version_fkey foreign key (package_key, scope_version)
    references private.billing_package_scope_versions (package_key, scope_version),
  constraint billing_package_scope_eligibility_activation_classification
    check (event <> 'activated' or classification in ('development', 'test'))
);
revoke all on table private.billing_package_scope_eligibility from public, anon, authenticated, service_role;
create trigger billing_package_scope_eligibility_append_only
  before update or delete on private.billing_package_scope_eligibility
  for each row execute function private.insert_only();
create trigger billing_package_scope_eligibility_no_truncate
  before truncate on private.billing_package_scope_eligibility
  for each statement execute function private.audit_events_immutable();

-- ---------------------------------------------------------------------------
-- 3. Record a legal approval (Owner, fresh MFA, live session)
-- ---------------------------------------------------------------------------
create function private.record_package_scope_approval(
  p_package_key text,
  p_scope_version integer,
  p_content_sha256 text,
  p_approval_reference text,
  p_evidence_sha256 text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  -- Audit target from validated values only (never the raw caller-supplied key or unbounded text).
  v_target text := (case when exists (select 1 from private.billing_packages b where b.package_key = p_package_key)
    then p_package_key else 'invalid' end) || ':' || coalesce(p_scope_version::text, 'invalid');
  v_existing private.billing_package_scope_approvals;
  v_header private.billing_package_scope_versions;
  v_code text;
begin
  -- NULL-safe: private.is_owner() is NULL (not false) for a caller without an active staff role.
  if private.is_owner() is not true or private.mfa_is_fresh() is not true
     or private.session_is_active() is not true then
    v_code := 'forbidden';
  elsif p_package_key is null or not exists (select 1 from private.billing_packages where package_key = p_package_key)
     or p_scope_version is null or p_scope_version < 1
     or coalesce(p_content_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_evidence_sha256, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_approval_reference, '') !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$' then
    v_code := 'invalid_input';
  end if;
  if v_code is null then
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
    perform pg_advisory_xact_lock(hashtextextended('wpd18-scope-version:' || p_package_key, 0));
    select * into v_existing from private.billing_package_scope_approvals a
     where a.package_key = p_package_key and a.scope_version = p_scope_version;
    if found then
      if v_existing.content_sha256 = p_content_sha256 and v_existing.approval_reference = p_approval_reference
         and v_existing.evidence_sha256 = p_evidence_sha256 then
        -- Identical replay: the existing record, no new event.
        return jsonb_build_object('ok', true, 'replayed', true, 'package_key', p_package_key,
          'scope_version', p_scope_version, 'content_sha256', p_content_sha256);
      end if;
      v_code := 'approval_conflict';
    else
      select * into v_header from private.billing_package_scope_versions h
       where h.package_key = p_package_key and h.scope_version = p_scope_version;
      if found and v_header.is_test_fixture then
        v_code := 'fixture_not_allowed';
      elsif found and v_header.content_sha256 <> p_content_sha256 then
        v_code := 'hash_mismatch';
      end if;
    end if;
  end if;
  if v_code is not null then
    perform private.record_audit_event('package_scope.approval_rejected', 'package_scope', v_target, null, null,
      jsonb_build_object('reason', v_code), 'general');
    return private.fail(v_code);
  end if;

  insert into private.billing_package_scope_approvals (package_key, scope_version, content_sha256,
    approval_reference, evidence_sha256, recorded_by)
  values (p_package_key, p_scope_version, p_content_sha256, p_approval_reference, p_evidence_sha256, (select auth.uid()));
  perform private.record_audit_event('package_scope.approval_recorded', 'package_scope', v_target, null, null,
    jsonb_build_object('package_key', p_package_key, 'scope_version', p_scope_version,
      'content_sha256', p_content_sha256, 'approval_reference', p_approval_reference,
      'evidence_sha256', p_evidence_sha256), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'package_key', p_package_key,
    'scope_version', p_scope_version, 'content_sha256', p_content_sha256);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Load and seal a version (Owner, fresh MFA, live session); never activates
-- ---------------------------------------------------------------------------
-- The expected hash is the approved hash for (package, version), recorded earlier and
-- independently of this request. It is verified before anything is written; the version is then
-- sealed through the AUTH-007 sealing function, and its returned identity is checked again inside
-- the same sub-block, so any mismatch or error leaves no partial version. Errors are reported by
-- SQLSTATE only: a constraint message could otherwise echo item text.
create function private.load_package_scope_version(
  p_package_key text,
  p_scope_version integer,
  p_items text[]
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  -- Audit target from validated values only (never the raw caller-supplied key or unbounded text).
  v_target text := (case when exists (select 1 from private.billing_packages b where b.package_key = p_package_key)
    then p_package_key else 'invalid' end) || ':' || coalesce(p_scope_version::text, 'invalid');
  v_count integer := coalesce(cardinality(p_items), 0);
  v_approval private.billing_package_scope_approvals;
  v_header private.billing_package_scope_versions;
  v_next integer;
  v_sha text;
  v_result jsonb;
  v_code text;
  v_state text;
begin
  -- NULL-safe: private.is_owner() is NULL (not false) for a caller without an active staff role.
  if private.is_owner() is not true or private.mfa_is_fresh() is not true
     or private.session_is_active() is not true then
    v_code := 'forbidden';
  elsif p_package_key is null or not exists (select 1 from private.billing_packages where package_key = p_package_key)
     or p_scope_version is null or p_scope_version < 1
     or v_count not between 1 and 50 or array_ndims(p_items) <> 1 or array_position(p_items, null) is not null
     or exists (select 1 from unnest(p_items) i (item) where char_length(i.item) not between 1 and 300) then
    v_code := 'invalid_input';
  end if;

  if v_code is null then
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
    perform pg_advisory_xact_lock(hashtextextended('wpd18-scope-version:' || p_package_key, 0));
    select * into v_approval from private.billing_package_scope_approvals a
     where a.package_key = p_package_key and a.scope_version = p_scope_version;
    if not found then
      v_code := 'approval_missing';
    else
      select encode(extensions.digest(convert_to(
               'spotlight.package_scope.v1'
               || '|k' || octet_length(p_package_key) || ':' || p_package_key
               || '|v' || p_scope_version || '|n' || v_count
               || string_agg('|p' || i.ord || ':' || octet_length(i.item) || ':' || i.item, '' order by i.ord),
               'UTF8'), 'sha256'), 'hex')
        into v_sha
      from unnest(p_items) with ordinality as i (item, ord);
      select * into v_header from private.billing_package_scope_versions h
       where h.package_key = p_package_key and h.scope_version = p_scope_version;
      if found then
        if not v_header.is_test_fixture and v_header.content_sha256 = v_sha
           and v_approval.content_sha256 = v_sha then
          -- Identical replay of the sealed, approved version: the existing result, no new event.
          return jsonb_build_object('ok', true, 'replayed', true, 'package_key', p_package_key,
            'scope_version', p_scope_version, 'item_count', v_header.item_count, 'content_sha256', v_sha);
        end if;
        v_code := 'version_conflict';
      else
        select coalesce(max(v), 0) + 1 into v_next from (
          select max(s.scope_version) as v from private.billing_package_scope s where s.package_key = p_package_key
          union all
          select max(h.scope_version) from private.billing_package_scope_versions h where h.package_key = p_package_key
        ) x;
        if p_scope_version <> v_next then
          v_code := 'version_conflict';
        elsif v_sha <> v_approval.content_sha256 then
          v_code := 'hash_mismatch';
        end if;
      end if;
    end if;
  end if;

  if v_code is null then
    begin
      v_result := private.create_package_scope_version(p_package_key, p_items, false);
      if (v_result ->> 'scope_version')::integer is distinct from p_scope_version
         or v_result ->> 'content_sha256' is distinct from v_approval.content_sha256 then
        raise exception 'sealed identity differs from the approved identity' using errcode = 'P0001';
      end if;
    exception when others then
      get stacked diagnostics v_state = returned_sqlstate;
      v_code := 'load_failed';
    end;
  end if;

  if v_code is not null then
    perform private.record_audit_event('package_scope.load_rejected', 'package_scope', v_target, null, null,
      jsonb_build_object('reason', v_code) || case when v_state is null then '{}'::jsonb
        else jsonb_build_object('sqlstate', v_state) end, 'general');
    return private.fail(v_code);
  end if;

  perform private.record_audit_event('package_scope.loaded', 'package_scope', v_target, null, null,
    jsonb_build_object('package_key', p_package_key, 'scope_version', p_scope_version, 'item_count', v_count,
      'content_sha256', v_approval.content_sha256, 'classification', private.app_environment()), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'package_key', p_package_key,
    'scope_version', p_scope_version, 'item_count', v_count, 'content_sha256', v_approval.content_sha256);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Activate a version for the current classification (Owner, fresh MFA, live session)
-- ---------------------------------------------------------------------------
-- Development and test only. Requires an approval for the same package and version whose hash
-- equals the sealed hash, re-verified from the stored items. Refuses fixtures and withdrawn versions.
create function private.activate_package_scope_version(
  p_package_key text,
  p_scope_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  -- Audit target from validated values only (never the raw caller-supplied key or unbounded text).
  v_target text := (case when exists (select 1 from private.billing_packages b where b.package_key = p_package_key)
    then p_package_key else 'invalid' end) || ':' || coalesce(p_scope_version::text, 'invalid');
  v_env text := private.app_environment();
  v_header private.billing_package_scope_versions;
  v_approval private.billing_package_scope_approvals;
  v_count integer;
  v_max integer;
  v_flag_mismatch boolean;
  v_sha text;
  v_code text;
begin
  -- NULL-safe: private.is_owner() is NULL (not false) for a caller without an active staff role.
  if private.is_owner() is not true or private.mfa_is_fresh() is not true
     or private.session_is_active() is not true then
    v_code := 'forbidden';
  elsif p_package_key is null or p_scope_version is null then
    v_code := 'invalid_input';
  elsif v_env not in ('development', 'test') then
    v_code := 'classification_not_allowed';
  end if;

  if v_code is null then
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
    perform pg_advisory_xact_lock(hashtextextended('wpd18-scope-version:' || p_package_key, 0));
    select * into v_header from private.billing_package_scope_versions h
     where h.package_key = p_package_key and h.scope_version = p_scope_version;
    if not found then
      v_code := 'version_not_found';
    elsif v_header.is_test_fixture then
      v_code := 'fixture_not_allowed';
    elsif exists (select 1 from private.billing_package_scope_eligibility e
                  where e.package_key = p_package_key and e.scope_version = p_scope_version and e.event = 'withdrawn') then
      v_code := 'withdrawn';
    else
      select * into v_approval from private.billing_package_scope_approvals a
       where a.package_key = p_package_key and a.scope_version = p_scope_version;
      if not found then
        v_code := 'approval_missing';
      elsif v_approval.content_sha256 <> v_header.content_sha256 then
        v_code := 'approval_mismatch';
      else
        select count(*)::integer, max(s.position)::integer, bool_or(s.is_test_fixture),
               encode(extensions.digest(convert_to(
                 'spotlight.package_scope.v1'
                 || '|k' || octet_length(v_header.package_key) || ':' || v_header.package_key
                 || '|v' || v_header.scope_version || '|n' || count(*)
                 || string_agg('|p' || s.position || ':' || octet_length(s.item_text) || ':' || s.item_text, ''
                               order by s.position), 'UTF8'), 'sha256'), 'hex')
          into v_count, v_max, v_flag_mismatch, v_sha
        from private.billing_package_scope s
        where s.package_key = v_header.package_key and s.scope_version = v_header.scope_version;
        if v_count is distinct from v_header.item_count or v_max is distinct from v_header.item_count
           or coalesce(v_flag_mismatch, true) or v_sha is distinct from v_header.content_sha256 then
          v_code := 'integrity_failure';
        elsif exists (select 1 from private.billing_package_scope_eligibility e
                      where e.package_key = p_package_key and e.scope_version = p_scope_version
                        and e.event = 'activated' and e.classification = v_env) then
          -- Identical replay: already active for this classification, no new event.
          return jsonb_build_object('ok', true, 'replayed', true, 'package_key', p_package_key,
            'scope_version', p_scope_version, 'classification', v_env);
        end if;
      end if;
    end if;
  end if;

  if v_code is not null then
    perform private.record_audit_event('package_scope.activation_rejected', 'package_scope', v_target, null, null,
      jsonb_build_object('reason', v_code, 'classification', v_env), 'general');
    return private.fail(v_code);
  end if;

  insert into private.billing_package_scope_eligibility (package_key, scope_version, event, classification,
    approved_sha256, recorded_by)
  values (p_package_key, p_scope_version, 'activated', v_env, v_header.content_sha256, (select auth.uid()));
  perform private.record_audit_event('package_scope.activated', 'package_scope', v_target, null, null,
    jsonb_build_object('package_key', p_package_key, 'scope_version', p_scope_version,
      'content_sha256', v_header.content_sha256, 'approval_reference', v_approval.approval_reference,
      'classification', v_env), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'package_key', p_package_key,
    'scope_version', p_scope_version, 'classification', v_env);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Withdraw a version (Owner, fresh MFA, live session); irreversible
-- ---------------------------------------------------------------------------
create function private.withdraw_package_scope_version(
  p_package_key text,
  p_scope_version integer
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  -- Audit target from validated values only (never the raw caller-supplied key or unbounded text).
  v_target text := (case when exists (select 1 from private.billing_packages b where b.package_key = p_package_key)
    then p_package_key else 'invalid' end) || ':' || coalesce(p_scope_version::text, 'invalid');
  v_env text := private.app_environment();
  v_header private.billing_package_scope_versions;
  v_code text;
begin
  -- NULL-safe: private.is_owner() is NULL (not false) for a caller without an active staff role.
  if private.is_owner() is not true or private.mfa_is_fresh() is not true
     or private.session_is_active() is not true then
    v_code := 'forbidden';
  elsif p_package_key is null or p_scope_version is null then
    v_code := 'invalid_input';
  end if;

  if v_code is null then
    perform pg_advisory_xact_lock(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
    perform pg_advisory_xact_lock(hashtextextended('wpd18-scope-version:' || p_package_key, 0));
    select * into v_header from private.billing_package_scope_versions h
     where h.package_key = p_package_key and h.scope_version = p_scope_version;
    if not found then
      v_code := 'version_not_found';
    elsif exists (select 1 from private.billing_package_scope_eligibility e
                  where e.package_key = p_package_key and e.scope_version = p_scope_version and e.event = 'withdrawn') then
      -- Identical replay: already withdrawn (in any classification), no new event.
      return jsonb_build_object('ok', true, 'replayed', true, 'package_key', p_package_key,
        'scope_version', p_scope_version);
    end if;
  end if;

  if v_code is not null then
    perform private.record_audit_event('package_scope.withdrawal_rejected', 'package_scope', v_target, null, null,
      jsonb_build_object('reason', v_code, 'classification', v_env), 'general');
    return private.fail(v_code);
  end if;

  insert into private.billing_package_scope_eligibility (package_key, scope_version, event, classification,
    approved_sha256, recorded_by)
  values (p_package_key, p_scope_version, 'withdrawn', v_env, v_header.content_sha256, (select auth.uid()));
  perform private.record_audit_event('package_scope.withdrawn', 'package_scope', v_target, null, null,
    jsonb_build_object('package_key', p_package_key, 'scope_version', p_scope_version,
      'content_sha256', v_header.content_sha256, 'classification', v_env), 'general');
  return jsonb_build_object('ok', true, 'replayed', false, 'package_key', p_package_key,
    'scope_version', p_scope_version);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The resolver: newest sealed version, eligible only (04 §4A items 7 and 8)
-- ---------------------------------------------------------------------------
-- Same arguments and result. Takes the newest sealed version (no fallback to an older one) and
-- returns its items only if: it is not withdrawn; a fixture version is in development or test; a
-- non-fixture version holds an activation for the current classification whose approved hash
-- equals its sealed hash; and, recomputed now, the item count, positions 1..n, the fixture flag of
-- every item and the canonical content hash all match the sealed header. Otherwise nothing is
-- returned, so issuance fails closed (scope_definition_missing). Loading a newer version
-- therefore suspends issuance for that package until it is activated.
create or replace function private.current_package_scope(p_package_key text)
returns table (scope_version integer, item_position smallint, item_text text)
language plpgsql volatile security definer set search_path = '' as $$
#variable_conflict use_column
declare
  h private.billing_package_scope_versions;
  v_count integer;
  v_max integer;
  v_flag_mismatch boolean;
  v_sha text;
begin
  perform pg_advisory_xact_lock_shared(hashtextextended('dep18-scope-eligibility:' || p_package_key, 0));
  select * into h from private.billing_package_scope_versions v
   where v.package_key = p_package_key order by v.scope_version desc limit 1;
  if not found then
    return;
  end if;
  if exists (select 1 from private.billing_package_scope_eligibility e
             where e.package_key = h.package_key and e.scope_version = h.scope_version and e.event = 'withdrawn') then
    return;
  end if;
  if h.is_test_fixture then
    if private.app_environment() not in ('development', 'test') then
      return;
    end if;
  elsif not exists (select 1 from private.billing_package_scope_eligibility e
                    where e.package_key = h.package_key and e.scope_version = h.scope_version
                      and e.event = 'activated' and e.classification = private.app_environment()
                      and e.approved_sha256 = h.content_sha256) then
    return;
  end if;
  select count(*)::integer, max(s.position)::integer, bool_or(s.is_test_fixture <> h.is_test_fixture),
         encode(extensions.digest(convert_to(
           'spotlight.package_scope.v1'
           || '|k' || octet_length(h.package_key) || ':' || h.package_key
           || '|v' || h.scope_version || '|n' || count(*)
           || string_agg('|p' || s.position || ':' || octet_length(s.item_text) || ':' || s.item_text, ''
                         order by s.position), 'UTF8'), 'sha256'), 'hex')
    into v_count, v_max, v_flag_mismatch, v_sha
  from private.billing_package_scope s
  where s.package_key = h.package_key and s.scope_version = h.scope_version;
  if v_count is distinct from h.item_count or v_max is distinct from h.item_count
     or coalesce(v_flag_mismatch, true) or v_sha is distinct from h.content_sha256 then
    return;
  end if;
  return query
    select s.scope_version, s.position, s.item_text
    from private.billing_package_scope s
    where s.package_key = h.package_key and s.scope_version = h.scope_version
    order by s.position;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Security-invoker wrappers and privileges
-- ---------------------------------------------------------------------------
create function public.record_package_scope_approval(p_package_key text, p_scope_version integer,
  p_content_sha256 text, p_approval_reference text, p_evidence_sha256 text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.record_package_scope_approval(p_package_key, p_scope_version, p_content_sha256,
    p_approval_reference, p_evidence_sha256);
$$;
create function public.load_package_scope_version(p_package_key text, p_scope_version integer, p_items text[])
returns jsonb language sql security invoker set search_path = '' as $$
  select private.load_package_scope_version(p_package_key, p_scope_version, p_items);
$$;
create function public.activate_package_scope_version(p_package_key text, p_scope_version integer)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.activate_package_scope_version(p_package_key, p_scope_version);
$$;
create function public.withdraw_package_scope_version(p_package_key text, p_scope_version integer)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.withdraw_package_scope_version(p_package_key, p_scope_version);
$$;

-- The resolver keeps its existing privileges (no API role). The Owner functions re-authorize the
-- caller inside, like private.create_agreement_version.
revoke all on function
  private.record_package_scope_approval(text, integer, text, text, text),
  private.load_package_scope_version(text, integer, text[]),
  private.activate_package_scope_version(text, integer),
  private.withdraw_package_scope_version(text, integer),
  public.record_package_scope_approval(text, integer, text, text, text),
  public.load_package_scope_version(text, integer, text[]),
  public.activate_package_scope_version(text, integer),
  public.withdraw_package_scope_version(text, integer)
from public, anon, authenticated, service_role;
grant execute on function
  private.record_package_scope_approval(text, integer, text, text, text),
  private.load_package_scope_version(text, integer, text[]),
  private.activate_package_scope_version(text, integer),
  private.withdraw_package_scope_version(text, integer),
  public.record_package_scope_approval(text, integer, text, text, text),
  public.load_package_scope_version(text, integer, text[]),
  public.activate_package_scope_version(text, integer),
  public.withdraw_package_scope_version(text, integer)
to authenticated;
