# R1 Implementation Handoffs (WP-H, WP-D18, WP-I-1)

| Field | Value |
|---|---|
| Version | 0.2.1 |
| Status | **Active handoffs.** AUTH-006, AUTH-007, and AUTH-008 (I-1 only) are active since 2026-11-25 (PR #25 merge `58d0e98981befe32f8ddff11c89ce7952dad3a72`, CI run 45543204966). The common baseline is filled in below. |
| Prepared by | Main (architecture, security, and integration review authority), 2026-11-25 |

Each prompt below is self-contained. Give it to its implementation session unchanged.

## Common rules (part of every prompt)

- Read CLAUDE.md, docs/CURRENT-STATE.md (§7, §13), docs/AUTHORIZATIONS.md (your record), and the decisions your record names, before any change.
- Verify that your authorization is **active** (CURRENT-STATE §13 activation record) and branch from exactly `58d0e98981befe32f8ddff11c89ce7952dad3a72` (`git checkout -b <your branch> 58d0e98981befe32f8ddff11c89ce7952dad3a72`). Later commits on `main` may only be documentation: `git diff --name-only 58d0e98981befe32f8ddff11c89ce7952dad3a72 origin/main` must list only `.md` files and must not change your authorization record's boundaries. Stop if the authorization is not active, the commit is missing, or `main` gained any non-documentation change or authorization change.
- Work only within your record's object and file inventory. Anything else is a stop condition: stop and report, do not work around it.
- Never edit a merged migration; never add a dependency; never weaken, skip, remove, or replace an existing assertion; never access Stripe, any hosted provider, or production; never touch PR #6, WP-D, or commission features.
- Use only your reserved migration timestamps.
- Record evidence in CURRENT-STATE and your PR: commands, results, test counts, CI run IDs, and effort (OI-67). Never claim a test passed unless it ran.
- Independent review is session-separated and recorded as a durable PR comment or non-approval review naming the reviewing session, the exact reviewed implementation commit and final head, the reviewed files, commands, results, findings, and verdict, stating that it is **not a GitHub APPROVED review**, and confirming that later commits are documentation-only. You never merge; the Owner alone merges, pinned to the exact head.
- Merge order is WP-I-1, then WP-H, then WP-D18. A later PR rebases onto the latest verified `main`; then verify the rebased diff, confirm implementation equivalence, assess newly integrated dependencies, run full CI on the exact rebased head, and obtain each reviewer's new confirmation (a focused re-review where behavior or dependencies changed). A conflict-free rebase never carries an approval forward.

## 1. WP-B session — AUTH-006 / WP-H (R1 financial hardening)

You are the WP-B implementation session. Implement WP-H under AUTH-006 on `wp-h/financial-hardening` from `58d0e98981befe32f8ddff11c89ce7952dad3a72`, as one PR.

**Scope (exhaustive):**
1. **OI-86** — migration `20261126120000`: replace `private.issue_order_summary` with the current body from `20261125120100` §10, byte-identical except the project lock `for update` → `for no key update`. Prove by genuine concurrent tests that it still serializes with `end_sales_assignment`, `assign_sales_representative`, `begin_initial_checkout`, `begin_payment_method_recovery`, `create_invitation`, and `revoke_invitation`, and that financial and assignment integrity hold. Change the T-SALES-32 true-race test so an `aborted:` (40P01) outcome is a failure, for both the Sales and Owner paths, over repeated iterations.
2. **OI-87** — migration `20261126120100`: revoke the table-level `select` on `public.order_summaries` from `authenticated` and grant `select` on every column except `change_reason` (the `agreement_acceptances` pattern). No new function or UI; the staff audit trail (`audit_events.reason`) stays the sole access path. Verify the client billing page, staff billing section, Sales progress, generated types, and every existing query. pgTAP: `not has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'select')`.
3. **N1(a)** — migration `20261126120200`: attribution at receipt in `private.handle_refund`, `private.handle_dispute`, `private.handle_charge_refunded`, through one new private helper. A `refund_decision_id` counts only if the decision exists and its `charge_key` matches the event's charge or payment intent; otherwise use `stripe_payment_links` and the invoice links (`checkout_sessions`, `final_balance_invoices`, `maintenance_recoveries`). Metadata alone never attributes. A safely identified project with incomplete evidence takes the existing B1 fail-closed gates. Conflicting projects: block every safely identified project's gates, keep all evidence, no automatic allocation, existing authorized reconciliation only, unresolved until reviewed; a later link never clears it. Unattributable events stay for reconciliation and Owner review.
4. **Release-approval cross-check** — migration `20261126120300`: in `private.consume_release_approved`, before any obligation or outbound request, read `private.project_fulfillment_status(project)` and the immutable `preview_releases` row and require: same project; `current_release_id` = the event's release; `current_release_approved`; `current_release_approval_id` = the event's `approval_id`; the event's `release_number` and `commit_sha` equal the release row; lifecycle eligibility. Otherwise `rejected` with a detail, audited, Owner notified, no charge. First analyse WP-C's supersession write path and show there is no unsafe gap between the check and charge initiation; if a lock is needed, lock only the specific release row; no broad cross-package lock or privilege, no WP-C change. If the interface cannot establish a condition safely, stop and report the exact gap.
5. Extend `tests/unit/wpb-contracts.test.ts` and `tests/unit/wpb-static.test.ts` to all four new migrations, restrictions unchanged.

**Migration ownership:** `20261126120000`, `20261126120100`, `20261126120200`, `20261126120300`, reserved exclusively for WP-H. **Shared files:** the WP-B static guard tests (you own them during WP-H).

**Prohibited:** any other WP-B, WP-C, WP-S, or Phase 2 object; any new table, role, grant, staff-only function, or UI; any WP-C change or broad cross-package lock or privilege; `supabase/seed.sql`, `playwright.config.ts`, and `tests/support/*` (owned by other packages); Stripe or any provider request; hosted or production environments; WP-D; commission features; PR #6; editing a merged migration; new dependencies; weakening, skipping, removing, or replacing an existing assertion.

**Acceptance:**
- **OI-86:** the T-SALES-32 true-race test accepts no `aborted:` outcome for the Sales and Owner paths (exactly one success, no 40P01) over repeated iterations; serialization with the six callers above proven by concurrent tests; financial and assignment integrity hold.
- **OI-87:** `not has_column_privilege('authenticated', 'public.order_summaries', 'change_reason', 'select')`; every other column still readable under the existing policies; client billing page, staff billing section, Sales progress, generated types, and all existing queries unaffected; the reason stays in `audit_events.reason` under the existing staff policy.
- **N1(a):** new pgTAP for refund-decision attribution (valid; forged decision; mismatched charge), link and invoice attribution, conflicting projects (every project blocked, evidence kept, no allocation, not cleared by a later link), and unattributable events (kept for reconciliation); T-PAY-32 and the 160 B1 assertions unchanged.
- **Cross-check:** positive (current approved release) and negative (missing release, other project, other approval, superseded release, mismatched number or SHA, ineligible) tests, with no obligation or outbound request on rejection, plus concurrency coverage of supersession against consumption.
- Full existing Phase 2, WP-0, WP-B, WP-C, and WP-S suites unchanged; 7/7 CI with the full suite on the exact head.

**Review:** independent financial review by a session other than WP-B, and Main.

**Stop conditions:** any object outside this list; any existing assertion would change; any permission would widen; a rule cannot be implemented as written; the cross-check gap cannot be closed with the existing mechanisms.

## 2. WP-S session — AUTH-007 / WP-D18 (package-scope version sealing)

You are the WP-S implementation session. Implement WP-D18 under AUTH-007 on `wp-d18/scope-sealing` from `58d0e98981befe32f8ddff11c89ce7952dad3a72`, as one PR, in migration `20261126140000` only.

**Scope (exhaustive):** new `private.billing_package_scope_versions` (package key, scope version, item count, content hash, `is_test_fixture`, sealed at; primary key package and version; no API grant); new `private.create_package_scope_version(p_package_key text, p_items text[], p_is_test_fixture boolean)` (SECURITY DEFINER, `search_path = ''`, no execute for any API role); one insert-protection trigger function on `private.billing_package_scope`; `private.current_package_scope(text)` changed to resolve sealed versions only (same signature); `supabase/seed.sql` WP-S section switched to the function (you are its sole owner during WP-D18); additive tests in WP-S pgTAP 300, 310, 320 and `tests/unit/wps-sales.test.ts`.

**Rules:**
- Insertion only inside the authorized atomic construction of a new unsealed version.
- No unsealed or partial version is visible to issuance.
- After sealing: no insertion; items never updated, deleted, or truncated; headers never modified, deleted, truncated, or unsealed.
- The resolver independently re-verifies count and canonical content hash. Canonical order is positions 1..n without gaps; the hash is SHA-256 over a length-prefixed canonical serialization of package key, version, and each position and item.
- Fixture status is identical on the header and every item. The `development`/`test` allowlist and both-way label check are unchanged; hosted environments receive no fixture content.
- Concurrent creation keeps package and version unique and atomic (per-package lock). Any failure rolls back the whole version.
- Historical versions reproduce exactly; issued snapshots never change; `issue_order_summary` is not changed.

**Migration cases:** a fresh run before seed data exists (nothing to seal; the seed then creates fixtures through the function), and an authorized local database already holding synthetic fixture rows (seal them as version 1 per package where the classification allows). Unexpected non-fixture content raises and changes nothing.

**Migration ownership:** `20261126140000`, reserved exclusively for WP-D18. **Shared files:** `supabase/seed.sql` (WP-S section; you are its sole owner during WP-D18).

**Prohibited:** production package content; any change to `issue_order_summary` or any other WP-B object; any WP-C or Phase 2 object; `playwright.config.ts` and `tests/support/*`; any API-role grant or execute on the new objects; Stripe or any provider request; hosted or production environments; WP-D; commission features; PR #6; editing a merged migration; new dependencies; weakening, skipping, removing, or replacing an existing assertion.

**Acceptance:** extended T-SALES-31 and T-SALES-36, including: sealed rejection for every writer, invisible partial versions, concurrent creation, hash and count tampering failing closed, rollback on failure, fixture consistency, migration raising on non-fixture content, no API execute; full existing suites unchanged; 7/7 CI on the exact head.

**Review:** WP-B (contractual snapshot and `issue_order_summary` interaction) and Main.

**Stop conditions:** `issue_order_summary` or any WP-B object must change; unexpected non-fixture data; any permission would widen; any production package content.

## 3. Dedicated integration session — AUTH-008 / WP-I-1 (integration infrastructure)

You are the dedicated integration implementation session (not Main). Implement I-1 under AUTH-008 (**I-1 only**) on `wp-i/integration-infra` from `58d0e98981befe32f8ddff11c89ce7952dad3a72`, as one PR. Tests and test infrastructure only: no production code, no migration, **no `seed.sql` change**.

**Scope (exhaustive):**
1. Replace `installDepositFixture` in `tests/support/wpc-fixtures.ts` with a helper that creates real WP-B records on fresh, isolated projects (the `tests/integration/wpb-billing.test.ts` pattern: business, project, membership, order summary, acceptance, mock-gateway checkout, synthetic signed webhook, payment-method lookup). Remove every global replacement of a financial function from test setup.
2. `tests/integration/wpc-delivery.test.ts` and `tests/integration/wpc-uploads.test.ts`: use fresh projects (parameterize `freeQuota` and the hard-coded project IDs; keep PROJECT_A unpaid for `tests/e2e/wpc.spec.ts` T-LC-01 and PROJECT_B `intake_locked`); every RPC helper checks and reports PostgREST `error`.
3. Deterministic schema-cache synchronization around the authorized local fixture operations (the committed trigger toggles in `tests/integration/wps-sales.test.ts` and `tests/e2e/wps.spec.ts`), assertions unchanged.
4. New shared e2e helpers in `tests/support/` and an isolated `r1` Playwright project in `playwright.config.ts` (after `wps`, added to the `testIgnore` lists of the generic projects). You own `playwright.config.ts` and `tests/support/*` during I-1.

**F2:** keep it open until the suspected cause is supported by evidence, ten consecutive cold-reset runs pass, failures, timing, and diagnostics are recorded, and repeatability is shown. A failure that stops reproducing never confirms the cause by itself.

**Migration ownership:** none (no migration in I-1). **Shared files:** `playwright.config.ts` and `tests/support/*` (you own them during I-1).

**Prohibited:** I-2 (the R1 suite, the billing-job runner, the mock live verifier, the authenticated Lighthouse CI change); any production-code change or test seam; any migration; `supabase/seed.sql`; `.github/workflows/*` and `lighthouserc.json`; the WP-B static guard tests; weakening, removing, or replacing any existing acceptance assertion; Stripe or any provider request; hosted or production environments; WP-D; commission features; PR #6; new dependencies.

**Acceptance:** existing assertions and coverage preserved; the F2 evidence above recorded; full existing suites unchanged; 7/7 CI on the exact head.

**Review:** WP-B (real WP-B record helpers), WP-C (WP-C fixtures and helpers), and Main.

**Stop conditions:** a production-code or migration change; a needed `seed.sql` change; any assertion change.
