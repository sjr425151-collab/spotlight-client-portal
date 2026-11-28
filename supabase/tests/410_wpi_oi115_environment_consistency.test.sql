-- OI-115 (AUTH-016, WP-I): environment classification consistency, local part.
--   C1 = private.environment_settings (WP-B, OI-69; absent reads as production)
--   C2 = private.runtime_environment (WP-C, DEP-07; absent means no mock scanner)
-- D1: private.app_environment() raises 42501 whenever C1 and C2 disagree, so every
-- environment-dependent privileged path fails closed unedited; the scanner check requires
-- agreement. They agree when C2 is absent, or when C2 and C1 hold the same value.
-- D2: staging keeps no explicit row (both absent reads as production).
-- public.environment_classification() returns the raw values for the application check and
-- never raises; execute for service_role only. Everything below rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(37);

create function pg_temp.set_env(p_c1 text, p_c2 text) returns void language plpgsql as $$
begin
  delete from private.runtime_environment;
  delete from private.environment_settings;
  if p_c1 is not null then insert into private.environment_settings (app_env) values (p_c1); end if;
  if p_c2 is not null then insert into private.runtime_environment (app_env) values (p_c2); end if;
end;
$$;

-- 1. Seeded local database: agreement
select is(private.app_environment(), 'development', 'seeded: the classifications agree on development');
select ok(private.environment_consistent(), 'seeded: consistent');
select ok(private.scanner_permitted('mock_scanner'), 'seeded: the mock scanner is permitted');
select is(public.environment_classification(), '{"c1": "development", "c2": "development"}'::jsonb,
  'seeded: the raw classification reports both values');

-- 2. C2 development, C1 absent (G1: mock scanner where billing reads production)
select pg_temp.set_env(null, 'development');
select ok(not private.environment_consistent(), 'C2 development with C1 absent is a disagreement');
select throws_ok($$ select private.app_environment() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 absent: app_environment() raises');
select throws_ok($$ select private.is_production() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 absent: is_production() raises');
select throws_ok($$ select private.stripe_mode() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 absent: stripe_mode() raises');
select throws_ok($$ select private.expected_livemode() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 absent: the webhook livemode check raises');
select throws_ok($$ select private.install_test_agreement_fixture() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 absent: the fixture installer fails closed');
select ok(not private.scanner_permitted('mock_scanner'), 'C2 development with C1 absent: no mock scanner');
select is(public.environment_classification(), '{"c1": null, "c2": "development"}'::jsonb,
  'C2 development with C1 absent: the raw classification still reads (it never raises)');

-- 3. C2 test, C1 development
select pg_temp.set_env('development', 'test');
select throws_ok($$ select private.app_environment() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 test with C1 development: app_environment() raises');
select ok(not private.scanner_permitted('mock_scanner'), 'C2 test with C1 development: no mock scanner');

-- 4. C2 development, C1 staging and preview
select pg_temp.set_env('staging', 'development');
select throws_ok($$ select private.app_environment() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 staging: app_environment() raises');
select throws_ok($$ select * from private.current_package_scope('essential') $$, '42501',
  'environment classification disagreement (OI-115)',
  'C2 development with C1 staging: package scope resolution fails closed');
select ok(not private.scanner_permitted('mock_scanner'), 'C2 development with C1 staging: no mock scanner');
select pg_temp.set_env('preview', 'development');
select throws_ok($$ select private.app_environment() $$, '42501', 'environment classification disagreement (OI-115)',
  'C2 development with C1 preview: app_environment() raises');

-- 5. C2 absent: C1 decides (staging under D2 has no row at all; an explicit one is still valid)
select pg_temp.set_env('staging', null);
select ok(private.environment_consistent(), 'C1 staging with C2 absent is consistent');
select is(private.app_environment(), 'staging', 'C1 staging with C2 absent reads staging');
select ok(not private.scanner_permitted('mock_scanner'), 'C1 staging with C2 absent: no mock scanner');
select pg_temp.set_env('development', null);
select is(private.app_environment(), 'development', 'C1 development with C2 absent reads development');
select ok(not private.scanner_permitted('mock_scanner'), 'C1 development with C2 absent: no mock scanner');

-- 6. Neither row (a hosted database, D2): production, consistent, no scanner
select pg_temp.set_env(null, null);
select ok(private.environment_consistent(), 'neither row is consistent');
select is(private.app_environment(), 'production', 'neither row reads as production');
select is(private.stripe_mode(), 'live', 'neither row: live mode is expected');
select ok(not private.scanner_permitted('mock_scanner'), 'neither row: no mock scanner');
select is(public.environment_classification(), '{"c1": null, "c2": null}'::jsonb,
  'neither row: the raw classification reports both absent');

-- 7. Agreement on test
select pg_temp.set_env('test', 'test');
select is(private.app_environment(), 'test', 'C1 and C2 test agree');
select ok(private.scanner_permitted('mock_scanner'), 'C1 and C2 test: the mock scanner is permitted');
select ok(not private.scanner_permitted('other_scanner'), 'only the mock scanner is ever permitted');

-- 8. Privileges
select pg_temp.set_env('development', 'development');
select ok(has_function_privilege('service_role', 'public.environment_classification()', 'execute'),
  'service_role can read the classification');
select ok(not has_function_privilege('authenticated', 'public.environment_classification()', 'execute')
  and not has_function_privilege('anon', 'public.environment_classification()', 'execute'),
  'authenticated and anon cannot read the classification');
select ok(not has_function_privilege('authenticated', 'private.environment_classification()', 'execute')
  and not has_function_privilege('anon', 'private.environment_classification()', 'execute'),
  'authenticated and anon cannot call the private reader');
select ok(not has_function_privilege('authenticated', 'private.environment_consistent()', 'execute')
  and not has_function_privilege('service_role', 'private.environment_consistent()', 'execute')
  and not has_function_privilege('anon', 'private.environment_consistent()', 'execute'),
  'no API role can call the consistency predicate directly');
set local role authenticated;
select throws_ok($$ select public.environment_classification() $$, '42501', null,
  'an authenticated caller is refused');
reset role;
set local role service_role;
select is(public.environment_classification(), '{"c1": "development", "c2": "development"}'::jsonb,
  'the service role reads the classification through the invoker wrapper');
reset role;

select * from finish();
rollback;
