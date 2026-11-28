# Open Issues and Dependencies Register

| Field | Value |
|---|---|
| Version | 0.48.0 |
| Status | Current (updated with the governance correction, OI-67). Overall status is in [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md). |
| Next unused issue ID | **OI-130** (OI-124 to OI-129 recorded 2026-11-28 by the PWP investigation; OI-119 and OI-123 are recorded with the AUTH-016 PR or below; OI-56 to OI-62 are allocated in draft PR #6, the AI operations proposal) |
| Next unused dependency ID | **DEP-21** |
| ID allocation | **Central (Owner, 2026-11-24).** Only the Main (integration) session allocates OI, DEP, and AUTH IDs. Work-package sessions propose items without IDs; Main assigns them. **One-time exception (Owner, 2026-11-25):** OI-98 to OI-112, DEP-19, DEP-20 and AUTH-011 were allocated by the PWP-0 documentation session under explicit Owner direction (AUTHORIZATIONS AUTH-011). |
| Decision record | [docs/08-DECISIONS-AND-CHANGELOG.md](docs/08-DECISIONS-AND-CHANGELOG.md) |

Rules:
- IDs are never reused.
- An **open issue** (OI-nn) needs an Owner decision. It closes only when the decision is recorded in 08.
- A **dependency** (DEP-nn) is work or verification that must happen before a named phase or production. Dependencies are not Owner policy decisions. Recommendations are proposals only.

---

## Part 1 — Decided issues (OI-01 to OI-55, OI-63 to OI-90, OI-92 to OI-94, OI-96 to OI-112)

All issues listed here are decided at the architectural level. The authoritative text is in [08 §3](docs/08-DECISIONS-AND-CHANGELOG.md#3-decision-register), and phase and dependency traceability is in [08 §3A](docs/08-DECISIONS-AND-CHANGELOG.md#3a-traceability-matrix-oi-01oi-55-oi-63oi-83).

| ID | Title | Status | Remaining dependencies |
|---|---|---|---|
| OI-01 | Specification governance | Decided | — |
| OI-02 | Development sequence | Decided | — |
| OI-03 | Roles | Decided | — |
| OI-04 | Notifications | Decided | DEP-06, DEP-08 |
| OI-05 | Project states | Decided | — |
| OI-06 | README and documentation governance | Decided | — |
| OI-07 | Portal URL | Decided | DEP-09 |
| OI-08 | Authentication | Decided | DEP-06 |
| OI-09 | Tenancy | Decided | — |
| OI-10 | Hosting and delivery | Decided | DEP-06, DEP-09 (DEP-10 complete) |
| OI-11 | Toolchain | Decided | DEP-11 |
| OI-12 | Design system | Decided | DEP-08 |
| OI-13 | Agreement | Decided | DEP-03 |
| OI-14 | Stripe catalog | Decided | DEP-02 |
| OI-15 | Payment calculations | Decided | DEP-04 |
| OI-16 | Maintenance subscription | Decided | DEP-03 |
| OI-17 | Stripe payment workflow | Decided | DEP-01, DEP-06 |
| OI-18 | Preview approval | Decided | — |
| OI-19 | Administrative overrides | Decided | — |
| OI-20 | Uploads | Decided | DEP-06, DEP-07 |
| OI-21 | Privacy and retention | Decided | DEP-05 |
| OI-22 | Publication | Decided | DEP-06 |
| OI-23 | Performance | Decided | DEP-12 |
| OI-24 | Optional post-publication inquiries | Decided | — |
| OI-25 | Nonresponsive preview clients | Decided | — |
| OI-26 | Failed maintenance payments | Decided | DEP-03, DEP-06 |
| OI-27 | Owner-authorized financial adjustments | Decided | DEP-03, DEP-06; OI-47 (decided) |
| OI-28 | Signer authority | Decided | DEP-03 (final wording) |
| OI-29 | Stripe Customer Portal | Decided | DEP-03, DEP-06 |
| OI-30 | Stripe test-mode catalog | Decided; catalog **created and verified** (2026-11-23) | DEP-01 |
| OI-31 | File upload security | Decided | DEP-07 |
| OI-32 | Client hosting | Decided | DEP-03, DEP-06 |
| OI-33 | Mandatory publishing QA | Decided | — |
| OI-34 | Agreement versioning | Decided | DEP-03 |
| OI-35 | Cancellation, refunds, post-cancellation milestones (revised 2026-11-23) | Decided | DEP-03, DEP-06 |
| OI-36 | Tax readiness | Decided | DEP-04 |
| OI-37 | Disputes and chargebacks | Decided | DEP-03 |
| OI-38 | Branding | Decided | DEP-08 |
| OI-39 | Provider verification | Decided | DEP-06 |
| OI-40 | Data governance | Decided | DEP-05 |
| OI-41 | Production infrastructure | Decided | DEP-09 |
| OI-42 | Unused client upload retention | Decided | DEP-05 |
| OI-43 | Business-day and time-zone calendar | Decided | DEP-03 |
| OI-44 | Adjusted final-balance payments | Decided | DEP-03, DEP-06 |
| OI-45 | Day-21 preview approval hold | Decided | — |
| OI-46 | Involuntary subscription cancellation | Decided | DEP-03, DEP-06 |
| OI-47 | Deposit-stage adjustments: none (Option A; reductions only on the final balance and never above it) | Decided (2026-11-23) | DEP-06 |
| OI-48 | Theme mode: dark-only MVP | Decided (2026-11-23) | DEP-08 (light variant, future) |
| OI-49 | Temporary logo compositing treatment | Decided (2026-11-23) | DEP-08 |
| OI-53 | Phase 2 implementation notes N-1 to N-8 (N-8 amended; N-2, N-6 retained) | Decided (2026-11-23) | — |
| OI-54 | Marking expired invitations: cleanup job deferred to Phase 5, on condition | Decided (2026-11-23) | — |
| OI-55 | Adjusted final-balance collection vehicle (option A) | Decided (2026-11-23) | DEP-06 |
| OI-63 | Webhook testing strategy: hybrid (synthetic signed events in CI; real Stripe test-mode verification) | Decided (2026-11-23) | DEP-01, DEP-15 |
| OI-64 | Stripe test-mode catalog structure: 11 products and 11 prices | Decided (2026-11-23) | DEP-01 |
| OI-65 | Stripe test-mode catalog naming, metadata, catalog keys, lookup keys, versioning (provided no conflict) | Decided (2026-11-23) | DEP-01 |
| OI-66 | `Stripe-Should-Retry: false` on a successful, verified HTTP 200 is not by itself a failure; never retried | Decided (2026-11-23) | DEP-01 |
| OI-50 | Supabase plan: Pro for hosted staging and production (option A) | Decided (2026-11-23) | DEP-14 |
| OI-51 | Resend SMTP for Supabase Auth email (option A) | Decided (2026-11-23) | DEP-14 |
| OI-52 | No CAPTCHA in the MVP; disabled hook kept (option C) | Decided (2026-11-23) | — |
| OI-67 | Risk-based authorization and execution model (revises OI-01, OI-02) | Decided (2026-11-23) | — |
| OI-68 | Release scope: R1 and R2 | Decided (2026-11-23) | DEP-03, DEP-06, DEP-07, DEP-12 |
| OI-69 | Test-only legal fixtures | Decided (2026-11-23) | — |
| OI-70 | Path-aware, fail-closed CI; dependency security patch exception | Decided (2026-11-23) | DEP-16 |
| OI-71 | Gate-interface coverage, publication holds, financial classification (mapped onto the existing interfaces) | Decided (2026-11-24; revised 2026-11-24) | — |
| OI-72 | Admin access to payment and financial records: derived operational states only (option A) | Decided (2026-11-24) | — |
| OI-73 | Final-balance collection order relative to publication: approved order kept (option A) | Decided (2026-11-24) | — |
| OI-74 | Mandatory payment method retention; automatic final charge in R1; card only; setup-mode recovery; revocation | Decided (2026-11-24) | DEP-03, DEP-06, DEP-15 |
| OI-75 | Recovery and revocation scope: final-balance authorization only, independent of the maintenance subscription (option A) | Decided (2026-11-24) | — |
| OI-76 | Collection timing statement: OI-73 retained (option A) | Decided (2026-11-24) | — |
| OI-77 | Sales Representative role (R1); assignment-scoped, `is_staff()` unchanged (option A, eight refinements) | Decided (2026-11-24) | AUTH-005 (scope final, not granted) |
| OI-78 | AUTH-005 policy decisions (pending invitations, ended assignments, termination), WP-S approval, integration order | Decided (2026-11-24) | AUTH-005 grant and activation |
| OI-79 | WP-C unstated values, decided item by item | Decided (2026-11-24) | — |
| OI-80 | WP-C blocked capabilities stay fail-closed; no new dependency or provider access | Decided (2026-11-24) | DEP-07 |
| OI-81 | No price change after a verified deposit in R1 | Decided (2026-11-24) | — |
| OI-82 | Refund and dispute allocation architecture | Decided (2026-11-24) | DEP-03, DEP-06 |
| OI-83 | Agreed order-summary pricing visible to Owner, Admin, assigned Sales Representatives | Decided (2026-11-24) | — |
| OI-84 | WP-S commercial capabilities: Sales order inputs and derived scope, no replacement after acceptance, resend as revoke and reissue, invitations in the progress view, order summaries at assignment end | Decided (2026-11-24) | DEP-18 |
| OI-85 | Staff/client separation enforced in the database (`is_project_member` with no staff role; membership and role invariant triggers); T-SALES-24 in full | Decided (2026-11-25); **closed** 2026-11-25 (corrected in PR #23 at `1eda945`; Main's focused re-review) | — |
| OI-86 | Lock-order deadlock between `issue_order_summary` and `accept_agreement` | **Resolved** by WP-H (AUTH-006), PR #35 merged at `30414c7` (post-merge CI 45689577718): project lock `FOR NO KEY UPDATE` | WP-B |
| OI-87 | Noncontractual `order_summaries.change_reason` readable by the project's clients | **Resolved** by WP-H (AUTH-006), PR #35 merged at `30414c7` (post-merge CI 45689577718): staff-only column privilege | WP-B |
| OI-88 | Strict `requireClient` and invitees without an active membership | **Closed (2026-11-27):** option A implemented under AUTH-017 (PR #53, `8ebcced`; post-merge CI 46062083448 7/7): `/invitations` for an invitee without an active membership; strict `requireClient` unchanged. Earlier: decided 2026-11-25 (strict kept; UX reassessed before the R1 release candidate) | — |
| OI-89 | WP-S confirmations (T-SALES-23 reading, rate limits, audit names, progress-view limits, agreed pricing fields, shared files) | Decided (2026-11-25) | — |
| OI-90 | Direct-writer lock ordering against the OI-85 triggers (a database-owner `UPDATE` holds the row lock before its trigger takes the per-user lock; can deadlock with `accept_invitation` or `set_staff_role` for the same user; integrity preserved) | Decided (2026-11-25): low, nonblocking for merge; OWNER-RUNBOOKS §7 required before R1 release-candidate acceptance; no code change | — |
| OI-92 | Final-balance initiation eligibility (approval hold, archived project, intake, anomaly-aware G2, withdrawal after initiation) | Decided (2026-11-25); (e) notification hook open (see OI-91) | DEP-03 |
| OI-93 | Conflicting reversal after Owner review | **Closed (2026-11-27):** implemented under AUTH-010 (PR #59, `30ee417`; post-merge CI 46080015419): Owner-only conflict decisions and re-verified financial applications. Earlier: decided (2026-11-25): Option A only with substantive reconciliation; **feasibility: not representable with existing mechanisms, so the candidate blocks persist in R1**; a representation mechanism needs separate authorization | — |
| OI-94 | WP-C tests ignore errors on some direct table reads (T-UP-04 usage, `deletionOf`) (PR #28 review O-1) | Decided (2026-11-25): track for I-2 | — |
| OI-96 | `runPaymentMethodLookups` processes every due lookup, not only the test project's (PR #28 review) | Decided (2026-11-25): acceptable under sequential integration execution; must be scoped before any test parallelization | — |
| OI-97 | WPI-P1: PostgREST startup-only `503 PGRST001` before tests (F2) | Decided (2026-11-25): accepted when bounded, observable, before any test, fail closed; F2 root cause and direction accepted subject to Main's final verification; F2 open until the AUTH-008 Amendment 1 timeout correction | — |
| OI-98 | Contractual instruments and per-package bundles (Architecture B; supplements OI-13, OI-34) | Decided (2026-11-25): approved direction; not implemented (PWP-1, PWP-2) | DEP-19, DEP-03 |
| OI-99 | Deliverable source, traceability and representation limits (SLM-CPS-002 authority only on completion, approval and publication) | Decided (2026-11-25): approved direction; not implemented | DEP-18, DEP-03 |
| OI-100 | Standardized issuance for every role; operational notes outside the contractual snapshot (revises OI-84(b)) | Decided (2026-11-25): approved direction; not implemented (PWP-2, PWP-5) | DEP-19 |
| OI-101 | Amendments, additional work and custom engagements; resolves 05 §8 against OI-81 | Decided (2026-11-25): approved direction; automated billing (PWP-6) post-R1 | DEP-03 |
| OI-102 | Versioned order snapshots, provenance and legacy compatibility | Decided (2026-11-25): approved direction; not implemented (PWP-2) | DEP-19, DEP-20 |
| OI-103 | Governance events (legal approval, production eligibility, activation) and irreversible withdrawal | Decided (2026-11-25): approved direction; not implemented (PWP-1, PWP-2) | DEP-19, DEP-20 |
| OI-104 | Deterministic concurrency, idempotency integrity, integrity failure without fallback | Decided (2026-11-25): approved direction; not verified (R-02) | DEP-19 |
| OI-105 | Individual disposition of replaced assertions (no blanket ratification) | Decided (2026-11-25) | — |
| OI-106 | Contractual records, confidentiality and content loading (legal text outside Git; no migration content path; revises DEP-18 loading) | Decided (2026-11-25): no loading mechanism chosen or authorized | DEP-18 |
| OI-107 | DEP-03 evidence standard and reconstruction status | Decided (2026-11-25) | DEP-03 |
| OI-108 | Maintenance commitments classification | Decided (2026-11-25) | DEP-03, DEP-06, DEP-12 |
| OI-109 | Canonicalization versioning; §3.1 byte verification | Decided (2026-11-25): verification outstanding | DEP-03 |
| OI-110 | Inactivity procedure 7/14/30/60; day-3 courtesy; commercial reconciliation (revises OI-25, OI-45) | Decided (2026-11-25): approved direction; not implemented (PWP-5) | DEP-03 |
| OI-111 | Project-specific scope confirmation and mandatory acknowledgment before preview release | Decided (2026-11-25): approved direction; not implemented (PWP-5) | DEP-19 |
| OI-112 | Contractual dependency and release gating | Decided (2026-11-25) | DEP-18, DEP-19, DEP-20 |

---

## Part 2 — Open issues requiring Owner decision

OI-50 (option A), OI-51 (option A), and OI-52 (option C) were decided on 2026-11-23 in the consolidated execution plan approval; their decisions are recorded in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The options considered remain in this file's Git history.

OI-72 was decided on 2026-11-24 (option A); its decision is in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The options considered remain in this file's Git history.

OI-73 was decided on 2026-11-24 (option A); its decision and the implications confirmed by the Owner are in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The options considered remain in this file's Git history.

OI-75 was decided on 2026-11-24 (option A); its decision is in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The options considered remain in this file's Git history.

OI-76, OI-77, and OI-78 were decided on 2026-11-24; their decisions are in [08](docs/08-DECISIONS-AND-CHANGELOG.md).

OI-79 (item by item) and OI-82 (allocation architecture, subject to DEP-03 and DEP-06) were decided on 2026-11-24; their decisions are in [08](docs/08-DECISIONS-AND-CHANGELOG.md).

OI-84 was decided on 2026-11-24; its decision is in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The discrepancies and options considered remain in this file's Git history.

**Closed: OI-91 (2026-11-26).** Resolved by AUTH-009: PR #43 merged at `3545d0a0fc63f63a059c3409cc67c4fc9c65ff54` (head `655c816`, base `48a8c04`; reviewed head `1d51f97`, CI 45743274091; one synchronization, setup-only; exact-head CI 45745385436 7/7); post-merge CI run 45745975920 (#150) 7/7 with the full suite. Original record: `private.outbound_request_for_execution` locks the final-balance invoice, then the payment authorization; revocation (`halt_automatic_collection`) locks the authorization, then the invoice; the two can deadlock. Remediation inventory: one consistent lock order (authorization, then invoice) in `outbound_request_for_execution`, body only, plus an Owner notification when the obligation's release was withdrawn after initiation (OI-92(e)). Acceptance: two-connection tests of outbound execution against revocation in both orders; no deadlock; no automatic charge after revocation (the hosted-only downgrade is honored); idempotency and single flight preserved. Not part of AUTH-006. **AUTH-009 granted (Owner, 2026-11-26), activation pending;** OI-91 stays open until its correction is implemented, independently verified and merged.

OI-92 and OI-93 were decided on 2026-11-25 (AUTH-006 Amendment 1); decisions in [08](docs/08-DECISIONS-AND-CHANGELOG.md).

**Closed: OI-95 (2026-11-25).** The `/sales` customer list rendered a `<p>` inside its `<ul>` when empty (`src/app/sales/page.tsx`), failing axe rule `list` on a fresh reset (PR #28 review O-3; pre-existing). **Resolved** by PR #37 under AUTH-012, merged at `e3a750883a90e52c7138dc72be11fcff3f1290d9` (head `39a8fdf`, base `b027e41`); post-merge CI run 45682383873 (#120) 7/7 with the full suite; Main review 7171553267. The empty-state message is outside any list, the list renders only with items, and a new e2e test covers both states with the axe `list` rule. **Carried forward to I-2:** O-1 (the new test leaves its Sales user and customer project in the database for later e2e projects).

**Closed: OI-113 (2026-11-26).** Deterministic approval identification and automatic final-balance initiation (WP-C review of PR #35, finding B-1, comment 7168769499): `approve_preview` emitted `release.approved` for the approval inserted first under the release lock, while `private.project_fulfillment_status` reported the earliest `approved_at`, so concurrent approvals could make WP-H's cross-check reject a legitimate initiation with `approval_mismatch` (fail closed). **Resolved** under AUTH-013 (option (a)) by PR #38, merged at `7226d6f60dcbf014033b1eb24b1e0e630d945942` (head `ae6c474`, base `05b32e9`; exact-head CI 45707874799 7/7); post-merge CI run 45725850769 (#131) 7/7 with the full suite. The interface now names the approval of the release's canonical `release.approved` event under six conditions, with no fallback; WP-H's strict equality is unchanged. Reviews: Main 7174631431 and 7175740664; WP-S 7174769687 and 7175762944; WP-B 7174846470 and 7175757171. Option (c) remains an emergency recovery procedure only (OWNER-RUNBOOKS §12). Informational findings are recorded in AUTHORIZATIONS AUTH-013 "Completion".

**Closed: OI-114 (2026-11-27).** Resolved by AUTH-015 with Amendment 1: PR #54 merged at `b5d8078` (exact-head CI 46066978313 7/7; post-merge CI 46077031048). Controlled, Owner-only recovery after a failed deployment or failed live verification; same-release re-authorization requires a recorded recovery; late verifications after a recovery are refused. *Original record:* (R1; AUTH-015 granted 2026-11-27; Owner decision 2026-11-26: "Include controlled recovery from failed live verification in R1"; WP-C prepares a narrowly scoped proposal preserving publication authorization, release identity, financial gates, auditability and verification requirements; no automatic bypass or uncontrolled redeployment).** After a deployment, its publication authorization stays active, so the staff page offers no new "Authorize publication" for the same release: there is no UI path to redeploy after a failed live verification. Found by WP-I in PR #42 (O-3); T-E2E-08's second authorization is labelled test setup. No decision is made.

**Partly closed: OI-115 (2026-11-28).** The local part is resolved by AUTH-016 (PR #55, `b294d33`; post-merge CI 46089426391); the hosted part remains open under AUTH-003. *Original record:* (R1; AUTH-016 granted 2026-11-27 for the local part; hosted part under AUTH-003; Owner decision 2026-11-26: "Include environment classification consistency in R1 hosted provisioning"; enforced within WP-D's scope; disagreement fails closed before environment-dependent privileged behavior or test-seam activation; WP-I prepares the proposal).** The database does not enforce agreement between `private.runtime_environment` and `private.environment_settings`. The seed sets both, and pgTAP `400_wpi_r1_fail_closed.test.sql` asserts their agreement and fail-closed absence. Found by WP-I in PR #42 (O-4). No decision is made. **Local part implemented (AUTH-016, WP-I PR; CURRENT-STATE §25):** `private.app_environment()` raises 42501 when C1 and C2 disagree (D1), the scanner check requires agreement, staging keeps no row (D2), and the application compares `APP_ENV` with the database before the mocked scanner, live verifier or payment gateway activates. Open until that PR merges with post-merge CI and the hosted check under AUTH-003.

**Closed: OI-119 (2026-11-28; AUTH-016, PR #55 `b294d33`).** *Decided 2026-11-27.* Implementing OI-115 D1 exactly as granted made six existing pgTAP files fail (100, 110, 120, 210, 310, 400: 247 subtests), because their setups create the very classification disagreement D1 now rejects (C1 changed while the seeded C2 row stayed). Found by WP-I as a stop condition; allocated and escalated by Main. **Owner decision (2026-11-27): option A**, setup and restoration statements only in exactly those six files and sites, every assertion, expected value, plan count and guarantee preserved, restoration verified; **point 1**, the application rule (development or test: both rows present, equal, development or test; staging, preview or production: no C2, C1 absent or equal to `APP_ENV`); **point 2**, `getStripeGateway()` async with an `await` at its three call sites. Individual dispositions in FD-14 format: CURRENT-STATE §25.2.

**Closed: OI-116 (2026-11-27).** Resolved by AUTH-014: PR #45 merged at `eacc8b5799a22958773012044c74023910af7083` (head `25a77a1`, base `a959a4a`; exact-head CI 46041562594 7/7; post-merge CI 46054458273). T-AUTH-11 now keeps its seven sends inside one fixed hourly window and fails loudly if they span two; no assertion, threshold or migration changed.

**Closed: OI-118 (2026-11-27).** Cause established by the Owner's Dashboard checks: **H1, sandbox mismatch.** The attempt 2 key belonged to "Setmore [Test mode]", which holds no products; the catalog is intact in "Spotlight Client Portal - Development" (all 11 products; `essential.deposit` matches the recorded IDs). Repository IDs, migrations and the accepted runner are unchanged. Remedy: the Stage A attempt 3 amendment binds the key to the dedicated sandbox's Stripe account ID (AUTHORIZATIONS AUTH-002). Record: CURRENT-STATE §13.

**Closed: OI-117 (2026-11-27).** Decided by the Owner: **option A**. Attempt 2 is reconciled against the key's "View request logs" view (Workbench), which the Owner confirmed is available and shows zero requests before entry. Cleanup order: remove the Network secret and its allow rule; record the per-key request log; expire the key promptly. Recorded in AUTHORIZATIONS AUTH-002 and in CURRENT-STATE §13 (attempt 2 Gate A record). The options considered remain in this file's Git history.

**Closed (2026-11-28): OI-120** (PR #61 merged at `19b173b`; post-merge CI 46086549947; AUTH-019 completed). *Original record:* ( (R1 release-candidate blocker; blocker for hosted migration deployment under AUTH-003; AUTH-019 granted 2026-11-27).** `private.is_owner()` returns NULL, not false, for a caller with no active staff role, so every `if not (private.is_owner() and …)` guard, and `private.owner_ok()`'s 18 callers, can be bypassed by a non-staff or revoked caller with fresh MFA (45 sites; reproduced locally: agreement-version creation by a client, Admin self-promotion to Owner, re-grant by a revoked staff member). Nothing deployed. **Owner decision (2026-11-27):** the root-function correction only (`coalesce(..., false)`), under AUTH-019. Closes on that PR's verified merge and post-merge CI. New code uses NULL-safe guards (`(...) is not true`). **Closure (AUTH-019):** migration `20261127125000_oi120_is_owner_null_safe.sql` redefines only `private.is_owner()` as `coalesce(..., false)`, attributes and ACL unchanged; pgTAP `420` covers the three reproduced escalations, one representative per site class against a fresh-MFA client, a revoked former staff member, an Admin, a Sales user and anon (no privileged state change), the genuine Owner's success, false-never-NULL for `is_owner()` and `owner_ok()`, and a mutation run; inventory in CURRENT-STATE §26. *Correction of the reproduced case (Main, 2026-11-27):* the second escalation was a fresh-MFA **client** promoting the Admin to Owner through `set_staff_role`; the Admin promoting itself was already refused and is kept as an extra guard.

**Closed: OI-121 (2026-11-27).** Fixed under AUTH-010 Amendment 1 in PR #59 (`30ee417`; post-merge CI 46080015419): charge.refunded uses a per-refund dedupe key; refund.* keys unchanged; each refund posts once, replay adds nothing, both cross-event orders recognize once. *Original record:* (R1; AUTH-010 Amendment 1, Owner 2026-11-27, option A). On `main`, a charge.refunded event with two or more refunds never posts: each refund's `payment.refund_recorded` uses the same dedupe key (`'payment.refund_recorded:' || stripe_event_id`) with a different subject, so `emit_domain_event` raises 23505 on the second (found and reproduced by WP-B; nothing deployed). **Owner decision:** refund-event keys unchanged; a per-refund key for charge.refunded; the verification in AUTHORIZATIONS AUTH-010 Amendment 1. Closes on the AUTH-010 PR's verified merge and post-merge CI.

**Closed: OI-122 (2026-11-28; AUTH-020, PR #64 `2ae3639`; post-merge CI 46103910059).** *Original record:* (R1; test reliability; found 2026-11-27 by the DEP-18 session, diagnosed by WP-B; AUTH-020 granted 2026-11-28). The AUTH-009 integration test `tests/integration/oi91-dispatch-revocation.test.ts`, "each function takes authorization, then invoice, then outbound request", fails intermittently under load (`expected 'unknown' to be …`). Cause: the helper `waitsOnRowOf` reads `pg_locks` and `pg_blocking_pids` at different instants, so one sample can see the waiter blocked before its tuple lock is visible; the holder is then not released, so later suites in the file hit 55P03. Reproduced on `main` without AUTH-018 (4 of 40 runs alone; 5 of 600 in WP-B's harness under load; the next sample always identifies the table). Not a product or lock-order defect. **Owner decision (2026-11-28):** AUTH-020, Tier 1, exactly as proposed, including deterministic failure cleanup. **Fix (AUTH-020, WP-B):** the approved one-file diff (`3675e8f8…`, as reported by WP-B and not independently verified; the base `bd596cff…` and patched file `27d324b0…` hashes are independently verified): `waitsOnRowOf` keeps polling within the same 40 × 50 ms deadline, and `probe()` and `race()` clean up on failure only (holders rolled back first, a wait of at most 10 s, never a commit); no assertion or expected value changed. Evidence A1 to A7 in CURRENT-STATE §27: before the fix, 2 of 42 runs failed under 6-way parallel load; after it, 0 of 40 alone and 0 of 42 under the same load. Closed on the verified merge and post-merge CI; WP-I's independent review and Main's final review found nothing blocking.

**Closed: OI-123 (2026-11-28; AUTH-016, PR #55 `b294d33`; Owner decision 2026-11-28).** *Found in PR #55's exact-head CI, run 46085318711.* With AUTH-016 (OI-115 D1) on top of `main`, AUTH-018's `330_dep18_scope_loader_activation.test.sql` aborts at test 76 of 137: its classification cases change `private.environment_settings` (staging, preview, absent, test) while `private.runtime_environment` stays `development`, and `private.app_environment()` raises on the disagreement. `main` is unaffected (AUTH-016 not merged). **Owner decision (Consolidated Owner Directive, 2026-11-28): approved exactly as reviewed, with the PR #55 allowlist change; dispositions in CURRENT-STATE §25.2.** Proposal: OI-119-option-A-style setup-only additions at four sites (+41 lines; no assertion, expected value, plan or description change; a restoration guard), measured with the 43 → 48 allowlist change: 330 137/137, full pgTAP 2,255, isolated 27/27.

**Open: OI-124 (R1; PWP-1, PWP-2; found 2026-11-28 by Main's read-only PWP investigation; awaiting the Owner).** *Contractual lock order: the implemented order and 04 §4A disagree.*
- **The conflict:** 04 §4A (Concurrency) gives a conceptual order: construction locks held alone; project row; order-summary row; per-package lock; bundle row. The implemented issuance (`20261126120000_wph_oi86_issue_order_summary_lock.sql`) takes a different order: the project row `FOR NO KEY UPDATE` (line 61), then the shared `dep18-scope-eligibility:<pkg>` lock inside `private.current_package_scope` (line 84), then the presented order-summary row `FOR UPDATE` (line 131).
- **Construction:** the AUTH-018 governance functions take the eligibility lock and then the sealing lock, and construct while holding both. They do not hold construction locks "alone".
- **Acceptance:** `private.accept_agreement` locks only the order-summary row (`20261124160000_wpb_agreements.sql`, the `for update` in `accept_agreement`). It is therefore not serialized against withdrawal, which T-CON-07 requires.
- **Main's proposal:** adopt the implemented order as canonical and amend 04 §4A to match:
  1. the project row;
  2. the per-package lock: shared for issuance, resolution and acceptance; exclusive for governance;
  3. sealing and construction locks, for governance only;
  4. the order-summary row;
  5. the bundle row.
- **What PWP-2 would change:** acceptance takes the per-package lock, shared, before the order-summary row. It reads the package key without a lock, then re-checks it under the lock. T-CON-07 proves both commit orders with no 40P01.
- **Status:** open until the Owner rules. This blocks the PWP-1 and PWP-2 grants.

**Open: OI-125 (R1 release-candidate verification; found 2026-11-28; awaiting the Owner).** *Fixture bundles cannot be verified in staging.*
- **The conflict:** R1 release-candidate acceptance runs in staging (01 §9.1, criterion 18). Fixture bundles are rejected outside `development` and `test`, and every component must agree on fixture status (04 §4A, T-CON-12, invariant 13). A non-fixture agreement is not loaded before counsel approves the final text (04 §1). Staging with no `environment_settings` row reads as `production` (D2).
- **The consequence:** contractual end-to-end verification in staging (PWP-4, R-04) needs counsel-approved content, whichever way OI-126 is decided.
- **Options:**
  - (A) The strict reading: staging verification of criterion 18 waits for counsel-approved content.
  - (B) A separately labeled verification-fixture class, allowed in staging and never in production. This needs an Owner amendment of invariant 13 and T-CON-12.
  - (C) Contractual end-to-end verification in an isolated hosted project classified `test`.
- **Main's recommendation:** A, which is the more restrictive reading. B and C are recorded as Owner options.

**Open: OI-126 (R1 release-candidate gate; found 2026-11-28; awaiting the Owner).** *What DEP-03 requires before R1 release-candidate acceptance.*
- **The conflict:** 01 §9.1 criterion 18 and 08 OI-112 stage 2 require the R1 portion of the DEP-03 evidence to be reconciled before release-candidate eligibility. That means counsel-approved R1 instruments, through PWP-3. OPEN-ISSUES DEP-03 reads "Phase 5 (Prod; before enforcement)", and the earlier CURRENT-STATE §7 wording read only "never presented as legally approved".
- **Rule applied:** under CLAUDE.md §2 the more restrictive reading applies, so counsel approval of the R1 instruments is required.
- **Status:** the Owner is asked to confirm. This sets the critical path.

**Open: OI-127 (AUTH-003 execution prerequisites; found 2026-11-28; awaiting the Owner).** The AUTH-003 record and the specifications leave these unresolved:
- (a) DEP-14 names hosted dev and staging projects; AUTH-003 is staging only.
- (b) Which Supabase project a Vercel preview with `APP_ENV=preview` uses. The environment schema rejects a non-local Supabase URL outside `staging` and `production` (03 §15).
- (c) Agents must never pass `--yes` (03), yet an agent's hosted change fails without it (03A). AUTH-003 authorizes migration pushes.
- (d) How hosted staging gets its classification. With no seed allowed and migrations environment-independent, staging reads as `production` (D2). This touches the hosted part of OI-115 and what staging can exercise.
- (e) How WP-I moves to, or is replaced on, `spotlight-staging-ops`, which no other session may use.
- (f) DEP-17 names no scheduler mechanism.
- (g) AUTH-003 lists monitoring integration "once DEP-12 is selected", while DEP-12 integration needs a separate grant. The more restrictive reading applies: a separate grant is required.
- (h) Whether staging may hold a Stripe test key or webhook secret, which DEP-17 reconciliation on staging would need.

**Open: OI-128 (rest of AUTH-002; found 2026-11-28; awaiting the Owner).** The AUTH-002 record leaves these unresolved:
- (a) The credential mechanism for the write-enabled test key. The Stage A Network-secret mechanism sets no precedent.
- (b) Whether the Stage A controls carry over: the sandbox account-ID binding, the eight-point attestation, the other-session acknowledgments and the Workbench reconciliation.
- (c) How the DEP-15 webhook signing secret is delivered without an agent seeing it.
- (d) Test refunds are permitted, but no Refunds permission is in the proposed key permissions. This is a provider fact to verify.
- (e) Whether the Stripe CLI is used, and which hosts it needs.

**Open: OI-129 (R1; PWP-1, PWP-2, PWP-5 specification gaps; found 2026-11-28; awaiting the Owner).** The specifications leave these undecided. Each needs an Owner ruling, recorded with the grant packages:
- (a) The older-bundle eligibility policy and the meaning of "newest such bundle" (04 §4A).
- (b) Where the scope fit check applies: the scope version, the bundle or both. Also whether the 300-character item limit applies (04 §4A, 08 OI-99).
- (c) Whether PWP-1 builds the Owner-controlled loader for instrument content, given that OI-106 says no loading mechanism is chosen.
- (d) Whether PWP-1 builds production eligibility and activation, or leaves them to DEP-20.
- (e) How the AUTH-018 scope-version approvals relate to approvals bound to the bundle hash. The "one-to-one" correspondence is asserted, not defined.
- (f) Whether any new confirmation version, or only a material change, needs renewed acknowledgment (05 §3A versus T-LC-19).
- (g) Read and write permissions for scope confirmations and operational notes.
- (h) The inactivity entities ("estimate suspension", "rescheduling eligibility"), whether the day-7 and day-14 actions are staff-recorded or system-sent in R1, and the transition for previews released before PWP-5.
- (i) The fixture labels for instruments and bundles.
- (j) The mechanism for reconciling legacy presented summaries (OI-102 versus DEP-20).

Main's recommendations are in the next-wave execution plan.

**OI-91 proposed architecture (separate work package; proposed AUTH-009):** `private.outbound_request_for_execution` body only: lock `payment_authorizations` before `final_balance_invoices`, matching revocation; detect an obligation whose release was withdrawn after initiation (read-only `preview_releases.withdrawn_at`) and notify the Owner once through `notify_owner` with the key `final_balance.release_withdrawn:<invoice id>` (the obligation stands, OI-92(e)); requests already claimed or in flight keep the existing `charged_after_halt` detection and Owner review, made explicit in tests and the runbook. Acceptance: two-connection outbound execution against revocation in both orders (no deadlock, no automatic charge after revocation, idempotency and single flight kept), one notification per withdrawn obligation under replay, in-flight behaviour documented. One reserved migration. **Design direction (Owner, 2026-11-25; approved, not authorized):** Option B pre-send dispatch confirmation (a set-once `dispatch_confirmed_at`, the narrow `outbound_guard` change); one lock order, payment authorization, then final-balance invoice, then outbound request, applied also in `handle_invoice_failed`, `handle_final_balance_paid`, `record_outbound_result` and `reconcile_outbound_request`; detection of withdrawal and of authoritative supersession of the originating release (WP-C `current_release` semantics) during execution and in the existing project reconciliation, with one deduplicated Owner notification; the obligation stands; claimed, confirmed, dispatched and recorded states are distinct, and confirmation is never proof of external dispatch; duplicate confirmations can never authorize two dispatches; fail-closed confirmation; deterministic hosted-only replacement; the residual interval between confirmation and HTTP dispatch is documented; provider automatic-collection timing stays unverified until authorized sandbox validation. The stale-unconfirmed-request optimization is deferred. Outstanding before authorization: the final inventory, the confirmation scope, and the claim-token mechanism. **Final design (2026-11-25):** recorded as the proposed record AUTHORIZATIONS AUTH-009 (not authorized).

**OI-93 architecture (AUTH-010 granted by the Owner, 2026-11-27; mandatory R1 requirement):** an Owner-only, fresh-MFA, live-session function that records an immutable conflict decision (event, chosen project from the recorded candidates, evidence references, reason; one per event) in a new private insert-only table, re-validates the chosen project against authoritative provider evidence, then lets the event take the normal attributed path once (a single permitted quarantined-to-processed transition in the `webhook_events` guard, recorded and audited) so `apply_reversal` posts it through the existing ledger rules; the other candidates' blocks clear only after that posting succeeds; replay of the decision or the event adds nothing; unsupported or undecided conflicts stay blocked. Needs a public Owner-only wrapper and an Owner screen; touches the `webhook_events` guard, so it is larger than OI-91 and stays a separate package. **Design direction (Owner, 2026-11-25; approved, not authorized; supersedes the guard-transition design above):** categories S1 (refunds) and S2 (disputes) in principle, with the unsupported list kept; one immutable decision per event; the original event stays immutable and quarantined and `webhook_events_guard` is unchanged; WP-H handler extraction and anomaly-branch change in principle after WP-H merges, with demonstrated behavioural equivalence; exact financial-effect proof (event and application identity, provider object, project, amount and currency, ledger entries and invariants, completeness), where an unrelated historical entry never satisfies clearance; append-only application attempts with Owner-only, fresh-MFA recovery and at most ten durably recorded attempts; reclassification under the event, charge and financial locks before posting. An Owner decision alone never clears a block. Outstanding before authorization: the refined treatment of an already-represented effect versus a legitimate later effect, the outcome classes (missing evidence, permanently unsupported, transient failure, applied), retry counting for transactions that cannot record an attempt, and the final inventory. **Final design (2026-11-25):** recorded as the proposed record AUTHORIZATIONS AUTH-010 (not authorized).

OI-85 to OI-89 were decided on 2026-11-25 (Owner disposition of Main's independent review of PR #23 at `72da723`); their decisions are in [08](docs/08-DECISIONS-AND-CHANGELOG.md). They allocate the WP-S proposals WPS-P1 to WPS-P7 and WP-B's review notes N1 to N5 without duplicate IDs: OI-85 = WPS-P1 + WP-B N4; OI-86 = WPS-P4 + WP-B N1; OI-87 = WP-B N5; OI-88 = WPS-P3; OI-89 = WPS-P2, P5, P6, P7, WP-B N3, and three shared files; WP-B N2 amends DEP-18. The WP-S proposal table remains in this file's Git history.

---

## Part 3 — Implementation and production dependencies

Earliest phase = the first original OI-02 phase whose **implementation** cannot proceed without the dependency (phases 3, 4, and 5 now correspond to WP-B, WP-C, and WP-D; OI-67). "Prod" = production launch authorization. Every dependency below is **incomplete** unless its status says otherwise.

| ID | Dependency | Action owner | Earliest phase | Status |
|---|---|---|---|---|
| DEP-01 | Stripe **test-mode** catalog created and test Price IDs recorded (OI-30; design OI-64, OI-65; manifest 04 §6.1) | Owner-authorized operator with a verified **test-mode** credential | Phase 3 | **Complete (2026-11-23).** All 11 products and 11 prices created and verified in sandbox "Spotlight Client Portal - Development" by run `dep01-20261123T220040Z-290aebd0`; IDs in 04 §6.5. The restricted keys are revoked (Owner-reported, 2026-11-24). |
| DEP-02 | Verify the live Price IDs (04 §5.2) against the live catalog | Owner / authorized implementer | Phase 5 (Prod) | Not started |
| DEP-03 | Qualified **legal review** of the agreement and related policies | Owner + counsel | Phase 5 (Prod; before enforcement) | Not started |
| DEP-04 | Qualified **tax review**; Stripe Tax production configuration (OI-36) | Owner + tax advisor | Phase 5 (Prod tax collection) | Not started |
| DEP-05 | **Legal/privacy review** of retention, deletion, data requests, DPAs, incident notification (OI-21, OI-40, OI-42) | Owner + counsel | Phase 5 (Prod) | Not started |
| DEP-06 | **Provider verification** per OI-39 (02 §10) | Implementer; escalations to the Owner | Phase 1 (Vercel, GitHub Actions); Phase 2 (Supabase); Phase 3 (Stripe); Phase 4 (Resend, Storage, client-site Vercel) | **In progress.** GitHub Actions: actions pinned to verified commit SHAs (Phase 1). **Supabase (local): verified** by the Phase 2 spike (03A §5); the Supabase CLI 3.2.0 release is checksum-pinned in CI. Hosted-only items remain (U-06 to U-08, U-10). Vercel: not verified, because Vercel access is not authorized in Phase 1. |
| DEP-07 | Malware scanning **vendor selection** after provider and cost verification (OI-31) | Owner (selection); implementer prepares a verified shortlist | WP-C (before scanned uploads can be released; before the R1 release candidate) | **Conditionally selected (Owner, 2026-11-27): Scanii Basic, US region**; conditions in CURRENT-STATE §13; integration needs a separate grant |
| DEP-08 | **Brand assets**: Owner confirmation of the official logo master (Phase 1); vector and variant assets and final visual approval (Prod) | Owner | Phase 1 (confirmation); Prod (final approval) | Phase 1 part **complete**: logo master confirmed 2026-11-23. Production part **outstanding**. |
| DEP-09 | **Production infrastructure** prerequisites P-1–P-9 (02 §11) | Owner + implementer | Phase 5 (Prod) | Not started |
| DEP-10 | **Branch protection** on `main` | Owner (GitHub settings) | Phase 1 | **Complete (2026-11-23)**. See detail below. |
| DEP-11 | Toolchain **version pins** verified against official sources (OI-11) | Implementer | Phase 1 | **Complete (2026-11-23).** See [docs/DEVELOPMENT.md §1](docs/DEVELOPMENT.md#1-toolchain). |
| DEP-12 | Monitoring, error-tracking, and RUM **vendor selection** (02 §8, OI-23) | Owner; implementer prepares a verified shortlist | Before the R1 release candidate (Owner-critical alerts use it in R1, OI-68) | **Conditionally selected (Owner, 2026-11-27): Sentry Team, US region**; conditions in CURRENT-STATE §13; integration needs a separate grant |
| DEP-13 | **Nonce-based Content-Security-Policy**: remove `'unsafe-inline'` from `script-src` (03 §13 T-SEC-03) | Implementer | **Phase 2 (required security work)** | **Complete (2026-11-23; merged to `main` in PR #4, merge commit `45d05f6`).** `src/proxy.ts` sets a per-request nonce CSP with `'strict-dynamic'` and no `'unsafe-inline'` for scripts or styles; no inline style attributes remain. Verified by T-SEC-03 and T-SEC-04 (e2e) and the Lighthouse budgets (T-PERF-01). |
| DEP-14 | **Hosted Supabase projects** (dev, staging): creation, configuration (sign-up disabled, OTP expiry, signing keys, TOTP, IP forwarding, SMTP), and migration pushes | Owner authorization; implementer executes | Before any hosted environment | Granted under AUTH-003 (not yet active). OI-50 and OI-51 decided. |
| DEP-15 | **Stripe test-mode webhook verification** (OI-63): a test-mode webhook signing secret, a way to deliver real test-mode events to a local server (for example the Stripe CLI), and a recorded verification run of the webhook handlers | Owner (credential and access authorization); implementer executes | WP-B | Not started. Runs under AUTH-002 once its activation conditions are met. |
| DEP-16 | Switch the required status checks to the aggregate `CI result` (OI-70): require `CI result`, `Lint, types, format, unit tests`, `Dependency audit`, and `Secret scan (gitleaks, full history)`; remove the e2e and Lighthouse jobs from the required list, because GitHub reports a skipped job as passing | Owner (GitHub settings, Tier 3) | Immediately after the governance correction PR merges | **Complete** (Owner-reported, 2026-11-24). `main` reports `protected: true` via the GitHub API; the ruleset check list is not readable from the agent session. |
| DEP-17 | **Hosted scheduler** (04 §13, 05 §5.4, §5.5): bind to a scheduler, with recorded runs and alerting (DEP-12): WP-B's billing job entry points (daily reconciliation, maintenance-recovery evaluation, webhook backfill, release approvals, outbound requests); WP-C's scan retries and revoked-object deletion retries | WP-D (staging, AUTH-003); Owner (production, Tier 3) | Before the R1 release candidate (staging); production launch | Not started. In R1 until then: staff trigger scan retries, the server retries due deletions opportunistically, the Owner retries deletions and runs reconciliation before authorizing publication |
| DEP-18 | **Standard package scope definitions** (OI-84(b); 03 §4.1, 04 §4): the Owner supplies, for each package key (Essential, Professional, Advanced, Signature, Prestige), the standard contractual deliverables that Sales-issued order summaries copy into the snapshot; loaded into `private.billing_package_scope` by a reviewed migration and recorded under 08 §6. **Formally amended (OI-106, OI-112, 2026-11-25; PWP-0):** no migration is an authorized contractual-content path; content is loaded only through an Owner-controlled, audited and hash-verified mechanism to be separately authorized; legal text and counsel evidence stay outside Git; scope items are approved deliverables traceable to SLM-CPS-002 once it is completed, approved and published (OI-99). **Closure criteria (OI-112):** authorized non-production materialization (PWP-4) and contractual integrity and end-to-end verification covering the complete R1 lifecycle including PWP-5 (R-04); production activation is DEP-20. The v0.1.0 reconstruction drafts are not content for this dependency. **Superseded in part (Owner decision FD-05, 2026-11-25):** the reviewed-migration loading requirement is replaced by an Owner-controlled, audited and hash-verified contractual content loading mechanism; the formal amendment is prepared in PWP-0 (not active); no content loading is authorized. No authoritative definition exists today (`private.billing_packages` holds key, name, and cents only). The scope language is in counsel review (DEP-03, A4). **Owner-confirmed (2026-11-24, A5):** mandatory before R1 release-candidate acceptance; **rows are append-only (Owner, 2026-11-25; WP-B review N2; implemented in PR #23): an existing row is never updated, deleted, or truncated, and every new contractual definition is a new version**; **Version completeness (Owner, 2026-11-25; WP-B corrected-head review):** existing scope rows cannot be updated, deleted, or truncated (append-only row protection), and issued contractual snapshots stay immutable; but a privileged migration can still **insert an additional position into an existing version**, so complete version reproducibility is **not yet enforced**. Before any non-fixture package-scope content is introduced, DEP-18 requires **atomic version creation and sealing**: a sealed version rejects every later addition, update, deletion, and truncation.; issuance fails closed when no approved scope exists; definitions are server-controlled and versioned; order-summary snapshots are immutable; issued summaries are never altered retroactively | Owner (content); WP-S (table and loader, AUTH-005) | Before Sales-issued order summaries are used outside local and CI tests, and before R1 release-candidate acceptance (mandatory) | **In progress (status corrected 2026-11-28):** version sealing delivered (WP-D18, PR #27 `05b32e9`) and interim loading and activation infrastructure delivered (AUTH-018, PR #57 `23346ef`; activation for `development` and `test` only); **the Owner's scope content is not supplied**, real content loading is not authorized, and closure needs PWP-4 and R-04. Until then, Sales issuance fails closed outside the test-only seed |
| DEP-19 | **Contractual architecture implemented** (OI-98 to OI-104, OI-111, OI-112): instruments, bundles, governance events and withdrawal (PWP-1); standardized issuance for every role and versioned snapshots (PWP-2); project-specific scope confirmation, mandatory acknowledgment and the inactivity reconciliation (PWP-5); each merged with its tests, including implementation-level concurrency verification (R-02) | Implementer under separate authorizations; Owner | Before R1 release-candidate acceptance (mandatory) | Not started. No authorization granted |
| DEP-20 | **Production contractual activation** (OI-102, OI-103, OI-112): after R1 release-candidate acceptance and a Tier 3 production deployment authorization, reconcile every ineligible legacy presented summary, record production eligibility and activation for counsel-approved bundles, and verify after activation. A production gate, not a release-candidate prerequisite | Owner (Tier 3); authorized implementer | Production launch | Not started |

### DEP-01 detail — Stripe test-mode catalog

- **Authorized scope:** create only the missing test-mode products and prices matching 04 §5.1, following 04 §6.
- **Catalog design (approved 2026-11-23):** 11 products and 11 prices (OI-64), with the naming, metadata, catalog keys, lookup keys, and versioning in 04 §6.1 (OI-65). Conflict handling and idempotency: 04 §6.2. Execution constraints: 04 §6.3. Failure handling, reconciliation, and concurrency: 04 §6.4. Credential and sandbox: 04 §6.5. This is a design approval only.
- **History (2026-11-23):**
  1. `api.stripe.com` was first blocked by the session network policy.
  2. A credential was then saved to the session environment. A single read-only verification request showed it was a **live-mode** key, and Stripe rejected it as invalid.
  3. No search, create, or update request was sent, and no Stripe object was created or modified.
  4. **Catalog run `dep01-20261123T142608Z-0295d87d`** (14:26:08–14:26:09Z, sandbox "Spotlight Client Portal - Development", 6 requests): `GET /v1/balance` returned `livemode: false`; the sandbox held no products or prices; all 11 entries classified *missing* with no conflict. Request 6 (`POST /v1/products`, key `dep01-v1-essential.deposit-product`, Stripe request `req_v8jMoDuB0OsJq0`) returned HTTP 200 with `Stripe-Should-Retry: false`, and the run stopped under the rule then in force (see OI-66). Nothing else was created.
  5. **Read-only reconciliation `dep01-reconcile-20261123T143019Z-defd3b34`** (14:30:19–14:30:20Z, 6 `GET` requests, all `livemode: false`): the sandbox holds exactly one product, `prod_VgKrmaWefVnWy1`, which matches the 04 §6.1 manifest for `essential.deposit` exactly (name, all metadata, active, no default price). It has **no price**, no price uses `spotlight_v1_essential_deposit`, and the sandbox holds no prices at all. A resumed run would classify `essential.deposit` as *price missing* and the other 10 entries as *missing*.
  6. **Resumed catalog run `dep01-20261123T220040Z-290aebd0`** (2026-11-23T22:00:40Z to 2026-11-23T22:00:49Z, 48 requests, Owner-authorized after OI-66 merged at `f543054`): `livemode: false` on every response; classification as expected with no conflict; 10 products and 11 prices created, 1 product reused; all 11 entries verified against 04 §6.1. Stripe sent `Stripe-Should-Retry: false` on every successful create; under OI-66 it was recorded only, and nothing was retried. **Catalog complete**; IDs in 04 §6.5.
- **Current status (2026-11-24):** complete. The following is **Owner-reported** and was not independently checked:
  - The restricted keys used for DEP-01 are revoked, and Stripe live mode shows no restricted keys.
  - The `chris-pribyl` and `spotlight-client-portal-dev` environments hold no network secrets and no environment variables. The earlier live-mode secret was removed from `chris-pribyl`.
  - `api.stripe.com` is not on the `spotlight-client-portal-dev` allowlist.
- **Future Stripe access:** only under AUTH-002 ([docs/AUTHORIZATIONS.md](docs/AUTHORIZATIONS.md)), after its activation conditions are met.
- **Historical record:** the earlier environment checks and the unblocking conditions that applied before DEP-01 are preserved in this file's Git history (v0.12.0).
- **Credential permissions [PROPOSED; provider model verified 2026-11-23]:** a restricted sandbox key (`rk_test_…`) created by the Owner in the Stripe Dashboard, in the one sandbox chosen for DEP-01 and all later test-mode development (04 §6.5). Per [Restricted API keys](https://docs.stripe.com/keys/restricted-api-keys), each permission is None, Read, or Write, and **Write includes Read**:

  | Resource | Level | Needed for |
  |---|---|---|
  | Balance | Read | `GET /v1/balance`, the fail-closed `livemode: false` check before any other request (04 §6.3). The field was confirmed in Stripe's OpenAPI specification (`2026-09-30.endive`, commit `2dcbcfb`) on 2026-11-23, and the Owner attests the `rk_test_` key; the run does not rely on this response alone. **Inferred** from Stripe's documented rule that `GET` requests need Read; the documentation does not name the Balance resource, so it must be confirmed on the Dashboard when the key is created. |
  | Products | Write | list, retrieve, and create products. Write includes Read (verified), so no separate Products Read setting is needed. |
  | Prices | Write | list (including by `lookup_keys`), retrieve, and create prices. Write includes Read (verified). |
  | Every other resource | None | — |

  - If the Dashboard groups prices under the Products resource, that single resource is set to Write.
  - If the Dashboard offers Read and Write as separate options, both Read and Write are granted for Products and Prices.
  - The search endpoints (`/v1/products/search`, `/v1/prices/search`) are not used. List endpoints are used instead.
  - A permission error during the run aborts it. The key is never broadened mid-run.
  - **Idempotency (verified 2026-11-23):** Stripe keeps keys for at least 24 hours and may remove them afterward; a reused expired key may execute a new request; identical retries can return the saved response, including HTTP 500; `Stripe-Should-Retry: false` prohibits retrying. The run therefore never retries an ambiguous create automatically, reconciles before resuming, and never runs concurrently (04 §6.4).
  - The key is entered by the Owner only through the secure credential form for `api.stripe.com` on `spotlight-client-portal-dev`. It is never pasted in chat, committed, or logged. The Owner revokes it after the IDs are recorded.

### DEP-03 detail — legal review scope

- Final agreement text and versioning (OI-34) and signer authority wording (OI-28).
- Payment-hold notice terms (draft §12 vs OI-26) and the Owner-authorized termination path after failed payment (OI-46).
- Draft §7 "designated billing portal" wording vs disabled self-service cancellation (OI-29).
- Draft §7 "discontinue hosting after the current paid period" vs the revised OI-35 milestones: M1 (12 business days, maintenance and designated infrastructure cessation) and M2 (60 calendar days, final transfer and offboarding). Also: the definition of the effective cancellation date, the definition of designated recurring infrastructure, the required notices before M2, and the one-year initial domain term with renewal responsibility. Incorporate only from the final counsel-approved copy.
- The calendar convention, including trigger-date exclusion (OI-43).
- Disclosure of adjusted final balances (OI-44).
- Refund terms (OI-35), domain ownership and transfer, IP ownership (OI-32; draft §5, §8), and dispute terms (OI-37).
- **R1 final-payment wording (OI-68, revised by OI-74):** the hosted-only R1 question is superseded; R1 now charges automatically under the §3.1 clause. Counsel confirms the R1 approval screen wording (**Approve Website & Authorize Final Payment**), the card-retention disclosure, and the contractual effect of revoking the authorization and of re-authorizing after revocation (04 §8.1).
- Unused-upload deletion terms (OI-42), coordinated with DEP-05.
- **Withdrawal or supersession of an approved release after the final-balance charge was durably initiated (OI-92(e)):** the obligation stands; counsel confirms the contractual position and client wording.
- **Contractual package-scope language (OI-84(b), DEP-18; Owner, 2026-11-24, A4):** the standard deliverables of each package as they appear in order summaries, together with the agreement and payment-authorization wording. Unreviewed scope language is never represented as legally approved.
- **Evidence standard (OI-107, 2026-11-25):** closure needs an identifiable final publication copy and counsel approval evidence naming the approved document versions, the approval scope and bundle combinations, outstanding conditions (incorporation by reference; OI-74 revocation effects; OI-92(e); additional-work terms, OI-101; maintenance qualifications, OI-108), the Christopher Pribyl legal identity correction in every formal legal representation, the final publication text hashes, and the relationship between reviewed text and materialized content. Evidence stays outside Git; the repository records identifiers and hashes only (OI-106).
- **Reconstruction status (Owner, 2026-11-25):** the original contractual suite is unavailable; SLM-CPS-001 to SLM-CPS-007 v0.1.0 are reconstruction drafts without contractual issuance authority; the earlier Owner-reported counsel approval of the original specifications is historical, unverified, and does not attach to the drafts. The 04 §3.1 clause-specific approval is unchanged; its byte-for-byte verification against the final publication copy is outstanding (OI-109).

### DEP-06 detail — provider verification items added by OI-43 to OI-46

- **Stripe:** a Checkout Session-level discount restricted to the balance product with a single redemption, which must never attach to the customer or subscription (OI-44). *Superseded by OI-55: verify the invoice-level discount in the next item instead.*
- **Stripe (OI-47, approved 2026-11-23):** a subscription-mode Checkout Session created with no discounts and with promotion codes disabled, so neither the deposit nor the maintenance line can be reduced.
- **Stripe (OI-17 revised, 2026-11-23):** saving the payment method in subscription-mode Checkout for a later off-session, one-off charge; an automatically charged one-off invoice using the standard balance Price ID; the events for failed charges and required authentication; the Stripe-hosted page for completing the same invoice; idempotency keys; and, for OI-55 (approved, option A), an invoice-level discount restricted to the balance product.
- **Stripe:** the subscription state after exhausted retries (`past_due` / `unpaid` vs cancellation) and the related events (OI-46).
- **Stripe (OI-74, 2026-11-24; documentation facts in 04 §8.2):** in test mode, confirm where subscription-mode Checkout stores the card (subscription default or Customer); card-wallet behavior under `allowed_payment_method_types: ["card"]`; an automatic off-session charge of the one-off invoice with an explicit `default_payment_method`; `invoice.payment_action_required` and hosted completion of the same invoice; finalizing an invoice without an automatic attempt when the authorization is not active; setup-mode Checkout for an existing Customer; and the `payment_method.detached`, `payment_method.automatically_updated`, `setup_intent.succeeded`, and `setup_intent.setup_failed` events.
- **Stripe (PR #20 review F7, F8, N1; 2026-11-24):** the test-mode acceptance criteria in 04 §8.2 (stop of automatic collection, saved-card fields, and charge linking including multi-payment invoices). F7, F8, and the N1 linking criterion are **mandatory before R1 release-candidate acceptance** together with N1 (04 §15.2.1 rule 9).
- **Supabase / Postgres:** time-zone database support for America/Detroit evaluation (OI-43). Backup expiry behavior for deleted data (OI-42).
- **Domain registrar (to be selected; revised OI-35):** registration date and expiry data, auto-renew settings, the transfer (auth code) process, and confirmation that hosting deactivation cannot affect a registration.
- **Vercel / infrastructure (revised OI-35):** discontinuing designated per-client resources at M1 independently of the remaining hosting.

### DEP-06 detail — Phase 2 Supabase verification (2026-11-23)

- 31 provider facts are verified with source citations in `docs/03A-SUPABASE-PROVIDER-VERIFICATION.md`.
- Verification used the official documentation source in the vendors' GitHub repositories, because `supabase.com` and `nextjs.org` are blocked by this environment's network policy.
- U-01 to U-05 and U-11 were **resolved by the Phase 2 local verification spike on 2026-11-23** (03A §5, S-01 to S-08). No result contradicted an approved decision; the implementation notes were approved by the Owner on 2026-11-23 (OI-53, with N-8 amended).
- U-06 to U-08 and U-10 still need hosted or dashboard access, or Owner checks (DEP-14, OI-50). U-09 is not needed.

### DEP-06 detail — contractual technical verification TV-01 to TV-03 (Owner, 2026-11-25)

None of these is complete. Provisional values are not contractual commitments until validated and approved (OI-108).

- **TV-01 (software catalog, contractual architecture and versioning compatibility):** verified from the repository: the five package keys and cents match the approved pricing (04 §5.1); maintenance is fixed at 9,900 cents; the 50-item, 300-character and 8,192-byte limits and their mismatch are identified (OI-99). Outstanding: measurement of the final approved deliverables and instruments against those limits and the 200,000-character agreement limit; the 04 §3.1 byte-for-byte check (OI-109). Needs final publication artifacts (DEP-03).
- **TV-02 (Stripe product and price consistency):** the test-mode catalog was verified on 2026-11-23 (DEP-01). Outstanding: the live catalog (DEP-02); no catalog representation exists for the $25 domain allowance (CD-12) or the $125 hourly rate (CD-14); creating any Stripe object is an Owner action. No Stripe access is authorized here.
- **TV-03 (hosting and maintenance infrastructure feasibility):** provisional allowances and frequencies: 5 GB website asset storage; 100 GB monthly transfer; 2,000 monthly form submissions; five-minute availability monitoring; daily recoverable backups; a thirty-day backup retention target; weekly vulnerability checks; monthly website health, technical SEO and routine maintenance reviews. Evidence needed: provider plan documentation and the documented metering method (INT-02); the form-submission counting method; the monitoring vendor's capability (DEP-12); the backup retention provider fact (02 §10) and a restore test (02 §11, P-7); vulnerability tooling; a runbook procedure for the monthly reviews. No hosted access is authorized here.

### DEP-08 detail — brand assets

- **Complete (Phase 1 part):** on 2026-11-23 the Owner confirmed that the single logo file in the official SLM folder is the official master (07 §10.1).
- **Outstanding (production part):**
  - a vector master
  - transparent and light-background variants
  - a favicon and app icon
  - Owner approval of the palette, typography, email branding, and final visual design

### DEP-10 detail — branch protection (complete)

The Owner created the GitHub repository ruleset `protect-main` on 2026-11-23:

| Setting | Value | Evidence |
|---|---|---|
| Enforcement | Active | Owner-attested |
| Target | Default branch (`main`) | Owner-attested. The GitHub API reports `main` as `protected: true` and the documentation branch as `protected: false` (checked 2026-11-23). |
| Require a pull request before merging | Enabled. Direct pushes to `main` are blocked. | Owner-attested |
| Required approvals | **0**. This is an Owner decision while the Owner is the sole developer. It replaces the earlier recommendation of 1 approval plus an admin bypass. | Owner-attested |
| Block force pushes | Enabled | Owner-attested |
| Restrict deletions | Enabled | Owner-attested |
| Required status checks | The 5 CI jobs: Lint, types, format, unit tests; Lighthouse budgets; Dependency audit; Secret scan; Database, integration, and e2e tests. "Require branches to be up to date" is on. To be switched to `CI result` under DEP-16. | **Verified** 2026-11-24 via the GitHub API (`/repos/…/rules/branches/main`) |

**Verification:** on 2026-11-24 the GitHub API returned active rules for `main` including deletion, non-fast-forward, creation, pull request (0 approvals), and required status checks. Earlier, the session's GitHub tools could confirm only the branch's protected status, and could not read ruleset rule details. The individual rules above are recorded from the Owner's confirmation, and they have not been tested with a write attempt against `main`.

**Follow-ups [PROPOSED]:**
- ~~Add the Phase 1 CI checks as required status checks once they exist.~~ Done (verified 2026-11-24). Next step: DEP-16.
- Raise required approvals to 1 when a second reviewer joins.
