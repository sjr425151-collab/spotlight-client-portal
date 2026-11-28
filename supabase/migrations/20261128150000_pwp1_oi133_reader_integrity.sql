-- AUTH-027 (OI-133): contract reader integrity, fail-closed (Owner, 2026-11-28).
-- Replaces the two contract readers so that neither returns any instrument text unless every
-- instrument it would return, and the bundle or order-summary binding it relies on, re-verifies:
--   * the staff reader   private.contract_bundle_documents(uuid)   (AUTH-021, 20261128100000)
--   * the client reader  private.order_summary_instruments(uuid)   (AUTH-022, 20261128120000)
-- Missing, inconsistent or invalid integrity evidence returns not_found for the whole request:
-- no partial bodies and no fallback. Each body below is the merged body with the integrity check
-- inserted immediately before the return; the signatures, the SECURITY DEFINER implementation
-- behind the unchanged SECURITY INVOKER public wrapper, the empty search_path, the grants and
-- every existing authorization check are unchanged. No audit event is written (the readers stay
-- STABLE), so no failure path can carry text into an audit row.
-- Integrity is not eligibility: withdrawal, activation, the governing agreement's usability and
-- the scope version's state are deliberately not consulted here, so a withdrawn bundle's
-- instruments stay readable wherever the readers allowed it before (T-CON-06). Only an
-- integrity failure refuses.
-- Never touched: issuance, acceptance, eligibility, withdrawal, sealing, governance, F1 to F5 and
-- every AUTH-018 object. Forward-only; no merged migration is edited.

-- ---------------------------------------------------------------------------
-- 1. Bundle content integrity (no eligibility): the bundle hash recomputes from its stored
--    fields, and each of its three instruments exists with the expected kind and package,
--    recomputes to its stored content hash, matches the component hash sealed into the bundle,
--    and carries the bundle's fixture flag.
-- ---------------------------------------------------------------------------
create function private.contract_bundle_content_intact(p_bundle_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  b private.contract_bundles;
  ip private.contract_instrument_versions;
  im private.contract_instrument_versions;
  isr private.contract_instrument_versions;
begin
  select * into b from private.contract_bundles x where x.id = p_bundle_id;
  if not found then
    return false;
  end if;
  select * into ip from private.contract_instrument_versions x where x.id = b.package_instrument_id;
  select * into im from private.contract_instrument_versions x where x.id = b.maintenance_instrument_id;
  select * into isr from private.contract_instrument_versions x where x.id = b.shared_terms_instrument_id;
  if ip.id is null or im.id is null or isr.id is null then
    return false;
  end if;
  return coalesce(
    b.canonicalization = 'spotlight.contract_bundle.v1'
    and b.bundle_sha256 = private.contract_bundle_sha256(b.package_key, b.bundle_version, b.title,
          b.agreement_version_id, b.agreement_text_sha256, b.package_instrument_id, b.package_instrument_sha256,
          b.maintenance_instrument_id, b.maintenance_instrument_sha256, b.shared_terms_instrument_id,
          b.shared_terms_instrument_sha256, b.scope_version, b.scope_content_sha256, b.scope_provision_map)
    and ip.kind = 'package_specification' and ip.package_key = b.package_key
    and im.kind = 'maintenance_specification' and im.package_key is null
    and isr.kind = 'shared_terms' and isr.package_key is null
    and ip.canonicalization = 'spotlight.contract_instrument.v1'
    and im.canonicalization = 'spotlight.contract_instrument.v1'
    and isr.canonicalization = 'spotlight.contract_instrument.v1'
    and private.contract_instrument_verifies(ip.id) and ip.content_sha256 = b.package_instrument_sha256
    and private.contract_instrument_verifies(im.id) and im.content_sha256 = b.maintenance_instrument_sha256
    and private.contract_instrument_verifies(isr.id) and isr.content_sha256 = b.shared_terms_instrument_sha256
    and ip.is_test_fixture = b.is_test_fixture and im.is_test_fixture = b.is_test_fixture
    and isr.is_test_fixture = b.is_test_fixture,
    false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Order-summary binding integrity (no eligibility): a v2 summary's stored snapshot hash
--    recomputes, and the governing agreement and every bundle and component identifier and hash
--    it carries (F5) equal the bundle it names.
-- ---------------------------------------------------------------------------
create function private.order_summary_bundle_binding_intact(p_order_summary_id uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare
  s public.order_summaries;
  b private.contract_bundles;
begin
  select * into s from public.order_summaries x where x.id = p_order_summary_id;
  if not found or s.snapshot_version is distinct from 2 then
    return false;
  end if;
  select * into b from private.contract_bundles x where x.id = s.contract_bundle_id;
  if not found then
    return false;
  end if;
  return coalesce(
    s.snapshot_sha256 = private.sha256_hex(private.order_summary_snapshot(s)::text)
    and s.package_key = b.package_key
    and s.agreement_version_id = b.agreement_version_id
    and s.agreement_text_sha256 = b.agreement_text_sha256
    and s.contract_bundle_sha256 = b.bundle_sha256
    and s.contract_bundle_canonicalization = b.canonicalization
    and s.package_instrument_id = b.package_instrument_id
    and s.package_instrument_sha256 = b.package_instrument_sha256
    and s.maintenance_instrument_id = b.maintenance_instrument_id
    and s.maintenance_instrument_sha256 = b.maintenance_instrument_sha256
    and s.shared_terms_instrument_id = b.shared_terms_instrument_id
    and s.shared_terms_instrument_sha256 = b.shared_terms_instrument_sha256
    and s.scope_version = b.scope_version
    and s.scope_content_sha256 = b.scope_content_sha256,
    false);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The staff reader (AUTH-021 body; the integrity check inserted before the return).
-- ---------------------------------------------------------------------------
create or replace function private.contract_bundle_documents(p_bundle_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  b private.contract_bundles;
begin
  select * into b from private.contract_bundles x where x.id = p_bundle_id;
  if not found then
    return private.fail('not_found');
  end if;
  if b.is_test_fixture and (private.environment_consistent() is not true
     or private.app_environment() not in ('development', 'test')) then
    return private.fail('not_found');
  end if;
  if not (private.is_staff() is true and private.is_aal2() is true and private.session_is_active() is true) then
    return private.fail('not_found');
  end if;
  -- AUTH-027 (OI-133): nothing is returned unless the bundle and all three instruments re-verify.
  if private.contract_bundle_content_intact(b.id) is not true then
    return private.fail('not_found');
  end if;
  return jsonb_build_object('ok', true, 'bundle_id', b.id, 'package_key', b.package_key,
    'bundle_version', b.bundle_version, 'bundle_sha256', b.bundle_sha256, 'is_test_fixture', b.is_test_fixture,
    'instruments', (select jsonb_agg(jsonb_build_object('kind', i.kind, 'instrument_id', i.id,
        'instrument_version', i.instrument_version, 'title', i.title, 'body', i.body,
        'content_sha256', i.content_sha256, 'is_test_fixture', i.is_test_fixture)
        order by array_position(array['package_specification', 'maintenance_specification', 'shared_terms'], i.kind))
      from private.contract_instrument_versions i
      where i.id in (b.package_instrument_id, b.maintenance_instrument_id, b.shared_terms_instrument_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The client reader (AUTH-022 body; the integrity checks inserted before the return).
-- ---------------------------------------------------------------------------
create or replace function private.order_summary_instruments(p_order_summary_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  s public.order_summaries;
  b private.contract_bundles;
begin
  select * into s from public.order_summaries x where x.id = p_order_summary_id;
  if not found or s.snapshot_version <> 2 then
    return private.fail('not_found');
  end if;
  if not ((private.wpc_is_client_member(s.project_id) is true)
          or (private.is_staff() is true and private.is_aal2() is true and private.session_is_active() is true)) then
    return private.fail('not_found');
  end if;
  if s.status <> 'presented'
     and not exists (select 1 from public.agreement_acceptances a where a.order_summary_id = s.id) then
    return private.fail('not_found');
  end if;
  select * into b from private.contract_bundles x where x.id = s.contract_bundle_id;
  if not found or (b.is_test_fixture and (private.environment_consistent() is not true
                   or private.app_environment() not in ('development', 'test'))) then
    return private.fail('not_found');
  end if;
  -- AUTH-027 (OI-133): nothing is returned unless the summary's binding to its bundle and the
  -- bundle with all three instruments re-verify.
  if private.order_summary_bundle_binding_intact(s.id) is not true
     or private.contract_bundle_content_intact(b.id) is not true then
    return private.fail('not_found');
  end if;
  return jsonb_build_object('ok', true, 'order_summary_id', s.id, 'bundle_id', b.id, 'package_key', b.package_key,
    'bundle_version', b.bundle_version, 'bundle_sha256', b.bundle_sha256, 'is_test_fixture', b.is_test_fixture,
    'instruments', (select jsonb_agg(jsonb_build_object('kind', i.kind, 'instrument_id', i.id,
        'instrument_version', i.instrument_version, 'title', i.title, 'body', i.body,
        'content_sha256', i.content_sha256, 'is_test_fixture', i.is_test_fixture)
        order by array_position(array['package_specification', 'maintenance_specification', 'shared_terms'], i.kind))
      from private.contract_instrument_versions i
      where i.id in (s.package_instrument_id, s.maintenance_instrument_id, s.shared_terms_instrument_id)));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Privileges: the readers keep their grants (create or replace preserves them); the two new
--    integrity helpers are callable by no API role.
-- ---------------------------------------------------------------------------
revoke all on function
  private.contract_bundle_content_intact(uuid),
  private.order_summary_bundle_binding_intact(uuid)
from public, anon, authenticated, service_role;
