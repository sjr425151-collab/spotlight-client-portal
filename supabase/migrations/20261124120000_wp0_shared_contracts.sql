-- WP-0: shared contracts (spec 01 §7; AUTH-001).
-- Creates the contracts that WP-B (payments) and WP-C (fulfillment) build on in parallel:
-- state-domain types (05 §2), the typed domain-event registry and append-only event log,
-- the durable notification outbox (07 §2-§3), and the two gate interfaces read by the
-- single gate evaluator (06 §2).
--
-- Rules for this file:
-- - Forward-only. Never edit this file after it is merged (T-MIG-02).
-- - Creates only new objects. No Phase 2 table, policy, function, or auth flow is changed
--   (AUTH-001 Tier 2 controls).
-- - The state-change functions of WP-B and WP-C are the only callers of the write
--   functions below. No role is granted EXECUTE on them, so an event or notification can
--   be written only inside a SECURITY DEFINER function that also performs the state change,
--   in the same transaction.

-- ---------------------------------------------------------------------------
-- 1. State-domain types (05 §2; 01 §7; R1 acceptance item 9)
-- ---------------------------------------------------------------------------
-- The six separately tracked state domains (01 §7). Each owns one or more dimensions below.
create type public.state_domain as enum (
  'agreement', 'payment', 'subscription', 'fulfillment', 'approval', 'deployment'
);

-- Domain: agreement (04 §1).
create type public.agreement_state as enum (
  'not_presented', 'presented', 'accepted_pending_payment', 'effective',
  'superseded', 'reacceptance_required', 'expired'
);

-- Domain: payment. Deposit and final balance change only through verified webhook
-- processing (05 §2 transition rules; 04 §11).
create type public.deposit_state as enum (
  'not_started', 'pending', 'verified', 'failed', 'refunded', 'disputed'
);
create type public.final_balance_state as enum (
  'not_due', 'due', 'pending', 'verified', 'failed', 'refunded', 'disputed', 'settled_by_adjustment'
);

-- Domain: subscription. A mirror of the Stripe subscription status (04 §11), verified
-- against Stripe's OpenAPI specification 2026-09-30.endive. Service termination is a
-- separate, Owner-authorized state that never follows the Stripe status (04 §9.1.1).
create type public.subscription_status as enum (
  'incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'canceled', 'unpaid', 'paused'
);
create type public.service_termination_state as enum (
  'none', 'under_owner_review', 'termination_authorized', 'effective',
  'maintenance_ceased', 'offboarded', 'transferred', 'withdrawn'
);

-- Domain: fulfillment. Development milestones are informational and never a gate (05 §2).
create type public.intake_state as enum (
  'locked', 'open', 'submitted', 'accepted_by_staff', 'changes_requested'
);
create type public.development_state as enum (
  'not_started', 'in_progress', 'ready_for_preview', 'paused'
);

-- Domain: approval. Per preview release (05 §6-§7).
create type public.release_approval_state as enum (
  'released', 'approved', 'superseded', 'withdrawn'
);

-- Domain: deployment. Publication eligibility and deployment (06).
create type public.publication_state as enum (
  'not_eligible', 'eligible', 'authorized', 'deploying', 'live_unverified', 'live_verified',
  'failed', 'rolled_back'
);

-- Hold types (04 §14). Billing and fulfillment holds are distinct types; which interface
-- reports each one is recorded in OI-71.
create type public.hold_type as enum (
  'maintenance_payment_hold', 'approval_nonresponsive_hold', 'dispute_risk_hold', 'owner_manual_hold'
);

-- Notification outbox (07 §2). 'recorded' is the R1 state: written, never sent. R2 rows
-- start at 'pending'.
create type public.notification_status as enum (
  'recorded', 'pending', 'sending', 'sent', 'failed', 'dead'
);
create type public.notification_recipient_role as enum ('client', 'owner', 'admin', 'staff');

-- ---------------------------------------------------------------------------
-- 2. Domain-event registry (private; typed events, 01 §7)
-- ---------------------------------------------------------------------------
-- Every event type is registered before it can be emitted. WP-B and WP-C register their own
-- event types in their own migrations, so neither edits this file or the other's rows.
create table private.domain_event_types (
  event_type text primary key,
  domain public.state_domain not null,
  owner_package text not null,
  schema_version smallint not null default 1,
  description text not null,
  constraint domain_event_types_name_format check (
    event_type ~ '^[a-z][a-z_]*\.[a-z][a-z_]*$' and char_length(event_type) <= 100),
  constraint domain_event_types_owner check (owner_package in ('WP-B', 'WP-C')),
  constraint domain_event_types_version check (schema_version >= 1),
  constraint domain_event_types_description_bounded check (char_length(description) between 1 and 300)
);
revoke all on table private.domain_event_types from public, anon, authenticated, service_role;

-- The cross-package events named in 01 §7. WP-C emits release.approved; WP-B consumes it
-- to create the final-balance invoice.
insert into private.domain_event_types (event_type, domain, owner_package, description) values
  ('agreement.accepted', 'agreement', 'WP-B', 'A client accepted the current agreement version and order summary'),
  ('payment.deposit_verified', 'payment', 'WP-B', 'The deposit was verified from a signature-verified Stripe event'),
  ('release.approved', 'approval', 'WP-C', 'A client approved the current released preview'),
  ('publication.authorized', 'deployment', 'WP-C', 'The Owner authorized publication of exactly one release');

-- Financial domains: Admin may not read these events (03 §4 "non-financial" rule, as for
-- audit_events).
create function private.domain_is_financial(p_domain public.state_domain) returns boolean
language sql immutable set search_path = '' as $$
  select p_domain in ('payment'::public.state_domain, 'subscription'::public.state_domain);
$$;

-- Rejects payloads that could carry secrets or card data (CLAUDE.md §3). Keys are checked
-- at every nesting level, by whole snake_case segment (so `company` is allowed but
-- `card_number` and `api_key` are not).
create function private.payload_is_safe(p_payload jsonb, p_max_bytes integer) returns boolean
language sql immutable set search_path = '' as $$
  select jsonb_typeof(p_payload) = 'object'
     and octet_length(p_payload::text) <= p_max_bytes
     and not exists (
       select 1 from jsonb_path_query(p_payload, 'strict $.**') v(value)
       where jsonb_typeof(v.value) = 'object'
         and exists (
           select 1 from jsonb_object_keys(v.value) k(key)
           where lower(k.key) ~ '(^|_)(secret|token|password|passcode|otp|apikey|api_key|card|cvc|cvv|pan|authorization|cookie)s?(_|$)'
         )
     );
$$;

-- ---------------------------------------------------------------------------
-- 3. Domain events (append-only, typed, idempotent)
-- ---------------------------------------------------------------------------
create table public.domain_events (
  id bigint generated always as identity primary key,
  event_id uuid not null unique default gen_random_uuid(),
  event_type text not null references private.domain_event_types (event_type),
  schema_version smallint not null,
  domain public.state_domain not null,
  category text not null,
  project_id uuid references public.projects (id),
  subject_type text not null,
  subject_id text not null,
  actor_user_id uuid,
  occurred_at timestamptz not null default now(),
  dedupe_key text unique,
  request_id text,
  payload jsonb not null default '{}'::jsonb,
  constraint domain_events_category check (category in ('general', 'financial')),
  constraint domain_events_subject_bounded check (
    char_length(subject_type) between 1 and 60 and char_length(subject_id) between 1 and 200),
  constraint domain_events_dedupe_bounded check (dedupe_key is null or char_length(dedupe_key) between 1 and 200),
  constraint domain_events_payload_safe check (private.payload_is_safe(payload, 8192))
);
create index domain_events_project_time_idx on public.domain_events (project_id, occurred_at);
create index domain_events_type_time_idx on public.domain_events (event_type, occurred_at);

create function private.domain_events_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'domain_events is append-only' using errcode = '42501';
end;
$$;
create trigger domain_events_no_update_delete
  before update or delete on public.domain_events
  for each row execute function private.domain_events_immutable();
create trigger domain_events_no_truncate
  before truncate on public.domain_events
  for each statement execute function private.domain_events_immutable();

-- Emits one event in the caller's transaction. Callable only from SECURITY DEFINER
-- state-change functions (no role holds EXECUTE). With a dedupe key, a repeated emission
-- (for example a replayed webhook) returns the original event and writes nothing; reusing a
-- key for a different event is an error.
create function private.emit_domain_event(
  p_event_type text,
  p_project_id uuid,
  p_subject_type text,
  p_subject_id text,
  p_payload jsonb default '{}'::jsonb,
  p_dedupe_key text default null
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_type private.domain_event_types%rowtype;
  v_existing public.domain_events%rowtype;
  v_id bigint;
begin
  select * into v_type from private.domain_event_types where event_type = p_event_type;
  if not found then
    raise exception 'unregistered domain event type: %', p_event_type using errcode = '23503';
  end if;
  if not private.payload_is_safe(coalesce(p_payload, '{}'::jsonb), 8192) then
    raise exception 'domain event payload must be a bounded object without secret-like keys'
      using errcode = '22023';
  end if;

  insert into public.domain_events (
    event_type, schema_version, domain, category, project_id, subject_type, subject_id,
    actor_user_id, dedupe_key, request_id, payload
  ) values (
    v_type.event_type, v_type.schema_version, v_type.domain,
    case when private.domain_is_financial(v_type.domain) then 'financial' else 'general' end,
    p_project_id, p_subject_type, p_subject_id, (select auth.uid()), p_dedupe_key,
    left(private.request_header('x-request-id'), 100), coalesce(p_payload, '{}'::jsonb)
  )
  on conflict (dedupe_key) do nothing
  returning id into v_id;

  if v_id is null then
    -- Only reachable with a dedupe key (NULL keys never conflict). Concurrency-safe: the
    -- unique index arbitrates, then the existing event is compared.
    select * into v_existing from public.domain_events where dedupe_key = p_dedupe_key;
    if v_existing.event_type <> p_event_type
       or v_existing.project_id is distinct from p_project_id
       or v_existing.subject_type <> p_subject_type
       or v_existing.subject_id <> p_subject_id then
      raise exception 'dedupe key % already used for a different event', p_dedupe_key
        using errcode = '23505';
    end if;
    v_id := v_existing.id;
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Notification outbox (07 §2-§3). Delivery is R2; R1 records only.
-- ---------------------------------------------------------------------------
create table public.notification_outbox (
  id bigint generated always as identity primary key,
  outbox_id uuid not null unique default gen_random_uuid(),
  notification_type text not null,
  domain_event_id bigint references public.domain_events (id),
  project_id uuid references public.projects (id),
  category text not null default 'general',
  recipient_user_ids uuid[] not null default '{}',
  recipient_roles public.notification_recipient_role[] not null default '{}',
  template_key text not null,
  template_version integer not null,
  payload_ref jsonb not null default '{}'::jsonb,
  idempotency_key text not null unique,
  status public.notification_status not null default 'recorded',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz,
  provider_message_id text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_outbox_type_format check (
    notification_type ~ '^[a-z][a-z_]*\.[a-z][a-z_]*$' and char_length(notification_type) <= 100),
  constraint notification_outbox_category check (category in ('general', 'financial')),
  constraint notification_outbox_has_recipient check (
    cardinality(recipient_user_ids) + cardinality(recipient_roles) > 0),
  constraint notification_outbox_template check (
    char_length(template_key) between 1 and 100 and template_version >= 1),
  constraint notification_outbox_payload_safe check (private.payload_is_safe(payload_ref, 2048)),
  constraint notification_outbox_key_bounded check (char_length(idempotency_key) between 1 and 200),
  constraint notification_outbox_attempts check (attempt_count >= 0),
  constraint notification_outbox_provider_bounded check (
    provider_message_id is null or char_length(provider_message_id) <= 200),
  constraint notification_outbox_error_bounded check (last_error is null or char_length(last_error) <= 1000)
);
create index notification_outbox_status_due_idx on public.notification_outbox (status, next_attempt_at);
create index notification_outbox_project_idx on public.notification_outbox (project_id);

-- Delivery state machine (07 §2-§3): pending -> sending -> sent | failed; failed -> sending
-- (retry) | dead. 'recorded' (R1), 'sent', and 'dead' are terminal. Identity, recipient,
-- template, payload, and key columns never change. Rows are never deleted here; retention
-- deletion (07 §6) arrives with its own migration.
create function private.notification_outbox_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'notification_outbox rows are not deleted' using errcode = '42501';
  end if;
  if (new.id, new.outbox_id, new.notification_type, new.domain_event_id, new.project_id, new.category,
      new.recipient_user_ids, new.recipient_roles, new.template_key, new.template_version,
      new.payload_ref, new.idempotency_key, new.created_at)
     is distinct from
     (old.id, old.outbox_id, old.notification_type, old.domain_event_id, old.project_id, old.category,
      old.recipient_user_ids, old.recipient_roles, old.template_key, old.template_version,
      old.payload_ref, old.idempotency_key, old.created_at) then
    raise exception 'notification_outbox identity and content are immutable' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'pending' and new.status = 'sending')
    or (old.status = 'sending' and new.status in ('sent', 'failed'))
    or (old.status = 'failed' and new.status in ('sending', 'dead'))
  ) then
    raise exception 'invalid notification status transition % -> %', old.status, new.status
      using errcode = '23514';
  end if;
  if old.status in ('recorded', 'sent', 'dead') then
    raise exception 'notification_outbox row in terminal status % cannot change', old.status
      using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger notification_outbox_guard
  before update or delete on public.notification_outbox
  for each row execute function private.notification_outbox_guard();
create function private.notification_outbox_no_truncate() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'notification_outbox cannot be truncated' using errcode = '42501';
end;
$$;
create trigger notification_outbox_no_truncate
  before truncate on public.notification_outbox
  for each statement execute function private.notification_outbox_no_truncate();

-- Records a notification in the caller's transaction (R1: status 'recorded', never sent).
-- Callable only from SECURITY DEFINER state-change functions. A duplicate idempotency key
-- is a no-op that returns the existing row (07 §3).
create function private.enqueue_notification(
  p_notification_type text,
  p_idempotency_key text,
  p_template_key text,
  p_template_version integer,
  p_project_id uuid default null,
  p_domain_event_id bigint default null,
  p_recipient_user_ids uuid[] default '{}',
  p_recipient_roles public.notification_recipient_role[] default '{}',
  p_payload_ref jsonb default '{}'::jsonb,
  p_category text default 'general'
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into public.notification_outbox (
    notification_type, idempotency_key, template_key, template_version, project_id,
    domain_event_id, recipient_user_ids, recipient_roles, payload_ref, category, status
  ) values (
    p_notification_type, p_idempotency_key, p_template_key, p_template_version, p_project_id,
    p_domain_event_id, coalesce(p_recipient_user_ids, '{}'), coalesce(p_recipient_roles, '{}'),
    coalesce(p_payload_ref, '{}'::jsonb), p_category, 'recorded'
  )
  on conflict (idempotency_key) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.notification_outbox where idempotency_key = p_idempotency_key;
  end if;
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Gate interfaces (01 §7; 06 §2)
-- ---------------------------------------------------------------------------
-- The single gate evaluator (06 §2, owned by WP-C) reads only these two functions.
-- WP-B replaces the body of project_financial_status, and WP-C the body of
-- project_fulfillment_status, with CREATE OR REPLACE in their own migrations, keeping the
-- signature and return type. Extending a status type is additive (ALTER TYPE ... ADD
-- ATTRIBUTE). Until then both return a fail-closed result: implemented = false and no gate
-- input satisfied, so no gate can pass.
create type private.project_financial_status as (
  project_id uuid,
  contract_version smallint,
  implemented boolean,
  deposit_state public.deposit_state,
  deposit_verified boolean,
  final_balance_state public.final_balance_state,
  balance_verified_or_settled boolean,
  balance_settled_by_adjustment boolean,
  active_billing_holds public.hold_type[],
  evidence jsonb
);

create type private.project_fulfillment_status as (
  project_id uuid,
  contract_version smallint,
  implemented boolean,
  intake_state public.intake_state,
  intake_accepted boolean,
  current_release_id uuid,
  current_release_approved boolean,
  current_release_approval_id uuid,
  qa_passed boolean,
  security_passed boolean,
  active_fulfillment_holds public.hold_type[],
  evidence jsonb
);

create function private.project_financial_status(p_project_id uuid)
returns private.project_financial_status
language sql stable security definer set search_path = '' as $$
  select row(
    p_project_id, 1::smallint, false,
    'not_started'::public.deposit_state, false,
    'not_due'::public.final_balance_state, false, false,
    '{}'::public.hold_type[], '{}'::jsonb
  )::private.project_financial_status;
$$;

create function private.project_fulfillment_status(p_project_id uuid)
returns private.project_fulfillment_status
language sql stable security definer set search_path = '' as $$
  select row(
    p_project_id, 1::smallint, false,
    'locked'::public.intake_state, false,
    null::uuid, false, null::uuid, false, false,
    '{}'::public.hold_type[], '{}'::jsonb
  )::private.project_fulfillment_status;
$$;

-- ---------------------------------------------------------------------------
-- 6. Privileges
-- ---------------------------------------------------------------------------
-- No role may execute the write or gate functions directly; only SECURITY DEFINER functions
-- owned by the migration role call them.
revoke all on function
  private.domain_is_financial(public.state_domain),
  private.payload_is_safe(jsonb, integer),
  private.domain_events_immutable(),
  private.emit_domain_event(text, uuid, text, text, jsonb, text),
  private.notification_outbox_guard(),
  private.notification_outbox_no_truncate(),
  private.enqueue_notification(text, text, text, integer, uuid, bigint, uuid[], public.notification_recipient_role[], jsonb, text),
  private.project_financial_status(uuid),
  private.project_fulfillment_status(uuid)
from public, anon, authenticated, service_role;

-- Tables: staff read through RLS; nobody writes directly. service_role reads (server-side
-- queues and reconciliation) but cannot insert, update, or delete.
revoke all on table public.domain_events, public.notification_outbox from public, anon, authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.domain_events, public.notification_outbox from service_role;
grant select on table public.domain_events, public.notification_outbox to authenticated;

-- ---------------------------------------------------------------------------
-- 7. Row Level Security (03 §8-§9; same model as audit_events)
-- ---------------------------------------------------------------------------
-- Owner reads all; Admin reads non-financial rows; clients read nothing (these are internal
-- records; client-facing state comes from the owning package's own tables).
alter table public.domain_events enable row level security;
alter table public.notification_outbox enable row level security;

create policy domain_events_select on public.domain_events for select to authenticated
  using ((select private.is_owner()) or ((select private.is_staff()) and category <> 'financial'));
create policy notification_outbox_select on public.notification_outbox for select to authenticated
  using ((select private.is_owner()) or ((select private.is_staff()) and category <> 'financial'));

do $$
declare
  t text;
begin
  foreach t in array array['domain_events', 'notification_outbox'] loop
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
