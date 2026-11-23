-- Phase 2: authentication, security, and tenant isolation.
-- Specification: docs/03-SECURITY-AUTH-AND-TENANCY.md v0.4.0 (§5-§11, §16).
-- Forward-only. Never edit this file after it is merged (T-MIG-02).

-- ---------------------------------------------------------------------------
-- 0. Baseline: schemas, extensions, default privileges (spec 03 §9.1)
-- ---------------------------------------------------------------------------
create extension if not exists citext with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
-- Policies call private helpers as the querying role, which needs schema usage.
grant usage on schema private to authenticated, service_role;

-- Nothing created from here on is reachable by anon/authenticated unless granted.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema private revoke execute on functions from public, anon, authenticated;
alter default privileges revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- 1. Types
-- ---------------------------------------------------------------------------
create type public.staff_role as enum ('owner', 'admin', 'fulfillment');
create type public.grant_status as enum ('active', 'revoked');
create type public.profile_status as enum ('active', 'deactivated');
create type public.invitation_kind as enum ('client', 'staff');
create type public.invitation_status as enum ('pending', 'accepted', 'revoked');
create type public.membership_role as enum ('client');

-- ---------------------------------------------------------------------------
-- 2. Tables (spec 03 §8.1)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  email extensions.citext not null unique,
  full_name text not null check (char_length(full_name) between 1 and 200),
  status public.profile_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deactivated_at timestamptz
);

create table public.staff_roles (
  user_id uuid primary key references public.profiles (id) on delete restrict,
  -- 'fulfillment' is reserved for the future and must never be assignable (OI-03).
  role public.staff_role not null check (role <> 'fulfillment'),
  status public.grant_status not null default 'active',
  granted_by uuid references public.profiles (id),
  granted_at timestamptz not null default now(),
  revoked_by uuid references public.profiles (id),
  revoked_at timestamptz,
  reason text
);

create table public.client_businesses (
  id uuid primary key default gen_random_uuid(),
  legal_name text not null check (char_length(legal_name) between 1 and 200),
  display_name text not null check (char_length(display_name) between 1 and 200),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

-- No status column: project state is derived from authoritative records (OI-05).
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  client_business_id uuid not null references public.client_businesses (id) on delete restrict,
  name text not null check (char_length(name) between 1 and 200),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create index projects_client_business_id_idx on public.projects (client_business_id);

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  kind public.invitation_kind not null,
  email extensions.citext not null check (email::text = lower(btrim(email::text)) and position('@' in email::text) > 1),
  full_name text not null check (char_length(full_name) between 1 and 200),
  project_id uuid references public.projects (id) on delete restrict,
  intended_role public.staff_role,
  token_hash bytea not null unique,
  status public.invitation_status not null default 'pending',
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  accepted_by uuid references public.profiles (id),
  accepted_at timestamptz,
  revoked_by uuid references public.profiles (id),
  revoked_at timestamptz,
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  constraint invitations_kind_shape check (
    (kind = 'client' and project_id is not null and intended_role is null)
    or (kind = 'staff' and project_id is null and intended_role in ('owner', 'admin'))
  )
);
create unique index invitations_one_pending_client
  on public.invitations (email, project_id) where status = 'pending' and kind = 'client';
create unique index invitations_one_pending_staff
  on public.invitations (email) where status = 'pending' and kind = 'staff';
create index invitations_project_id_idx on public.invitations (project_id);

create table public.project_memberships (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete restrict,
  user_id uuid not null references public.profiles (id) on delete restrict,
  role public.membership_role not null default 'client',
  status public.grant_status not null default 'active',
  invitation_id uuid references public.invitations (id),
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles (id),
  revoke_reason text
);
create unique index project_memberships_one_active
  on public.project_memberships (project_id, user_id) where status = 'active';
create index project_memberships_user_status_idx on public.project_memberships (user_id, status);

create table public.audit_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_user_id uuid,
  actor_role text,
  actor_aal text,
  session_id uuid,
  action text not null,
  category text not null default 'general',
  target_type text,
  target_id text,
  project_id uuid,
  request_id text,
  ip text,
  user_agent text,
  reason text,
  summary jsonb not null default '{}'::jsonb,
  -- Bounded payloads at the database boundary (Phase 2 remediation D1): an append-only log
  -- can never be cleaned up, so oversized rows must be impossible to write.
  constraint audit_events_summary_bounded check (
    jsonb_typeof(summary) = 'object' and octet_length(summary::text) <= 8192),
  constraint audit_events_action_bounded check (char_length(action) between 1 and 100),
  constraint audit_events_reason_bounded check (reason is null or char_length(reason) <= 1000)
);
create index audit_events_project_time_idx on public.audit_events (project_id, occurred_at);
create index audit_events_actor_time_idx on public.audit_events (actor_user_id, occurred_at);

create table private.rate_limits (
  bucket text not null,
  window_start timestamptz not null,
  count integer not null default 0,
  primary key (bucket, window_start)
);

-- Belt and braces: no default grants on application tables for anon/authenticated.
revoke all on table public.profiles, public.staff_roles, public.client_businesses, public.projects,
  public.invitations, public.project_memberships, public.audit_events from anon, authenticated;
revoke all on table private.rate_limits from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Helper functions (private, security definer, search_path = '') (spec 03 §9.2)
-- ---------------------------------------------------------------------------
create function private.is_active_user() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p where p.id = (select auth.uid()) and p.status = 'active'
  );
$$;

create function private.staff_role_of(p_user uuid) returns public.staff_role
language sql stable security definer set search_path = '' as $$
  select s.role from public.staff_roles s
  join public.profiles p on p.id = s.user_id
  where s.user_id = p_user and s.status = 'active' and p.status = 'active';
$$;

create function private.is_staff() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.staff_role_of((select auth.uid())) is not null;
$$;

create function private.is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.staff_role_of((select auth.uid())) = 'owner';
$$;

create function private.is_project_member(p_project uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_active_user() and exists (
    select 1 from public.project_memberships m
    where m.project_id = p_project and m.user_id = (select auth.uid()) and m.status = 'active'
  );
$$;

create function private.can_access_project(p_project uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_staff() or private.is_project_member(p_project);
$$;

-- Storage paths are "<project_id>/..."; anything else is denied rather than raising.
create function private.can_access_project_path(p_name text) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  v_first text := split_part(p_name, '/', 1);
begin
  if v_first !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;
  return private.can_access_project(v_first::uuid);
exception
  when invalid_text_representation then
    return false;
end;
$$;

-- aal2 claim, and the caller still has a verified factor: a reset factor stops counting
-- immediately, not only after the token refreshes (spec 03 §7 "Factor removal", F-14).
create function private.is_aal2() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select auth.jwt()) ->> 'aal', 'aal1') = 'aal2'
     and exists (
       select 1 from auth.mfa_factors f
       where f.user_id = (select auth.uid()) and f.status = 'verified'
     );
$$;

-- Live check that the JWT's session still exists (sign-out deletes it; 03A F-17) and is
-- within the interim session limits of spec 03 §6.2 (pending OI-50, which may move them
-- to Supabase's Pro-plan session controls): staff 12 hours inactivity and a 7-day
-- time-box; clients 7 days inactivity. Activity is the last token refresh.
create function private.session_is_active() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.sessions s
    where s.id = nullif((select auth.jwt()) ->> 'session_id', '')::uuid
      and s.user_id = (select auth.uid())
      and (s.not_after is null or s.not_after > now())
      and case
        when private.staff_role_of(s.user_id) is not null then
          s.created_at > now() - interval '7 days'
          and greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC') > now() - interval '12 hours'
        else
          greatest(s.created_at, s.updated_at, s.refreshed_at at time zone 'UTC') > now() - interval '7 days'
      end
  );
$$;

-- Fresh MFA: any 'totp' amr entry within max_age. The amr array is not reliably
-- ordered most-recent-first after the first MFA verification (Phase 2 spike, 03A S-04),
-- so every entry is examined.
create function private.mfa_is_fresh(p_max_age interval default interval '5 minutes') returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_aal2() and exists (
    select 1
    from jsonb_array_elements(coalesce((select auth.jwt()) -> 'amr', '[]'::jsonb)) e
    where e ->> 'method' = 'totp'
      and to_timestamp((e ->> 'timestamp')::double precision) >= now() - p_max_age
  );
$$;

create function private.current_email() returns text
language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u where u.id = (select auth.uid());
$$;

-- ---------------------------------------------------------------------------
-- 4. Audit (append-only) (spec 03 §11)
-- ---------------------------------------------------------------------------
create function private.request_header(p_name text) returns text
language sql stable set search_path = '' as $$
  select nullif(current_setting('request.headers', true), '')::json ->> p_name;
$$;

create function private.record_audit_event(
  p_action text,
  p_target_type text default null,
  p_target_id text default null,
  p_project_id uuid default null,
  p_reason text default null,
  p_summary jsonb default '{}'::jsonb,
  p_category text default 'general'
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_role text;
begin
  v_role := coalesce(
    private.staff_role_of(v_uid)::text,
    case when v_uid is not null then 'client' end,
    case when ((select auth.jwt()) ->> 'role') = 'service_role' then 'system' end
  );
  insert into public.audit_events (
    actor_user_id, actor_role, actor_aal, session_id, action, category, target_type, target_id,
    project_id, request_id, ip, user_agent, reason, summary
  ) values (
    v_uid, v_role, (select auth.jwt()) ->> 'aal',
    nullif((select auth.jwt()) ->> 'session_id', '')::uuid,
    p_action, p_category, p_target_type, p_target_id, p_project_id,
    left(private.request_header('x-request-id'), 100),
    left(coalesce(private.request_header('x-client-ip'), private.request_header('x-forwarded-for')), 100),
    left(private.request_header('user-agent'), 300),
    left(coalesce(p_reason, nullif(current_setting('app.audit_reason', true), '')), 1000),
    coalesce(p_summary, '{}'::jsonb)
  );
end;
$$;

create function private.audit_events_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'audit_events is append-only' using errcode = '42501';
end;
$$;

create trigger audit_events_no_update_delete
  before update or delete on public.audit_events
  for each row execute function private.audit_events_immutable();
create trigger audit_events_no_truncate
  before truncate on public.audit_events
  for each statement execute function private.audit_events_immutable();

-- One audit event per row change on audited tables. Never records secret columns.
create function private.audit_row_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_action text;
  v_project uuid;
  v_target text;
  v_changed text[];
begin
  if tg_op = 'INSERT' then
    v_target := (to_jsonb(new) ->> coalesce(nullif(tg_argv[1], ''), 'id'));
    v_project := case tg_table_name
      when 'projects' then (to_jsonb(new) ->> 'id')::uuid
      when 'project_memberships' then (to_jsonb(new) ->> 'project_id')::uuid
      when 'invitations' then (to_jsonb(new) ->> 'project_id')::uuid
      else null end;
    v_action := tg_argv[0] || '.created';
    perform private.record_audit_event(v_action, tg_table_name, v_target, v_project, null,
      jsonb_build_object('fields', (select coalesce(jsonb_agg(k), '[]'::jsonb)
        from jsonb_object_keys(to_jsonb(new) - 'token_hash') k)));
    return new;
  end if;

  select coalesce(array_agg(n.key), '{}') into v_changed
  from jsonb_each(to_jsonb(new) - 'token_hash' - 'updated_at') n
  where n.value is distinct from (to_jsonb(old) -> n.key);
  if cardinality(v_changed) = 0 or v_changed = array['failed_attempts'] then
    return new;
  end if;

  v_target := (to_jsonb(new) ->> coalesce(nullif(tg_argv[1], ''), 'id'));
  v_project := case tg_table_name
    when 'projects' then (to_jsonb(new) ->> 'id')::uuid
    when 'project_memberships' then (to_jsonb(new) ->> 'project_id')::uuid
    when 'invitations' then (to_jsonb(new) ->> 'project_id')::uuid
    else null end;
  v_action := case
    when tg_table_name = 'invitations' and (to_jsonb(new) ->> 'status') is distinct from (to_jsonb(old) ->> 'status')
      then 'invitation.' || (to_jsonb(new) ->> 'status')
    when tg_table_name = 'project_memberships' and (to_jsonb(new) ->> 'status') = 'revoked'
      then 'membership.revoked'
    when tg_table_name = 'staff_roles' and (to_jsonb(new) ->> 'status') = 'revoked'
      then 'staff_role.revoked'
    when tg_table_name = 'staff_roles' then 'staff_role.changed'
    when tg_table_name = 'profiles' and (to_jsonb(new) ->> 'status') is distinct from (to_jsonb(old) ->> 'status')
      then 'user.' || case (to_jsonb(new) ->> 'status') when 'deactivated' then 'deactivated' else 'reactivated' end
    else tg_argv[0] || '.updated'
  end;
  perform private.record_audit_event(v_action, tg_table_name, v_target, v_project,
    nullif(coalesce(to_jsonb(new) ->> 'reason', to_jsonb(new) ->> 'revoke_reason'), ''),
    jsonb_build_object('changed', to_jsonb(v_changed)));
  return new;
end;
$$;

create trigger audit_profiles after insert or update on public.profiles
  for each row execute function private.audit_row_change('profile', 'id');
create trigger audit_staff_roles after insert or update on public.staff_roles
  for each row execute function private.audit_row_change('staff_role', 'user_id');
create trigger audit_client_businesses after insert or update on public.client_businesses
  for each row execute function private.audit_row_change('client_business', 'id');
create trigger audit_projects after insert or update on public.projects
  for each row execute function private.audit_row_change('project', 'id');
create trigger audit_project_memberships after insert or update on public.project_memberships
  for each row execute function private.audit_row_change('membership', 'id');
create trigger audit_invitations after insert or update on public.invitations
  for each row execute function private.audit_row_change('invitation', 'id');

-- ---------------------------------------------------------------------------
-- 5. Integrity triggers
-- ---------------------------------------------------------------------------
create function private.set_created_by() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.created_by := (select auth.uid());
  if new.created_by is null then
    raise exception 'created_by requires an authenticated user' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger client_businesses_created_by before insert on public.client_businesses
  for each row execute function private.set_created_by();
create trigger projects_created_by before insert on public.projects
  for each row execute function private.set_created_by();

create function private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger profiles_updated_at before update on public.profiles
  for each row execute function private.touch_updated_at();

-- At least one active Owner must always exist (spec 03 §3, T-ROLE-08).
create function private.protect_last_owner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.role = 'owner' and old.status = 'active'
     and (tg_op = 'DELETE' or new.role <> 'owner' or new.status <> 'active')
     and not exists (
       select 1 from public.staff_roles s
       join public.profiles p on p.id = s.user_id and p.status = 'active'
       where s.role = 'owner' and s.status = 'active' and s.user_id <> old.user_id
     ) then
    raise exception 'the last active Owner cannot be removed or demoted' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
create trigger staff_roles_protect_last_owner before update or delete on public.staff_roles
  for each row execute function private.protect_last_owner();

create function private.protect_last_owner_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'active' and new.status <> 'active'
     and private.staff_role_of(old.id) = 'owner'
     and not exists (
       select 1 from public.staff_roles s
       join public.profiles p on p.id = s.user_id and p.status = 'active'
       where s.role = 'owner' and s.status = 'active' and s.user_id <> old.id
     ) then
    raise exception 'the last active Owner cannot be deactivated' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger profiles_protect_last_owner before update on public.profiles
  for each row execute function private.protect_last_owner_profile();

-- ---------------------------------------------------------------------------
-- 6. Rate limiting (spec 03 §17). Fixed windows; callable by the server only.
-- ---------------------------------------------------------------------------
create function private.consume_rate_limit(p_bucket text, p_limit integer, p_window interval)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_window timestamptz := to_timestamp(floor(extract(epoch from now()) / extract(epoch from p_window)) * extract(epoch from p_window));
  v_count integer;
begin
  insert into private.rate_limits as r (bucket, window_start, count)
  values (p_bucket, v_window, 1)
  on conflict (bucket, window_start) do update set count = r.count + 1
  returning r.count into v_count;
  delete from private.rate_limits where window_start < now() - interval '2 days';
  return v_count <= p_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Invitation and authorization actions (spec 03 §6.1, §7). Return jsonb; never
--    raise for expected failures, so failure audit rows and attempt counters persist.
-- ---------------------------------------------------------------------------
create function private.fail(p_code text) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('ok', false, 'error', p_code);
$$;

create function private.create_invitation(
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
begin
  if not private.is_staff() or not private.is_aal2() or not private.session_is_active() then
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

-- Server-side pre-check before sign-in (service role only): is this invitation link valid?
create function private.check_invitation_link(p_invitation_id uuid, p_token text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_inv public.invitations;
begin
  select * into v_inv from public.invitations where id = p_invitation_id for update;
  if not found then
    return private.fail('invalid');
  end if;
  if v_inv.failed_attempts >= 10 then
    return private.fail('invalid');
  end if;
  if v_inv.token_hash <> extensions.digest(coalesce(p_token, ''), 'sha256') then
    update public.invitations set failed_attempts = failed_attempts + 1 where id = v_inv.id;
    perform private.record_audit_event('invitation.link_check_failed', 'invitations', v_inv.id::text,
      v_inv.project_id, null, jsonb_build_object('reason', 'token_mismatch'));
    return private.fail('invalid');
  end if;
  if v_inv.status <> 'pending' or v_inv.expires_at <= now() then
    perform private.record_audit_event('invitation.link_check_failed', 'invitations', v_inv.id::text,
      v_inv.project_id, null, jsonb_build_object('reason', case when v_inv.status <> 'pending' then v_inv.status::text else 'expired' end));
    return private.fail('invalid');
  end if;
  return jsonb_build_object('ok', true, 'email', v_inv.email::text);
end;
$$;

create function private.accept_invitation(p_invitation_id uuid, p_token text) returns jsonb
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

create function private.revoke_invitation(p_invitation_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_kind public.invitation_kind;
begin
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

create function private.revoke_membership(p_membership_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_staff() or not private.is_aal2() or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  update public.project_memberships
     set status = 'revoked', revoked_at = now(), revoked_by = (select auth.uid()),
         revoke_reason = nullif(btrim(p_reason), '')
   where id = p_membership_id and status = 'active';
  if not found then
    return private.fail('not_found');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- Owner only, aal2, fresh MFA (spec 03 §4, §7; T-ROLE-07).
create function private.set_staff_role(p_user_id uuid, p_role public.staff_role, p_reason text) returns jsonb
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

create function private.revoke_staff(p_user_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_owner() or not private.mfa_is_fresh() or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  update public.staff_roles set status = 'revoked', revoked_at = now(), revoked_by = (select auth.uid()),
         reason = nullif(btrim(p_reason), '')
   where user_id = p_user_id and status = 'active';
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

-- Deactivate / reactivate. Staff targets require the Owner with fresh MFA.
create function private.set_user_status(p_user_id uuid, p_status public.profile_status, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_staff() or not private.is_aal2() or not private.session_is_active() then
    return private.fail('forbidden');
  end if;
  if exists (select 1 from public.staff_roles where user_id = p_user_id)
     and not (private.is_owner() and private.mfa_is_fresh()) then
    return private.fail('forbidden');
  end if;
  perform set_config('app.audit_reason', coalesce(btrim(p_reason), ''), true);
  update public.profiles
     set status = p_status,
         deactivated_at = case when p_status = 'deactivated' then now() end
   where id = p_user_id and status <> p_status;
  if not found then
    return private.fail('not_found');
  end if;
  -- Deactivation terminates every Supabase session of the user (spec 03 §6.2; 03A S-05).
  -- Refresh tokens belong to sessions, so none can be used again.
  if p_status = 'deactivated' then
    delete from auth.sessions where user_id = p_user_id;
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

-- Authorization context for server guards in one round trip (spec 03 §10).
create function private.auth_context() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'user_id', (select auth.uid()),
    'email', private.current_email(),
    'active', private.is_active_user(),
    'staff_role', private.staff_role_of((select auth.uid())),
    'aal', coalesce((select auth.jwt()) ->> 'aal', 'aal1'),
    'mfa_fresh', private.mfa_is_fresh(),
    'session_active', private.session_is_active()
  );
$$;

-- Security events (sign-in outcomes, OTP requests, MFA events, sessions) are recorded only
-- by the server with the secret key (Phase 2 remediation D1; spec 03 §11, T-ROLE-01). The
-- actor is the user the server verified (getClaims / Auth response), passed explicitly; it is
-- never derived from a client-callable path. Defense in depth: EXECUTE is granted to
-- service_role only, and the function also refuses any caller whose JWT role is not
-- service_role.
create function private.record_security_event(
  p_actor_user_id uuid,
  p_action text,
  p_summary jsonb default '{}'::jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_summary jsonb := coalesce(p_summary, '{}'::jsonb);
begin
  if coalesce((select auth.jwt()) ->> 'role', '') <> 'service_role' then
    raise exception 'security events are recorded by the server only' using errcode = '42501';
  end if;
  if p_action is null or char_length(p_action) > 64
     or p_action !~ '^(auth|mfa|session)\.[a-z_]+(\.[a-z_]+)*$' then
    raise exception 'invalid security event action' using errcode = '22023';
  end if;
  if jsonb_typeof(v_summary) <> 'object' or octet_length(v_summary::text) > 2048 then
    raise exception 'security event summary must be a JSON object of at most 2048 bytes'
      using errcode = '22023';
  end if;
  if p_actor_user_id is not null
     and not exists (select 1 from auth.users u where u.id = p_actor_user_id) then
    raise exception 'unknown security event actor' using errcode = '22023';
  end if;
  insert into public.audit_events (actor_user_id, actor_role, action, category, request_id, ip, user_agent, summary)
  values (
    p_actor_user_id,
    coalesce(private.staff_role_of(p_actor_user_id)::text,
             case when p_actor_user_id is not null then 'client' end,
             'system'),
    p_action, 'security',
    left(private.request_header('x-request-id'), 100),
    left(coalesce(private.request_header('x-client-ip'), private.request_header('x-forwarded-for')), 100),
    left(private.request_header('user-agent'), 300),
    v_summary
  );
end;
$$;

-- Before-user-created hook (spec 03 §5): only emails with a pending, unexpired invitation.
create function private.hook_before_user_created(event jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_email text := lower(btrim(event -> 'user' ->> 'email'));
begin
  if v_email is not null and exists (
    select 1 from public.invitations
    where email = v_email::extensions.citext and status = 'pending' and expires_at > now()
  ) then
    return '{}'::jsonb;
  end if;
  return jsonb_build_object('error', jsonb_build_object(
    'http_code', 403, 'message', 'Access to this portal is by invitation only.'));
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Exposed RPC wrappers (public, SECURITY INVOKER). Definer code stays in private.
-- ---------------------------------------------------------------------------
create function public.create_invitation(p_kind public.invitation_kind, p_email text, p_full_name text,
  p_project_id uuid default null, p_intended_role public.staff_role default null) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.create_invitation(p_kind, p_email, p_full_name, p_project_id, p_intended_role);
$$;
create function public.accept_invitation(p_invitation_id uuid, p_token text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.accept_invitation(p_invitation_id, p_token);
$$;
create function public.revoke_invitation(p_invitation_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.revoke_invitation(p_invitation_id);
$$;
create function public.revoke_membership(p_membership_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.revoke_membership(p_membership_id, p_reason);
$$;
create function public.set_staff_role(p_user_id uuid, p_role public.staff_role, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.set_staff_role(p_user_id, p_role, p_reason);
$$;
create function public.revoke_staff(p_user_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.revoke_staff(p_user_id, p_reason);
$$;
create function public.set_user_status(p_user_id uuid, p_status public.profile_status, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.set_user_status(p_user_id, p_status, p_reason);
$$;
create function public.auth_context() returns jsonb
language sql stable security invoker set search_path = '' as $$
  select private.auth_context();
$$;
-- Server (secret key) only:
create function public.record_security_event(p_actor_user_id uuid, p_action text, p_summary jsonb default '{}'::jsonb)
returns void
language sql security invoker set search_path = '' as $$
  select private.record_security_event(p_actor_user_id, p_action, p_summary);
$$;
create function public.check_invitation_link(p_invitation_id uuid, p_token text) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.check_invitation_link(p_invitation_id, p_token);
$$;
create function public.consume_rate_limit(p_bucket text, p_limit integer, p_window_seconds integer) returns boolean
language sql security invoker set search_path = '' as $$
  select private.consume_rate_limit(p_bucket, p_limit, make_interval(secs => p_window_seconds));
$$;

-- ---------------------------------------------------------------------------
-- 9. Function privileges (spec 03 §9.1 rule 4; T-TEN-06)
-- ---------------------------------------------------------------------------
revoke all on all functions in schema private from public, anon, authenticated, service_role;
revoke all on all functions in schema public from public, anon, authenticated, service_role;

-- Helpers used by RLS policies and by the invoker wrappers.
grant execute on function
  private.is_active_user(), private.staff_role_of(uuid), private.is_staff(), private.is_owner(),
  private.is_project_member(uuid), private.can_access_project(uuid), private.can_access_project_path(text),
  private.is_aal2(), private.session_is_active(), private.mfa_is_fresh(interval), private.current_email(),
  private.create_invitation(public.invitation_kind, text, text, uuid, public.staff_role),
  private.accept_invitation(uuid, text), private.revoke_invitation(uuid),
  private.revoke_membership(uuid, text), private.set_staff_role(uuid, public.staff_role, text),
  private.revoke_staff(uuid, text), private.set_user_status(uuid, public.profile_status, text),
  private.auth_context()
to authenticated;

grant execute on function
  public.create_invitation(public.invitation_kind, text, text, uuid, public.staff_role),
  public.accept_invitation(uuid, text), public.revoke_invitation(uuid),
  public.revoke_membership(uuid, text), public.set_staff_role(uuid, public.staff_role, text),
  public.revoke_staff(uuid, text), public.set_user_status(uuid, public.profile_status, text),
  public.auth_context()
to authenticated;

grant execute on function
  private.check_invitation_link(uuid, text), private.consume_rate_limit(text, integer, interval),
  private.record_security_event(uuid, text, jsonb),
  private.staff_role_of(uuid), private.fail(text),
  public.check_invitation_link(uuid, text), public.consume_rate_limit(text, integer, integer),
  public.record_security_event(uuid, text, jsonb)
to service_role;

-- private.record_audit_event is executed only by SECURITY DEFINER functions and triggers
-- (as their owner). No API role is granted EXECUTE on it (Phase 2 remediation D1).
grant execute on function private.fail(text) to authenticated;

-- Auth hook (spec 03 §5)
grant usage on schema private to supabase_auth_admin;
grant execute on function private.hook_before_user_created(jsonb) to supabase_auth_admin;

-- ---------------------------------------------------------------------------
-- 10. Table grants (minimal) and RLS (spec 03 §9.3)
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.staff_roles enable row level security;
alter table public.client_businesses enable row level security;
alter table public.projects enable row level security;
alter table public.invitations enable row level security;
alter table public.project_memberships enable row level security;
alter table public.audit_events enable row level security;

grant select on public.profiles to authenticated;
grant update (full_name) on public.profiles to authenticated;
grant select on public.staff_roles to authenticated;
grant select on public.client_businesses to authenticated;
grant insert (legal_name, display_name) on public.client_businesses to authenticated;
grant update (legal_name, display_name, archived_at) on public.client_businesses to authenticated;
grant select on public.projects to authenticated;
grant insert (client_business_id, name) on public.projects to authenticated;
grant update (name, archived_at) on public.projects to authenticated;
grant select on public.project_memberships to authenticated;
-- token_hash is never selectable by end users.
grant select (id, kind, email, full_name, project_id, intended_role, status, expires_at, created_by,
  created_at, accepted_by, accepted_at, revoked_by, revoked_at, failed_attempts)
  on public.invitations to authenticated;
grant select on public.audit_events to authenticated;
-- Audit is append-only for every role, including service_role (T-AUD-02).
revoke insert, update, delete, truncate on public.audit_events from service_role;
revoke update, delete, truncate on public.profiles, public.staff_roles, public.client_businesses,
  public.projects, public.invitations, public.project_memberships from service_role;

-- profiles
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.is_staff()));
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = (select auth.uid()) and (select private.is_active_user()))
  with check (id = (select auth.uid()));

-- staff_roles
create policy staff_roles_select on public.staff_roles for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_staff()));

-- client_businesses
create policy client_businesses_select on public.client_businesses for select to authenticated
  using (
    (select private.is_staff())
    or exists (
      select 1 from public.projects p
      where p.client_business_id = client_businesses.id and private.is_project_member(p.id)
    )
  );
create policy client_businesses_insert on public.client_businesses for insert to authenticated
  with check ((select private.is_staff()));
create policy client_businesses_update on public.client_businesses for update to authenticated
  using ((select private.is_staff())) with check ((select private.is_staff()));

-- projects
create policy projects_select on public.projects for select to authenticated
  using (private.can_access_project(id));
create policy projects_insert on public.projects for insert to authenticated
  with check ((select private.is_staff()));
create policy projects_update on public.projects for update to authenticated
  using ((select private.is_staff())) with check ((select private.is_staff()));

-- project_memberships (writes only through definer functions)
create policy project_memberships_select on public.project_memberships for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_staff()));

-- invitations (writes only through definer functions)
create policy invitations_select on public.invitations for select to authenticated
  using (
    (select private.is_staff())
    or (status = 'pending' and expires_at > now() and email::text = (select private.current_email()))
  );

-- audit_events: Owner reads all; Admin reads non-financial; clients nothing.
create policy audit_events_select on public.audit_events for select to authenticated
  using ((select private.is_owner()) or ((select private.is_staff()) and category <> 'financial'));

-- Restrictive policies: staff must be at aal2, in a session that still exists (signed-out
-- sessions are denied before token expiry, T-AUTH-10), for every command on every table (spec 03 §7),
-- and deactivated users see nothing except their own profile row.
do $$
declare
  t text;
begin
  foreach t in array array['profiles', 'staff_roles', 'client_businesses', 'projects',
                           'invitations', 'project_memberships', 'audit_events'] loop
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated
         using (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))
         with check (not (select private.is_staff()) or ((select private.is_aal2()) and (select private.session_is_active())))',
      t || '_staff_aal2', t);
  end loop;
  foreach t in array array['staff_roles', 'client_businesses', 'projects', 'project_memberships', 'audit_events'] loop
    execute format(
      'create policy %I on public.%I as restrictive for all to authenticated
         using ((select private.is_active_user())) with check ((select private.is_active_user()))',
      t || '_active_user', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Storage: private project-assets bucket (spec 03 §9.4). No uploads in Phase 2.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('project-assets', 'project-assets', false)
on conflict (id) do update set public = false;

create policy project_assets_select on storage.objects for select to authenticated
  using (bucket_id = 'project-assets' and private.can_access_project_path(name));
create policy project_assets_staff_aal2 on storage.objects as restrictive for all to authenticated
  using (bucket_id <> 'project-assets' or not (select private.is_staff())
         or ((select private.is_aal2()) and (select private.session_is_active())))
  with check (bucket_id <> 'project-assets' or not (select private.is_staff())
         or ((select private.is_aal2()) and (select private.session_is_active())));
