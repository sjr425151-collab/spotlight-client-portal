-- WP-S migration B: Sales Representative authorization infrastructure.
-- Specification: 03 §3, §4, §4.1, §6.1, §13 (v0.5.8); 04 §4 (v0.9.6). Decisions OI-77, OI-78,
-- OI-83, OI-84 (a)-(f), amendments A2 and A5, the AUTH-005 environment-isolation amendment
-- (Owner, 2026-11-25). Authorization: AUTH-005 (Tier 2, active 2026-11-25). WP-S directive
-- items 3-7 and 9 (CURRENT-STATE §9).
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02). Merged migrations are not edited.
-- - Changes ONLY the Phase 2 objects AUTH-005 lists: (2) invitations_kind_shape, (3)
--   private.is_staff(), (4) private.create_invitation and private.revoke_invitation, (6)
--   private.accept_invitation, (7) private.set_staff_role. Items (6) and (7) only add
--   rejections; every Owner and Admin path is otherwise unchanged (copied verbatim).
-- - Replaces ONE WP-B function, private.issue_order_summary, with one added alternative
--   caller (an assigned Sales Representative) and the OI-84 (b), (c) rules for that caller
--   only. Signature, grants, catalog-only pricing, the OI-81 price lock, and the Owner and
--   Admin path are unchanged. No WP-B table changes. No WP-C function changes.
-- - A Sales Representative receives no table, view, or storage grant or policy beyond
--   reading its own active assignment rows (03 §4.1 "Direct access"). Every Sales capability
--   is a SECURITY DEFINER function that checks the role, aal2, the live session, and the
--   active assignment live, at every call (OI-78: no cached authorization, no token claims
--   beyond sub, session_id, aal, amr).
-- - No synthetic or fixture package-scope row is inserted here (A2); local and CI fixtures
--   live only in supabase/seed.sql. Production scope content comes only from the Owner (DEP-18).

-- ---------------------------------------------------------------------------
-- 1. Phase 2 object (2): staff invitations may carry the Sales role
-- ---------------------------------------------------------------------------
alter table public.invitations drop constraint invitations_kind_shape;
alter table public.invitations add constraint invitations_kind_shape check (
  (kind = 'client' and project_id is not null and intended_role is null)
  or (kind = 'staff' and project_id is null and intended_role in ('owner', 'admin', 'sales'))
);

-- ---------------------------------------------------------------------------
-- 2. Phase 2 object (3): is_staff() means Owner or Admin only
-- ---------------------------------------------------------------------------
-- Identical for existing data (no other assignable role exists). coalesce keeps the result a
-- strict boolean for non-staff callers, exactly as the original `is not null` was: every
-- restrictive policy written as `not is_staff() or ...` must keep evaluating to true for clients.
create or replace function private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.staff_role_of((select auth.uid())) in ('owner', 'admin'), false);
$$;

-- ---------------------------------------------------------------------------
-- 3. Assignments (03 §4.1 "Assignment", OI-78) and their append-only history
-- ---------------------------------------------------------------------------
create table public.project_sales_assignments (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  sales_user_id uuid not null references public.profiles (id) on delete restrict,
  assigned_by uuid not null references public.profiles (id),
  active boolean not null default true,
  assigned_at timestamptz not null default now(),
  ended_at timestamptz,
  ended_by uuid references public.profiles (id),
  end_reason text,
  constraint project_sales_assignments_end_shape check (
    (active and ended_at is null and ended_by is null)
    or (not active and ended_at is not null and ended_by is not null)),
  constraint project_sales_assignments_reason_bounded check (end_reason is null or char_length(end_reason) <= 500)
);
-- One active representative per project; reassignment ends the previous assignment first.
create unique index project_sales_assignments_one_active
  on public.project_sales_assignments (project_id) where active;
create index project_sales_assignments_user_idx
  on public.project_sales_assignments (sales_user_id, active);

create table public.project_sales_assignment_history (
  id bigint generated always as identity primary key,
  assignment_id uuid not null references public.project_sales_assignments (id),
  project_id uuid not null references public.projects (id),
  sales_user_id uuid not null references public.profiles (id),
  event text not null check (event in ('created', 'ended')),
  actor_user_id uuid references public.profiles (id),
  reason text check (reason is null or char_length(reason) <= 500),
  occurred_at timestamptz not null default now()
);
create index project_sales_assignment_history_project_idx
  on public.project_sales_assignment_history (project_id, occurred_at);

-- The only change ever allowed on an assignment: active -> ended, once. Rows are never deleted.
create function private.project_sales_assignments_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'sales assignments are never deleted' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    if not new.active then
      raise exception 'a sales assignment starts active' using errcode = '42501';
    end if;
    return new;
  end if;
  if not (old.active and not new.active)
     or (to_jsonb(new) - 'active' - 'ended_at' - 'ended_by' - 'end_reason')
        is distinct from (to_jsonb(old) - 'active' - 'ended_at' - 'ended_by' - 'end_reason') then
    raise exception 'a sales assignment can only be ended, once' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger project_sales_assignments_guard
  before insert or update or delete on public.project_sales_assignments
  for each row execute function private.project_sales_assignments_guard();
create trigger project_sales_assignments_no_truncate
  before truncate on public.project_sales_assignments
  for each statement execute function private.audit_events_immutable();

-- Every assignment change writes one history row in the same transaction.
create function private.project_sales_assignments_history() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    insert into public.project_sales_assignment_history (assignment_id, project_id, sales_user_id, event, actor_user_id)
    values (new.id, new.project_id, new.sales_user_id, 'created', new.assigned_by);
  else
    insert into public.project_sales_assignment_history
      (assignment_id, project_id, sales_user_id, event, actor_user_id, reason)
    values (new.id, new.project_id, new.sales_user_id, 'ended', new.ended_by, new.end_reason);
  end if;
  return new;
end;
$$;
create trigger project_sales_assignments_history
  after insert or update on public.project_sales_assignments
  for each row execute function private.project_sales_assignments_history();

-- History is append-only for every role (the WP-B insert-only guard, reused unchanged).
create trigger project_sales_assignment_history_insert_only
  before update or delete on public.project_sales_assignment_history
  for each row execute function private.insert_only();
create trigger project_sales_assignment_history_no_truncate
  before truncate on public.project_sales_assignment_history
  for each statement execute function private.audit_events_immutable();

-- ---------------------------------------------------------------------------
-- 4. Sales helpers (read live at every call; 03 §4.1 "Assignment termination")
-- ---------------------------------------------------------------------------
-- A Sales Representative in a fully authenticated staff session: active Sales role (role
-- grant and profile both active), aal2 with a verified factor, and a live session within the
-- 12-hour staff rule (session_is_active applies the staff rule to every staff role).
create function private.is_sales() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.staff_role_of((select auth.uid())) = 'sales', false)
     and private.is_aal2() and private.session_is_active();
$$;

-- The caller is an authenticated Sales Representative with an ACTIVE assignment to this
-- (non-archived) project. Ended assignments, revoked roles, deactivated users, aal1, and
-- dead or expired sessions all return false at the next call.
create function private.sales_assigned(p_project_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_sales() and exists (
    select 1 from public.project_sales_assignments a
    join public.projects p on p.id = a.project_id and p.archived_at is null
    where a.project_id = p_project_id and a.sales_user_id = (select auth.uid()) and a.active
  );
$$;

-- ---------------------------------------------------------------------------
-- 5. Package scope definition (OI-84(b); 04 §4; DEP-18; A2, A5; AUTH-005 amendment 2026-11-25)
-- ---------------------------------------------------------------------------
-- Versioned standard scope per package. Rows come only from reviewed migrations (production
-- content: DEP-18, Owner-supplied) or, for local and CI tests only, from supabase/seed.sql.
-- No API role holds any privilege. A Sales-issued order summary copies the current version
-- into its immutable snapshot, so a later version never alters an issued summary (A5).
create table private.billing_package_scope (
  package_key text not null references private.billing_packages (package_key),
  scope_version integer not null check (scope_version >= 1),
  position smallint not null check (position between 1 and 50),
  item_text text not null check (char_length(item_text) between 1 and 300),
  is_test_fixture boolean not null,
  recorded_at timestamptz not null default now(),
  primary key (package_key, scope_version, position),
  -- A2: a row is a fixture if and only if its text carries the fixture label (both directions).
  constraint billing_package_scope_fixture_label check (
    is_test_fixture = starts_with(item_text, 'TEST FIXTURE — NOT A DELIVERABLE'))
);
revoke all on table private.billing_package_scope from public, anon, authenticated, service_role;

-- AUTH-005 environment allowlist: fixture rows are accepted only where the trusted
-- classification is development or test. production, staging, preview, any unknown value,
-- and a missing private.environment_settings row (read as production) are all rejected.
create function private.billing_package_scope_fixture_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.is_test_fixture and private.app_environment() not in ('development', 'test') then
    raise exception 'package-scope test fixtures are allowed only in development and test databases'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger billing_package_scope_fixture_guard
  before insert or update on private.billing_package_scope
  for each row execute function private.billing_package_scope_fixture_guard();

-- The current (highest) scope version of a package, in order. The allowlist is re-checked at
-- every call: when the current version holds a fixture row and the classification is not
-- development or test (for example after a change to staging, or a removed row), nothing is
-- returned, so Sales issuance fails closed instead of falling back to an older version.
create function private.current_package_scope(p_package_key text)
returns table (scope_version integer, item_position smallint, item_text text)
language sql stable security definer set search_path = '' as $$
  with latest as (
    select max(s.scope_version) as v from private.billing_package_scope s where s.package_key = p_package_key
  )
  select s.scope_version, s.position, s.item_text
  from private.billing_package_scope s
  join latest on s.scope_version = latest.v
  where s.package_key = p_package_key
    and (not s.is_test_fixture or private.app_environment() in ('development', 'test'))
    and not exists (
      select 1 from private.billing_package_scope x
      where x.package_key = p_package_key and x.scope_version = latest.v and x.is_test_fixture
        and private.app_environment() not in ('development', 'test'))
  order by s.position;
$$;

-- ---------------------------------------------------------------------------
-- 6. Phase 2 object (4): create_invitation and revoke_invitation
-- ---------------------------------------------------------------------------
-- Added: (a) a Sales Representative may create a CLIENT invitation for a project it is
-- actively assigned to (aal2, live session), never a staff invitation and never to the
-- address of a user with an active staff role of any kind; Sales calls consume a per-user
-- Sales bucket (rejections audited as sales.rate_limited). (b) No inviter can address a
-- client invitation to a user with an active Sales role (03 §4.1(a)); audited. Everything
-- else, including the Owner and Admin path and the in-function "resend" revocation, is the
-- Phase 2 body unchanged.
create or replace function private.create_invitation(
  p_kind public.invitation_kind,
  p_email text,
  p_full_name text,
  p_project_id uuid default null,
  p_intended_role public.staff_role default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_email text := lower(btrim(p_email));
  v_token text;
  v_id uuid;
  v_sales boolean := coalesce(private.staff_role_of((select auth.uid())) = 'sales', false);
begin
  if v_sales then
    -- WP-S: client invitations to an actively assigned project only (03 §4, §4.1).
    if p_kind <> 'client' or p_intended_role is not null or p_project_id is null
       or not private.sales_assigned(p_project_id) then
      return private.fail('forbidden');
    end if;
    if exists (
      select 1 from public.profiles pr join public.staff_roles s on s.user_id = pr.id and s.status = 'active'
      where pr.email = v_email::extensions.citext
    ) then
      perform private.record_audit_event('invitation.create_rejected', 'invitations', null, p_project_id, null,
        jsonb_build_object('reason', 'staff_address', 'email_domain', split_part(v_email, '@', 2)));
      return private.fail('invalid_recipient');
    end if;
    if not private.consume_rate_limit('sales-invite:' || v_uid, 30, interval '1 hour') then
      perform private.record_audit_event('sales.rate_limited', 'invitations', null, p_project_id, null,
        jsonb_build_object('operation', 'invitation_create'));
      return private.fail('rate_limited');
    end if;
  elsif not private.is_staff() or not private.is_aal2() or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  if p_intended_role = 'fulfillment' then
    perform private.record_audit_event('staff_role.fulfillment_assignment_attempted', 'invitation', null, null,
      null, jsonb_build_object('email_domain', split_part(v_email, '@', 2)));
    return private.fail('role_not_assignable');
  end if;
  if p_kind = 'staff' and not (private.is_owner() and private.mfa_is_fresh()) then
    return private.fail('forbidden');
  end if;
  if p_kind = 'client' and not exists (
    select 1 from public.projects where id = p_project_id and archived_at is null
  ) then
    return private.fail('project_not_found');
  end if;
  -- WP-S (03 §4.1(a)): a Sales Representative never holds a project membership.
  if p_kind = 'client' and exists (
    select 1 from public.profiles pr join public.staff_roles s on s.user_id = pr.id
    where pr.email = v_email::extensions.citext and s.status = 'active' and s.role = 'sales'
  ) then
    perform private.record_audit_event('invitation.create_rejected', 'invitations', null, p_project_id, null,
      jsonb_build_object('reason', 'sales_address', 'email_domain', split_part(v_email, '@', 2)));
    return private.fail('invalid_recipient');
  end if;
  if not private.consume_rate_limit('invite:' || v_uid, 50, interval '1 hour') then
    return private.fail('rate_limited');
  end if;
  if p_kind = 'client' and (
    select count(*) from public.invitations
    where project_id = p_project_id and status = 'pending' and expires_at > now()
  ) >= 20 then
    return private.fail('too_many_pending');
  end if;

  -- "Resend": the previous pending invitation for the same target is revoked.
  update public.invitations
     set status = 'revoked', revoked_by = v_uid, revoked_at = now()
   where status = 'pending' and email = v_email::extensions.citext and kind = p_kind
     and project_id is not distinct from (case when p_kind = 'client' then p_project_id end);

  v_token := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.invitations (kind, email, full_name, project_id, intended_role, token_hash, created_by)
  values (p_kind, v_email, btrim(p_full_name),
          case when p_kind = 'client' then p_project_id end,
          case when p_kind = 'staff' then p_intended_role end,
          extensions.digest(v_token, 'sha256'), v_uid)
  returning id into v_id;

  -- The plaintext token is returned exactly once, to the server, for the invitation link.
  return jsonb_build_object('ok', true, 'invitation_id', v_id, 'token', v_token);
exception
  when check_violation or invalid_text_representation then
    return private.fail('invalid_input');
end;
$$;

-- Added: a Sales Representative may revoke a pending CLIENT invitation of a project it is
-- actively assigned to (rate-limited, per-user Sales bucket). Anything else is reported as
-- not found, so another project's invitations are indistinguishable from missing ones.
-- The Owner and Admin path is the Phase 2 body unchanged.
create or replace function private.revoke_invitation(p_invitation_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_kind public.invitation_kind;
  v_project uuid;
begin
  if coalesce(private.staff_role_of((select auth.uid())) = 'sales', false) then
    if not private.is_sales() then
      return private.fail('forbidden');
    end if;
    select kind, project_id into v_kind, v_project from public.invitations
     where id = p_invitation_id and status = 'pending' for update;
    if not found or v_kind <> 'client' or not private.sales_assigned(v_project) then
      return private.fail('not_found');
    end if;
    if not private.consume_rate_limit('sales-invite:' || (select auth.uid()), 30, interval '1 hour') then
      perform private.record_audit_event('sales.rate_limited', 'invitations', p_invitation_id::text, v_project,
        null, jsonb_build_object('operation', 'invitation_revoke'));
      return private.fail('rate_limited');
    end if;
    update public.invitations set status = 'revoked', revoked_by = (select auth.uid()), revoked_at = now()
     where id = p_invitation_id;
    return jsonb_build_object('ok', true);
  end if;

  if not private.is_staff() or not private.is_aal2() or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  select kind into v_kind from public.invitations where id = p_invitation_id and status = 'pending' for update;
  if not found then
    return private.fail('not_found');
  end if;
  if v_kind = 'staff' and not (private.is_owner() and private.mfa_is_fresh()) then
    return private.fail('forbidden');
  end if;
  update public.invitations set status = 'revoked', revoked_by = (select auth.uid()), revoked_at = now()
   where id = p_invitation_id;
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Phase 2 object (6): accept_invitation adds two rejections (03 §4.1(a))
-- ---------------------------------------------------------------------------
-- A client invitation is rejected for a user with an active Sales role; a Sales staff
-- invitation is rejected for a user with an active project membership. Both are audited as
-- invitation.accept_failed with their reason, like every other failed acceptance.
create or replace function private.accept_invitation(p_invitation_id uuid, p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv public.invitations;
  v_user_email text;
  v_confirmed timestamptz;
  v_reason text;
begin
  if v_uid is null then
    return private.fail('invalid');
  end if;
  select * into v_inv from public.invitations where id = p_invitation_id for update;
  if not found then
    return private.fail('invalid');
  end if;
  select lower(u.email), u.email_confirmed_at into v_user_email, v_confirmed
    from auth.users u where u.id = v_uid;

  v_reason := case
    when v_inv.failed_attempts >= 10 then 'locked'
    -- A null token is the in-portal path for a signed-in user (spec 03 §6.1 step 2):
    -- it is bound only by the verified email below and never counts as a guess.
    when p_token is not null and v_inv.token_hash <> extensions.digest(p_token, 'sha256') then 'token_mismatch'
    when v_inv.status = 'accepted' then 'already_accepted'
    when v_inv.status = 'revoked' then 'revoked'
    when v_inv.expires_at <= now() then 'expired'
    when v_confirmed is null or v_user_email is distinct from v_inv.email::text then 'email_mismatch'
    when v_inv.kind = 'client' and exists (
      select 1 from public.projects where id = v_inv.project_id and archived_at is not null) then 'project_archived'
    when exists (select 1 from public.profiles where id = v_uid and status <> 'active') then 'user_inactive'
    -- WP-S (03 §4.1(a)): Sales Representatives and clients never overlap.
    when v_inv.kind = 'client' and exists (
      select 1 from public.staff_roles s where s.user_id = v_uid and s.status = 'active' and s.role = 'sales')
      then 'sales_role'
    when v_inv.kind = 'staff' and v_inv.intended_role = 'sales' and exists (
      select 1 from public.project_memberships m where m.user_id = v_uid and m.status = 'active')
      then 'client_membership'
  end;
  if v_reason is not null then
    if v_reason = 'token_mismatch' or (v_reason = 'email_mismatch' and p_token is not null) then
      update public.invitations set failed_attempts = failed_attempts + 1 where id = v_inv.id;
    end if;
    perform private.record_audit_event('invitation.accept_failed', 'invitations', v_inv.id::text,
      v_inv.project_id, null, jsonb_build_object('reason', v_reason, 'via', case when p_token is null then 'portal' else 'link' end));
    return private.fail('invalid');
  end if;

  insert into public.profiles (id, email, full_name)
  values (v_uid, v_user_email, v_inv.full_name)
  on conflict (id) do nothing;

  if v_inv.kind = 'client' then
    insert into public.project_memberships (project_id, user_id, invitation_id)
    select v_inv.project_id, v_uid, v_inv.id
    where not exists (
      select 1 from public.project_memberships
      where project_id = v_inv.project_id and user_id = v_uid and status = 'active'
    );
  else
    insert into public.staff_roles (user_id, role, granted_by)
    values (v_uid, v_inv.intended_role, v_inv.created_by)
    on conflict (user_id) do update
      set role = excluded.role, status = 'active', granted_by = excluded.granted_by,
          granted_at = now(), revoked_by = null, revoked_at = null, reason = null;
  end if;

  update public.invitations
     set status = 'accepted', accepted_by = v_uid, accepted_at = now()
   where id = v_inv.id;

  return jsonb_build_object('ok', true, 'kind', v_inv.kind, 'project_id', v_inv.project_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Phase 2 object (7): set_staff_role adds one rejection (03 §4.1(a))
-- ---------------------------------------------------------------------------
create or replace function private.set_staff_role(p_user_id uuid, p_role public.staff_role, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() or not private.mfa_is_fresh() or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  if p_role = 'fulfillment' then
    perform private.record_audit_event('staff_role.fulfillment_assignment_attempted', 'staff_roles',
      p_user_id::text, null, p_reason);
    return private.fail('role_not_assignable');
  end if;
  -- WP-S: the Sales role is never given to a user with an active project membership.
  if p_role = 'sales' and exists (
    select 1 from public.project_memberships m where m.user_id = p_user_id and m.status = 'active'
  ) then
    perform private.record_audit_event('staff_role.sales_assignment_rejected', 'staff_roles',
      p_user_id::text, null, nullif(btrim(p_reason), ''), jsonb_build_object('reason', 'client_membership'));
    return private.fail('client_membership');
  end if;
  update public.staff_roles set role = p_role, status = 'active', reason = nullif(btrim(p_reason), ''),
         revoked_at = null, revoked_by = null
   where user_id = p_user_id;
  if not found then
    return private.fail('not_found');
  end if;
  return jsonb_build_object('ok', true);
exception
  when insufficient_privilege then
    -- The failed change is rolled back; the protected attempt itself is audited (spec 03 §11).
    perform private.record_audit_event('staff_role.last_owner_protected', 'staff_roles', p_user_id::text,
      null, nullif(btrim(p_reason), ''));
    return private.fail('last_owner');
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Sales functions (03 §4.1; OI-77 refinements 3-5; OI-78; OI-83; OI-84(e))
-- ---------------------------------------------------------------------------
-- Customer, project, and self-assignment in ONE transaction (refinement 3). Any failure
-- leaves none of the three. Concurrent duplicate requests from the same representative are
-- serialized by a per-user transaction lock and return the set the first one created.
create function private.sales_create_customer_project(
  p_legal_name text,
  p_display_name text,
  p_project_name text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_legal text := btrim(coalesce(p_legal_name, ''));
  v_display text := btrim(coalesce(nullif(btrim(coalesce(p_display_name, '')), ''), p_legal_name, ''));
  v_name text := btrim(coalesce(p_project_name, ''));
  v_business uuid;
  v_project uuid;
  v_assignment uuid;
begin
  if not private.is_sales() then
    return private.fail('forbidden');
  end if;
  if not private.consume_rate_limit('sales-customer:' || v_uid, 10, interval '1 hour') then
    perform private.record_audit_event('sales.rate_limited', 'client_businesses', null, null, null,
      jsonb_build_object('operation', 'customer_create'));
    return private.fail('rate_limited');
  end if;
  if char_length(v_legal) not between 1 and 200 or char_length(v_display) not between 1 and 200
     or char_length(v_name) not between 1 and 200 then
    return private.fail('invalid_input');
  end if;

  perform pg_advisory_xact_lock(hashtextextended('sales_create_customer_project:' || v_uid::text, 0));
  select p.id, b.id, a.id into v_project, v_business, v_assignment
  from public.project_sales_assignments a
  join public.projects p on p.id = a.project_id and p.archived_at is null
  join public.client_businesses b on b.id = p.client_business_id
  where a.sales_user_id = v_uid and a.active and a.assigned_by = v_uid
    and p.created_by = v_uid and b.created_by = v_uid
    and lower(b.legal_name) = lower(v_legal) and lower(p.name) = lower(v_name)
  limit 1;
  if v_project is not null then
    return jsonb_build_object('ok', true, 'existing', true, 'client_business_id', v_business,
      'project_id', v_project, 'assignment_id', v_assignment);
  end if;

  begin
    insert into public.client_businesses (legal_name, display_name) values (v_legal, v_display)
    returning id into v_business;
    insert into public.projects (client_business_id, name) values (v_business, v_name)
    returning id into v_project;
    insert into public.project_sales_assignments (project_id, sales_user_id, assigned_by)
    values (v_project, v_uid, v_uid) returning id into v_assignment;
    perform private.record_audit_event('sales.customer_created', 'project', v_project::text, v_project, null,
      jsonb_build_object('client_business_id', v_business, 'assignment_id', v_assignment));
    perform private.record_audit_event('sales_assignment.created', 'project_sales_assignments',
      v_assignment::text, v_project, null,
      jsonb_build_object('sales_user_id', v_uid, 'via', 'customer_creation'));
  exception
    when check_violation or invalid_text_representation or not_null_violation then
      return private.fail('invalid_input');
  end;
  return jsonb_build_object('ok', true, 'existing', false, 'client_business_id', v_business,
    'project_id', v_project, 'assignment_id', v_assignment);
end;
$$;

-- Owner or Admin assigns (or reassigns) a project to a Sales Representative. A Sales
-- Representative can never change any assignment (03 §4.1 "Assignment").
create function private.assign_sales_representative(p_project_id uuid, p_sales_user_id uuid, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_current public.project_sales_assignments%rowtype;
  v_id uuid;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not (private.is_staff() and private.is_aal2() and private.session_is_active()) then
    if coalesce(private.staff_role_of(v_uid) = 'sales', false) then
      perform private.record_audit_event('sales_assignment.change_rejected', 'project_sales_assignments', null,
        p_project_id, null, jsonb_build_object('operation', 'assign'));
    end if;
    return private.fail('forbidden');
  end if;
  perform 1 from public.projects where id = p_project_id and archived_at is null for update;
  if not found then
    return private.fail('project_not_found');
  end if;
  if coalesce(private.staff_role_of(p_sales_user_id) = 'sales', false) is not true then
    return private.fail('not_sales_representative');
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    return private.fail('invalid_input');
  end if;
  select * into v_current from public.project_sales_assignments
   where project_id = p_project_id and active for update;
  if found and v_current.sales_user_id = p_sales_user_id then
    return jsonb_build_object('ok', true, 'assignment_id', v_current.id, 'existing', true);
  end if;
  if found then
    update public.project_sales_assignments
       set active = false, ended_at = now(), ended_by = v_uid, end_reason = coalesce(v_reason, 'Reassigned')
     where id = v_current.id;
  end if;
  insert into public.project_sales_assignments (project_id, sales_user_id, assigned_by)
  values (p_project_id, p_sales_user_id, v_uid) returning id into v_id;
  if v_current.id is not null then
    perform private.record_audit_event('sales_assignment.reassigned', 'project_sales_assignments', v_id::text,
      p_project_id, v_reason, jsonb_build_object('previous_assignment_id', v_current.id,
        'previous_sales_user_id', v_current.sales_user_id, 'sales_user_id', p_sales_user_id));
  else
    perform private.record_audit_event('sales_assignment.created', 'project_sales_assignments', v_id::text,
      p_project_id, v_reason, jsonb_build_object('sales_user_id', p_sales_user_id, 'via', 'staff'));
  end if;
  return jsonb_build_object('ok', true, 'assignment_id', v_id, 'existing', false);
end;
$$;

create function private.end_sales_assignment(p_assignment_id uuid, p_reason text default null)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_row public.project_sales_assignments%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not (private.is_staff() and private.is_aal2() and private.session_is_active()) then
    if coalesce(private.staff_role_of(v_uid) = 'sales', false) then
      perform private.record_audit_event('sales_assignment.change_rejected', 'project_sales_assignments',
        null, null, null, jsonb_build_object('operation', 'end'));
    end if;
    return private.fail('forbidden');
  end if;
  if v_reason is not null and char_length(v_reason) > 500 then
    return private.fail('invalid_input');
  end if;
  select * into v_row from public.project_sales_assignments where id = p_assignment_id and active for update;
  if not found then
    return private.fail('not_found');
  end if;
  update public.project_sales_assignments
     set active = false, ended_at = now(), ended_by = v_uid, end_reason = v_reason
   where id = v_row.id;
  perform private.record_audit_event('sales_assignment.ended', 'project_sales_assignments', v_row.id::text,
    v_row.project_id, v_reason, jsonb_build_object('sales_user_id', v_row.sales_user_id));
  return jsonb_build_object('ok', true);
end;
$$;

-- The representative's own customers: ACTIVE assignments to non-archived projects only.
-- Ended assignments are hidden (OI-78 item 2).
create function private.sales_list_customers() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_sales() then
    return private.fail('forbidden');
  end if;
  return jsonb_build_object('ok', true, 'customers', coalesce((
    select jsonb_agg(jsonb_build_object(
      'project_id', p.id, 'project_name', p.name,
      'client_business_id', b.id, 'business_legal_name', b.legal_name, 'business_display_name', b.display_name,
      'assigned_at', a.assigned_at) order by a.assigned_at desc, p.id)
    from public.project_sales_assignments a
    join public.projects p on p.id = a.project_id and p.archived_at is null
    join public.client_businesses b on b.id = p.client_business_id
    where a.sales_user_id = (select auth.uid()) and a.active
  ), '[]'::jsonb));
end;
$$;

-- Commercial progress of one assigned project (03 §4.1; OI-72, OI-83, OI-84(e)). Derived
-- states only, read through the two gate interfaces and the single publication evaluator;
-- the agreed order-summary pricing (total, deposit, remaining contractual balance); and
-- the project's pending client invitations with the minimum fields. Never paid amounts,
-- invoices, ledger entries, refunds, disputes, holds' records, tokens, token hashes, or
-- failed-attempt counts. An unassigned project is indistinguishable from a missing one.
create function private.sales_project_progress(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_project public.projects%rowtype;
  v_business public.client_businesses%rowtype;
  v_fin private.project_financial_status;
  v_ful private.project_fulfillment_status;
  v_summary public.order_summaries%rowtype;
  v_eligible boolean := false;
begin
  if not (private.sales_assigned(p_project_id)
          or (private.is_staff() and private.is_aal2() and private.session_is_active())) then
    return private.fail('not_found');
  end if;
  select * into v_project from public.projects where id = p_project_id and archived_at is null;
  if not found then
    return private.fail('not_found');
  end if;
  select * into v_business from public.client_businesses where id = v_project.client_business_id;
  v_fin := private.project_financial_status(p_project_id);
  v_ful := private.project_fulfillment_status(p_project_id);
  if v_ful.current_release_id is not null then
    v_eligible := coalesce((private.evaluate_publication_gates(p_project_id, v_ful.current_release_id)
                            ->> 'eligible')::boolean, false);
  end if;
  select * into v_summary from public.order_summaries
   where project_id = p_project_id order by revision desc limit 1;

  return jsonb_build_object(
    'ok', true,
    'project', jsonb_build_object('id', v_project.id, 'name', v_project.name, 'created_at', v_project.created_at),
    'business', jsonb_build_object('legal_name', v_business.legal_name, 'display_name', v_business.display_name),
    'order_summary', case when v_summary.id is null then null else jsonb_build_object(
      'id', v_summary.id, 'revision', v_summary.revision, 'status', v_summary.status,
      'package_key', v_summary.package_key,
      'package_display_name', (select bp.display_name from private.billing_packages bp where bp.package_key = v_summary.package_key),
      'package_total_cents', v_summary.package_total_cents, 'deposit_cents', v_summary.deposit_cents,
      'balance_cents', v_summary.balance_cents, 'maintenance_monthly_cents', v_summary.maintenance_monthly_cents,
      'currency', v_summary.currency, 'scope_items', v_summary.scope_items, 'issued_at', v_summary.issued_at) end,
    'progress', jsonb_build_object(
      'agreement_state', v_fin.agreement_state,
      'agreement_effective', coalesce(v_fin.agreement_effective, false),
      'deposit_requirement_satisfied', coalesce(v_fin.deposit_verified, false),
      'final_balance_requirement_satisfied', coalesce(v_fin.balance_verified_or_settled, false),
      'billing_operational_hold', coalesce(cardinality(v_fin.active_billing_holds), 0) > 0,
      'intake_state', v_ful.intake_state,
      'preview_approved', coalesce(v_ful.current_release_approved, false),
      'publication_eligible', v_eligible),
    'pending_invitations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'email', i.email::text, 'full_name', i.full_name,
        'status', case when i.expires_at <= now() then 'expired' else 'pending' end,
        'sent_at', i.created_at, 'expires_at', i.expires_at) order by i.created_at desc, i.id)
      from public.invitations i
      where i.project_id = p_project_id and i.kind = 'client' and i.status = 'pending'
    ), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. WP-B integration: private.issue_order_summary with one added caller (AUTH-005)
-- ---------------------------------------------------------------------------
-- Replaces the definition in 20261124160000_wpb_agreements.sql. Differences, all for the
-- Sales caller only (v_sales): the alternative caller private.sales_assigned(p_project_id);
-- (i) a non-empty p_scope_items or any p_project_notes is rejected and audited; (ii) scope
-- items are copied from private.current_package_scope(p_package_key), project notes are
-- null, and the scope version is recorded in the order_summary.issued audit metadata; (iii)
-- a missing scope definition fails closed; (iv) after the existing project and order-summary
-- row locks (the same lock accept_agreement takes), any agreement acceptance or verified
-- deposit on the project rejects the call. The Owner and Admin path is byte-for-byte the
-- WP-B logic. WP-B reviews this replacement.
create or replace function private.issue_order_summary(
  p_project_id uuid,
  p_package_key text,
  p_scope_items jsonb default '[]'::jsonb,
  p_project_notes text default null,
  p_change_reason text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_project public.projects%rowtype;
  v_legal_name text;
  v_version_id uuid;
  v_version_hash text;
  v_prices record;
  v_current public.order_summaries%rowtype;
  v_paid_summary public.order_summaries%rowtype;
  v_revision integer;
  v_id uuid;
  v_effective_acceptance boolean := false;
  v_event bigint;
  v_sales boolean := false;
  v_scope_version integer;
begin
  if not (private.is_staff() and private.is_aal2() and private.session_is_active()) then
    -- WP-S: the one added caller, an actively assigned Sales Representative.
    if not private.sales_assigned(p_project_id) then
      return private.fail('forbidden');
    end if;
    v_sales := true;
  end if;
  select * into v_project from public.projects where id = p_project_id and archived_at is null for update;
  if not found then
    return private.fail('project_not_found');
  end if;
  if v_sales then
    -- OI-84(b): the representative supplies only the package key and a change reason.
    if p_scope_items is not null and p_scope_items <> '[]'::jsonb then
      perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
        p_project_id, null, jsonb_build_object('reason', 'scope_input'), 'general');
      return private.fail('scope_not_allowed');
    end if;
    if p_project_notes is not null then
      perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
        p_project_id, null, jsonb_build_object('reason', 'notes_input'), 'general');
      return private.fail('notes_not_allowed');
    end if;
    select coalesce(jsonb_agg(to_jsonb(s.item_text) order by s.item_position), '[]'::jsonb), max(s.scope_version)
      into p_scope_items, v_scope_version
      from private.current_package_scope(p_package_key) s;
    if v_scope_version is null then
      perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
        p_project_id, null, jsonb_build_object('reason', 'missing_scope_definition'), 'general');
      return private.fail('scope_definition_missing');
    end if;
  end if;
  if p_scope_items is null or jsonb_typeof(p_scope_items) <> 'array'
     or exists (select 1 from jsonb_array_elements(p_scope_items) e
                where jsonb_typeof(e) <> 'string' or char_length(e #>> '{}') not between 1 and 300) then
    return private.fail('invalid_input');
  end if;
  select legal_name into v_legal_name from public.client_businesses where id = v_project.client_business_id;

  select v.id, v.text_sha256 into v_version_id, v_version_hash
  from public.agreement_versions v
  where private.agreement_version_usable(v.id)
  order by v.effective_from desc, v.created_at desc
  limit 1;
  if v_version_id is null then
    return private.fail('no_usable_agreement_version');
  end if;

  select * into v_prices from private.verified_package_prices(p_package_key);
  if not found then
    perform private.record_audit_event('order_summary.catalog_mismatch', 'project', p_project_id::text,
      p_project_id, null, jsonb_build_object('package_key', left(p_package_key, 40)), 'general');
    return private.fail('catalog_mismatch');
  end if;

  -- OI-81 (approved, R1): once the deposit is verified, the agreed price is fixed. A new
  -- summary whose total, deposit, or balance differs from the order summary accepted with
  -- the verified deposit is rejected and audited.
  select os.* into v_paid_summary from public.order_summaries os
   where os.id = (select l.order_summary_id from public.ledger_entries l
                   where l.project_id = p_project_id and l.entry_type = 'deposit_charge' order by l.id limit 1);
  if v_paid_summary.id is not null
     and (v_paid_summary.package_total_cents, v_paid_summary.deposit_cents, v_paid_summary.balance_cents)
         is distinct from (v_prices.total_cents, v_prices.deposit_cents, v_prices.balance_cents) then
    perform private.record_audit_event('order_summary.price_change_rejected', 'project', p_project_id::text,
      p_project_id, p_change_reason,
      jsonb_build_object('accepted_order_summary_id', v_paid_summary.id, 'requested_package_key', left(p_package_key, 40)),
      'general');
    return private.fail('price_change_after_deposit');
  end if;

  select * into v_current from public.order_summaries
   where project_id = p_project_id and status = 'presented' for update;
  -- OI-84(c): no Sales replacement once the project has any acceptance or a verified deposit.
  -- Checked after the order-summary row lock that accept_agreement also takes, so a
  -- concurrent acceptance and Sales replacement serialize and never both succeed.
  if v_sales and (
    exists (select 1 from public.agreement_acceptances a where a.project_id = p_project_id)
    or private.project_deposit_ever_verified(p_project_id)
  ) then
    perform private.record_audit_event('sales.order_summary_rejected', 'project', p_project_id::text,
      p_project_id, null, jsonb_build_object('reason', 'after_acceptance'), 'general');
    return private.fail('replacement_after_acceptance');
  end if;
  if found then
    if nullif(btrim(coalesce(p_change_reason, '')), '') is null then
      return private.fail('reason_required');
    end if;
    v_effective_acceptance := private.project_deposit_ever_verified(p_project_id)
      and exists (select 1 from public.agreement_acceptances a where a.order_summary_id = v_current.id);
    update public.order_summaries set status = 'superseded' where id = v_current.id;
    perform private.record_audit_event('order_summary.superseded', 'order_summary', v_current.id::text,
      p_project_id, p_change_reason, '{}'::jsonb, 'general');
  end if;

  select coalesce(max(revision), 0) + 1 into v_revision from public.order_summaries where project_id = p_project_id;
  insert into public.order_summaries (
    project_id, revision, agreement_version_id, agreement_text_sha256, package_key, package_total_cents,
    deposit_cents, balance_cents, maintenance_monthly_cents, catalog_environment, catalog_version,
    deposit_price_id, balance_price_id, maintenance_price_id, scope_items, project_notes,
    business_legal_name, snapshot_sha256, supersedes_id, change_reason, issued_by)
  values (
    p_project_id, v_revision, v_version_id, v_version_hash, p_package_key, v_prices.total_cents,
    v_prices.deposit_cents, v_prices.balance_cents, private.maintenance_monthly_cents(), private.stripe_mode(),
    v_prices.catalog_version, v_prices.deposit_price_id, v_prices.balance_price_id, v_prices.maintenance_price_id,
    p_scope_items, nullif(btrim(coalesce(p_project_notes, '')), ''), v_legal_name, repeat('0', 64),
    v_current.id, nullif(btrim(coalesce(p_change_reason, '')), ''), v_uid)
  returning id into v_id;

  perform private.record_audit_event('order_summary.issued', 'order_summary', v_id::text, p_project_id,
    p_change_reason, jsonb_build_object('revision', v_revision, 'package_key', p_package_key)
      || case when v_sales then jsonb_build_object('scope_version', v_scope_version) else '{}'::jsonb end,
    'general');
  v_event := private.emit_domain_event('order_summary.issued', p_project_id, 'order_summary', v_id::text,
    jsonb_build_object('revision', v_revision, 'supersedes_id', v_current.id),
    'order_summary.issued:' || v_id::text);
  if v_effective_acceptance then
    perform private.record_audit_event('agreement.reacceptance_required', 'order_summary', v_id::text,
      p_project_id, p_change_reason, '{}'::jsonb, 'general');
    v_event := private.emit_domain_event('agreement.reacceptance_required', p_project_id, 'order_summary',
      v_id::text, jsonb_build_object('superseded_order_summary_id', v_current.id),
      'agreement.reacceptance_required:' || v_id::text);
    perform private.enqueue_notification('agreement.reacceptance_required',
      'agreement.reacceptance_required:' || v_id::text || ':1', 'agreement.reacceptance_required', 1,
      p_project_id, v_event, private.project_client_user_ids(p_project_id), '{owner}',
      jsonb_build_object('order_summary_id', v_id), 'general');
  end if;
  return jsonb_build_object('ok', true, 'order_summary_id', v_id, 'revision', v_revision);
exception
  when check_violation or invalid_text_representation then
    return private.fail('invalid_input');
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Exposed RPC wrappers (public, SECURITY INVOKER) on the Phase 2 pattern
-- ---------------------------------------------------------------------------
create function public.sales_create_customer_project(p_legal_name text, p_display_name text, p_project_name text)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.sales_create_customer_project(p_legal_name, p_display_name, p_project_name);
$$;
create function public.assign_sales_representative(p_project_id uuid, p_sales_user_id uuid, p_reason text default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.assign_sales_representative(p_project_id, p_sales_user_id, p_reason);
$$;
create function public.end_sales_assignment(p_assignment_id uuid, p_reason text default null)
returns jsonb language sql security invoker set search_path = '' as $$
  select private.end_sales_assignment(p_assignment_id, p_reason);
$$;
create function public.sales_list_customers()
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.sales_list_customers();
$$;
create function public.sales_project_progress(p_project_id uuid)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.sales_project_progress(p_project_id);
$$;

-- ---------------------------------------------------------------------------
-- 12. Privileges, RLS, and the restrictive-policy loops (03 §9; T-TEN-05, T-TEN-06)
-- ---------------------------------------------------------------------------
revoke all on function
  private.project_sales_assignments_guard(), private.project_sales_assignments_history(),
  private.is_sales(), private.sales_assigned(uuid),
  private.billing_package_scope_fixture_guard(), private.current_package_scope(text),
  private.sales_create_customer_project(text, text, text),
  private.assign_sales_representative(uuid, uuid, text), private.end_sales_assignment(uuid, text),
  private.sales_list_customers(), private.sales_project_progress(uuid),
  public.sales_create_customer_project(text, text, text),
  public.assign_sales_representative(uuid, uuid, text), public.end_sales_assignment(uuid, text),
  public.sales_list_customers(), public.sales_project_progress(uuid)
from public, anon, authenticated, service_role;

-- The RLS helpers and the definer functions the invoker wrappers call (Phase 2 pattern).
grant execute on function
  private.is_sales(), private.sales_assigned(uuid),
  private.sales_create_customer_project(text, text, text),
  private.assign_sales_representative(uuid, uuid, text), private.end_sales_assignment(uuid, text),
  private.sales_list_customers(), private.sales_project_progress(uuid),
  public.sales_create_customer_project(text, text, text),
  public.assign_sales_representative(uuid, uuid, text), public.end_sales_assignment(uuid, text),
  public.sales_list_customers(), public.sales_project_progress(uuid)
to authenticated;
-- private.current_package_scope and private.billing_package_scope: no API role (OI-84(b)).

alter table public.project_sales_assignments enable row level security;
alter table public.project_sales_assignment_history enable row level security;

revoke all on table public.project_sales_assignments, public.project_sales_assignment_history
  from public, anon, authenticated;
-- No direct write by any API role, including service_role (AUTH-005).
revoke insert, update, delete, truncate, references, trigger
  on table public.project_sales_assignments, public.project_sales_assignment_history from service_role;
grant select on table public.project_sales_assignments, public.project_sales_assignment_history to authenticated;

-- Owner and Admin read all; a Sales Representative reads only its own ACTIVE rows, in a
-- fully authenticated session (aal2, live session); history is Owner and Admin only.
create policy project_sales_assignments_select on public.project_sales_assignments for select to authenticated
  using ((select private.is_staff())
         or (sales_user_id = (select auth.uid()) and active and (select private.is_sales())));
create policy project_sales_assignment_history_select on public.project_sales_assignment_history
  for select to authenticated using ((select private.is_staff()));

do $$
declare
  t text;
begin
  foreach t in array array['project_sales_assignments', 'project_sales_assignment_history'] loop
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
