-- OI-120: private.is_owner() is NULL-safe (AUTH-019, Owner 2026-11-27).
--
-- Rules for this file:
-- - Forward-only. Never edit after merge (T-MIG-02).
-- - Changes exactly one object: the body of private.is_owner(). Every attribute is kept (language
--   sql, stable, security definer, empty search_path, owner, privileges); CREATE OR REPLACE keeps the
--   owner and the ACL. No call site, policy, grant or other function changes, including
--   private.staff_role_of.
--
-- private.is_owner() returned NULL (not false) for a caller without an active staff role, so a guard
-- of the form `if not (private.is_owner() and ...)` did not refuse. It now returns false for every
-- caller who is not an active Owner, and every guard that calls it (directly or through
-- private.owner_ok) inherits the fix.
create or replace function private.is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.staff_role_of((select auth.uid())) = 'owner', false);
$$;
