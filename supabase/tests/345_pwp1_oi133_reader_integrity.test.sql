-- AUTH-027 (OI-133): contract reader integrity, fail-closed.
-- Both readers, the staff reader contract_bundle_documents and the client reader
-- order_summary_instruments, return nothing unless every instrument they would return, and the
-- bundle or order-summary binding they rely on, re-verifies. Covered here:
--   positive:  intact reads are unchanged, including an accepted summary (and its bundle) after the
--              bundle is withdrawn (T-CON-06 historical access: integrity is not eligibility);
--   negative:  Sales, cross-tenant, aal1 and anon callers are refused exactly as before;
--   tampering: for each reader, a tampered body, title or provision list, a tampered, re-sealed or
--              missing stored hash, a missing component, and an inconsistent bundle or summary
--              binding each give exactly not_found, with no audit row and nothing partial;
--   leakage:   no instrument text appears in any result or audit row from the failure paths;
--   mutation:  with the re-verification replaced by `true`, the same tampering returns text;
--   privileges: signatures, SECURITY DEFINER behind the INVOKER wrappers, empty search_path and
--              grants unchanged; the new integrity helpers are callable by no API role.
-- Seed: Owner …01, Admin …02, Sales …05, client A …a1 (Project A …a0), client B …b1 (Project B …b0).
-- Synthetic and fixture data only. Every tampering runs inside a subtransaction that is rolled back
-- before the next case, and the whole file is rolled back.
begin;
create extension if not exists pgtap with schema extensions;
grant usage on schema extensions to authenticated, service_role;
grant execute on all functions in schema extensions to authenticated, service_role;
select plan(55);

create function pg_temp.act_as(p_uid uuid, p_aal text default 'aal1', p_fresh boolean default false)
returns void language plpgsql as $$
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
    'session_id', v_sid, 'amr', case when p_fresh then jsonb_build_array(jsonb_build_object('method', 'totp',
      'timestamp', extract(epoch from now())::bigint)) else '[]'::jsonb end)::text, true);
  set local role authenticated;
end;
$$;
create temp table ids (k text primary key, v text);
grant all on ids to authenticated;
create function pg_temp.id(p_k text) returns uuid language sql as $$ select v::uuid from ids where k = p_k $$;
grant execute on function pg_temp.id(text) to authenticated;

-- Reads as a given caller, then returns to the test role.
create function pg_temp.staff_read(p_bundle uuid, p_uid uuid default '00000000-0000-4000-8000-000000000002',
  p_aal text default 'aal2') returns jsonb language plpgsql as $$
declare
  r jsonb;
begin
  perform pg_temp.act_as(p_uid, p_aal);
  r := public.contract_bundle_documents(p_bundle);
  reset role;
  return r;
end;
$$;
create function pg_temp.client_read(p_summary uuid, p_uid uuid default '00000000-0000-4000-8000-0000000000a1',
  p_aal text default 'aal1') returns jsonb language plpgsql as $$
declare
  r jsonb;
begin
  perform pg_temp.act_as(p_uid, p_aal);
  r := public.order_summary_instruments(p_summary);
  reset role;
  return r;
end;
$$;

-- Every failure-path result, with the audit rows written while it ran, for the leakage checks.
create temp table results (case_name text, reader text, r jsonb, audits integer);
-- Applies p_tamper as the table owner (append-only and RI triggers bypassed by replica mode), reads
-- with p_reader, records the result and the audit rows written meanwhile, then rolls the whole case
-- back (the tampering, any test-only DDL and the role) by raising inside a subtransaction.
create function pg_temp.under(p_case text, p_tamper text, p_reader text, p_target uuid) returns jsonb
language plpgsql as $$
declare
  r jsonb;
  v_before bigint;
  v_audits integer;
begin
  begin
    set local session_replication_role = replica;
    execute p_tamper;
    set local session_replication_role = origin;
    v_before := (select coalesce(max(id), 0) from public.audit_events);
    if p_reader = 'staff' then
      r := pg_temp.staff_read(p_target);
    else
      r := pg_temp.client_read(p_target);
    end if;
    v_audits := (select count(*)::int from public.audit_events where id > v_before);
    raise exception using errcode = 'P0001', message = 'pgtap_case_rollback';
  exception when sqlstate 'P0001' then
    if sqlerrm <> 'pgtap_case_rollback' then
      raise;
    end if;
  end;
  insert into results values (p_case, p_reader, r, v_audits);
  return r;
end;
$$;
-- A failure path returned exactly not_found (no other key, so no text and nothing partial) and
-- wrote no audit row.
create function pg_temp.refused(p_case text, p_reader text) returns boolean language sql as $$
  select r = '{"ok": false, "error": "not_found"}'::jsonb and audits = 0
  from results where case_name = p_case and reader = p_reader
$$;

-- ---------------------------------------------------------------------------
-- Setup: an accepted v2 summary on Project A (essential) and a presented one on Project B (advanced)
-- ---------------------------------------------------------------------------
select pg_temp.act_as('00000000-0000-4000-8000-000000000002', 'aal2');
insert into ids select 'osa', public.issue_order_summary('20000000-0000-4000-8000-0000000000a0', 'essential') ->> 'order_summary_id';
insert into ids select 'osp', public.issue_order_summary('20000000-0000-4000-8000-0000000000b0', 'advanced') ->> 'order_summary_id';
reset role;
select pg_temp.act_as('00000000-0000-4000-8000-0000000000a1');
insert into ids select 'acc', public.accept_agreement(pg_temp.id('osa'), true, true, 'Alex Client',
  'Synthetic Business A LLC', 'Managing Member', true) ->> 'acceptance_id';
reset role;
insert into ids select 'ba', contract_bundle_id::text from public.order_summaries where id = pg_temp.id('osa');
insert into ids select 'bv', contract_bundle_id::text from public.order_summaries where id = pg_temp.id('osp');
insert into ids select 'ip', package_instrument_id::text from private.contract_bundles where id = pg_temp.id('ba');
insert into ids select 'im', maintenance_instrument_id::text from private.contract_bundles where id = pg_temp.id('ba');
insert into ids select 'is', shared_terms_instrument_id::text from private.contract_bundles where id = pg_temp.id('ba');
insert into ids select 'ipv', package_instrument_id::text from private.contract_bundles where id = pg_temp.id('bv');
-- A second, synthetic agreement version (a heading and the approved 04 §3.1 clause only; created,
-- never approved), so a summary can be rebound to an existing agreement id in the tampering cases.
insert into ids select 'ag2_text', 'PGTAP SYNTHETIC AGREEMENT (345, OI-133)' || E'\n\n' || private.final_payment_clause();
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
insert into ids select 'ag2', public.create_agreement_version('pgtap-345-oi133',
  (select v from ids where k = 'ag2_text'), date '2026-11-01', 'PGTAP-345-AGR') ->> 'agreement_version_id';
reset role;
select ok(pg_temp.id('osa') is not null and pg_temp.id('osp') is not null and pg_temp.id('acc') is not null
  and pg_temp.id('ip') is not null and pg_temp.id('ipv') is not null and pg_temp.id('ba') <> pg_temp.id('bv')
  and pg_temp.id('ag2') is not null,
  'setup: an accepted essential summary, a presented advanced summary, their two bundles and a second agreement');
-- Every instrument title and body in the database, for the leakage checks.
create temp table texts as select title t from private.contract_instrument_versions
  union select body from private.contract_instrument_versions union select 'PGTAP TAMPERED';

-- ---------------------------------------------------------------------------
-- 1. Positive: intact reads are unchanged, and stay readable after withdrawal (T-CON-06)
-- ---------------------------------------------------------------------------
create temp table intact as select pg_temp.staff_read(pg_temp.id('ba')) staff, pg_temp.client_read(pg_temp.id('osa')) client;
select ok((select (staff ->> 'ok')::boolean and jsonb_array_length(staff -> 'instruments') = 3
             and (select bool_and(i ->> 'body' = v.body and i ->> 'title' = v.title and i ->> 'content_sha256' = v.content_sha256)
                  from jsonb_array_elements(staff -> 'instruments') i
                  join private.contract_instrument_versions v on v.id = (i ->> 'instrument_id')::uuid)
           from intact),
  'staff: an Admin at aal2 reads the three intact instruments, exactly as stored');
select ok((select (client ->> 'ok')::boolean and client -> 'instruments' = staff -> 'instruments'
             and client ->> 'bundle_sha256' = staff ->> 'bundle_sha256' from intact),
  'client: the client reads the same three instruments of its accepted summary');
select is(pg_temp.client_read(pg_temp.id('osp'), '00000000-0000-4000-8000-0000000000b1') ->> 'ok', 'true',
  'client: client B reads the instruments of its presented summary');
select pg_temp.act_as('00000000-0000-4000-8000-000000000001', 'aal2', true);
select is(public.withdraw_contract_bundle(pg_temp.id('ba'), 'Synthetic withdrawal for AUTH-027', 'PGTAP-AUTH-027') ->> 'ok',
  'true', 'setup: the Owner withdraws the essential bundle after the acceptance');
reset role;
select ok(private.contract_bundle_withdrawn(pg_temp.id('ba')), 'setup: the bundle is withdrawn');
select is(pg_temp.client_read(pg_temp.id('osa')), (select client from intact),
  'T-CON-06: the client still reads its accepted summary''s instruments, unchanged, after withdrawal');
select is(pg_temp.staff_read(pg_temp.id('ba')), (select staff from intact),
  'T-CON-06: staff still read the withdrawn bundle''s instruments, unchanged');

-- ---------------------------------------------------------------------------
-- 2. Negative: refused exactly as before (intact data)
-- ---------------------------------------------------------------------------
select is(pg_temp.staff_read(pg_temp.id('ba'), '00000000-0000-4000-8000-000000000005'), '{"ok": false, "error": "not_found"}'::jsonb,
  'staff reader: Sales reads nothing');
select is(pg_temp.staff_read(pg_temp.id('ba'), '00000000-0000-4000-8000-000000000002', 'aal1'), '{"ok": false, "error": "not_found"}'::jsonb,
  'staff reader: an Admin at aal1 reads nothing');
select is(pg_temp.staff_read(pg_temp.id('ba'), '00000000-0000-4000-8000-0000000000a1', 'aal1'), '{"ok": false, "error": "not_found"}'::jsonb,
  'staff reader: a client reads nothing');
select is(pg_temp.client_read(pg_temp.id('osa'), '00000000-0000-4000-8000-0000000000b1'), '{"ok": false, "error": "not_found"}'::jsonb,
  'client reader: another tenant''s client reads nothing');
select is(pg_temp.client_read(pg_temp.id('osa'), '00000000-0000-4000-8000-000000000005', 'aal2'), '{"ok": false, "error": "not_found"}'::jsonb,
  'client reader: Sales reads nothing');
select is(pg_temp.client_read(pg_temp.id('osa'), '00000000-0000-4000-8000-000000000002', 'aal1'), '{"ok": false, "error": "not_found"}'::jsonb,
  'client reader: an Admin at aal1 reads nothing');
set local role anon;
select throws_ok($$ select public.contract_bundle_documents('00000000-0000-4000-8000-000000000000') $$, '42501', null,
  'staff reader: anon cannot call it');
select throws_ok($$ select public.order_summary_instruments('00000000-0000-4000-8000-000000000000') $$, '42501', null,
  'client reader: anon cannot call it');
reset role;

-- ---------------------------------------------------------------------------
-- 3. Tampering: each case gives exactly not_found, with no audit row, for each reader
-- ---------------------------------------------------------------------------
create temp table cases (case_name text primary key, sql text, readers text[], label text);
insert into cases values
  ('body', format($q$update private.contract_instrument_versions set body = body || ' PGTAP TAMPERED' where id = %L$q$,
     pg_temp.id('ip')), array['staff', 'client'], 'a tampered instrument body'),
  ('title', format($q$update private.contract_instrument_versions set title = 'PGTAP TAMPERED' where id = %L$q$,
     pg_temp.id('im')), array['staff', 'client'], 'a tampered instrument title'),
  ('provisions', format($q$update private.contract_instrument_versions set provision_ids = provision_ids || array['PGTAP-X'] where id = %L$q$,
     pg_temp.id('is')), array['staff', 'client'], 'a tampered provision list'),
  ('stored_hash', format($q$update private.contract_instrument_versions set content_sha256 = repeat('a', 64) where id = %L$q$,
     pg_temp.id('ip')), array['staff', 'client'], 'a tampered stored instrument hash'),
  ('resealed', format($q$update private.contract_instrument_versions set body = body || ' PGTAP TAMPERED',
       content_sha256 = private.contract_instrument_sha256(kind, package_key, instrument_version, title,
         body || ' PGTAP TAMPERED', provision_ids) where id = %L$q$,
     pg_temp.id('ip')), array['staff', 'client'], 'a tampered body re-hashed to self-verify (bundle component hash differs)'),
  ('missing_hash', format($q$alter table private.contract_instrument_versions alter column content_sha256 drop not null;
       alter table private.contract_instrument_versions drop constraint contract_instrument_versions_content_sha256_check;
       update private.contract_instrument_versions set content_sha256 = null where id = %L$q$,
     pg_temp.id('im')), array['staff', 'client'], 'a missing stored instrument hash'),
  ('missing_component', format($q$delete from private.contract_instrument_versions where id = %L$q$,
     pg_temp.id('is')), array['staff', 'client'], 'a missing component instrument'),
  ('bundle_component_hash', format($q$update private.contract_bundles set package_instrument_sha256 = repeat('b', 64) where id = %L$q$,
     pg_temp.id('ba')), array['staff', 'client'], 'a tampered component hash in the bundle'),
  ('bundle_hash', format($q$update private.contract_bundles set bundle_sha256 = repeat('c', 64) where id = %L$q$,
     pg_temp.id('ba')), array['staff', 'client'], 'a tampered bundle hash'),
  ('bundle_swap', format($q$update private.contract_bundles set package_instrument_id = %L,
       package_instrument_sha256 = (select content_sha256 from private.contract_instrument_versions where id = %L) where id = %L$q$,
     pg_temp.id('ipv'), pg_temp.id('ipv'), pg_temp.id('ba')), array['staff', 'client'],
     'a bundle rebound to another package''s intact instrument'),
  ('summary_bundle_hash', format($q$update public.order_summaries set contract_bundle_sha256 = repeat('d', 64) where id = %L$q$,
     pg_temp.id('osa')), array['client'], 'a tampered bundle hash in the summary'),
  ('summary_snapshot', format($q$update public.order_summaries set snapshot_sha256 = repeat('e', 64) where id = %L$q$,
     pg_temp.id('osa')), array['client'], 'a tampered summary snapshot hash'),
  ('summary_rebound', format($q$update public.order_summaries set package_instrument_id = %L,
       package_instrument_sha256 = (select content_sha256 from private.contract_instrument_versions where id = %L) where id = %L;
       update public.order_summaries o set snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(o)::text) where o.id = %L$q$,
     pg_temp.id('ipv'), pg_temp.id('ipv'), pg_temp.id('osa'), pg_temp.id('osa')), array['client'],
     'a summary rebound to another intact instrument, snapshot re-hashed'),
  ('summary_other_bundle', format($q$update public.order_summaries set contract_bundle_id = %L where id = %L;
       update public.order_summaries o set snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(o)::text) where o.id = %L$q$,
     pg_temp.id('bv'), pg_temp.id('osa'), pg_temp.id('osa')), array['client'],
     'a summary pointed at another intact bundle, snapshot re-hashed'),
  ('summary_agreement_id', format($q$update public.order_summaries set agreement_version_id = %L where id = %L;
       update public.order_summaries o set snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(o)::text) where o.id = %L$q$,
     pg_temp.id('ag2'), pg_temp.id('osa'), pg_temp.id('osa')),
     array['client'], 'a summary rebound to another agreement version, snapshot re-hashed'),
  ('summary_agreement_hash', format($q$update public.order_summaries set agreement_text_sha256 = repeat('f', 64) where id = %L;
       update public.order_summaries o set snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(o)::text) where o.id = %L$q$,
     pg_temp.id('osa'), pg_temp.id('osa')), array['client'], 'a tampered agreement text hash in the summary, snapshot re-hashed');
select pg_temp.under(c.case_name, c.sql, rd, case when rd = 'staff' then pg_temp.id('ba') else pg_temp.id('osa') end)
  from cases c, unnest(c.readers) rd order by c.case_name, rd;
select ok(pg_temp.refused('body', 'staff'), 'staff reader: a tampered instrument body gives not_found');
select ok(pg_temp.refused('body', 'client'), 'client reader: a tampered instrument body gives not_found');
select ok(pg_temp.refused('title', 'staff'), 'staff reader: a tampered instrument title gives not_found');
select ok(pg_temp.refused('title', 'client'), 'client reader: a tampered instrument title gives not_found');
select ok(pg_temp.refused('provisions', 'staff'), 'staff reader: a tampered provision list gives not_found');
select ok(pg_temp.refused('provisions', 'client'), 'client reader: a tampered provision list gives not_found');
select ok(pg_temp.refused('stored_hash', 'staff'), 'staff reader: a tampered stored instrument hash gives not_found');
select ok(pg_temp.refused('stored_hash', 'client'), 'client reader: a tampered stored instrument hash gives not_found');
select ok(pg_temp.refused('resealed', 'staff'), 'staff reader: a self-consistent re-hashed instrument gives not_found (bundle binding)');
select ok(pg_temp.refused('resealed', 'client'), 'client reader: a self-consistent re-hashed instrument gives not_found (bundle binding)');
select ok(pg_temp.refused('missing_hash', 'staff'), 'staff reader: a missing stored instrument hash gives not_found');
select ok(pg_temp.refused('missing_hash', 'client'), 'client reader: a missing stored instrument hash gives not_found');
select ok(pg_temp.refused('missing_component', 'staff'), 'staff reader: a missing component gives not_found, with no partial result');
select ok(pg_temp.refused('missing_component', 'client'), 'client reader: a missing component gives not_found, with no partial result');
select ok(pg_temp.refused('bundle_component_hash', 'staff'), 'staff reader: a tampered component hash in the bundle gives not_found');
select ok(pg_temp.refused('bundle_component_hash', 'client'), 'client reader: a tampered component hash in the bundle gives not_found');
select ok(pg_temp.refused('bundle_hash', 'staff'), 'staff reader: a tampered bundle hash gives not_found');
select ok(pg_temp.refused('bundle_hash', 'client'), 'client reader: a tampered bundle hash gives not_found');
select ok(pg_temp.refused('bundle_swap', 'staff'), 'staff reader: a bundle rebound to another intact instrument gives not_found');
select ok(pg_temp.refused('bundle_swap', 'client'), 'client reader: a bundle rebound to another intact instrument gives not_found');
select ok(pg_temp.refused('summary_bundle_hash', 'client'), 'client reader: a tampered bundle hash in the summary gives not_found');
select ok(pg_temp.refused('summary_snapshot', 'client'), 'client reader: a tampered summary snapshot hash gives not_found');
select ok(pg_temp.refused('summary_rebound', 'client'),
  'client reader: a summary rebound to another intact instrument (snapshot re-hashed) gives not_found');
select ok(pg_temp.refused('summary_other_bundle', 'client'),
  'client reader: a summary pointed at another intact bundle (snapshot re-hashed) gives not_found');
select ok(pg_temp.refused('summary_agreement_id', 'client'),
  'client reader: a summary rebound to another agreement version (snapshot re-hashed) gives not_found');
select ok(pg_temp.refused('summary_agreement_hash', 'client'),
  'client reader: a tampered agreement text hash in the summary (snapshot re-hashed) gives not_found');
select is((select count(*)::int from results), 26, 'every tampering case ran for each applicable reader');
select is(pg_temp.client_read(pg_temp.id('osa')), (select client from intact),
  'after the rolled-back tampering cases the intact read is unchanged');

-- ---------------------------------------------------------------------------
-- 4. Leakage: no instrument text in any failure result or audit row
-- ---------------------------------------------------------------------------
select ok(not exists (select 1 from results r, texts t where position(t.t in r.r::text) > 0)
  and (select sum(audits) from results) = 0,
  'no failure-path result contains any instrument title or body, and none wrote an audit row');
select ok(not exists (select 1 from public.audit_events e, texts t
                      where position(t.t in coalesce(e.summary::text, '') || coalesce(e.reason, '')) > 0),
  'no audit row in this run contains any instrument title or body');

-- ---------------------------------------------------------------------------
-- 5. Mutation: with the re-verification replaced by `true`, the same tampering returns text
-- ---------------------------------------------------------------------------
create temp table mutant (sql text);
insert into mutant values ($m$create or replace function private.contract_bundle_content_intact(p_bundle_id uuid)
  returns boolean language sql stable set search_path = '' as $b$ select true $b$;
  create or replace function private.order_summary_bundle_binding_intact(p_order_summary_id uuid)
  returns boolean language sql stable set search_path = '' as $b$ select true $b$;$m$);
select pg_temp.under('mutant_' || c.case_name, (select sql from mutant) || ';' || c.sql, rd,
  case when rd = 'staff' then pg_temp.id('ba') else pg_temp.id('osa') end)
  from cases c, unnest(c.readers) rd where c.case_name in ('body', 'bundle_hash', 'summary_rebound', 'summary_agreement_id', 'summary_agreement_hash')
  order by c.case_name, rd;
select ok((select (r ->> 'ok')::boolean and position('PGTAP TAMPERED' in r::text) > 0 from results
            where case_name = 'mutant_body' and reader = 'staff'),
  'mutation: without the re-verification the staff reader returns the tampered body');
select ok((select (r ->> 'ok')::boolean and position('PGTAP TAMPERED' in r::text) > 0 from results
            where case_name = 'mutant_body' and reader = 'client'),
  'mutation: without the re-verification the client reader returns the tampered body');
select ok((select (r ->> 'ok')::boolean from results where case_name = 'mutant_bundle_hash' and reader = 'staff')
  and (select (r ->> 'ok')::boolean from results where case_name = 'mutant_bundle_hash' and reader = 'client'),
  'mutation: without the re-verification both readers return text for a tampered bundle hash');
select ok((select (r ->> 'ok')::boolean
             and exists (select 1 from jsonb_array_elements(r -> 'instruments') i where i ->> 'instrument_id' = pg_temp.id('ipv')::text)
           from results where case_name = 'mutant_summary_rebound' and reader = 'client'),
  'mutation: without the binding check the client reader returns another package''s instrument');
select ok((select (r ->> 'ok')::boolean from results where case_name = 'mutant_summary_agreement_id' and reader = 'client')
  and (select (r ->> 'ok')::boolean from results where case_name = 'mutant_summary_agreement_hash' and reader = 'client'),
  'mutation: without the binding check the client reader returns text for an altered agreement id or text hash');
select ok(private.contract_bundle_content_intact(pg_temp.id('ba')) and private.order_summary_bundle_binding_intact(pg_temp.id('osa'))
  and (select prosecdef from pg_proc where oid = 'private.contract_bundle_content_intact(uuid)'::regprocedure),
  'the mutants were rolled back: the real helpers are in place and pass on intact data');

-- ---------------------------------------------------------------------------
-- 6. Privileges and function attributes
-- ---------------------------------------------------------------------------
select is((select string_agg(n.nspname || '.' || p.proname || ':' || p.prosecdef || ':' || p.provolatile::text || ':'
             || coalesce(array_to_string(p.proconfig, ';'), '-'), ',' order by n.nspname, p.proname)
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where p.proname in ('contract_bundle_documents', 'order_summary_instruments', 'contract_bundle_content_intact',
             'order_summary_bundle_binding_intact')),
  'private.contract_bundle_content_intact:true:s:search_path="",private.contract_bundle_documents:true:s:search_path="",'
  || 'private.order_summary_bundle_binding_intact:true:s:search_path="",private.order_summary_instruments:true:s:search_path="",'
  || 'public.contract_bundle_documents:false:v:search_path="",public.order_summary_instruments:false:v:search_path=""',
  'the readers keep SECURITY DEFINER behind the INVOKER wrappers and the empty search_path; the helpers are DEFINER with it');
select ok(has_function_privilege('authenticated', 'private.contract_bundle_documents(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.contract_bundle_documents(uuid)', 'execute')
  and has_function_privilege('authenticated', 'private.order_summary_instruments(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.order_summary_instruments(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.contract_bundle_documents(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.order_summary_instruments(uuid)', 'execute'),
  'the readers keep their grants: authenticated only');
select ok(not has_function_privilege('authenticated', 'private.contract_bundle_content_intact(uuid)', 'execute')
  and not has_function_privilege('anon', 'private.contract_bundle_content_intact(uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.contract_bundle_content_intact(uuid)', 'execute')
  and not has_function_privilege('public', 'private.contract_bundle_content_intact(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.order_summary_bundle_binding_intact(uuid)', 'execute')
  and not has_function_privilege('anon', 'private.order_summary_bundle_binding_intact(uuid)', 'execute')
  and not has_function_privilege('service_role', 'private.order_summary_bundle_binding_intact(uuid)', 'execute')
  and not has_function_privilege('public', 'private.order_summary_bundle_binding_intact(uuid)', 'execute'),
  'the integrity helpers are callable by no API role');

select * from finish();
rollback;
