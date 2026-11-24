-- WP-B: privileges on every new table and function, package pricing and catalog invariants,
-- and the shared deadline calendar.
-- Covers: T-TEN-05/06 for WP-B objects, T-PAY-02, T-PAY-12 (catalog side), T-BIL-22 (schema),
-- T-PAY-10 (schema), T-CAL-01 to T-CAL-03, T-CAL-05 (SQL side), T-CAL-06, OI-69 environment
-- marker.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(41);

-- ---------------------------------------------------------------------------
-- 1. Table privileges: reads only through RLS; writes only through definer functions
-- ---------------------------------------------------------------------------
create temporary table wpb_tables (name text) on commit drop;
insert into wpb_tables values ('agreement_versions'), ('order_summaries'), ('agreement_acceptances'),
  ('stripe_customers'), ('outbound_stripe_requests'), ('checkout_sessions'), ('webhook_events'), ('ledger_entries'),
  ('refund_decisions'), ('refunds'), ('disputes'), ('subscriptions'), ('maintenance_recoveries'), ('billing_holds'),
  ('billing_hold_reviews'), ('stripe_cancellation_exceptions'), ('cancellation_requests'), ('service_terminations'),
  ('termination_notices'), ('final_balance_invoices'), ('reconciliation_runs'), ('reconciliation_mismatches'),
  ('payment_obligations'), ('refund_decision_lines'), ('reversal_reconciliations'), ('payment_authorizations'),
  ('payment_authorization_events'), ('recovery_sessions'), ('billing_job_runs');

select is((select count(*)::integer from wpb_tables t join pg_class c on c.relname = t.name
           join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public' where c.relrowsecurity), 29,
  'every WP-B table exists in public with RLS enabled');
select is_empty($$
  select t.name || ':' || r.role || ':' || p.priv from wpb_tables t
  cross join (values ('authenticated'), ('service_role'), ('anon')) r(role)
  cross join (values ('insert'), ('update'), ('delete'), ('truncate')) p(priv)
  where has_table_privilege(r.role, 'public.' || t.name, p.priv)
$$, 'no API role (including service_role) can insert, update, delete or truncate any WP-B table');
select is_empty($$
  select t.name from wpb_tables t where not has_any_column_privilege('authenticated', 'public.' || t.name, 'select')
$$, 'authenticated reads WP-B tables only through RLS (select granted, policies decide)');
select is_empty($$
  select t.name || ':' || pol from wpb_tables t cross join (values ('_staff_aal2'), ('_active_user')) x(pol)
  where not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = t.name
                      and p.policyname = t.name || x.pol and p.permissive = 'RESTRICTIVE')
$$, 'every WP-B table carries the restrictive staff-aal2 and active-user policies');
select ok(not has_column_privilege('authenticated', 'public.agreement_acceptances', 'ip', 'select')
  and not has_column_privilege('authenticated', 'public.agreement_acceptances', 'user_agent', 'select'),
  'signer network metadata is not selectable through the API');
select is_empty($$
  select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private' and c.relname in ('environment_settings', 'billing_packages', 'stripe_catalog_prices',
    'stripe_payment_links', 'event_consumptions')
    and (has_table_privilege('authenticated', c.oid, 'select') or has_table_privilege('service_role', c.oid, 'select')
         or has_table_privilege('anon', c.oid, 'select'))
$$, 'private WP-B tables are unreadable by every API role');

-- ---------------------------------------------------------------------------
-- 2. Function privileges
-- ---------------------------------------------------------------------------
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('ingest_stripe_event', 'process_stripe_event', 'record_outbound_result',
    'outbound_request_for_execution', 'run_billing_job', 'begin_billing_job', 'finish_billing_job',
    'payment_method_lookups_due', 'record_payment_method_lookup', 'start_reconciliation_run',
    'record_project_reconciliation', 'complete_reconciliation_run')
    and has_function_privilege('authenticated', p.oid, 'execute')
$$, 'server-only RPCs are not executable by authenticated');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('emit_domain_event', 'enqueue_notification', 'post_ledger_entry',
    'mark_deposit_verified', 'consume_release_approved', 'dispatch_stripe_event', 'handle_invoice_paid',
    'place_hold_internal', 'clear_hold_internal', 'project_financial_status', 'install_test_agreement_fixture',
    'apply_outbound_success', 'mark_agreement_effective', 'apply_reversal', 'post_reversal_entry', 'mirror_reversal',
    'create_obligation', 'halt_automatic_collection', 'revoke_authorization_internal', 'consume_release_approvals',
    'evaluate_maintenance_recoveries', 'retry_pending_webhook_events', 'advance_service_terminations',
    'mark_stale_outbound_requests')
    and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('service_role', p.oid, 'execute'))
$$, 'internal writers, the gate interface and the fixture installer are executable by no API role');
select is_empty($$
  select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prosecdef
$$, 'WP-B exposes no SECURITY DEFINER function in public (wrappers are invokers)');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
select throws_ok($$ select public.ingest_stripe_event('{}'::jsonb, repeat('0', 64)) $$, '42501', null,
  'an authenticated client cannot ingest a Stripe event');
select throws_ok($$ select public.record_outbound_result(gen_random_uuid(), 'succeeded', 'cs_test_x0001', false, 200, null, '{}') $$,
  '42501', null, 'an authenticated client cannot record a Stripe result');
select throws_ok($$ insert into public.ledger_entries (project_id, entry_type, amount_cents, service_category, source, dedupe_key)
  values ('20000000-0000-4000-8000-0000000000a0', 'deposit_charge', 1, 'development', 'webhook', 'x') $$,
  '42501', null, 'an authenticated client cannot insert ledger entries');
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok($$ select private.ingest_stripe_event('{}'::jsonb, repeat('0', 64)) $$, '42501', null,
  'the service_role database role with a non-service JWT is still refused (defense in depth)');
reset role;

-- ---------------------------------------------------------------------------
-- 3. Pricing, catalog and ledger schema rules (04 §5-§7, §12)
-- ---------------------------------------------------------------------------
select results_eq($$ select package_key, total_cents, deposit_cents, balance_cents from private.billing_packages order by total_cents $$,
  $$ values ('essential', 80000, 16000, 64000), ('professional', 149500, 29900, 119600), ('advanced', 249500, 49900, 199600),
            ('signature', 349500, 69900, 279600), ('prestige', 499500, 99900, 399600) $$,
  'T-PAY-02: the five packages match 04 §5.1 exactly in integer cents');
select is_empty($$
  select t from (select (random() * 10000000)::integer + 1 as t from generate_series(1, 2000)) r
  where (t * 20 + 50) / 100 <> round(t::numeric * 20 / 100)
     or ((t * 20 + 50) / 100) + (t - (t * 20 + 50) / 100) <> t
$$, 'T-PAY-02: deposit = round_half_up(20%) and deposit + balance = total for 2000 random integer totals');
select throws_ok($$ update private.billing_packages set deposit_cents = 200, balance_cents = 79800 where package_key = 'essential' $$, '23514', null,
  'the package table rejects a deposit that is not round_half_up(20%)');
select is((select count(*)::integer from private.stripe_catalog_prices where environment = 'test' and catalog_version = 1), 11,
  'the test catalog holds exactly the 11 DEP-01 prices');
select is((select count(*)::integer from private.stripe_catalog_prices where environment = 'live'), 0,
  'no live Price ID is loaded in any non-production database (04 §5.2)');
select is((select count(*)::integer from private.billing_packages p, private.verified_package_prices(p.package_key) v), 5,
  'every package resolves to verified test-mode prices');
update private.stripe_catalog_prices set expected_unit_amount = 16001 where catalog_key = 'essential.deposit';
select is_empty($$ select * from private.verified_package_prices('essential') $$,
  'T-PAY-12: a catalog amount that differs from the package pricing resolves no price (blocks Checkout and invoices)');
update private.stripe_catalog_prices set expected_unit_amount = 16000 where catalog_key = 'essential.deposit';
select is(private.maintenance_monthly_cents(), 9900, 'maintenance is 9900 cents per month');

select throws_ok($$ insert into public.ledger_entries (project_id, entry_type, amount_cents, service_category, source, dedupe_key)
  values ('20000000-0000-4000-8000-0000000000a0', 'deposit_charge', 16000, 'development', 'owner', 'manual:1') $$,
  '23514', null, 'T-PAY-10: the database refuses a payment entry without a webhook event (no "mark as paid")');
select throws_ok($$ insert into public.ledger_entries (project_id, entry_type, amount_cents, service_category, source, actor_user_id, reason, dedupe_key)
  values ('20000000-0000-4000-8000-0000000000a0', 'waiver', 0, 'development', 'owner', '00000000-0000-4000-8000-000000000001', 'x', 'waiver:1') $$,
  '23514', null, 'T-BIL-22: R1 refuses discount, credit and waiver entries');
select is((select count(*)::integer from pg_enum e join pg_type t on t.oid = e.enumtypid where t.typname = 'ledger_entry_type'), 14,
  'the ledger entry types are the 04 §12 list plus the OI-82 holding reclassification');

-- ---------------------------------------------------------------------------
-- 4. Environment marker (OI-69)
-- ---------------------------------------------------------------------------
select is(private.app_environment(), 'development', 'the local seed marks this database as development');
delete from private.environment_settings;
select is(private.app_environment(), 'production', 'no environment row means production (fail closed)');
select is(private.stripe_mode(), 'live', 'production expects live mode');
select ok(private.expected_livemode(), 'production expects livemode true events');
insert into private.environment_settings (app_env) values ('development');
select is(private.stripe_mode(), 'test', 'non-production expects test mode');
select throws_ok($$ insert into private.environment_settings (app_env) values ('production') $$, '23514', null,
  'the environment marker cannot claim production (production simply has no row)');

-- ---------------------------------------------------------------------------
-- 5. Deadline calendar (02 §13)
-- ---------------------------------------------------------------------------
select is(private.add_business_days(date '2026-11-20', 12), date '2026-12-09',
  'T-CAL-01: 12 business days after Fri 2026-11-20 skip weekends and Thanksgiving');
select is(private.end_of_local_day(private.add_business_days(date '2026-11-20', 12)), timestamptz '2026-12-10 04:59:59+00',
  'T-CAL-01: the business-day deadline ends at 23:59:59 America/Detroit (EST)');
select is(private.add_business_days(date '2026-12-18', 12), date '2027-01-07',
  'T-CAL-01: 12 business days across Christmas and New Year''s skip both holidays');
select is(private.end_of_local_day(private.local_date(timestamptz '2026-10-29 02:00:00+00') + 7),
  timestamptz '2026-11-05 04:59:59+00',
  'T-CAL-02: seven full calendar days across the DST change end 23:59:59 local on day 7');
select isnt(private.end_of_local_day(private.local_date(timestamptz '2026-10-29 02:00:00+00') + 7),
  timestamptz '2026-10-29 02:00:00+00' + interval '168 hours', 'T-CAL-02: not trigger + 168 hours');
select is(private.end_of_local_day(private.local_date(timestamptz '2026-11-24 03:00:00+00') + 7),
  timestamptz '2026-12-01 04:59:59+00',
  'T-CAL-02: the 02 §13.2 example (Monday 22:00 local) ends the following Monday 23:59:59');
select ok(extract(isodow from date '2026-07-04') = 6 and not private.is_business_day(date '2026-07-03'),
  'T-CAL-03: July 4 on a Saturday is observed Friday July 3, a non-business day');
select ok(extract(isodow from date '2028-01-01') = 6 and not private.is_business_day(date '2027-12-31'),
  'T-CAL-03: New Year''s Day on a Saturday is observed on December 31 of the prior year');
select ok(not private.is_business_day(date '2026-01-19') and not private.is_business_day(date '2026-05-25')
  and not private.is_business_day(date '2026-10-12') and private.is_business_day(date '2026-10-13'),
  'T-CAL-03: MLK Day, Memorial Day and Columbus Day 2026 are non-business days');
select is(private.end_of_local_day(date '2026-11-20' + 60), timestamptz '2027-01-20 04:59:59+00',
  'T-CAL-06: M2 counts 60 calendar days including weekends and holidays and ends 23:59:59 local');
select is_empty($$
  select p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname in ('add_business_days', 'end_of_local_day', 'termination_deadlines',
    'handle_invoice_failed', 'confirm_cancellation', 'authorize_service_termination')
    and pg_get_functiondef(p.oid) ~* '(hours''|\* *24|interval ''[0-9]+ days'')'
$$, 'T-CAL-05: no WP-B deadline function adds 24-hour multiples to a timestamp');

select * from finish();
rollback;
