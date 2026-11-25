-- WP-H (AUTH-006), OI-87: the noncontractual order_summaries.change_reason is staff-only.
-- Decision: OI-87 (Owner, 2026-11-25; mandatory before the R1 release candidate). Authorization:
-- AUTH-006, existing object (2). Handoff: docs/R1-HANDOFFS.md §1 item 2.
--
-- The table-level SELECT that authenticated held on public.order_summaries is replaced by
-- column-level SELECT on every column except change_reason (the agreement_acceptances pattern
-- in 20261124160000). Row-level security, the policies, and every other role's privileges are
-- unchanged: Owner, Admin and the project's clients read the same rows, minus that column.
--
-- The change reason stays available to staff only through the existing audit trail: it is
-- recorded as audit_events.reason by order_summary.issued and order_summary.superseded (and
-- by the price-change rejection), which only staff can read. No new function or UI.
--
-- Verified callers (none reads change_reason through the API): the client billing page and the
-- staff billing section name their columns; Sales progress reads inside a SECURITY DEFINER
-- function; the agreement_versions policy reads only agreement_version_id and project_id.
--
-- Forward-only (T-MIG-02); the merged 20261124160000 is not edited.

revoke select on table public.order_summaries from authenticated;

grant select (id, project_id, revision, agreement_version_id, agreement_text_sha256, package_key,
  package_total_cents, deposit_cents, balance_cents, maintenance_monthly_cents, currency,
  catalog_environment, catalog_version, deposit_price_id, balance_price_id, maintenance_price_id,
  scope_items, project_notes, business_legal_name, snapshot_sha256, status, supersedes_id,
  issued_by, issued_at, superseded_at)
  on public.order_summaries to authenticated;

-- Fail closed if a column was added without a decision: every column except change_reason must
-- be readable, and change_reason must not be.
do $$
declare
  v_missing text;
begin
  select string_agg(c.column_name, ', ' order by c.ordinal_position) into v_missing
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'order_summaries' and c.column_name <> 'change_reason'
    and not has_column_privilege('authenticated', 'public.order_summaries', c.column_name, 'select');
  if v_missing is not null then
    raise exception 'OI-87: order_summaries columns not readable by authenticated: %', v_missing;
  end if;
  if has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'select') then
    raise exception 'OI-87: change_reason is still readable by authenticated';
  end if;
end;
$$;
