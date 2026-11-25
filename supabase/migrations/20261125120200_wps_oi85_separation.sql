-- WP-S correction (PR #23 review): staff/client separation in the database, and append-only
-- package-scope versions. Decisions: OI-85 (Owner, 2026-11-25), DEP-18 append-only versions
-- (Owner, 2026-11-25). Authorization: AUTH-005 with the OI-85 amendment. Directive:
-- CURRENT-STATE §12, exact object inventory C1 to C5 (nothing else).
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02). The two reviewed WP-S migrations
--   (20261125120000, 20261125120100) are unchanged.
-- - Existing data is never repaired, deleted, or rewritten: a conflict found here stops the
--   migration (C4).
-- - Two distinct rules (CURRENT-STATE §12): C1 is universal (no staff role of any kind gets
--   client-only authorization through a membership); C2 and C3 are Sales-specific integrity
--   constraints (03 §4.1(a)): Owner and Admin memberships stay permitted and, under C1, grant
--   no client authorization.
-- - The triggers apply to every writer, including service_role and the migration owner. They
--   do not protect against a database owner who deliberately disables or replaces them.

-- ---------------------------------------------------------------------------
-- C4. Migration-time conflict check: stop, never repair (runs before C2 and C3 exist)
-- ---------------------------------------------------------------------------
do $$
declare
  v_conflicts integer;
begin
  select count(distinct s.user_id) into v_conflicts
  from public.staff_roles s
  join public.project_memberships m on m.user_id = s.user_id and m.status = 'active'
  where s.status = 'active' and s.role = 'sales';
  if v_conflicts > 0 then
    raise exception 'OI-85: % user(s) hold an active Sales role and an active project membership; resolve them before this migration (no data was changed)', v_conflicts
      using errcode = '23514';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- C1. private.is_project_member: no staff role of any kind (Phase 2; same signature, grants)
-- ---------------------------------------------------------------------------
-- The same client test as private.wpc_is_client_member. Every caller that serves staff ORs
-- private.is_staff() (can_access_project, the policies), so Owner and Admin are unaffected;
-- clients hold no staff role and are unaffected. Fails closed even with inconsistent data.
create or replace function private.is_project_member(p_project uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_active_user()
     and private.staff_role_of((select auth.uid())) is null
     and not exists (
       select 1 from public.staff_roles s where s.user_id = (select auth.uid()) and s.status = 'active')
     and exists (
       select 1 from public.project_memberships m
       where m.project_id = p_project and m.user_id = (select auth.uid()) and m.status = 'active'
     );
$$;

-- ---------------------------------------------------------------------------
-- C2. No active membership for a user with an active Sales role (every writer)
-- ---------------------------------------------------------------------------
-- The per-user lock is the one accept_invitation and set_staff_role('sales') already take
-- first (re-entrant within a transaction), so those paths are unchanged; a direct writer takes
-- it here. The check runs after the lock, so concurrent conflicting writes serialize.
create function private.project_memberships_sales_separation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'active' then
    perform pg_advisory_xact_lock(hashtextextended('wps-role-membership:' || new.user_id::text, 0));
    if exists (
      select 1 from public.staff_roles s
      where s.user_id = new.user_id and s.status = 'active' and s.role = 'sales'
    ) then
      raise exception 'OI-85: a user with an active Sales role cannot hold an active project membership'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger project_memberships_sales_separation
  before insert or update on public.project_memberships
  for each row execute function private.project_memberships_sales_separation();

-- ---------------------------------------------------------------------------
-- C3. No active Sales role for a user with an active membership (every writer)
-- ---------------------------------------------------------------------------
create function private.staff_roles_sales_separation() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'active' and new.role = 'sales' then
    perform pg_advisory_xact_lock(hashtextextended('wps-role-membership:' || new.user_id::text, 0));
    if exists (
      select 1 from public.project_memberships m
      where m.user_id = new.user_id and m.status = 'active'
    ) then
      raise exception 'OI-85: a user with an active project membership cannot hold an active Sales role'
        using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger staff_roles_sales_separation
  before insert or update on public.staff_roles
  for each row execute function private.staff_roles_sales_separation();

-- ---------------------------------------------------------------------------
-- C5. Append-only package-scope versions (DEP-18, Owner 2026-11-25)
-- ---------------------------------------------------------------------------
-- An existing version is never updated, deleted, or replaced in place; a new contractual
-- definition is a new version (new rows). The existing guards are reused unchanged. Named so
-- they fire before the fixture allowlist trigger, which is unchanged.
create trigger billing_package_scope_append_only
  before update or delete on private.billing_package_scope
  for each row execute function private.insert_only();
create trigger billing_package_scope_no_truncate
  before truncate on private.billing_package_scope
  for each statement execute function private.audit_events_immutable();

-- ---------------------------------------------------------------------------
-- Privileges: trigger functions are not executable by any API role
-- ---------------------------------------------------------------------------
revoke all on function
  private.project_memberships_sales_separation(), private.staff_roles_sales_separation()
from public, anon, authenticated, service_role;
