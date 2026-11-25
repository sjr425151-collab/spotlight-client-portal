# Current State

| Field | Value |
|---|---|
| Version | 1.25.0 |
| Status | **Canonical status record** (OI-67). Every pull request that changes status updates this file in the same pull request. |
| Last updated | 2026-11-25, by the WP-D18 PR (AUTH-007 and Amendments 1 to 3; §17), synchronized with `main` at `30414c7` (after the WP-H merge) |

This file replaces the status tables that were previously repeated in CLAUDE.md §1, README, 01 §8, 08 §4, OPEN-ISSUES headers, and 04 §6. Those places now link here. **What is authorized** is in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). **What was decided** is in [08](08-DECISIONS-AND-CHANGELOG.md). Detailed dependency records are in [OPEN-ISSUES.md](../OPEN-ISSUES.md).

Evidence labels: **Verified** (checked from repository or provider evidence, with the source named) · **Owner-reported** (stated by the Owner, not independently checked).

## 1. Authorization summary

| Item | State |
|---|---|
| Architecture | Approved |
| Specifications | All approved, with scope limits in §3 |
| Active authorizations | AUTH-000 (Tier 0, standing); **AUTH-001** (Tier 1: WP-A, WP-0, WP-B and WP-C on local and CI); **AUTH-004** (scoped Tier 2: WP-C storage policies, local and CI); **AUTH-006** (WP-H), **AUTH-007** (WP-D18), **AUTH-008** (WP-I, I-1 only), active 2026-11-25. **AUTH-005** (WP-S) **expired 2026-11-25** on the WP-S merge |
| Granted, not yet active | **AUTH-002** (Stripe sandbox; scope amended 2026-11-24 to include setup-mode recovery sessions), **AUTH-003** (hosted non-production). Activation conditions are in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). |
| Production launch | **Not authorized.** No real client payment may be accepted until production launch authorization (Tier 3) is granted. |
| Deployments | None. Nothing is deployed. |

## 2. Releases and work packages (OI-67, OI-68)

**Readiness levels (kept distinct):** *implemented* = merged with its package suites passing (Phase 2, WP-0, WP-C, WP-B, WP-S); *integrated R1 verification* = the cross-package browser and security suite T-E2E-01 to T-E2E-10 and the R1 release-candidate blockers (§7), **not yet done**; *production readiness* = legal, provider, hosted-environment, and Tier 3 launch steps, **not authorized**.

| Item | Scope | State |
|---|---|---|
| Phase 1, Foundation and CI | Tooling, CI, design tokens | **Done** (PR #2) |
| Phase 2, Auth, security, tenancy | Invitation-only OTP, MFA, RLS, audit, nonce CSP, private storage policies | **Done, local only** (PR #4) |
| WP-A | Governance and specification correction | **Done** (PR #14, merge commit `d6d795a`) |
| WP-0 | Shared contracts: domain-event and outbox tables, state-domain types, audit action names, gate-function interfaces | **Done** (PR #15, merge commit `60954d4`; post-merge CI run #39 on `main` concluded `success`, 2026-11-24). OI-71 and OI-72 decided. Integration closed by the integration closure PR. |
| WP-B | Agreements, payments, webhooks, ledger, reconciliation (R1 scope), including OI-74, OI-75, OI-81, OI-82, OI-83, and B1 | **Done** (PR #20, merge commit `8ac8143`; post-merge CI run #66 `success`). **N1 is a mandatory blocker for R1 release-candidate acceptance** (04 §15.2.1 rule 9; §7). Implementation record in §10. |
| WP-C | Intake, uploads, approvals, publication authorization, admin queue (R1 scope) | **Done** (PR #19, merge commit `bcddb1f`; post-merge CI run #63 `success`). Review findings H1, M1, M2 closed. |
| WP-S | Sales Representative authorization infrastructure (03 §4.1; OI-77, OI-78, OI-84, OI-85) | **Done** (PR #23, merge commit `d75bd94`; post-merge CI run #78 (id 45535755135) 7/7 `success` with the full suite). OI-85 closed; T-SALES-01 to T-SALES-36 satisfied; WP-B independent technical review record [PR comment 7151195165](https://github.com/sjr425151-collab/spotlight-client-portal/pull/23#issuecomment-7151195165) (not a GitHub APPROVED review). AUTH-005 expired on the merge. Records in §11. **DEP-18 (content and version sealing), OI-86, OI-87, OI-88, and OI-90 remain R1 release-candidate items.** |
| WP-D | Hosted non-production infrastructure, then production readiness | Not started. Needs AUTH-003 active. Production steps are Tier 3. Hosted environments receive reviewed migrations only: no seed, no database reset; WP-D verifies and documents this before hosted-environment acceptance (A3). |
| WP-E | Legal, tax, and commercial approvals | Owner. Not started (DEP-03, DEP-04, DEP-05). |
| **R1** release candidate | Complete controlled transaction (01 §9.1) | Not started |
| **R2** release candidate | Fulfillment automation (01 §9.2) | Not started |

Former phases 3–5 map onto these work packages (01 §7). Phase numbers are no longer used for authorization.

## 3. Specifications

| Spec | Version | State |
|---|---|---|
| 01 Project overview | 0.4.2 | Approved (v0.4.1: OI-74, OI-77; v0.4.2: §9.1.1 integrated R1 browser acceptance, Owner direction) |
| 02 Architecture and environments | 0.4.0 | Approved |
| 03 Security, auth, tenancy | 0.5.12 (OI-77, OI-78, OI-79, OI-83 to OI-85, OI-89; WP-S merged) | Approved (03A is supporting evidence) |
| 04 Agreement and billing | 0.9.8 (OI-74, OI-81, OI-82, OI-84; F3–F6; B1; N1; DEP-18 sealing) | Approved for implementation and test mode. **Not approved for production:** legal review (DEP-03) and provider verification (DEP-06) remain conditions. |
| 05 Lifecycle and uploads | 0.4.5 (OI-74, OI-79; §5.5 rules 1–9) | Approved |
| 06 Publishing and post-launch | 0.5.2 (OI-79 item 5; G7 clarification; B1 note) | Approved |
| 07 Notifications, privacy, design | 0.4.0 | Approved. Retention periods remain provisional (DEP-05). |
| 08 Decisions and changelog | 0.25.0 | Approved. The provenance caveat in 08 §1 still applies to transcribed decisions. |
| AUTHORIZATIONS, CURRENT-STATE | 1.11.0 (AUTH-002 and AUTH-003 inactive; AUTH-005 expired 2026-11-25), 1.15.0 | Approved |
| OWNER-RUNBOOKS | 0.2.0 (§7 direct role and membership writes, OI-90) | **[PROPOSED]** Owner review, including §7 |
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
| DEP-16 | Switch required status checks to `CI result` | **Complete.** Owner-evidenced (ruleset screenshots, 2026-11-24): see §5. |
| DEP-17 | Hosted scheduler: WP-B billing jobs, WP-C scan retries and revoked-object deletion retries | Not started. WP-D under AUTH-003 (staging), Tier 3 (production). Required before the R1 release candidate. |
| DEP-18 | Standard package scope definitions for Sales-issued order summaries (OI-84(b)) | Not started. **Owner-confirmed, mandatory before R1 release-candidate acceptance (A5).** Owner supplies the content; no authoritative definition exists today; counsel review covers it (DEP-03, A4). |

## 5. Verified facts

| Fact | Evidence |
|---|---|
| `main` is protected by ruleset `protect-main`: enforcement **Active**; target `main`; pull request required; **required status checks enabled** with "require branches to be up to date"; force pushes and branch creation blocked; repository-admin bypass for pull requests only (agents never use it, CLAUDE.md §7). Required checks (GitHub Actions): `Lint, types, format, unit tests`, `Dependency audit`, `Secret scan (gitleaks, full history)`, `CI result`. Lighthouse and the database, integration, and e2e suite are enforced through `CI result`, which fails closed on any required suite (OI-70) | **Owner-evidenced** (ruleset screenshots, 2026-11-24); a ruleset JSON export would be stronger evidence |
| `main` at `d75bd94` (PR #23 merge, WP-S; parents `005cc36`, `6843bd2`; tree identical to the authorized head; three WP-S migrations added, no earlier migration changed). Post-merge CI run #78 (id 45535755135): all 7 jobs `success`, with the full suite executed (T-MIG-02, T-MIG-01, pgTAP, integration, builds, bundle check, e2e, Lighthouse). Earlier: `005cc36` (PR #22, run #72), `0b289f3` (PR #21, run #70) | **Verified** (GitHub API, git, CI) |
| `main` at `0b289f3` (PR #21 merge, documentation only; parents `8ac8143`, `7ba7cb3`; tree identical to the reviewed head). Post-merge CI run #70 (id 45511277460): all 7 jobs `success`, including the full suite. Previously `main` at `8ac8143` (PR #20 merge; parents `bcddb1f`, `aa7a20a`; tree identical to the reviewed head). Post-merge CI run #66 (id 45506039608): all 7 jobs `success`, including migrations applied from scratch (T-MIG-01), pgTAP, integration, and e2e. Earlier: `bcddb1f` (PR #19) run #63 `success`; `77a887b` (PR #18) run #59 `success` | **Verified** via the GitHub API, 2026-11-24 |
| `main` at `19b68cb` (PR #17 merge; parents `3f3b59d`, `33c082b`; tree identical to the reviewed head). Post-merge CI run #43 (id 45322697836): all 7 jobs `success`, including `CI result` | **Verified** via the GitHub API, 2026-11-24 |
| The `spotlight-client-portal-dev` environment: Limited network; allowlist `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; no network secrets; no environment variables | **Verified** via the environment API, 2026-11-24 |
| The Stripe sandbox catalog exists as specified | **Verified** by run `dep01-20261123T220040Z-290aebd0` (04 §6.5) |
| The restricted Stripe keys used for DEP-01 are revoked; no restricted keys remain in live mode; `chris-pribyl` and `spotlight-client-portal-dev` hold no network secrets or environment variables; `api.stripe.com` is not on the `spotlight-client-portal-dev` allowlist | **Owner-reported**, 2026-11-24 |
| The `spotlight-client-portal-dev` allowlist is `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; network access is Limited | **Owner-reported**, 2026-11-24 |
| CI post-merge run #35 on `e7c8d47` concluded `success` | **Verified** via the GitHub API |

## 6. Pending Owner actions

1. (Done 2026-11-25) WP-S merged (PR #23); WPS-P1 to WPS-P7 decided as OI-85 to OI-89.
2. (Active 2026-11-25) AUTH-006, AUTH-007, AUTH-008 (I-1 only), baseline `58d0e98`. Later: the separate I-2 grant.
2a. Supply the standard scope for each package (DEP-18) and include it in counsel review (DEP-03).
3. Review OWNER-RUNBOOKS (proposed), **including §7** (direct role and membership writes, OI-90; required before R1 release-candidate acceptance).
4. Engage counsel and a tax advisor (DEP-03, DEP-04, DEP-05). DEP-03 includes the OI-74 items, the OI-82 refund and allocation terms, revocation effects, and the interim payment wording (F10), and the contractual package-scope language (A4).
5. When ready: meet the AUTH-002 activation conditions for the Stripe test-mode criteria (04 §8.2: F7, F8, N1 linking; DEP-15).
6. When ready for WP-D: create the accounts in AUTH-003 (DEP-14, DEP-17).
7. Select the malware scanning vendor (DEP-07) and the monitoring vendor (DEP-12).

## 7. Known follow-ups

| Item | When |
|---|---|
| `supabase/.temp` files tracked although ignored | **Done in WP-0.** `postgres-version` stays tracked on purpose (it pins the database image CI tests against, 17.4.1.054) with an explicit `.gitignore` exception; `cli-latest`, an empty update-check cache, is untracked. |
| DEP-07 and DEP-12 verified vendor shortlist | WP-A follow-up |
| PR #6 (AI operations proposal): header corrected to the current next unused ID; remains a draft outside the release path (OI-67) | Done in PR #6 |
| Time tracking: each implementation PR description records AI session hours, Owner review hours, and admin hours (OI-67) | From WP-0 onward |
| **R1 release-candidate blockers (mandatory before R1 acceptance)** | **N1** (04 §15.2.1 rule 9): (a) safe project attribution of deferred refund and dispute events (WP-B follow-up); (b) Owner runs reconciliation before publication (OWNER-RUNBOOKS §5) until DEP-17; (c) the multi-payment linking criterion passes in test mode (AUTH-002). Also: F7 and F8 test-mode criteria (04 §8.2, DEP-06, DEP-15); the integrated R1 browser suite T-E2E-01 to T-E2E-10 (integration stream); DEP-07, DEP-12, DEP-17; DEP-18 package scope content (OI-84(b); append-only versions); **OI-86** (lock-order deadlock; WP-B, separate authorization); **OI-87** (change reason staff-only; WP-B, separate authorization); OI-88 user-experience reassessment; **OI-90** operator runbook (OWNER-RUNBOOKS §7); DEP-18 version sealing before non-fixture content; **OI-91** (outbound/revocation deadlock; separate authorization); **OI-95** (Sales empty-list accessibility; separate correction); OI-93 conflict-representation mechanism (if R1 needs conflicts cleared); DEP-03 wording, never presented as legally approved until approved (F10) |
| **F2** (integration stream; **open**; WP-I I-1 implementation, §14) | Cause reproduced: after `supabase db reset`, PostgREST answers `503 PGRST001` while it reconnects from dead pooled connections to the restarted database (11 of 12 consecutive cold-reset runs failed before the readiness gate). Done in I-1 and Amendment 1: real WP-B records replace the global `private.project_financial_status` fixture; WP-C RPC helpers report the PostgREST `error`; a deadline-bounded PostgREST readiness gate per integration file (WPI-P1 accepted); a deterministic, deadline-bounded schema-cache sync after the trigger toggles, including the W-1 database bounds. Stays open until Main's independent verification |
| Optional (nonblocking) | L1: atomic write of the OTP spacing file; L2: rate-limit refused upload requests |
| Low notes (accepted) | N2–N4 (OWNER-RUNBOOKS §6) |
| Code comments describing OI-71 as open | **Done** (corrected in PRs #19 and #20) |

## 8. Parallel execution: WP-B and WP-C (approved 2026-11-24)

**Complete:** WP-C merged at `bcddb1f` (PR #19) and WP-B at `8ac8143` (PR #20). The table and plans below are kept as the record.

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
| Integration (primary session) | F2 (§7); then the integrated R1 browser and security suite T-E2E-01 to T-E2E-10, including the Sales-assisted onboarding journey; track the R1 release-candidate blockers (§7) | §7, §9; 01 §9.1, §9.1.1 | AUTH-000; AUTH-001 for cross-package tests (confirm scope with the Owner) |
| WP-S | **Done** (PR #23, `d75bd94`) | §11 | AUTH-005 expired |
| WP-B follow-up (financial hardening) | OI-86 (lock order), OI-87 (change reason staff-only), N1(a) (safe attribution), each before the R1 release candidate | 04 §15.2.1 rules 8–9; 08 OI-86, OI-87 | Owner authorization required (OI-86, OI-87: separate WP-B authorization) |

**AUTH-005 activation record (2026-11-25):** Owner grant 2026-11-25 (conditional, with the environment-isolation amendment). Conditions: (a) PR #22 merged at `005cc36130e582b098bcbcbc3c9d85dd87bb91e9` (parents `0b289f3`, `eb34fe2`; tree identical to the reviewed head; no migration changed), post-merge CI run #72 (id 45514706755) `success` with the full suite including T-MIG-01 and T-MIG-02; (b) read-only revalidation on `005cc36`: no migration or source change since `8ac8143`; Phase 2 objects (1) to (7) as recorded (`staff_role` = owner, admin, fulfillment; `invitations_kind_shape`; `is_staff()` = any staff role; `create_invitation` staff path Owner with fresh MFA and the per-user rate limit; `revoke_invitation`, `accept_invitation`, `set_staff_role` present); app files present; `issue_order_summary` guard and lock order as recorded; `begin_initial_checkout` client-only; order-summary snapshot guard covers scope and notes; both WP-C corrections present; no name collision; 46 `is_staff()` and 20 `wpc_is_staff_aal2()` call sites; environment classification (`private.environment_settings`) writable only by the migration owner, so the allowlist amendment is enforceable without changes; (c) inventory accurate; (d) this record committed on `wp-s/sales-representative` before implementation; (e) no unresolved conflict. **AUTH-005 is active.** Reviews: WP-B independently approves the `issue_order_summary` replacement; Main reviews architecture, security, and integration; WP-S never merges its own PR; the Owner alone merges.

**WP-S directive (definitive; against `main` at `005cc36`; AUTH-005 active):**
1. **Entry (done 2026-11-25, activation record above).** Record the AUTH-005 grant and activation here; re-verify read-only on the current `main` that `private.issue_order_summary`, `private.wpc_is_client_member`, `private.record_live_verification`, and the enumerated Phase 2 objects match AUTH-005; branch `wp-s/sales-representative` from that commit. Any difference is a stop condition.
2. **Migration A (own file):** `alter type public.staff_role add value 'sales'` (a new enum value cannot be used in the transaction that adds it).
3. **Migration B (Phase 2 objects, exactly as AUTH-005 lists):**
   - `invitations_kind_shape` allows `intended_role = 'sales'`;
   - `private.is_staff()` becomes Owner or Admin only (identical for existing data; 46 call sites and 20 `wpc_is_staff_aal2` call sites keep their meaning);
   - `create_invitation` and `revoke_invitation` allow `kind = 'client'` for a Sales Representative with an active assignment to that project, never to the address of a user with an active staff role; staff invitations stay Owner-only with fresh MFA;
   - `accept_invitation` rejects a client invitation for an active Sales user and a Sales staff invitation for a user with an active membership; `set_staff_role` rejects `sales` for a user with an active membership.
4. **New objects:** `public.project_sales_assignments` and its append-only history (Owner and Admin read all; a Sales Representative reads only its own active rows; no direct write by any API role; added to the isolation and restrictive-policy loops); `private.is_sales()`, `private.sales_assigned(uuid)` (active assignment, `aal2`, live session, read live at every call); SECURITY DEFINER functions with `search_path = ''` and public wrappers: `sales_create_customer_project` (business, project, and self-assignment in one transaction), `assign_sales_representative` and `end_sales_assignment` (Owner or Admin, `aal2`, live session, audited), `sales_list_customers` (active assignments only), `sales_project_progress` (derived states through the two gate interfaces plus agreed order-summary pricing, OI-83, plus the assigned project's pending client invitations with minimum fields, OI-84(e); never paid amounts, invoices, ledger entries, refunds, disputes, tokens, or token hashes); **package scope definition (OI-84(b)):** `private.billing_package_scope` and `private.current_package_scope(text)` (no API grant; rows from reviewed migrations only; production content DEP-18; test-only seed labeled "TEST FIXTURE — NOT A DELIVERABLE", approved; fixture isolation: explicit `is_test_fixture` flag, flag and label consistent in both directions, fixture rows accepted and resolved only where `private.app_environment()` is `development` or `test` (affirmative allowlist; rejected in production, staging, preview, unknown, or missing classifications, and re-checked at every resolution), synthetic rows only in `supabase/seed.sql`, none in any migration; A2 as amended 2026-11-25).
5. **Rate limits:** `sales_create_customer_project` and every Sales invitation operation (create, resend, revoke) call `private.consume_rate_limit` with a per-user bucket; exceeding a limit returns the standard failure and is audited.
6. **WP-B integration:** a new WP-S migration replaces `private.issue_order_summary` with one added caller, `private.sales_assigned(p_project_id)`. For a Sales caller only (OI-84(b), (c)): supplied scope items or project notes are rejected and audited; scope is copied from `private.current_package_scope`, and its version is recorded in the audit metadata; a missing definition fails closed; after the existing row locks, any agreement acceptance or verified deposit on the project rejects the call. The signature, the Owner and Admin path, catalog-only pricing, the OI-81 price lock, and WP-B tables are unchanged; WP-B independently reviews. No WP-C function changes.
7. **OI-78 and OI-84(f) policies:** pending client invitations and issued order summaries stay valid after an assignment ends (Owner and Admin keep visibility, resend, revoke, replace); the former representative loses all project, order, and invitation access at the next authorization check, including existing sessions; ended assignments are hidden from the representative; history and `issued_by` attribution are preserved. Commission processing stays out of scope.
7a. **Resend (OI-84(d)):** for every role, resend is `revoke_invitation` followed by `create_invitation` (revoke first, because one pending invitation per address is allowed), composed in `src/server/services/invitations.ts`; the old link and token stop working; the new invitation has a new token and expiry; both steps are audited and rate-limited; no new database object. Owner and Admin get the action in `/staff`, Sales in `/sales`.
8. **App:** the auth context recognizes `sales` as its own role; a `requireSales` guard (`aal2`, live session, forced MFA enrollment, global sign-out); `requireStaff` stays Owner and Admin; **`requireClient` corrected** (no staff role of any kind plus an active membership; 03 §4.1); a minimal `/sales` area (customers, create customer, project and order summary, invite client, progress); the Owner's staff-role selector offers `sales`.
9. **Audit (contracts, WP-S section, spec-cited):** `sales.customer_created`, `sales_assignment.created`, `sales_assignment.ended`, `sales_assignment.reassigned`, `sales.rate_limited`, `sales.order_summary_rejected` (reason kind only: scope input, notes input, after acceptance, missing scope definition; OI-84); invitation and order-summary events keep their existing names with the actor's role.
10. **Tests:** T-SALES-01 to T-SALES-36 (03 §13, including OI-84: T-SALES-31 to T-SALES-35, the T-SALES-31 no-retroactive-change assertion, and fixture isolation with the environment allowlist T-SALES-36), including the adversarial set, the enumerated regression over every staff-only check, T-SALES-24 for `requireClient`, rate limiting (T-SALES-29), and pricing visibility (T-SALES-30); the full Phase 2, WP-0, WP-B, and WP-C suites pass unchanged. Browser tests for the `/sales` area with database and audit assertions (create, invite, unassigned denial, MFA enforcement, revoked assignment).
11. **Shared files:** additive, WP-S sections only (`src/domain/contracts/*`, pgTAP 050 reviewed-RPC list, `seed.sql`, `src/lib/messages.ts`); merged migrations are never edited.
12. **Migration order:** after `20261124160100`; migration A before migration B.
13. **Exit:** AUTH-005 exit criteria (CI `CI result` on the exact head with the full suite; only listed objects changed; WP-B review of the `issue_order_summary` replacement; documentation and effort recorded; Owner merge).

**Migration order (merged):** `20261123060000` (Phase 2) → `20261124120000` (WP-0) → `20261124140000`, `140100`, `140200` (WP-C) → `20261124160000`, `160100` (WP-B) → WP-S. Re-verified from scratch on each merged tree (T-MIG-01); merged migrations are never edited (T-MIG-02).

Standing constraints for every stream: no live Stripe and no Stripe request without an active AUTH-002; no production or hosted environment; no change to existing Phase 2 security objects outside an active grant; never merge without Owner approval; never edit a merged migration; OI-73 and OI-76: payment before publication; OI-75: final-balance recovery and revocation never write the maintenance subscription's payment method.

## 10. WP-B implementation record (PR #20)

Local evidence for the §9 WP-B directive, on branch `wp-b/billing-ledger` rebased on `main` at `bcddb1f`. **Verified** by the commands named, on a freshly reset local stack (`supabase db reset`, all migrations and the synthetic seed). Remote CI for the exact head is recorded in the PR.

| Directive item | Implementation | Tests |
|---|---|---|
| 1. Rebase | On `bcddb1f`; `OPEN-ISSUES.md` and this file taken from `main`; WP-B's own OI-73 to OI-75 copies removed (now OI-81 to OI-83) | Migration check against `origin/main` passes |
| 2. OI-74, OI-75 | `payment_authorizations` and insert-only history (Owner-only read); card-only `allowed_payment_method_types` on every Checkout Session; automatic collection on the single final-balance invoice with `default_payment_method` and `auto_advance` set deliberately; hosted page only when the authorization is not `active`; setup-mode recovery and signer revocation through the mocked gateway; the subscription's payment method is never written; `payment_authorization_ready` and `payment_authorization_state` on `private.project_financial_status`, `contract_version` 3 | T-PAY-13, T-PAY-14, T-PAY-18 to T-PAY-26 (pgTAP 120, 130; unit; integration; e2e for T-PAY-18). T-PAY-17 retired |
| 3. OI-81 | `issue_order_summary` rejects (`price_change_after_deposit`) and audits (`order_summary.price_change_rejected`) a changed total, deposit or balance once the deposit is verified | pgTAP 120 |
| 4. OI-82 | Development-deposit, maintenance and development-balance obligations; deterministic full-reversal allocation; Owner-recorded refund decision lines; unresolved reversal holding account with an Owner item, failing G2 or G4; cumulative limit per obligation; each Stripe object counted once; dispute opened, won and lost as new entries; Owner reconciliation with fresh MFA, reason, audit, exactly balancing entries; no deposit-first, maintenance-first or proportional path | T-PAY-27 to T-PAY-36 (pgTAP 110, 140; static) |
| 5. OI-83 | Admin reads the agreed total, deposit and balance; paid amounts, invoices, ledger, refunds and disputes stay Owner-only | pgTAP 110; e2e |
| 6. OI-73 | Final balance triggered on `release.approved` only; no Sales condition; client-only checks use `staff_role_of(...) is null` | pgTAP 120 (consumer), 130 (client-only paths) |
| 7. Browser tests | Admin issues the summary (derived view only); client accepts the labeled fixture; Checkout start with the mocked gateway (Stripe page intercepted); a redirect alone leaves the deposit pending and intake locked; a synthetic signed webhook verifies it; client billing page and staff section | `tests/e2e/wpb.spec.ts` (5 tests; the deposit test is labeled T-PAY-03, T-PAY-05, T-PAY-18, corrected from T-PAY-13 in review item L3) |
| 8. Billing jobs | `public.run_billing_job(job)`: `maintenance_recovery`, `webhook_backfill`, `release_approvals`, `service_terminations`, `outbound_requests`; `begin_billing_job`/`finish_billing_job` for the card lookup; `start_reconciliation_run` keyed per local day. Service-role only, idempotent, single-flight, audited. Scheduler binding is WP-D's (DEP-17) | T-ARC-09 (pgTAP 150; integration) |
| 9. Dispute evidence | `dispute_evidence_package` includes `private.wpc_dispute_evidence` in full; the placeholder note is removed | T-ARC-10 (pgTAP 150) |

| Suite | Result |
|---|---|
| pgTAP (`supabase test db`) | 23 files, **1107** assertions, all pass. WP-B: 100 (41), 110 (141), 120 (96), 130 (79), 140 (40), 150 (18). Phase 2, WP-0 and WP-C files unchanged except the additive 050/060 rows |
| Unit (`pnpm test`) | 15 files, **268** tests, all pass |
| Integration (`pnpm test:integration`) | 5 files, **59** tests, all pass (WP-B 15). One earlier run right after a reset had 4 WP-C delivery failures (`request_upload` returned no data); not reproduced in three later runs, including the exact CI sequence |
| E2E (`pnpm test:e2e`, `APP_ENV=test`) | **44** tests, all pass (WP-B 5) |
| Lint, typecheck, format, builds, bundle scan, audit, gitleaks, migration immutability | Pass |

### 10.1 B1 correction: financial integrity fails closed (Main's review of `0329271`)

`private.project_financial_status` now fails the payment gate of the charge concerned while any financial-integrity anomaly is unresolved: **G2** for the initial charge, **G4** for the final-balance charge, **both** when the charge cannot be told; a maintenance renewal charge blocks neither (its recovery is the maintenance hold). Contract version stays **3** (no attribute changed); `evidence.blocking_anomalies` names the blocking kinds per gate, with no amounts or identifiers (OI-72).

| Anomaly | Gate | Resolved only by (existing, Owner-only, fresh MFA, audited) |
|---|---|---|
| Quarantined event, attributed through its charge (payment links, invoice, Checkout record) | G2 / G4 / both | `resolve_quarantined_event` |
| Open reconciliation item: totals (both), deposit snapshot (G2), balance snapshot (G4), unmatched refund or dispute (by its charge), charged after halt (G4) | as listed | `resolve_reconciliation_mismatch` |
| Ambiguous outbound request (Checkout: G2; final balance, its stop, recovery: G4; Customer: both) | as listed | `reconcile_outbound_request` |
| Failed `final_balance_invoice_disable_auto` (not `already_paid`) | G4 | `reconcile_outbound_request` (extended to this one failed purpose) |
| `charged_after_halt` without a resolved review item | G4 | `resolve_reconciliation_mismatch` (an item is created when it happens) |
| A refund or dispute Stripe reports in effect (latest observation) that the ledger never posted | its charge | Not resolvable by review: only a posted reversal or Stripe's later evidence (refund failed or canceled, dispute won) ends it |

- **Resolution is a review record only.** It posts nothing, reprocesses nothing, adds no override or hold type, is recorded once (a new guard makes reconciliation resolutions immutable, like quarantine resolutions), and returns and audits a fresh evaluation of G2 and G4 from all the evidence. So resolving one anomaly never clears another, a confirmed reversal keeps its gate blocked, and valid evidence lets the gate pass again.
- **Malformed refund and dispute amounts** are quarantined against their charge (`private.try_cents`) instead of failing processing without attribution.
- **Daily reconciliation** receives Stripe's refund and dispute objects for each Customer; any object WP-B never recorded is attributed through its charge (payment intent, charge or invoice link; unknown means both gates) and becomes a blocking item, once per object state.
- Evidence (local, freshly reset stack, CI order): pgTAP **1166** assertions in 24 files (new `160_wpb_financial_integrity` 53; 110 and 120 gained the B1 steps), unit **268**, integration **62** (WP-B 18), e2e **44**. Every scenario uses the real event, outbound, reconciliation and resolution paths, and WP-C's `private.evaluate_publication_gates` returns `eligible = false` with `deposit_not_verified` or `balance_not_verified` while an anomaly blocks.

**Interim decisions for Owner review** (shipped fail-closed; labeled **[PROPOSED]** or **[VERIFY-PROVIDER]**; no spec text changed):
- **[PROPOSED]** Client revocation needs fresh reauthentication: a sign-in code verified within five minutes (JWT `amr`); clients have no TOTP (03 §7).
- **[PROPOSED]** Only the acceptance signer may revoke in the portal; the Owner records revocations received elsewhere (fresh MFA, reason) and reviews every revocation.
- **[PROPOSED]** After a revocation, setup-mode recovery re-establishes an authorization only with an acceptance newer than the revocation.
- **[PROPOSED]** `payment_recovery_required` also covers a verified deposit without a ready authorization.
- **[VERIFY-PROVIDER]** An automatic attempt racing a revocation or detachment is stopped by setting `auto_advance: false` on the created invoice; a charge that still occurs is flagged for Owner review (`charged_after_halt`).
- **[VERIFY-PROVIDER]** Which Stripe fields report the saved card for subscription-mode Checkout and setup-mode SetupIntents, and whether the card is attached to the Customer.
- The OI-82 holding path cannot be reached on the final-balance charge (one obligation, rule a); its G4 wiring is proven with a fixture in pgTAP 140.

**Remaining dependencies:** DEP-06 (Stripe items) and DEP-15 (T-PAY-16) under AUTH-002; DEP-17 scheduler binding (WP-D); DEP-03 final UI and legal wording; integrated R1 journey T-E2E-01 to T-E2E-10 (integration stream).

### 10.2 WP-H implementation record (AUTH-006, Amendments 1 and 2)

**Authorization:** AUTH-006, active since 2026-11-25 (merge `58d0e98`, CI run 45543204966). Amendment 1 is active (merge `7469b2d`, CI run 45558153619). Amendment 2 is active (merge `f37cf7e`, CI run 45583992649, 7/7 with the full suite, verified before implementation). Branch `wp-h/financial-hardening` from `58d0e98`. **Synchronized** after WP-I-1 merged (PR #28 at `b027e41`, post-merge CI run 45675171938, 7/7 with the full suite).

- **Method:** `main` at `b027e41` was merged into the branch. There was no rebase and no force-push, so every reviewed commit is preserved. The merge was conflict-free.
- **Equivalence:** the implementation diff against `main` is patch-identical (`git patch-id --stable`) to the reviewed `58d0e98..aec8ff3` diff, file by file. That includes `tests/integration/wps-sales.test.ts`, which PR #28 also changes; T-SALES-32 keeps its 12 iterations and its `aborted:`-free assertions.
- **Readiness gate:** PR #28's gate runs through `tests/support/local-supabase.ts` in every file that uses PostgREST. `wph-hardening.test.ts` uses direct database connections only.
- **Second synchronization:** `main` at `e3a7508` (PR #37, OI-95; post-merge CI run 45682383873, 7/7) was merged in, again conflict-free, with no rebase and no force-push. PR #37 changes `src/app/sales/page.tsx`, `tests/e2e/wps.spec.ts` and this file's §16, which is kept intact. None is a WP-H file, and all 17 WP-H files remain patch-identical to the reviewed diff.
- **This file:** the header version is allocated from the baseline (v1.23.0 to v1.24.0; PR #37 did not change it).
- **Merge order is unchanged** (WP-I-1, WP-H, WP-D18). AUTHORIZATIONS AUTH-006 "Merge" applies: full CI on the synchronized head, and a new record from every reviewer.

| Commit | Content | Migration (SHA-256) |
|---|---|---|
| `fc7b236` | OI-86: `issue_order_summary` locks the project row `FOR NO KEY UPDATE` | `20261126120000` (`c57be580…5773b14`) |
| `33eb953` | OI-87: `order_summaries.change_reason` is not readable by API users (column grants) | `20261126120100` (`f173ba41…e86fb`) |
| `95d03a1` | N1(a): refund and dispute attribution at receipt; conflict candidates captured atomically; persistent G2 and G4 blocks | `20261126120200` (`a9d99d16…5d09b`) |
| `aec8ff3` | The release-approval cross-check (04 §10.2) and the Amendment 2 test corrections | `20261126120300` (`20953c2e36d44f5a496e69ba0c0f84451f6577d7dbf4d018af706d6b953be18a`, identical to the held draft) |

**Amendment 2 dispositions (exact inventory):**

- **Disposition A** is the only assertion change.
  - Where: `supabase/tests/120_wpb_final_balance_holds_gate.test.sql`, lines 199–201 at `95d03a1`; lines 240–242 at `aec8ff3`.
  - Original: `array['duplicate_obligation', 'duplicate_obligation']`, "T-PAY-13: a repeated approval and a later release revision collapse onto the existing obligation".
  - Replacement: `array['rejected', 'duplicate_obligation']`, "T-PAY-13 / OI-92: an approval of a superseded release is rejected; the current release's approval collapses onto the existing obligation".
  - Guarantee: unchanged (no repeated or later approval creates a second obligation), plus the superseded release's approval is rejected with `release_superseded`. The "exactly one obligation and one outbound create" assertion is unchanged.
- **Disposition B1:** T-PAY-22 (130 line 351 at `aec8ff3`) is unchanged.
  - Immediately before it, the Owner reconciles the T-PAY-26 quarantined payment through the existing `public.resolve_quarantined_event` (`aal2`, fresh MFA, live session, a reason).
  - That call records the review and re-derives the gates from all the evidence. No anomaly rule changes.
- **Revision 2 helper:** `pg_temp.genuine_release_approved` in 120, 130, 150 and 160.
  - It inserts the release (recorded by the active Admin) and the approval (by the project's non-staff client member).
  - It fails the test unless `private.project_fulfillment_status` reports both as current.
  - It then writes a **synthetic test emission** in WP-C's payload shape. It is labelled as such and is distinct from WP-C's `approve_preview`, which is unchanged.
- **Setup-only changes:**
  1. 120: `pg_temp.release_approved` calls the helper.
  2. 120: `ev0`'s release is `30000000-0000-4000-8000-000000000000`.
  3. 120: the pair's first event is a synthetic re-delivery of release …001's recorded approval …001, under key `release.approved:redelivery:40000000-0000-4000-8000-000000000001`. It is consumer-defense construction, not a WP-C emission.
  4. 130, 150 and 160: `pg_temp.approve` calls the helper, with IDs and keys unchanged.
  5. 150: the direct emission adds `release_id`, `release_number` and `commit_sha`.
  6. `tests/integration/wpb-billing.test.ts`: one genuine release and its first approval, checked against the fulfillment interface, before the two emissions. Keys and assertions are unchanged.
- **Compensating coverage:**
  - **C-1** (120): a further event for the current release and approval returns `duplicate_obligation`, and both counts stay at one.
  - **C-2** (120): detail `release_superseded`, a `release_approval.rejected` audit and a `payment.final_balance_blocked` notification exist, and no outbound request is added.
  - **C-4** (190): a G4-listed quarantined event rejects with `balance_gate_anomaly` and creates nothing. After the authorized resolution, a valid approval proceeds.
- **Amendment 1 cross-check acceptance** (new `supabase/tests/190_wpb_release_crosscheck.test.sql`, 47 assertions; positive cases consume WP-C's own `approve_preview` emission):
  - positive: the current approved release;
  - missing release;
  - another project's release;
  - another release's approval, and an unrecorded approval;
  - mismatched number, mismatched SHA, and a missing version;
  - superseded, withdrawn and archived;
  - a G2 anomaly (N1(a) conflict);
  - a G4-listed anomaly;
  - the interface not implemented.

  Every rejection is audited and notified, with no obligation and no outbound request.
- **Concurrency** (`tests/integration/wph-hardening.test.ts`): two connections, both orders, with WP-C's real `release_preview`, `withdraw_preview` and `approve_preview`.
  - The second transaction is shown to wait every time.
  - A supersession or withdrawal committed first rejects; a consumption committed first initiates and keeps the obligation (OI-92(e)).
  - A stale approval is never consumed.
  - Exactly one obligation results, and there is no 40P01.
  - The races' final-balance creates are settled afterwards through the executor's normal path, so no pending request leaks into another suite.
- **Static guards:**
  - `tests/unit/wpb-contracts.test.ts`:
    - exactly the four `_wph_` migrations;
    - the exact `create or replace` allow-list: `project_financial_status` plus `issue_order_summary`, `handle_refund`, `handle_dispute`, `handle_charge_refunded`, `process_stripe_event`, `project_financial_anomalies`, `resolve_quarantined_event` and `consume_release_approved`;
    - the WP-B additive-only restrictions applied to the WP-H SQL;
    - one new table and one grant.
  - `tests/unit/wpb-static.test.ts`: the WP-B payment invariants on all four WP-H migrations.
  - Every existing restriction is unchanged.

**Local verification at `aec8ff3`.** Supabase CLI local stack; CI's environment (`APP_ENV=test`, `NEXT_PUBLIC_SITE_URL=http://localhost:3100`); per-run test webhook secret; synthetic data; no provider.

| Command | Result |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 16 files, 286 passed |
| `pnpm audit --audit-level=high` | No known vulnerabilities |
| `gitleaks git` | 95 commits, no leaks |
| `supabase db reset --local`; `supabase test db` | 30 files, 1,605 tests, PASS |
| `pnpm test:integration` | 7 files, 96 passed |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` | 51 passed |
| Lighthouse | Not run locally (CI) |

**Local verification after synchronization** (merge of `b027e41`; same environment as above).

| Command | Result |
|---|---|
| `sha256sum` of `20261126120300` | `20953c2e36d44f5a496e69ba0c0f84451f6577d7dbf4d018af706d6b953be18a` (unchanged) |
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 17 files, 303 passed (adds PR #28's readiness-gate unit file) |
| `pnpm audit --audit-level=high`; `./scripts/check-migrations.sh origin/main` | No known vulnerabilities; no merged migration changed |
| `supabase db reset --local`; `supabase test db` | 30 files, 1,605 tests, PASS |
| `pnpm test:integration` | 7 files, 96 passed (PR #28's 81 plus WP-H's 15) |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` | 51 passed |

**Reviews at `0b1e542`** (durable non-approval PR comments). Each needs a new record for the synchronized head (AUTH-006 "Merge").

| Reviewer | Comment | Result |
|---|---|---|
| Main | 7159127341 | No blocking findings. M-1 to M-4: M-1 is this synchronization; M-2 is AUTH-009's inventory; M-3 and M-4 need no change |
| WP-S, independent financial | 7168757687 | No blocking findings. F-1 to F-3 need no change; F-1 is consolidated into AUTH-013 |
| WP-C, read-only | 7168769499 | B-1, recorded as **OI-113** |

**Known limitation until AUTH-013 lands: OI-113, a mandatory R1 release-candidate blocker that is open.**
- **When it happens:** two client members of one project approve the same release concurrently, and the earlier-started transaction takes the release lock second.
- **What goes wrong:** WP-C's emitting approval and `project_fulfillment_status.current_release_approval_id` disagree. The WP-H cross-check then rejects the initiation with **`approval_mismatch`**.
- **Effect:** it fails closed, with no obligation, no outbound request and no charge. The automatic initiation does not happen, and the Owner receives `payment.final_balance_blocked`.
- **Decision (Owner, 2026-11-25):** option (a), a separately authorized WP-C interface correction (AUTH-013, proposed). WP-H's strict approval matching is kept, and WP-H does not change for it. Option (c), re-release and re-approval, is an emergency recovery procedure only, never closure.

The Owner merges, pinned to the exact head.

## 11. WP-S implementation record

Local evidence for the §9 WP-S directive on `wp-s/sales-representative` (from `005cc36`; AUTH-005 recorded at `a8ae91d` before any implementation). **Verified** by the commands named, on a freshly reset local stack (Supabase CLI 3.2.0, checksum verified; Node 24.22.3; pnpm 12.21.0), in the CI order. Remote CI for the exact head is recorded in the pull request. Lighthouse was **not run locally**; it runs in CI.

### 11.1 Directive items

| Item | Implementation |
|---|---|
| 1. Entry | Branch, baseline `005cc36`, and authorization commit `a8ae91d` verified; `wpc_is_client_member` (`staff_role_of(...) is null` plus membership) and `record_live_verification` (Owner or Admin requester) present; baseline pgTAP 24 files, 1166 assertions, all pass |
| 2. Migration A | `20261125120000_wps_staff_role_sales.sql`: `staff_role` adds `sales` (only statement) |
| 3. Migration B, Phase 2 objects | `20261125120100_wps_sales_representative.sql`: `invitations_kind_shape` (adds `sales`); `is_staff()` = `coalesce(staff_role_of(uid) in ('owner','admin'), false)` (strict boolean, so every `not is_staff() or …` restrictive policy is unchanged for clients); `create_invitation` and `revoke_invitation` (Sales: client invitations to an actively assigned project only, never to a staff address, per-user Sales bucket; any inviter: no client invitation to a Sales address); `accept_invitation` (adds `sales_role` and `client_membership` rejections); `set_staff_role` (rejects `sales` with an active membership). Owner and Admin bodies copied verbatim |
| 4. New objects | `project_sales_assignments` (one active per project; ended once, never deleted) and `project_sales_assignment_history` (append-only, trigger-written), both with RLS and the restrictive loops, no write grant to any API role; `is_sales()`, `sales_assigned(uuid)`; `sales_create_customer_project`, `assign_sales_representative`, `end_sales_assignment`, `sales_list_customers`, `sales_project_progress` (definer, `search_path = ''`, invoker wrappers); `billing_package_scope` (flag, bidirectional label check, environment-allowlist trigger, no grants) and `current_package_scope(text)` (allowlist re-checked per call; a current version with an ineligible fixture returns nothing). Helper triggers: `project_sales_assignments_guard`, `project_sales_assignments_history`, `billing_package_scope_fixture_guard` |
| 5. Rate limits | Per-user buckets: customer creation 10/hour, Sales invitation operations 30/hour (WPS-P5); rejections audited `sales.rate_limited` |
| 6. WP-B | `issue_order_summary` replaced with one added caller (`sales_assigned`, re-read after the project lock); for Sales only: scope or notes rejected and audited, scope copied from the current definition with its version in `order_summary.issued`, missing definition fails closed, acceptance or verified deposit rejects after the order-summary lock. Owner and Admin path, signature, grants, pricing, OI-81 unchanged. **Awaiting WP-B review** |
| 7, 7a | Termination at the next check; `end_sales_assignment` locks the project row, so concurrent Sales writes wait and then see the ended assignment. Invitations and order summaries survive the end. Resend = revoke then reissue in `src/server/services/invitations.ts`, for every role, with controls in `/staff`, `/staff/team`, and `/sales` |
| 8. App | `AuthContext.sales` and `anyStaffRole`; `requireSales` (aal2, forced MFA); `requireStaff` unchanged (Sales sent to `/sales`); `requireClient` = no staff role of any kind plus an active membership (WPS-P3); global sign-out for every staff role; MFA pages accept Sales; Owner role selector with `sales`; Owner and Admin assign and end assignments on the team page; `/sales` (customers, create, order summary, invite, resend, revoke, progress) |
| 9. Audit | WP-S contract section (`WP_S_AUDIT_ACTIONS`), plus three rejection names (WPS-P6) |
| 10. Tests | §11.2 |
| 11. Shared files | Additive only: `src/domain/contracts/audit-actions.ts`, pgTAP 050 list, `seed.sql`, `src/lib/messages.ts`; also `playwright.config.ts` (a `wps` project), the static guard test (recognizes `requireSales`), and the `AppShell` nav union |
| 12. Order | After `20261124160100`; A before B |
| Serialization added | Per-user transaction lock in `accept_invitation` and `set_staff_role('sales')`, so a concurrent role grant and client acceptance can never both succeed |

### 11.2 Acceptance-test traceability

pgTAP: `supabase/tests/300_wps_sales_access.test.sql` (90), `310_wps_sales_commercial.test.sql` (157). Integration: `tests/integration/wps-sales.test.ts` (14). Unit: `tests/unit/wps-sales.test.ts` (11). E2E: `tests/e2e/wps.spec.ts` (6).

| Test | Where |
|---|---|
| T-SALES-01 | 300 |
| T-SALES-02 | 300: enumerated call of every exposed RPC (≥ 60) as Sales at aal2 with its own assigned project, all refused, no table written, with positive controls; helper results; static check that no other definer function mentions the role |
| T-SALES-03 | 300 (aal1); integration (real aal1 session); e2e (forced enrollment) |
| T-SALES-04 | 310; e2e (database and audit rows) |
| T-SALES-05, T-SALES-21 | 310; e2e (404) |
| T-SALES-06 | 310; unit (no amount, scope, or note on the Sales path); e2e |
| T-SALES-07 | 310; e2e |
| T-SALES-08, T-SALES-30 | 310 |
| T-SALES-09 | 300 |
| T-SALES-10 | 310 |
| T-SALES-11 | 300 |
| T-SALES-12 | unit (guards); e2e |
| T-SALES-13 | 310 |
| T-SALES-14, T-SALES-18 | 310 (role revoked in the same session); e2e |
| T-SALES-15 | 300 |
| T-SALES-16 | 300 |
| T-SALES-17 | 310 (duplicate, invalid input, injected failure); integration (5 concurrent duplicates → one set) |
| T-SALES-19 | 310 |
| T-SALES-20 | 300 (aal1, 13-hour session, deleted session, deactivated user) |
| T-SALES-22 | 300; the full existing suites below |
| T-SALES-23 | 300: every exposed table and view, aal1 and aal2, reads and writes (reading per WPS-P2) |
| T-SALES-24 | 310 (create, link and portal acceptance, staff acceptance, `set_staff_role`, client-only functions with a fixture membership); unit (`requireClient`); integration (role grant racing acceptance). **Policy clause not satisfiable under AUTH-005: WPS-P1** |
| T-SALES-25 | 300 |
| T-SALES-26 | 310; integration (real, unexpired token); e2e (open browser session) |
| T-SALES-27, T-SALES-35 | 310; e2e |
| T-SALES-28 | 300, 310; e2e |
| T-SALES-29 | 310; integration (12 concurrent → exactly 10 succeed) |
| T-SALES-31 | 310 (including A5: a new version leaves the issued snapshot and hash unchanged); e2e |
| T-SALES-32 | 310 (serial); integration (both interleavings deterministic; true races for the Sales and Owner paths, WPS-P4) |
| T-SALES-33 | 310 (Sales; Owner); integration (Sales, Owner, Admin, real Auth); e2e |
| T-SALES-34 | 310 |
| T-SALES-36 | 310 (label and flag both ways, insert and update; staging, preview, missing; leftover fixtures not returned; development and test; no API access to the classification); unit (no fixture row in any migration) |

Concurrency also covered (integration): assignment end racing an order summary and an invitation (the write waits, then is refused); invitation revocation racing acceptance, both orders.

### 11.3 Suites (local, fresh reset, CI order)

| Suite | Result |
|---|---|
| Migration immutability (`scripts/check-migrations.sh origin/main`) | Pass |
| pgTAP (`supabase test db`) | 26 files, **1413** assertions, all pass (existing 24 files and 1166 assertions unchanged except the additive 050 row) |
| Unit (`pnpm test`) | 16 files, **283** tests, all pass |
| Integration (`pnpm test:integration`) | 6 files, **76** tests, all pass (WP-S 14) |
| Build, bundle secret scan (13 files), production-mode build | Pass |
| E2E (`pnpm test:e2e`, `APP_ENV=test`) | **50** tests, all pass (WP-S 6). Locally with the preinstalled Chromium (`PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH`); CI installs its own |
| Lint, typecheck, format | Pass |
| Lighthouse | Not run locally (CI) |

**Environment note:** the session environment's allowlist gained `pkg-containers.githubusercontent.com` (Owner-approved in-session, 2026-11-25) so the local Supabase images could be pulled; no credential, secret, or provider access was added.

### 11.5 Independent review record

| Review | Head | Result |
|---|---|---|
| Main, comprehensive | `72da723` | Returned for targeted correction (OI-85; WP-B approval not recorded); accepted by the Owner |
| WP-B, financial (`issue_order_summary`) | `72da723` | Approved (14 criteria); GitHub review not recordable under one identity |
| Main, focused re-review | `1eda945` | OI-85 closed; technically approved; findings: DEP-18 version sealing (amendment), OI-90 (runbook) |
| WP-B, corrected head | `1eda945` | Approved (Owner-reported); the durable record on the final head is pending under the exit-criterion 4 governance amendment |

Full-suite evidence for the unchanged implementation: CI run 45531629347 (#76) on `1eda945`, 7/7 `success` (pgTAP 1,484 assertions in 27 files, integration 81, e2e 51 locally per §11.4).

### 11.4 Correction record (§12 directive, OI-85, DEP-18 append-only)

Executed on `wp-s/sales-representative` after the authorization commit `9803af7` (and Main's clarification `d053550`). **Verified** on a freshly reset local stack in the CI order. Remote CI on the exact corrected head is recorded in PR #23.

**Pre-implementation checks (recorded before any change, fresh `supabase db reset`):** conflicting users (active Sales role and active membership) **0**; staff of any kind with an active membership **0**; existing triggers `project_memberships`: `audit_project_memberships`; `staff_roles`: `audit_staff_roles`, `staff_roles_protect_last_owner`; `billing_package_scope`: `billing_package_scope_fixture_guard`; `service_role` may INSERT into `staff_roles` and `project_memberships` but not UPDATE (so service-role evidence uses inserts, update paths run as the migration owner); `is_project_member` matched the Phase 2 definition. Callers of `is_project_member`: `can_access_project` (and through it `record_asset_access`, `project_status`, `get_intake_state`, the WP-C table policies, storage), the `client_businesses`, `order_summaries`, `agreement_versions`, and `agreement_acceptances` policies, `accept_agreement`, and the WP-B client functions and policies (which already also required `staff_role_of(...) is null`). Lock order: `accept_invitation` and `set_staff_role('sales')` take the per-user lock first; the advisory lock is re-entrant, so they are unchanged. Merged suites rely on Owner and Admin memberships (225 §9), which the Sales-scoped C2 and C3 keep permitted.

**Changed-object inventory (exactly C1 to C5, one migration `20261125120200_wps_oi85_separation.sql`):**

| # | Object |
|---|---|
| C1 | `private.is_project_member(uuid)` replaced: existing conditions plus `staff_role_of(uid) is null` and no active `staff_roles` row; same signature and grants |
| C2 | `private.project_memberships_sales_separation()` + trigger `project_memberships_sales_separation` (BEFORE INSERT OR UPDATE) |
| C3 | `private.staff_roles_sales_separation()` + trigger `staff_roles_sales_separation` (BEFORE INSERT OR UPDATE) |
| C4 | Migration-time conflict check (raises, changes nothing), before C2 and C3 are created |
| C5 | Triggers `billing_package_scope_append_only` (BEFORE UPDATE OR DELETE, `private.insert_only()`) and `billing_package_scope_no_truncate` (BEFORE TRUNCATE, `private.audit_events_immutable()`) |

Trigger functions are SECURITY DEFINER with `search_path = ''` and no execute grant for any API role. The two reviewed WP-S migrations are byte-for-byte unchanged (`git diff 72da723` empty for both). No other database object, no app change.

**Tests changed or added (WP-S files only; no existing Phase 2, WP-0, WP-B, or WP-C assertion changed):**
- pgTAP **300** (90 → 113): the authorization-without-triggers fixture (C2 disabled by name only around the insert, inside the rolled-back transaction, and re-enabled before any assertion). With a Sales membership on Project A and its own project, the representative reads no `projects`, `client_businesses`, `order_summaries`, `agreement_versions`, `agreement_acceptances`, upload, intake, release, or storage row, and the enumeration over every table and view shows only its own identity rows. `record_asset_access` on a released file, `project_status`, and `get_intake_state` are refused, and every exposed RPC is refused on both projects with no row written. Positive controls: the real client is authorized on the same released file and project. The static list adds the two C2/C3 functions.
- pgTAP **310** (157 → 173): the function checks use the controlled fixture. The diagnostic is replaced with real assertions (no project, business, or order-summary row; `project_status` refused). T-SALES-31 adds append-only enforcement: owner, Owner (authenticated), and `service_role` cannot update, delete, or truncate; version 1 stays exactly what the first summary copied; version 2 is a new row set. T-SALES-36's update assertions expect the append-only rejection, and the label check is still proven on update with C5 disabled only inside the transaction. The missing-definition case disables C5 only around its deletion.
- pgTAP **320** (new, 32): C2 and C3 for the migration owner and `service_role`, insert and update, both directions; inactive rows are not conflicts; scoped to Sales (an Admin may hold a membership and keep it); `set_staff_role` and `accept_invitation` keep their own audited rejections ahead of the trigger; C1 for Admin, Owner, client, a former staff member, and a deactivated user; the client invitation path; and C4 (no conflict remains).
- Integration (+5): direct-writer interleavings in both orders (the second waits on the per-user lock, then fails 42501); six true races (exactly one succeeds each time); `service_role` refused in both directions; and a real signed-in Sales session holding an inconsistent membership (a temporary local fixture, trigger disabled only inside its one transaction, removed afterwards) is refused by `deliverAsset`, `record_asset_access`, and `project_status`, and reads no project or upload row, with no `upload.accessed` audit.
- E2E (+1): the portal asset route returns 404 to the Sales browser session under the same fixture; the portal page sends it to `/sales`; no access audit.
- Unit (+1): the new migration contains only C1 to C5, runs C4 before the triggers, and contains no data change or other DDL.

| Suite (local, fresh reset, CI order) | Result |
|---|---|
| Migration immutability | Pass |
| pgTAP | 27 files, **1484** assertions, all pass (existing 1166 unchanged) |
| Unit | 16 files, **284** tests, all pass |
| Integration | 6 files, **81** tests, all pass (WP-S 19) |
| Build, bundle scan, production build | Pass |
| E2E | **51** tests, all pass (WP-S 7) |
| Lint, typecheck, format | Pass |

**T-SALES-24** now passes in full (every clause asserted; no diagnostic or expected failure). **T-SALES-31** and **T-SALES-36** are verified with the append-only rule.

**Remaining findings and limitations (not in this round):**
- **OI-86:** the deadlock is preserved as-is; the integration race test still records it.
- **OI-87:** `change_reason` is still client-readable.
- **OI-88:** the user-experience reassessment is still pending.
- **DEP-18:** no production scope content exists, so Sales issuance stays fail-closed outside the seed.
- **The triggers have one stated limit:** they do not protect against a database owner who disables or replaces them, as approved.
- **With an inconsistent fixture membership, a Sales user can still read its own membership row** through the unchanged Phase 2 `project_memberships_select` policy (its own identity row; no client-only data). That state cannot be created while the triggers are enabled.
- **This environment only:** e2e ran with the preinstalled Chromium, and the allowlist entry from §11.3 is unchanged.

**Correction effort (OI-67):** AI session about 0.3 h (2026-11-25, 01:58–02:16 UTC); administrative about 0.05 h (local Docker restart after a container recycle); Owner review 0 h so far.

## 12. PR #23 targeted correction directive (Main, 2026-11-25) — executed; PR #23 merged at `d75bd94`

Owner disposition of Main's independent review of PR #23 at `72da723` (base `005cc36`, CI run 45521097273): **not authorized for merge; one targeted correction round**. Authority: AUTH-005 with the **OI-85 amendment** and the DEP-18 append-only approval (AUTHORIZATIONS AUTH-005). This record precedes every corrective change. WP-S implements; Main re-reviews; WP-B reviews and records its approval in the PR review mechanism; the Owner alone merges.

**Exact authorized object inventory for this round (nothing else):**

| # | Object | Change |
|---|---|---|
| C1 | `private.is_project_member(uuid)` (Phase 2) | `create or replace`, same signature and grants: existing conditions **and** `private.staff_role_of((select auth.uid())) is null` **and** no active `public.staff_roles` row for the caller (the `private.wpc_is_client_member` test). Owner and Admin are unaffected (every caller ORs `is_staff()`); clients are unaffected |
| C2 | New trigger function + BEFORE INSERT OR UPDATE trigger on `public.project_memberships` | When `NEW.status = 'active'`: take the existing per-user lock on `NEW.user_id`, then refuse (errcode `42501`) if that user has an active `staff_roles` row with role `sales` |
| C3 | New trigger function + BEFORE INSERT OR UPDATE trigger on `public.staff_roles` | When `NEW.status = 'active' and NEW.role = 'sales'`: take the same per-user lock on `NEW.user_id`, then refuse if that user has an active `project_memberships` row |
| C4 | Migration-time conflict check | Before C2 and C3 are created: if any user holds an active Sales role and an active membership, `raise exception` and stop. Never repair, delete, or rewrite data |
| C5 | `private.billing_package_scope` (WP-S) | BEFORE UPDATE OR DELETE `private.insert_only()`; BEFORE TRUNCATE `private.audit_events_immutable()`. The fixture trigger and allowlist are unchanged |

Rules: one new forward-only migration after `20261125120100`; the two reviewed WP-S migrations stay byte-for-byte unchanged, so the review of `72da723` remains valid; trigger functions SECURITY DEFINER, `search_path = ''`, `revoke all ... from public, anon, authenticated, service_role`; the triggers fire for every writer including `service_role`; scope C2 and C3 to the approved invariant (Sales role versus active membership; 03 §4.1(a)), so the existing Owner/Admin-with-membership test data and workflows keep working. Lock order: the per-user advisory lock is re-entrant in the same transaction, so `accept_invitation` and `set_staff_role('sales')`, which already take it first, are unchanged; a direct writer takes it in the trigger.

**Two distinct rules (Owner clarification, 2026-11-25).** (1) **Universal authorization invariant (C1):** no staff role of any kind exercises client-only authorization through a membership; `is_project_member` excludes every staff role, and every other client-only check already does (`staff_role_of(...) is null` in WP-B, `wpc_is_client_member` in WP-C, `requireClient` in the app). Owner and Admin reach projects only through their staff paths (`is_staff()` / `is_owner()` branches, with the `aal2` and live-session restrictive policies); no call site gives them anything through `is_project_member` alone. (2) **Sales-specific integrity constraint (C2, C3):** only the Sales role and an active membership are mutually exclusive in data (03 §4.1(a)). Owner and Admin memberships are not prohibited by any approved rule, Phase 2 `accept_invitation` lets them accept a client invitation, a revoked staff member may become a client and later be re-granted Owner or Admin, and merged suites rely on such rows (`225_wpc_scan_authority` §9 inserts Owner and Admin memberships and re-activates an Admin role while the membership exists; `310_wps_sales_commercial` uses an Admin with a membership). Widening C2/C3 would change those workflows and existing assertions, so the narrower scope is retained; under C1 such memberships grant no client authorization.

**Before implementing, verify and record:** the affected object list above against the branch; every caller of `is_project_member` (Phase 2 `can_access_project`, the policies on `client_businesses`, `order_summaries`, `agreement_versions`, `agreement_acceptances`, the WP-B client functions, WP-C `record_asset_access`, `project_status`, and the policies built on `can_access_project`); existing lock ordering; trigger execution privileges; and that no seed or test data holds a conflicting state. **Stop and report** if conflicting data exists, or if any change outside C1 to C5 becomes necessary.

**Tests (all real assertions; no diagnostic or expected failure):**
- **T-SALES-24 in full** (03 §13): with a controlled local/CI-only inconsistent-data fixture (disable only the C2/C3 triggers by name inside the rolled-back pgTAP transaction, as the migration owner; never an application-accessible mechanism or a production bypass), a Sales Representative holding a membership reads no client-only `projects`, `client_businesses`, `agreement_versions`, `agreement_acceptances`, `order_summaries`, intake, upload, or release row; `project_status` is refused; `record_asset_access` is refused; the portal asset route returns 404 (integration or browser evidence); every exposed RPC is still refused. With the triggers enabled: inserts and updates as `service_role` and as the migration owner that would create the conflict are rejected in both directions; a concurrent role grant and membership write never both succeed (integration, two connections); Owner, Admin, and client workflows, including the Admin-with-membership fixture, still work; client-only write and financial protections are unchanged.
- **T-SALES-31** adds: update, delete, and truncate of `billing_package_scope` are rejected for every role; a new version is a new row set; historical versions stay readable and issued snapshots unchanged. Tests that need a missing scope definition use a package or version without rows, or disable C5 only inside the rolled-back test transaction.
- **T-SALES-36** stays as approved; update-path assertions now expect the append-only rejection.
- Full Phase 2, WP-0, WP-B, and WP-C suites unchanged; all 7 CI jobs `success` on the exact corrected head.

**Documentation in the same PR:** CURRENT-STATE §11 (traceability, evidence, the new migration), and effort (OI-67). The decisions themselves are already recorded (08 OI-85 to OI-89; OPEN-ISSUES; AUTHORIZATIONS; 03 v0.5.10; 04 v0.9.7).

**Not in this round:** OI-86 (`FOR NO KEY UPDATE`), OI-87 (`change_reason` privileges), OI-88 portal path, any production scope content (DEP-18), Stripe, hosted providers, production, WP-D, commission features, PR #6.

**Exit:** OI-85 corrected; T-SALES-24 passing in full; append-only scope enforced and verified; T-SALES-01 to T-SALES-36 satisfied; existing suites unchanged; 7/7 CI on the exact head; WP-B's independent technical review recorded on PR #23 **as the review record defined in the AUTH-005 exit-criterion 4 governance amendment (a PR comment or non-approval review; not a GitHub APPROVED review; Owner, 2026-11-25)**; Main's focused re-review; R1 release-candidate blockers preserved.

**Status (2026-11-25):** executed at `1eda945` (§11.4). Main's focused re-review accepted: OI-85 **closed**; T-SALES-24, T-SALES-31, and T-SALES-36 pass; C1 to C5 only; the two reviewed migrations byte-identical; no WP-B, WP-C, or app change; CI run 45531629347 (#76) 7/7 `success` with the full suite. Every later commit is documentation only. Remaining before the Owner's pinned merge: WP-B's review record on the final head and 7/7 CI on that head.

## 13. R1 development execution plan (Main, 2026-11-25; proposed, nothing started)

Baseline: `main` at `a8c6ddc` (PR #24, post-merge CI run 45538366194 7/7). Authorizations: **AUTH-006 (WP-H), AUTH-007 (WP-D18), and AUTH-008 (I-1 only) granted by the Owner on 2026-11-25; **active since 2026-11-25**. **Activation record:** PR #25 merged at `58d0e98981befe32f8ddff11c89ce7952dad3a72` (parents `a8c6ddc`, `1386465`; tree identical to the authorized head; documentation only); post-merge CI run 45543204966 (#82) 7/7 `success` with the full suite executed. **Common implementation baseline: `58d0e98981befe32f8ddff11c89ce7952dad3a72`**; WP-I-1, WP-H, and WP-D18 branch from exactly this commit (not from later documentation merges). I-2 needs a separate grant. Handoff prompts: [R1-HANDOFFS.md](R1-HANDOFFS.md).

| Package | Implementer | Independent review | Branch | Migrations | Shared files |
|---|---|---|---|---|---|
| WP-I, I-1 | Integration session | WP-C, WP-B, Main | `wp-i/integration-infra` | none | `playwright.config.ts`, `tests/support/*` (owner during I-1) |
| WP-H | WP-B session | WP-S or a fresh review session (financial), Main | `wp-h/financial-hardening` | `20261126120000` to `20261126120300` | WP-B static guard tests |
| WP-D18 | WP-S session | WP-B, Main | `wp-d18/scope-sealing` | `20261126140000` | `supabase/seed.sql` (WP-S section; sole owner) |
| WP-I, I-2 | Integration session | WP-C, WP-B, Main | `wp-i/r1-e2e` | none (pgTAP only) | `playwright.config.ts`, `lighthouserc.json`, `.github/workflows/ci.yml` (Lighthouse job) |

**Sequence:** I-1, WP-H, and WP-D18 run in parallel from the verified authorization merge commit (disjoint objects; no provider); merge I-1, then WP-H, then WP-D18, each later one rebased with the re-verification in AUTHORIZATIONS; then I-2 against the integrated `main`; then AUTH-002 sandbox verification (F7, F8, N1(c)) after WP-H; then WP-D under AUTH-003 (DEP-17, DEP-12, hosted staging, migrations-only deployment); then R1 release-candidate acceptance.

**Owner actions:** grant AUTH-006, AUTH-007, AUTH-008 (I-1), and later the I-2 seams; supply the five package definitions (DEP-18); engage counsel for DEP-03 (agreement, payment authorization, F10 wording, package scope); choose the malware scanner (DEP-07) and monitoring (DEP-12) vendors; review OWNER-RUNBOOKS including §7 (OI-90); reassess the OI-88 invitation experience before the R1 release candidate.

**WP-H status (2026-11-25):** stopped at an AUTH-006 boundary; OI-86 and OI-87 implemented at `33eb953` (Main preliminary verification: OI-86 changes only the lock clause; OI-87 grants every column except `change_reason`; six-caller concurrency and strengthened T-SALES-32 tests present; static guard extension and N1(a) and the cross-check not yet done). **AUTH-006 Amendment 1** approved; WP-H resumes only after its merge and full post-merge CI (continuation handoff: R1-HANDOFFS §1A).

**AUTH-006 Amendment 1 activation record (2026-11-25):** PR #29 merged at `7469b2d4f899ea7d25a43d86088ce92b5bfb3cb5` (parents `b4a43bc`, `59e89e6`; tree identical; documentation only); post-merge CI run 45558153619 (#89) 7/7 `success` with the full suite. **WP-H may resume** from `33eb953` (R1-HANDOFFS §1A). **Corrections pending:** WP-I-1 readiness timeout (AUTH-008 Amendment 1; R1-HANDOFFS §3A) before PR #28 merges; WP-D18 (AUTH-007 Amendment 1; R1-HANDOFFS §2A) before PR #27 merges. Merge order unchanged: WP-I-1, WP-H, WP-D18. Implementation PRs keep their CURRENT-STATE edits inside their own implementation-record sections to avoid conflicts with these records.

**DEP-18 Phase 4 reconciliation (Owner, 2026-11-25; 08):** FD-05 (Owner-controlled, audited and hash-verified contractual content loading; no loading authorized; mechanism not chosen), FD-14 (individual T-SALES-36 assertion dispositions before PR #27 merges; Change 1 ratification withheld as written; no blanket ratification; R1-HANDOFFS §2A lists D-1 to D-10) and H-0 (PR #30 corrected before merge) are reflected in AUTH-007 Amendment 1. The day-3 reminder (non-contractual courtesy only) and the scope-confirmation prerequisite (mandatory acknowledgment before preview release, no bypass) are recorded, not implemented. **PWP-0** is conditionally granted and **not active**; its branch does not exist; it activates only when its seven Owner prerequisites hold, including PR #30 merged by the Owner and post-merge CI on the exact baseline. DEP-03 and DEP-18 stay open. **Contractual reconstruction (Owner, 2026-11-25; 08):** the original contractual specification suite is unavailable; SLM-CPS-001 to SLM-CPS-007 exist outside Git as v0.1.0 reconstruction drafts (not approved, not publishable, not eligible content); FD-04, FD-12 and FD-13 amended; the 04 §3.1 clause approval is unchanged; the PWP-0 objective is amended to preserve the approved architecture, recoverable decisions and gates during reconstruction. No content loading, sealing, issuance, production activation or new work package is authorized.

**AUTH-007 and AUTH-008 Amendment 1 activation record (2026-11-25):** PR #30 merged at `393e3c875c2db46efb45811ac4ef2a522a09ed26` (parents `7469b2d`, `a4db32a`; tree identical; documentation only); post-merge CI run 45565499637 (#95) 7/7 `success` with the full suite. **WP-I-1 may continue** from `a01b84e` (R1-HANDOFFS §3A) and **WP-D18 may continue** from `6173ffa` (R1-HANDOFFS §2A), except the seed comment correction, which waits for **AUTH-007 Amendment 2** (recorded, activation pending its merge and post-merge CI). PWP-0 stays conditional (14-file inventory; 08). Merge order unchanged: WP-I-1, WP-H, WP-D18.

**AUTH-007 Amendment 2 activation record (2026-11-25):** PR #31 merged at `d9cf32aec6db3e3ffbc2aa810604ddc094093834` (parents `393e3c8`, `e32d6fb`; tree identical; documentation only); post-merge CI run 45567129662 (#97) 7/7 `success` with the full suite. The seed comment correction (R1-HANDOFFS §2A item 7) is implemented on PR #27 at `5ebd664`; Main verified it as comment-only (the non-comment text of `supabase/seed.sql` is identical; no migration changed).

**PWP-0 merge record (2026-11-25):** PR #32 merged by the Owner at `c89bf56740f01e8cf646cf6d4d1838233e606d81` (parents `d9cf32a`, `02761b5`; tree identical; documentation only); post-merge CI run 45575951029 (#101) 7/7 `success` with the full suite. AUTH-011 expired on the merge. Independent records: Main 7156287899 and 7156307411, WP-S 7156346268, WP-C 7156570799, WP-B 7156577361 (none blocking). Next unused identifiers verified on `main` and every remote branch after the merge: OI-113, DEP-21, AUTH-012 (AUTH-012 is allocated by this record to the OI-95 correction; next AUTH-013).

**Consolidated authorization cycle (2026-11-25; 08):** recorded, **activation pending this record's merge and post-merge CI:** AUTH-006 Amendment 2 (WP-H test corrections for the cross-check; R1-HANDOFFS §1B), AUTH-007 Amendment 3 (D-2 to D-10 approved, D-1 unratified, Option A; §2B), AUTH-012 (OI-95; §4, after WP-I-1 merges). Recorded without new authority: the AUTH-008 Amendment 1 clarification (W-1 and the baseline synchronization; §3B). **Not authorized:** AUTH-009 and AUTH-010 (design directions only, OPEN-ISSUES OI-91 and OI-93). Deferred PR #32 findings: S1 and S2 after PR #27 merges; WP-C O-1 and O-2 in PWP-5. Merge order unchanged: WP-I-1, WP-H, WP-D18; OI-95 may follow WP-I-1.

## 14. WP-I I-1 implementation record (AUTH-008, I-1 only)

Original I-1 record (14.1 to 14.3, as reviewed at `a01b84e`), followed by the AUTH-008 Amendment 1 correction (14.4), the Owner-approved W-1 correction (14.5), decisions (14.6), and final-candidate verification (14.7). Implemented by the dedicated integration session (`https://claude.ai/code/session_01RCnsL7k3rDKjjpTicExTsF`; not Main) on `wp-i/integration-infra`. Branched from `58d0e98981befe32f8ddff11c89ce7952dad3a72`; before review, rebased onto `main` at `b4a43bc` (PR #26; `git diff --name-only 58d0e98 b4a43bc` lists only `.md` files and AUTH-008's boundaries are unchanged). `git range-diff` shows both implementation commits identical after the rebase. **Implementation commit: `c829fdb`** (rebased from `045470f`; the same non-documentation tree). Tests and test infrastructure only: no production code, migration, `seed.sql`, workflow, `lighthouserc.json`, WP-B static guard test, or dependency change.

### 14.1 Scope delivered

| Item | Change |
|---|---|
| 1. Real WP-B records | `installDepositFixture` is removed. `createPaidProject` in `tests/support/wpc-fixtures.ts` creates a fresh business, project, and client membership, then runs the WP-B path of `wpb-billing.test.ts`: the Owner issues the order summary, the client accepts, the mocked Checkout gateway starts the session, a synthetic signed `checkout.session.completed` webhook (per-run test secret, OI-63) posts the deposit, and the payment-method lookup records the card. It then checks that the real `private.project_financial_status` reports the deposit verified and the authorization ready and that `private.wpc_intake_unlocked` is true. No test setup replaces a financial function (`grep` of `tests/` finds no `create or replace function`, `alter type`, or `pg_get_functiondef` outside static tests that read migration text). |
| 2. WP-C integration files | `wpc-delivery.test.ts`: project A is a fresh paid project and project B a fresh unpaid project for client B. `wpc-uploads.test.ts`: project A is a fresh paid project, and the seeded `PROJECT_B` is only read (`intake_locked`). `freeQuota(projectId)` is parameterized. The seeded `PROJECT_A` is never paid or written by integration tests (e2e T-LC-01 passes). Every RPC helper reports the PostgREST `error` (`tests/support/rpc.ts` `callRpc`, or an explicit throw before the unchanged `expect(error).toBeNull()`). The T-UP-04 quota setup sums usage for project A only, because client A is now a member of several projects; this is setup arithmetic, not an assertion. |
| 3. Schema-cache sync | `tests/support/postgrest-sync.ts` `withSchemaCacheSync` wraps the committed trigger toggle in `wps-sales.test.ts` and `wps.spec.ts`. A primed PostgREST pool backend from before the DDL is released only when the reload triggered by `pgrst_ddl_watch` finishes, so the helper waits for that release (bounded at 15 s, with diagnostics) and then requires a successful PostgREST request. Measured reloads: 91–137 ms. |
| 4. Shared e2e helpers, `r1` project | `tests/support/e2e.ts` (accessibility check, sign-in, staff at aal2, audit and row helpers) and `tests/support/stripe-events.ts` (signed synthetic events). `playwright.config.ts` has an `r1` project (`r1.spec.ts`, after `wps`), and `r1.` is added to the `testIgnore` lists of `desktop-chromium` and `mobile-chromium`. A temporary probe file was listed only under `[r1]` and then removed. `r1.spec.ts` itself is I-2. |
| F2 gate | `tests/support/postgrest-ready.ts` `waitForPostgrestReady`, run once per integration file from `local-supabase.ts`, before any test (§14.3). |

**Assertions preserved (mechanical check against `58d0e98`).** `expect(` count and test count are unchanged: `wpc-delivery` 70/16, `wpc-uploads` 42/8, `wps-sales` 71/18, `wps.spec` 50/7. In both WP-C files, the multiset of `expect(...)` lines is identical once `PROJECT_A`/`PROJECT_B` are renamed to the fresh `projectA`/`projectB`. In the WP-S files only the wrapping changed (`git diff -w`).

### 14.2 F2 investigation

| # | Suspected cause | Evidence | Finding |
|---|---|---|---|
| a | Schema-cache reload after test DDL | Supabase's `pgrst_ddl_watch` sends `NOTIFY pgrst` for `ALTER TABLE`, `CREATE FUNCTION`, and `ALTER TYPE`. PostgREST v16.5 logs a pool re-initialization and a config and schema-cache reload for each one. Baseline suite: 5 reloads (4 from the old fixture's install and restore, 1 from the WP-S trigger toggle); after I-1: 1. A probe with eight concurrent request streams through 40 committed reloads (10 trigger toggles, 10 identical-body function replacements, and 10 fixture install and restore cycles as an authenticated client) returned **0 errors in 22,435 requests**. Controls with no reload (idle, and rolled-back toggles, which send no `NOTIFY`) returned 0 errors in 15,835 requests | Mechanism real; **no transient error reproduced**. The sync now removes this timing dependence deterministically |
| b | Global replacement of `private.project_financial_status` | The fixture made Project A "paid" for every session while installed and depended on an `afterAll` restore | Removed (item 1); no setup DDL remains in the WP-C files |
| c | Unreported PostgREST errors | Some WP-C helpers discarded `error` and read `data` | Fixed (item 2) |
| d | **PostgREST reconnect after `supabase db reset`** | First series (I-1 items 1 to 4 only), 12 consecutive cold resets, each immediately followed by the full integration suite: **run 1 passed** (after more than a minute without PostgREST traffic); **runs 2 to 12 failed**, 2 to 4 `auth-tenancy` tests each, all `503 PGRST001 "no connection to the server"` on the suite's first PostgREST requests, failing within 3–4 ms. Targeted reproduction with PostgREST's log captured from the start of the reset (05:12:44 to 05:12:59 UTC): the listener drops when Postgres restarts; on reconnect, PostgREST's version, settings, and schema-cache queries fail on dead pooled connections; it backs off for 1, 2, then 4 s; requests at 05:12:55 get 503; it recovers at 05:12:59. Synthetic probes from an idle pool did not reproduce it | **Cause supported by evidence:** a suite started within seconds of a reset that followed PostgREST traffic. CI does one reset right after `supabase start`, with no earlier PostgREST traffic, which matches CI never showing it |

A failure that stopped reproducing was not used as evidence. Cause (d) was reproduced on demand, explained step by step from PostgREST's own log, and removed only by the gate below.

### 14.3 Verification (local stack, Supabase CLI 3.2.0 checksum-verified as in CI, Node 24.22.3; synthetic data only)

| Command | Result |
|---|---|
| `pnpm test:integration` at baseline `58d0e98` (warm stack) | 6 files, **81 passed** |
| F2 series 1: 12 × (`supabase db reset`, then `pnpm test:integration`), before the gate | 1 of 12 passed; runs 2 to 12 failed with `PGRST001` (cause d) |
| **F2 series 2:** 12 × (`supabase db reset`, then `pnpm test:integration --silent=false`), implementation as committed | **12 of 12 consecutive runs passed, 81/81 each; 0 PostgREST error codes in any test output.** Reset 9.3–9.8 s; suite 40.1–42.2 s. The gate waited in 10 of 12 runs (258–374 ms; 2–3 `503 PGRST001` each, all before the first test); in runs 1 and 9 it did not wait. Schema-cache sync 91–137 ms |
| `supabase db reset`; `supabase test db` | 27 files, **1,484 tests, PASS** |
| `pnpm test:integration` (same fresh reset) | 6 files, **81 passed** |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` (same stack, CI settings) | **51 passed** (auth-setup 1, auth 8, wpc 5, wpb 5, wps 7, desktop 11, mobile 11, production-gating 3; `r1` 0) |
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check`, `pnpm test` | Pass; unit tests 16 files, **284 passed** |
| CI on the PR head | Recorded in the PR (7/7 required) |

Not run locally: the dependency audit, gitleaks, and Lighthouse (CI only).

### 14.4 AUTH-008 Amendment 1 correction (`99615e2`)

Files: exactly `tests/support/postgrest-ready.ts`, `tests/support/postgrest-sync.ts`, and the new `tests/unit/postgrest-ready.test.ts` (`git diff --name-only a01b84e 99615e2`).

- **Readiness gate (`postgrest-ready.ts`):** a real overall deadline (60 s). Each request is bounded by min(remaining deadline, request timeout 5 s) and aborted with an `AbortSignal` that also covers reading the body; the pause after a failure is bounded by the remaining deadline. Every failed attempt is recorded (kind `http`, `timeout` or `network`; HTTP status; PGRST code; attempt; time). Three consecutive successes are required. At the deadline the gate throws `PostgrestNotReadyError` with the diagnostics (fail closed). It runs once per integration file before any test and never around a test, a financial operation, or an application RPC.
- **Unit tests:** deterministic local fake HTTP servers for the five authorized scenarios (immediate readiness, startup recovery, persistent unavailability, a non-responding request, overall-deadline expiry), plus the three-consecutive-successes rule, a refused connection, and a non-local URL.
- **Renewed cold-reset series at `99615e2`:** 12 of 12 consecutive runs passed (81/81 each); the gate waited in 11 runs (160–266 ms; 1–2 `503 PGRST001` each) and not in run 1. In every run the 503 count in PostgREST's access log equalled the gate's recorded failures: every startup 503 was a gate probe, none reached a test, and no PGRST code appears in any test output. Schema-cache sync 88–126 ms.
- **Real-world fail-closed evidence:** while the local stack was down, the gate stopped after 60,001 ms (588 attempts, all `network ECONNREFUSED`) with those diagnostics, and no test ran.
- **Finding W-1 (reported by this session, confirmed by Main):** the sync helper's database polls went through `tests/support/db.ts` `withDb`, whose connect, client-side response wait, and close are unbounded; `statement_timeout` bounds only server-side execution. Corrected in 14.5.

### 14.5 W-1 correction and `ddl()` clarification (`b415327`; Owner direction and AUTH-008 Amendment 1 clarification, R1-HANDOFFS §3B)

Files: exactly `tests/support/postgrest-sync.ts` and `tests/unit/postgrest-ready.test.ts`. `tests/support/db.ts` is unchanged.

| Requirement | Implementation |
|---|---|
| One absolute deadline over helper-owned operations | `SyncBudget` (15 s): the priming probe, each database connect, `SET`, query, close, the pauses between polls, and the final probe all draw on it |
| Remaining budget recalculated before every step | `budget.bound(step)` before each operation returns min(remaining, step timeout 5 s) and throws once the budget is exhausted |
| Bounds independent of the server | A pg client local to the helper (the local-only host check is kept): `connectionTimeoutMillis` bounds connecting; a client-side `query_timeout` bounds each response wait; the close races `client.end()` against the bound |
| `statement_timeout` | Kept, set before each poll, as defense in depth only |
| No abandoned work | A timed-out query, a failed step, or an unfinished close destroys the socket. A client `error` listener prevents unhandled `error` events, every `end()` promise is settled, timers are cleared, and polling is sequential, so nothing continues after a failure |
| pg internals | pg 8.16.3 (pinned) was verified: `connectionTimeoutMillis` destroys the stream on expiry; `query_timeout` rejects the query but leaves the connection open; `client.end()` waits for the socket's `end` event. The socket is destroyed through `client.connection.stream` (guarded; if absent, the step still fails closed and says so), documented in the file header |
| Diagnostics | `SchemaCacheSyncError` names the step (`probe-before`, `connect`, `set-statement-timeout`, `query`, `close`, `poll-wait`, `reload-wait`, `probe-after`), helper-owned elapsed time, the bound, and the cause |
| `ddl()` | The caller's own authorized local test operation, **not bounded by this helper**. The budget is paused while it runs, so its duration is excluded; code comments, behaviour, and this record say the same |
| Existing fail-closed behaviour | Unchanged: three consecutive successes in the gate; failed probes, missing pooled backends, and an incomplete reload all throw |

**New unit tests** (a minimal fake Postgres wire-protocol server; every test checks the client socket is closed): a stalled connection establishment; a stalled query response; a stalled close (the fake ignores Terminate and stays half-open; destruction is proven by a write being reset); a normal poll and close; cumulative deadline exhaustion, with `ddl()` excluded and no polling after the failure; successful completion with `ddl()` excluded from the helper's time; a failed probe before any DDL; a non-local database URL. File total: 16 tests.

**Mutation sensitivity** (each mutation reverted afterwards): no `connectionTimeoutMillis` → the stalled-connect test fails; no `query_timeout` → the stalled-query test fails; an unbounded close → the stalled-close test fails; no socket destruction → the stalled-close test fails; `ddl()` counted in the budget → both `ddl()`-exclusion tests fail.

**One assertion in the new unit file made deterministic.** It is not an existing acceptance assertion: it was added in this PR at `99615e2` and never merged. The persistent-unavailability test required every attempt to be a 503; 1 run in 20 failed because the final attempt, whose timeout is only the few milliseconds left before the deadline, was correctly aborted as `timeout`. The assertion now requires every attempt except the last to be `503 PGRST001`, and the last to be a 503 or that deadline-bounded timeout. The gate's code did not change. Determinism: each fake-server scenario scripts every answer, and every timing assertion has at least 1 s of slack except the deadline lower bounds (with 20 ms tolerance for timer granularity). Repeat evidence: 30 of 30 runs of the file passed after the change.

### 14.6 Decisions

- **WPI-P1: accepted by the Owner** (AUTH-008 Amendment 1). Bounded, observable PostgREST startup-only failures before any test runs are acceptable: no test before readiness, failures and timing visible, a timeout that fails the suite, no transient PostgREST error during test execution, no weakened assertion, and no general retry masking application failures.
- **WPI-P2 (informational):** `tests/integration/wpc-scan-authority.test.ts` uses `pg` only and needs no gate; RPC calls outside items 1 and 2 already assert `error` and are unchanged.
- **Baseline synchronization (Option A):** `main` was merged into `wp-i/integration-infra` once, after PR #33, with no rebase or force-push. Every `main` record is kept. This record takes §14 (free on `main`; `tests/support/postgrest-ready.ts` cites it), and WP-D18 renumbers its section when it rebases.
- **F2 stays open** until Main's independent verification.

### 14.7 Final-candidate verification

Final candidate: the merge commit `d45e624` (implementation tree identical to `b415327`: `git diff --name-only b415327 d45e624` lists no non-documentation file), integrating `main` at `f37cf7e` (PR #33; post-merge CI run 45583992649 (#103) 7/7 with the full suite). This record is added in a documentation-only commit on top; the exact-head CI run is recorded in the PR.

| Check (local stack; Supabase CLI 3.2.0; Node 24.22.3; synthetic data) | Result |
|---|---|
| **Cold-reset series:** 12 × (`supabase db reset`, then `pnpm test:integration --silent=false`) | **12 of 12 consecutive runs passed, 81/81 each; 0 PGRST codes in any test output.** Reset 11.3–16.3 s; suite 43.9–52.1 s. The gate waited in 8 runs (273–302 ms, 5 attempts, 2 `http 503 PGRST001` each) and not in runs 1, 2, 11, 12; in every run the 503 count in PostgREST's access log equalled the gate's recorded failures. Schema-cache sync 104–168 ms |
| `supabase db reset`; `supabase test db` | 27 files, **1,484 tests, PASS** |
| `pnpm test:integration` (same reset) | 6 files, **81 passed** |
| `pnpm test:e2e --trace off` (CI settings) | **51 passed** |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm lhci` (the CI Lighthouse configuration) | Pass: 2 URLs, 6 runs, all assertions met |
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 17 files, **300 passed** (16 in `tests/unit/postgrest-ready.test.ts`) |
| `tests/unit/postgrest-ready.test.ts` repeated | 30 of 30 runs passed |

No test was retried, skipped, or quarantined, and no assertion outside the one disclosed in 14.5 changed. Not run locally: the dependency audit and gitleaks (CI only).

### 14.8 B-1 correction (WP-C final-head finding at `9e6aba1`; Owner-approved under AUTH-008 Amendment 1)

WP-C's final-head reconfirmation (PR #28 comment 7159321922) found one blocking, test-only issue in the new Amendment 1 unit file. Main found a second race in the same test. Both are in the test "cumulative deadline exhaustion: repeated polls stop at the budget; the caller's ddl() is excluded" in `tests/unit/postgrest-ready.test.ts`. The file was added in this PR and never merged, so no existing acceptance assertion is affected. The helpers behave correctly in both cases: they fail closed and destroy the socket.

| | B-1a (WP-C) | B-1b (Main) |
|---|---|---|
| Assertion | the message regex `/exhausted\|did not complete a reload\|timeout/` | `expect(pg.polls()).toBe(pollsAtFailure)` |
| Cause | `close` was an accepted step, but the regex rejected the close-path message ("client.end() did not finish within the bound; socket destroyed") | the fake Postgres counts a poll when its server side reads the query, so a query sent just before the failure could be counted after the snapshot |
| Observed | WP-C: 2 failures in 86 runs | Main: 1 failure in 45 runs (`expected 55 to be 54`) |
| Reproduction (this session) | deterministic, 3 of 3, in a scratch copy where closes stall after `ddl()`: step `close` at 601 ms of a 600 ms budget, socket destroyed | not reproduced in 100 instrumented parallel runs; the cause is confirmed from the code |

**Correction** (Owner-approved; `tests/unit/postgrest-ready.test.ts` only, +60/−12; no helper change; N-1 excluded):
1. **Per-step message expectations** in place of the single regex. They are stricter, and the accepted step list is unchanged.
2. **The no-background-polling check waits until every connection is closed.** Node delivers a socket's pending data before it closes, so the fake has by then read everything it was sent. The check then asserts that neither the poll count nor the connection count changes.
3. **One new deterministic test** for the budget running out during a poll's close after `ddl()`: step `close`, the message, helper-owned elapsed time, and socket closure.

**Sweep:** all 33 timing and count assertions in the file were reviewed. Only these two could race. The weakest remaining margin is about 1.3× (at least three aborted attempts in 700 ms with 150 ms per-request timeouts), and that assertion has never been observed to fail.

**Verification of the corrected file:**
- Repeated runs: 150 of 150 passed (50 sequential, 100 at four in parallel).
- Mutations, each caught:
  - a close failure reported as step `query`;
  - a changed close message;
  - the helper polling in the background after failure;
  - the old regex restored in the new test;
  - all five earlier W-1 mutations.
- Full unit suite: 17 files, 301 passed.
- Lint, typecheck and format pass.

WP-C and Main agreed the correction resolves B-1 before it was committed. Final-head verification of the combined candidate is in 14.9.

### 14.9 Combined-candidate verification

The combined candidate is the merge commit `cb541df`. Its parents are the B-1 commit `977e1df` and `main` at `a5dfad0`: PR #34, whose post-merge CI run 45665855580 (#112) passed 7/7 with the full suite. This was the second and last single synchronization (Option A), with no rebase or force-push.

Since `f37cf7e`, `main` changed only `OPEN-ISSUES.md`, `docs/08-DECISIONS-AND-CHANGELOG.md`, `docs/AUTHORIZATIONS.md` and `docs/R1-HANDOFFS.md`. The merge was conflict-free, and `git diff --name-only 977e1df cb541df` lists no non-documentation file. `main`'s CURRENT-STATE is unchanged at 1.22.0, so this file keeps 1.23.0. This record is added in a documentation-only commit on top; the exact-head CI run is recorded in the PR.

| Check (local stack; Supabase CLI 3.2.0; Node 24.22.3; synthetic data) | Result |
|---|---|
| **Cold-reset series:** 12 × (`supabase db reset`, then `pnpm test:integration --silent=false`) | **12 of 12 consecutive runs passed, 81/81 each; 0 PGRST codes in any test output.** In every run, the 503 count in PostgREST's access log equalled the gate's recorded failures. Runs 2 to 12: the gate waited 247–277 ms (5 attempts, 2 `http 503 PGRST001` each). Run 1 directly followed a restart of the local stack: PostgREST was still loading its schema cache, and the gate waited **19,869 ms** (190 attempts, 187 `http 503 PGRST002`) before the first test, within the 60 s deadline. This is the bounded, observable startup-only case WPI-P1 accepts. Reset 8.3–22.7 s; suite 37.8–60.4 s; schema-cache sync 77–124 ms |
| `supabase db reset`; `supabase test db` | 27 files, **1,484 tests, PASS** |
| `pnpm test:integration` (same reset) | 6 files, **81 passed** |
| `pnpm test:e2e --trace off` (CI settings) | **51 passed** |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm lhci` (the CI Lighthouse configuration) | Pass: 2 URLs, 6 runs, all assertions met |
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 17 files, **301 passed** (17 in `tests/unit/postgrest-ready.test.ts`) |
| `tests/unit/postgrest-ready.test.ts` repeated | **140 of 140 passed** (50 sequential, 90 at three in parallel) |

No test was retried, skipped or quarantined. The only assertions changed are the two B-1 assertions in the new unit file (14.8). Not run locally: the dependency audit and gitleaks (CI only).

**Effort (OI-67):** AI session about 4.5 h in total (I-1 about 1.5 h; Amendment 1 and W-1 about 2 h; B-1 about 1 h); Owner review and administrative time not recorded by this session.

## 15. PWP-0 contractual governance reconciliation record (AUTH-011)

**Authorization:** AUTH-011, the Owner's conditional PWP-0 grant as amended on 2026-11-25 (reconstruction objective; 14-file inventory). **Activated 2026-11-25** after independent verification of all seven prerequisites at baseline `d9cf32aec6db3e3ffbc2aa810604ddc094093834` (PR #30 merged at `393e3c8`; PR #31 merged at `d9cf32a`; post-merge CI run 45567129662 (#97): seven jobs executed and passed, full suite). Branch `docs/pwp-0-contractual-reconciliation`; the grant record is its first commit. Documentation only.

**Recorded:** OI-98 to OI-112, DEP-19 (contractual architecture implemented; R1 release-candidate blocker) and DEP-20 (production contractual activation; production gate), with the temporary-to-permanent mapping and the CD, INT, OD and FD cross-reference in 08; revision notes on OI-13, OI-25, OI-34, OI-45 and OI-84; specification amendments in 01, 02, 03, 04, 05, 06 and 07; OWNER-RUNBOOKS §10 and §11; one CLAUDE.md §5 bullet; an appended annotation to the 2026-11-22 sign-off record. Next unused IDs: OI-113, DEP-21, AUTH-012.

**Status, unchanged by PWP-0:**
- **Nothing is implemented.** Every OI-98 to OI-112 requirement is approved direction; the implemented behavior (Owner and Admin free-text scope, snapshot v1, the day 3/7/14/21 schedule and day-21 hold, release preconditions) is unchanged until the separately authorized work packages land.
- **Contractual content:** the original suite is unavailable; SLM-CPS-001 to SLM-CPS-007 are v0.1.0 reconstruction drafts outside Git with no contractual issuance authority; no instrument, provision, entitlement, counsel approval or publication artifact is recorded as existing or verified. The 04 §3.1 clause, its clause-specific approval, canonicalization and equality tests are unchanged.
- **Dependencies:** DEP-03 and DEP-18 stay open; DEP-19 and DEP-20 are not started; TV-01 is incomplete and TV-02 and TV-03 are outstanding (OPEN-ISSUES DEP-06 detail).
- **Authorizations:** AUTH-007 is unchanged; no PWP-1 to PWP-6 authorization exists.

| Work package | R1 | State |
|---|---|---|
| PWP-0 Decision and documentation reconciliation | Required | This PR (AUTH-011) |
| PWP-1 Contractual instruments, bundles, governance events | Required | Not authorized; after WP-D18 merges |
| PWP-2 Standardized issuance and snapshot v2 | Required | Not authorized; after PWP-1 and WP-H |
| PWP-3 Counsel and publication evidence | Required | Not authorized; needs final publication artifacts |
| PWP-4 Non-production materialization and verification | Required | Not authorized; needs PWP-2, PWP-3, AUTH-003 |
| PWP-5 Scope confirmation, operational notes, inactivity reconciliation | Required | Not authorized; after PWP-2 |
| PWP-6 Automated additional-work billing | Post-R1 | Deferred |

**Sequencing:** existing implementation merge order is unchanged (WP-I-1, WP-H, WP-D18). Main's next documentation record follows the PWP-0 merge.

**Owner actions:** review and merge this PR (pinned to its exact head); the repository visibility change (OWNER-RUNBOOKS §11); continue the external contractual reconstruction; separate authorizations for PWP-1 to PWP-5 when ready.

## 16. OI-95 `/sales` empty-state accessibility correction (AUTH-012)

Implemented by the WP-S session on `wp-s/oi-95-empty-state`, from the verified `main` at `b027e4192fe3100d89dec106b7ae7686f82a974a`.

**Entry (confirmed read-only):**
- WP-I-1 merged as PR #28 at `b027e41`. Post-merge CI run 45675171938 (#116) on that exact commit completed `success`.
- AUTH-012 is active: PR #33 at `f37cf7e`, run 45583992649. Its implementation condition, the WP-I-1 merge, is now met.

**Defect, reproduced before the fix:**
- On a freshly reset database, the seeded representative has no customers. The page rendered the empty-state `<p>` inside the `<ul data-testid="sales-customers">`.
- axe reported `list` (1 node). The existing T-SALES-03 scan failed: `[{ id: "list", count: 1 }]`.
- CI passed only because the integration suite runs before e2e and leaves customers behind. That is the order dependence OI-95 records.
- The new test, run alone against the unfixed page, failed the same way.

**Change (files exactly as authorized):**

| File | Change |
|---|---|
| `src/app/sales/page.tsx` | A `<div data-testid="sales-customers">` container in both states. The empty-state message sits outside any list. The `<ul>` (same classes) and its items render only when there are customers. No data, privilege or Sales behavior change. |
| `tests/e2e/wps.spec.ts` | Additive only: 0 lines removed. One new final test, `OI-95: the customer list is accessible when empty and when populated`. |
| This section, and the PR description | The record. |

**The new test:**
- It creates a fresh, isolated Sales Representative for itself, using the same SQL pattern as the integration suite's fresh users (`auth.users`, `profiles`, `staff_roles 'sales'`). Neither state depends on earlier tests or suites.
- It signs in and enrolls MFA.
- **Empty state:** the message is shown, there is no list inside the container, and the WCAG scan has zero violations. The `list` rule was evaluated: it passes on the page because the shell's navigation is a list.
- It then creates one customer through the form, waiting for the project page as T-SALES-04 does, and returns to `/sales`.
- **Populated state:** exactly one list with one item and the project name, no empty-state message, zero violations, and the `list` rule evaluated.
- Existing test IDs and assertions are unchanged. T-SALES-05 and T-SALES-14 still target `sales-customers`, which exists in both states.

**Local results (branch tree, fresh reset, CI order):**

| Check | Result |
|---|---|
| Lint, typecheck, format | Pass |
| Unit | 17 files, **301** |
| `pnpm audit --audit-level=high` | No known vulnerabilities |
| Migration immutability | Pass |
| pgTAP | 27 files, **1484** |
| Integration | 6 files, **81** |
| Build, bundle scan, production build | Pass |
| E2E | **52** (51 plus the new test) |

The WPS project alone, on a fresh reset, gives 27 passed.

**Runs during development, kept for the record:**
- Fresh reset with the new test before the fix: T-SALES-03 failed on `list`, so the new test was skipped under serial mode.
- The new test alone before the fix: failed on `list`.
- The first runs after the fix failed only in the new test itself:
  - It wrongly expected `list` to be inapplicable in the empty state. The navigation list makes it applicable.
  - It navigated before the create action had completed.
  
  Both were corrected in the new test; no existing assertion was touched.
- One run was invalid because the local Docker daemon stopped. It was repeated.

**Effort (OI-67):** AI session about 0.5 h; administrative about 0.1 h (a Docker recovery); Owner: none.

## 17. WP-D18 implementation record (AUTH-007; DEP-18 version sealing)

Implemented by the WP-S session on `wp-d18/scope-sealing`, branched from exactly `58d0e98981befe32f8ddff11c89ce7952dad3a72`. **Verified** on a freshly reset local stack in the CI order; remote CI for the exact head is recorded in the PR.

**Entry checks:**
- AUTH-007 is active (activation record §13).
- `git diff --name-only 58d0e98 origin/main` lists only `.md` files.
- The authorization record's changes after the baseline only mark it active; its boundaries are unchanged.
- The branch was new.
- Migration slot `20261126140000` was unused.

**Changed-object inventory (migration `20261126140000_wpd18_scope_version_sealing.sql` only):**

| Object | Change |
|---|---|
| `private.billing_package_scope_versions` | New. Package key, scope version, item count (1–50), content SHA-256, `is_test_fixture`, sealed at; primary key (package, version). Append-only (`insert_only()`), no truncate (`audit_events_immutable()`), no API grant |
| `private.billing_package_scope_construction_guard()` | New, the one insert-protection trigger function. Attached as BEFORE INSERT to the items and the headers. It accepts a row only while the constructor builds exactly that (package, version) in the current transaction, never into a sealed version, and applies the `development`/`test` allowlist to fixture headers |
| `private.create_package_scope_version(text, text[], boolean)` | New. SECURITY DEFINER, `search_path = ''`, no API-role execute. It takes a per-package advisory lock, assigns the next version, inserts items 1..n, computes the canonical length-prefixed SHA-256, and seals, all in one call; any error rolls back the whole version |
| `private.current_package_scope(text)` | Replaced, same signature. It resolves the newest **sealed** version only, and returns it only if the recomputed item count, positions 1..n, per-item fixture flag and canonical hash all match the seal, and the fixture allowlist admits it. Otherwise it returns nothing, with no fallback to an older version |
| Existing items | Insert protection added. The existing fixture guard, label check and append-only triggers are unchanged |
| `supabase/seed.sql` (WP-S section) | The same labeled fixture items are now created through the constructor (version 1 per package) |

No WP-B (`issue_order_summary` unchanged), WP-C, Phase 2, or API-grant change. No production package content.

**Migration cases (verified):**
- **Fresh run:** nothing to seal; the seed then seals five fixture versions.
- **Existing local database** (reset to `20261125120200` with the old seed, then `supabase migration up`): the fifteen fixture rows are sealed as version 1 per package and resolve, and their hashes are identical to the constructor's for the same content.
- **Non-fixture row present:** the migration raises and changes nothing (row count unchanged, no new table).

**Tests:**
- **pgTAP 310** (173 → 204). The existing statements that wrote scope rows directly now go through the constructor; every expected outcome is unchanged. New assertions:
  - direct item and header inserts are rejected, even for the migration owner
  - no item can be added to a sealed version, even with a forged marker
  - sealed headers cannot be modified, unsealed, deleted or truncated
  - `service_role` and authenticated callers cannot execute the constructor or touch the headers
  - an independent hash recomputation matches every intact seal, and fixture status is consistent between headers and items
  - the historical version reproduces the issued snapshot exactly
  - creations get consecutive versions, a failed construction rolls back the whole version, and an empty version is rejected
  - a half-created (unsealed) version is never resolved
  - a fixture header is rejected under `staging`
  - tampering with an item or a count fails closed, so Sales issuance fails closed
  - every protection trigger is enabled again at the end
- **pgTAP 320** (32 → 37). A real concurrent creation through two `dblink` sessions: the second waits on the per-package lock, then assigns the next free version (no duplicate or gap). Both roll back, so nothing persists. It runs over TCP, as `supabase test db` and CI do.
- **Unit:** two additive WP-D18 checks. Two existing assertions were refined, with Owner approval in session (2026-11-25), because AUTH-007's mandated design made their literal form false:
  - "No migration contains a synthetic or fixture package-scope row": an insert into the scope tables may only copy parameters or existing rows, never a literal. A mutation check confirmed it still fails on an appended literal row.
  - "The seed's fixture rows are all flagged and labeled": the same properties, now checked on the constructor calls, and the seed may write the scope tables no other way.

| Suite (local, fresh reset, CI order) | Result |
|---|---|
| Migration immutability | Pass |
| pgTAP | 27 files, **1520** assertions, all pass (existing 1484 unchanged) |
| Unit | 16 files, **286** tests, all pass |
| Integration | 6 files, **81** tests, all pass |
| Build, bundle scan, production build | Pass |
| E2E | **51** tests, all pass |
| Lint, typecheck, format | Pass |

**Findings and limitations:**
- **`pnpm test:db` can't run the 320 concurrency case.** That runner connects over the container's socket, where `dblink` is refused (a trust-authenticated connection). `supabase test db` and CI connect over TCP and run it.
- **Construction marker and contractual content (corrected under AUTH-007 Amendment 1, item 5; supersedes the earlier wording here):** the construction marker `wpd18.scope_construction` is an unprivileged, transaction-local setting. API roles cannot use it: they hold no table privilege and no execute on the constructor, the guard, or the resolver. It cannot add items to a sealed version, and an unsealed version is never resolved. The database owner, however, can construct a new version (through the constructor, or by setting the marker and inserting directly). That is **not** an authorized content path. Non-fixture contractual content is loaded only through an **Owner-controlled, audited and hash-verified contractual content loading mechanism** (Owner decision FD-05). Authoritative legal text and counsel evidence remain outside Git. That mechanism is not yet designed or authorized (PWP-0, not active, and later separately authorized work), and **no non-fixture content loading is authorized**.
- **DEP-18 remains a mandatory R1 release-candidate blocker:** no production content exists, so Sales issuance stays fail-closed outside the seed.

**Effort (OI-67):** AI session about 0.6 h (2026-11-25, 04:35–05:15 UTC); administrative about 0.05 h (local stack restarts after container and worker recycles); Owner review: one in-session decision on the two assertions.

### 17A. AUTH-007 Amendment 1 correction record (R1-HANDOFFS §2A)

Continued on `wp-d18/scope-sealing` from `6173ffa`, keeping its commits; not rebased. **Activation:** AUTH-007 Amendment 1 is on `main` at merge `393e3c875c2db46efb45811ac4ef2a522a09ed26` (PR #30). Post-merge CI run 45565499637 (#95) on that commit completed `success`. Both were confirmed read-only before starting. AUTH-007 Amendment 2 is **not active**, so item 7 was not executed and `supabase/seed.sql` was not touched. Implementation commit: `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38`.

**Scope executed:** tests and records only. No migration, seed, immutability, API-privilege, workflow, or script change. No existing or rewritten assertion's expected result changed.

| Item | Result |
|---|---|
| 1. Compensating controls (unit) | **Done.** Two new tests in `tests/unit/wps-sales.test.ts`. Outside the exact file name `20261126140000_wpd18_scope_version_sealing.sql`, a migration fails if it names the constructor, uses the construction marker, or carries the fixture label in any form the control recognizes. Recognized label forms are any case, any separators, split by `\|\|`, either half alone, and hex or base64 halves. The one label occurrence allowed elsewhere is the merged label constraint text in `20261125120100`, removed by exact match, and that match is asserted to occur exactly once. Twelve synthetic inputs prove the controls are not vacuous: a clean migration passes, every offending form fails, a similarly named file is not exempt, and an extra label in the constraint migration fails. A real-file mutation check (scratch, not committed) placed a temporary `20270101000000_wpd18_scope_version_sealing_x.sql` containing a constructor call, then a marker use. Each run failed the control and was then removed. Change 1 is unchanged. Its corrected form is presented under D-1 for the Owner's disposition. |
| 2. FD-14 evidence (pgTAP 310, plan 204 → 217) | **Done**, additive. A forged marker on a new, unsealed version (`prestige:60`) is used. An unlabeled fixture item and a labeled unflagged item each fail with 23514, with the exact message naming `billing_package_scope_fixture_label`, and the constraint name is read from the error diagnostics. A fixture item fails with 42501 and the `billing_package_scope_fixture_guard` message under staging, preview, and a missing classification, with the raising function read from the error context. Catalog checks confirm the constraint definition is unchanged and the fixture-guard trigger is `BEFORE INSERT OR UPDATE … FOR EACH ROW` and enabled (`O`). Scratch checks (not committed) confirm the attribution helper is not vacuous: without the marker, or with a sealed version, it reports `billing_package_scope_construction_guard`, and with the forged marker under development a labeled fixture item inserts. They also confirm the rewritten constructor-path statements D-4 to D-8 each reach the intended constraint or guard function. |
| 3. Two-session concurrent-commit test | **Stopped: no disposable state within the authorized inventory.** See the options below. The rollback concurrency test is kept unchanged in substance. |
| 4. Runner handling (pgTAP 320, plan 37 unchanged) | **Done.** The two-session block is a `pg_temp` function. Over TCP (`supabase test db`, CI) it must run: the vacuous `ok(c is not null)` is replaced by a real round trip, in which a second backend answers with its own process id and that id must differ from this one. A connection failure fails all five assertions and is never a skip. This was verified on a scratch copy with a wrong password: `not ok 33` to `37`, "failed 5 tests of 37". Only over a Unix socket (`pnpm test:db`, where `inet_server_addr()` is null) are the five assertions skipped explicitly with the reason, so the other 32 assertions run (verified: `ok 33 # SKIP …` to `ok 37 # SKIP …`). **Limitation:** `pnpm test:db` does not exercise the two-session tests. `scripts/run-db-tests.sh` counts skips as passes and does not print them, and changing that script is outside AUTH-007. |
| 5. Construction marker and contractual-content wording | **Done.** The §17 bullet is corrected, citing FD-05. The PR body is corrected to match. The known residual comments in `supabase/seed.sql` (WP-S section) and the merged `20261125120100` still describe a reviewed-migration content path. They are unchanged here, because no seed change is permitted and merged migrations are never edited. FD-05 prevails. |
| 6. Disposition records | **Done**, below, one record per row (D-1 to D-10). |

**Item 3 options for the Owner's decision (nothing implemented).**

A genuine commit leaves rows in the append-only scope tables. Removing them would need the immutability triggers disabled, which is prohibited, and a committed version on a seeded package would change what later suites resolve. A disposable database copy is not available in the current workflow. `create database … template postgres` was attempted read-only and refused ("source database "postgres" is being accessed by other users", 5 other sessions: PostgREST, auth, storage, pg_net, pg_cron). No probe database was created. `max_prepared_transactions` is 0.

| Option | What it needs | Residual |
|---|---|---|
| (a) Dedicated synthetic package | A new `private.billing_packages` row (a WP-B table) committed by the test, used only by the commit test, with relative version assertions so reruns pass. Also proof that no later suite (integration, e2e) lists or counts packages. | Writes durable synthetic rows to a WP-B table and to the append-only scope tables in the local and CI database. Needs an Owner decision on the WP-B data write. |
| (b) Disposable database in CI | A workflow step (for example after `supabase test db`) that stops the stack's service connections or creates a fresh database from `template0` and replays the migrations, then runs only the commit test there. | Needs a `.github/workflows/ci.yml` or scripts change, outside AUTH-007. |
| (c) Run the commit test last, then reset | A workflow change that runs the commit test after the other suites, or adds a `supabase db reset` after it. | As (b): a workflow change. |
| (d) Keep the current evidence only | Nothing. | The committed-A, B-gets-version-3 path stays untested across two sessions. It rests on the per-package advisory lock and on each statement taking a fresh snapshot under read committed, plus the sequential consecutive-version test (310). |

**Individual assertion disposition records (FD-14).** Line numbers are at `6173ffa` and unchanged at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38`, because the new 310 assertions are inserted after line 768. Evidence common to every record: a fresh local reset in CI order at `1eefdd9` (results in the suite table below), the remote CI run on the exact head (PR #27), and the scratch checks named in items 1 and 2.

**D-1: unit T-SALES-36 migration check (Change 1, `tests/unit/wps-sales.test.ts` 177).**
- *Original:* every migration has zero `insert into private.billing_package_scope…` statements.
- *Replacement:* the regex also covers `_versions`. A migration whose name contains `wpd18_scope_version_sealing` may have inserts, provided none contains a single quote. All others have zero.
- *Original guarantee:* no migration writes scope rows.
- *Replacement guarantee:* no migration writes literal scope content, and only one file (by substring) writes scope rows at all.
- *Exposure:*
  - The substring exemption: a later file named, for example, `…_wpd18_scope_version_sealing_x.sql` passes Change 1 with a non-literal insert. This was shown in a scratch run: all 16 unit tests passed.
  - The quote heuristic misses dollar-quoted or `chr()`-built text.
  - Constructor calls and marker use were not covered.
- *Compensating coverage:*
  - The item 1 controls with their twelve synthetic proofs. They fail constructor or marker use and label forms in any non-exact-named file, including the substring-named one.
  - The runtime construction guard: a direct insert without the marker is rejected (310 "a direct item insert is rejected").
  - Remaining after the controls: a non-literal `insert … select` in a substring-named file, caught only at runtime by the construction guard. Also dollar-quoted or `chr()`-built text inside the exact exempt file, which is merged once and never edited.
- *Proposed correction for disposition (not applied):* replace `if (!file.includes("wpd18_scope_version_sealing"))` with `if (file !== "20261126140000_wpd18_scope_version_sealing.sql")`. In a scratch run it passes on the real migrations (16/16) and fails on the substring-named mutation ("1 failed | 15 passed").
- *Authorization:* individual Owner disposition. Ratification is **withheld as written** (AUTH-007 Amendment 1, FD-14). Applying the correction is an assertion change needing the Owner's decision.
- *Evidence:* unit suite at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38`; the scratch runs above.

**D-2: unit seed fixtures flagged and labeled (Change 2, 199).**
- *Original:* the block from the seed's `insert into private.billing_package_scope` contains the label and `, true\nfrom private.billing_packages`, and comes after `insert into private.environment_settings`.
- *Replacement:* the seed has no direct scope insert. The block from `select private.create_package_scope_version(` contains the label and `], true)\nfrom private.billing_packages`, and comes after the classification.
- *Original guarantee:* seed rows are labeled, flagged, and inserted after the classification.
- *Replacement guarantee:* the same three properties, checked on the constructor call, and no other seed write path.
- *Exposure:* none essential. The check is lexical, like the original.
- *Compensating coverage:*
  - The additive WP-D18 seed test requires exactly three labeled items and the call shape.
  - The database label constraint and fixture guard (310 FD-14 rows).
  - A missing anchor fails, because `indexOf` returns −1.
- *Authorization:* approved in principle (AUTH-007 Amendment 1). Needs an individual Owner disposition. No seed change is made here, and Amendment 2 is not active.
- *Evidence:* unit suite at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38`.

**D-3: 310 A5 setup, essential version 2 (260 to 265).**
- *Original:* a direct insert of `essential` v2 (two labeled fixture items). The existing assertions then check that the issued summary's `scope_items` and `snapshot_sha256` equal the pre-insert values.
- *Replacement:* `select private.create_package_scope_version('essential', array[… item 1, … item 2], true)`, which creates sealed v2. The same assertions follow, with unchanged expectations.
- *Original guarantee:* a later scope version leaves an issued snapshot and its hash unchanged (A5).
- *Replacement guarantee:* the same, with the later version sealed. That is the realistic path, because the direct path is now rejected.
- *Exposure:* none identified. The setup is the only change.
- *Compensating coverage:* WP-D18 "the historical version reproduces the issued snapshot exactly", plus the hash recomputation and re-verification assertions.
- *Authorization:* approved in principle. Needs an individual Owner disposition.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38` (217/217).

**D-4: fixture without the label rejected, 23514 (602).**
- *Original:* a direct insert of `('prestige', 9, 1, 'Unlabeled item', true)` throws 23514.
- *Replacement:* `create_package_scope_version('prestige', array['Unlabeled item'], true)` throws 23514.
- *Original guarantee:* the label constraint rejects a flagged, unlabeled row.
- *Replacement guarantee:* the same constraint, reached through the constructor. The scratch attribution reports `23514 billing_package_scope_fixture_label`.
- *Exposure:*
  - The message is not pinned in the rewritten assertion (a null message, as originally).
  - The direct path now stops at the construction guard, so the original direct path no longer reaches the constraint.
- *Compensating coverage:*
  - Item 2(a): with a forged marker, the direct path reaches the constraint. The exact message and the diagnostic constraint name are asserted.
  - Item 2(d): the constraint definition is unchanged.
- *Authorization:* approved in principle, subject to 2(a) and 2(d), both now present. Needs an individual Owner disposition.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38` ("FD-14 (D-4)" rows); scratch attribution.

**D-5: unflagged labeled row rejected, 23514 (604).**
- *Original:* a direct insert of a labeled row with `false` throws 23514.
- *Replacement:* the constructor with `array['TEST FIXTURE — NOT A DELIVERABLE (unflagged)'], false` throws 23514.
- *Original guarantee:* the reverse direction of the label constraint.
- *Replacement guarantee:* the same constraint through the constructor. The scratch attribution reports `23514 billing_package_scope_fixture_label`.
- *Exposure:* as D-4.
- *Compensating coverage:* item 2(b) and 2(d).
- *Authorization:* approved in principle, subject to 2(b) and 2(d), now present. Needs an individual Owner disposition.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38` ("FD-14 (D-5)" rows); scratch attribution.

**D-6: fixture rejected under staging, 42501 (622).**
- *Original:* under staging, a direct fixture insert throws 42501.
- *Replacement:* under staging, the constructor with a labeled fixture item throws 42501.
- *Original guarantee:* the fixture guard rejects fixtures outside `development`/`test`.
- *Replacement guarantee:* the same guard through the constructor. The constructor's marker matches, so the construction guard admits the item, and the scratch attribution reports `42501 private.billing_package_scope_fixture_guard`.
- *Exposure:*
  - The message is not pinned in the rewritten assertion.
  - The construction guard is a second 42501 source on the path. Its header branch carries the identical message, but it is never reached here, because the item insert fails first.
- *Compensating coverage:*
  - Item 2(c), staging: exact message, plus the raising function read from the error context.
  - Item 2(d): the trigger definition and enabled state.
  - The WP-D18 "a fixture header is rejected under staging".
- *Authorization:* approved in principle, subject to 2(c) and 2(d), now present. Needs an individual Owner disposition.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38` ("FD-14 (D-6)" rows); scratch attribution.

**D-7: fixture rejected under preview, 42501 (632).**
- *Original and replacement:* as D-6, under preview.
- *Guarantees:* as D-6. The scratch attribution reports `42501 private.billing_package_scope_fixture_guard`.
- *Exposure:* as D-6.
- *Compensating coverage:* item 2(c), preview; 2(d).
- *Authorization:* as D-6.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38` ("FD-14 (D-7)" rows).

**D-8: fixture rejected with a missing classification, 42501 (638).**
- *Original and replacement:* as D-6, with no `environment_settings` row (read as production).
- *Guarantees:* as D-6. The scratch attribution reports `42501 private.billing_package_scope_fixture_guard`.
- *Exposure:* as D-6.
- *Compensating coverage:* item 2(c), missing classification; 2(d).
- *Authorization:* as D-6.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38` ("FD-14 (D-8)" rows).

**D-9: non-fixture setup, signature (646 to 647).**
- *Original:* a direct insert of `('signature', 7, 1, 'PGTAP SYNTHETIC NON-FIXTURE ROW (rolled back)', false)`. Then `scope_rows('signature') = 1` with a missing classification.
- *Replacement:* `create_package_scope_version('signature', array['PGTAP SYNTHETIC NON-FIXTURE ROW (rolled back)'], false)` creates sealed v2. The same assertion follows, with the same expectation.
- *Original guarantee:* a non-fixture row resolves under any classification (the allowlist affects fixtures only).
- *Replacement guarantee:* the same, through the sealed, re-verified resolver.
- *Exposure:* none identified. The row is synthetic and rolled back with the transaction.
- *Compensating coverage:* the WP-D18 re-verification assertions (hash, count, fixture consistency).
- *Authorization:* approved in principle. Needs an individual Owner disposition.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38`.

**D-10: fixture inserts under `test`, `lives_ok` (652).**
- *Original:* under `test`, a direct fixture insert lives.
- *Replacement:* under `test`, the constructor with a labeled fixture item lives.
- *Original guarantee:* the allowlist admits fixtures under `test`.
- *Replacement guarantee:* the same, through the constructor. The direct insertion is now intentionally rejected.
- *Exposure:* none identified.
- *Compensating coverage:* the WP-D18 direct-insert rejection assertions, and the following `scope_rows('prestige') = 1` under development (the newest fixture version resolves).
- *Authorization:* approved in principle. Needs an individual Owner disposition.
- *Evidence:* 310 at `1eefdd96fb1edd093ad8fdec5c57ea7196c93e38`.

**Findings for Main (no ID allocated; only Main allocates):**
1. R1-HANDOFFS §2A item 2 cites "H-1", but no H-1 record exists on `main` (08, AUTHORIZATIONS, CURRENT-STATE and OPEN-ISSUES were searched). The item's own text was followed.
2. Item 1 asks for no fixture label "in every migration other than" the sealing migration. The merged `20261125120100` necessarily contains it once, in the label constraint, and can never be edited. The controls exempt exactly that constraint text, asserted to match exactly once. Any other occurrence fails.
3. Item 3 is stopped (options above).

**Suites at `1eefdd9`** (local, fresh reset, CI order; the working tree was identical to `1eefdd9` for the test files):

| Suite | Result |
|---|---|
| Lint, typecheck, format | Pass |
| Unit | 16 files, **288** pass (286 + 2 new) |
| Migration immutability | Pass |
| pgTAP (`supabase test db`, TCP) | 27 files, **1533** pass (1520 + 13 new in 310). The 320 two-session block ran: 5 of 5 |
| pgTAP (`pnpm test:db`, socket; after a fresh reset) | 27 files, 1533 planned, 0 failed; the 320 two-session block is 5 explicit skips |
| Integration | 6 files, **81** pass |
| Build, bundle scan, production build | Pass |
| E2E | **51** pass |

`pnpm test:db` must start from a fresh reset. Run after the integration and e2e suites, it reports failures in 13 files, because those suites leave data behind. This is pre-existing behavior of those files, not part of this change. The remote CI result on the exact head is recorded in PR #27.

**Effort (OI-67), Amendment 1 continuation:** AI session about 0.5 h (2026-11-25, 07:10–07:40 UTC); administrative about 0.05 h (local stack restart); Owner review: the individual D-1 to D-10 dispositions and the item 3 decision are pending.

### 17B. AUTH-007 Amendment 2: seed comment-only correction (item 7)

**Activation evidence (confirmed read-only before the change):**
- PR #31 merged into `main` at `d9cf32aec6db3e3ffbc2aa810604ddc094093834`.
- Post-merge CI run 45567129662 (#97) on that exact commit completed `success`.
- The AUTHORIZATIONS row still reads "activation pending"; Main corrects that record separately.

**Change.** The change is in `supabase/seed.sql`, WP-S section, comment lines only.
- Removed: "…These are NOT deliverables: the production scope content is / supplied by the Owner (DEP-18) through a reviewed migration."
- Added: "…These are NOT deliverables. Non-fixture contractual content is loaded only through an Owner-controlled, audited and hash-verified contractual content loading mechanism (FD-05). No migration is an authorized content path. Legal text and counsel evidence remain outside Git. No loading is authorized."

No executable SQL, seed data, constructor call, fixture content, or environment behavior changed. Commit: `5ebd664`.

| Required evidence | Method and result |
|---|---|
| SQL without comments identical | A PostgreSQL-aware lexer (session scratch tool, not committed) removes `--` and nested `/* */` comments and collapses whitespace outside literals. It copies byte for byte every single-quoted string (with `''`), `E''` string (with backslash escapes), quoted identifier, and dollar-quoted body (`$$`, `$tag$`), so comment-like text inside them is never discarded. Self-tests (9 of 9) cover: `--` inside a string, an `E''` string, a quoted identifier and dollar quotes; nested block comments; positional `$1` versus dollar quotes; `1 - -1`; and detection of a changed literal and of an added statement. Result: executable SHA-256 `8b3f1d342a91f7789b6d1eb2761107ecbf73c707d47cb3dd59e3f6eb9e3f3aa3` before (the committed `bbf9b05` file, confirmed with `cmp`) and after, **identical**. Comments: 18 before, 20 after. The only comments that differ are the two removed and the four added lines above. |
| Diff changes only the authorized lines | `git diff -U0 supabase/seed.sql`: one hunk at line 75, `-2 +4`. Every changed line (both sides) begins with `--`; count of changed lines not starting with `--`: 0. |
| Reset package-scope state identical | `supabase db reset` before and after, then the same query of every header (key, version, item count, content hash, fixture flag), every item (key, version, position, flag, item-text SHA-256, text), the resolved scope of every package (version, count, digest), and the totals and classification. Result: 26 rows, byte-identical (output SHA-256 `58f3a4308d3b4131c3f4848c5cadb515017581e89d5fb0e7bbc4a13be589200d` both times): 5 packages, 5 headers, 15 items, all version 1 with 3 items, fixtures `t`, classification `development`. |
| Full suites unchanged and passing | See the suite table below. |
| Exact-head CI 7/7 | Recorded in PR #27. |

**Suites at `5ebd664`** (local, fresh reset, CI order): lint, typecheck, format pass; unit **288** pass; migration immutability pass; pgTAP (`supabase test db`) 27 files, **1533** pass; integration **81** pass; build, bundle scan, production build pass; e2e **51** pass. These counts are identical to `1eefdd9`.

**Effort (OI-67), Amendment 2:** AI session about 0.2 h (2026-11-25, 07:33–07:45 UTC); administrative: none; Owner: none.

### 17C. AUTH-007 Amendment 3: isolated concurrent-commit verification and D-1 correction (R1-HANDOFFS §2B)

**Activation (confirmed read-only before starting):**
- PR #33 merged into `main` at `f37cf7ecf13c7f25e37477684731a2e7d11e0943`.
- Post-merge CI run 45583992649 (#103) on that exact commit completed `success`.
- Work continues on `wp-d18/scope-sealing` from `9f9a5ca`, keeping its commits; not rebased.
- Implementation commit: `d2077d2`.

**Owner dispositions (FD-14, OI-105; Amendment 3):**
- **D-2 to D-10 are individually approved.** Their records are in §17A, written at `bbf9b05` with evidence at `1eefdd9`; the line numbers were taken at `6173ffa`. CI evidence for that state: `9f9a5ca`, run 45569788777, 7/7.
- **D-1 (Change 1) is not ratified as written.** The exact-filename correction is implemented below. Final ratification needs independent review of the corrected check, of the mutation evidence below, and of the stricter rule, which is held (see below).

**Files:**

| File | Status |
|---|---|
| F1 `scripts/wpd18-isolated-commit-test.sh` | **Done (new).** Builds `wpd18_iso_<run>_<pid>` from `template0`, refusing an existing name. Takes a read-only `pg_dump -Fc -n private` of the source and selects the 37 allow-listed entries: a missing, duplicate or extra entry, or a total other than 37, fails. Restores with `pg_restore --exit-on-error --single-transaction -L` (zero tolerated errors). A structural check refuses `--no-privileges`, `--no-acl`, `-x`, `--no-owner` and `-O` in the dump and restore commands. Requires parity, runs F4 over TCP, checks its TAP output, and verifies the source is unchanged. Drops the database in a trap on exit, error, interrupt and timeout, and asserts it is gone. The whole run is wrapped in `timeout 240`. |
| F2 `supabase/tests-isolated/wpd18-restore-allowlist.txt` | **Done (new).** Exactly 37 descriptors (dump IDs removed): the dependency closure of the scope objects. That is 4 tables (`billing_packages`, `billing_package_scope`, `billing_package_scope_versions`, `environment_settings`), their data, 4 primary keys, 2 foreign keys and 7 triggers, plus 7 functions (`create_package_scope_version`, `current_package_scope`, the construction guard, the fixture guard, `app_environment`, `insert_only`, `audit_events_immutable`) with their ACLs, and the `private` schema with its ACL. None of these references `public`, `auth`, `storage` or `vault`; the only external dependency is `extensions.digest` (`pgcrypto`). |
| F3 `supabase/tests-isolated/wpd18_parity.sql` | **Done (new).** Read-only. Section `fp` is the 67-line catalog fingerprint, with ACLs normalized by `acldefault()`. It covers the schema, 4 tables, 20 columns, 19 constraints, 4 indexes, 7 triggers with their enabled state, and 7 functions (owner, SECURITY DEFINER, `search_path`, ACL, definition MD5). It also records effective privileges for `anon`, `authenticated`, `service_role` and `public`, and the classification. Section `state` holds headers, items (text SHA-256), resolved scope and totals. The `fp` section is byte-identical to the fingerprint reviewed in scratch. |
| F4 `supabase/tests-isolated/wpd18_commit_race.test.sql` | **Done (new).** TAP, `1..25`. It refuses to run outside a `wpd18_iso_*` database or without TCP. See the assertions below. |
| F5 `.github/workflows/ci.yml` (one step) | **Not yet: by sequencing.** It lands only when PR #27 is brought up to date after WP-I-1 and WP-H merge (Amendment 3). Until then CI does not run F1; the evidence below is local. |
| F6 `tests/unit/wps-sales.test.ts` | **Partly done.** The D-1 exact-filename correction is implemented as one helper (`scopeInsertViolations`), used for the real migrations and for the synthetic inputs, with the mutation test. **Held:** the stricter lexical rule (conflict below). **With F5:** the check that the F5 step is present and unconditional. |
| F7 this record and the PR #27 description | **Done.** |

**F4 assertions:**
1. 1–4: every API role lacks execute on the constructor and resolver and every table privilege on both tables.
2. 5: all 7 triggers are enabled.
3. 6: real second and third backends answer.
4. 7–9: while A holds version 2 uncommitted, an independent session sees 0 headers and 0 items for it and still resolves version 1 (3 items).
5. 10–11: B waits. A bounded poll (at most 100 checks, 50 ms apart) finds B's ungranted advisory lock in `pg_locks`, and `dblink_is_busy` = 1.
6. 12–13: A built version 2. After A commits, B builds and commits version 3.
7. 14–17:
   - headers are exactly `1:3, 2:1, 3:2` (version:items), all fixtures
   - positions run 1..n with item counts equal to the headers
   - every hash equals an independent canonical recomputation
   - the resolver returns version 3, positions 1 and 2, with the exact texts
8. 18–23: each of these is rejected with 42501:
   - a forged-marker addition to version 2 ("sealed")
   - a header update or delete
   - truncating the headers
   - an item update

   All 7 triggers are still enabled afterwards.
9. 24–25: A holds and never commits; B fails with `55P03` (lock timeout) within 5 s. A's version rolls back when its session ends.

Every session sets `statement_timeout` (20 s) and `lock_timeout` (15 s); the coordinator's limit is 60 s.

**Conflict, escalated to Main and the Owner; not resolved here, and no ID allocated.**
- The recorded stricter rule says: outside `20261125120100` and the exact `20261126140000`, a migration that names `billing_package_scope` in any form fails.
- The **merged** `20261125120200_wps_oi85_separation.sql` names the table at lines 109–113 (the C5 append-only and no-truncate triggers). Merged migrations are never edited, so the rule as recorded would fail CI.
- The WP-S proposal (§6.4) made the same omission.
- Options:
  - (a) Add `20261125120200_wps_oi85_separation.sql` to the exact-name exemptions (recommended).
  - (b) Apply the rule only to migrations after `20261126140000`.
- The stricter rule is held until a decision is recorded. The runtime construction guard remains the enforcing control.

**Evidence at `d2077d2` (local stack; F1 is not yet in CI):**

| Check | Result |
|---|---|
| `./scripts/wpd18-isolated-commit-test.sh`, fresh reset | PASS 25/25: 37 of 683 dump entries selected, restore with no errors, 67 fingerprint lines and 26 state lines identical, source identical before and after, about 8 s, the disposable database dropped and its absence verified |
| The same, after the full suite (post-e2e database) | PASS 25/25, cleanup verified |
| Negative cases (scratch mutations of the working files, restored after each and compared with `cmp` against a baseline copy) | Each exits 1 and leaves no `wpd18_iso_*` database:<br>• allow-list with an entry missing: "36 entries, expected 37"<br>• unknown entry: "matched 0 dump entries"<br>• duplicate entry: "duplicate entries"<br>• replaced entry: "matched 0"<br>• wrong race expectation: `not ok 13`<br>• injected `# SKIP` line: TAP check fails<br>• `--no-privileges` or `--no-owner` in the dump command: refused before anything is created<br>• conflicting object before the restore: `pg_restore` aborts ("schema "private" already exists"), cleanup runs<br>• TERM during the race: cleanup drops the database |
| Shared database after all the runs | Package-scope state byte-identical to the seeded state |
| D-1 mutation, synthetic (unit) | The exact `20261126140000_wpd18_scope_version_sealing.sql` passes. `…_wpd18_scope_version_sealing_v2.sql`, `…_x_wpd18_scope_version_sealing.sql` and `…sealing.sql.bak` each fail (`insert-outside-sealing-migration`). An insert into `_versions` in another migration fails. A literal fails even in the exact file. A clean migration passes. |
| D-1 mutation, real file (scratch) | A temporary `supabase/migrations/20270101000000_wpd18_scope_version_sealing_v2.sql` containing `insert into private.billing_package_scope select * from private.staging_rows;` fails the T-SALES-36 check ("1 failed \| 16 passed"); after removal, 17/17 pass. The former substring exemption let the same file pass (scratch, 16/16). |
| Full suites, CI order | Lint, typecheck, format pass. Unit 289 (288 + 1). Migration immutability pass. pgTAP 27 files, 1533. Integration 81. Build, bundle scan, production build pass. E2E 51. |

**D-1 lexical limitations (measured):** the Change 1 pattern recognizes only `insert into private.billing_package_scope…`. It does not recognize:
- quoted identifiers
- whitespace around the dot
- an unqualified name under `search_path`
- `COPY`
- `MERGE`
- dynamic SQL
- a comment between `insert` and `into`
- dollar-quoted or `chr()`-built text inside the exact exempt file

All of these are rejected at runtime by `billing_package_scope_construction_guard`, which fires BEFORE INSERT for INSERT, COPY and MERGE, unless the construction marker is set; marker use is a separate lexical control. The held stricter rule would close the quoted, spaced, COPY, MERGE and comment forms.

**Scratch evidence carried into this record:**
- The full-clone probes: `--no-privileges` widened privileges, and the clone without that flag had 74 restore errors.
- The scoped design probe: zero errors, parity, the race, the 55P03 case, cleanup.
- The F1 baseline and negative-case outputs.
- The Amendment 2 seed evidence.

It is in the WP-S session scratchpad (41 files; `MANIFEST.sha256` SHA-256 `f150b8316909008475804a98bc3eff84f0236c75e6f6f42bd60993f0c68c9e88`).

Selected entries:

| File | SHA-256 |
|---|---|
| `commit_race_probe.sql` | `f3be881b523ee30ab817920ee3b38b9ede5753be83f55922dc89b3ef0ecd89d3` |
| `probe-results-2026-11-25.md` | `46580faaf20c1e9972fb45ace1fe0855bc4f08943b9d0425750fc55d712f5479` |
| `restore-design/allow.list` | `be187367564800dc7a1dcc93c9d9609b518adf0106ae8ed2275cbdf58b8ff6f1` |
| `restore-design/commit_race_iso.out` | `0dd99c19d590cccaaf6b23cbcfccc3f4603d6f48627219f41aaffc68b17fb265` |
| `restore-design/commit_race_iso.sql` | `55b245fe79d791df71f3b8723c22f222196fef1d443363fb144a34b786baed4c` |
| `restore-design/parity.sql` | `213a801ac92acc6a732a65d18387447af11016b223f6bfa97c511f50a84989eb` |
| `restore-design/timeout_probe.out` | `525aa7a3458a65380b0923e4c3f18ee5ed2344db18aff54aa88ed5e52c7bf6c0` |
| `restore-design/timeout_probe.sql` | `f6b178208a2dc47e96482053669cb797c430b87139d7b3a5230f89ba3da5474d` |
| `state.before.txt` | `58f3a4308d3b4131c3f4848c5cadb515017581e89d5fb0e7bbc4a13be589200d` |
| `tools/sqlstrip.py` | `3006ad0205ec3ef0b8d35b61e00471e9addd07ea2c237cb08bfe05b6e314ac2a` |
| `wpd18-amendment3-proposal.md` | `d7334df0104fd6d8384544911269aa26bfe99b298b8b6a691d3bede11574cef4` |

**Effort (OI-67), Amendment 3:** AI session about 1.2 h (2026-11-25, design probes and implementation); administrative about 0.1 h (two Docker daemon recoveries after container recycles); Owner: dispositions D-2 to D-10, Option A, and the D-1 direction.

**Amendment 3 correction: the stricter lexical rule (option (a)).**
- **Activation, confirmed read-only before applying the held patch:** PR #34 merged at `a5dfad0ccdef3aa669588c49976fb784d43bfbbc` (parents `f37cf7e` and `951d7dd`). Post-merge CI run 45665855580 (#112) on that exact commit completed `success`.
- **Exemption list (exhaustive):** exactly `20261125120100_wps_sales_representative.sql`, `20261125120200_wps_oi85_separation.sql` and `20261126140000_wpd18_scope_version_sealing.sql`, as recorded. There is no timestamp, directory, wildcard or substring exemption. The SHA-256 of `20261125120200` equals the recorded `67c8851fabbac621b421dcb995111cc367e914179d580cde15b4358ebbb9fe8c`.
- **Implementation:** commit `1508ede`, `tests/unit/wps-sales.test.ts` only.
  - Comments are removed with a quote-aware lexer, so string, E-string, dollar-quoted and quoted-identifier contents are kept.
  - Identifier quotes are dropped and whitespace around dots is collapsed.
  - Any remaining `billing_package_scope` in a non-exempt migration fails.
  - A non-vacuity check requires each exempt file to be present and to name the table.
- **Mutation evidence:**
  - **Synthetic inputs that fail:** quoted identifiers, spaced dots, an unqualified name under `search_path`, `COPY`, `MERGE`, a dynamic-SQL name in a string, a comment between `insert` and `into`, upper case, and trigger DDL.
  - **Synthetic inputs that pass:** names in comments only, nested comments, and an unrelated `billing_packages_audit`.
  - **Exemption is by exact name:** `20270101000000_wps_oi85_separation.sql` fails, while `20261125120200_wps_oi85_separation.sql` passes.
  - **Disclosed exposure:** a name assembled from string fragments is not recognized, and that is asserted. The runtime construction guard remains the enforcing control.
  - **Real temporary files (scratch, removed):**
    - a quoted-identifier insert fails ("1 failed | 18 passed")
    - `COPY` fails ("1 failed | 18 passed")
    - a plain insert fails both checks ("2 failed | 17 passed")
    - a similarly named `…_wpd18_scope_version_sealing_v2.sql` fails both checks
    - after removal, 19/19 pass
  - **Rule as originally recorded (scratch):** without the `20261125120200` exemption it fails on that merged file ("2 failed | 17 passed").
- **Local results at `1508ede`:**
  - lint, typecheck and format pass
  - unit: 16 files, **291** (289 + 2)
  - pgTAP: 27 files, **1533**
  - `./scripts/wpd18-isolated-commit-test.sh`: **PASS 25/25**, cleanup verified
  - integration and e2e were not run locally for this test-only change; they run in the exact-head CI below
- **Docker during this run:** the local Docker daemon stopped once. With the database unreachable, F1 reported the disposable database's absence as unverified and failed. That is the intended fail-closed behavior. After the restart, no `wpd18_iso_*` database existed.
- **D-1 remains unratified.** Ratification is a separate Owner disposition after independent review.
- **Still sequenced:** F5 and its F6 presence check, at the rebase after WP-I-1 and WP-H.

### 17D. Synchronization after the WP-H merge, F5, and the F6 presence check

**Baseline:**
- WP-H merged as PR #35 at `30414c78b80594a735c8031a3a285a3e88d8f6cb` (parents `e3a7508` and `85ec6ce`). Post-merge CI run 45689577718 (#123) on that exact commit completed `success`.
- Both conditions for the synchronization and for F5 are met: WP-I-1 merged at `b027e41`, and WP-H merged at `30414c7`.

**Synchronization:**
- `main` was merged into `wp-d18/scope-sealing` as merge `73efddd` (parents `3226771` and `30414c7`). There was no rebase, and every reviewed commit is kept.
- One conflict, in `docs/CURRENT-STATE.md`. It was resolved by taking `main`'s file as it is, which keeps §10.2 (WP-H), §14 (WP-I-1), §15 and §16 (OI-95), and by moving the WP-D18 record from §14 to the next free section, §17 (§17A to §17C). Only the numbering changed; this was checked with a line diff.
- The header version is allocated from the baseline: `main` is 1.24.0, so this is 1.25.0.
- **Net diff against `30414c7`:** exactly the WP-D18 files (the migration, seed, pgTAP 310 and 320, F1 to F4, the unit file and CURRENT-STATE) plus the F5 workflow step. Nothing else.

**F5 (commit `da4ca60`):**
- Exactly one new step in "Database, integration, and e2e tests (local Supabase)": `WP-D18 isolated concurrent-commit verification`, `run: ./scripts/wpd18-isolated-commit-test.sh`, `timeout-minutes: 5`.
- It sits after "Database tests (pgTAP)" and before "Integration tests", with no `continue-on-error` and no `if:`. There is no other workflow change.

**F6 presence check (same commit):**
- `f5Violations` parses the steps of the workflow text without a new dependency. It requires:
  - exactly one step that runs the script, with exactly the recorded three lines
  - no `continue-on-error` and no `if:`
  - immediate adjacency to the pgTAP step before it and the integration step after it
  - the same job as the pgTAP step
  - an executable script
- **Synthetic mutations that each fail it:** step removed, `continue-on-error` added, `if:` added, a different command, moved after integration, duplicated.
- **Real-file mutation:** a temporary `continue-on-error: true` in `ci.yml` failed the check ("1 failed | 20 passed"). After restoring the file, 21/21 pass.

**Local results at `da4ca60` (fresh reset, CI order, with F1 at its CI position):**

| Check | Result |
|---|---|
| Lint, typecheck, format | Pass |
| Unit | 17 files, **312** (303 on `main` plus 9 WP-D18 tests) |
| `pnpm audit` | Clean |
| Migration immutability | Pass |
| pgTAP | 30 files, **1654** (1605 plus 49 WP-D18 assertions) |
| F1 | **PASS 25/25**: 37 of 693 dump entries, 67 fingerprint lines and 26 state lines identical, source unchanged, cleanup verified |
| Integration | 7 files, **96** |
| Build, bundle scan, production build | Pass |
| E2E | **52** |

One earlier local run was invalid because the local Docker daemon stopped. It was repeated in full.

**D-1** remains unratified; ratification is requested separately with this evidence. **Effort:** AI session about 0.4 h; administrative about 0.1 h (a Docker recovery).
