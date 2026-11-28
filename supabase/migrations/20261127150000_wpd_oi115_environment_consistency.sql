-- OI-115 (AUTH-016, WP-I): environment classification consistency, local part.
--
-- Two database classifications exist:
-- - C1 `private.environment_settings` (WP-B, OI-69): development, test, preview or staging;
--   a missing row reads as production.
-- - C2 `private.runtime_environment` (WP-C, DEP-07): development or test only; a missing
--   row means the mocked malware scanner is never permitted.
-- Nothing enforced their agreement. Decision D1 (Owner, 2026-11-27): whenever they
-- disagree, `private.app_environment()` raises, so every environment-dependent privileged
-- path that reads it fails closed without being edited, and the scanner check requires
-- agreement. Decision D2: staging keeps no explicit row (both absent reads as production).
--
-- They agree when C2 is absent (C1 may be anything, including absent), or when C2 and C1
-- are both present with the same value. No table changes and no trigger or constraint is
-- added: the seed writes C2 and C1 in separate statements, and hosted databases have
-- neither row (AUTH-003 A3). The application compares APP_ENV with these values through
-- `public.environment_classification()` before any test seam activates.

create function private.environment_consistent() returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (select 1 from private.runtime_environment)
      or exists (select 1
                   from private.runtime_environment r
                   join private.environment_settings e on e.singleton
                  where r.singleton and e.app_env = r.app_env);
$$;
revoke all on function private.environment_consistent() from public, anon, authenticated, service_role;

create or replace function private.app_environment() returns text
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.environment_consistent() then
    raise exception 'environment classification disagreement (OI-115)' using errcode = '42501';
  end if;
  return coalesce((select e.app_env from private.environment_settings e where e.singleton), 'production');
end;
$$;

create or replace function private.scanner_permitted(p_scanner text) returns boolean
language sql stable security definer set search_path = '' as $$
  select p_scanner = 'mock_scanner'
     and private.environment_consistent()
     and exists (select 1 from private.runtime_environment where app_env in ('development', 'test'));
$$;

-- The raw classifications for the application check (OI-115 E2). It never raises, so the
-- application can report a disagreement. Server-only: execute for service_role alone, through
-- a security-invoker public wrapper (T-TEN-06: no SECURITY DEFINER function in public).
create function private.environment_classification() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'c1', (select e.app_env from private.environment_settings e where e.singleton),
    'c2', (select r.app_env from private.runtime_environment r where r.singleton));
$$;
revoke all on function private.environment_classification() from public, anon, authenticated;
grant execute on function private.environment_classification() to service_role;

create function public.environment_classification() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select private.environment_classification();
$$;
revoke all on function public.environment_classification() from public, anon, authenticated;
grant execute on function public.environment_classification() to service_role;
