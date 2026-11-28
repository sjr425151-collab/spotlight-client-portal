-- AUTH-022 (PWP-2) preparation, T-CON-10 part: golden vectors that pin the frozen v1 order-summary
-- snapshot and v1 acceptance. v1 is frozen (OD-1 to OD-19): no backfill and no rehash, so every v1
-- hash must stay reproducible after the v2 migration. The expected texts and hashes were computed by an
-- independent implementation of the jsonb text form (keys ordered by length, then bytewise).
-- Seed: Admin …02, client A …a1 (Project A …a0). Synthetic data only.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(11);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1') returns void language plpgsql as $$
declare
  v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'pgtap', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', '[]'::jsonb)::text, true);
  set local role authenticated;
end;
$$;
create temp table ids (k text primary key, v text);
grant all on ids to authenticated;

-- ---- Pure vectors: the v1 snapshot text and its SHA-256 ----
select is(private.order_summary_snapshot(jsonb_populate_record(null::public.order_summaries, '{"project_id": "7e570000-0000-4000-8000-0000000000a1", "revision": 1, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "package_key": "essential", "package_total_cents": 150000, "deposit_cents": 30000, "balance_cents": 120000, "maintenance_monthly_cents": 9900, "currency": "usd", "catalog_environment": "test", "catalog_version": 1, "deposit_price_id": "price_TEST_dep", "balance_price_id": "price_TEST_bal", "maintenance_price_id": "price_TEST_mnt", "scope_items": ["Five-page website", "Contact form"], "project_notes": null, "business_legal_name": "Acme Roofing LLC", "id": "7e570000-0000-4000-8000-000000000001"}'::jsonb))::text,
  '{"currency": "usd", "revision": 1, "project_id": "7e570000-0000-4000-8000-0000000000a1", "package_key": "essential", "scope_items": ["Five-page website", "Contact form"], "balance_cents": 120000, "deposit_cents": 30000, "project_notes": null, "catalog_version": 1, "balance_price_id": "price_TEST_bal", "deposit_price_id": "price_TEST_dep", "order_summary_id": "7e570000-0000-4000-8000-000000000001", "business_legal_name": "Acme Roofing LLC", "catalog_environment": "test", "package_total_cents": 150000, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "maintenance_price_id": "price_TEST_mnt", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "maintenance_monthly_cents": 9900}',
  'T-CON-10: v1 golden vector V1, the snapshot text is unchanged');
select is(private.sha256_hex(private.order_summary_snapshot(jsonb_populate_record(null::public.order_summaries, '{"project_id": "7e570000-0000-4000-8000-0000000000a1", "revision": 1, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "package_key": "essential", "package_total_cents": 150000, "deposit_cents": 30000, "balance_cents": 120000, "maintenance_monthly_cents": 9900, "currency": "usd", "catalog_environment": "test", "catalog_version": 1, "deposit_price_id": "price_TEST_dep", "balance_price_id": "price_TEST_bal", "maintenance_price_id": "price_TEST_mnt", "scope_items": ["Five-page website", "Contact form"], "project_notes": null, "business_legal_name": "Acme Roofing LLC", "id": "7e570000-0000-4000-8000-000000000001"}'::jsonb))::text),
  '67d1f13b9781ba994669239e4b6373c77436276614d9381cfd9e14aa6a37df64',
  'T-CON-10: v1 golden vector V1, the snapshot hash is unchanged');
select is(private.order_summary_snapshot(jsonb_populate_record(null::public.order_summaries, '{"project_id": "7e570000-0000-4000-8000-0000000000a1", "revision": 2, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "package_key": "professional", "package_total_cents": 299999, "deposit_cents": 60000, "balance_cents": 239999, "maintenance_monthly_cents": 9900, "currency": "usd", "catalog_environment": "test", "catalog_version": 1, "deposit_price_id": "price_TEST_dep", "balance_price_id": "price_TEST_bal", "maintenance_price_id": "price_TEST_mnt", "scope_items": [], "project_notes": "Line one\nLine \"two\"\t\\ end", "business_legal_name": "Café Ünïcode — Société Ltd", "id": "7e570000-0000-4000-8000-000000000002"}'::jsonb))::text,
  '{"currency": "usd", "revision": 2, "project_id": "7e570000-0000-4000-8000-0000000000a1", "package_key": "professional", "scope_items": [], "balance_cents": 239999, "deposit_cents": 60000, "project_notes": "Line one\nLine \"two\"\t\\ end", "catalog_version": 1, "balance_price_id": "price_TEST_bal", "deposit_price_id": "price_TEST_dep", "order_summary_id": "7e570000-0000-4000-8000-000000000002", "business_legal_name": "Café Ünïcode — Société Ltd", "catalog_environment": "test", "package_total_cents": 299999, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "maintenance_price_id": "price_TEST_mnt", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "maintenance_monthly_cents": 9900}',
  'T-CON-10: v1 golden vector V2, the snapshot text is unchanged');
select is(private.sha256_hex(private.order_summary_snapshot(jsonb_populate_record(null::public.order_summaries, '{"project_id": "7e570000-0000-4000-8000-0000000000a1", "revision": 2, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "package_key": "professional", "package_total_cents": 299999, "deposit_cents": 60000, "balance_cents": 239999, "maintenance_monthly_cents": 9900, "currency": "usd", "catalog_environment": "test", "catalog_version": 1, "deposit_price_id": "price_TEST_dep", "balance_price_id": "price_TEST_bal", "maintenance_price_id": "price_TEST_mnt", "scope_items": [], "project_notes": "Line one\nLine \"two\"\t\\ end", "business_legal_name": "Café Ünïcode — Société Ltd", "id": "7e570000-0000-4000-8000-000000000002"}'::jsonb))::text),
  '9d0848d15b670e1b0678df2ac7161db77461a42a2e7ed0e1be501b3dc9c247bd',
  'T-CON-10: v1 golden vector V2, the snapshot hash is unchanged');
select is(private.order_summary_snapshot(jsonb_populate_record(null::public.order_summaries, '{"project_id": "7e570000-0000-4000-8000-0000000000a1", "revision": 3, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "package_key": "premium", "package_total_cents": 3, "deposit_cents": 1, "balance_cents": 2, "maintenance_monthly_cents": 9900, "currency": "usd", "catalog_environment": "test", "catalog_version": 32767, "deposit_price_id": "price_TEST_dep", "balance_price_id": "price_TEST_bal", "maintenance_price_id": "price_TEST_mnt", "scope_items": ["Ünïcode ✓", "quote \" and \\ backslash", "ctl \u0001 char"], "project_notes": "", "business_legal_name": "X", "id": "7e570000-0000-4000-8000-000000000003"}'::jsonb))::text,
  '{"currency": "usd", "revision": 3, "project_id": "7e570000-0000-4000-8000-0000000000a1", "package_key": "premium", "scope_items": ["Ünïcode ✓", "quote \" and \\ backslash", "ctl \u0001 char"], "balance_cents": 2, "deposit_cents": 1, "project_notes": "", "catalog_version": 32767, "balance_price_id": "price_TEST_bal", "deposit_price_id": "price_TEST_dep", "order_summary_id": "7e570000-0000-4000-8000-000000000003", "business_legal_name": "X", "catalog_environment": "test", "package_total_cents": 3, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "maintenance_price_id": "price_TEST_mnt", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "maintenance_monthly_cents": 9900}',
  'T-CON-10: v1 golden vector V3, the snapshot text is unchanged');
select is(private.sha256_hex(private.order_summary_snapshot(jsonb_populate_record(null::public.order_summaries, '{"project_id": "7e570000-0000-4000-8000-0000000000a1", "revision": 3, "agreement_version_id": "7e570000-0000-4000-8000-0000000000b1", "agreement_text_sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "package_key": "premium", "package_total_cents": 3, "deposit_cents": 1, "balance_cents": 2, "maintenance_monthly_cents": 9900, "currency": "usd", "catalog_environment": "test", "catalog_version": 32767, "deposit_price_id": "price_TEST_dep", "balance_price_id": "price_TEST_bal", "maintenance_price_id": "price_TEST_mnt", "scope_items": ["Ünïcode ✓", "quote \" and \\ backslash", "ctl \u0001 char"], "project_notes": "", "business_legal_name": "X", "id": "7e570000-0000-4000-8000-000000000003"}'::jsonb))::text),
  '3673cc195ee4e4f379a01ef6b1fd199ebaef5afcb30d9c97f145885486abe32b',
  'T-CON-10: v1 golden vector V3, the snapshot hash is unchanged');

-- ---- A real v1 lifecycle: issue, then accept ----
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'os', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential',
  '["Five-page website"]'::jsonb) ->> 'order_summary_id';
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'acc', public.accept_agreement((select v::uuid from ids where k = 'os'), true, true, 'Alex Client',
  'Synthetic Business A LLC', 'Managing Member', true) ->> 'acceptance_id';
reset role;
select isnt((select v from ids where k = 'acc'), null, 'T-CON-10: a v1 summary is issued and accepted');
select is((select snapshot_sha256 from public.order_summaries where id = (select v::uuid from ids where k = 'os')),
  (select private.sha256_hex(private.order_summary_snapshot(s)::text) from public.order_summaries s
    where s.id = (select v::uuid from ids where k = 'os')),
  'T-CON-10: the issued v1 summary stores the hash of its v1 snapshot');
select is((select a.order_summary_sha256 from public.agreement_acceptances a where a.id = (select v::uuid from ids where k = 'acc')),
  (select snapshot_sha256 from public.order_summaries where id = (select v::uuid from ids where k = 'os')),
  'T-CON-10: the v1 acceptance records exactly the summary hash it accepted');
select is((select a.price_snapshot::text from public.agreement_acceptances a where a.id = (select v::uuid from ids where k = 'acc')),
  (select format('{"currency": "usd", "package_key": "essential", "balance_cents": %s, "deposit_cents": %s, '
      || '"package_total_cents": %s, "maintenance_monthly_cents": 9900}', s.balance_cents, s.deposit_cents, s.package_total_cents)
     from public.order_summaries s where s.id = (select v::uuid from ids where k = 'os')),
  'T-CON-10: the v1 acceptance price snapshot keeps its exact v1 form');
select is((select count(*)::int from public.order_summaries s
  where s.snapshot_sha256 <> private.sha256_hex(private.order_summary_snapshot(s)::text)), 0,
  'T-CON-10: every stored v1 summary hash still reproduces (v1 frozen: no backfill, no rehash)');

select * from finish();
rollback;
