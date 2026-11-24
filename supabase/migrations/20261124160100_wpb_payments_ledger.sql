-- WP-B (2 of 2): outbound Stripe requests, initial Checkout, durable webhook ingestion and
-- processing, the append-only integer-cents ledger, refunds, disputes, the subscription
-- mirror, failed-payment recovery and billing holds, service termination and cancellation,
-- reconciliation and quarantine, the release.approved consumer and final-balance invoice,
-- the financial gate interface (G1, G2, G4, WP-B holds), and the OI-72 derived projection.
-- Specifications: 04 §8-§17 (v0.8.0), 02 §13, 03 §4, §7, §11-§12, 05 §2, §9, 06 §2, 07 §2;
-- decisions OI-17, OI-19, OI-26, OI-27, OI-35, OI-37, OI-43, OI-46, OI-47, OI-63, OI-68,
-- OI-71, OI-72. Authorization: AUTH-001. No Stripe credential exists anywhere: every Stripe
-- result reaches the database through the mocked gateway (CI) or, later, AUTH-002.
--
-- Rules for this file: forward-only (T-MIG-02); new WP-B objects only; every write through a
-- SECURITY DEFINER function that authorizes the caller and commits the state change, its
-- ledger entries, domain event, outbox row and audit event in one transaction (04 §17 #6).

-- Functions that exist before this file; every function created below starts with no
-- EXECUTE privilege for any API role (revoked at the end of the file, T-TEN-06).
create temporary table wpb_functions_before on commit drop as
  select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'private');

-- ---------------------------------------------------------------------------
-- 0. Helpers
-- ---------------------------------------------------------------------------
create function private.caller_is_service_role() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select auth.jwt()) ->> 'role', '') = 'service_role';
$$;

-- An integer number of cents, or null for anything else (a string, a fraction, a negative,
-- or more than 15 digits). Money is integer cents only (CLAUDE.md §3).
create function private.try_cents(p_value jsonb) returns bigint
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(p_value) = 'number' and (p_value #>> '{}') ~ '^[0-9]{1,15}$'
              then (p_value #>> '{}')::bigint end;
$$;

create function private.try_uuid(p_text text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  if p_text is null or p_text !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return null;
  end if;
  return p_text::uuid;
end;
$$;

create function private.unix_ts(p_value jsonb) returns timestamptz
language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(p_value) = 'number' then to_timestamp((p_value #>> '{}')::double precision) end;
$$;

-- Stripe mode expected of every event and object in this environment (04 §11 rule 5).
create function private.expected_livemode() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_production();
$$;

-- ---------------------------------------------------------------------------
-- 1. Deadline calendar (02 §13; OI-43). The one shared calendar: computed once, stored in
--    UTC with the calendar version. Never 24-hour arithmetic on timestamps.
-- ---------------------------------------------------------------------------
create function private.calendar_version() returns text
language sql immutable set search_path = '' as $$ select 'us-federal-5usc6103-v1'; $$;

create function private.nth_weekday(p_year integer, p_month integer, p_isodow integer, p_n integer)
returns date language sql immutable set search_path = '' as $$
  select make_date(p_year, p_month, 1)
       + ((p_isodow - extract(isodow from make_date(p_year, p_month, 1))::integer + 7) % 7)
       + (p_n - 1) * 7;
$$;

create function private.observed(p_date date) returns date
language sql immutable set search_path = '' as $$
  select case extract(isodow from p_date)::integer
    when 6 then p_date - 1 when 7 then p_date + 1 else p_date end;
$$;

-- 5 U.S.C. § 6103, with the observed-date rule (02 §13.1).
create function private.us_federal_holidays(p_year integer) returns setof date
language sql immutable set search_path = '' as $$
  select private.observed(make_date(p_year, 1, 1))
  union all select private.nth_weekday(p_year, 1, 1, 3)
  union all select private.nth_weekday(p_year, 2, 1, 3)
  union all select make_date(p_year, 5, 31) - ((extract(isodow from make_date(p_year, 5, 31))::integer - 1 + 7) % 7)
  union all select private.observed(make_date(p_year, 6, 19))
  union all select private.observed(make_date(p_year, 7, 4))
  union all select private.nth_weekday(p_year, 9, 1, 1)
  union all select private.nth_weekday(p_year, 10, 1, 2)
  union all select private.observed(make_date(p_year, 11, 11))
  union all select private.nth_weekday(p_year, 11, 4, 4)
  union all select private.observed(make_date(p_year, 12, 25));
$$;

create function private.is_business_day(p_date date) returns boolean
language sql immutable set search_path = '' as $$
  select extract(isodow from p_date) < 6
     and p_date not in (
       select h from private.us_federal_holidays(extract(year from p_date)::integer) h
       union all
       -- New Year's Day on a Saturday is observed on December 31 of the prior year.
       select h from private.us_federal_holidays(extract(year from p_date)::integer + 1) h);
$$;

-- The Nth business day after p_date; p_date itself is excluded (02 §13.2).
create function private.add_business_days(p_date date, p_n integer) returns date
language plpgsql immutable set search_path = '' as $$
declare
  v_date date := p_date;
  v_left integer := p_n;
begin
  if p_n < 1 then raise exception 'business-day count must be positive' using errcode = '22023'; end if;
  while v_left > 0 loop
    v_date := v_date + 1;
    if private.is_business_day(v_date) then v_left := v_left - 1; end if;
  end loop;
  return v_date;
end;
$$;

create function private.local_date(p_at timestamptz) returns date
language sql immutable set search_path = '' as $$
  select (p_at at time zone 'America/Detroit')::date;
$$;

-- 23:59:59 America/Detroit on a local date, as a UTC instant (02 §13).
create function private.end_of_local_day(p_date date) returns timestamptz
language sql immutable set search_path = '' as $$
  select (p_date + time '23:59:59') at time zone 'America/Detroit';
$$;

-- ---------------------------------------------------------------------------
-- 2. Types
-- ---------------------------------------------------------------------------
create type public.outbound_request_purpose as enum (
  'customer_create', 'checkout_session_create', 'final_balance_invoice_create',
  'recovery_session_create', 'final_balance_invoice_disable_auto');
create type public.outbound_request_status as enum (
  'pending', 'succeeded', 'failed', 'ambiguous', 'reconciled_present', 'reconciled_absent');
create type public.checkout_session_status as enum ('creating', 'open', 'complete', 'expired', 'failed');
create type public.webhook_processing_status as enum (
  'received', 'processed', 'ignored', 'deferred', 'quarantined', 'failed');
-- 04 §12. discount, credit, partial_waiver and waiver are Owner-authorized R2 adjustments
-- (OI-68); a constraint below keeps them unpostable in R1 (T-BIL-22).
create type public.ledger_entry_type as enum (
  'deposit_charge', 'maintenance_charge', 'balance_charge', 'refund', 'dispute_opened',
  'dispute_won', 'dispute_lost', 'tax', 'discount', 'credit', 'partial_waiver', 'waiver',
  'refund_discretionary', 'reclassification');
create type public.service_category as enum ('development', 'maintenance', 'marketing_future');
create type public.final_balance_invoice_status as enum (
  'creating', 'open', 'paid', 'payment_failed', 'action_required', 'creation_failed', 'void');
create type public.maintenance_recovery_status as enum ('in_recovery', 'recovered', 'hold_placed');
create type public.billing_hold_review_decision as enum (
  'continue_collection', 'authorize_exception', 'initiate_termination');
create type public.cancellation_request_status as enum ('received', 'confirmed', 'withdrawn');
-- 04 §8.1 (OI-74).
create type public.payment_authorization_status as enum ('active', 'payment_method_unavailable', 'revoked');
-- 04 §15.2.1 rule 1 (OI-82).
create type public.obligation_kind as enum ('development_deposit', 'maintenance', 'development_balance');

-- ---------------------------------------------------------------------------
-- 3. Tables
-- ---------------------------------------------------------------------------
create table public.stripe_customers (
  client_business_id uuid primary key references public.client_businesses (id),
  stripe_customer_id text not null unique,
  livemode boolean not null,
  created_at timestamptz not null default now(),
  constraint stripe_customers_id_format check (stripe_customer_id ~ '^cus_[A-Za-z0-9]{6,64}$')
);

-- 04 §17 invariant 2: inserted before any Stripe create, in the intent's transaction.
create table public.outbound_stripe_requests (
  id uuid primary key default gen_random_uuid(),
  purpose public.outbound_request_purpose not null,
  project_id uuid references public.projects (id),
  domain_record_type text not null,
  domain_record_id uuid not null,
  attempt smallint not null,
  idempotency_key text not null unique,
  status public.outbound_request_status not null default 'pending',
  request_params jsonb not null default '{}'::jsonb,
  stripe_object_id text,
  livemode boolean,
  http_status integer,
  error_code text,
  created_at timestamptz not null default now(),
  -- Set once by the single executor allowed to send this request (atomic claim).
  claimed_at timestamptz,
  completed_at timestamptz,
  reconciled_by uuid references public.profiles (id),
  reconciled_at timestamptz,
  reconcile_note text,
  unique (domain_record_type, domain_record_id, attempt),
  constraint outbound_record_type check (domain_record_type in ('client_business', 'checkout_session', 'final_balance_invoice', 'recovery_session')),
  constraint outbound_attempt check (attempt between 1 and 20),
  -- <purpose>-<domain record ids>[-c<checkout attempt>]-a<request attempt> (04 §8, §10, §17 #2).
  constraint outbound_key_format check (idempotency_key ~ '^wpb-[a-z-]+-[0-9a-f-]{36}(-[0-9a-f-]{36})?(-c[0-9]{1,2})?-a[0-9]{1,2}$'),
  constraint outbound_params_safe check (private.payload_is_safe(request_params, 8192)),
  constraint outbound_object_bounded check (stripe_object_id is null or stripe_object_id ~ '^[a-z]{2,8}_[A-Za-z0-9_]{6,200}$'),
  constraint outbound_error_bounded check (error_code is null or char_length(error_code) <= 100),
  constraint outbound_note_bounded check (reconcile_note is null or char_length(reconcile_note) <= 1000)
);
-- One request in flight per domain record; an ambiguous one blocks until reconciled (04 §6.4).
create unique index outbound_one_in_flight on public.outbound_stripe_requests (domain_record_type, domain_record_id)
  where status in ('pending', 'ambiguous');
create index outbound_project_idx on public.outbound_stripe_requests (project_id);

create table public.checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  order_summary_id uuid not null references public.order_summaries (id),
  acceptance_id uuid not null references public.agreement_acceptances (id),
  kind text not null default 'initial',
  attempt smallint not null,
  status public.checkout_session_status not null default 'creating',
  stripe_checkout_session_id text unique,
  checkout_url text,
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_invoice_id text,
  payment_status text,
  amount_total_cents bigint,
  expires_at timestamptz,
  completed_at timestamptz,
  last_event_created timestamptz,
  -- 04 §8: the card used for the first invoice, re-read from Stripe after the verified event.
  payment_method_checked_at timestamptz,
  payment_method_reusable boolean,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_summary_id, attempt),
  constraint checkout_kind check (kind = 'initial'),
  constraint checkout_attempt check (attempt between 1 and 20),
  constraint checkout_stripe_id check (stripe_checkout_session_id is null or stripe_checkout_session_id ~ '^cs_[A-Za-z0-9_]{6,200}$'),
  constraint checkout_url_host check (checkout_url is null or (checkout_url ~ '^https://checkout\.stripe\.com/' and char_length(checkout_url) <= 2000)),
  constraint checkout_payment_status check (payment_status is null or payment_status in ('paid', 'unpaid', 'no_payment_required', 'failed'))
);
-- 04 §8 and §17 #3: at most one open initial session per project.
create unique index checkout_one_open_initial on public.checkout_sessions (project_id)
  where kind = 'initial' and status in ('creating', 'open');

-- 04 §17 invariant 4: stored durably before acknowledgement; stripe_event_id unique.
create table public.webhook_events (
  id bigint generated always as identity primary key,
  stripe_event_id text not null unique,
  event_type text not null,
  api_version text,
  livemode boolean not null,
  stripe_created_at timestamptz not null,
  object_type text,
  object_id text,
  payload jsonb not null,
  raw_body_sha256 text not null,
  signature_verified boolean not null,
  received_at timestamptz not null default now(),
  processing_status public.webhook_processing_status not null default 'received',
  attempts integer not null default 0,
  last_error text,
  processed_at timestamptz,
  project_id uuid references public.projects (id),
  quarantine_reason text,
  quarantine_resolved_at timestamptz,
  quarantine_resolved_by uuid references public.profiles (id),
  quarantine_resolution text,
  constraint webhook_event_id_format check (stripe_event_id ~ '^evt_[A-Za-z0-9_]{6,200}$'),
  constraint webhook_event_type_format check (event_type ~ '^[a-z_]+(\.[a-z_]+){1,4}$' and char_length(event_type) <= 100),
  constraint webhook_signature_verified check (signature_verified),
  constraint webhook_hash_format check (raw_body_sha256 ~ '^[0-9a-f]{64}$'),
  constraint webhook_payload_bounded check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 262144),
  constraint webhook_error_bounded check (last_error is null or char_length(last_error) <= 500),
  constraint webhook_reason_bounded check (quarantine_reason is null or char_length(quarantine_reason) <= 200),
  constraint webhook_resolution_bounded check (quarantine_resolution is null or char_length(quarantine_resolution) <= 1000)
);
create index webhook_events_status_idx on public.webhook_events (processing_status, id);
create index webhook_events_project_idx on public.webhook_events (project_id);

-- 04 §12: append-only; corrections are reversing entries; signed integer cents.
create table public.ledger_entries (
  id bigint generated always as identity primary key,
  entry_id uuid not null unique default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  order_summary_id uuid references public.order_summaries (id),
  entry_type public.ledger_entry_type not null,
  amount_cents bigint not null,
  currency text not null default 'usd',
  -- Null only for the unresolved reversal holding account (04 §15.2.1 rule 2d: no category
  -- is assumed).
  service_category public.service_category,
  source text not null,
  webhook_event_id bigint references public.webhook_events (id),
  stripe_object_type text,
  stripe_object_id text,
  stripe_invoice_id text,
  stripe_charge_ref text,
  refers_to_entry_id bigint references public.ledger_entries (id),
  refund_decision_id uuid,
  -- Reversal targets (04 §15.2.1): exactly one of an obligation or the holding account of a
  -- charge. obligation_id gets its foreign key once payment_obligations exists.
  obligation_id uuid,
  holding_charge_key text,
  actor_user_id uuid references public.profiles (id),
  reason text,
  dedupe_key text not null unique,
  posted_at timestamptz not null default now(),
  constraint ledger_currency check (currency = 'usd'),
  constraint ledger_source check (source in ('webhook', 'owner')),
  -- OI-19 / T-PAY-10: no entry records a payment without a signature-verified Stripe event.
  constraint ledger_payments_from_webhooks check (
    entry_type not in ('deposit_charge', 'maintenance_charge', 'balance_charge', 'refund',
      'dispute_opened', 'dispute_won', 'dispute_lost', 'tax')
    or (source = 'webhook' and webhook_event_id is not null)),
  constraint ledger_owner_entries check (
    entry_type not in ('refund_discretionary', 'reclassification')
    or (source = 'owner' and actor_user_id is not null and reason is not null)),
  -- Reversals target one obligation or the holding account, never both and never neither;
  -- only holding entries lack a service category.
  constraint ledger_allocation_shape check (
    case when entry_type in ('refund', 'dispute_opened', 'dispute_won', 'dispute_lost', 'reclassification')
         then (obligation_id is null) <> (holding_charge_key is null)
              and ((holding_charge_key is not null) = (service_category is null))
         else obligation_id is null and holding_charge_key is null and service_category is not null end),
  -- OI-68 / T-BIL-22: R1 offers no discount, credit, or waiver.
  constraint ledger_no_r1_adjustments check (entry_type not in ('discount', 'credit', 'partial_waiver', 'waiver')),
  constraint ledger_signs check (
    (entry_type in ('deposit_charge', 'maintenance_charge', 'balance_charge') and amount_cents > 0)
    or (entry_type = 'refund' and amount_cents <> 0)
    or (entry_type = 'dispute_opened' and amount_cents < 0)
    or (entry_type = 'dispute_won' and amount_cents > 0)
    or (entry_type in ('dispute_lost', 'refund_discretionary') and amount_cents = 0)
    or (entry_type = 'reclassification' and amount_cents <> 0)
    or (entry_type = 'tax' and amount_cents >= 0)),
  constraint ledger_reason_bounded check (reason is null or char_length(reason) <= 1000),
  constraint ledger_key_bounded check (char_length(dedupe_key) between 1 and 200)
);
create index ledger_project_idx on public.ledger_entries (project_id, entry_type);
create index ledger_refers_idx on public.ledger_entries (refers_to_entry_id);
create index ledger_obligation_idx on public.ledger_entries (obligation_id);
create index ledger_holding_idx on public.ledger_entries (holding_charge_key) where holding_charge_key is not null;

-- 04 §15.2.1 rule 1: each charge maps to fixed obligations. The initial invoice has a
-- development deposit and a maintenance obligation; each later maintenance invoice and the
-- final-balance invoice is one obligation. charge_key: initial:<checkout record>,
-- renewal:<Stripe invoice>, final_balance:<final-balance invoice record>.
create table public.payment_obligations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  order_summary_id uuid references public.order_summaries (id),
  kind public.obligation_kind not null,
  charge_key text not null,
  charge_entry_id bigint not null unique references public.ledger_entries (id),
  original_cents bigint not null check (original_cents > 0),
  service_category public.service_category not null,
  created_at timestamptz not null default now(),
  unique (charge_key, kind),
  constraint obligations_charge_key check (charge_key ~ '^(initial|renewal|final_balance):[A-Za-z0-9_-]{6,200}$'),
  constraint obligations_category check ((kind = 'maintenance') = (service_category = 'maintenance'))
);
create index obligations_project_idx on public.payment_obligations (project_id);
alter table public.ledger_entries
  add constraint ledger_obligation_fk foreign key (obligation_id) references public.payment_obligations (id);

-- Which domain record a Stripe charge or payment intent paid for, learned from invoices.
-- Lets refund and dispute events be attributed regardless of arrival order.
create table private.stripe_payment_links (
  stripe_ref text primary key,
  project_id uuid not null references public.projects (id),
  kind text not null check (kind in ('initial', 'renewal', 'final_balance')),
  domain_record_id uuid,
  stripe_invoice_id text not null,
  created_at timestamptz not null default now(),
  constraint stripe_payment_links_ref check (stripe_ref ~ '^(ch|py|pi)_[A-Za-z0-9_]{6,200}$')
);
revoke all on table private.stripe_payment_links from public, anon, authenticated, service_role;

-- 04 §15.2: the Owner's discretionary refund decision. Issuing the refund is a Tier 3
-- Owner action in Stripe; the ledger refund comes only from the webhook.
create table public.refund_decisions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  -- The charge the refund applies to, and (04 §15.2.1 rule 2c) the per-line allocation that
  -- the Owner records before issuing a partial refund. The Stripe refund must reference the
  -- decision ID; the reference mechanism stays mocked until DEP-06 verifies it.
  charge_key text,
  amount_cents bigint not null check (amount_cents > 0),
  reason text not null check (char_length(reason) between 1 and 1000),
  decided_by uuid not null references public.profiles (id),
  decided_at timestamptz not null default now(),
  matched_refund_id text,
  matched_at timestamptz
);
create table public.refund_decision_lines (
  refund_decision_id uuid not null references public.refund_decisions (id),
  obligation_id uuid not null references public.payment_obligations (id),
  amount_cents bigint not null check (amount_cents > 0),
  primary key (refund_decision_id, obligation_id)
);

-- 04 §15.2.1 rule 6: Owner reclassification of the holding account (immutable record).
create table public.reversal_reconciliations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  charge_key text not null,
  holding_balance_cents bigint not null check (holding_balance_cents <> 0),
  lines jsonb not null,
  reason text not null check (char_length(reason) between 1 and 1000),
  reconciled_by uuid not null references public.profiles (id),
  reconciled_at timestamptz not null default now(),
  constraint reversal_reconciliations_lines check (jsonb_typeof(lines) = 'array' and jsonb_array_length(lines) between 1 and 10)
);

create table public.refunds (
  stripe_refund_id text primary key,
  project_id uuid not null references public.projects (id),
  stripe_charge_ref text not null,
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null check (currency = 'usd'),
  status text not null check (status in ('pending', 'requires_action', 'succeeded', 'failed', 'canceled')),
  refund_decision_id uuid references public.refund_decisions (id),
  last_event_created timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint refunds_id_format check (stripe_refund_id ~ '^(re|pyr)_[A-Za-z0-9_]{6,200}$')
);

-- 04 §15.4 (OI-37). Status values per Stripe's dispute object [VERIFY-PROVIDER, DEP-15].
create table public.disputes (
  stripe_dispute_id text primary key,
  project_id uuid not null references public.projects (id),
  stripe_charge_ref text not null,
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null check (currency = 'usd'),
  status text not null check (status in ('warning_needs_response', 'warning_under_review', 'warning_closed',
    'needs_response', 'under_review', 'won', 'lost', 'prevented')),
  reason text check (reason is null or char_length(reason) <= 100),
  evidence_due_by timestamptz,
  opened_at timestamptz not null,
  closed_at timestamptz,
  last_event_created timestamptz not null,
  updated_at timestamptz not null default now(),
  constraint disputes_id_format check (stripe_dispute_id ~ '^(dp|du)_[A-Za-z0-9_]{6,200}$')
);
create index disputes_project_idx on public.disputes (project_id);

create table public.subscriptions (
  stripe_subscription_id text primary key,
  project_id uuid not null references public.projects (id),
  stripe_customer_id text,
  status public.subscription_status not null,
  cancel_at_period_end boolean not null default false,
  current_period_end timestamptz,
  canceled_at timestamptz,
  last_event_created timestamptz not null,
  updated_at timestamptz not null default now(),
  constraint subscriptions_id_format check (stripe_subscription_id ~ '^sub_[A-Za-z0-9_]{6,200}$')
);
create unique index subscriptions_one_per_project on public.subscriptions (project_id)
  where status not in ('canceled', 'incomplete_expired');

-- 04 §9.1 (OI-26): one recovery per failed renewal invoice; deadline stored once in UTC.
create table public.maintenance_recoveries (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  stripe_invoice_id text not null unique,
  stripe_subscription_id text,
  failed_at timestamptz not null,
  recovery_ends_at timestamptz not null,
  calendar_version text not null,
  status public.maintenance_recovery_status not null default 'in_recovery',
  recovered_at timestamptz,
  created_at timestamptz not null default now(),
  constraint recoveries_invoice_format check (stripe_invoice_id ~ '^in_[A-Za-z0-9_]{6,200}$')
);

-- 04 §14: WP-B hold records (OI-71 item 3). approval_nonresponsive_hold is WP-C's.
create table public.billing_holds (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  hold_type public.hold_type not null,
  trigger_source text not null,
  source_ref text,
  placed_at timestamptz not null default now(),
  placed_by uuid references public.profiles (id),
  reason text,
  cleared_at timestamptz,
  cleared_by uuid references public.profiles (id),
  clear_kind text,
  clear_reason text,
  clearing_evidence jsonb,
  constraint billing_holds_type check (hold_type in ('maintenance_payment_hold', 'dispute_risk_hold', 'owner_manual_hold')),
  constraint billing_holds_source check (
    (hold_type = 'maintenance_payment_hold' and trigger_source = 'system' and source_ref is not null)
    or (hold_type <> 'maintenance_payment_hold' and trigger_source = 'owner' and placed_by is not null and reason is not null)),
  constraint billing_holds_clear_shape check (
    (cleared_at is null and clear_kind is null)
    or (cleared_at is not null and clear_kind in ('verified_recovery', 'owner_exception', 'owner_clear'))),
  constraint billing_holds_reason_bounded check (
    (reason is null or char_length(reason) <= 1000) and (clear_reason is null or char_length(clear_reason) <= 1000)),
  constraint billing_holds_evidence check (clearing_evidence is null or private.payload_is_safe(clearing_evidence, 2048))
);
create unique index billing_holds_one_active_system on public.billing_holds (source_ref)
  where cleared_at is null and hold_type = 'maintenance_payment_hold';
create unique index billing_holds_one_active_manual on public.billing_holds (project_id, hold_type)
  where cleared_at is null and hold_type in ('dispute_risk_hold', 'owner_manual_hold');

create table public.billing_hold_reviews (
  id uuid primary key default gen_random_uuid(),
  hold_id uuid not null references public.billing_holds (id),
  decision public.billing_hold_review_decision not null,
  reason text not null check (char_length(reason) between 1 and 1000),
  decided_by uuid not null references public.profiles (id),
  decided_at timestamptz not null default now()
);

create table public.stripe_cancellation_exceptions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  stripe_subscription_id text not null unique,
  webhook_event_id bigint not null references public.webhook_events (id),
  detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id),
  resolution text check (resolution is null or char_length(resolution) between 1 and 1000)
);

-- 04 §15.1.1: cancellation requests (request date recorded separately from the effective date).
create table public.cancellation_requests (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  channel text not null check (channel in ('portal', 'written_notice')),
  requested_by uuid references public.profiles (id),
  recorded_by uuid references public.profiles (id),
  request_date timestamptz not null,
  status public.cancellation_request_status not null default 'received',
  confirmed_by uuid references public.profiles (id),
  confirmed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index cancellation_one_received on public.cancellation_requests (project_id) where status = 'received';

-- 04 §9.1.1 and §15.1: one active termination per project (T-BIL-16).
create table public.service_terminations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  origin text not null check (origin in ('billing_hold_review', 'client_cancellation')),
  state public.service_termination_state not null,
  billing_hold_id uuid references public.billing_holds (id),
  cancellation_request_id uuid references public.cancellation_requests (id),
  opened_by uuid not null references public.profiles (id),
  opened_at timestamptz not null default now(),
  reason text not null check (char_length(reason) between 1 and 1000),
  authorized_by uuid references public.profiles (id),
  authorized_at timestamptz,
  effective_cancellation_date date,
  m1_deadline timestamptz,
  m2_deadline timestamptz,
  calendar_version text,
  became_effective_at timestamptz,
  maintenance_ceased_at timestamptz,
  services_deactivated_at timestamptz,
  transferred_at timestamptz,
  withdrawn_at timestamptz,
  constraint terminations_state check (state <> 'none'),
  constraint terminations_deadlines check (
    (state in ('under_owner_review', 'withdrawn') and effective_cancellation_date is null)
    or (state in ('withdrawn')) or
    (effective_cancellation_date is not null and m1_deadline is not null and m2_deadline is not null
     and calendar_version is not null and m1_deadline < m2_deadline))
);
create unique index terminations_one_active on public.service_terminations (project_id)
  where state not in ('offboarded', 'transferred', 'withdrawn');

create table public.termination_notices (
  id uuid primary key default gen_random_uuid(),
  termination_id uuid not null references public.service_terminations (id),
  notice_kind text not null check (notice_kind in ('milestones_and_responsibilities', 'm1_reached', 'm2_minus_30_days', 'm2_minus_7_days')),
  recorded_by uuid not null references public.profiles (id),
  sent_at timestamptz not null default now(),
  unique (termination_id, notice_kind)
);

-- 04 §10: the final-balance obligation. Uniqueness protects the obligation, not the
-- approval: one invoice per order summary, and at most one non-void invoice per project, so
-- a repeated approval, a replayed event, or a later release revision can never create a
-- second outstanding invoice.
create table public.final_balance_invoices (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  order_summary_id uuid not null unique references public.order_summaries (id),
  acceptance_id uuid not null references public.agreement_acceptances (id),
  approval_id uuid not null,
  release_id uuid not null,
  source_domain_event_id bigint not null references public.domain_events (id),
  amount_cents bigint not null check (amount_cents > 0),
  currency text not null default 'usd' check (currency = 'usd'),
  balance_price_id text not null,
  stripe_customer_id text not null,
  -- 04 §10 (OI-74): charged automatically to the authorization's card; when the authorization
  -- is not active, finalized without an automatic attempt and paid only on its hosted page.
  collection_method text not null default 'charge_automatically' check (collection_method = 'charge_automatically'),
  collection_mode text not null check (collection_mode in ('automatic', 'hosted_only')),
  payment_authorization_id uuid,
  default_payment_method_id text,
  automatic_stop_required boolean not null default false,
  -- Why automatic collection stopped (set once): 'revoked' or 'payment_method_detached' make
  -- a payment that still lands an Owner review item; 'charge_failed' is the expected
  -- hosted-page completion path (04 §10).
  halt_cause text check (halt_cause is null or halt_cause in ('revoked', 'payment_method_detached', 'charge_failed', 'authorization_changed')),
  charged_after_halt boolean not null default false,
  status public.final_balance_invoice_status not null default 'creating',
  stripe_invoice_id text unique,
  hosted_invoice_url text,
  last_event_created timestamptz,
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  paid_at timestamptz,
  constraint fbi_invoice_format check (stripe_invoice_id is null or stripe_invoice_id ~ '^in_[A-Za-z0-9_]{6,200}$'),
  constraint fbi_automatic_card check (collection_mode <> 'automatic' or (default_payment_method_id is not null and payment_authorization_id is not null)),
  constraint fbi_url_host check (hosted_invoice_url is null or (hosted_invoice_url ~ '^https://invoice\.stripe\.com/' and char_length(hosted_invoice_url) <= 2000))
);
create unique index fbi_one_per_project on public.final_balance_invoices (project_id) where status <> 'void';

-- Durable, idempotent consumption of domain events by WP-B (01 §7; CURRENT-STATE §8).
create table private.event_consumptions (
  consumer text not null,
  domain_event_id bigint not null references public.domain_events (id),
  outcome text not null default 'pending' check (outcome in ('pending', 'created', 'duplicate_obligation', 'rejected')),
  detail text check (detail is null or char_length(detail) <= 200),
  consumed_at timestamptz not null default now(),
  primary key (consumer, domain_event_id)
);
revoke all on table private.event_consumptions from public, anon, authenticated, service_role;

-- 04 §8.1 (OI-74): the payment authorization for the final balance. References the
-- acceptance evidence rather than copying it. Never stores card data (not even brand or last
-- four). At most one non-revoked authorization per project; revoked is terminal.
create table public.payment_authorizations (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  client_business_id uuid not null references public.client_businesses (id),
  acceptance_id uuid not null references public.agreement_acceptances (id),
  agreement_version_id uuid not null references public.agreement_versions (id),
  order_summary_id uuid not null references public.order_summaries (id),
  authorized_at timestamptz not null,
  authorized_balance_cents bigint not null check (authorized_balance_cents >= 0),
  currency text not null default 'usd' check (currency = 'usd'),
  stripe_customer_id text not null,
  stripe_payment_method_id text not null,
  status public.payment_authorization_status not null default 'active',
  checkout_session_id uuid references public.checkout_sessions (id),
  recovery_session_id uuid,
  evidence_webhook_event_id bigint not null references public.webhook_events (id),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles (id),
  revocation_source text check (revocation_source is null or revocation_source in ('client', 'owner')),
  revocation_reason text check (revocation_reason is null or char_length(revocation_reason) <= 1000),
  revocation_reviewed_at timestamptz,
  revocation_reviewed_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint authorizations_pm_format check (stripe_payment_method_id ~ '^(pm|card)_[A-Za-z0-9_]{6,200}$'),
  constraint authorizations_customer_format check (stripe_customer_id ~ '^cus_[A-Za-z0-9]{6,64}$'),
  constraint authorizations_revoked_shape check ((status = 'revoked') = (revoked_at is not null and revocation_source is not null))
);
create unique index authorizations_one_live on public.payment_authorizations (project_id) where status <> 'revoked';

create table public.payment_authorization_events (
  id bigint generated always as identity primary key,
  payment_authorization_id uuid not null references public.payment_authorizations (id),
  project_id uuid not null references public.projects (id),
  event text not null check (event in ('established', 'unavailable', 'revoked', 'payment_method_replaced',
    'recovery_session_created', 'automatically_updated', 'charged_after_halt', 'revocation_reviewed')),
  from_status public.payment_authorization_status,
  to_status public.payment_authorization_status,
  stripe_payment_method_id text,
  webhook_event_id bigint references public.webhook_events (id),
  actor_user_id uuid references public.profiles (id),
  reason text check (reason is null or char_length(reason) <= 1000),
  occurred_at timestamptz not null default now()
);
create index authorization_events_auth_idx on public.payment_authorization_events (payment_authorization_id, id);

-- 04 §8.1: setup-mode payment method recovery (card only; saves a card, never charges).
create table public.recovery_sessions (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id),
  payment_authorization_id uuid references public.payment_authorizations (id),
  acceptance_id uuid not null references public.agreement_acceptances (id),
  attempt smallint not null check (attempt between 1 and 50),
  status public.checkout_session_status not null default 'creating',
  stripe_checkout_session_id text unique,
  checkout_url text,
  stripe_setup_intent_id text unique,
  evidence_webhook_event_id bigint references public.webhook_events (id),
  completed_at timestamptz,
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, attempt),
  constraint recovery_stripe_id check (stripe_checkout_session_id is null or stripe_checkout_session_id ~ '^cs_[A-Za-z0-9_]{6,200}$'),
  constraint recovery_setup_intent check (stripe_setup_intent_id is null or stripe_setup_intent_id ~ '^seti_[A-Za-z0-9_]{6,200}$'),
  constraint recovery_url_host check (checkout_url is null or (checkout_url ~ '^https://checkout\.stripe\.com/' and char_length(checkout_url) <= 2000))
);
create unique index recovery_one_open on public.recovery_sessions (project_id) where status in ('creating', 'open');
alter table public.payment_authorizations
  add constraint authorizations_recovery_fk foreign key (recovery_session_id) references public.recovery_sessions (id);
alter table public.final_balance_invoices
  add constraint fbi_authorization_fk foreign key (payment_authorization_id) references public.payment_authorizations (id);

-- 04 §13 (T-ARC-09): one row per billing job run; audited; single-flight by advisory lock.
create table public.billing_job_runs (
  id uuid primary key default gen_random_uuid(),
  job text not null check (job in ('reconciliation', 'maintenance_recovery', 'webhook_backfill',
    'release_approvals', 'service_terminations', 'outbound_requests', 'payment_method_lookups')),
  run_key text not null,
  status text not null default 'running' check (status in ('running', 'completed')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  result jsonb,
  unique (job, run_key),
  constraint billing_job_result check (result is null or private.payload_is_safe(result, 8192))
);

-- 04 §13: reconciliation runs and quarantined mismatches. Never correct payment state.
create table public.reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  source text not null check (source in ('mocked_gateway', 'stripe_test_mode', 'stripe_live')),
  -- One run per key (the America/Detroit date for the daily run): a rerun is a no-op (T-ARC-09).
  run_key text not null unique check (char_length(run_key) between 1 and 100),
  billing_job_run_id uuid references public.billing_job_runs (id),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  projects_checked integer not null default 0,
  mismatch_count integer not null default 0
);
-- B1 (fail closed): an Owner reconciliation item for any unresolved financial-integrity
-- anomaly the daily run or an event detects. Each blocks G2 or G4 by its charge (or both
-- when the charge is unknown) until the Owner resolves it; resolving never posts money.
create table public.reconciliation_mismatches (
  id uuid primary key default gen_random_uuid(),
  -- Null only for an item detected while processing a verified event (charged_after_halt).
  run_id uuid references public.reconciliation_runs (id),
  project_id uuid not null references public.projects (id),
  kind text not null check (kind in ('charges_total', 'refunds_total', 'deposit_snapshot', 'balance_snapshot', 'disputes_open',
    'unmatched_refund', 'unmatched_dispute', 'charged_after_halt')),
  -- The charge the item is attributed to (initial:, renewal:, final_balance:); null = unknown.
  charge_key text check (charge_key is null or charge_key ~ '^(initial|renewal|final_balance):[A-Za-z0-9_-]{6,200}$'),
  -- The Stripe refund or dispute observed by reconciliation, and its status then.
  stripe_object_id text check (stripe_object_id is null or stripe_object_id ~ '^[a-z]{2,4}_[A-Za-z0-9_]{6,200}$'),
  observed_status text check (observed_status is null or observed_status ~ '^[a-z_]{1,40}$'),
  expected_cents bigint,
  observed_cents bigint,
  detected_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles (id),
  resolution text check (resolution is null or char_length(resolution) between 1 and 1000),
  constraint mismatch_source check ((run_id is null) = (kind = 'charged_after_halt')),
  constraint mismatch_object check ((kind in ('unmatched_refund', 'unmatched_dispute')) = (stripe_object_id is not null)),
  constraint mismatch_halt_charge check (kind <> 'charged_after_halt' or charge_key like 'final\_balance:%')
);
-- One item per observed object state, and one charged-after-halt item per invoice.
create unique index reconciliation_mismatches_object_idx on public.reconciliation_mismatches (stripe_object_id, observed_status)
  where stripe_object_id is not null;
create unique index reconciliation_mismatches_halt_idx on public.reconciliation_mismatches (charge_key)
  where kind = 'charged_after_halt';

-- ---------------------------------------------------------------------------
-- 4. Immutability and transition guards
-- ---------------------------------------------------------------------------
create trigger ledger_entries_insert_only before update or delete on public.ledger_entries
  for each row execute function private.insert_only();
create function private.no_truncate() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception '% cannot be truncated', tg_table_name using errcode = '42501';
end;
$$;
create trigger ledger_entries_no_truncate before truncate on public.ledger_entries
  for each statement execute function private.no_truncate();
create trigger webhook_events_no_truncate before truncate on public.webhook_events
  for each statement execute function private.no_truncate();
create trigger billing_hold_reviews_insert_only before update or delete on public.billing_hold_reviews
  for each row execute function private.insert_only();
create trigger termination_notices_insert_only before update or delete on public.termination_notices
  for each row execute function private.insert_only();
create trigger payment_obligations_insert_only before update or delete on public.payment_obligations
  for each row execute function private.insert_only();
create trigger refund_decision_lines_insert_only before update or delete on public.refund_decision_lines
  for each row execute function private.insert_only();
create trigger reversal_reconciliations_insert_only before update or delete on public.reversal_reconciliations
  for each row execute function private.insert_only();
create trigger authorization_events_insert_only before update or delete on public.payment_authorization_events
  for each row execute function private.insert_only();

-- A generic guard: rows are never deleted, and only the listed columns may change.
create function private.guard_columns() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_mutable text[] := tg_argv;
begin
  if tg_op = 'DELETE' then
    raise exception '% rows are never deleted', tg_table_name using errcode = '42501';
  end if;
  if (to_jsonb(new) - v_mutable) is distinct from (to_jsonb(old) - v_mutable) then
    raise exception '% identity columns are immutable', tg_table_name using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger stripe_customers_guard before update or delete on public.stripe_customers
  for each row execute function private.guard_columns();
create trigger refund_decisions_guard before update or delete on public.refund_decisions
  for each row execute function private.guard_columns('matched_refund_id', 'matched_at');
create trigger refunds_guard before update or delete on public.refunds
  for each row execute function private.guard_columns('status', 'last_event_created', 'updated_at', 'refund_decision_id');
create trigger disputes_guard before update or delete on public.disputes
  for each row execute function private.guard_columns('status', 'reason', 'evidence_due_by', 'closed_at', 'last_event_created', 'updated_at');
create trigger subscriptions_guard before update or delete on public.subscriptions
  for each row execute function private.guard_columns('status', 'cancel_at_period_end', 'current_period_end', 'canceled_at', 'last_event_created', 'updated_at', 'stripe_customer_id');
create trigger recoveries_guard before update or delete on public.maintenance_recoveries
  for each row execute function private.guard_columns('status', 'recovered_at');
create trigger billing_holds_guard before update or delete on public.billing_holds
  for each row execute function private.guard_columns('cleared_at', 'cleared_by', 'clear_kind', 'clear_reason', 'clearing_evidence');
create trigger cancellation_exceptions_guard before update or delete on public.stripe_cancellation_exceptions
  for each row execute function private.guard_columns('resolved_at', 'resolved_by', 'resolution');
create trigger cancellation_requests_guard before update or delete on public.cancellation_requests
  for each row execute function private.guard_columns('status', 'confirmed_by', 'confirmed_at');
create trigger terminations_guard before update or delete on public.service_terminations
  for each row execute function private.guard_columns('state', 'authorized_by', 'authorized_at', 'effective_cancellation_date',
    'm1_deadline', 'm2_deadline', 'calendar_version', 'became_effective_at', 'maintenance_ceased_at',
    'services_deactivated_at', 'transferred_at', 'withdrawn_at');
create trigger reconciliation_runs_guard before update or delete on public.reconciliation_runs
  for each row execute function private.guard_columns('completed_at', 'projects_checked', 'mismatch_count');
create trigger reconciliation_mismatches_guard before update or delete on public.reconciliation_mismatches
  for each row execute function private.guard_columns('resolved_at', 'resolved_by', 'resolution');
-- B1: an Owner resolution is recorded once and never undone or rewritten.
create function private.mismatch_resolution_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.resolved_at is not null and (new.resolved_at, new.resolved_by, new.resolution)
     is distinct from (old.resolved_at, old.resolved_by, old.resolution) then
    raise exception 'a reconciliation resolution is recorded once' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger reconciliation_mismatches_resolution_guard before update on public.reconciliation_mismatches
  for each row execute function private.mismatch_resolution_guard();
create trigger event_consumptions_guard before update or delete on private.event_consumptions
  for each row execute function private.guard_columns('outcome', 'detail');
create trigger billing_job_runs_guard before update or delete on public.billing_job_runs
  for each row execute function private.guard_columns('status', 'completed_at', 'result');

-- Set-once columns and monotonic statuses.
create function private.set_once(p_old text, p_new text) returns boolean
language sql immutable set search_path = '' as $$
  select p_old is null or p_old is not distinct from p_new;
$$;

create function private.outbound_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'outbound Stripe requests are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.purpose, new.project_id, new.domain_record_type, new.domain_record_id, new.attempt,
      new.idempotency_key, new.request_params, new.created_at)
     is distinct from
     (old.id, old.purpose, old.project_id, old.domain_record_type, old.domain_record_id, old.attempt,
      old.idempotency_key, old.request_params, old.created_at)
     or not private.set_once(old.stripe_object_id, new.stripe_object_id)
     or not private.set_once(old.claimed_at::text, new.claimed_at::text) then
    raise exception 'outbound Stripe request identity is immutable' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'pending' and new.status in ('succeeded', 'failed', 'ambiguous'))
    or (old.status = 'ambiguous' and new.status in ('reconciled_present', 'reconciled_absent'))
    -- B1: a failed automatic-collection stop is reconciled by the Owner against Stripe.
    or (old.status = 'failed' and new.status in ('reconciled_present', 'reconciled_absent')
        and old.purpose = 'final_balance_invoice_disable_auto' and coalesce(old.error_code, '') <> 'already_paid')) then
    raise exception 'invalid outbound request transition % -> %', old.status, new.status using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger outbound_guard before update or delete on public.outbound_stripe_requests
  for each row execute function private.outbound_guard();

create function private.checkout_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'checkout sessions are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.order_summary_id, new.acceptance_id, new.kind, new.attempt, new.created_at)
     is distinct from (old.id, old.project_id, old.order_summary_id, old.acceptance_id, old.kind, old.attempt, old.created_at)
     or not private.set_once(old.stripe_checkout_session_id, new.stripe_checkout_session_id)
     or not private.set_once(old.stripe_customer_id, new.stripe_customer_id)
     or not private.set_once(old.stripe_subscription_id, new.stripe_subscription_id)
     or not private.set_once(old.stripe_invoice_id, new.stripe_invoice_id)
     or not private.set_once(old.checkout_url, new.checkout_url)
     or not private.set_once(old.payment_method_checked_at::text, new.payment_method_checked_at::text)
     or not private.set_once(old.payment_method_reusable::text, new.payment_method_reusable::text) then
    raise exception 'checkout session identity is immutable' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'creating' and new.status in ('open', 'failed', 'complete', 'expired'))
    or (old.status = 'open' and new.status in ('complete', 'expired'))) then
    raise exception 'invalid checkout transition % -> %', old.status, new.status using errcode = '23514';
  end if;
  -- A verified payment is never downgraded by a late event (04 §17 #5).
  if old.payment_status = 'paid' and new.payment_status is distinct from 'paid' then
    raise exception 'a paid checkout session cannot be downgraded' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger checkout_guard before update or delete on public.checkout_sessions
  for each row execute function private.checkout_guard();

create function private.webhook_events_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'webhook events are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.stripe_event_id, new.event_type, new.api_version, new.livemode, new.stripe_created_at,
      new.object_type, new.object_id, new.payload, new.raw_body_sha256, new.signature_verified, new.received_at)
     is distinct from
     (old.id, old.stripe_event_id, old.event_type, old.api_version, old.livemode, old.stripe_created_at,
      old.object_type, old.object_id, old.payload, old.raw_body_sha256, old.signature_verified, old.received_at) then
    raise exception 'stored webhook events are immutable' using errcode = '42501';
  end if;
  if new.processing_status is distinct from old.processing_status
     and old.processing_status in ('processed', 'ignored', 'quarantined') then
    raise exception 'webhook event in terminal status % cannot change', old.processing_status using errcode = '23514';
  end if;
  if old.quarantine_resolved_at is not null and (new.quarantine_resolved_at, new.quarantine_resolved_by, new.quarantine_resolution)
     is distinct from (old.quarantine_resolved_at, old.quarantine_resolved_by, old.quarantine_resolution) then
    raise exception 'a quarantine resolution is recorded once' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger webhook_events_guard before update or delete on public.webhook_events
  for each row execute function private.webhook_events_guard();

create function private.fbi_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'final-balance invoices are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.order_summary_id, new.acceptance_id, new.approval_id, new.release_id,
      new.source_domain_event_id, new.amount_cents, new.currency, new.balance_price_id,
      new.stripe_customer_id, new.collection_method, new.payment_authorization_id,
      new.default_payment_method_id, new.created_at)
     is distinct from
     (old.id, old.project_id, old.order_summary_id, old.acceptance_id, old.approval_id, old.release_id,
      old.source_domain_event_id, old.amount_cents, old.currency, old.balance_price_id,
      old.stripe_customer_id, old.collection_method, old.payment_authorization_id,
      old.default_payment_method_id, old.created_at)
     or not private.set_once(old.stripe_invoice_id, new.stripe_invoice_id)
     or not private.set_once(old.halt_cause, new.halt_cause) then
    raise exception 'the final-balance obligation is immutable' using errcode = '42501';
  end if;
  -- Collection only ever moves toward the safer mode, and the halt flags never clear.
  if (old.collection_mode = 'hosted_only' and new.collection_mode = 'automatic')
     or (old.automatic_stop_required and not new.automatic_stop_required)
     or (old.charged_after_halt and not new.charged_after_halt) then
    raise exception 'automatic collection cannot be re-enabled on a halted invoice' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'creating' and new.status in ('open', 'creation_failed', 'paid', 'payment_failed', 'action_required'))
    or (old.status = 'creation_failed' and new.status in ('creating'))
    or (old.status in ('open', 'payment_failed', 'action_required') and new.status in ('open', 'paid', 'payment_failed', 'action_required'))) then
    raise exception 'invalid final-balance transition % -> %', old.status, new.status using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger fbi_guard before update or delete on public.final_balance_invoices
  for each row execute function private.fbi_guard();

-- Authorization: identity and evidence references never change; the card changes only when
-- a verified replacement makes the authorization active; revoked is terminal (a late or
-- replayed event can never re-activate it, T-PAY-25).
create function private.authorizations_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'payment authorizations are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.client_business_id, new.acceptance_id, new.agreement_version_id,
      new.order_summary_id, new.authorized_at, new.authorized_balance_cents, new.currency,
      new.stripe_customer_id, new.checkout_session_id, new.created_at)
     is distinct from
     (old.id, old.project_id, old.client_business_id, old.acceptance_id, old.agreement_version_id,
      old.order_summary_id, old.authorized_at, old.authorized_balance_cents, old.currency,
      old.stripe_customer_id, old.checkout_session_id, old.created_at) then
    raise exception 'payment authorization identity is immutable' using errcode = '42501';
  end if;
  if old.status = 'revoked' and (new.status, new.stripe_payment_method_id, new.revoked_at, new.revoked_by,
       new.revocation_source, new.revocation_reason) is distinct from (old.status, old.stripe_payment_method_id,
       old.revoked_at, old.revoked_by, old.revocation_source, old.revocation_reason) then
    raise exception 'a revoked payment authorization is final' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'active' and new.status in ('payment_method_unavailable', 'revoked'))
    or (old.status = 'payment_method_unavailable' and new.status in ('active', 'revoked'))) then
    raise exception 'invalid payment authorization transition % -> %', old.status, new.status using errcode = '23514';
  end if;
  if new.stripe_payment_method_id is distinct from old.stripe_payment_method_id
     and not (new.status = 'active' and new.recovery_session_id is distinct from old.recovery_session_id) then
    raise exception 'the card changes only through a verified recovery' using errcode = '42501';
  end if;
  if old.revocation_reviewed_at is not null
     and (new.revocation_reviewed_at, new.revocation_reviewed_by) is distinct from (old.revocation_reviewed_at, old.revocation_reviewed_by) then
    raise exception 'a revocation review is recorded once' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger authorizations_guard before update or delete on public.payment_authorizations
  for each row execute function private.authorizations_guard();

create function private.recovery_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'recovery sessions are never deleted' using errcode = '42501';
  end if;
  if (new.id, new.project_id, new.payment_authorization_id, new.acceptance_id, new.attempt, new.created_at)
     is distinct from (old.id, old.project_id, old.payment_authorization_id, old.acceptance_id, old.attempt, old.created_at)
     or not private.set_once(old.stripe_checkout_session_id, new.stripe_checkout_session_id)
     or not private.set_once(old.checkout_url, new.checkout_url)
     or not private.set_once(old.stripe_setup_intent_id, new.stripe_setup_intent_id)
     or not private.set_once(old.evidence_webhook_event_id::text, new.evidence_webhook_event_id::text)
     or not private.set_once(old.applied_at::text, new.applied_at::text) then
    raise exception 'recovery session identity is immutable' using errcode = '42501';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'creating' and new.status in ('open', 'failed', 'complete', 'expired'))
    or (old.status = 'open' and new.status in ('complete', 'expired'))) then
    raise exception 'invalid recovery transition % -> %', old.status, new.status using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger recovery_guard before update or delete on public.recovery_sessions
  for each row execute function private.recovery_guard();

-- ---------------------------------------------------------------------------
-- 5. Derived state (05 §2: computed from records, never an editable status)
-- ---------------------------------------------------------------------------
create function private.dispute_is_open(p_status text) returns boolean
language sql immutable set search_path = '' as $$
  select p_status not in ('won', 'warning_closed', 'prevented');
$$;

-- 04 §15.2.1: net retained cents of an obligation after every reversal entry referring to it
-- (refunds and disputes are negative, reinstatements positive, reclassifications signed).
create function private.obligation_net_cents(p_obligation_id uuid) returns bigint
language sql stable security definer set search_path = '' as $$
  select o.original_cents + coalesce((select sum(l.amount_cents) from public.ledger_entries l
                                      where l.obligation_id = o.id), 0)
  from public.payment_obligations o where o.id = p_obligation_id;
$$;

-- Unresolved reversal holding balance of one charge (rule 2d). Zero means resolved.
create function private.holding_balance_cents(p_charge_key text) returns bigint
language sql stable security definer set search_path = '' as $$
  select coalesce(sum(l.amount_cents), 0) from public.ledger_entries l where l.holding_charge_key = p_charge_key;
$$;

-- An obligation is disputed while an open (or lost) dispute withdrew funds from it, directly
-- or through the holding account of its charge.
create function private.obligation_disputed(p_obligation_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.ledger_entries x
    join public.disputes d on d.stripe_dispute_id = x.stripe_object_id
    join public.payment_obligations o on o.id = p_obligation_id
    where x.entry_type = 'dispute_opened'
      and (x.obligation_id = o.id or x.holding_charge_key = o.charge_key)
      and (private.dispute_is_open(d.status) or d.status = 'lost'));
$$;

create function private.project_deposit_ever_verified(p_project_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ledger_entries where project_id = p_project_id and entry_type = 'deposit_charge');
$$;

create function private.project_deposit_obligation(p_project_id uuid) returns public.payment_obligations
language sql stable security definer set search_path = '' as $$
  select o.* from public.payment_obligations o
  where o.project_id = p_project_id and o.kind = 'development_deposit' order by o.created_at limit 1;
$$;

-- Deposit (05 §2): verified only from the webhook-derived ledger. Disputed while funds are
-- withdrawn; refunded once the deposit obligation is fully reversed (04 §15.2.1).
create function private.project_deposit_state(p_project_id uuid) returns public.deposit_state
language plpgsql stable security definer set search_path = '' as $$
declare
  v_ob public.payment_obligations%rowtype;
  v_session public.checkout_sessions%rowtype;
begin
  v_ob := private.project_deposit_obligation(p_project_id);
  if v_ob.id is not null then
    if private.obligation_disputed(v_ob.id) then
      return 'disputed';
    end if;
    if private.obligation_net_cents(v_ob.id) <= 0 then
      return 'refunded';
    end if;
    return 'verified';
  end if;
  select * into v_session from public.checkout_sessions
   where project_id = p_project_id and kind = 'initial' order by created_at desc, attempt desc limit 1;
  if not found then
    return 'not_started';
  end if;
  if v_session.status in ('expired', 'failed') or v_session.payment_status = 'failed' then
    return 'failed';
  end if;
  return 'pending';
end;
$$;

-- G2 (06 §2, 04 §15.2.1 rule 3): verified, and no unresolved reversal on the initial charge.
create function private.project_deposit_verified(p_project_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.project_deposit_state(p_project_id) = 'verified'
     and private.holding_balance_cents((private.project_deposit_obligation(p_project_id)).charge_key) = 0;
$$;

create function private.project_final_balance_state(p_project_id uuid) returns public.final_balance_state
language plpgsql stable security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_ob public.payment_obligations%rowtype;
begin
  select * into v_fbi from public.final_balance_invoices
   where project_id = p_project_id and status <> 'void' order by created_at desc limit 1;
  if not found then
    return 'not_due';
  end if;
  if v_fbi.status = 'paid' then
    select * into v_ob from public.payment_obligations
     where charge_key = 'final_balance:' || v_fbi.id::text and kind = 'development_balance';
    if not found then
      return 'pending';
    end if;
    if private.obligation_disputed(v_ob.id) then
      return 'disputed';
    end if;
    if private.obligation_net_cents(v_ob.id) < v_ob.original_cents then
      return 'refunded';
    end if;
    return 'verified';
  end if;
  return case v_fbi.status
    when 'open' then 'pending'::public.final_balance_state
    when 'action_required' then 'pending'::public.final_balance_state
    when 'payment_failed' then 'failed'::public.final_balance_state
    else 'due'::public.final_balance_state end;
end;
$$;

-- G4 (04 §15.2.1 rule 3): verified, and no unresolved reversal on the final-balance invoice.
create function private.project_balance_verified(p_project_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.project_final_balance_state(p_project_id) = 'verified'
     and not exists (select 1 from public.final_balance_invoices f where f.project_id = p_project_id
                       and f.status = 'paid' and private.holding_balance_cents('final_balance:' || f.id::text) <> 0);
$$;

-- 04 §8.1: the project's live authorization, or the latest revoked one.
create function private.project_payment_authorization(p_project_id uuid) returns public.payment_authorizations
language sql stable security definer set search_path = '' as $$
  select a.* from public.payment_authorizations a where a.project_id = p_project_id
  order by (a.status <> 'revoked') desc, a.created_at desc limit 1;
$$;

create function private.payment_authorization_state(p_project_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((private.project_payment_authorization(p_project_id)).status::text, 'none');
$$;

-- Agreement (04 §1; G1 per OI-71 item 1).
create function private.project_agreement_state(p_project_id uuid,
  out state public.agreement_state, out order_summary_id uuid, out acceptance_id uuid)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_summary_id uuid;
begin
  select os.id into v_summary_id from public.order_summaries os
   where os.project_id = p_project_id and os.status = 'presented';
  order_summary_id := v_summary_id;
  if v_summary_id is null then
    state := 'not_presented';
    return;
  end if;
  select a.id into acceptance_id from public.agreement_acceptances a where a.order_summary_id = v_summary_id;
  if acceptance_id is null then
    if private.project_deposit_ever_verified(p_project_id) and exists (
         select 1 from public.agreement_acceptances a join public.order_summaries os on os.id = a.order_summary_id
         where os.project_id = p_project_id and os.status = 'superseded') then
      state := 'reacceptance_required';
    else
      state := 'presented';
    end if;
    return;
  end if;
  state := case when private.project_deposit_ever_verified(p_project_id) then 'effective'
                else 'accepted_pending_payment' end;
end;
$$;

create function private.project_active_billing_holds(p_project_id uuid) returns public.hold_type[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct h.hold_type order by h.hold_type), '{}')
  from public.billing_holds h where h.project_id = p_project_id and h.cleared_at is null;
$$;

-- ---------------------------------------------------------------------------
-- 6. Posting and effects (single transaction with the caller)
-- ---------------------------------------------------------------------------
create function private.audit_financial(p_action text, p_target_type text, p_target_id text,
  p_project_id uuid, p_summary jsonb default '{}'::jsonb, p_reason text default null) returns void
language sql security definer set search_path = '' as $$
  select private.record_audit_event(p_action, p_target_type, p_target_id, p_project_id, p_reason, p_summary, 'financial');
$$;

-- Returns the new entry id, or null when the dedupe key was already posted (idempotent).
create function private.post_ledger_entry(
  p_project_id uuid, p_order_summary_id uuid, p_type public.ledger_entry_type, p_amount bigint,
  p_category public.service_category, p_webhook_event_id bigint, p_object_type text, p_object_id text,
  p_invoice_id text, p_charge_ref text, p_refers_to bigint, p_dedupe_key text
) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into public.ledger_entries (project_id, order_summary_id, entry_type, amount_cents, service_category,
    source, webhook_event_id, stripe_object_type, stripe_object_id, stripe_invoice_id, stripe_charge_ref,
    refers_to_entry_id, dedupe_key)
  values (p_project_id, p_order_summary_id, p_type, p_amount, p_category, 'webhook', p_webhook_event_id,
    p_object_type, p_object_id, p_invoice_id, p_charge_ref, p_refers_to, p_dedupe_key)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is not null then
    perform private.audit_financial('ledger.entry_posted', 'ledger_entry', v_id::text, p_project_id,
      jsonb_build_object('entry_type', p_type, 'amount_cents', p_amount, 'service_category', p_category));
  end if;
  return v_id;
end;
$$;

create function private.link_payment_refs(p_project_id uuid, p_kind text, p_record uuid, p_invoice jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_ref text;
begin
  foreach v_ref in array array[
    p_invoice ->> 'charge', p_invoice ->> 'payment_intent',
    p_invoice #>> '{payments,data,0,payment,charge}', p_invoice #>> '{payments,data,0,payment,payment_intent}'] loop
    if v_ref ~ '^(ch|py|pi)_[A-Za-z0-9_]{6,200}$' then
      insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
      values (v_ref, p_project_id, p_kind, p_record, p_invoice ->> 'id')
      on conflict (stripe_ref) do nothing;
    end if;
  end loop;
end;
$$;

create function private.invoice_price_ids(p_invoice jsonb) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(coalesce(l #>> '{pricing,price_details,price}', l #>> '{price,id}',
                                     case when jsonb_typeof(l -> 'price') = 'string' then l ->> 'price' end)
                            order by ordinality), '{}')
  from jsonb_array_elements(coalesce(p_invoice #> '{lines,data}', '[]'::jsonb)) with ordinality t(l, ordinality);
$$;

create function private.invoice_line_quantities_ok(p_invoice jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(bool_and(coalesce((l ->> 'quantity')::integer, 1) = 1), true)
  from jsonb_array_elements(coalesce(p_invoice #> '{lines,data}', '[]'::jsonb)) l;
$$;

create function private.invoice_discount_cents(p_invoice jsonb) returns bigint
language sql immutable set search_path = '' as $$
  select coalesce((select sum((d ->> 'amount')::bigint)
                   from jsonb_array_elements(coalesce(p_invoice -> 'total_discount_amounts', '[]'::jsonb)) d), 0)
       + case when jsonb_typeof(p_invoice -> 'discounts') = 'array' then jsonb_array_length(p_invoice -> 'discounts') else 0 end;
$$;

create function private.invoice_subscription_metadata(p_invoice jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select coalesce(p_invoice #> '{parent,subscription_details,metadata}', p_invoice #> '{subscription_details,metadata}', '{}'::jsonb);
$$;

create function private.invoice_subscription_id(p_invoice jsonb) returns text
language sql immutable set search_path = '' as $$
  select coalesce(p_invoice #>> '{parent,subscription_details,subscription}',
                  case when jsonb_typeof(p_invoice -> 'subscription') = 'string' then p_invoice ->> 'subscription' end);
$$;

create function private.mark_agreement_effective(p_acceptance_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_acc public.agreement_acceptances%rowtype;
  v_key text := 'agreement.effective:' || p_acceptance_id::text;
begin
  if exists (select 1 from public.domain_events where dedupe_key = v_key) then
    return;
  end if;
  select * into v_acc from public.agreement_acceptances where id = p_acceptance_id;
  perform private.emit_domain_event('agreement.effective', v_acc.project_id, 'agreement_acceptance',
    p_acceptance_id::text, jsonb_build_object('order_summary_id', v_acc.order_summary_id), v_key);
  perform private.record_audit_event('agreement.effective', 'agreement_acceptance', p_acceptance_id::text,
    v_acc.project_id, null, jsonb_build_object('order_summary_id', v_acc.order_summary_id), 'general');
end;
$$;

-- 04 §15.2.1 rule 1: one obligation per charge line, created with the charge entry.
create function private.create_obligation(p_project_id uuid, p_order_summary_id uuid, p_kind public.obligation_kind,
  p_charge_key text, p_entry_dedupe_key text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_entry public.ledger_entries%rowtype;
  v_id uuid;
begin
  select * into v_entry from public.ledger_entries where dedupe_key = p_entry_dedupe_key;
  insert into public.payment_obligations (project_id, order_summary_id, kind, charge_key, charge_entry_id,
    original_cents, service_category)
  values (p_project_id, p_order_summary_id, p_kind, p_charge_key, v_entry.id, v_entry.amount_cents, v_entry.service_category)
  on conflict (charge_key, kind) do nothing
  returning id into v_id;
  return coalesce(v_id, (select id from public.payment_obligations where charge_key = p_charge_key and kind = p_kind));
end;
$$;

-- Posts the deposit and first maintenance entries for an initial Checkout (keys are per
-- checkout record, so the session and invoice events can never double-post; T-PAY-05/06),
-- and their two obligations (04 §15.2.1 rule 1).
create function private.mark_deposit_verified(p_checkout_id uuid, p_webhook_event_id bigint, p_invoice_id text)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_cs public.checkout_sessions%rowtype;
  v_os public.order_summaries%rowtype;
  v_deposit bigint;
  v_event bigint;
  v_key text;
begin
  select * into v_cs from public.checkout_sessions where id = p_checkout_id;
  select * into v_os from public.order_summaries where id = v_cs.order_summary_id;
  v_key := 'initial:' || v_cs.id::text;
  v_deposit := private.post_ledger_entry(v_cs.project_id, v_os.id, 'deposit_charge', v_os.deposit_cents,
    'development', p_webhook_event_id, 'checkout_session', v_cs.stripe_checkout_session_id, p_invoice_id,
    null, null, v_key || ':deposit');
  perform private.post_ledger_entry(v_cs.project_id, v_os.id, 'maintenance_charge', v_os.maintenance_monthly_cents,
    'maintenance', p_webhook_event_id, 'checkout_session', v_cs.stripe_checkout_session_id, p_invoice_id,
    null, null, v_key || ':maintenance');
  perform private.create_obligation(v_cs.project_id, v_os.id, 'development_deposit', v_key, v_key || ':deposit');
  perform private.create_obligation(v_cs.project_id, v_os.id, 'maintenance', v_key, v_key || ':maintenance');
  if v_deposit is null then
    return;
  end if;
  v_event := private.emit_domain_event('payment.deposit_verified', v_cs.project_id, 'checkout_session',
    v_cs.id::text, jsonb_build_object('order_summary_id', v_os.id), 'payment.deposit_verified:' || v_cs.id::text);
  perform private.audit_financial('payment.deposit_verified', 'checkout_session', v_cs.id::text, v_cs.project_id,
    jsonb_build_object('order_summary_id', v_os.id, 'deposit_cents', v_os.deposit_cents));
  perform private.enqueue_notification('payment.deposit_verified', 'payment.deposit_verified:' || v_cs.id::text || ':1',
    'payment.deposit_verified', 1, v_cs.project_id, v_event, private.project_client_user_ids(v_cs.project_id),
    '{}', jsonb_build_object('project_id', v_cs.project_id), 'general');
  perform private.mark_agreement_effective(v_cs.acceptance_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6a. Payment authorization (04 §8.1; OI-74, OI-75). Final-balance authorization only: no
--     function here ever writes the maintenance subscription's payment method.
-- ---------------------------------------------------------------------------
create function private.record_authorization_event(p_authorization_id uuid, p_event text,
  p_from public.payment_authorization_status, p_to public.payment_authorization_status,
  p_payment_method text, p_webhook_event_id bigint, p_reason text) returns void
language sql security definer set search_path = '' as $$
  insert into public.payment_authorization_events (payment_authorization_id, project_id, event, from_status, to_status,
    stripe_payment_method_id, webhook_event_id, actor_user_id, reason)
  select a.id, a.project_id, p_event, p_from, p_to, p_payment_method, p_webhook_event_id, (select auth.uid()), p_reason
  from public.payment_authorizations a where a.id = p_authorization_id;
$$;

-- Stops automatic collection of the project's final-balance invoice (revocation, detached
-- or unavailable card). Serialized with the executor's claim by the authorization row lock
-- the callers hold. Unsent automatic requests are superseded at claim time; an invoice that
-- exists, or a create already in flight, gets a "disable automatic collection" request.
create function private.halt_automatic_collection(p_project_id uuid, p_cause text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
begin
  select * into v_fbi from public.final_balance_invoices
   where project_id = p_project_id and status <> 'void' for update;
  if not found or v_fbi.status = 'paid' or v_fbi.collection_mode <> 'automatic' then
    return;
  end if;
  update public.final_balance_invoices set collection_mode = 'hosted_only', automatic_stop_required = true,
    halt_cause = coalesce(halt_cause, p_cause)
   where id = v_fbi.id;
  if v_fbi.stripe_invoice_id is not null and not exists (
       select 1 from public.outbound_stripe_requests where domain_record_type = 'final_balance_invoice'
         and domain_record_id = v_fbi.id and status in ('pending', 'ambiguous')) then
    perform private.new_outbound_request('final_balance_invoice_disable_auto', p_project_id, 'final_balance_invoice', v_fbi.id,
      'wpb-final-balance-stop-' || v_fbi.id::text, jsonb_build_object('invoice', v_fbi.stripe_invoice_id, 'auto_advance', false));
  end if;
  perform private.audit_financial('balance.automatic_collection_halted', 'final_balance_invoice', v_fbi.id::text,
    p_project_id, jsonb_build_object('cause', p_cause, 'invoice_created', v_fbi.stripe_invoice_id is not null));
end;
$$;

-- Server only: the payment-method re-reads still due (04 §8, invariant 5). Initial
-- Checkouts that verified a deposit, and completed recovery sessions not yet applied.
create function private.payment_method_lookups_due() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  return jsonb_build_object('ok', true,
    'initial', (select coalesce(jsonb_agg(jsonb_build_object('record_id', cs.id, 'stripe_checkout_session_id',
                  cs.stripe_checkout_session_id) order by cs.created_at), '[]'::jsonb)
                from public.checkout_sessions cs
                where cs.payment_status = 'paid' and cs.payment_method_checked_at is null
                  and cs.stripe_checkout_session_id is not null
                  and exists (select 1 from public.payment_obligations o where o.charge_key = 'initial:' || cs.id::text)),
    'recovery', (select coalesce(jsonb_agg(jsonb_build_object('record_id', r.id, 'stripe_setup_intent_id',
                   r.stripe_setup_intent_id) order by r.completed_at), '[]'::jsonb)
                 from public.recovery_sessions r
                 where r.status = 'complete' and r.applied_at is null and r.stripe_setup_intent_id is not null));
end;
$$;

-- Server only: records the card Stripe reports for a verified initial Checkout or recovery
-- (04 §8.1). The card must be attached to the client business's Customer, in the expected
-- mode. Creates or restores the authorization; a revoked one is never re-activated.
create function private.record_payment_method_lookup(p_kind text, p_record_id uuid, p_payment_method_id text,
  p_customer_id text, p_livemode boolean, p_attached boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_cs public.checkout_sessions%rowtype;
  v_rec public.recovery_sessions%rowtype;
  v_project uuid;
  v_business uuid;
  v_customer text;
  v_auth public.payment_authorizations%rowtype;
  v_acc public.agreement_acceptances%rowtype;
  v_os public.order_summaries%rowtype;
  v_deposit public.ledger_entries%rowtype;
  v_reusable boolean;
  v_id uuid;
  v_event bigint;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  if p_livemode is distinct from private.expected_livemode() then
    perform private.audit_financial('payment_method.lookup_rejected', p_kind, p_record_id::text, null,
      jsonb_build_object('reason', 'livemode_mismatch'));
    return private.fail('livemode_mismatch');
  end if;
  if p_kind = 'initial' then
    select * into v_cs from public.checkout_sessions where id = p_record_id for update;
    if not found or v_cs.payment_status is distinct from 'paid' then
      return private.fail('not_found');
    end if;
    if v_cs.payment_method_checked_at is not null then
      return jsonb_build_object('ok', true, 'already', true);
    end if;
    v_project := v_cs.project_id;
  elsif p_kind = 'recovery' then
    select * into v_rec from public.recovery_sessions where id = p_record_id for update;
    if not found or v_rec.status <> 'complete' then
      return private.fail('not_found');
    end if;
    if v_rec.applied_at is not null then
      return jsonb_build_object('ok', true, 'already', true);
    end if;
    v_project := v_rec.project_id;
  else
    return private.fail('invalid_input');
  end if;
  select p.client_business_id, c.stripe_customer_id into v_business, v_customer
    from public.projects p left join public.stripe_customers c on c.client_business_id = p.client_business_id
   where p.id = v_project;
  v_reusable := p_attached is true and p_payment_method_id ~ '^(pm|card)_[A-Za-z0-9_]{6,200}$'
                and p_customer_id is not distinct from v_customer and v_customer is not null;

  select * into v_auth from public.payment_authorizations
   where project_id = v_project and status <> 'revoked' for update;

  if p_kind = 'initial' then
    update public.checkout_sessions set payment_method_checked_at = now(), payment_method_reusable = v_reusable
     where id = v_cs.id;
    if not v_reusable then
      -- T-PAY-18: a verified deposit without a reusable card leaves the authorization not ready.
      perform private.audit_financial('payment_authorization.unavailable_at_deposit', 'checkout_session', v_cs.id::text,
        v_project, jsonb_build_object('attached', p_attached, 'customer_matches', p_customer_id is not distinct from v_customer));
      perform private.enqueue_notification('payment.method_recovery_required',
        'payment.method_recovery_required:' || v_cs.id::text || ':1', 'payment.method_recovery_required', 1, v_project, null,
        private.project_client_user_ids(v_project), '{owner}', jsonb_build_object('project_id', v_project), 'financial');
      return jsonb_build_object('ok', true, 'established', false);
    end if;
    if v_auth.id is not null or exists (select 1 from public.payment_authorizations where project_id = v_project) then
      -- An initial lookup never replaces or re-establishes an existing or revoked authorization.
      return jsonb_build_object('ok', true, 'established', false, 'reason', 'authorization_exists');
    end if;
    select * into v_acc from public.agreement_acceptances where id = v_cs.acceptance_id;
    select * into v_deposit from public.ledger_entries where dedupe_key = 'initial:' || v_cs.id::text || ':deposit';
    select * into v_os from public.order_summaries where id = v_cs.order_summary_id;
    insert into public.payment_authorizations (project_id, client_business_id, acceptance_id, agreement_version_id,
      order_summary_id, authorized_at, authorized_balance_cents, stripe_customer_id, stripe_payment_method_id,
      checkout_session_id, evidence_webhook_event_id)
    values (v_project, v_business, v_acc.id, v_acc.agreement_version_id, v_os.id, v_deposit.posted_at, v_os.balance_cents,
      v_customer, p_payment_method_id, v_cs.id, v_deposit.webhook_event_id)
    returning id into v_id;
    perform private.record_authorization_event(v_id, 'established', null, 'active', p_payment_method_id,
      v_deposit.webhook_event_id, null);
    v_event := null;
    perform private.audit_financial('payment_authorization.established', 'payment_authorization', v_id::text, v_project,
      jsonb_build_object('acceptance_id', v_acc.id, 'order_summary_id', v_os.id, 'authorized_balance_cents', v_os.balance_cents));
    return jsonb_build_object('ok', true, 'established', true, 'payment_authorization_id', v_id);
  end if;

  -- Recovery (setup mode). Saves a card; never charges.
  if not v_reusable then
    update public.recovery_sessions set applied_at = now() where id = v_rec.id;
    perform private.audit_financial('payment_method.recovery_failed', 'recovery_session', v_rec.id::text, v_project,
      jsonb_build_object('attached', p_attached));
    return jsonb_build_object('ok', true, 'applied', false);
  end if;
  if v_auth.id is not null then
    update public.payment_authorizations
       set status = 'active', stripe_payment_method_id = p_payment_method_id, recovery_session_id = v_rec.id
     where id = v_auth.id;
    perform private.record_authorization_event(v_auth.id, 'payment_method_replaced', v_auth.status, 'active',
      p_payment_method_id, v_rec.evidence_webhook_event_id, null);
    perform private.audit_financial('payment_method.replaced', 'payment_authorization', v_auth.id::text, v_project,
      jsonb_build_object('recovery_session_id', v_rec.id));
    v_id := v_auth.id;
  else
    -- No live authorization: one is (re-)established only from a deposit that was verified
    -- and, after a revocation, a newer acceptance of the current agreement (04 §8.1).
    select * into v_acc from public.agreement_acceptances where id = v_rec.acceptance_id;
    if not private.project_deposit_ever_verified(v_project) or exists (
         select 1 from public.payment_authorizations a where a.project_id = v_project and a.status = 'revoked'
           and a.revoked_at >= v_acc.accepted_at) then
      update public.recovery_sessions set applied_at = now() where id = v_rec.id;
      perform private.audit_financial('payment_method.recovery_rejected', 'recovery_session', v_rec.id::text, v_project,
        jsonb_build_object('reason', 'new_acceptance_required'));
      return jsonb_build_object('ok', true, 'applied', false, 'reason', 'new_acceptance_required');
    end if;
    select * into v_os from public.order_summaries where id = v_acc.order_summary_id;
    insert into public.payment_authorizations (project_id, client_business_id, acceptance_id, agreement_version_id,
      order_summary_id, authorized_at, authorized_balance_cents, stripe_customer_id, stripe_payment_method_id,
      recovery_session_id, evidence_webhook_event_id)
    values (v_project, v_business, v_acc.id, v_acc.agreement_version_id, v_os.id, now(), v_os.balance_cents, v_customer,
      p_payment_method_id, v_rec.id, v_rec.evidence_webhook_event_id)
    returning id into v_id;
    perform private.record_authorization_event(v_id, 'established', null, 'active', p_payment_method_id,
      v_rec.evidence_webhook_event_id, null);
    perform private.audit_financial('payment_authorization.established', 'payment_authorization', v_id::text, v_project,
      jsonb_build_object('acceptance_id', v_acc.id, 'recovery_session_id', v_rec.id));
  end if;
  update public.recovery_sessions set applied_at = now() where id = v_rec.id;
  return jsonb_build_object('ok', true, 'applied', true, 'payment_authorization_id', v_id);
end;
$$;

-- Client: setup-mode recovery (04 §8.1). The client business's member, never staff, for a
-- project whose deposit is verified and whose authorization needs a card: none yet, a card
-- unavailable, or revoked with a newer acceptance. One open session per project.
create function private.begin_payment_method_recovery(p_project_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_business uuid;
  v_auth public.payment_authorizations%rowtype;
  v_agreement record;
  v_acc public.agreement_acceptances%rowtype;
  v_open public.recovery_sessions%rowtype;
  v_attempt smallint;
  v_id uuid;
  v_req uuid;
begin
  if v_uid is null or private.staff_role_of(v_uid) is not null or not private.is_active_user()
     or not private.session_is_active() or not private.is_project_member(p_project_id) then
    return private.fail('not_found');
  end if;
  select client_business_id into v_business from public.projects where id = p_project_id and archived_at is null for update;
  if not found then
    return private.fail('not_found');
  end if;
  if not private.project_deposit_ever_verified(p_project_id)
     or not exists (select 1 from public.stripe_customers where client_business_id = v_business) then
    return private.fail('deposit_required');
  end if;
  select * into v_agreement from private.project_agreement_state(p_project_id);
  if v_agreement.state <> 'effective' then
    return private.fail('acceptance_required');
  end if;
  select * into v_acc from public.agreement_acceptances where id = v_agreement.acceptance_id;
  v_auth := private.project_payment_authorization(p_project_id);
  if v_auth.status = 'active' then
    return private.fail('authorization_active');
  end if;
  if v_auth.status = 'revoked' and v_auth.revoked_at >= v_acc.accepted_at then
    return private.fail('new_acceptance_required');
  end if;
  select * into v_open from public.recovery_sessions where project_id = p_project_id and status in ('creating', 'open');
  if found then
    return jsonb_build_object('ok', true, 'recovery_session_id', v_open.id, 'status', v_open.status,
      'checkout_url', v_open.checkout_url, 'reused', true,
      'requests', (select coalesce(jsonb_agg(r.id), '[]'::jsonb) from public.outbound_stripe_requests r
                    where r.domain_record_type = 'recovery_session' and r.domain_record_id = v_open.id and r.status = 'pending'));
  end if;
  select coalesce(max(attempt), 0) + 1 into v_attempt from public.recovery_sessions where project_id = p_project_id;
  insert into public.recovery_sessions (project_id, payment_authorization_id, acceptance_id, attempt)
  values (p_project_id, case when v_auth.status = 'payment_method_unavailable' then v_auth.id end, v_acc.id, v_attempt)
  returning id into v_id;
  -- Card only (04 §8, §8.2 items 2-4): setup mode never charges.
  v_req := private.new_outbound_request('recovery_session_create', p_project_id, 'recovery_session', v_id,
    'wpb-recovery-' || v_id::text,
    jsonb_build_object('mode', 'setup', 'allowed_payment_method_types', jsonb_build_array('card'),
      'metadata', jsonb_build_object('project_id', p_project_id, 'recovery_session_id', v_id,
        'environment', private.app_environment()),
      'setup_intent_data', jsonb_build_object('metadata', jsonb_build_object('project_id', p_project_id,
        'recovery_session_id', v_id))));
  if v_auth.id is not null and v_auth.status <> 'revoked' then
    perform private.record_authorization_event(v_auth.id, 'recovery_session_created', v_auth.status, v_auth.status,
      null, null, null);
  end if;
  perform private.audit_financial('payment_method.recovery_session_created', 'recovery_session', v_id::text, p_project_id,
    jsonb_build_object('attempt', v_attempt));
  return jsonb_build_object('ok', true, 'recovery_session_id', v_id, 'status', 'creating', 'reused', false,
    'requests', jsonb_build_array(v_req));
end;
$$;

create function private.revoke_authorization_internal(p_project_id uuid, p_source text, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_auth public.payment_authorizations%rowtype;
  v_event bigint;
begin
  select * into v_auth from public.payment_authorizations
   where project_id = p_project_id and status <> 'revoked' for update;
  if not found then
    if exists (select 1 from public.payment_authorizations where project_id = p_project_id and status = 'revoked') then
      return jsonb_build_object('ok', true, 'existing', true);
    end if;
    return private.fail('no_authorization');
  end if;
  update public.payment_authorizations
     set status = 'revoked', revoked_at = now(), revoked_by = (select auth.uid()), revocation_source = p_source,
         revocation_reason = nullif(btrim(coalesce(p_reason, '')), '')
   where id = v_auth.id;
  perform private.record_authorization_event(v_auth.id, 'revoked', v_auth.status, 'revoked', null, null, p_reason);
  perform private.halt_automatic_collection(p_project_id, 'revoked');
  perform private.audit_financial('payment_authorization.revoked', 'payment_authorization', v_auth.id::text, p_project_id,
    jsonb_build_object('source', p_source), p_reason);
  -- An Owner review item (04 §8.1): open until the Owner records the review.
  perform private.notify_owner('payment.authorization_revoked', 'payment.authorization_revoked:' || v_auth.id::text || ':1',
    p_project_id, null, jsonb_build_object('payment_consent_id', v_auth.id));
  return jsonb_build_object('ok', true, 'existing', false);
end;
$$;

-- Client revocation by the authorized signer, with fresh reauthentication (a sign-in code
-- verified within five minutes; clients have no TOTP, 03 §7) [PROPOSED mechanics].
create function private.client_reauth_is_fresh(p_max_age interval default interval '5 minutes') returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from jsonb_array_elements(coalesce((select auth.jwt()) -> 'amr', '[]'::jsonb)) e
    where e ->> 'method' in ('otp', 'magiclink', 'email')
      and jsonb_typeof(e -> 'timestamp') = 'number'
      and to_timestamp((e ->> 'timestamp')::double precision) >= now() - p_max_age);
$$;

create function private.revoke_payment_authorization(p_project_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_auth public.payment_authorizations%rowtype;
begin
  if v_uid is null or private.staff_role_of(v_uid) is not null or not private.is_active_user()
     or not private.session_is_active() or not private.is_project_member(p_project_id) then
    return private.fail('not_found');
  end if;
  v_auth := private.project_payment_authorization(p_project_id);
  if v_auth.id is null then
    return private.fail('no_authorization');
  end if;
  if not exists (select 1 from public.agreement_acceptances a where a.id = v_auth.acceptance_id and a.signer_user_id = v_uid) then
    perform private.audit_financial('payment_authorization.revocation_denied', 'payment_authorization', v_auth.id::text,
      p_project_id, jsonb_build_object('reason', 'not_signer'));
    return private.fail('signer_required');
  end if;
  if not private.client_reauth_is_fresh() then
    return private.fail('reauthentication_required');
  end if;
  return private.revoke_authorization_internal(p_project_id, 'client', p_reason);
end;
$$;

-- Owner records a revocation received outside the portal (fresh MFA and a reason).
create function private.record_payment_authorization_revocation(p_project_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  return private.revoke_authorization_internal(p_project_id, 'owner', p_reason);
end;
$$;

create function private.review_authorization_revocation(p_project_id uuid, p_note text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_auth public.payment_authorizations%rowtype;
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null then
    return private.fail('reason_required');
  end if;
  select * into v_auth from public.payment_authorizations
   where project_id = p_project_id and status = 'revoked' and revocation_reviewed_at is null
   order by revoked_at desc limit 1 for update;
  if not found then
    return private.fail('not_found');
  end if;
  update public.payment_authorizations set revocation_reviewed_at = now(), revocation_reviewed_by = (select auth.uid())
   where id = v_auth.id;
  perform private.record_authorization_event(v_auth.id, 'revocation_reviewed', 'revoked', 'revoked', null, null, p_note);
  perform private.audit_financial('payment_authorization.revocation_reviewed', 'payment_authorization', v_auth.id::text,
    p_project_id, '{}'::jsonb, p_note);
  return jsonb_build_object('ok', true);
end;
$$;
create function private.notify_owner(p_type text, p_key text, p_project_id uuid, p_event bigint, p_payload jsonb)
returns void language sql security definer set search_path = '' as $$
  select private.enqueue_notification(p_type, p_key, p_type, 1, p_project_id, p_event, '{}', '{owner}',
    coalesce(p_payload, '{}'::jsonb), 'financial');
$$;

create function private.clear_hold_internal(p_hold_id uuid, p_kind text, p_reason text, p_evidence jsonb) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_hold public.billing_holds%rowtype;
  v_event bigint;
begin
  update public.billing_holds
     set cleared_at = now(), cleared_by = (select auth.uid()), clear_kind = p_kind,
         clear_reason = p_reason, clearing_evidence = p_evidence
   where id = p_hold_id and cleared_at is null
  returning * into v_hold;
  if not found then
    return false;
  end if;
  v_event := private.emit_domain_event('payment.hold_cleared', v_hold.project_id, 'billing_hold', v_hold.id::text,
    jsonb_build_object('hold_type', v_hold.hold_type, 'clear_kind', p_kind), 'payment.hold_cleared:' || v_hold.id::text);
  perform private.audit_financial('hold.cleared', 'billing_hold', v_hold.id::text, v_hold.project_id,
    jsonb_build_object('hold_type', v_hold.hold_type, 'clear_kind', p_kind), p_reason);
  perform private.enqueue_notification('billing.hold_cleared', 'billing.hold_cleared:' || v_hold.id::text || ':1',
    'billing.hold_cleared', 1, v_hold.project_id, v_event,
    case when v_hold.hold_type = 'maintenance_payment_hold' then private.project_client_user_ids(v_hold.project_id) else '{}' end,
    '{owner}', jsonb_build_object('hold_id', v_hold.id), 'financial');
  return true;
end;
$$;

create function private.place_hold_internal(p_project_id uuid, p_type public.hold_type, p_source text,
  p_source_ref text, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_event bigint;
begin
  insert into public.billing_holds (project_id, hold_type, trigger_source, source_ref, placed_by, reason)
  values (p_project_id, p_type, p_source, p_source_ref,
          case when p_source = 'owner' then (select auth.uid()) end, p_reason)
  on conflict do nothing
  returning id into v_id;
  if v_id is null then
    return null;
  end if;
  v_event := private.emit_domain_event('payment.hold_placed', p_project_id, 'billing_hold', v_id::text,
    jsonb_build_object('hold_type', p_type), 'payment.hold_placed:' || v_id::text);
  perform private.audit_financial('hold.placed', 'billing_hold', v_id::text, p_project_id,
    jsonb_build_object('hold_type', p_type, 'trigger_source', p_source), p_reason);
  perform private.enqueue_notification('billing.hold_placed', 'billing.hold_placed:' || v_id::text || ':1',
    'billing.hold_placed', 1, p_project_id, v_event,
    case when p_type = 'maintenance_payment_hold' then private.project_client_user_ids(p_project_id) else '{}' end,
    '{owner}', jsonb_build_object('hold_id', v_id), 'financial');
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Outbound requests (04 §17 #2) and the initial Checkout (04 §8)
-- ---------------------------------------------------------------------------
create function private.new_outbound_request(p_purpose public.outbound_request_purpose, p_project_id uuid,
  p_record_type text, p_record_id uuid, p_key_base text, p_params jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_attempt smallint;
  v_id uuid;
begin
  select coalesce(max(attempt), 0) + 1 into v_attempt from public.outbound_stripe_requests
   where domain_record_type = p_record_type and domain_record_id = p_record_id;
  insert into public.outbound_stripe_requests (purpose, project_id, domain_record_type, domain_record_id,
    attempt, idempotency_key, request_params)
  values (p_purpose, p_project_id, p_record_type, p_record_id, v_attempt,
    p_key_base || '-a' || v_attempt, p_params)
  returning id into v_id;
  return v_id;
end;
$$;

-- 03 §4 "Start initial Checkout": client members only. Price IDs come from the order
-- summary snapshot (never client input) and are re-verified against the catalog
-- (T-PAY-12). Concurrent and double-click requests return the same session (T-ARC-05).
create function private.begin_initial_checkout(p_project_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_agreement record;
  v_os public.order_summaries%rowtype;
  v_business uuid;
  v_prices record;
  v_open public.checkout_sessions%rowtype;
  v_customer text;
  v_customer_req uuid;
  v_requests uuid[] := '{}';
  v_attempt smallint;
  v_cs_id uuid;
begin
  if v_uid is null or private.staff_role_of(v_uid) is not null or not private.is_active_user()
     or not private.session_is_active() or not private.is_project_member(p_project_id) then
    return private.fail('not_found');
  end if;
  -- Serialize per project (double click, concurrent tabs).
  select client_business_id into v_business from public.projects where id = p_project_id and archived_at is null for update;
  if not found then
    return private.fail('not_found');
  end if;
  select * into v_agreement from private.project_agreement_state(p_project_id);
  if v_agreement.state = 'effective' or private.project_deposit_ever_verified(p_project_id) then
    return private.fail('deposit_already_verified');
  end if;
  if v_agreement.state <> 'accepted_pending_payment' then
    return private.fail('acceptance_required');
  end if;
  select * into v_os from public.order_summaries where id = v_agreement.order_summary_id;
  select * into v_prices from private.verified_package_prices(v_os.package_key);
  if not found or v_prices.deposit_price_id <> v_os.deposit_price_id
     or v_prices.maintenance_price_id <> v_os.maintenance_price_id or v_os.catalog_environment <> private.stripe_mode() then
    perform private.audit_financial('checkout.price_verification_failed', 'order_summary', v_os.id::text, p_project_id);
    return private.fail('catalog_mismatch');
  end if;

  select * into v_open from public.checkout_sessions
   where project_id = p_project_id and kind = 'initial' and status in ('creating', 'open');
  if found then
    if v_open.order_summary_id = v_os.id then
      select coalesce(array_agg(r.id), '{}') into v_requests from public.outbound_stripe_requests r
       where r.status = 'pending' and ((r.domain_record_type = 'checkout_session' and r.domain_record_id = v_open.id)
          or (r.domain_record_type = 'client_business' and r.domain_record_id = v_business));
      return jsonb_build_object('ok', true, 'checkout_session_id', v_open.id, 'status', v_open.status,
        'checkout_url', v_open.checkout_url, 'reused', true, 'requests', to_jsonb(v_requests));
    end if;
    return private.fail('checkout_in_progress');
  end if;

  select stripe_customer_id into v_customer from public.stripe_customers where client_business_id = v_business;
  if v_customer is null then
    select id into v_customer_req from public.outbound_stripe_requests
     where domain_record_type = 'client_business' and domain_record_id = v_business and status in ('pending', 'ambiguous');
    if v_customer_req is not null and exists (select 1 from public.outbound_stripe_requests where id = v_customer_req and status = 'ambiguous') then
      return private.fail('reconciliation_required');
    end if;
    if v_customer_req is null then
      v_customer_req := private.new_outbound_request('customer_create', p_project_id, 'client_business', v_business,
        'wpb-customer-' || v_business::text,
        jsonb_build_object('name', v_os.business_legal_name, 'metadata',
          jsonb_build_object('client_business_id', v_business, 'environment', private.app_environment())));
    end if;
    v_requests := v_requests || v_customer_req;
  end if;

  select coalesce(max(attempt), 0) + 1 into v_attempt from public.checkout_sessions where order_summary_id = v_os.id;
  insert into public.checkout_sessions (project_id, order_summary_id, acceptance_id, attempt)
  values (p_project_id, v_os.id, v_agreement.acceptance_id, v_attempt)
  returning id into v_cs_id;
  -- 04 §8, OI-47, OI-74, T-BIL-20, T-PAY-24: card only; exactly the standard deposit and maintenance prices, quantity 1,
  -- subscription mode, no discount, coupon, promotion code or credit, no automatic tax
  -- (DEP-04). The server adds only the customer and the return URLs.
  v_requests := v_requests || private.new_outbound_request('checkout_session_create', p_project_id, 'checkout_session',
    v_cs_id, 'wpb-checkout-' || v_os.id::text || '-c' || v_attempt,
    jsonb_build_object(
      'mode', 'subscription',
      -- OI-74 (04 §8, §8.2 item 2): card only; a payment method is always collected.
      'allowed_payment_method_types', jsonb_build_array('card'),
      'payment_method_collection', 'always',
      'line_items', jsonb_build_array(
        jsonb_build_object('price', v_os.deposit_price_id, 'quantity', 1),
        jsonb_build_object('price', v_os.maintenance_price_id, 'quantity', 1)),
      'discounts', '[]'::jsonb,
      'allow_promotion_codes', false,
      'automatic_tax', jsonb_build_object('enabled', false),
      'expected_amount_total', v_os.deposit_cents + v_os.maintenance_monthly_cents,
      'metadata', jsonb_build_object('project_id', p_project_id, 'order_summary_id', v_os.id,
        'acceptance_id', v_agreement.acceptance_id, 'checkout_record_id', v_cs_id,
        'environment', private.app_environment()),
      'subscription_data', jsonb_build_object('metadata', jsonb_build_object('project_id', p_project_id,
        'order_summary_id', v_os.id, 'checkout_record_id', v_cs_id))));
  perform private.audit_financial('checkout.session_requested', 'checkout_session', v_cs_id::text, p_project_id,
    jsonb_build_object('order_summary_id', v_os.id, 'attempt', v_attempt));
  return jsonb_build_object('ok', true, 'checkout_session_id', v_cs_id, 'status', 'creating', 'reused', false,
    'requests', to_jsonb(v_requests));
end;
$$;

-- Server (secret key) only: atomically claims one pending request and returns its exact
-- parameters, with the customer resolved. Exactly one executor can ever claim a request,
-- so concurrent workers never send the same create twice (04 §6.2: idempotency keys are
-- never the only duplicate guard). The server never builds Stripe parameters from client input.
create function private.outbound_request_for_execution(p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
  v_customer text;
  v_fbi public.final_balance_invoices%rowtype;
  v_auth public.payment_authorizations%rowtype;
  v_next uuid;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id;
  if not found or v_req.status <> 'pending' then
    return private.fail('not_pending');
  end if;
  -- 04 §10, §8.1 (OI-74): an automatic charge is sent only while the authorization is still
  -- active with the same card. The authorization row lock serializes this check with
  -- revocation and detachment; a request that no longer qualifies is replaced, before it is
  -- ever sent, by a hosted-only attempt on the same single invoice record.
  if v_req.purpose = 'final_balance_invoice_create' then
    select * into v_fbi from public.final_balance_invoices where id = v_req.domain_record_id for update;
    select * into v_auth from public.payment_authorizations
     where project_id = v_req.project_id and status <> 'revoked' for update;
    if v_req.request_params -> 'auto_advance' = 'true'::jsonb and (
         v_fbi.collection_mode <> 'automatic' or v_auth.id is distinct from v_fbi.payment_authorization_id
         or v_auth.status is distinct from 'active'
         or v_auth.stripe_payment_method_id is distinct from (v_req.request_params ->> 'default_payment_method')) then
      update public.outbound_stripe_requests set status = 'failed', error_code = 'authorization_changed', completed_at = now()
       where id = v_req.id and status = 'pending' and claimed_at is null;
      if not found then
        return private.fail('already_claimed');
      end if;
      if v_fbi.collection_mode = 'automatic' then
        update public.final_balance_invoices set collection_mode = 'hosted_only', automatic_stop_required = true,
          halt_cause = coalesce(halt_cause, 'authorization_changed')
         where id = v_fbi.id returning * into v_fbi;
      end if;
      v_next := private.new_outbound_request('final_balance_invoice_create', v_fbi.project_id, 'final_balance_invoice',
        v_fbi.id, 'wpb-final-balance-' || v_fbi.order_summary_id::text || '-' || v_fbi.approval_id::text,
        private.final_balance_invoice_params(v_fbi, 'hosted_only'));
      perform private.audit_financial('balance.automatic_collection_superseded', 'final_balance_invoice', v_fbi.id::text,
        v_fbi.project_id, jsonb_build_object('superseded_request_id', v_req.id, 'hosted_request_id', v_next));
      return jsonb_build_object('ok', false, 'error', 'superseded', 'next_request_id', v_next);
    end if;
  end if;
  if v_req.purpose = 'final_balance_invoice_disable_auto' then
    select * into v_fbi from public.final_balance_invoices where id = v_req.domain_record_id;
    if v_fbi.status = 'paid' then
      update public.outbound_stripe_requests set status = 'failed', error_code = 'already_paid', completed_at = now()
       where id = v_req.id and status = 'pending' and claimed_at is null;
      return private.fail('not_needed');
    end if;
  end if;
  if v_req.purpose in ('checkout_session_create', 'final_balance_invoice_create', 'recovery_session_create') then
    select c.stripe_customer_id into v_customer from public.stripe_customers c
      join public.projects p on p.client_business_id = c.client_business_id where p.id = v_req.project_id;
    if v_customer is null then
      return private.fail('customer_missing');
    end if;
  end if;
  update public.outbound_stripe_requests set claimed_at = now()
   where id = v_req.id and status = 'pending' and claimed_at is null;
  if not found then
    return private.fail('already_claimed');
  end if;
  return jsonb_build_object('ok', true, 'id', v_req.id, 'purpose', v_req.purpose,
    'idempotency_key', v_req.idempotency_key, 'params', v_req.request_params, 'customer', v_customer,
    'expected_livemode', private.expected_livemode());
end;
$$;

-- Server (secret key) only: records the outcome of a Stripe create and applies its domain
-- effect in the same transaction. A livemode mismatch aborts (CLAUDE.md §4).
create function private.record_outbound_result(p_request_id uuid, p_outcome text, p_stripe_object_id text,
  p_livemode boolean, p_http_status integer, p_error_code text, p_details jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
  v_fbi public.final_balance_invoices%rowtype;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id for update;
  if not found or v_req.status <> 'pending' then
    return private.fail('not_pending');
  end if;
  if p_outcome not in ('succeeded', 'failed', 'ambiguous') or (p_outcome = 'succeeded' and p_stripe_object_id is null) then
    return private.fail('invalid_input');
  end if;
  if p_outcome = 'succeeded' and p_livemode is distinct from private.expected_livemode() then
    update public.outbound_stripe_requests set status = 'ambiguous', livemode = p_livemode, http_status = p_http_status,
      error_code = 'livemode_mismatch', completed_at = now() where id = v_req.id;
    perform private.audit_financial('outbound.livemode_mismatch', 'outbound_stripe_request', v_req.id::text, v_req.project_id);
    perform private.notify_owner('outbound.livemode_mismatch', 'outbound.livemode_mismatch:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id));
    return private.fail('livemode_mismatch');
  end if;

  update public.outbound_stripe_requests
     set status = p_outcome::public.outbound_request_status, stripe_object_id = p_stripe_object_id,
         livemode = p_livemode, http_status = p_http_status, error_code = left(p_error_code, 100), completed_at = now()
   where id = v_req.id;

  if p_outcome = 'succeeded' then
    perform private.apply_outbound_success(v_req, p_stripe_object_id, p_livemode, coalesce(p_details, '{}'::jsonb));
  elsif p_outcome = 'failed' then
    if v_req.purpose = 'checkout_session_create' then
      update public.checkout_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
    elsif v_req.purpose = 'recovery_session_create' then
      update public.recovery_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
    elsif v_req.purpose = 'final_balance_invoice_disable_auto' then
      perform private.notify_owner('payment.automatic_stop_failed', 'payment.automatic_stop_failed:' || v_req.id::text || ':1',
        v_req.project_id, null, jsonb_build_object('final_balance_invoice_id', v_req.domain_record_id));
    elsif v_req.purpose = 'final_balance_invoice_create' then
      update public.final_balance_invoices set status = 'creation_failed'
       where id = v_req.domain_record_id and status = 'creating' returning * into v_fbi;
      perform private.notify_owner('payment.final_invoice_creation_failed',
        'payment.final_invoice_creation_failed:' || v_req.id::text || ':1', v_req.project_id, null,
        jsonb_build_object('final_balance_invoice_id', v_req.domain_record_id));
    end if;
    perform private.audit_financial('outbound.request_failed', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
      jsonb_build_object('purpose', v_req.purpose, 'http_status', p_http_status));
  else
    perform private.audit_financial('outbound.request_ambiguous', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
      jsonb_build_object('purpose', v_req.purpose));
    perform private.notify_owner('outbound.request_ambiguous', 'outbound.request_ambiguous:' || v_req.id::text || ':1',
      v_req.project_id, null, jsonb_build_object('request_id', v_req.id));
  end if;
  return jsonb_build_object('ok', true, 'status', p_outcome);
end;
$$;

create function private.apply_outbound_success(p_req public.outbound_stripe_requests, p_object_id text,
  p_livemode boolean, p_details jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_business uuid;
  v_event bigint;
  v_fbi public.final_balance_invoices%rowtype;
begin
  if p_req.purpose = 'customer_create' then
    insert into public.stripe_customers (client_business_id, stripe_customer_id, livemode)
    values (p_req.domain_record_id, p_object_id, p_livemode) on conflict (client_business_id) do nothing;
  elsif p_req.purpose = 'checkout_session_create' then
    update public.checkout_sessions
       set stripe_checkout_session_id = p_object_id,
           checkout_url = coalesce(checkout_url, p_details ->> 'url'),
           expires_at = coalesce(expires_at, private.unix_ts(p_details -> 'expires_at')),
           status = case when status = 'creating' then 'open'::public.checkout_session_status else status end
     where id = p_req.domain_record_id;
    perform private.audit_financial('checkout.session_created', 'checkout_session', p_req.domain_record_id::text,
      p_req.project_id, jsonb_build_object('stripe_checkout_session_id', p_object_id));
  elsif p_req.purpose = 'final_balance_invoice_create' then
    update public.final_balance_invoices
       set stripe_invoice_id = p_object_id,
           hosted_invoice_url = coalesce(hosted_invoice_url, p_details ->> 'hosted_invoice_url'),
           status = case when status = 'creating' then 'open'::public.final_balance_invoice_status else status end,
           opened_at = coalesce(opened_at, now())
     where id = p_req.domain_record_id
    returning * into v_fbi;
    v_event := private.emit_domain_event('payment.balance_invoice_opened', v_fbi.project_id, 'final_balance_invoice',
      v_fbi.id::text, jsonb_build_object('order_summary_id', v_fbi.order_summary_id),
      'payment.balance_invoice_opened:' || v_fbi.id::text);
    perform private.audit_financial('balance.charge_attempted', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id,
      jsonb_build_object('collection_method', 'charge_automatically',
        'auto_advance', p_req.request_params -> 'auto_advance', 'stripe_invoice_id', p_object_id,
        'approval_id', v_fbi.approval_id, 'amount_cents', v_fbi.amount_cents));
    -- Revocation or detachment arrived while this automatic create was in flight: stop the
    -- scheduled automatic attempt on the invoice that now exists.
    if p_req.request_params -> 'auto_advance' = 'true'::jsonb and v_fbi.automatic_stop_required
       and not exists (select 1 from public.outbound_stripe_requests where domain_record_type = 'final_balance_invoice'
                         and domain_record_id = v_fbi.id and status in ('pending', 'ambiguous')) then
      perform private.new_outbound_request('final_balance_invoice_disable_auto', v_fbi.project_id, 'final_balance_invoice',
        v_fbi.id, 'wpb-final-balance-stop-' || v_fbi.id::text,
        jsonb_build_object('invoice', p_object_id, 'auto_advance', false));
    end if;
    perform private.enqueue_notification('payment.final_invoice_ready', 'payment.final_invoice_ready:' || v_fbi.id::text || ':1',
      'payment.final_invoice_ready', 1, v_fbi.project_id, v_event, private.project_client_user_ids(v_fbi.project_id),
      '{}', jsonb_build_object('project_id', v_fbi.project_id), 'general');
  elsif p_req.purpose = 'recovery_session_create' then
    update public.recovery_sessions
       set stripe_checkout_session_id = p_object_id, checkout_url = coalesce(checkout_url, p_details ->> 'url'),
           status = case when status = 'creating' then 'open'::public.checkout_session_status else status end
     where id = p_req.domain_record_id;
  elsif p_req.purpose = 'final_balance_invoice_disable_auto' then
    perform private.audit_financial('balance.automatic_collection_disabled', 'final_balance_invoice',
      p_req.domain_record_id::text, p_req.project_id, jsonb_build_object('stripe_invoice_id', p_object_id));
  end if;
end;
$$;

-- Server only: a request claimed by an executor that never recorded a result (a crash
-- mid-call) becomes ambiguous and is never retried automatically (04 §6.4). An unclaimed
-- request was never sent to Stripe, so it stays pending and safe to execute.
create function private.mark_stale_outbound_requests() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_count integer;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  with stale as (
    update public.outbound_stripe_requests set status = 'ambiguous', error_code = 'stale_pending', completed_at = now()
     where status = 'pending' and claimed_at is not null and claimed_at < now() - interval '10 minutes'
     returning id, project_id)
  select count(*) into v_count from stale;
  return v_count;
end;
$$;

-- Owner, fresh MFA: reconcile an ambiguous create against Stripe's actual records (04 §6.4).
create function private.reconcile_outbound_request(p_request_id uuid, p_found boolean, p_stripe_object_id text, p_note text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_req public.outbound_stripe_requests%rowtype;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null or p_found is null then
    return private.fail('reason_required');
  end if;
  select * into v_req from public.outbound_stripe_requests where id = p_request_id for update;
  -- B1: a failed automatic-collection stop (other than already_paid) is reconciled the same
  -- way: found = Stripe shows automatic collection off on that invoice.
  if not found or not (v_req.status = 'ambiguous'
       or (v_req.status = 'failed' and v_req.purpose = 'final_balance_invoice_disable_auto'
           and coalesce(v_req.error_code, '') <> 'already_paid')) then
    return private.fail('not_ambiguous');
  end if;
  if p_found and coalesce(v_req.error_code, '') = 'livemode_mismatch' then
    return private.fail('livemode_mismatch');
  end if;
  update public.outbound_stripe_requests
     set status = case when p_found then 'reconciled_present'::public.outbound_request_status else 'reconciled_absent'::public.outbound_request_status end,
         stripe_object_id = case when p_found then p_stripe_object_id else stripe_object_id end,
         reconciled_by = (select auth.uid()), reconciled_at = now(), reconcile_note = btrim(p_note)
   where id = v_req.id;
  if p_found then
    perform private.apply_outbound_success(v_req, p_stripe_object_id, private.expected_livemode(), '{}'::jsonb);
  elsif v_req.purpose = 'checkout_session_create' then
    update public.checkout_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
  elsif v_req.purpose = 'final_balance_invoice_create' then
    update public.final_balance_invoices set status = 'creation_failed' where id = v_req.domain_record_id and status = 'creating';
  elsif v_req.purpose = 'recovery_session_create' then
    update public.recovery_sessions set status = 'failed' where id = v_req.domain_record_id and status = 'creating';
  end if;
  perform private.audit_financial('outbound.request_reconciled', 'outbound_stripe_request', v_req.id::text, v_req.project_id,
    jsonb_build_object('found', p_found, 'gates', private.financial_gate_recheck(v_req.project_id)), p_note);
  return jsonb_build_object('ok', true, 'gates', private.financial_gate_recheck(v_req.project_id));
end;
$$;

-- Owner, fresh MFA: a new attempt for a final-balance invoice whose creation failed
-- definitively or was reconciled absent. Never while one is pending or ambiguous.
create function private.retry_final_balance_invoice(p_final_balance_invoice_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_req uuid;
  v_os public.order_summaries%rowtype;
  v_prices record;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  select * into v_fbi from public.final_balance_invoices where id = p_final_balance_invoice_id for update;
  if not found or v_fbi.status <> 'creation_failed' then
    return private.fail('not_retryable');
  end if;
  select * into v_os from public.order_summaries where id = v_fbi.order_summary_id;
  select * into v_prices from private.verified_package_prices(v_os.package_key);
  if not found or v_prices.balance_price_id <> v_fbi.balance_price_id then
    return private.fail('catalog_mismatch');
  end if;
  update public.final_balance_invoices set status = 'creating' where id = v_fbi.id;
  v_req := private.new_outbound_request('final_balance_invoice_create', v_fbi.project_id, 'final_balance_invoice', v_fbi.id,
    'wpb-final-balance-' || v_fbi.order_summary_id::text || '-' || v_fbi.approval_id::text,
    private.final_balance_invoice_params(v_fbi, v_fbi.collection_mode));
  perform private.audit_financial('outbound.request_retried', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id,
    '{}'::jsonb, p_reason);
  return jsonb_build_object('ok', true, 'request_id', v_req);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Durable webhook ingestion (04 §11, §17 #4)
-- ---------------------------------------------------------------------------
-- Drops card, payment-method, address and contact details at any depth before storage
-- (CLAUDE.md §3: never store card data; 07 §5 data minimization).
create function private.sanitize_stripe_payload(p_value jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_result jsonb;
  v_key text;
  v_item jsonb;
begin
  if jsonb_typeof(p_value) = 'object' then
    v_result := '{}'::jsonb;
    for v_key, v_item in select * from jsonb_each(p_value) loop
      if v_key not in ('payment_method_details', 'card', 'billing_details', 'customer_details', 'customer_email',
                       'customer_name', 'customer_address', 'customer_phone', 'customer_shipping', 'shipping',
                       'shipping_details', 'source', 'sources', 'payment_method', 'payment_method_options',
                       'collected_information', 'evidence', 'client_secret', 'receipt_email') then
        v_result := v_result || jsonb_build_object(v_key, private.sanitize_stripe_payload(v_item));
      end if;
    end loop;
    return v_result;
  elsif jsonb_typeof(p_value) = 'array' then
    select coalesce(jsonb_agg(private.sanitize_stripe_payload(e) order by o), '[]'::jsonb) into v_result
    from jsonb_array_elements(p_value) with ordinality t(e, o);
    return v_result;
  end if;
  return p_value;
end;
$$;

-- Server (secret key) only, after it verified the Stripe signature on the raw body. Returns
-- only after the event row is durably stored; a duplicate is a no-op (T-PAY-05, T-ARC-01).
create function private.ingest_stripe_event(p_event jsonb, p_raw_body_sha256 text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_livemode jsonb := p_event -> 'livemode';
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  if jsonb_typeof(p_event) <> 'object' or jsonb_typeof(p_event -> 'data' -> 'object') <> 'object'
     or coalesce(p_event ->> 'id', '') !~ '^evt_[A-Za-z0-9_]{6,200}$' or jsonb_typeof(p_event -> 'created') <> 'number' then
    perform private.audit_financial('webhook.rejected', 'webhook_event', left(p_event ->> 'id', 200), null,
      jsonb_build_object('reason', 'malformed'));
    return private.fail('malformed_event');
  end if;
  -- 04 §11 rule 5 and §6.3 fail-closed: a missing, null or non-boolean livemode is rejected.
  if jsonb_typeof(v_livemode) <> 'boolean' or (v_livemode #>> '{}')::boolean is distinct from private.expected_livemode() then
    perform private.audit_financial('webhook.rejected', 'webhook_event', p_event ->> 'id', null,
      jsonb_build_object('reason', 'livemode_mismatch', 'event_type', left(p_event ->> 'type', 100)));
    perform private.notify_owner('webhook.livemode_mismatch', 'webhook.livemode_mismatch:' || (p_event ->> 'id') || ':1',
      null, null, jsonb_build_object('stripe_event_id', p_event ->> 'id'));
    return private.fail('livemode_mismatch');
  end if;
  insert into public.webhook_events (stripe_event_id, event_type, api_version, livemode, stripe_created_at,
    object_type, object_id, payload, raw_body_sha256, signature_verified)
  values (p_event ->> 'id', p_event ->> 'type', left(p_event ->> 'api_version', 40), (v_livemode #>> '{}')::boolean,
    private.unix_ts(p_event -> 'created'), left(p_event #>> '{data,object,object}', 60),
    left(p_event #>> '{data,object,id}', 200), private.sanitize_stripe_payload(p_event), p_raw_body_sha256, true)
  on conflict (stripe_event_id) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.webhook_events where stripe_event_id = p_event ->> 'id';
    return jsonb_build_object('ok', true, 'webhook_event_id', v_id, 'duplicate', true);
  end if;
  perform private.audit_financial('webhook.received', 'webhook_event', v_id::text, null,
    jsonb_build_object('stripe_event_id', p_event ->> 'id', 'event_type', p_event ->> 'type'));
  return jsonb_build_object('ok', true, 'webhook_event_id', v_id, 'duplicate', false);
exception
  when check_violation or invalid_text_representation then
    perform private.audit_financial('webhook.rejected', 'webhook_event', left(p_event ->> 'id', 200), null,
      jsonb_build_object('reason', 'invalid'));
    return private.fail('malformed_event');
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. Event handlers. Each returns 'processed', 'ignored', 'deferred' (retried later, for
--    order independence), or 'quarantined:<reason>' (Owner review; never verifies payment).
-- ---------------------------------------------------------------------------
create function private.handle_checkout_session(e public.webhook_events, s jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_cs public.checkout_sessions%rowtype;
  v_os public.order_summaries%rowtype;
  v_customer text;
  v_paid boolean;
  v_newer boolean;
begin
  if s ->> 'mode' = 'setup' then
    return private.handle_recovery_session(e, s);
  end if;
  -- Card only (OI-74): delayed payment methods are excluded, so these are never expected.
  if e.event_type in ('checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed') then
    return 'quarantined:async_payment_not_expected';
  end if;
  select * into v_cs from public.checkout_sessions
   where stripe_checkout_session_id = s ->> 'id' or id = private.try_uuid(s #>> '{metadata,checkout_record_id}')
   order by (stripe_checkout_session_id = s ->> 'id') desc nulls last limit 1 for update;
  if not found then
    return 'quarantined:unknown_checkout_session';
  end if;
  select * into v_os from public.order_summaries where id = v_cs.order_summary_id;
  if (s #>> '{metadata,project_id}') is distinct from v_cs.project_id::text
     or (s #>> '{metadata,order_summary_id}') is distinct from v_cs.order_summary_id::text
     or (s #>> '{metadata,checkout_record_id}') is distinct from v_cs.id::text
     or (v_cs.stripe_checkout_session_id is not null and v_cs.stripe_checkout_session_id <> s ->> 'id') then
    return 'quarantined:metadata_mismatch';
  end if;
  if s ->> 'mode' is distinct from 'subscription' or s ->> 'currency' is distinct from 'usd' then
    return 'quarantined:mode_or_currency_mismatch';
  end if;
  if (s ->> 'amount_total')::bigint is distinct from (v_os.deposit_cents + v_os.maintenance_monthly_cents)::bigint then
    return 'quarantined:amount_mismatch';
  end if;
  if coalesce((s #>> '{total_details,amount_discount}')::bigint, 0) <> 0
     or coalesce((s #>> '{total_details,amount_tax}')::bigint, 0) <> 0 then
    return 'quarantined:discount_or_tax_present';
  end if;
  select c.stripe_customer_id into v_customer from public.stripe_customers c
    join public.projects p on p.client_business_id = c.client_business_id where p.id = v_cs.project_id;
  if v_customer is not null and (s ->> 'customer') is distinct from v_customer then
    return 'quarantined:customer_mismatch';
  end if;
  update public.webhook_events set project_id = v_cs.project_id where id = e.id;

  v_newer := v_cs.last_event_created is null or e.stripe_created_at >= v_cs.last_event_created;
  v_paid := e.event_type = 'checkout.session.completed' and s ->> 'payment_status' = 'paid';
  update public.checkout_sessions
     set stripe_checkout_session_id = coalesce(stripe_checkout_session_id, s ->> 'id'),
         stripe_customer_id = coalesce(stripe_customer_id, s ->> 'customer'),
         stripe_subscription_id = coalesce(stripe_subscription_id, s ->> 'subscription'),
         stripe_invoice_id = coalesce(stripe_invoice_id, s ->> 'invoice'),
         amount_total_cents = (s ->> 'amount_total')::bigint,
         status = case when status in ('creating', 'open') then 'complete'::public.checkout_session_status else status end,
         completed_at = coalesce(completed_at, now()),
         payment_status = case
           when payment_status = 'paid' or v_paid then 'paid'
           when not v_newer then payment_status
           else coalesce(s ->> 'payment_status', payment_status) end,
         last_event_created = greatest(coalesce(last_event_created, e.stripe_created_at), e.stripe_created_at)
   where id = v_cs.id;
  perform private.audit_financial('checkout.session_completed', 'checkout_session', v_cs.id::text, v_cs.project_id,
    jsonb_build_object('event_type', e.event_type, 'payment_status', s ->> 'payment_status'));
  if v_paid then
    perform private.mark_deposit_verified(v_cs.id, e.id, s ->> 'invoice');
  end if;
  return 'processed';
end;
$$;

-- Setup-mode recovery completion (04 §8.1). The replacement card is applied only after the
-- server re-reads the SetupIntent from Stripe (record_payment_method_lookup, invariant 5).
create function private.handle_recovery_session(e public.webhook_events, s jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_rec public.recovery_sessions%rowtype;
  v_customer text;
begin
  select * into v_rec from public.recovery_sessions
   where stripe_checkout_session_id = s ->> 'id' or id = private.try_uuid(s #>> '{metadata,recovery_session_id}')
   order by (stripe_checkout_session_id = s ->> 'id') desc nulls last limit 1 for update;
  if not found then
    return 'quarantined:unknown_recovery_session';
  end if;
  update public.webhook_events set project_id = v_rec.project_id where id = e.id;
  select c.stripe_customer_id into v_customer from public.stripe_customers c
    join public.projects p on p.client_business_id = c.client_business_id where p.id = v_rec.project_id;
  if (s #>> '{metadata,project_id}') is distinct from v_rec.project_id::text
     or (s #>> '{metadata,recovery_session_id}') is distinct from v_rec.id::text
     or (v_rec.stripe_checkout_session_id is not null and v_rec.stripe_checkout_session_id <> s ->> 'id')
     or (s ->> 'customer') is distinct from v_customer then
    return 'quarantined:metadata_mismatch';
  end if;
  -- Setup mode never charges: a recovery session that reports an amount is not ours.
  if coalesce((s ->> 'amount_total')::bigint, 0) <> 0 then
    return 'quarantined:recovery_session_charged';
  end if;
  if e.event_type = 'checkout.session.completed' and v_rec.status in ('creating', 'open') then
    update public.recovery_sessions
       set status = 'complete', completed_at = now(),
           stripe_checkout_session_id = coalesce(stripe_checkout_session_id, s ->> 'id'),
           stripe_setup_intent_id = coalesce(stripe_setup_intent_id,
             case when jsonb_typeof(s -> 'setup_intent') = 'string' then s ->> 'setup_intent' end),
           evidence_webhook_event_id = coalesce(evidence_webhook_event_id, e.id)
     where id = v_rec.id;
  end if;
  return 'processed';
end;
$$;

create function private.handle_setup_intent(e public.webhook_events, si jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_rec public.recovery_sessions%rowtype;
begin
  select * into v_rec from public.recovery_sessions
   where stripe_setup_intent_id = si ->> 'id' or id = private.try_uuid(si #>> '{metadata,recovery_session_id}')
   order by (stripe_setup_intent_id = si ->> 'id') desc nulls last limit 1 for update;
  if not found then
    return 'ignored';
  end if;
  update public.webhook_events set project_id = v_rec.project_id where id = e.id;
  if (si #>> '{metadata,project_id}') is distinct from v_rec.project_id::text
     or (v_rec.stripe_setup_intent_id is not null and v_rec.stripe_setup_intent_id <> si ->> 'id') then
    return 'quarantined:metadata_mismatch';
  end if;
  if e.event_type = 'setup_intent.succeeded' and v_rec.status in ('creating', 'open') then
    update public.recovery_sessions
       set status = 'complete', completed_at = now(), stripe_setup_intent_id = coalesce(stripe_setup_intent_id, si ->> 'id'),
           evidence_webhook_event_id = coalesce(evidence_webhook_event_id, e.id)
     where id = v_rec.id;
  elsif e.event_type = 'setup_intent.setup_failed' then
    -- The session stays open for another try; the authorization stays unavailable.
    perform private.audit_financial('payment_method.recovery_attempt_failed', 'recovery_session', v_rec.id::text, v_rec.project_id);
  end if;
  return 'processed';
end;
$$;

-- payment_method.detached / automatically_updated (04 §8.2 items 7-8). Only the card the
-- live authorization names is affected, so late events about a replaced card do nothing,
-- and a revoked authorization never changes (T-PAY-25).
create function private.handle_payment_method(e public.webhook_events, pm jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_auth public.payment_authorizations%rowtype;
begin
  select * into v_auth from public.payment_authorizations
   where stripe_payment_method_id = pm ->> 'id' and status <> 'revoked' for update;
  if not found then
    return 'ignored';
  end if;
  update public.webhook_events set project_id = v_auth.project_id where id = e.id;
  if e.event_type = 'payment_method.automatically_updated' then
    perform private.record_authorization_event(v_auth.id, 'automatically_updated', v_auth.status, v_auth.status,
      pm ->> 'id', e.id, null);
    return 'processed';
  end if;
  if v_auth.status = 'active' then
    update public.payment_authorizations set status = 'payment_method_unavailable' where id = v_auth.id;
    perform private.record_authorization_event(v_auth.id, 'unavailable', 'active', 'payment_method_unavailable',
      pm ->> 'id', e.id, 'payment_method.detached');
    perform private.halt_automatic_collection(v_auth.project_id, 'payment_method_detached');
    perform private.audit_financial('payment_authorization.unavailable', 'payment_authorization', v_auth.id::text,
      v_auth.project_id, jsonb_build_object('cause', 'payment_method.detached'));
    perform private.enqueue_notification('payment.method_recovery_required',
      'payment.method_recovery_required:' || e.stripe_event_id || ':1', 'payment.method_recovery_required', 1,
      v_auth.project_id, null, private.project_client_user_ids(v_auth.project_id), '{owner}',
      jsonb_build_object('project_id', v_auth.project_id), 'financial');
  end if;
  return 'processed';
end;
$$;

create function private.handle_checkout_expired(e public.webhook_events, s jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_cs public.checkout_sessions%rowtype;
begin
  if s ->> 'mode' = 'setup' then
    update public.recovery_sessions set status = 'expired',
      stripe_checkout_session_id = coalesce(stripe_checkout_session_id, s ->> 'id')
     where (stripe_checkout_session_id = s ->> 'id' or id = private.try_uuid(s #>> '{metadata,recovery_session_id}'))
       and status in ('creating', 'open');
    return 'processed';
  end if;
  select * into v_cs from public.checkout_sessions
   where stripe_checkout_session_id = s ->> 'id' or id = private.try_uuid(s #>> '{metadata,checkout_record_id}')
   limit 1 for update;
  if not found then
    return 'quarantined:unknown_checkout_session';
  end if;
  update public.webhook_events set project_id = v_cs.project_id where id = e.id;
  if v_cs.status in ('creating', 'open') then
    update public.checkout_sessions set status = 'expired',
      stripe_checkout_session_id = coalesce(stripe_checkout_session_id, s ->> 'id') where id = v_cs.id;
  end if;
  return 'processed';
end;
$$;

-- Builds one final-balance invoice request (04 §10, §8.2 items 5, 6, 11; OI-74): a one-off
-- invoice for the client business's Customer, a single balance line at quantity 1, charged
-- automatically. Automatic: `default_payment_method` names the authorization's card
-- explicitly (never a Customer or subscription default, T-PAY-26) and `auto_advance` is
-- true. Hosted only (no active authorization): finalized with `auto_advance` false, so no
-- automatic attempt is made and it is paid on its Stripe-hosted page. No discount; the
-- maintenance subscription is never on it [VERIFY-PROVIDER, DEP-06].
create function private.final_balance_invoice_params(p_fbi public.final_balance_invoices, p_mode text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'collection_method', 'charge_automatically',
    'auto_advance', p_mode = 'automatic',
    'lines', jsonb_build_array(jsonb_build_object('price', p_fbi.balance_price_id, 'quantity', 1)),
    'discounts', '[]'::jsonb,
    'automatic_tax', jsonb_build_object('enabled', false),
    'expected_amount_due', p_fbi.amount_cents,
    'metadata', jsonb_build_object('project_id', p_fbi.project_id, 'order_summary_id', p_fbi.order_summary_id,
      'final_balance_invoice_id', p_fbi.id, 'approval_id', p_fbi.approval_id, 'release_id', p_fbi.release_id,
      -- payment_consent_id: the 04 §8.1 authorization record (payload keys may not contain
      -- "authorization", WP-0 payload_is_safe).
      'payment_consent_id', p_fbi.payment_authorization_id, 'collection_mode', p_mode,
      'environment', private.app_environment()))
  || case when p_mode = 'automatic' then jsonb_build_object('default_payment_method', p_fbi.default_payment_method_id)
          else '{}'::jsonb end;
$$;

create function private.handle_final_balance_paid(e public.webhook_events, inv jsonb, p_fbi_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_entry bigint;
  v_event bigint;
  v_key text;
begin
  select * into v_fbi from public.final_balance_invoices where id = p_fbi_id for update;
  update public.webhook_events set project_id = v_fbi.project_id where id = e.id;
  if (inv #>> '{metadata,final_balance_invoice_id}') is distinct from v_fbi.id::text
     or (inv #>> '{metadata,project_id}') is distinct from v_fbi.project_id::text
     or (inv #>> '{metadata,order_summary_id}') is distinct from v_fbi.order_summary_id::text
     or (v_fbi.stripe_invoice_id is not null and v_fbi.stripe_invoice_id <> inv ->> 'id') then
    return 'quarantined:metadata_mismatch';
  end if;
  if (inv ->> 'customer') is distinct from v_fbi.stripe_customer_id or inv ->> 'currency' is distinct from 'usd' then
    return 'quarantined:customer_or_currency_mismatch';
  end if;
  if private.invoice_price_ids(inv) <> array[v_fbi.balance_price_id] or not private.invoice_line_quantities_ok(inv) then
    return 'quarantined:line_items_mismatch';
  end if;
  if private.invoice_discount_cents(inv) <> 0 or coalesce((inv ->> 'tax')::bigint, 0) <> 0 then
    return 'quarantined:discount_or_tax_present';
  end if;
  -- The charged amount equals the authorized snapshot balance (T-PAY-26).
  if (inv ->> 'amount_paid')::bigint is distinct from v_fbi.amount_cents then
    return 'quarantined:amount_mismatch';
  end if;
  -- An invoice created for automatic collection must still name the authorization's card;
  -- any other card, or none, is quarantined (T-PAY-26, fail closed).
  if v_fbi.default_payment_method_id is not null
     and (inv ->> 'default_payment_method') is distinct from v_fbi.default_payment_method_id then
    return 'quarantined:payment_method_mismatch';
  end if;
  perform private.link_payment_refs(v_fbi.project_id, 'final_balance', v_fbi.id, inv);
  update public.final_balance_invoices
     set status = 'paid', paid_at = coalesce(paid_at, now()), stripe_invoice_id = coalesce(stripe_invoice_id, inv ->> 'id'),
         hosted_invoice_url = coalesce(hosted_invoice_url, case when inv ->> 'hosted_invoice_url' ~ '^https://invoice\.stripe\.com/' then inv ->> 'hosted_invoice_url' end),
         charged_after_halt = charged_after_halt or coalesce(halt_cause in ('revoked', 'payment_method_detached'), false),
         last_event_created = greatest(coalesce(last_event_created, e.stripe_created_at), e.stripe_created_at)
   where id = v_fbi.id and status <> 'paid';
  v_key := 'final_balance:' || v_fbi.id::text;
  v_entry := private.post_ledger_entry(v_fbi.project_id, v_fbi.order_summary_id, 'balance_charge', v_fbi.amount_cents,
    'development', e.id, 'invoice', inv ->> 'id', inv ->> 'id', null, null, v_key || ':balance');
  perform private.create_obligation(v_fbi.project_id, v_fbi.order_summary_id, 'development_balance', v_key, v_key || ':balance');
  if v_entry is not null then
    v_event := private.emit_domain_event('payment.balance_verified', v_fbi.project_id, 'final_balance_invoice',
      v_fbi.id::text, jsonb_build_object('order_summary_id', v_fbi.order_summary_id),
      'payment.balance_verified:' || v_fbi.id::text);
    perform private.audit_financial('balance.charge_succeeded', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id,
      jsonb_build_object('approval_id', v_fbi.approval_id, 'amount_cents', v_fbi.amount_cents,
        'collection_mode', v_fbi.collection_mode));
    perform private.enqueue_notification('payment.final_verified', 'payment.final_verified:' || v_fbi.id::text || ':1',
      'payment.final_verified', 1, v_fbi.project_id, v_event, private.project_client_user_ids(v_fbi.project_id),
      '{owner,admin}', jsonb_build_object('project_id', v_fbi.project_id), 'general');
    -- Stripe is authoritative for money: a payment that landed after automatic collection
    -- was halted (revocation or detached card) is verified, and goes to Owner review.
    if v_fbi.halt_cause in ('revoked', 'payment_method_detached') then
      if v_fbi.payment_authorization_id is not null then
        perform private.record_authorization_event(v_fbi.payment_authorization_id, 'charged_after_halt',
          (select status from public.payment_authorizations where id = v_fbi.payment_authorization_id),
          (select status from public.payment_authorizations where id = v_fbi.payment_authorization_id), null, e.id, null);
      end if;
      perform private.notify_owner('payment.charged_after_halt', 'payment.charged_after_halt:' || v_fbi.id::text || ':1',
        v_fbi.project_id, v_event, jsonb_build_object('final_balance_invoice_id', v_fbi.id));
      -- B1: G4 stays blocked until the Owner reviews this item (resolve_reconciliation_mismatch).
      insert into public.reconciliation_mismatches (project_id, kind, charge_key, observed_cents)
      values (v_fbi.project_id, 'charged_after_halt', v_key, v_fbi.amount_cents)
      on conflict (charge_key) where kind = 'charged_after_halt' do nothing;
      perform private.audit_financial('balance.charged_after_halt', 'final_balance_invoice', v_fbi.id::text, v_fbi.project_id);
    end if;
  end if;
  return 'processed';
end;
$$;
create function private.handle_invoice_paid(e public.webhook_events, inv jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi_id uuid;
  v_cs public.checkout_sessions%rowtype;
  v_os public.order_summaries%rowtype;
  v_meta jsonb := private.invoice_subscription_metadata(inv);
  v_project uuid;
  v_sub text := private.invoice_subscription_id(inv);
  v_rec public.maintenance_recoveries%rowtype;
  v_hold uuid;
  v_event bigint;
  v_entry bigint;
begin
  select id into v_fbi_id from public.final_balance_invoices
   where stripe_invoice_id = inv ->> 'id' or id = private.try_uuid(inv #>> '{metadata,final_balance_invoice_id}')
   limit 1;
  if v_fbi_id is not null then
    return private.handle_final_balance_paid(e, inv, v_fbi_id);
  end if;

  select * into v_cs from public.checkout_sessions
   where stripe_invoice_id = inv ->> 'id' or id = private.try_uuid(v_meta ->> 'checkout_record_id') limit 1 for update;
  if found or inv ->> 'billing_reason' = 'subscription_create' then
    if v_cs.id is null then
      return 'deferred';
    end if;
    select * into v_os from public.order_summaries where id = v_cs.order_summary_id;
    update public.webhook_events set project_id = v_cs.project_id where id = e.id;
    if (v_meta ->> 'project_id') is not null and (v_meta ->> 'project_id') <> v_cs.project_id::text then
      return 'quarantined:metadata_mismatch';
    end if;
    if v_cs.stripe_invoice_id is not null and v_cs.stripe_invoice_id <> inv ->> 'id' then
      return 'quarantined:invoice_mismatch';
    end if;
    if inv ->> 'currency' is distinct from 'usd' or (inv ->> 'amount_paid')::bigint is distinct from
       (v_os.deposit_cents + v_os.maintenance_monthly_cents)::bigint then
      return 'quarantined:amount_mismatch';
    end if;
    if (select array_agg(x order by x) from unnest(private.invoice_price_ids(inv)) x)
       is distinct from (select array_agg(x order by x) from unnest(array[v_os.deposit_price_id, v_os.maintenance_price_id]) x)
       or not private.invoice_line_quantities_ok(inv) then
      return 'quarantined:line_items_mismatch';
    end if;
    if private.invoice_discount_cents(inv) <> 0 or coalesce((inv ->> 'tax')::bigint, 0) <> 0 then
      return 'quarantined:discount_or_tax_present';
    end if;
    update public.checkout_sessions set stripe_invoice_id = coalesce(stripe_invoice_id, inv ->> 'id'),
      stripe_subscription_id = coalesce(stripe_subscription_id, v_sub) where id = v_cs.id;
    perform private.link_payment_refs(v_cs.project_id, 'initial', v_cs.id, inv);
    perform private.mark_deposit_verified(v_cs.id, e.id, inv ->> 'id');
    return 'processed';
  end if;

  if inv ->> 'billing_reason' in ('subscription_cycle', 'subscription_update') then
    select project_id into v_project from public.subscriptions where stripe_subscription_id = v_sub;
    if v_project is null then
      v_project := (select p.id from public.projects p where p.id = private.try_uuid(v_meta ->> 'project_id'));
    end if;
    if v_project is null then
      return 'deferred';
    end if;
    update public.webhook_events set project_id = v_project where id = e.id;
    if inv ->> 'currency' is distinct from 'usd' or (inv ->> 'amount_paid')::bigint is distinct from private.maintenance_monthly_cents()
       or private.invoice_price_ids(inv) <> array[(select price_id from private.stripe_catalog_prices
            where environment = private.stripe_mode() and catalog_version = private.current_catalog_version()
              and component = 'maintenance')]
       or private.invoice_discount_cents(inv) <> 0 then
      return 'quarantined:maintenance_amount_mismatch';
    end if;
    perform private.link_payment_refs(v_project, 'renewal', null, inv);
    v_entry := private.post_ledger_entry(v_project, null, 'maintenance_charge', private.maintenance_monthly_cents(),
      'maintenance', e.id, 'invoice', inv ->> 'id', inv ->> 'id', null, null, 'invoice:' || (inv ->> 'id') || ':maintenance');
    perform private.create_obligation(v_project, null, 'maintenance', 'renewal:' || (inv ->> 'id'),
      'invoice:' || (inv ->> 'id') || ':maintenance');
    select * into v_rec from public.maintenance_recoveries where stripe_invoice_id = inv ->> 'id' for update;
    if found and v_rec.status <> 'recovered' then
      update public.maintenance_recoveries set status = 'recovered', recovered_at = now() where id = v_rec.id;
      v_event := private.emit_domain_event('subscription.payment_recovered', v_project, 'maintenance_recovery',
        v_rec.id::text, '{}'::jsonb, 'subscription.payment_recovered:' || v_rec.id::text);
      perform private.audit_financial('maintenance.payment_recovered', 'maintenance_recovery', v_rec.id::text, v_project);
      -- OI-26: verified payment recovery clears the system hold automatically.
      select id into v_hold from public.billing_holds
       where source_ref = v_rec.id::text and hold_type = 'maintenance_payment_hold' and cleared_at is null;
      if v_hold is not null then
        perform private.clear_hold_internal(v_hold, 'verified_recovery', 'Verified recovery payment',
          jsonb_build_object('webhook_event_id', e.id, 'stripe_invoice_id', inv ->> 'id'));
      end if;
    end if;
    return 'processed';
  end if;
  return 'quarantined:unrecognized_invoice';
end;
$$;

create function private.handle_invoice_failed(e public.webhook_events, inv jsonb, p_action_required boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
  v_sub text := private.invoice_subscription_id(inv);
  v_project uuid;
  v_rec uuid;
  v_t0 timestamptz;
  v_event bigint;
begin
  select * into v_fbi from public.final_balance_invoices
   where stripe_invoice_id = inv ->> 'id' or id = private.try_uuid(inv #>> '{metadata,final_balance_invoice_id}')
   limit 1 for update;
  if found then
    update public.webhook_events set project_id = v_fbi.project_id where id = e.id;
    if (inv #>> '{metadata,final_balance_invoice_id}') is distinct from v_fbi.id::text then
      return 'quarantined:metadata_mismatch';
    end if;
    -- Stale events never move the balance backwards (T-ARC-03).
    if v_fbi.status in ('paid', 'void') or (v_fbi.last_event_created is not null and e.stripe_created_at < v_fbi.last_event_created) then
      return 'ignored';
    end if;
    update public.final_balance_invoices
       set status = case when p_action_required then 'action_required'::public.final_balance_invoice_status
                         else 'payment_failed'::public.final_balance_invoice_status end,
           stripe_invoice_id = coalesce(stripe_invoice_id, inv ->> 'id'),
           hosted_invoice_url = coalesce(hosted_invoice_url, case when inv ->> 'hosted_invoice_url' ~ '^https://invoice\.stripe\.com/' then inv ->> 'hosted_invoice_url' end),
           last_event_created = e.stripe_created_at
     where id = v_fbi.id;
    v_event := private.emit_domain_event('payment.balance_failed', v_fbi.project_id, 'final_balance_invoice', v_fbi.id::text,
      jsonb_build_object('action_required', p_action_required), 'payment.balance_failed:' || e.stripe_event_id);
    -- A failed automatic charge (04 §8.1 "When"): the card is unavailable for automatic use and
    -- recovery is offered; this invoice is completed on its hosted page (T-PAY-14). A failure
    -- on the hosted page of a hosted-only invoice says nothing about the authorization's card.
    if not p_action_required and v_fbi.collection_mode = 'automatic' then
      update public.payment_authorizations set status = 'payment_method_unavailable'
       where project_id = v_fbi.project_id and status = 'active';
      if found then
        perform private.record_authorization_event((select id from public.payment_authorizations
            where project_id = v_fbi.project_id and status = 'payment_method_unavailable'),
          'unavailable', 'active', 'payment_method_unavailable', null, e.id, 'final_balance_charge_failed');
        perform private.audit_financial('payment_authorization.unavailable', 'final_balance_invoice', v_fbi.id::text,
          v_fbi.project_id, jsonb_build_object('cause', 'invoice.payment_failed'));
      end if;
      -- No automatic retry without an active authorization (04 §8.1 invariant 14).
      perform private.halt_automatic_collection(v_fbi.project_id, 'charge_failed');
    end if;
    perform private.audit_financial(case when p_action_required then 'balance.action_required' else 'balance.charge_failed' end,
      'final_balance_invoice', v_fbi.id::text, v_fbi.project_id, jsonb_build_object('stripe_event_id', e.stripe_event_id));
    perform private.enqueue_notification('payment.final_action_required',
      'payment.final_action_required:' || e.stripe_event_id || ':1', 'payment.final_action_required', 1,
      v_fbi.project_id, v_event, private.project_client_user_ids(v_fbi.project_id), '{}',
      jsonb_build_object('project_id', v_fbi.project_id), 'general');
    return 'processed';
  end if;

  if p_action_required or inv ->> 'billing_reason' is distinct from 'subscription_cycle' then
    return 'ignored';
  end if;
  select project_id into v_project from public.subscriptions where stripe_subscription_id = v_sub;
  if v_project is null then
    v_project := (select p.id from public.projects p where p.id = private.try_uuid(private.invoice_subscription_metadata(inv) ->> 'project_id'));
  end if;
  if v_project is null then
    return 'deferred';
  end if;
  update public.webhook_events set project_id = v_project where id = e.id;
  if exists (select 1 from public.ledger_entries where dedupe_key = 'invoice:' || (inv ->> 'id') || ':maintenance') then
    return 'ignored';
  end if;
  -- OI-26: T0 is Stripe's failure time; recovery ends 23:59:59 America/Detroit on the 7th
  -- calendar day after T0's local date (02 §13.2).
  v_t0 := e.stripe_created_at;
  insert into public.maintenance_recoveries (project_id, stripe_invoice_id, stripe_subscription_id, failed_at,
    recovery_ends_at, calendar_version)
  values (v_project, inv ->> 'id', v_sub, v_t0, private.end_of_local_day(private.local_date(v_t0) + 7),
    private.calendar_version())
  on conflict (stripe_invoice_id) do nothing
  returning id into v_rec;
  if v_rec is not null then
    v_event := private.emit_domain_event('subscription.payment_failed', v_project, 'maintenance_recovery', v_rec::text,
      '{}'::jsonb, 'subscription.payment_failed:' || v_rec::text);
    perform private.audit_financial('maintenance.payment_failed', 'maintenance_recovery', v_rec::text, v_project,
      jsonb_build_object('stripe_invoice_id', inv ->> 'id'));
    perform private.enqueue_notification('billing.maintenance_payment_failed',
      'billing.maintenance_payment_failed:' || v_rec::text || ':1', 'billing.maintenance_payment_failed', 1, v_project,
      v_event, private.project_client_user_ids(v_project), '{owner}', jsonb_build_object('project_id', v_project), 'financial');
  end if;
  return 'processed';
end;
$$;

create function private.handle_invoice_finalized(e public.webhook_events, inv jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_fbi public.final_balance_invoices%rowtype;
begin
  select * into v_fbi from public.final_balance_invoices
   where stripe_invoice_id = inv ->> 'id' or id = private.try_uuid(inv #>> '{metadata,final_balance_invoice_id}')
   limit 1 for update;
  if not found then
    return 'ignored';
  end if;
  update public.webhook_events set project_id = v_fbi.project_id where id = e.id;
  if (inv #>> '{metadata,final_balance_invoice_id}') is distinct from v_fbi.id::text
     or (v_fbi.stripe_invoice_id is not null and v_fbi.stripe_invoice_id <> inv ->> 'id') then
    return 'quarantined:metadata_mismatch';
  end if;
  update public.final_balance_invoices
     set stripe_invoice_id = coalesce(stripe_invoice_id, inv ->> 'id'),
         hosted_invoice_url = coalesce(hosted_invoice_url, case when inv ->> 'hosted_invoice_url' ~ '^https://invoice\.stripe\.com/' then inv ->> 'hosted_invoice_url' end)
   where id = v_fbi.id;
  return 'processed';
end;
$$;

create function private.handle_subscription(e public.webhook_events, sub jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
  v_existing public.subscriptions%rowtype;
  v_status public.subscription_status;
  v_exception uuid;
  v_event bigint;
begin
  select * into v_existing from public.subscriptions where stripe_subscription_id = sub ->> 'id' for update;
  v_project := coalesce(v_existing.project_id,
    (select p.id from public.projects p where p.id = private.try_uuid(sub #>> '{metadata,project_id}')),
    (select cs.project_id from public.checkout_sessions cs where cs.stripe_subscription_id = sub ->> 'id' limit 1));
  if v_project is null then
    return 'deferred';
  end if;
  update public.webhook_events set project_id = v_project where id = e.id;
  if v_existing.project_id is not null and (sub #>> '{metadata,project_id}') is not null
     and (sub #>> '{metadata,project_id}') <> v_existing.project_id::text then
    return 'quarantined:metadata_mismatch';
  end if;
  if e.event_type = 'customer.subscription.deleted' then
    v_status := 'canceled';
  elsif sub ->> 'status' in ('incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'canceled', 'unpaid', 'paused') then
    v_status := (sub ->> 'status')::public.subscription_status;
  else
    return 'quarantined:unknown_subscription_status';
  end if;

  if v_existing.stripe_subscription_id is null then
    insert into public.subscriptions (stripe_subscription_id, project_id, stripe_customer_id, status, cancel_at_period_end,
      current_period_end, canceled_at, last_event_created)
    values (sub ->> 'id', v_project, sub ->> 'customer', v_status, coalesce((sub ->> 'cancel_at_period_end')::boolean, false),
      coalesce(private.unix_ts(sub -> 'current_period_end'), private.unix_ts(sub #> '{items,data,0,current_period_end}')),
      private.unix_ts(sub -> 'canceled_at'), e.stripe_created_at);
  elsif e.stripe_created_at >= v_existing.last_event_created and v_existing.status <> 'canceled' then
    -- Order independence (04 §17 #5): only a newer event changes the mirror, and a canceled
    -- subscription stays canceled.
    update public.subscriptions
       set status = v_status, cancel_at_period_end = coalesce((sub ->> 'cancel_at_period_end')::boolean, cancel_at_period_end),
           current_period_end = coalesce(private.unix_ts(sub -> 'current_period_end'),
             private.unix_ts(sub #> '{items,data,0,current_period_end}'), current_period_end),
           canceled_at = coalesce(private.unix_ts(sub -> 'canceled_at'), canceled_at),
           stripe_customer_id = coalesce(stripe_customer_id, sub ->> 'customer'),
           last_event_created = e.stripe_created_at, updated_at = now()
     where stripe_subscription_id = v_existing.stripe_subscription_id;
  elsif e.event_type <> 'customer.subscription.deleted' then
    return 'ignored';
  end if;
  if v_existing.status is distinct from v_status then
    perform private.emit_domain_event('subscription.status_changed', v_project, 'subscription', sub ->> 'id',
      jsonb_build_object('status', v_status), 'subscription.status_changed:' || e.stripe_event_id);
    perform private.audit_financial('subscription.status_mirrored', 'subscription', sub ->> 'id', v_project,
      jsonb_build_object('status', v_status, 'previous_status', v_existing.status));
  end if;

  -- OI-46 / T-BIL-15: a deletion that matches no authorized termination is an Owner
  -- exception review. It never starts a termination and never affects the website.
  if e.event_type = 'customer.subscription.deleted' and not exists (
       select 1 from public.service_terminations t where t.project_id = v_project
         and t.state in ('termination_authorized', 'effective', 'maintenance_ceased', 'offboarded', 'transferred')) then
    insert into public.stripe_cancellation_exceptions (project_id, stripe_subscription_id, webhook_event_id)
    values (v_project, sub ->> 'id', e.id) on conflict (stripe_subscription_id) do nothing returning id into v_exception;
    if v_exception is not null then
      v_event := private.emit_domain_event('subscription.cancellation_exception', v_project, 'stripe_cancellation_exception',
        v_exception::text, '{}'::jsonb, 'subscription.cancellation_exception:' || v_exception::text);
      perform private.audit_financial('stripe.cancellation_exception', 'stripe_cancellation_exception', v_exception::text, v_project);
      perform private.notify_owner('billing.stripe_cancellation_exception',
        'billing.stripe_cancellation_exception:' || v_exception::text || ':1', v_project, v_event,
        jsonb_build_object('exception_id', v_exception));
    end if;
  end if;
  return 'processed';
end;
$$;

-- ---------------------------------------------------------------------------
-- 9a. Reversal allocation: refunds and disputes (04 §15.2.1; OI-82). Never deposit-first,
--     maintenance-first, or proportional. Serialized per charge (advisory lock); each Stripe
--     refund and dispute is applied once; limits per obligation and per charge.
-- ---------------------------------------------------------------------------
create function private.link_charge_key(p_link private.stripe_payment_links) returns text
language sql immutable set search_path = '' as $$
  select case p_link.kind
    when 'initial' then 'initial:' || p_link.domain_record_id::text
    when 'renewal' then 'renewal:' || p_link.stripe_invoice_id
    when 'final_balance' then 'final_balance:' || p_link.domain_record_id::text end;
$$;

create function private.post_reversal_entry(p_project_id uuid, p_type public.ledger_entry_type, p_amount bigint,
  p_obligation public.payment_obligations, p_holding_key text, p_webhook_event_id bigint, p_object_type text,
  p_object_id text, p_charge_ref text, p_dedupe_key text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
begin
  insert into public.ledger_entries (project_id, order_summary_id, entry_type, amount_cents, service_category, source,
    webhook_event_id, stripe_object_type, stripe_object_id, stripe_charge_ref, obligation_id, holding_charge_key, dedupe_key)
  values (p_project_id, p_obligation.order_summary_id, p_type, p_amount,
    case when p_holding_key is null then p_obligation.service_category end, 'webhook', p_webhook_event_id,
    p_object_type, p_object_id, p_charge_ref, p_obligation.id, p_holding_key, p_dedupe_key)
  on conflict (dedupe_key) do nothing
  returning id into v_id;
  if v_id is not null then
    perform private.audit_financial('ledger.entry_posted', 'ledger_entry', v_id::text, p_project_id,
      jsonb_build_object('entry_type', p_type, 'amount_cents', p_amount,
        'target', case when p_holding_key is null then 'obligation' else 'holding' end));
  end if;
  return v_id;
end;
$$;

-- Applies one new reversal (a succeeded refund, or an opened dispute) of p_amount to the
-- charge's obligations by the approved rules, in order:
--   (a) single-obligation charge: that obligation;
--   (b) verified full reversal of the initial charge: every line in full;
--   (c) refunds only: an Owner-recorded allocation referenced by the refund, recorded before
--       issuance, per line, summing exactly to the refund;
--   (d) anything else: the unresolved reversal holding account, with an Owner item.
-- Rule 4: cumulative reversals never exceed an obligation or the charge; excess quarantines.
create function private.apply_reversal(e public.webhook_events, p_link private.stripe_payment_links,
  p_type public.ledger_entry_type, p_object_type text, p_object_id text, p_amount bigint, p_decision_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_key text := private.link_charge_key(p_link);
  v_obs public.payment_obligations[];
  v_ob public.payment_obligations%rowtype;
  v_original bigint;
  v_retained bigint;
  v_decision public.refund_decisions%rowtype;
  v_lines_ok boolean;
  v_null public.payment_obligations%rowtype;
begin
  perform pg_advisory_xact_lock(hashtextextended('wpb:charge:' || v_key, 0));
  -- Counted once: a reversal already applied for this Stripe object posts nothing again.
  if exists (select 1 from public.ledger_entries where stripe_object_id = p_object_id and entry_type = p_type) then
    return 'processed';
  end if;
  select array_agg(o order by o.kind) into v_obs from public.payment_obligations o where o.charge_key = v_key;
  if v_obs is null then
    return 'deferred'; -- the charge itself has not been posted yet (order independence)
  end if;
  select coalesce(sum(o.original_cents), 0), coalesce(sum(private.obligation_net_cents(o.id)), 0)
    into v_original, v_retained from unnest(v_obs) o;
  v_retained := v_retained + private.holding_balance_cents(v_key);
  if p_amount <= 0 or p_amount > v_retained then
    return 'quarantined:reversal_exceeds_charge';
  end if;

  if cardinality(v_obs) = 1 then -- (a)
    v_ob := v_obs[1];
    if p_amount > private.obligation_net_cents(v_ob.id) then
      return 'quarantined:reversal_exceeds_obligation';
    end if;
    perform private.post_reversal_entry(p_link.project_id, p_type, -p_amount, v_ob, null, e.id, p_object_type,
      p_object_id, p_link.stripe_ref, p_object_id || ':' || p_type || ':' || v_ob.id::text);
    return 'processed';
  end if;

  if p_amount = v_original and v_retained = v_original then -- (b)
    foreach v_ob in array v_obs loop
      perform private.post_reversal_entry(p_link.project_id, p_type, -v_ob.original_cents, v_ob, null, e.id, p_object_type,
        p_object_id, p_link.stripe_ref, p_object_id || ':' || p_type || ':' || v_ob.id::text);
    end loop;
    return 'processed';
  end if;

  if p_type = 'refund' and p_decision_id is not null then -- (c)
    select * into v_decision from public.refund_decisions
     where id = p_decision_id and project_id = p_link.project_id and charge_key = v_key and amount_cents = p_amount
       and (matched_refund_id is null or matched_refund_id = p_object_id) for update;
    if found then
      select coalesce(sum(l.amount_cents), 0) = p_amount
             and bool_and(o.charge_key = v_key and l.amount_cents <= private.obligation_net_cents(o.id))
        into v_lines_ok
        from public.refund_decision_lines l join public.payment_obligations o on o.id = l.obligation_id
       where l.refund_decision_id = v_decision.id;
      if coalesce(v_lines_ok, false) then
        for v_ob in select o.* from public.refund_decision_lines l join public.payment_obligations o on o.id = l.obligation_id
                     where l.refund_decision_id = v_decision.id order by o.kind loop
          perform private.post_reversal_entry(p_link.project_id, p_type,
            -(select l.amount_cents from public.refund_decision_lines l
               where l.refund_decision_id = v_decision.id and l.obligation_id = v_ob.id),
            v_ob, null, e.id, p_object_type, p_object_id, p_link.stripe_ref,
            p_object_id || ':' || p_type || ':' || v_ob.id::text);
        end loop;
        update public.refund_decisions set matched_refund_id = p_object_id, matched_at = now()
         where id = v_decision.id and matched_refund_id is null;
        return 'processed';
      end if;
    end if;
  end if;

  -- (d) Holding account: no category is assumed; the Owner reconciles (rule 6).
  perform private.post_reversal_entry(p_link.project_id, p_type, -p_amount, v_null, v_key, e.id, p_object_type,
    p_object_id, p_link.stripe_ref, p_object_id || ':' || p_type || ':holding');
  perform private.audit_financial('reversal.holding_posted', 'charge', v_key, p_link.project_id,
    jsonb_build_object('stripe_object_id', p_object_id, 'entry_type', p_type, 'amount_cents', p_amount,
      'refund_decision_id', p_decision_id));
  perform private.notify_owner('reversal.reconciliation_required',
    'reversal.reconciliation_required:' || p_object_id || ':' || p_type, p_link.project_id, null,
    jsonb_build_object('charge_key', v_key));
  return 'processed';
end;
$$;

-- Mirrors every entry an earlier reversal posted (dispute won: reinstatement; dispute lost:
-- zero-amount final record; refund failed after succeeding: reversal). New entries only.
create function private.mirror_reversal(e public.webhook_events, p_object_id text, p_source_type public.ledger_entry_type,
  p_type public.ledger_entry_type, p_suffix text) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_entry public.ledger_entries%rowtype;
  v_ob public.payment_obligations%rowtype;
  v_count integer := 0;
begin
  for v_entry in select * from public.ledger_entries where stripe_object_id = p_object_id and entry_type = p_source_type
                   and amount_cents < 0 order by id loop
    select * into v_ob from public.payment_obligations where id = v_entry.obligation_id;
    if private.post_reversal_entry(v_entry.project_id, p_type,
         case when p_type = 'dispute_lost' then 0 else -v_entry.amount_cents end,
         v_ob, v_entry.holding_charge_key, e.id, v_entry.stripe_object_type, p_object_id, v_entry.stripe_charge_ref,
         v_entry.dedupe_key || ':' || p_suffix) is not null then
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end;
$$;

create function private.handle_refund(e public.webhook_events, r jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_link private.stripe_payment_links%rowtype;
  v_existing public.refunds%rowtype;
  -- A malformed amount is quarantined once the charge is known, never a processing error.
  v_amount bigint := private.try_cents(r -> 'amount');
  v_decision uuid := private.try_uuid(r #>> '{metadata,refund_decision_id}');
  v_outcome text := 'processed';
begin
  select * into v_link from private.stripe_payment_links
   where stripe_ref in (r ->> 'charge', r ->> 'payment_intent') order by stripe_ref limit 1;
  if not found then
    return 'deferred';
  end if;
  update public.webhook_events set project_id = v_link.project_id where id = e.id;
  if r ->> 'currency' is distinct from 'usd' or v_amount is null or v_amount <= 0 then
    return 'quarantined:refund_invalid';
  end if;
  select * into v_existing from public.refunds where stripe_refund_id = r ->> 'id' for update;
  if not found then
    insert into public.refunds (stripe_refund_id, project_id, stripe_charge_ref, amount_cents, currency, status,
      refund_decision_id, last_event_created)
    values (r ->> 'id', v_link.project_id, v_link.stripe_ref, v_amount, 'usd', r ->> 'status',
      (select d.id from public.refund_decisions d where d.id = v_decision and d.project_id = v_link.project_id),
      e.stripe_created_at);
  elsif v_existing.amount_cents <> v_amount then
    return 'quarantined:refund_amount_changed';
  elsif e.stripe_created_at >= v_existing.last_event_created and v_existing.status not in ('failed', 'canceled') then
    update public.refunds set status = r ->> 'status', last_event_created = e.stripe_created_at, updated_at = now()
     where stripe_refund_id = v_existing.stripe_refund_id;
  end if;

  if r ->> 'status' = 'succeeded' then
    v_outcome := private.apply_reversal(e, v_link, 'refund', 'refund', r ->> 'id', v_amount, v_decision);
  elsif r ->> 'status' in ('failed', 'canceled') then
    perform private.mirror_reversal(e, r ->> 'id', 'refund', 'refund', 'reversal');
  end if;
  if v_outcome = 'processed' then
    perform private.emit_domain_event('payment.refund_recorded', v_link.project_id, 'refund', r ->> 'id',
      jsonb_build_object('status', r ->> 'status'), 'payment.refund_recorded:' || e.stripe_event_id);
    perform private.audit_financial('refund.recorded', 'refund', r ->> 'id', v_link.project_id,
      jsonb_build_object('amount_cents', v_amount, 'status', r ->> 'status', 'refund_decision_id', v_decision));
  end if;
  return v_outcome;
end;
$$;

create function private.handle_charge_refunded(e public.webhook_events, ch jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_refund jsonb;
  v_outcome text;
  v_any boolean := false;
begin
  if jsonb_typeof(ch #> '{refunds,data}') <> 'array' then
    return 'ignored'; -- refund.* events carry each refund object
  end if;
  for v_refund in select * from jsonb_array_elements(ch #> '{refunds,data}') loop
    v_outcome := private.handle_refund(e, v_refund || jsonb_build_object('charge', ch ->> 'id'));
    if v_outcome <> 'processed' then
      return v_outcome;
    end if;
    v_any := true;
  end loop;
  return case when v_any then 'processed' else 'ignored' end;
end;
$$;

-- 04 §15.2.1 rule 5 (OI-37 holds unchanged): opened posts withdrawn entries; won posts
-- reinstatement entries; lost leaves the reversal final. Inquiries (warning_*) post nothing.
create function private.handle_dispute(e public.webhook_events, d jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_link private.stripe_payment_links%rowtype;
  v_existing public.disputes%rowtype;
  v_amount bigint := private.try_cents(d -> 'amount');
  v_event bigint;
  v_new boolean := false;
  v_outcome text := 'processed';
begin
  select * into v_link from private.stripe_payment_links
   where stripe_ref in (d ->> 'charge', d ->> 'payment_intent') order by stripe_ref limit 1;
  if not found then
    return 'deferred';
  end if;
  update public.webhook_events set project_id = v_link.project_id where id = e.id;
  if d ->> 'currency' is distinct from 'usd' or v_amount is null or v_amount <= 0
     or d ->> 'status' not in ('warning_needs_response', 'warning_under_review', 'warning_closed', 'needs_response',
                               'under_review', 'won', 'lost', 'prevented') then
    return 'quarantined:dispute_invalid';
  end if;
  if not exists (select 1 from public.payment_obligations where charge_key = private.link_charge_key(v_link)) then
    return 'deferred';
  end if;
  select * into v_existing from public.disputes where stripe_dispute_id = d ->> 'id' for update;
  if not found then
    v_new := true;
    insert into public.disputes (stripe_dispute_id, project_id, stripe_charge_ref, amount_cents, currency, status, reason,
      evidence_due_by, opened_at, closed_at, last_event_created)
    values (d ->> 'id', v_link.project_id, v_link.stripe_ref, v_amount, 'usd', d ->> 'status', left(d ->> 'reason', 100),
      private.unix_ts(d #> '{evidence_details,due_by}'), coalesce(private.unix_ts(d -> 'created'), e.stripe_created_at),
      case when d ->> 'status' in ('won', 'lost', 'warning_closed', 'prevented') then now() end, e.stripe_created_at);
  elsif v_existing.amount_cents <> v_amount then
    return 'quarantined:dispute_amount_changed';
  elsif e.stripe_created_at >= v_existing.last_event_created and v_existing.status not in ('won', 'lost') then
    update public.disputes
       set status = d ->> 'status', reason = coalesce(left(d ->> 'reason', 100), reason),
           evidence_due_by = coalesce(private.unix_ts(d #> '{evidence_details,due_by}'), evidence_due_by),
           closed_at = case when d ->> 'status' in ('won', 'lost', 'warning_closed', 'prevented') then coalesce(closed_at, now()) end,
           last_event_created = e.stripe_created_at, updated_at = now()
     where stripe_dispute_id = v_existing.stripe_dispute_id;
  end if;

  -- Funds are withdrawn for any non-inquiry status (a dispute first seen as won or lost
  -- still withdrew funds before closing).
  if d ->> 'status' not in ('warning_needs_response', 'warning_under_review', 'warning_closed', 'prevented')
     and not exists (select 1 from public.ledger_entries where stripe_object_id = d ->> 'id' and entry_type = 'dispute_opened') then
    v_outcome := private.apply_reversal(e, v_link, 'dispute_opened', 'dispute', d ->> 'id', v_amount, null);
    if v_outcome <> 'processed' then
      return v_outcome;
    end if;
    v_event := private.emit_domain_event('payment.dispute_opened', v_link.project_id, 'dispute', d ->> 'id', '{}'::jsonb,
      'payment.dispute_opened:' || (d ->> 'id'));
    perform private.audit_financial('dispute.opened', 'dispute', d ->> 'id', v_link.project_id,
      jsonb_build_object('amount_cents', v_amount, 'evidence_due_by', d #> '{evidence_details,due_by}'));
    -- OI-37: immediate Owner notification; no takedown and no automatic hold.
    perform private.notify_owner('dispute.opened', 'dispute.opened:' || (d ->> 'id') || ':1', v_link.project_id, v_event,
      jsonb_build_object('dispute_id', d ->> 'id'));
  end if;
  -- Only the stored, monotonic outcome is mirrored: a stale "won" after "lost" (or the
  -- reverse) never posts anything (04 §17 #5, T-ARC-03).
  if d ->> 'status' in ('won', 'lost')
     and (select x.status from public.disputes x where x.stripe_dispute_id = d ->> 'id') = d ->> 'status' then
    if private.mirror_reversal(e, d ->> 'id', 'dispute_opened',
         case when d ->> 'status' = 'won' then 'dispute_won'::public.ledger_entry_type
              else 'dispute_lost'::public.ledger_entry_type end, d ->> 'status') > 0 then
      perform private.emit_domain_event('payment.dispute_closed', v_link.project_id, 'dispute', d ->> 'id',
        jsonb_build_object('outcome', d ->> 'status'), 'payment.dispute_closed:' || (d ->> 'id'));
      perform private.audit_financial('dispute.closed', 'dispute', d ->> 'id', v_link.project_id,
        jsonb_build_object('outcome', d ->> 'status'));
    end if;
  elsif not v_new then
    perform private.audit_financial('dispute.updated', 'dispute', d ->> 'id', v_link.project_id,
      jsonb_build_object('status', d ->> 'status'));
  end if;
  return 'processed';
end;
$$;

create function private.dispatch_stripe_event(e public.webhook_events) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_obj jsonb := e.payload #> '{data,object}';
begin
  case e.event_type
    when 'checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed' then
      return private.handle_checkout_session(e, v_obj);
    when 'checkout.session.expired' then
      return private.handle_checkout_expired(e, v_obj);
    when 'invoice.paid' then
      return private.handle_invoice_paid(e, v_obj);
    when 'invoice.payment_failed' then
      return private.handle_invoice_failed(e, v_obj, false);
    when 'invoice.payment_action_required' then
      return private.handle_invoice_failed(e, v_obj, true);
    when 'invoice.finalized', 'invoice.sent' then
      return private.handle_invoice_finalized(e, v_obj);
    when 'customer.subscription.created', 'customer.subscription.updated', 'customer.subscription.deleted' then
      return private.handle_subscription(e, v_obj);
    when 'charge.refunded' then
      return private.handle_charge_refunded(e, v_obj);
    when 'refund.created', 'refund.updated', 'refund.failed', 'charge.refund.updated' then
      return private.handle_refund(e, v_obj);
    when 'charge.dispute.created', 'charge.dispute.updated', 'charge.dispute.closed',
         'charge.dispute.funds_withdrawn', 'charge.dispute.funds_reinstated' then
      return private.handle_dispute(e, v_obj);
    when 'setup_intent.succeeded', 'setup_intent.setup_failed' then
      return private.handle_setup_intent(e, v_obj);
    when 'payment_method.detached', 'payment_method.automatically_updated' then
      return private.handle_payment_method(e, v_obj);
    else
      return 'ignored';
  end case;
end;
$$;

-- Server (secret key) only. Processing happens after the durable insert (04 §17 #4). Any
-- failure rolls back every effect of the attempt and leaves the event retryable (T-ARC-02,
-- T-ARC-06). Concurrent processing of one event is serialized by the row lock.
create function private.process_stripe_event(p_webhook_event_id bigint) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_evt public.webhook_events%rowtype;
  v_outcome text;
  v_status public.webhook_processing_status;
  v_reason text;
  v_message text;
  v_state text;
  v_project uuid;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  select * into v_evt from public.webhook_events where id = p_webhook_event_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if v_evt.processing_status in ('processed', 'ignored', 'quarantined') then
    return jsonb_build_object('ok', true, 'status', v_evt.processing_status, 'already', true);
  end if;
  begin
    v_outcome := private.dispatch_stripe_event(v_evt);
    -- A quarantine decision rolls back every effect the handler made before deciding, so a
    -- quarantined event never leaves a partial record (04 §11 rule 6). Only the project
    -- attribution is kept for the Owner's review.
    if v_outcome like 'quarantined:%' then
      select project_id into v_project from public.webhook_events where id = v_evt.id;
      raise exception using errcode = 'WPBQ1', message = v_outcome;
    end if;
  exception when sqlstate 'WPBQ1' then
    null; -- v_outcome and v_project survive the rollback of the handler's subtransaction
  when others then
    get stacked diagnostics v_message = message_text, v_state = returned_sqlstate;
    update public.webhook_events set processing_status = 'failed', attempts = attempts + 1,
      last_error = left(v_state || ': ' || v_message, 500) where id = v_evt.id;
    perform private.audit_financial('webhook.processing_failed', 'webhook_event', v_evt.id::text, null,
      jsonb_build_object('stripe_event_id', v_evt.stripe_event_id, 'sqlstate', v_state));
    return jsonb_build_object('ok', false, 'status', 'failed');
  end;
  if v_outcome like 'quarantined:%' then
    v_status := 'quarantined';
    v_reason := left(substr(v_outcome, 13), 200);
  else
    v_status := v_outcome::public.webhook_processing_status;
  end if;
  update public.webhook_events
     set processing_status = v_status, attempts = attempts + 1, quarantine_reason = v_reason,
         project_id = coalesce(v_project, project_id),
         processed_at = case when v_status in ('processed', 'ignored', 'quarantined') then now() end, last_error = null
   where id = v_evt.id
  returning * into v_evt;
  if v_status = 'quarantined' then
    perform private.audit_financial('webhook.quarantined', 'webhook_event', v_evt.id::text, v_evt.project_id,
      jsonb_build_object('stripe_event_id', v_evt.stripe_event_id, 'reason', v_reason));
    perform private.notify_owner('webhook.quarantined', 'webhook.quarantined:' || v_evt.stripe_event_id || ':1',
      v_evt.project_id, null, jsonb_build_object('webhook_event_id', v_evt.id));
  elsif v_status = 'processed' then
    perform private.audit_financial('webhook.processed', 'webhook_event', v_evt.id::text, v_evt.project_id,
      jsonb_build_object('stripe_event_id', v_evt.stripe_event_id, 'event_type', v_evt.event_type));
  end if;
  return jsonb_build_object('ok', true, 'status', v_status, 'reason', v_reason);
end;
$$;

-- Owner, fresh MFA: records the review of a quarantined event. Never changes payment state
-- (OI-19: no override creates a payment).
create function private.resolve_quarantined_event(p_webhook_event_id bigint, p_resolution text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
begin
  if not (private.is_owner() and private.mfa_is_fresh() and private.session_is_active()) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_resolution, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.webhook_events set quarantine_resolved_at = now(), quarantine_resolved_by = (select auth.uid()),
    quarantine_resolution = btrim(p_resolution)
   where id = p_webhook_event_id and processing_status = 'quarantined' and quarantine_resolved_at is null
  returning project_id into v_project;
  if not found then
    return private.fail('not_found');
  end if;
  -- B1: resolving records the Owner's review only. Nothing is reprocessed or posted; the
  -- gates are re-derived from all the evidence, so a reversal the event shows still blocks.
  perform private.audit_financial('quarantine.resolved', 'webhook_event', p_webhook_event_id::text, v_project,
    jsonb_build_object('gates', private.financial_gate_recheck(v_project)), p_resolution);
  return jsonb_build_object('ok', true, 'gates', private.financial_gate_recheck(v_project));
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. release.approved consumer and the final-balance obligation (04 §10; T-PAY-09, -17)
-- ---------------------------------------------------------------------------
-- Consumer contract (schema_version 1, emitted by WP-C): project_id set; subject_type
-- 'preview_release', subject_id = the approved release ID; payload.approval_id = the
-- client approval ID. Durable and idempotent per event; the obligation is unique per order
-- summary and per project, so replays, repeated approvals and later releases collapse.
create function private.consume_release_approved(p_domain_event_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_ev public.domain_events%rowtype;
  v_consumer constant text := 'wpb.final_balance_invoice';
  v_inserted integer;
  v_release uuid;
  v_approval uuid;
  v_agreement record;
  v_os public.order_summaries%rowtype;
  v_prices record;
  v_customer text;
  v_fbi public.final_balance_invoices%rowtype;
  v_auth public.payment_authorizations%rowtype;
  v_mode text;
  v_event bigint;
  v_outcome text;
  v_detail text;
begin
  insert into private.event_consumptions (consumer, domain_event_id) values (v_consumer, p_domain_event_id)
  on conflict do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted = 0 then
    return 'already_consumed';
  end if;
  select * into v_ev from public.domain_events where id = p_domain_event_id;
  v_release := private.try_uuid(v_ev.subject_id);
  v_approval := private.try_uuid(v_ev.payload ->> 'approval_id');

  if v_ev.event_type <> 'release.approved' or v_ev.project_id is null or v_release is null or v_approval is null then
    v_outcome := 'rejected'; v_detail := 'invalid_event';
  else
    select * into v_agreement from private.project_agreement_state(v_ev.project_id);
    if v_agreement.state <> 'effective' then
      v_outcome := 'rejected'; v_detail := 'agreement_not_effective';
    elsif not private.project_deposit_verified(v_ev.project_id) then
      v_outcome := 'rejected'; v_detail := 'deposit_not_verified';
    else
      select * into v_os from public.order_summaries where id = v_agreement.order_summary_id;
      select * into v_prices from private.verified_package_prices(v_os.package_key);
      select c.stripe_customer_id into v_customer from public.stripe_customers c
        join public.projects p on p.client_business_id = c.client_business_id where p.id = v_ev.project_id;
      if v_prices.balance_price_id is null or v_prices.balance_price_id <> v_os.balance_price_id
         or v_prices.balance_cents <> v_os.balance_cents then
        v_outcome := 'rejected'; v_detail := 'catalog_mismatch';
      elsif v_os.balance_cents <= 0 then
        v_outcome := 'rejected'; v_detail := 'no_balance_due';
      elsif v_customer is null then
        v_outcome := 'rejected'; v_detail := 'customer_missing';
      else
        -- 04 §10 (OI-74): automatic only while the authorization is active, decided under the
        -- authorization row lock that revocation and card detachment also take.
        select * into v_auth from public.payment_authorizations
         where project_id = v_ev.project_id and status <> 'revoked' for update;
        v_mode := case when v_auth.status = 'active' then 'automatic' else 'hosted_only' end;
        insert into public.final_balance_invoices (project_id, order_summary_id, acceptance_id, approval_id, release_id,
          source_domain_event_id, amount_cents, balance_price_id, stripe_customer_id, collection_mode,
          payment_authorization_id, default_payment_method_id)
        values (v_ev.project_id, v_os.id, v_agreement.acceptance_id, v_approval, v_release, v_ev.id, v_os.balance_cents,
          v_os.balance_price_id, v_customer, v_mode, v_auth.id,
          case when v_mode = 'automatic' then v_auth.stripe_payment_method_id end)
        on conflict do nothing
        returning * into v_fbi;
        if v_fbi.id is null then
          v_outcome := 'duplicate_obligation'; v_detail := 'obligation_exists';
        else
          v_outcome := 'created';
          perform private.new_outbound_request('final_balance_invoice_create', v_fbi.project_id, 'final_balance_invoice',
            v_fbi.id, 'wpb-final-balance-' || v_os.id::text || '-' || v_approval::text,
            private.final_balance_invoice_params(v_fbi, v_mode));
          v_event := private.emit_domain_event('payment.balance_due', v_fbi.project_id, 'final_balance_invoice', v_fbi.id::text,
            jsonb_build_object('order_summary_id', v_os.id, 'approval_id', v_approval, 'release_id', v_release),
            'payment.balance_due:' || v_fbi.id::text);
          perform private.audit_financial('balance.collection_authorized', 'final_balance_invoice', v_fbi.id::text,
            v_fbi.project_id, jsonb_build_object('approval_id', v_approval, 'release_id', v_release,
              'order_summary_id', v_os.id, 'amount_cents', v_fbi.amount_cents, 'collection_mode', v_mode,
              'payment_consent_id', v_auth.id));
        end if;
      end if;
    end if;
  end if;
  update private.event_consumptions set outcome = v_outcome, detail = v_detail
   where consumer = v_consumer and domain_event_id = p_domain_event_id;
  if v_outcome = 'rejected' then
    perform private.audit_financial('release_approval.rejected', 'domain_event', p_domain_event_id::text, v_ev.project_id,
      jsonb_build_object('detail', v_detail));
    perform private.notify_owner('payment.final_balance_blocked', 'payment.final_balance_blocked:' || p_domain_event_id::text || ':1',
      v_ev.project_id, null, jsonb_build_object('domain_event_id', p_domain_event_id));
  elsif v_outcome = 'duplicate_obligation' then
    perform private.audit_financial('release_approval.duplicate', 'domain_event', p_domain_event_id::text, v_ev.project_id);
  end if;
  return v_outcome;
end;
$$;

-- Server only: consumes every pending release.approved event, oldest first. Concurrent
-- runs skip events another run holds.
create function private.consume_release_approvals(p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_results jsonb := '[]'::jsonb;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  for v_id in
    select d.id from public.domain_events d
    where d.event_type = 'release.approved'
      and not exists (select 1 from private.event_consumptions c
                      where c.consumer = 'wpb.final_balance_invoice' and c.domain_event_id = d.id)
    order by d.id limit least(greatest(coalesce(p_limit, 50), 1), 500)
    for update of d skip locked
  loop
    v_results := v_results || jsonb_build_object('domain_event_id', v_id, 'outcome', private.consume_release_approved(v_id));
  end loop;
  return jsonb_build_object('ok', true, 'results', v_results);
end;
$$;

-- ---------------------------------------------------------------------------
-- 11. Scheduled jobs (server only)
-- ---------------------------------------------------------------------------
-- OI-26 / T-BIL-01, T-BIL-14: a hold only after the stored recovery deadline has passed.
create function private.evaluate_maintenance_recoveries() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_rec public.maintenance_recoveries%rowtype;
  v_hold uuid;
  v_count integer := 0;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  for v_rec in select * from public.maintenance_recoveries
                where status = 'in_recovery' and recovery_ends_at < now() for update skip locked loop
    v_hold := private.place_hold_internal(v_rec.project_id, 'maintenance_payment_hold', 'system', v_rec.id::text,
      'Maintenance payment recovery period ended unresolved');
    update public.maintenance_recoveries set status = 'hold_placed' where id = v_rec.id;
    perform private.notify_owner('billing.hold_review_required', 'billing.hold_review_required:' || v_rec.id::text || ':1',
      v_rec.project_id, null, jsonb_build_object('hold_id', v_hold));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create function private.advance_service_terminations() returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
  v_count integer := 0;
  v_event bigint;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  for v_t in select * from public.service_terminations
              where state = 'termination_authorized' and effective_cancellation_date <= private.local_date(now())
              for update skip locked loop
    update public.service_terminations set state = 'effective', became_effective_at = now() where id = v_t.id;
    v_event := private.emit_domain_event('subscription.termination_effective', v_t.project_id, 'service_termination',
      v_t.id::text, jsonb_build_object('m1_deadline', v_t.m1_deadline, 'm2_deadline', v_t.m2_deadline),
      'subscription.termination_effective:' || v_t.id::text);
    perform private.audit_financial(case when v_t.origin = 'client_cancellation' then 'cancellation.effective'
                                         else 'termination.effective' end,
      'service_termination', v_t.id::text, v_t.project_id);
    perform private.enqueue_notification('termination.milestones', 'termination.milestones:' || v_t.id::text || ':1',
      'termination.milestones', 1, v_t.project_id, v_event, private.project_client_user_ids(v_t.project_id), '{owner}',
      jsonb_build_object('termination_id', v_t.id), 'financial');
    perform private.audit_financial('cancellation.milestones_notified', 'service_termination', v_t.id::text, v_t.project_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Retries deferred and failed events through the same idempotent handler (04 §13 backfill).
create function private.retry_pending_webhook_events(p_limit integer default 100) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_id bigint;
  v_count integer := 0;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  for v_id in select id from public.webhook_events
               where processing_status in ('received', 'deferred', 'failed') and attempts < 25
               order by stripe_created_at, id limit least(greatest(coalesce(p_limit, 100), 1), 1000) loop
    perform private.process_stripe_event(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- One entry point per database job (04 §13; T-ARC-09): service-role only; single-flight (a
-- concurrent run of the same job is a recorded no-op, held by a transaction advisory lock);
-- idempotent (every effect is keyed, so a rerun changes nothing); audited with its result.
-- Binding these to a hosted scheduler is WP-D's (DEP-17).
create function private.run_billing_job(p_job text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_run uuid;
  v_result jsonb;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  if p_job not in ('maintenance_recovery', 'webhook_backfill', 'release_approvals', 'service_terminations',
                   'outbound_requests') then
    return private.fail('unknown_job');
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('wpb:job:' || p_job, 0)) then
    perform private.audit_financial('billing_job.skipped', 'billing_job', p_job, null, jsonb_build_object('reason', 'running'));
    return jsonb_build_object('ok', true, 'job', p_job, 'skipped', true);
  end if;
  insert into public.billing_job_runs (job, run_key) values (p_job, gen_random_uuid()::text) returning id into v_run;
  v_result := case p_job
    when 'maintenance_recovery' then jsonb_build_object('holds_placed', private.evaluate_maintenance_recoveries())
    when 'webhook_backfill' then jsonb_build_object('events_retried', private.retry_pending_webhook_events(100))
    when 'release_approvals' then jsonb_build_object('consumed',
      jsonb_array_length(private.consume_release_approvals(50) -> 'results'))
    when 'service_terminations' then jsonb_build_object('became_effective', private.advance_service_terminations())
    when 'outbound_requests' then jsonb_build_object('marked_ambiguous', private.mark_stale_outbound_requests()) end;
  update public.billing_job_runs set status = 'completed', completed_at = now(), result = v_result where id = v_run;
  perform private.audit_financial('billing_job.completed', 'billing_job', p_job, null,
    jsonb_build_object('run_id', v_run, 'result', v_result));
  return jsonb_build_object('ok', true, 'job', p_job, 'skipped', false, 'run_id', v_run, 'result', v_result);
end;
$$;

-- Row-based single-flight for the server-driven job that calls Stripe between database
-- calls (payment_method_lookups): a second concurrent start gets null. A run left running
-- for 15 minutes (a crashed worker) is closed so the next one can start.
create function private.begin_billing_job(p_job text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_run uuid;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  if p_job <> 'payment_method_lookups' then
    raise exception 'unknown server-driven job' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('wpb:job:' || p_job, 0));
  update public.billing_job_runs set status = 'completed', completed_at = now(), result = jsonb_build_object('abandoned', true)
   where job = p_job and status = 'running' and started_at < now() - interval '15 minutes';
  if exists (select 1 from public.billing_job_runs where job = p_job and status = 'running') then
    perform private.audit_financial('billing_job.skipped', 'billing_job', p_job, null, jsonb_build_object('reason', 'running'));
    return null;
  end if;
  insert into public.billing_job_runs (job, run_key) values (p_job, gen_random_uuid()::text) returning id into v_run;
  perform private.audit_financial('billing_job.started', 'billing_job', p_job, null, jsonb_build_object('run_id', v_run));
  return v_run;
end;
$$;

create function private.finish_billing_job(p_run_id uuid, p_result jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_job text;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  update public.billing_job_runs set status = 'completed', completed_at = now(), result = coalesce(p_result, '{}'::jsonb)
   where id = p_run_id and status = 'running' returning job into v_job;
  if v_job is null then
    return private.fail('not_found');
  end if;
  perform private.audit_financial('billing_job.completed', 'billing_job', v_job, null,
    jsonb_build_object('run_id', p_run_id, 'result', coalesce(p_result, '{}'::jsonb)));
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------------------------------------------------------------------------
-- 12. Owner financial controls (03 §4, §7, §12)
-- ---------------------------------------------------------------------------
create function private.owner_ok(p_fresh boolean) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_owner() and private.is_aal2() and private.session_is_active()
     and (not p_fresh or private.mfa_is_fresh());
$$;

-- Place dispute_risk_hold or owner_manual_hold (Owner only, with a reason).
create function private.place_billing_hold(p_project_id uuid, p_hold_type public.hold_type, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.owner_ok(false) then
    perform private.audit_financial('hold.placement_denied', 'project', p_project_id::text, p_project_id,
      jsonb_build_object('hold_type', p_hold_type));
    return private.fail('forbidden');
  end if;
  if p_hold_type not in ('dispute_risk_hold', 'owner_manual_hold') then
    return private.fail('hold_type_not_manual');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  if not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('not_found');
  end if;
  v_id := private.place_hold_internal(p_project_id, p_hold_type, 'owner', null, btrim(p_reason));
  if v_id is null then
    select id into v_id from public.billing_holds where project_id = p_project_id and hold_type = p_hold_type and cleared_at is null;
    return jsonb_build_object('ok', true, 'hold_id', v_id, 'existing', true);
  end if;
  return jsonb_build_object('ok', true, 'hold_id', v_id, 'existing', false);
end;
$$;

-- Manual holds: Owner with a reason. A system hold (maintenance_payment_hold) clears only on
-- verified recovery or as an Owner exception with fresh reauthentication (OI-26).
create function private.clear_billing_hold(p_hold_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hold public.billing_holds%rowtype;
begin
  select * into v_hold from public.billing_holds where id = p_hold_id for update;
  if not found or v_hold.cleared_at is not null then
    return private.fail('not_found');
  end if;
  if not private.owner_ok(v_hold.hold_type = 'maintenance_payment_hold') then
    perform private.audit_financial('hold.clear_denied', 'billing_hold', p_hold_id::text, v_hold.project_id);
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  perform private.clear_hold_internal(p_hold_id,
    case when v_hold.hold_type = 'maintenance_payment_hold' then 'owner_exception' else 'owner_clear' end, btrim(p_reason),
    jsonb_build_object('cleared_by_owner', true));
  if v_hold.hold_type = 'maintenance_payment_hold' then
    perform private.audit_financial('hold.exception_authorized', 'billing_hold', p_hold_id::text, v_hold.project_id,
      '{}'::jsonb, p_reason);
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

-- OI-46 stage 4: the Owner's review decision on an active maintenance_payment_hold.
create function private.decide_billing_hold_review(p_hold_id uuid, p_decision public.billing_hold_review_decision, p_reason text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_hold public.billing_holds%rowtype;
  v_termination uuid;
begin
  select * into v_hold from public.billing_holds where id = p_hold_id for update;
  if not found or v_hold.hold_type <> 'maintenance_payment_hold' or v_hold.cleared_at is not null then
    return private.fail('not_found');
  end if;
  if not private.owner_ok(p_decision <> 'continue_collection') then
    perform private.audit_financial('billing_hold.review_denied', 'billing_hold', p_hold_id::text, v_hold.project_id);
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  if p_decision = 'initiate_termination' then
    insert into public.service_terminations (project_id, origin, state, billing_hold_id, opened_by, reason)
    values (v_hold.project_id, 'billing_hold_review', 'under_owner_review', v_hold.id, (select auth.uid()), btrim(p_reason))
    on conflict do nothing returning id into v_termination;
    if v_termination is null then
      return private.fail('termination_already_active');
    end if;
    perform private.audit_financial('termination.review_opened', 'service_termination', v_termination::text, v_hold.project_id,
      '{}'::jsonb, p_reason);
  end if;
  insert into public.billing_hold_reviews (hold_id, decision, reason, decided_by)
  values (v_hold.id, p_decision, btrim(p_reason), (select auth.uid()));
  perform private.audit_financial('billing_hold.review_decided', 'billing_hold', v_hold.id::text, v_hold.project_id,
    jsonb_build_object('decision', p_decision), p_reason);
  if p_decision = 'authorize_exception' then
    perform private.clear_hold_internal(v_hold.id, 'owner_exception', btrim(p_reason), jsonb_build_object('review', true));
    perform private.audit_financial('hold.exception_authorized', 'billing_hold', v_hold.id::text, v_hold.project_id,
      '{}'::jsonb, p_reason);
  end if;
  return jsonb_build_object('ok', true, 'termination_id', v_termination);
end;
$$;

create function private.termination_deadlines(p_effective date, out m1 timestamptz, out m2 timestamptz, out version text)
language sql immutable set search_path = '' as $$
  -- 04 §15.1 / 02 §13.3: M1 12 business days, M2 60 calendar days, trigger date excluded.
  select private.end_of_local_day(private.add_business_days(p_effective, 12)),
         private.end_of_local_day(p_effective + 60), private.calendar_version();
$$;

-- OI-46 stage 5: the Owner records the termination, with reason, effective date and fresh
-- reauthentication. Repeated authorization is idempotent (T-BIL-16).
create function private.authorize_service_termination(p_termination_id uuid, p_effective_date date, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
  v_d record;
  v_event bigint;
begin
  if not private.owner_ok(true) then
    perform private.audit_financial('termination.authorization_denied', 'service_termination', p_termination_id::text, null);
    return private.fail('forbidden');
  end if;
  select * into v_t from public.service_terminations where id = p_termination_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if v_t.state <> 'under_owner_review' then
    if v_t.state in ('termination_authorized', 'effective', 'maintenance_ceased', 'offboarded', 'transferred') then
      return jsonb_build_object('ok', true, 'existing', true, 'm1_deadline', v_t.m1_deadline, 'm2_deadline', v_t.m2_deadline);
    end if;
    return private.fail('invalid_state');
  end if;
  if p_effective_date is null or nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  select * into v_d from private.termination_deadlines(p_effective_date);
  update public.service_terminations
     set state = 'termination_authorized', authorized_by = (select auth.uid()), authorized_at = now(),
         effective_cancellation_date = p_effective_date, m1_deadline = v_d.m1, m2_deadline = v_d.m2, calendar_version = v_d.version
   where id = v_t.id;
  v_event := private.emit_domain_event('subscription.termination_authorized', v_t.project_id, 'service_termination', v_t.id::text,
    jsonb_build_object('effective_cancellation_date', p_effective_date), 'subscription.termination_authorized:' || v_t.id::text);
  perform private.audit_financial('termination.authorized', 'service_termination', v_t.id::text, v_t.project_id,
    jsonb_build_object('effective_cancellation_date', p_effective_date, 'm1_deadline', v_d.m1, 'm2_deadline', v_d.m2), p_reason);
  perform private.enqueue_notification('termination.authorized', 'termination.authorized:' || v_t.id::text || ':1',
    'termination.authorized', 1, v_t.project_id, v_event, private.project_client_user_ids(v_t.project_id), '{owner}',
    jsonb_build_object('termination_id', v_t.id), 'financial');
  return jsonb_build_object('ok', true, 'existing', false, 'm1_deadline', v_d.m1, 'm2_deadline', v_d.m2);
end;
$$;

create function private.withdraw_service_termination(p_termination_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  select * into v_t from public.service_terminations where id = p_termination_id for update;
  if not found or v_t.state not in ('under_owner_review', 'termination_authorized') then
    return private.fail('invalid_state');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.service_terminations set state = 'withdrawn', withdrawn_at = now() where id = v_t.id;
  if v_t.cancellation_request_id is not null then
    update public.cancellation_requests set status = 'withdrawn' where id = v_t.cancellation_request_id and status = 'received';
  end if;
  perform private.audit_financial('termination.withdrawn', 'service_termination', v_t.id::text, v_t.project_id, '{}'::jsonb, p_reason);
  return jsonb_build_object('ok', true);
end;
$$;

-- 04 §15.1.1: a client member submits a cancellation request (idempotent while received).
create function private.submit_cancellation_request(p_project_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
  v_event bigint;
begin
  if v_uid is null or private.staff_role_of(v_uid) is not null or not private.is_active_user()
     or not private.session_is_active() or not private.is_project_member(p_project_id) then
    return private.fail('not_found');
  end if;
  select id into v_id from public.cancellation_requests where project_id = p_project_id and status = 'received';
  if v_id is not null then
    return jsonb_build_object('ok', true, 'cancellation_request_id', v_id, 'existing', true);
  end if;
  insert into public.cancellation_requests (project_id, channel, requested_by, request_date)
  values (p_project_id, 'portal', v_uid, now()) returning id into v_id;
  v_event := private.emit_domain_event('subscription.cancellation_requested', p_project_id, 'cancellation_request', v_id::text,
    '{}'::jsonb, 'subscription.cancellation_requested:' || v_id::text);
  perform private.audit_financial('cancellation.requested', 'cancellation_request', v_id::text, p_project_id,
    jsonb_build_object('channel', 'portal'));
  perform private.enqueue_notification('cancellation.received', 'cancellation.received:' || v_id::text || ':1',
    'cancellation.received', 1, p_project_id, v_event, private.project_client_user_ids(p_project_id), '{owner}',
    jsonb_build_object('cancellation_request_id', v_id), 'financial');
  return jsonb_build_object('ok', true, 'cancellation_request_id', v_id, 'existing', false);
exception
  when unique_violation then
    select id into v_id from public.cancellation_requests where project_id = p_project_id and status = 'received';
    return jsonb_build_object('ok', true, 'cancellation_request_id', v_id, 'existing', true);
end;
$$;

-- Written notice received by the Provider, recorded by the Owner with its request date.
create function private.record_written_cancellation_notice(p_project_id uuid, p_request_date timestamptz) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not private.owner_ok(false) then
    return private.fail('forbidden');
  end if;
  if p_request_date is null or p_request_date > now() or not exists (select 1 from public.projects where id = p_project_id) then
    return private.fail('invalid_input');
  end if;
  insert into public.cancellation_requests (project_id, channel, recorded_by, request_date)
  values (p_project_id, 'written_notice', (select auth.uid()), p_request_date)
  on conflict do nothing returning id into v_id;
  if v_id is null then
    return private.fail('request_already_open');
  end if;
  perform private.audit_financial('cancellation.requested', 'cancellation_request', v_id::text, p_project_id,
    jsonb_build_object('channel', 'written_notice'));
  return jsonb_build_object('ok', true, 'cancellation_request_id', v_id);
end;
$$;

-- 03 §4 "Confirm cancellation": Owner. Records the effective cancellation date separately
-- from the request date and computes M1 and M2 once (T-BIL-07, T-CAL-04, T-CAL-06).
create function private.confirm_cancellation(p_cancellation_request_id uuid, p_effective_date date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_req public.cancellation_requests%rowtype;
  v_d record;
  v_id uuid;
  v_event bigint;
begin
  if not private.owner_ok(false) then
    return private.fail('forbidden');
  end if;
  select * into v_req from public.cancellation_requests where id = p_cancellation_request_id for update;
  if not found then
    return private.fail('not_found');
  end if;
  if v_req.status = 'confirmed' then
    select id into v_id from public.service_terminations where cancellation_request_id = v_req.id;
    return jsonb_build_object('ok', true, 'termination_id', v_id, 'existing', true);
  end if;
  if v_req.status <> 'received' then
    return private.fail('invalid_state');
  end if;
  if p_effective_date is null or p_effective_date < private.local_date(v_req.request_date) then
    return private.fail('invalid_input');
  end if;
  select * into v_d from private.termination_deadlines(p_effective_date);
  insert into public.service_terminations (project_id, origin, state, cancellation_request_id, opened_by, reason,
    authorized_by, authorized_at, effective_cancellation_date, m1_deadline, m2_deadline, calendar_version)
  values (v_req.project_id, 'client_cancellation', 'termination_authorized', v_req.id, (select auth.uid()),
    'Client cancellation request', (select auth.uid()), now(), p_effective_date, v_d.m1, v_d.m2, v_d.version)
  on conflict do nothing returning id into v_id;
  if v_id is null then
    return private.fail('termination_already_active');
  end if;
  update public.cancellation_requests set status = 'confirmed', confirmed_by = (select auth.uid()), confirmed_at = now()
   where id = v_req.id;
  v_event := private.emit_domain_event('subscription.termination_authorized', v_req.project_id, 'service_termination', v_id::text,
    jsonb_build_object('effective_cancellation_date', p_effective_date), 'subscription.termination_authorized:' || v_id::text);
  perform private.audit_financial('cancellation.confirmed', 'cancellation_request', v_req.id::text, v_req.project_id,
    jsonb_build_object('effective_cancellation_date', p_effective_date, 'm1_deadline', v_d.m1, 'm2_deadline', v_d.m2));
  perform private.enqueue_notification('cancellation.confirmed', 'cancellation.confirmed:' || v_req.id::text || ':1',
    'cancellation.confirmed', 1, v_req.project_id, v_event, private.project_client_user_ids(v_req.project_id), '{owner}',
    jsonb_build_object('cancellation_request_id', v_req.id), 'financial');
  return jsonb_build_object('ok', true, 'termination_id', v_id, 'existing', false, 'm1_deadline', v_d.m1, 'm2_deadline', v_d.m2);
end;
$$;

create function private.record_termination_notice(p_termination_id uuid, p_notice_kind text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
begin
  if not private.owner_ok(false) then
    return private.fail('forbidden');
  end if;
  select * into v_t from public.service_terminations where id = p_termination_id;
  if not found or v_t.state not in ('termination_authorized', 'effective', 'maintenance_ceased') then
    return private.fail('invalid_state');
  end if;
  insert into public.termination_notices (termination_id, notice_kind, recorded_by)
  values (v_t.id, p_notice_kind, (select auth.uid())) on conflict do nothing;
  perform private.audit_financial('cancellation.notice_sent', 'service_termination', v_t.id::text, v_t.project_id,
    jsonb_build_object('notice_kind', p_notice_kind));
  return jsonb_build_object('ok', true);
exception
  when check_violation then return private.fail('invalid_input');
end;
$$;

-- T-BIL-17: rejected before M1. M1 and M2 are not enforced against production clients
-- until counsel-approved terms exist (04 §15.1; DEP-03), so production refuses.
create function private.record_maintenance_ceased(p_termination_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  if private.is_production() then
    return private.fail('legal_terms_pending');
  end if;
  select * into v_t from public.service_terminations where id = p_termination_id for update;
  if not found or v_t.state <> 'effective' then
    return private.fail('invalid_state');
  end if;
  if now() <= v_t.m1_deadline then
    perform private.audit_financial('cancellation.maintenance_cessation_rejected', 'service_termination', v_t.id::text, v_t.project_id);
    return private.fail('before_m1');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.service_terminations set state = 'maintenance_ceased', maintenance_ceased_at = now() where id = v_t.id;
  perform private.audit_financial('cancellation.maintenance_ceased', 'service_termination', v_t.id::text, v_t.project_id,
    '{}'::jsonb, p_reason);
  return jsonb_build_object('ok', true);
end;
$$;

-- T-BIL-17: rejected before M2 or without the required notices. Records the Owner's
-- deactivation decision; it never deletes data or calls a registrar (T-BIL-08, T-BIL-19).
create function private.record_services_deactivated(p_termination_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  if private.is_production() then
    return private.fail('legal_terms_pending');
  end if;
  select * into v_t from public.service_terminations where id = p_termination_id for update;
  if not found or v_t.state not in ('effective', 'maintenance_ceased') then
    return private.fail('invalid_state');
  end if;
  if now() <= v_t.m2_deadline then
    perform private.audit_financial('cancellation.deactivation_rejected', 'service_termination', v_t.id::text, v_t.project_id,
      jsonb_build_object('reason', 'before_m2'));
    return private.fail('before_m2');
  end if;
  if (select count(*) from public.termination_notices n where n.termination_id = v_t.id
        and n.notice_kind in ('milestones_and_responsibilities', 'm1_reached', 'm2_minus_30_days', 'm2_minus_7_days')) < 4 then
    perform private.audit_financial('cancellation.deactivation_rejected', 'service_termination', v_t.id::text, v_t.project_id,
      jsonb_build_object('reason', 'notices_missing'));
    return private.fail('notices_missing');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.service_terminations set state = 'offboarded', services_deactivated_at = now() where id = v_t.id;
  perform private.audit_financial('cancellation.services_deactivated', 'service_termination', v_t.id::text, v_t.project_id,
    '{}'::jsonb, p_reason);
  return jsonb_build_object('ok', true);
end;
$$;

create function private.record_service_transfer(p_termination_id uuid, p_reason text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_t public.service_terminations%rowtype;
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  select * into v_t from public.service_terminations where id = p_termination_id for update;
  if not found or v_t.state not in ('effective', 'maintenance_ceased') then
    return private.fail('invalid_state');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.service_terminations set state = 'transferred', transferred_at = now() where id = v_t.id;
  perform private.audit_financial('cancellation.transferred', 'service_termination', v_t.id::text, v_t.project_id, '{}'::jsonb, p_reason);
  return jsonb_build_object('ok', true);
end;
$$;

create function private.resolve_stripe_cancellation_exception(p_exception_id uuid, p_resolution text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  if not private.owner_ok(false) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_resolution, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.stripe_cancellation_exceptions set resolved_at = now(), resolved_by = (select auth.uid()),
    resolution = btrim(p_resolution) where id = p_exception_id and resolved_at is null;
  if not found then
    return private.fail('not_found');
  end if;
  perform private.audit_financial('stripe.cancellation_exception_resolved', 'stripe_cancellation_exception',
    p_exception_id::text, null, '{}'::jsonb, p_resolution);
  return jsonb_build_object('ok', true);
end;
$$;

-- 04 §15.2 and §15.2.1 rule 2c: Owner-only discretionary refund decision with a reason and
-- fresh MFA, recorded BEFORE the refund is issued. For a partial refund of the combined
-- initial charge the Owner records the per-line allocation, which must sum exactly to the
-- amount and respect each line's remaining amount. The refund itself is a Tier 3 Owner
-- action in Stripe that must reference the decision ID; only its webhook posts the refund.
create function private.record_refund_decision(p_project_id uuid, p_amount_cents bigint, p_reason text,
  p_lines jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_entry bigint;
  v_key text;
  v_line jsonb;
  v_ob public.payment_obligations%rowtype;
  v_sum bigint := 0;
begin
  if not private.owner_ok(true) then
    perform private.audit_financial('refund.decision_denied', 'project', p_project_id::text, p_project_id);
    return private.fail('forbidden');
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 or nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('invalid_input');
  end if;
  if p_lines is not null then
    if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 1 and 3 then
      return private.fail('invalid_input');
    end if;
    for v_line in select * from jsonb_array_elements(p_lines) loop
      select * into v_ob from public.payment_obligations
       where id = private.try_uuid(v_line ->> 'obligation_id') and project_id = p_project_id;
      if not found or jsonb_typeof(v_line -> 'amount_cents') <> 'number'
         or (v_line ->> 'amount_cents')::bigint <= 0
         or (v_line ->> 'amount_cents')::bigint > private.obligation_net_cents(v_ob.id)
         or (v_key is not null and v_key <> v_ob.charge_key) then
        return private.fail('invalid_allocation');
      end if;
      v_key := v_ob.charge_key;
      v_sum := v_sum + (v_line ->> 'amount_cents')::bigint;
    end loop;
    if v_sum <> p_amount_cents then
      return private.fail('allocation_must_equal_amount');
    end if;
  end if;
  if p_amount_cents > (select coalesce(sum(private.obligation_net_cents(o.id)), 0) from public.payment_obligations o
                        where o.project_id = p_project_id) then
    return private.fail('exceeds_collected');
  end if;
  insert into public.refund_decisions (project_id, charge_key, amount_cents, reason, decided_by)
  values (p_project_id, v_key, p_amount_cents, btrim(p_reason), (select auth.uid())) returning id into v_id;
  if p_lines is not null then
    insert into public.refund_decision_lines (refund_decision_id, obligation_id, amount_cents)
    select v_id, (l ->> 'obligation_id')::uuid, (l ->> 'amount_cents')::bigint from jsonb_array_elements(p_lines) l;
  end if;
  insert into public.ledger_entries (project_id, entry_type, amount_cents, service_category, source, refund_decision_id,
    actor_user_id, reason, dedupe_key)
  values (p_project_id, 'refund_discretionary', 0, 'development', 'owner', v_id, (select auth.uid()), btrim(p_reason),
    'refund_decision:' || v_id::text)
  returning id into v_entry;
  perform private.audit_financial('refund.decision_recorded', 'refund_decision', v_id::text, p_project_id,
    jsonb_build_object('amount_cents', p_amount_cents, 'ledger_entry_id', v_entry, 'charge_key', v_key,
      'lines', coalesce(p_lines, '[]'::jsonb)), p_reason);
  return jsonb_build_object('ok', true, 'refund_decision_id', v_id);
exception
  when unique_violation then return private.fail('invalid_allocation');
end;
$$;

-- 04 §15.2.1 rule 6: Owner reconciliation of a charge's holding account. Tier 3 decision,
-- fresh MFA and a reason; immutable record and audit; append-only reclassification entries
-- that balance exactly (the holding entry and the line entries sum to zero) and keep every
-- obligation between zero and its original amount (rule 4).
create function private.reconcile_holding_reversal(p_project_id uuid, p_charge_key text, p_lines jsonb, p_reason text)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_balance bigint;
  v_line jsonb;
  v_ob public.payment_obligations%rowtype;
  v_sum bigint := 0;
  v_amount bigint;
  v_id uuid;
  v_uid uuid := (select auth.uid());
begin
  if not private.owner_ok(true) then
    perform private.audit_financial('reversal.reconciliation_denied', 'charge', left(p_charge_key, 200), p_project_id);
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_reason, '')), '') is null then
    return private.fail('reason_required');
  end if;
  if not exists (select 1 from public.payment_obligations where charge_key = p_charge_key and project_id = p_project_id) then
    return private.fail('not_found');
  end if;
  perform pg_advisory_xact_lock(hashtextextended('wpb:charge:' || p_charge_key, 0));
  v_balance := private.holding_balance_cents(p_charge_key);
  if v_balance = 0 then
    return private.fail('nothing_to_reconcile');
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) not between 1 and 3 then
    return private.fail('invalid_input');
  end if;
  for v_line in select * from jsonb_array_elements(p_lines) loop
    select * into v_ob from public.payment_obligations
     where id = private.try_uuid(v_line ->> 'obligation_id') and charge_key = p_charge_key;
    if not found or jsonb_typeof(v_line -> 'amount_cents') <> 'number' or (v_line ->> 'amount_cents')::bigint = 0 then
      return private.fail('invalid_allocation');
    end if;
    v_amount := (v_line ->> 'amount_cents')::bigint;
    if private.obligation_net_cents(v_ob.id) + v_amount not between 0 and v_ob.original_cents then
      return private.fail('allocation_exceeds_limit');
    end if;
    v_sum := v_sum + v_amount;
  end loop;
  if v_sum <> v_balance then
    return private.fail('allocation_must_balance');
  end if;
  insert into public.reversal_reconciliations (project_id, charge_key, holding_balance_cents, lines, reason, reconciled_by)
  values (p_project_id, p_charge_key, v_balance, p_lines, btrim(p_reason), v_uid) returning id into v_id;
  insert into public.ledger_entries (project_id, entry_type, amount_cents, service_category, source, holding_charge_key,
    actor_user_id, reason, dedupe_key)
  values (p_project_id, 'reclassification', -v_balance, null, 'owner', p_charge_key, v_uid, btrim(p_reason),
    'reclass:' || v_id::text || ':holding');
  for v_line in select * from jsonb_array_elements(p_lines) loop
    select * into v_ob from public.payment_obligations where id = (v_line ->> 'obligation_id')::uuid;
    insert into public.ledger_entries (project_id, order_summary_id, entry_type, amount_cents, service_category, source,
      obligation_id, actor_user_id, reason, dedupe_key)
    values (p_project_id, v_ob.order_summary_id, 'reclassification', (v_line ->> 'amount_cents')::bigint,
      v_ob.service_category, 'owner', v_ob.id, v_uid, btrim(p_reason), 'reclass:' || v_id::text || ':' || v_ob.id::text);
  end loop;
  perform private.audit_financial('reversal.reconciled', 'reversal_reconciliation', v_id::text, p_project_id,
    jsonb_build_object('charge_key', p_charge_key, 'holding_balance_cents', v_balance, 'lines', p_lines), p_reason);
  return jsonb_build_object('ok', true, 'reversal_reconciliation_id', v_id);
end;
$$;

-- 04 §15.4 (T-ARC-10): an evidence package compiled only from authoritative records (Owner
-- only). WP-B's records (acceptance and version hash, order summaries, ledger, payment
-- authorization history) plus WP-C's evidence interface in full: for a dispute on the
-- final-balance charge, the exact release whose approval made the balance due; otherwise
-- every release of the project. Nothing is altered or synthesized.
create function private.dispute_evidence_package(p_dispute_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_d public.disputes%rowtype;
  v_link private.stripe_payment_links%rowtype;
  v_release uuid;
begin
  if not private.owner_ok(false) then
    return private.fail('forbidden');
  end if;
  select * into v_d from public.disputes where stripe_dispute_id = p_dispute_id;
  if not found then
    return private.fail('not_found');
  end if;
  select * into v_link from private.stripe_payment_links where stripe_ref = v_d.stripe_charge_ref;
  if v_link.kind = 'final_balance' then
    select f.release_id into v_release from public.final_balance_invoices f where f.id = v_link.domain_record_id;
  end if;
  return jsonb_build_object('ok', true,
    'dispute', to_jsonb(v_d),
    'charge_key', private.link_charge_key(v_link),
    'acceptances', (select coalesce(jsonb_agg(to_jsonb(a) order by a.accepted_at), '[]'::jsonb)
                    from public.agreement_acceptances a where a.project_id = v_d.project_id),
    'agreement_versions', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'version_label', v.version_label,
                             'text_sha256', v.text_sha256, 'is_test_fixture', v.is_test_fixture)), '[]'::jsonb)
                           from public.agreement_versions v where v.id in (
                             select a.agreement_version_id from public.agreement_acceptances a where a.project_id = v_d.project_id)),
    'order_summaries', (select coalesce(jsonb_agg(to_jsonb(o) order by o.revision), '[]'::jsonb)
                        from public.order_summaries o where o.project_id = v_d.project_id),
    'payment_authorizations', (select coalesce(jsonb_agg(to_jsonb(pa) order by pa.created_at), '[]'::jsonb)
                               from public.payment_authorizations pa where pa.project_id = v_d.project_id),
    'payment_authorization_events', (select coalesce(jsonb_agg(to_jsonb(pe) order by pe.id), '[]'::jsonb)
                                     from public.payment_authorization_events pe where pe.project_id = v_d.project_id),
    'final_balance_invoices', (select coalesce(jsonb_agg(to_jsonb(f) order by f.created_at), '[]'::jsonb)
                               from public.final_balance_invoices f where f.project_id = v_d.project_id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('entry_type', l.entry_type, 'amount_cents', l.amount_cents,
                 'service_category', l.service_category, 'obligation_id', l.obligation_id,
                 'holding_charge_key', l.holding_charge_key, 'posted_at', l.posted_at,
                 'stripe_object_id', l.stripe_object_id) order by l.id), '[]'::jsonb)
               from public.ledger_entries l where l.project_id = v_d.project_id),
    'fulfillment', private.wpc_dispute_evidence(v_d.project_id, v_release));
end;
$$;
-- Daily reconciliation entry point (04 §13; T-ARC-09): service-role only, single-flight and
-- idempotent per run key (default: today's America/Detroit date). Returns null when a run
-- with that key exists or is in progress; the caller then does nothing.
create function private.start_reconciliation_run(p_source text, p_run_key text default null) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_key text := coalesce(nullif(btrim(coalesce(p_run_key, '')), ''), private.local_date(now())::text);
  v_job uuid;
  v_id uuid;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  insert into public.billing_job_runs (job, run_key) values ('reconciliation', v_key)
  on conflict (job, run_key) do nothing returning id into v_job;
  if v_job is null then
    perform private.audit_financial('billing_job.skipped', 'billing_job', 'reconciliation', null,
      jsonb_build_object('run_key', v_key));
    return null;
  end if;
  insert into public.reconciliation_runs (source, run_key, billing_job_run_id) values (p_source, v_key, v_job)
  returning id into v_id;
  perform private.audit_financial('billing_job.started', 'billing_job', 'reconciliation', null,
    jsonb_build_object('run_key', v_key, 'reconciliation_run_id', v_id));
  return v_id;
end;
$$;
-- p_stripe: {"charges_cents": n, "refunds_cents": n, "open_disputes": n}, summed by the
-- server from Stripe invoices, charges, refunds and disputes for the project.
create function private.record_project_reconciliation(p_run_id uuid, p_project_id uuid, p_stripe jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_charges bigint;
  v_refunds bigint;
  v_os public.order_summaries%rowtype;
  v_deposit bigint;
  v_balance bigint;
  v_fbi_amount bigint;
  v_open bigint;
  v_count integer := 0;
  v_kind text;
  v_expected bigint;
  v_observed bigint;
  v_obj jsonb;
  v_charge_key text;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  if not exists (select 1 from public.reconciliation_runs where id = p_run_id and completed_at is null) then
    raise exception 'unknown or completed reconciliation run' using errcode = '22023';
  end if;
  select coalesce(sum(amount_cents) filter (where entry_type in ('deposit_charge', 'maintenance_charge', 'balance_charge')), 0),
         coalesce(-sum(amount_cents) filter (where entry_type = 'refund'), 0),
         coalesce(sum(amount_cents) filter (where entry_type = 'deposit_charge'), 0),
         coalesce(sum(amount_cents) filter (where entry_type = 'balance_charge'), 0)
    into v_charges, v_refunds, v_deposit, v_balance
  from public.ledger_entries where project_id = p_project_id;
  select count(*) into v_open from public.disputes where project_id = p_project_id and private.dispute_is_open(status);
  select * into v_os from public.order_summaries where project_id = p_project_id and status = 'presented';
  select amount_cents into v_fbi_amount from public.final_balance_invoices where project_id = p_project_id and status = 'paid';

  for v_kind, v_expected, v_observed in
    select 'charges_total', v_charges, (p_stripe ->> 'charges_cents')::bigint
    union all select 'refunds_total', v_refunds, (p_stripe ->> 'refunds_cents')::bigint
    union all select 'disputes_open', v_open, (p_stripe ->> 'open_disputes')::bigint
    union all select 'deposit_snapshot', v_os.deposit_cents::bigint, nullif(v_deposit, 0)
    union all select 'balance_snapshot', v_fbi_amount, nullif(v_balance, 0)
  loop
    if v_kind in ('deposit_snapshot', 'balance_snapshot') and (v_observed is null or v_expected is null) then
      continue;
    end if;
    if v_observed is distinct from v_expected then
      insert into public.reconciliation_mismatches (run_id, project_id, kind, expected_cents, observed_cents)
      values (p_run_id, p_project_id, v_kind, v_expected, v_observed);
      v_count := v_count + 1;
    end if;
  end loop;
  -- B1: every refund and dispute Stripe holds for this customer that WP-B has not recorded
  -- (its event never arrived, was deferred, or could not be attributed) is attributed through
  -- its charge and becomes a blocking item. One item per object state; nothing is posted.
  for v_obj in
    select r || jsonb_build_object('object', 'refund') from jsonb_array_elements(
      case when jsonb_typeof(p_stripe -> 'refunds') = 'array' then p_stripe -> 'refunds' else '[]'::jsonb end) r
    union all
    select d || jsonb_build_object('object', 'dispute') from jsonb_array_elements(
      case when jsonb_typeof(p_stripe -> 'disputes') = 'array' then p_stripe -> 'disputes' else '[]'::jsonb end) d
  loop
    if (v_obj ->> 'object' = 'refund' and exists (select 1 from public.refunds where stripe_refund_id = v_obj ->> 'id'))
       or (v_obj ->> 'object' = 'dispute' and exists (select 1 from public.disputes where stripe_dispute_id = v_obj ->> 'id')) then
      continue;
    end if;
    select case when count(distinct private.link_charge_key(l)) = 1 then min(private.link_charge_key(l)) end
      into v_charge_key
      from private.stripe_payment_links l
     where l.project_id = p_project_id
       and (l.stripe_ref in (v_obj ->> 'charge', v_obj ->> 'payment_intent') or l.stripe_invoice_id = v_obj ->> 'invoice');
    insert into public.reconciliation_mismatches (run_id, project_id, kind, charge_key, stripe_object_id, observed_status,
      observed_cents)
    values (p_run_id, p_project_id, case when v_obj ->> 'object' = 'refund' then 'unmatched_refund' else 'unmatched_dispute' end,
      v_charge_key, v_obj ->> 'id', coalesce(substring(v_obj ->> 'status' from '^[a-z_]{1,40}$'), 'unknown'), private.try_cents(v_obj -> 'amount'))
    on conflict (stripe_object_id, observed_status) where stripe_object_id is not null do nothing;
    if found then
      v_count := v_count + 1;
    end if;
  end loop;
  update public.reconciliation_runs set projects_checked = projects_checked + 1, mismatch_count = mismatch_count + v_count
   where id = p_run_id;
  if v_count > 0 then
    perform private.audit_financial('reconciliation.mismatch', 'reconciliation_run', p_run_id::text, p_project_id,
      jsonb_build_object('mismatches', v_count));
    perform private.notify_owner('reconciliation.mismatch', 'reconciliation.mismatch:' || p_run_id::text || ':' || p_project_id::text,
      p_project_id, null, jsonb_build_object('run_id', p_run_id));
  end if;
  return v_count;
end;
$$;

create function private.complete_reconciliation_run(p_run_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_run public.reconciliation_runs%rowtype;
begin
  if not private.caller_is_service_role() then
    raise exception 'server only' using errcode = '42501';
  end if;
  update public.reconciliation_runs set completed_at = now() where id = p_run_id and completed_at is null returning * into v_run;
  if not found then
    return private.fail('not_found');
  end if;
  update public.billing_job_runs set status = 'completed', completed_at = now(),
    result = jsonb_build_object('projects_checked', v_run.projects_checked, 'mismatches', v_run.mismatch_count)
   where id = v_run.billing_job_run_id;
  perform private.audit_financial('reconciliation.completed', 'reconciliation_run', p_run_id::text, null,
    jsonb_build_object('projects_checked', v_run.projects_checked, 'mismatches', v_run.mismatch_count, 'source', v_run.source));
  return jsonb_build_object('ok', true, 'projects_checked', v_run.projects_checked, 'mismatches', v_run.mismatch_count);
end;
$$;

create function private.resolve_reconciliation_mismatch(p_mismatch_id uuid, p_resolution text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_project uuid;
begin
  if not private.owner_ok(true) then
    return private.fail('forbidden');
  end if;
  if nullif(btrim(coalesce(p_resolution, '')), '') is null then
    return private.fail('reason_required');
  end if;
  update public.reconciliation_mismatches set resolved_at = now(), resolved_by = (select auth.uid()),
    resolution = btrim(p_resolution) where id = p_mismatch_id and resolved_at is null
  returning project_id into v_project;
  if not found then
    return private.fail('not_found');
  end if;
  -- B1: as for quarantine, a resolution is a review record; the gates are re-derived.
  perform private.audit_financial('reconciliation.mismatch_resolved', 'reconciliation_mismatch', p_mismatch_id::text, v_project,
    jsonb_build_object('gates', private.financial_gate_recheck(v_project)), p_resolution);
  return jsonb_build_object('ok', true, 'gates', private.financial_gate_recheck(v_project));
end;
$$;

-- ---------------------------------------------------------------------------
-- 14. The financial gate interface (01 §7; 06 §2 G1, G2, G4, G8; OI-71). Additive change:
--     two attributes for G1, contract_version 2, implemented = true.
-- ---------------------------------------------------------------------------
alter type private.project_financial_status
  add attribute agreement_state public.agreement_state,
  add attribute agreement_effective boolean,
  -- 04 §8.1 (OI-74): WP-C's intake precondition reads payment_authorization_ready.
  add attribute payment_authorization_ready boolean,
  add attribute payment_authorization_state text;

-- ---------------------------------------------------------------------------
-- 14A. Financial-integrity anomalies (B1: fail closed)
-- ---------------------------------------------------------------------------
-- Every unresolved anomaly blocks the payment gate of the charge it concerns: G2 for the
-- initial charge, G4 for the final-balance charge, both when the charge cannot be told. A
-- maintenance renewal charge blocks neither (its recovery is the maintenance hold, 04 §14).
-- Each anomaly is resolved only through an existing Owner-only, audited function. Resolving
-- records a review and nothing else: G2 and G4 are always re-derived from all the evidence.

-- The gates a charge (or a set of candidate charges) belongs to. Unknown or conflicting
-- attribution fails both.
create function private.charge_kind_gates(p_kinds text[]) returns text[]
language sql immutable set search_path = '' as $$
  select case
    when coalesce(cardinality(p_kinds), 0) <> 1 then array['G2', 'G4']
    when p_kinds[1] = 'initial' then array['G2']
    when p_kinds[1] = 'final_balance' then array['G4']
    when p_kinds[1] = 'renewal' then array[]::text[]
    else array['G2', 'G4'] end;
$$;

create function private.charge_key_gates(p_charge_key text) returns text[]
language sql immutable set search_path = '' as $$
  select private.charge_kind_gates(case when p_charge_key ~ '^(initial|renewal|final_balance):'
                                        then array[split_part(p_charge_key, ':', 1)] end);
$$;

-- The charge kinds a Stripe object references, through the recorded payment links.
create function private.object_charge_kinds(p_project_id uuid, p_refs text[], p_invoice text) returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct l.kind order by l.kind), '{}')
    from private.stripe_payment_links l
   where l.project_id = p_project_id and (l.stripe_ref = any (coalesce(p_refs, '{}')) or l.stripe_invoice_id = p_invoice);
$$;

-- The charge kinds a stored, verified event concerns ('{}' when it cannot be told).
create function private.event_charge_kinds(e public.webhook_events) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare
  o jsonb := e.payload #> '{data,object}';
  v_type text := e.payload #>> '{data,object,object}';
begin
  if e.project_id is null then
    return '{}';
  end if;
  if v_type in ('refund', 'dispute') then
    return private.object_charge_kinds(e.project_id, array[o ->> 'charge', o ->> 'payment_intent'], null);
  elsif v_type = 'charge' then
    return private.object_charge_kinds(e.project_id, array[o ->> 'id', o ->> 'payment_intent'], o ->> 'invoice');
  elsif v_type = 'checkout.session' then
    if o ->> 'mode' = 'setup' then
      return array['final_balance']; -- recovery of the final-balance authorization (04 §8.1)
    end if;
    if exists (select 1 from public.checkout_sessions c where c.project_id = e.project_id
                 and (c.stripe_checkout_session_id = o ->> 'id' or c.id = private.try_uuid(o #>> '{metadata,checkout_record_id}'))) then
      return array['initial'];
    end if;
    return '{}';
  elsif v_type = 'invoice' then
    return (select coalesce(array_agg(distinct k order by k), '{}') from (
      select 'final_balance' k from public.final_balance_invoices f where f.project_id = e.project_id
         and (f.stripe_invoice_id = o ->> 'id' or f.id = private.try_uuid(o #>> '{metadata,final_balance_invoice_id}'))
      union all select l.kind from private.stripe_payment_links l where l.project_id = e.project_id and l.stripe_invoice_id = o ->> 'id'
      union all select 'initial' where o ->> 'billing_reason' = 'subscription_create'
      union all select 'renewal' where o ->> 'billing_reason' = 'subscription_cycle') s);
  elsif v_type in ('setup_intent', 'payment_method') then
    return array['final_balance'];
  end if;
  return '{}';
end;
$$;

-- Every observation of a refund or dispute of a project: from verified events in any
-- processing state (including quarantined, deferred and failed ones) and from the daily
-- reconciliation. One row per observation.
create function private.reversal_observations(p_project_id uuid)
returns table (object_id text, object_kind text, status text, gates text[], observed_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select o ->> 'id', o ->> 'object', o ->> 'status',
         private.charge_kind_gates(private.object_charge_kinds(w.project_id, array[o ->> 'charge', o ->> 'payment_intent'], null)),
         w.stripe_created_at
    from public.webhook_events w
   cross join lateral (
     select w.payload #> '{data,object}' as o where w.payload #>> '{data,object,object}' in ('refund', 'dispute')
     union all
     select r || jsonb_build_object('charge', w.payload #>> '{data,object,id}')
       from jsonb_array_elements(case when w.payload #>> '{data,object,object}' = 'charge'
                                           and jsonb_typeof(w.payload #> '{data,object,refunds,data}') = 'array'
                                      then w.payload #> '{data,object,refunds,data}' else '[]'::jsonb end) r) x
   where w.project_id = p_project_id and w.processing_status <> 'ignored' and o ->> 'id' is not null
  union all
  select m.stripe_object_id, case when m.kind = 'unmatched_refund' then 'refund' else 'dispute' end, m.observed_status,
         private.charge_key_gates(m.charge_key), m.detected_at
    from public.reconciliation_mismatches m
   where m.project_id = p_project_id and m.kind in ('unmatched_refund', 'unmatched_dispute');
$$;

-- A reversal Stripe reports as in effect (refund succeeded; dispute funds withdrawn) whose
-- latest observation is still in effect and which the ledger has not posted. It blocks its
-- charge's gate whatever any review says: only a posted reversal (which the gates already
-- count) or a later Stripe observation (refund failed, dispute won) ends it.
create function private.unposted_reversals(p_project_id uuid) returns table (object_id text, gates text[])
language sql stable security definer set search_path = '' as $$
  select l.object_id, l.gates
    from (select distinct on (r.object_id) r.*
            from private.reversal_observations(p_project_id) r
           order by r.object_id, r.observed_at desc,
                    -- On a tie, the observation that blocks wins (fail closed).
                    (r.status in ('succeeded', 'needs_response', 'under_review', 'lost')) desc) l
   where ((l.object_kind = 'refund' and l.status = 'succeeded')
          or (l.object_kind = 'dispute' and l.status in ('needs_response', 'under_review', 'lost')))
     and not exists (select 1 from public.ledger_entries e where e.project_id = p_project_id
                       and e.stripe_object_id = l.object_id and e.entry_type in ('refund', 'dispute_opened'));
$$;

-- The unresolved anomalies of a project and the gates each blocks (Owner-only detail).
create function private.project_financial_anomalies(p_project_id uuid) returns table (kind text, gates text[])
language sql stable security definer set search_path = '' as $$
  -- 1. Quarantined events, attributed through the charge they concern.
  select 'quarantined_event', private.charge_kind_gates(private.event_charge_kinds(w))
    from public.webhook_events w
   where w.project_id = p_project_id and w.processing_status = 'quarantined' and w.quarantine_resolved_at is null
  union all
  -- 2. Open reconciliation items.
  select 'reconciliation_mismatch', case
           when m.kind = 'deposit_snapshot' then array['G2']
           when m.kind in ('balance_snapshot', 'charged_after_halt') then array['G4']
           when m.kind in ('unmatched_refund', 'unmatched_dispute') then private.charge_key_gates(m.charge_key)
           else array['G2', 'G4'] end
    from public.reconciliation_mismatches m
   where m.project_id = p_project_id and m.resolved_at is null
  union all
  -- 3. Ambiguous outbound requests, by the charge their record belongs to.
  select 'ambiguous_request', case
           when o.purpose = 'checkout_session_create' then array['G2']
           when o.purpose in ('final_balance_invoice_create', 'final_balance_invoice_disable_auto', 'recovery_session_create')
             then array['G4']
           else array['G2', 'G4'] end
    from public.outbound_stripe_requests o
   where o.project_id = p_project_id and o.status = 'ambiguous'
  union all
  -- 4. A failed automatic-collection stop; already_paid alone is not an anomaly.
  select 'automatic_stop_failed', array['G4']
    from public.outbound_stripe_requests o
   where o.project_id = p_project_id and o.purpose = 'final_balance_invoice_disable_auto' and o.status = 'failed'
     and coalesce(o.error_code, '') <> 'already_paid'
  union all
  -- 5. A charge after halted collection that the Owner has not reviewed (its item resolved).
  select 'charged_after_halt', array['G4']
    from public.final_balance_invoices f
   where f.project_id = p_project_id and f.charged_after_halt
     and not exists (select 1 from public.reconciliation_mismatches m where m.kind = 'charged_after_halt'
                       and m.charge_key = 'final_balance:' || f.id::text and m.resolved_at is not null)
  union all
  -- 6. Reversals Stripe reports that the ledger has not posted.
  select 'unposted_reversal', u.gates from private.unposted_reversals(p_project_id) u;
$$;

create function private.gate_anomalies(p_project_id uuid, p_gate text) returns text[]
language sql stable security definer set search_path = '' as $$
  select coalesce(array_agg(distinct a.kind order by a.kind), '{}')
    from private.project_financial_anomalies(p_project_id) a where p_gate = any (a.gates);
$$;

-- The fresh evaluation an Owner resolution returns and audits: G2 and G4 re-derived from all
-- the evidence, and the anomaly kinds still blocking each (no amounts, no identifiers).
create function private.financial_gate_recheck(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v private.project_financial_status;
begin
  if p_project_id is null then
    return null;
  end if;
  v := private.project_financial_status(p_project_id);
  return jsonb_build_object('G2', v.deposit_verified, 'G4', v.balance_verified_or_settled,
    'blocking_anomalies', v.evidence -> 'blocking_anomalies');
end;
$$;

-- Owner intervention items for a project (Owner-only detail; Admin sees the boolean).
create function private.project_owner_intervention_required(p_project_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.webhook_events w where w.project_id = p_project_id
                   and w.processing_status = 'quarantined' and w.quarantine_resolved_at is null)
      or exists (select 1 from public.reconciliation_mismatches m where m.project_id = p_project_id and m.resolved_at is null)
      or exists (select 1 from public.disputes d where d.project_id = p_project_id and private.dispute_is_open(d.status))
      or exists (select 1 from public.billing_holds h where h.project_id = p_project_id and h.cleared_at is null
                   and h.hold_type = 'maintenance_payment_hold'
                   and not exists (select 1 from public.billing_hold_reviews r where r.hold_id = h.id))
      or exists (select 1 from public.stripe_cancellation_exceptions x where x.project_id = p_project_id and x.resolved_at is null)
      or exists (select 1 from public.outbound_stripe_requests o where o.project_id = p_project_id and o.status = 'ambiguous')
      or exists (select 1 from public.outbound_stripe_requests o where o.project_id = p_project_id
                   and o.purpose = 'final_balance_invoice_disable_auto' and o.status = 'failed'
                   and coalesce(o.error_code, '') <> 'already_paid')
      or exists (select 1 from public.final_balance_invoices f where f.project_id = p_project_id
                   and f.status = 'creation_failed')
      or exists (select 1 from private.project_financial_anomalies(p_project_id))
      or exists (select 1 from public.refunds r where r.project_id = p_project_id and r.status = 'succeeded' and r.refund_decision_id is null)
      or exists (select 1 from public.payment_obligations o where o.project_id = p_project_id
                   and private.holding_balance_cents(o.charge_key) <> 0)
      or exists (select 1 from public.payment_authorizations a where a.project_id = p_project_id
                   and a.status = 'revoked' and a.revocation_reviewed_at is null)
      or exists (select 1 from public.service_terminations t where t.project_id = p_project_id and t.state = 'under_owner_review')
      or exists (select 1 from private.event_consumptions c join public.domain_events d on d.id = c.domain_event_id
                   where d.project_id = p_project_id and c.outcome = 'rejected'
                     and not exists (select 1 from public.final_balance_invoices f where f.project_id = p_project_id));
$$;

-- No role may execute this; the single gate evaluator (WP-C) calls it as a definer.
-- Contract version 3 (OI-71 rule): G1 (agreement), G2 (deposit, failing on any unresolved
-- reversal of the initial charge), G4 (balance, failing on any unresolved reversal of the
-- final-balance charge), WP-B holds, and the payment authorization WP-C's intake reads.
-- Evidence carries no amounts and no restricted record identifiers (OI-72).
create or replace function private.project_financial_status(p_project_id uuid)
returns private.project_financial_status
language plpgsql stable security definer set search_path = '' as $$
declare
  v_agreement record;
  v_deposit public.deposit_state;
  v_balance public.final_balance_state;
  v_holds public.hold_type[];
  v_digest text;
  v_auth_state text;
  v_g2 text[];
  v_g4 text[];
begin
  select * into v_agreement from private.project_agreement_state(p_project_id);
  v_deposit := private.project_deposit_state(p_project_id);
  v_balance := private.project_final_balance_state(p_project_id);
  v_holds := private.project_active_billing_holds(p_project_id);
  v_auth_state := private.payment_authorization_state(p_project_id);
  -- B1: an unresolved financial-integrity anomaly fails the gate of its charge (fail closed).
  v_g2 := private.gate_anomalies(p_project_id, 'G2');
  v_g4 := private.gate_anomalies(p_project_id, 'G4');
  select private.sha256_hex(coalesce(string_agg(entry_id::text, ',' order by id), ''))
    into v_digest from public.ledger_entries where project_id = p_project_id;
  return row(
    p_project_id, 3::smallint, true,
    v_deposit, private.project_deposit_verified(p_project_id) and cardinality(v_g2) = 0,
    v_balance, private.project_balance_verified(p_project_id) and cardinality(v_g4) = 0, v_balance = 'settled_by_adjustment',
    v_holds,
    jsonb_build_object('order_summary_id', v_agreement.order_summary_id, 'acceptance_id', v_agreement.acceptance_id,
      'ledger_digest', v_digest, 'calendar_version', private.calendar_version(), 'evaluated_at', now(),
      -- Anomaly kinds only (no amounts, no record identifiers; OI-72).
      'blocking_anomalies', jsonb_build_object('G2', to_jsonb(v_g2), 'G4', to_jsonb(v_g4))),
    v_agreement.state, v_agreement.state = 'effective',
    v_auth_state = 'active', v_auth_state
  )::private.project_financial_status;
end;
$$;
-- ---------------------------------------------------------------------------
-- 15. OI-72 derived operational projection (Owner and Admin) and the client's own status
-- ---------------------------------------------------------------------------
-- Exactly the six approved derived states, as booleans. No amounts, no record identifiers,
-- no payment-method details, no dispute evidence. Staff at aal2 in a live session only.
create function private.operational_payment_states(p_project_ids uuid[] default null)
returns table (
  project_id uuid,
  deposit_requirement_satisfied boolean,
  final_balance_requirement_satisfied boolean,
  payment_recovery_required boolean,
  publication_financially_eligible boolean,
  billing_operational_hold boolean,
  owner_intervention_required boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not (private.is_staff() and private.is_aal2() and private.session_is_active()) then
    raise exception 'staff only' using errcode = '42501';
  end if;
  return query
    select p.id,
           (f).deposit_verified,
           (f).balance_verified_or_settled,
           -- Payment recovery required: a failed maintenance renewal, or a verified deposit
           -- without a usable payment authorization (04 §8.1; OI-72 derived state).
           exists (select 1 from public.maintenance_recoveries r where r.project_id = p.id and r.status <> 'recovered')
             or (private.project_deposit_ever_verified(p.id) and not coalesce((f).payment_authorization_ready, false)),
           coalesce((f).agreement_effective and (f).deposit_verified and (f).balance_verified_or_settled
                    and cardinality((f).active_billing_holds) = 0, false),
           cardinality((f).active_billing_holds) > 0,
           private.project_owner_intervention_required(p.id)
    from public.projects p
    cross join lateral (select private.project_financial_status(p.id) as f) s
    where p_project_ids is null or p.id = any (p_project_ids)
    order by p.created_at;
end;
$$;

-- The client's own billing status (03 §4 "M (own invoices)"); also the Owner. Admin uses
-- the derived projection instead. T-PAY-04: a redirect alone never changes these states.
create function private.project_billing_status(p_project_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_agreement record;
  v_os public.order_summaries%rowtype;
  v_fbi public.final_balance_invoices%rowtype;
  v_cs public.checkout_sessions%rowtype;
begin
  if not ((private.is_owner() and private.is_aal2() and private.session_is_active())
          or (private.staff_role_of((select auth.uid())) is null and private.session_is_active()
              and private.is_project_member(p_project_id))) then
    return private.fail('not_found');
  end if;
  select * into v_agreement from private.project_agreement_state(p_project_id);
  select * into v_os from public.order_summaries where id = v_agreement.order_summary_id;
  select * into v_fbi from public.final_balance_invoices where project_id = p_project_id and status <> 'void'
   order by created_at desc limit 1;
  select * into v_cs from public.checkout_sessions where project_id = p_project_id and kind = 'initial'
   order by created_at desc, attempt desc limit 1;
  return jsonb_build_object('ok', true,
    'agreement_state', v_agreement.state,
    'order_summary_id', v_os.id,
    'deposit_state', private.project_deposit_state(p_project_id),
    'final_balance_state', private.project_final_balance_state(p_project_id),
    'deposit_cents', v_os.deposit_cents,
    'maintenance_monthly_cents', v_os.maintenance_monthly_cents,
    'balance_cents', v_os.balance_cents,
    'checkout_status', v_cs.status,
    'checkout_url', case when v_cs.status = 'open' then v_cs.checkout_url end,
    'final_invoice_amount_cents', v_fbi.amount_cents,
    'final_invoice_url', case when v_fbi.status in ('open', 'payment_failed', 'action_required') then v_fbi.hosted_invoice_url end,
    'billing_hold_active', exists (select 1 from public.billing_holds h where h.project_id = p_project_id
                                     and h.cleared_at is null and h.hold_type = 'maintenance_payment_hold'),
    'payment_authorization_state', private.payment_authorization_state(p_project_id),
    'is_authorization_signer', exists (select 1 from public.payment_authorizations a
        join public.agreement_acceptances c on c.id = a.acceptance_id
        where a.project_id = p_project_id and a.status <> 'revoked' and c.signer_user_id = (select auth.uid())),
    'recovery_url', (select r.checkout_url from public.recovery_sessions r
                     where r.project_id = p_project_id and r.status = 'open' order by r.created_at desc limit 1),
    'final_collection_mode', v_fbi.collection_mode);
end;
$$;

-- ---------------------------------------------------------------------------
-- 16. RLS (03 §8-§9; OI-72): Owner-only financial records; clients see their own invoices
-- ---------------------------------------------------------------------------
do $$
declare
  t text;
  v_tables text[] := array['stripe_customers', 'outbound_stripe_requests', 'checkout_sessions', 'webhook_events',
    'ledger_entries', 'refund_decisions', 'refunds', 'disputes', 'subscriptions', 'maintenance_recoveries',
    'billing_holds', 'billing_hold_reviews', 'stripe_cancellation_exceptions', 'cancellation_requests',
    'service_terminations', 'termination_notices', 'final_balance_invoices', 'reconciliation_runs',
    'reconciliation_mismatches', 'payment_obligations', 'refund_decision_lines', 'reversal_reconciliations',
    'payment_authorizations', 'payment_authorization_events', 'recovery_sessions', 'billing_job_runs'];
begin
  foreach t in array v_tables loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
    execute format('revoke insert, update, delete, truncate, references, trigger on table public.%I from service_role', t);
    execute format('grant select on table public.%I to authenticated', t);
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
  -- Owner-only financial records (OI-72): Admin and clients read nothing.
  foreach t in array array['stripe_customers', 'outbound_stripe_requests', 'webhook_events', 'ledger_entries',
    'refund_decisions', 'refunds', 'disputes', 'subscriptions', 'maintenance_recoveries', 'billing_holds',
    'billing_hold_reviews', 'stripe_cancellation_exceptions', 'termination_notices', 'reconciliation_runs',
    'reconciliation_mismatches', 'payment_obligations', 'refund_decision_lines', 'reversal_reconciliations',
    'payment_authorizations', 'payment_authorization_events', 'recovery_sessions', 'billing_job_runs'] loop
    execute format('create policy %I on public.%I for select to authenticated using ((select private.is_owner()))',
      t || '_select_owner', t);
  end loop;
end;
$$;

-- Own invoices and requests: the Owner, or a client member of the project. Never Admin.
create policy checkout_sessions_select on public.checkout_sessions for select to authenticated
  using ((select private.is_owner()) or (private.staff_role_of((select auth.uid())) is null and private.is_project_member(project_id)));
create policy final_balance_invoices_select on public.final_balance_invoices for select to authenticated
  using ((select private.is_owner()) or (private.staff_role_of((select auth.uid())) is null and private.is_project_member(project_id)));
create policy cancellation_requests_select on public.cancellation_requests for select to authenticated
  using ((select private.is_owner()) or (private.staff_role_of((select auth.uid())) is null and private.is_project_member(project_id)));
create policy service_terminations_select on public.service_terminations for select to authenticated
  using ((select private.is_owner()) or (private.staff_role_of((select auth.uid())) is null
         and private.is_project_member(project_id) and state not in ('under_owner_review', 'withdrawn')));

-- ---------------------------------------------------------------------------
-- 17. Exposed wrappers (SECURITY INVOKER) and function privileges (T-TEN-06)
-- ---------------------------------------------------------------------------
-- Client and staff (authenticated); each private function re-authorizes the caller.
create function public.begin_initial_checkout(p_project_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.begin_initial_checkout(p_project_id); $$;
create function public.project_billing_status(p_project_id uuid) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.project_billing_status(p_project_id); $$;
create function public.operational_payment_states(p_project_ids uuid[] default null)
returns table (project_id uuid, deposit_requirement_satisfied boolean, final_balance_requirement_satisfied boolean,
  payment_recovery_required boolean, publication_financially_eligible boolean, billing_operational_hold boolean,
  owner_intervention_required boolean)
language sql stable security invoker set search_path = '' as $$ select * from private.operational_payment_states(p_project_ids); $$;
create function public.submit_cancellation_request(p_project_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.submit_cancellation_request(p_project_id); $$;
create function public.place_billing_hold(p_project_id uuid, p_hold_type public.hold_type, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.place_billing_hold(p_project_id, p_hold_type, p_reason); $$;
create function public.clear_billing_hold(p_hold_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.clear_billing_hold(p_hold_id, p_reason); $$;
create function public.decide_billing_hold_review(p_hold_id uuid, p_decision public.billing_hold_review_decision, p_reason text)
returns jsonb language sql security invoker set search_path = '' as $$ select private.decide_billing_hold_review(p_hold_id, p_decision, p_reason); $$;
create function public.authorize_service_termination(p_termination_id uuid, p_effective_date date, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.authorize_service_termination(p_termination_id, p_effective_date, p_reason); $$;
create function public.withdraw_service_termination(p_termination_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.withdraw_service_termination(p_termination_id, p_reason); $$;
create function public.record_written_cancellation_notice(p_project_id uuid, p_request_date timestamptz) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_written_cancellation_notice(p_project_id, p_request_date); $$;
create function public.confirm_cancellation(p_cancellation_request_id uuid, p_effective_date date) returns jsonb
language sql security invoker set search_path = '' as $$ select private.confirm_cancellation(p_cancellation_request_id, p_effective_date); $$;
create function public.record_termination_notice(p_termination_id uuid, p_notice_kind text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_termination_notice(p_termination_id, p_notice_kind); $$;
create function public.record_maintenance_ceased(p_termination_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_maintenance_ceased(p_termination_id, p_reason); $$;
create function public.record_services_deactivated(p_termination_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_services_deactivated(p_termination_id, p_reason); $$;
create function public.record_service_transfer(p_termination_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_service_transfer(p_termination_id, p_reason); $$;
create function public.resolve_stripe_cancellation_exception(p_exception_id uuid, p_resolution text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.resolve_stripe_cancellation_exception(p_exception_id, p_resolution); $$;
create function public.record_refund_decision(p_project_id uuid, p_amount_cents bigint, p_reason text, p_lines jsonb default null)
returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_refund_decision(p_project_id, p_amount_cents, p_reason, p_lines); $$;
create function public.dispute_evidence_package(p_dispute_id text) returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.dispute_evidence_package(p_dispute_id); $$;
create function public.resolve_quarantined_event(p_webhook_event_id bigint, p_resolution text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.resolve_quarantined_event(p_webhook_event_id, p_resolution); $$;
create function public.resolve_reconciliation_mismatch(p_mismatch_id uuid, p_resolution text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.resolve_reconciliation_mismatch(p_mismatch_id, p_resolution); $$;
create function public.reconcile_outbound_request(p_request_id uuid, p_found boolean, p_stripe_object_id text, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.reconcile_outbound_request(p_request_id, p_found, p_stripe_object_id, p_note); $$;
create function public.begin_payment_method_recovery(p_project_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.begin_payment_method_recovery(p_project_id); $$;
create function public.revoke_payment_authorization(p_project_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.revoke_payment_authorization(p_project_id, p_reason); $$;
create function public.record_payment_authorization_revocation(p_project_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.record_payment_authorization_revocation(p_project_id, p_reason); $$;
create function public.review_authorization_revocation(p_project_id uuid, p_note text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.review_authorization_revocation(p_project_id, p_note); $$;
create function public.reconcile_holding_reversal(p_project_id uuid, p_charge_key text, p_lines jsonb, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.reconcile_holding_reversal(p_project_id, p_charge_key, p_lines, p_reason); $$;
create function public.retry_final_balance_invoice(p_final_balance_invoice_id uuid, p_reason text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.retry_final_balance_invoice(p_final_balance_invoice_id, p_reason); $$;

-- Server (secret key) only; each private function also refuses non-service_role JWTs.
create function public.ingest_stripe_event(p_event jsonb, p_raw_body_sha256 text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.ingest_stripe_event(p_event, p_raw_body_sha256); $$;
create function public.process_stripe_event(p_webhook_event_id bigint) returns jsonb
language sql security invoker set search_path = '' as $$ select private.process_stripe_event(p_webhook_event_id); $$;
create function public.outbound_request_for_execution(p_request_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.outbound_request_for_execution(p_request_id); $$;
create function public.record_outbound_result(p_request_id uuid, p_outcome text, p_stripe_object_id text, p_livemode boolean,
  p_http_status integer, p_error_code text, p_details jsonb default '{}'::jsonb) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_outbound_result(p_request_id, p_outcome, p_stripe_object_id, p_livemode, p_http_status, p_error_code, p_details);
$$;
create function public.run_billing_job(p_job text) returns jsonb
language sql security invoker set search_path = '' as $$ select private.run_billing_job(p_job); $$;
create function public.payment_method_lookups_due() returns jsonb
language sql stable security invoker set search_path = '' as $$ select private.payment_method_lookups_due(); $$;
create function public.record_payment_method_lookup(p_kind text, p_record_id uuid, p_payment_method_id text,
  p_customer_id text, p_livemode boolean, p_attached boolean) returns jsonb
language sql security invoker set search_path = '' as $$
  select private.record_payment_method_lookup(p_kind, p_record_id, p_payment_method_id, p_customer_id, p_livemode, p_attached);
$$;
create function public.start_reconciliation_run(p_source text, p_run_key text default null) returns uuid
language sql security invoker set search_path = '' as $$ select private.start_reconciliation_run(p_source, p_run_key); $$;
create function public.record_project_reconciliation(p_run_id uuid, p_project_id uuid, p_stripe jsonb) returns integer
language sql security invoker set search_path = '' as $$ select private.record_project_reconciliation(p_run_id, p_project_id, p_stripe); $$;
create function public.begin_billing_job(p_job text) returns uuid
language sql security invoker set search_path = '' as $$ select private.begin_billing_job(p_job); $$;
create function public.finish_billing_job(p_run_id uuid, p_result jsonb) returns jsonb
language sql security invoker set search_path = '' as $$ select private.finish_billing_job(p_run_id, p_result); $$;
create function public.complete_reconciliation_run(p_run_id uuid) returns jsonb
language sql security invoker set search_path = '' as $$ select private.complete_reconciliation_run(p_run_id); $$;

-- Default deny, then explicit grants.
do $$
declare
  f regprocedure;
begin
  for f in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.oid not in (select oid from wpb_functions_before)
  loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end;
$$;

grant execute on function
  private.begin_initial_checkout(uuid), public.begin_initial_checkout(uuid),
  private.project_billing_status(uuid), public.project_billing_status(uuid),
  private.operational_payment_states(uuid[]), public.operational_payment_states(uuid[]),
  private.submit_cancellation_request(uuid), public.submit_cancellation_request(uuid),
  private.place_billing_hold(uuid, public.hold_type, text), public.place_billing_hold(uuid, public.hold_type, text),
  private.clear_billing_hold(uuid, text), public.clear_billing_hold(uuid, text),
  private.decide_billing_hold_review(uuid, public.billing_hold_review_decision, text),
  public.decide_billing_hold_review(uuid, public.billing_hold_review_decision, text),
  private.authorize_service_termination(uuid, date, text), public.authorize_service_termination(uuid, date, text),
  private.withdraw_service_termination(uuid, text), public.withdraw_service_termination(uuid, text),
  private.record_written_cancellation_notice(uuid, timestamptz), public.record_written_cancellation_notice(uuid, timestamptz),
  private.confirm_cancellation(uuid, date), public.confirm_cancellation(uuid, date),
  private.record_termination_notice(uuid, text), public.record_termination_notice(uuid, text),
  private.record_maintenance_ceased(uuid, text), public.record_maintenance_ceased(uuid, text),
  private.record_services_deactivated(uuid, text), public.record_services_deactivated(uuid, text),
  private.record_service_transfer(uuid, text), public.record_service_transfer(uuid, text),
  private.resolve_stripe_cancellation_exception(uuid, text), public.resolve_stripe_cancellation_exception(uuid, text),
  private.record_refund_decision(uuid, bigint, text, jsonb), public.record_refund_decision(uuid, bigint, text, jsonb),
  private.begin_payment_method_recovery(uuid), public.begin_payment_method_recovery(uuid),
  private.revoke_payment_authorization(uuid, text), public.revoke_payment_authorization(uuid, text),
  private.record_payment_authorization_revocation(uuid, text), public.record_payment_authorization_revocation(uuid, text),
  private.review_authorization_revocation(uuid, text), public.review_authorization_revocation(uuid, text),
  private.reconcile_holding_reversal(uuid, text, jsonb, text), public.reconcile_holding_reversal(uuid, text, jsonb, text),
  private.dispute_evidence_package(text), public.dispute_evidence_package(text),
  private.resolve_quarantined_event(bigint, text), public.resolve_quarantined_event(bigint, text),
  private.resolve_reconciliation_mismatch(uuid, text), public.resolve_reconciliation_mismatch(uuid, text),
  private.reconcile_outbound_request(uuid, boolean, text, text), public.reconcile_outbound_request(uuid, boolean, text, text),
  private.retry_final_balance_invoice(uuid, text), public.retry_final_balance_invoice(uuid, text)
to authenticated;

grant execute on function
  private.ingest_stripe_event(jsonb, text), public.ingest_stripe_event(jsonb, text),
  private.process_stripe_event(bigint), public.process_stripe_event(bigint),
  private.outbound_request_for_execution(uuid), public.outbound_request_for_execution(uuid),
  private.record_outbound_result(uuid, text, text, boolean, integer, text, jsonb),
  public.record_outbound_result(uuid, text, text, boolean, integer, text, jsonb),
  -- One entry point per job (T-ARC-09); the job internals are executable by no API role.
  private.run_billing_job(text), public.run_billing_job(text),
  private.begin_billing_job(text), public.begin_billing_job(text),
  private.finish_billing_job(uuid, jsonb), public.finish_billing_job(uuid, jsonb),
  private.payment_method_lookups_due(), public.payment_method_lookups_due(),
  private.record_payment_method_lookup(text, uuid, text, text, boolean, boolean),
  public.record_payment_method_lookup(text, uuid, text, text, boolean, boolean),
  private.start_reconciliation_run(text, text), public.start_reconciliation_run(text, text),
  private.record_project_reconciliation(uuid, uuid, jsonb), public.record_project_reconciliation(uuid, uuid, jsonb),
  private.complete_reconciliation_run(uuid), public.complete_reconciliation_run(uuid)
to service_role;
