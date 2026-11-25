# R1 Implementation Handoffs (WP-H, WP-D18, WP-I-1)

| Field | Value |
|---|---|
| Version | 0.4.0 |
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

## 1A. WP-B session — WP-H continuation under AUTH-006 Amendment 1

**Amendment 1 is active:** PR #29 merged at `7469b2d4f899ea7d25a43d86088ce92b5bfb3cb5`, post-merge CI run 45558153619 (#89) 7/7 with the full suite. All common rules above apply.

You are the WP-B implementation session. Continue WP-H on `wp-h/financial-hardening` from its current head `33eb953` (OI-86 and OI-87 done; keep both commits unchanged). If `main` has moved, follow the rebase rule only when preparing the merge.

**Remaining scope (exhaustive, AUTHORIZATIONS AUTH-006 and Amendment 1):**
1. `20261126120200` (N1(a)): the attribution helper and the three handlers (one candidate: current path; two or more: `quarantined:attribution_conflict`, no project set; none: `deferred`; never re-point an existing project); `private.financial_event_project_candidates` exactly as specified; `process_stripe_event` captures the handler's candidate set before the rollback and records it after the rollback in the same transaction as the quarantine; the additive `project_financial_anomalies` branch (both G2 and G4 for every candidate, kind `quarantined_event`); `resolve_quarantined_event` body only (re-check and audit every candidate; **candidate blocks persist**, OI-93).
2. `20261126120300` (cross-check): the 04 §10.2 eligibility and lock order in `consume_release_approved` (release advisory lock, release row `FOR SHARE`, then the checks, then the existing authorization lock).
3. Static guards: an exact `create or replace` allow-list for the functions named in AUTH-006 and Amendment 1; every other restriction unchanged; include all four WP-H migrations.

**Acceptance:** the "Amendment 1 acceptance" row in full, plus the original WP-H acceptance; T-PAY-32 and B1 unchanged; full suites unchanged; 7/7 CI on the exact head.

**Review:** financial review by a session other than WP-B; WP-C read-only review of the lock-key interface contract; Main.

**Prohibited:** everything in §1, plus: any conflict-clearing or allocation mechanism (OI-93), any withdrawal notification hook (OI-92(e), OI-91), any change to `outbound_request_for_execution` or revocation (OI-91), `contract_version` or anomaly-kind changes, any WP-C change.

**Stop conditions:** the Amendment 1 stop conditions, and everything in §1.

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

## 2A. WP-S session — WP-D18 correction under AUTH-007 Amendment 1

All common rules above apply. Continue on `wp-d18/scope-sealing` from `6173ffa` (PR #27); keep its commits. Governance: Owner decisions FD-05, FD-14 and H-0 (DEP-18 Phase 4, 08). **No blanket ratification:** migration-insertion Change 1 ratification is **withheld as currently written** (not approved, conditionally or otherwise); the seed-constructor refinement is approved in principle; the pgTAP 310 constructor rewrites are approved in principle, subject to preservation of the original guarantees. Scope (exhaustive, tests and records only, no migration or seed change):
1. `tests/unit/wps-sales.test.ts`: add the compensating controls (failures for any `create_package_scope_version(` call, any `wpd18.scope_construction` use, and the fixture label in any form in every migration other than `20261126140000_wpd18_scope_version_sealing.sql`) and prove each fails on a synthetic offending input (no vacuous pass). Present a corrected Change 1 for the Owner's individual disposition: exempt only that exact file name (the current check exempts any name containing `wpd18_scope_version_sealing`) and state its remaining exposure (dollar-quoted or `chr()`-built text inside the exempt file). Nothing here ratifies Change 1.
2. `supabase/tests/310_wps_sales_commercial.test.sql`, additive only (FD-14 label and environment evidence; H-1): with a forged construction marker on a new, unsealed version, (a) an unlabeled fixture item fails with 23514 from `billing_package_scope_fixture_label`, identified by name; (b) a labeled unflagged item fails with 23514 from the same constraint; (c) a fixture item fails with 42501 and the `billing_package_scope_fixture_guard` message under staging, preview, and a missing classification; (d) catalog assertions that the label constraint exists with its definition unchanged and that the fixture-guard trigger exists (BEFORE INSERT OR UPDATE) and is enabled. No existing or rewritten assertion changes its expected result; the plan count is updated.
3. `supabase/tests/320_*`: a genuine two-session concurrent-commit test (A creates version 2 and holds; B waits, shown deterministically; A commits; B completes with version 3; both resolve where applicable; counts and hashes correct; no duplicate, partial version, or gap). Use isolated disposable state; never disable or weaken an immutability trigger to clean up. If no disposable mechanism exists without a workflow or migration change, **stop and report** the options (for example a dedicated package with proof that no later suite depends on its version) for the Owner's decision. Keep the rollback concurrency test.
4. Under `pnpm test:db` (no TCP), skip the two-session blocks explicitly with a recorded reason so the other assertions run; replace the vacuous `ok(c is not null)` guard with a real connectivity check; record the runner limitation.
5. Correct the record of the construction marker (an unprivileged transaction-local setting: API roles cannot use it; it cannot add items to a sealed version; the database owner can construct a new version, which is **not** an authorized content path: non-fixture contractual content is loaded only through an **Owner-controlled, audited and hash-verified contractual content loading mechanism** (Owner decision FD-05); authoritative legal text and counsel evidence remain outside Git; the mechanism is not yet designed or authorized (PWP-0, not active, and later separately authorized work); no non-fixture content loading is authorized).
6. **Assertion disposition records (FD-14):** for each row of the table below, record in the WP-D18 section of CURRENT-STATE the original assertion, the replacement assertion, the original guarantee, the replacement guarantee, the identified weakness or remaining exposure, the compensating coverage, the required authorization, and the verification evidence (commands, results, exact head). The Owner decides each row individually; Main records the dispositions in 08 before PR #27 merges.

**Individual assertion dispositions (Main's independent comparison at `6173ffa`; Owner dispositions pending).** Code basis: the constructor does not pre-check the label or the classification; BEFORE INSERT triggers fire by name (`…_construction_guard`, then `…_fixture_guard`), then the CHECK constraints run. So each rewritten 23514 case still reaches `billing_package_scope_fixture_label`, and each rewritten 42501 case reaches `billing_package_scope_fixture_guard`. The direct path, however, now stops at the construction guard (42501) and never reaches them. The label CHECK and the fixture guard are unchanged by PR #27.

| ID | Assertion (PR #27 `310`, line) | Original guarantee | Replacement guarantee | Remaining exposure | Compensating coverage | Owner status |
|---|---|---|---|---|---|---|
| D-1 | Unit: T-SALES-36 migration check (Change 1, `wps-sales.test.ts` 177) | No migration inserts into the scope tables | One file (substring match) may insert without single-quoted literals | Substring exemption; quote heuristic; constructor calls and the marker not covered | Item 1 controls with mutation proofs; exact-name exemption | **Ratification withheld as written** |
| D-2 | Unit: seed fixtures flagged and labeled (Change 2, 199) | Seed rows labeled, flagged, after the classification | The same on the constructor call; no direct seed insert | None essential (preserved, slightly strengthened) | The new WP-D18 seed test (three labeled items) | Approved in principle; record required |
| D-3 | 310 A5 setup, essential version 2 (260 to 265) | A later version leaves the issued snapshot and hash unchanged | The same, with a sealed version 2 | None identified | WP-D18 historical reproducibility assertion | Approved in principle; record required |
| D-4 | Fixture without the label rejected, 23514 (602) | The label CHECK rejects a flagged, unlabeled row | The same CHECK, through the constructor | Error message not pinned; the direct path no longer reaches the CHECK | Item 2(a), 2(d) | Approved in principle, subject to 2(a), 2(d) |
| D-5 | Unflagged labeled row rejected, 23514 (604) | The label CHECK's reverse direction | The same CHECK, through the constructor | As D-4 | Item 2(b), 2(d) | Approved in principle, subject to 2(b), 2(d) |
| D-6 | Fixture rejected under staging, 42501 (622) | The fixture guard rejects outside `development`/`test` | The same guard, through the constructor | Message not pinned; the construction guard is a second 42501 source on the path | Item 2(c), 2(d) | Approved in principle, subject to 2(c), 2(d) |
| D-7 | Fixture rejected under preview, 42501 (632) | As D-6 | As D-6 | As D-6 | Item 2(c), 2(d) | As D-6 |
| D-8 | Fixture rejected with a missing classification, 42501 (638) | As D-6 (missing reads as production) | As D-6 | As D-6 | Item 2(c), 2(d) | As D-6 |
| D-9 | Non-fixture setup, signature (646 to 647) | A non-fixture row resolves under any classification | The same through the sealed resolver (version 2, synthetic, rolled back) | None identified | WP-D18 re-verification assertions | Approved in principle; record required |
| D-10 | Fixture inserts under `test`, lives_ok (652) | The allowlist admits fixtures under `test` | The same through the constructor; direct insertion is intentionally rejected | None identified | WP-D18 direct-insert rejection assertions | Approved in principle; record required |

The 320 additions and the other new WP-D18 assertions are additive, not rewrites. The proposed manifest-based database-state check (DEP-18 Phase 3 and 4) belongs to a later package and is not authorized here. **Known residual wording, unchanged here** (no seed change; merged migrations are never edited): the `supabase/seed.sql` WP-S comment and the `20261125120100` migration comment still describe a reviewed-migration content path. FD-05 prevails. A comment-only seed correction needs the Owner's decision.

**Acceptance:** the AUTH-007 acceptance and Amendment 1 rows; full suites unchanged; 7/7 CI on the exact head; the item 6 records; WP-B and Main reconfirmation records. Rebase only when preparing the merge (after WP-I-1 and WP-H); keep CURRENT-STATE edits inside the WP-D18 section. **Stop conditions:** any migration, seed, or immutability change; any API privilege; a change to an existing or rewritten assertion's expected result; no disposable state for the commit test.

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

## 3A. Dedicated integration session — WP-I-1 correction under AUTH-008 Amendment 1

All common rules above apply. Continue on `wp-i/integration-infra` from `a01b84e` (PR #28); keep its commits. Scope (exhaustive):
1. `tests/support/postgrest-ready.ts` and `tests/support/postgrest-sync.ts`: a real overall deadline; each request bounded by `min(remaining deadline, individual timeout)` and aborted with an `AbortSignal` when stalled; diagnostics include each failure (status, PGRST code, timeout, network error) and elapsed time; three consecutive successes still required; throw at the deadline (fail closed); no retry around tests, financial operations, or application RPCs.
2. New `tests/unit/postgrest-ready.test.ts`: deterministic local fake HTTP servers covering immediate readiness, startup recovery (503 then 200), persistent unavailability (fails at the deadline), a non-responding request (aborted and still fails by the deadline), and overall-deadline expiry with diagnostics.

**Not authorized:** production code, dependencies, workflows, `seed.sql`, any other test infrastructure, or any change to existing assertions.

**Acceptance:** renewed cold-reset verification (at least ten consecutive runs, recorded with timing and gate diagnostics); 7/7 CI on the exact head; WP-B, WP-C, and Main reconfirmation records against the new head. F2 closes only after Main's final verification. **Stop conditions:** any change outside the two helpers and the new unit test.
