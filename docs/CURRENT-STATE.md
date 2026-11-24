# Current State

| Field | Value |
|---|---|
| Version | 1.8.0 |
| Status | **Canonical status record** (OI-67). Every pull request that changes status updates this file in the same pull request. |
| Last updated | 2026-11-24, by PR #18 (OI-73 to OI-83 decided; pre-merge security reconciliation: scan-result authority, billing jobs, dispute evidence; AUTH-005 proposed, not granted), based on `main` at `19b68cb` |

This file replaces the status tables that were previously repeated in CLAUDE.md §1, README, 01 §8, 08 §4, OPEN-ISSUES headers, and 04 §6. Those places now link here. **What is authorized** is in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). **What was decided** is in [08](08-DECISIONS-AND-CHANGELOG.md). Detailed dependency records are in [OPEN-ISSUES.md](../OPEN-ISSUES.md).

Evidence labels: **Verified** (checked from repository or provider evidence, with the source named) · **Owner-reported** (stated by the Owner, not independently checked).

## 1. Authorization summary

| Item | State |
|---|---|
| Architecture | Approved |
| Specifications | All approved, with scope limits in §3 |
| Active authorizations | AUTH-000 (Tier 0, standing); **AUTH-001** (Tier 1: WP-A, WP-0, WP-B and WP-C on local and CI); **AUTH-004** (scoped Tier 2: WP-C storage policies, local and CI) |
| Granted, not yet active | **AUTH-002** (Stripe sandbox; scope amended 2026-11-24 to include setup-mode recovery sessions), **AUTH-003** (hosted non-production). Activation conditions are in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). |
| Production launch | **Not authorized.** No real client payment may be accepted until production launch authorization (Tier 3) is granted. |
| Deployments | None. Nothing is deployed. |

## 2. Releases and work packages (OI-67, OI-68)

| Item | Scope | State |
|---|---|---|
| Phase 1, Foundation and CI | Tooling, CI, design tokens | **Done** (PR #2) |
| Phase 2, Auth, security, tenancy | Invitation-only OTP, MFA, RLS, audit, nonce CSP, private storage policies | **Done, local only** (PR #4) |
| WP-A | Governance and specification correction | **Done** (PR #14, merge commit `d6d795a`) |
| WP-0 | Shared contracts: domain-event and outbox tables, state-domain types, audit action names, gate-function interfaces | **Done** (PR #15, merge commit `60954d4`; post-merge CI run #39 on `main` concluded `success`, 2026-11-24). OI-71 and OI-72 decided. Integration closed by the integration closure PR. |
| WP-B | Agreements, payments, webhooks, ledger, reconciliation (R1 scope), including OI-74, OI-75, OI-81, OI-83 | **PR #20 open** (`wp-b/billing-ledger` at `ae482c4`, base `19b68cb`; CI run 45333439725 `CI result` success). **Not merge-ready:** predates PR #18 (no OI-74 automatic collection or payment authorization) and uses its own OI-73 to OI-75 (now OI-81 to OI-83). Directives in §9. |
| WP-C | Intake, uploads, approvals, publication authorization, admin queue (R1 scope) | **PR #19: §9 WP-C directive items 1–9 implemented; awaiting remote CI and Owner approval (item 10).** Branch `wp-c/fulfillment-r1`, merged with `main` at `77a887b`. CI root cause fixed with authoritative scan results (05 §5.5: sequence after the row lock, scan attempts, malware always wins including revocation after release, exact bytes); tests 64 and 69 unchanged. OI-78 corrections, `payment_authorization_ready` intake check, OI-79 values, approval label, dispute evidence interface, WP-C browser tests. Local evidence: pgTAP 632/632, unit 191/191, integration 28/28, e2e 39/39, Lighthouse pass; remote CI is recorded in the PR. |
| WP-S | Sales Representative authorization infrastructure (03 §4.1; approved as a separate work package, OI-78) | Not started. Needs AUTH-005 granted and activated, and its entry criteria (AUTHORIZATIONS §3A). |
| WP-D | Hosted non-production infrastructure, then production readiness | Not started. Needs AUTH-003 active. Production steps are Tier 3. |
| WP-E | Legal, tax, and commercial approvals | Owner. Not started (DEP-03, DEP-04, DEP-05). |
| **R1** release candidate | Complete controlled transaction (01 §9.1) | Not started |
| **R2** release candidate | Fulfillment automation (01 §9.2) | Not started |

Former phases 3–5 map onto these work packages (01 §7). Phase numbers are no longer used for authorization.

## 3. Specifications

| Spec | Version | State |
|---|---|---|
| 01 Project overview | 0.4.2 | Approved (v0.4.1: OI-74, OI-77; v0.4.2: §9.1.1 integrated R1 browser acceptance, Owner direction) |
| 02 Architecture and environments | 0.4.0 | Approved |
| 03 Security, auth, tenancy | 0.5.4 (OI-77, OI-78, OI-79, OI-83) | Approved (03A is supporting evidence) |
| 04 Agreement and billing | 0.9.3 (OI-74, OI-81, OI-82; job and evidence ownership) | Approved for implementation and test mode. **Not approved for production:** legal review (DEP-03) and provider verification (DEP-06) remain conditions, including the OI-82 allocation model. |
| 05 Lifecycle and uploads | 0.4.4 (OI-74, OI-79; §5.5 scan-result authority) | Approved |
| 06 Publishing and post-launch | 0.5.1 (OI-79 item 5) | Approved |
| 07 Notifications, privacy, design | 0.4.0 | Approved. Retention periods remain provisional (DEP-05). |
| 08 Decisions and changelog | 0.19.0 | Approved. The provenance caveat in 08 §1 still applies to transcribed decisions. |
| AUTHORIZATIONS, CURRENT-STATE | 1.5.0 (AUTH-002 scope amended, still inactive; AUTH-005 scope final with rate limiting, not granted), 1.8.0 | Approved |
| CLAUDE.md | rewritten 2026-11-24 | Approved |

## 4. Dependencies

| ID | Item | State |
|---|---|---|
| DEP-01 | Stripe sandbox catalog | **Complete.** 11 products and 11 prices verified (04 §6.5). |
| DEP-02 | Live Price ID verification | Not started (Tier 3, before production) |
| DEP-03 | Legal review of the agreement and policies | Not started. **Start now** (longest external lead time). Includes the R1 approval wording, the card-retention disclosure, and the effect of authorization revocation (OI-74; OPEN-ISSUES DEP-03 detail). |
| DEP-04 | Tax review and Stripe Tax configuration | Not started. Start now. |
| DEP-05 | Privacy and retention legal review | Not started. Start now. |
| DEP-06 | Provider verification | In progress. Stripe items run under AUTH-002; OI-74 documentation facts recorded (Tier 0, 04 §8.2), test-mode confirmation outstanding. Vercel, Resend, Storage items run under AUTH-003 and WP-C. |
| DEP-07 | Malware scanning vendor | Not started. A verified shortlist is a WP-A follow-up deliverable; the Owner selects before the R1 release candidate. |
| DEP-08 | Brand assets for production | Production part outstanding |
| DEP-09 | Production infrastructure | Not started (Tier 3) |
| DEP-10 | Branch protection | **Complete.** See §5. |
| DEP-12 | Monitoring vendor | Not started. Shortlist with DEP-07. |
| DEP-14 | Hosted Supabase staging | Not started. Unblocked by OI-50 and OI-51 (decided); runs under AUTH-003. |
| DEP-15 | Real test-mode webhook verification | Not started. Runs under AUTH-002. |
| DEP-16 | Switch required status checks to `CI result` | **Complete** (Owner-reported, 2026-11-24). `main` reports `protected: true` via the GitHub API (**Verified**); the ruleset's check list cannot be read from the agent session. |
| DEP-17 | Hosted scheduler for billing jobs (04 §13) | Not started. WP-D under AUTH-003 (staging), Tier 3 (production). Required before the R1 release candidate. |

## 5. Verified facts

| Fact | Evidence |
|---|---|
| `main` is protected by ruleset `protect-main`: pull request required (0 approvals), force pushes and deletions blocked, and 5 required status checks with "require branches to be up to date": Lint, types, format, unit tests; Lighthouse budgets; Dependency audit; Secret scan; Database, integration, and e2e tests | **Verified** 2026-11-24 via the GitHub API (`/repos/…/rules/branches/main`) |
| **Discrepancy (open):** the row above predates DEP-16, which reports that the required checks were switched to the aggregate `CI result` (Owner-reported). The agent session cannot read the ruleset's check list (the GitHub tools available here return only `protected: true`). | **Open.** Closes on **Owner-provided evidence**: a ruleset JSON export, or a screenshot of the `protect-main` ruleset's required status checks, reviewed in a documentation PR that records the exact check names |
| `main` at `19b68cb` (PR #17 merge; parents `3f3b59d`, `33c082b`; tree identical to the reviewed head). Post-merge CI run #43 (id 45322697836): all 7 jobs `success`, including `CI result` | **Verified** via the GitHub API, 2026-11-24 |
| The `spotlight-client-portal-dev` environment: Limited network; allowlist `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; no network secrets; no environment variables | **Verified** via the environment API, 2026-11-24 |
| The Stripe sandbox catalog exists as specified | **Verified** by run `dep01-20261123T220040Z-290aebd0` (04 §6.5) |
| The restricted Stripe keys used for DEP-01 are revoked; no restricted keys remain in live mode; `chris-pribyl` and `spotlight-client-portal-dev` hold no network secrets or environment variables; `api.stripe.com` is not on the `spotlight-client-portal-dev` allowlist | **Owner-reported**, 2026-11-24 |
| The `spotlight-client-portal-dev` allowlist is `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; network access is Limited | **Owner-reported**, 2026-11-24 |
| CI post-merge run #35 on `e7c8d47` concluded `success` | **Verified** via the GitHub API |

## 6. Pending Owner actions

1. Review and merge PR #18 (all issues OI-73 to OI-83 decided). Then WP-C and WP-B apply the §9 directives; neither is merge-ready yet.
2. Provide evidence of the required status checks on `main` (§5 discrepancy): a ruleset export or settings screenshot showing `CI result` as required.
3. **AUTH-005** (scope final, v1.5.0) authorizes nothing until you grant it and its entry criteria are met.
4. Engage counsel and a tax advisor (DEP-03, DEP-04, DEP-05). DEP-03 includes the OI-74 items and the OI-82 refund and allocation terms.
5. When ready for WP-B's Stripe work: meet the AUTH-002 activation conditions (the OI-82 provider checks, DEP-06, run under AUTH-002).
6. When ready for WP-D: create the accounts in AUTH-003.

## 7. Known follow-ups

| Item | When |
|---|---|
| `supabase/.temp` files tracked although ignored | **Done in WP-0.** `postgres-version` stays tracked on purpose (it pins the database image CI tests against, 17.4.1.054) with an explicit `.gitignore` exception; `cli-latest`, an empty update-check cache, is untracked. |
| DEP-07 and DEP-12 verified vendor shortlist | WP-A follow-up |
| PR #6 (AI operations proposal): header corrected to the current next unused ID; remains a draft outside the release path (OI-67) | Done in PR #6 |
| Time tracking: each implementation PR description records AI session hours, Owner review hours, and admin hours (OI-67) | From WP-0 onward |
| Code comments still describe OI-71 as open: `src/domain/contracts/gates.ts` (lines 12, 77), `state-domains.ts` (134), `audit-actions.ts` (12). The merged migration's comment (line 70) is immutable and stays. | First WP-B or WP-C PR that touches the file (WP-B sets `GATE_SOURCES.G1`, WP-C sets G6) |

## 8. Parallel execution: WP-B and WP-C (approved 2026-11-24)

| Rule | WP-B | WP-C |
|---|---|---|
| Branches | `wp-b/*` | `wp-c/*` |
| Base | The merge commit of the integration closure PR | Same commit |
| Owns (writes only its own) | Agreement versions and acceptances, order summaries, Checkout records, webhook events, ledger, reconciliation, disputes, refunds, subscription mirror, billing holds (`maintenance_payment_hold`, `dispute_risk_hold`, `owner_manual_hold`), final-balance invoices, the derived non-financial payment projection (03 §4, OI-72) | Intake, uploads and quarantine, preview releases, approvals, outreach, `approval_nonresponsive_hold`, QA and security evidence, domain readiness, gate evaluator results, publication authorization and deployment records, derived queues |
| Gate interface | Implements `private.project_financial_status`; adds G1 attributes | Implements `private.project_fulfillment_status`; adds G6 attributes; builds the single gate evaluator (reads only the two interfaces; G8 fails closed) |
| Events | Registers its own types; consumes `release.approved` durably idempotently, keyed to the approved release and the order summary (one final-balance invoice per obligation, 04 §10) | Registers its own types; emits `release.approved` for exactly the approved release |
| Migrations | New timestamped files only; never edit merged migrations; ordering coordinated by the integration stream | Same |
| pgTAP files | `1xx_*.test.sql` | `2xx_*.test.sql` |
| Shared files (additive, own section only) | `src/domain/contracts/*`; `GATE_SOURCES.G1` | `src/domain/contracts/*`; `GATE_SOURCES.G6` |
| Authorization | AUTH-001 (AUTH-002 inactive: mocked Stripe client and synthetic signed events only) | AUTH-001 and AUTH-004 |

The integration stream owns cross-package verification, shared-file conflict resolution, migration ordering, and the end-to-end R1 journey test.

**Integration dependencies and merge sequence (OI-74; proposed by the integration stream, 2026-11-24; to be reconciled against the actual WP-B and WP-C branches once they are pushed):**

WP-B and WP-C already have substantial local implementation (Owner-reported). Their work is preserved; neither stream restarts. The sequence below is the target order of *dependencies*, not a required PR split: if a branch already contains the contract extension together with its features, it lands in that branch's first PR. No work is duplicated or re-implemented to fit the table.

| # | Merge | Why first |
|---|---|---|
| 1 | PR #18 (OI-73, OI-74 documentation) | WP-B and WP-C implement against 04 v0.9.0 and 05 v0.4.2. Branches started from `19b68cb` merge `main` after it (documentation only; no code conflict). |
| 2 | **Contract extensions land first within each package's first PR (or as a separate small PR only if the branch already separates them):** WP-B adds `agreement_state`, `agreement_effective`, `payment_authorization_ready`, `payment_authorization_state` to `private.project_financial_status`; WP-C adds `domain_ready`, `domain_check_id`, `domain_checked_at` to `private.project_fulfillment_status`. Each increments `contract_version`; stubs stay fail-closed (`implemented = false`). | WP-C's intake precondition reads `payment_authorization_ready`; the gate evaluator reads G1 and G6. Landing the attributes early removes cross-package waiting. |
| 3 | Feature PRs in either order, each rebased on `main`, with new timestamped migrations | Migration order is set at merge time by the integration stream; a merged migration is never edited. |
| 4 | WP-B `release.approved` consumer and the automatic final-balance invoice; WP-C gate evaluator | Both read the other package's contract only through the interfaces and the registered event. |
| 5 | Integration PR: end-to-end R1 journey test (mocked Stripe, synthetic signed events) | Needs both packages. |
| 6 | After the Owner activates AUTH-002: test-mode verification (DEP-15, the 04 §8.2 open items) | Not before activation. |

**Reconciliation against the pushed branches (read-only review, 2026-11-24):** `wp-b/billing-ledger` at `ae482c4` and `wp-c/fulfillment-r1` at `bd03be1`, both based on `19b68cb` and predating PR #18.

| Finding | Branch | Needed after PR #18 merges |
|---|---|---|
| Final-balance invoice uses `collection_method = 'send_invoice'` (hosted only, the pre-OI-74 R1 design); no `payment_authorizations`; no card-only filter | WP-B | OI-74 changes (04 §8, §8.1, §10; T-PAY-13, T-PAY-14, T-PAY-18 to T-PAY-26), in the same branch; no restart |
| Final balance is triggered by `release.approved` (approval), not by publication | WP-B | None: matches OI-73 |
| Order summaries are issued only by staff with `aal2` and a live session; amounts and Price IDs come from the catalog snapshot | WP-B | None: matches 03 §4 and 04 §4, §8 |
| Intake unlock reads only `deposit_verified` from `private.project_financial_status` (through `to_jsonb`, so new attributes need no WP-C migration change) | WP-C | Also require `payment_authorization_ready = true` (05 §3, T-LC-01) once WP-B adds it |
| Migration timestamps: WP-C `20261124140000`–`140200`, WP-B `20261124160000`–`160100`, both after WP-0 | Both | WP-C applies before WP-B; WP-C reads WP-B only through the interface, so the order is safe; verify on the merged tree |
| Both branches edit the same files: `OPEN-ISSUES.md`, `docs/CURRENT-STATE.md`, `supabase/seed.sql`, `supabase/tests/050_security_events.test.sql`, `supabase/tests/060_shared_contracts.test.sql`, `src/domain/contracts/{audit-actions,gates}.ts`, `tests/unit/contracts.test.ts`, `src/domain/README.md`, `src/lib/messages.ts`, `src/app/portal/page.tsx`, `src/app/staff/projects/[projectId]/page.tsx` | Both | Integration stream resolves on merge; the second branch to merge rebases on the first |

**RBAC dependency (OI-77, read-only assessment 2026-11-24):** the Sales Representative role cannot be added inside WP-B or WP-C, because it changes Phase 2 objects that both depend on. It needs one **narrowly scoped foundational PR**. Recommended as its own work package, **WP-S** (`wp-s/sales-representative`, owned by the integration stream, under the proposed AUTH-005): it changes Phase 2 objects that neither WP-B nor WP-C may touch, needs its own Tier 2 scope and stop conditions, and stays small. It includes a replacement of WP-B's `issue_order_summary` with one added condition, reviewed by WP-B, and replacements of two WP-C functions with one changed condition each, reviewed by WP-C (row "Client-role separation" below). Neither branch changes.

| Area | Finding | Change (foundation PR unless noted) |
|---|---|---|
| Role definitions | `public.staff_role` = owner, admin, fulfillment; `staff_roles` rejects `fulfillment`; staff invitations accept only owner or admin | Add `sales` in its own migration (a new enum value cannot be used in the transaction that adds it); allow it in the invitation check; Owner-only assignment as today |
| `private.is_staff()` | True for any `staff_roles` row; 21 uses in Phase 2 (policies, `can_access_project`, storage, audit visibility, the restrictive `aal2` policies), 9 in WP-B, 32 in WP-C | Redefine as Owner or Admin only. Identical behavior for existing data; every existing and WP policy stays Owner/Admin-only without editing it |
| Sessions and MFA | `session_is_active()` applies the 12-hour staff rule to any staff role; the restrictive `aal2` policies key on `is_staff()` | Sales inherits the staff session rule automatically; Sales gets no direct table access, so every Sales function checks `aal2` and the live session itself |
| Customer and project ownership | No assignment concept; staff access is global | New `project_sales_assignments` (+ history) with RLS and isolation tests; `private.is_sales()`, `private.sales_assigned(project)` |
| Onboarding | `create_invitation` requires `is_staff()` | Allow `kind = 'client'` for an assigned Sales Representative; staff invitations stay Owner-only |
| Customer creation | Table policies allow `is_staff()` inserts | New `sales_create_customer_project` function (business, project, and assignment in one transaction, audited); no new table policies |
| Order preparation | WP-B `issue_order_summary(project, package_key, …)` takes no amounts (catalog-resolved) and requires `is_staff()` | **WP-B amendment:** also allow an assigned Sales Representative (one condition), after the foundation PR |
| Commercial progress | No Sales read path | `sales_project_progress(project)` returning derived states only, read through the two gate interfaces (as Admin under OI-72) |
| App layer | `src/server/auth/context.ts` maps only owner/admin (a `sales` value would become a non-staff user and skip forced MFA); `guards.ts`, `mfa/*`, `sign-in/*` key on `staffRole` | Add the Sales role to the context, a `requireSales` guard, forced MFA, global sign-out, and a minimal sales area; `requireStaff` stays Owner/Admin |
| WP-C | Fulfillment, queue, and publication functions use `wpc_is_staff_aal2` and `requireStaff`, which exclude Sales once `is_staff()` is redefined. `wpc_is_client_member` tests `not private.is_staff()`, and `record_live_verification` accepts a requester with any staff role (verified at `bd03be1`) | **WP-C corrects both in PR #19 before merge (OI-78 amended):** client test `staff_role_of(auth.uid()) is null` plus membership; requester Owner or Admin. WP-S touches no WP-C function |
| Client-role separation | `accept_invitation` lets any verified user accept a client invitation. After `is_staff()` is narrowed, a Sales user holding a membership would pass `wpc_is_client_member`, so a representative could invite its own address to its own project and record a client approval (refinement 6). WP-B client paths already test `staff_role_of(...) is null` (`ae482c4`) and deny Sales | A Sales user can never hold a membership: `create_invitation`, `accept_invitation`, and `set_staff_role` add rejections (Owner and Admin unchanged); T-SALES-24. Direct table access: Sales has no permissive grant beyond its own profile; T-SALES-23 |
| Tests | — | T-SALES-01 to T-SALES-28 (03 §13), including the adversarial set, the OI-78 termination, invitation, and attribution regressions, and an enumerated regression proving every existing staff-only function denies Sales |

Merge-order consequence (safest): WP-S merges **after** WP-C and WP-B. Its enumerated regression (T-SALES-02, T-SALES-22) then runs against the complete R1 staff surface, neither branch has to rebase onto a changed `is_staff()`, and the WP-B function replacement lands in the same PR. Its migrations take timestamps after every merged migration.

**Approved order (OI-78, Owner, 2026-11-24):** (1) PR #18; (2) WP-C; (3) WP-B rebased on WP-C; (4) WP-S after explicit AUTH-005 activation; (5) integrated R1 end-to-end and security verification; (6) real Stripe test-mode verification after explicit AUTH-002 activation. Detail: WP-C first, with the `payment_authorization_ready` check added in its own branch before merge (it reads the attribute through `to_jsonb`, so a missing attribute fails closed and intake stays locked until WP-B lands; no extra PR); then WP-B with the OI-74 changes, rebased on WP-C; then WP-S (once AUTH-005 is granted; includes the `issue_order_summary` replacement); then the end-to-end R1 journey test, including the Sales onboarding path. This table is a review record; it does not change either branch.

Conflict hotspots: `docs/CURRENT-STATE.md` (each package edits only its own §2 row), `src/domain/contracts/*` (own section only), and `GATE_SOURCES` (WP-B sets G1, WP-C sets G6). Draft PR #6 stays outside the release path and is not merged.

## 9. Resume here (session handoff, 2026-11-24)

A new session starts by reading CLAUDE.md, this file, and AUTHORIZATIONS.md, then:

| Stream | Next step | Read first | Authorization |
|---|---|---|---|
| Integration (primary session) | Wait for the PR #18 merge. When WP-B and WP-C push, reconcile the §8 sequence against their actual branches (migration timestamps, contract-extension placement, shared-file sections) before recommending merge order; never ask either stream to restart. Then own migration ordering, shared-file conflicts, and the end-to-end R1 journey test. Do not start WP-B or WP-C in the integration session. | §8; 08 OI-71, OI-72, OI-74 | AUTH-000; AUTH-001 for cross-package tests |
| WP-B (PR #20, `wp-b/billing-ledger`) | See **WP-B directive** below | 04 (all, v0.9.1), 03 §4 (v0.5.3), 01 §7, §9.1, §9.1.1 | AUTH-001 only; AUTH-002 **not active** (mocked Stripe, synthetic signed events) |
| WP-C (PR #19, `wp-c/fulfillment-r1`) | See **WP-C directive** below | 05 (v0.4.2), 06, 03 §4, §13, 01 §7, §9.1, §9.1.1 | AUTH-001 and AUTH-004 |
| WP-S (`wp-s/sales-representative`, integration stream) | Not started. Starts only when the AUTH-005 entry criteria are met (PR #18, WP-C, and WP-B merged; AUTH-005 granted and activated; re-verification on `main`). Scope, exit criteria, and coordination: AUTHORIZATIONS AUTH-005; tests T-SALES-01 to T-SALES-28 | 03 §3, §4, §4.1, §13; 08 OI-77 | AUTH-005 (proposed) |

**WP-C directive (PR #19; issue IDs OI-79, OI-80):**
1. **Fix CI by the identified root cause, and close the inverse case.** Root cause (WP-C, confirmed by Main from `bd03be1`): `release_upload` picks the latest scan result by `scanned_at desc, id desc`; results inserted in one transaction share `now()` (transaction start time), so a random UUID decides authority and tests 64 and 69 fail intermittently. In the current state machine that ordering alone fails closed, but Main found the **inverse risk**: `record_scan_result` accepts a result only while the upload is `scanning`, so a `malicious` verdict that arrives after a clean result (a retried, concurrent, or delayed attempt) is discarded, and the file can still be released. Implement 05 §5.5 in WP-C's own unmerged migration:
   - an identity sequence on `upload_scan_results`, every insert after the upload row lock; authority by sequence, never by timestamp or UUID;
   - a scan-attempt identifier created on each entry to `scanning`; results must name the current attempt; earlier-attempt, duplicate, and replayed results are stored as non-authoritative;
   - `malicious` accepted and acted on in any non-terminal state and from any attempt, including after a clean result or after release (reject, revoke access, audit, alert the Owner); any `malicious` result for the same bytes permanently blocks release;
   - `error`, unpermitted-scanner, or invalid results return the file to quarantine; only a newer attempt's clean result counts;
   - the clean result must match the server-computed SHA-256 of the stored quarantine object; processing re-verifies that hash; the released hash is server-computed.
   Release eligibility and every existing assertion stay as strict as they are; tests 64 and 69 must pass unchanged. Add T-UP-14 to T-UP-19 (identical timestamps, concurrent submissions, unpermitted then permitted clean, clean then malicious or error, stale or replayed results, exact-bytes mismatch). Record the cause and fix in the PR. CI on the exact head is the only accepted evidence (CLAUDE.md §6).
2. After PR #18 merges, merge `main`. In `OPEN-ISSUES.md` and `docs/CURRENT-STATE.md`, take `main`'s version and re-add only WP-C's §2 row. WP-C's former OI-73 and OI-74 are now **OI-79** and **OI-80**, both decided on `main`; remove WP-C's own copies.
3. **Security corrections (OI-78 amended; within AUTH-001, own new functions only):** `private.wpc_is_client_member` uses `private.staff_role_of(auth.uid()) is null` plus an active membership, never `not private.is_staff()`; `private.record_live_verification` accepts only `staff_role_of(p_requested_by) in ('owner', 'admin')`. Add pgTAP tests that any staff-role holder is never a client member and that a non-Owner/Admin requester is rejected. No Phase 2 object changes.
4. Intake also requires `payment_authorization_ready = true` from `private.project_financial_status` (read through `to_jsonb`; a missing attribute fails closed). Update T-LC-01.
5. Approval action label **Approve Website & Authorize Final Payment** and screen text per 04 §10 and 05 §7 (v0.4.2); no amount shown until the WP-B interface provides it (OI-80 item 3). Final wording is for counsel (DEP-03).
6. **OI-79 decisions:** decimal units (item 1); 24-hour quarantine flag (2); 60-day domain-expiry warning (3); image limits 12,000 px per side and 100 MP read from the header before any full decode, with bounded memory and processing time and early rejection of malformed images, and no new dependency (4); G7 fails on any failed high or critical finding, with no exception path (5); release requires `accepted_by_staff`, no override (6); Owner **and** Admin may correct intake with a required reason, preserving the original submission and version history (7; 03 §4 row updated); scanner errors keep files quarantined with bounded retries and backoff, then the review queue (8). Tests T-LC-16, T-LC-17, T-UP-10 to T-UP-13, T-PUB-20.
7. **Browser tests:** add Playwright tests for WP-C pages in the states reachable without WP-B: intake locked for an unpaid project, the staff queue, release recording, upload type rejection, and cross-project denial for pages and asset URLs. The full journey is T-E2E-01 to T-E2E-10 (01 §9.1.1), owned by the integration stream.
8. **Dispute evidence interface (04 §15.4):** add a read-only, Owner-only SECURITY DEFINER function returning the project's preview releases and approvals with release IDs, outreach log, QA and security results, publication authorization, deployment, and live-verification records, with isolation tests; WP-B consumes it (T-ARC-10).
9. Keep migrations `20261124140000` to `140200` (WP-C's own unmerged files may be amended before merge); edit shared files only in WP-C's sections (`src/domain/contracts/*`, `GATE_SOURCES.G6`, tests 050 and 060 additive). Do not touch WP-B tables or functions.
10. Merge-ready when: CI `CI result` succeeds with the full suite on the exact head, the items above are done, and the Owner approves.

**WP-B directive (PR #20; issue IDs OI-81, OI-82, OI-83):**
1. Rebase on `main` after PR #19 merges. Take `main`'s `OPEN-ISSUES.md` and `CURRENT-STATE.md` and re-add only WP-B's §2 row. WP-B's former OI-73, OI-74, and OI-75 are now **OI-81**, **OI-82**, and **OI-83**, all decided on `main`; remove WP-B's own copies.
2. **OI-74 and OI-75:** `payment_authorizations` and its history (Owner-only read); card-only `allowed_payment_method_types` on every Checkout Session; automatic collection on the single final-balance invoice with `default_payment_method` set to the authorized card and `auto_advance` set deliberately; no automatic attempt when the authorization is not `active` (hosted page only); setup-mode recovery and revocation through the mocked gateway; never write the subscription's payment method; `payment_authorization_ready` and `payment_authorization_state` on `private.project_financial_status` with `contract_version` incremented. Tests T-PAY-13, T-PAY-14, T-PAY-18 to T-PAY-26; T-PAY-17 retired.
3. **OI-81:** `issue_order_summary` rejects (and audits) any new order summary whose total, deposit, or balance differs from the accepted order summary once the deposit is verified.
4. **OI-82 (approved architecture, 04 §15.2.1):** separate development-deposit, maintenance, and development-balance obligations; full reversals allocated deterministically; Owner-recorded allocation for partial refunds (recorded before issuance, referenced from the refund; the mechanism stays mocked until DEP-06 verifies it); everything else to the unresolved reversal holding account with an Owner reconciliation item; unresolved reversals fail G2 (initial charge) or G4 (final balance); cumulative reversal limit per obligation; each Stripe refund, dispute, and balance transaction counted once; dispute opened, won (reinstatement), and lost as new entries; Owner reconciliation with fresh reauthentication, a reason, immutable audit, and append-only entries that balance exactly; OI-37 holds unchanged. No deposit-first, maintenance-first, or proportional code path. Tests T-PAY-27 to T-PAY-36. Synthetic events only; no live refund, Stripe API request, or Tier 3 action.
5. **OI-83:** Admin reads agreed order-summary pricing (total, deposit, balance); paid amounts, invoices, ledger, refunds, and disputes stay Owner-only.
6. Keep the final-balance trigger on `release.approved` (OI-73). Do not add any Sales condition (WP-S owns that). Client-only checks keep `staff_role_of(...) is null`.
7. **Browser tests:** agreement acceptance and initial Checkout start with the mocked gateway and a synthetic signed webhook (redirect alone leaves intake locked), the client billing page, and the staff billing section including Admin's derived view.
8. **Billing jobs (04 §13):** one service-role, idempotent, single-flight, audited entry point per job (daily reconciliation, maintenance-recovery evaluation, webhook backfill), tested by direct invocation (T-ARC-09). The hosted scheduler binding is WP-D's (DEP-17), not WP-B's.
9. **Dispute evidence (04 §15.4):** `dispute_evidence_package` includes WP-C's evidence interface in full and drops its placeholder note (T-ARC-10).
10. Merge-ready when: CI `CI result` succeeds with the full suite on the exact rebased head, the items above are done, and the Owner approves. Stripe remains mocked; AUTH-002 stays inactive.

**Shared-file reconciliation plan (confirmed):**

| File | Rule |
|---|---|
| `docs/CURRENT-STATE.md`, `OPEN-ISSUES.md`, `docs/08-*.md` | `main` (from PR #18) is authoritative. Each package re-adds only its own §2 row and implementation evidence; it allocates no ID and records no decision |
| `src/domain/contracts/*`, `tests/unit/contracts.test.ts` | Additive, own section only. WP-C sets `GATE_SOURCES.G6`, WP-B sets `GATE_SOURCES.G1`; the second to merge rebases on the first and keeps both |
| `supabase/tests/050_security_events.test.sql`, `060_shared_contracts.test.sql` | Additive assertions only; plan counts reconciled on rebase. WP-B's change of the financial-status expectation and WP-C's change of the fulfillment-status expectation are both kept |
| `supabase/seed.sql` | Additive synthetic rows only; no shared IDs reused |
| `src/lib/messages.ts`, `src/domain/README.md`, `src/app/portal/page.tsx`, `src/app/staff/projects/[projectId]/page.tsx` | Both changes kept; the second branch resolves by union and its CI must pass on the combined result |

**Migration order (confirmed):** `20261123060000` (Phase 2) → `20261124120000` (WP-0) → `20261124140000`, `140100`, `140200` (WP-C) → `20261124160000`, `160100` (WP-B, plus any new WP-B migrations timestamped after `160100`) → WP-S migrations (timestamped after every merged migration). WP-C reads WP-B only through `private.project_financial_status`, so this order is safe; it is re-verified from scratch (T-MIG-01) on each merged tree. Merged migrations are never edited (T-MIG-02).

**Production-readiness carry-forward (must not drop out):** (1) billing job scheduling and daily reconciliation: WP-B job entry points (T-ARC-09) → WP-D hosted scheduler (DEP-17) → staging evidence of scheduled runs and alerts before the R1 release candidate → production evidence before launch; (2) WP-C approval and publication records in dispute evidence: WP-C interface → WP-B package (T-ARC-10) → verified in the integrated R1 suite. Both are listed in 04 §13 and §15.4 as R1 release requirements.

**Updated integration sequence:** PR #18 → PR #19 (WP-C, directive done, CI green) → PR #20 (WP-B, rebased, directive done, CI green) → WP-S (after AUTH-005 grant and entry criteria) → integrated R1 browser and security verification (T-E2E-01 to T-E2E-10, T-SALES) → Stripe test-mode verification (after AUTH-002 activation).

Standing constraints for every stream: no live Stripe and no Stripe request without an active AUTH-002; no production or hosted environment; no change to existing Phase 2 security objects; never merge without Owner approval; never edit a merged migration; OI-73 (option A): never add a publication precondition to collection; publication requires verified payment (G4). OI-75 (option A): final-balance recovery and revocation never write the maintenance subscription's payment method.

