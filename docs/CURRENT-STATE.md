# Current State

| Field | Value |
|---|---|
| Version | 1.10.0 |
| Status | **Canonical status record** (OI-67). Every pull request that changes status updates this file in the same pull request. |
| Last updated | 2026-11-25, by the WP-S branch authorization record (AUTH-005 granted and active), based on `main` at `005cc36` |

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
| WP-B | Agreements, payments, webhooks, ledger, reconciliation (R1 scope), including OI-74, OI-75, OI-81, OI-82, OI-83, and B1 | **Done** (PR #20, merge commit `8ac8143`; post-merge CI run #66 `success`). **N1 is a mandatory blocker for R1 release-candidate acceptance** (04 §15.2.1 rule 9; §7). Implementation record in §10. |
| WP-C | Intake, uploads, approvals, publication authorization, admin queue (R1 scope) | **Done** (PR #19, merge commit `bcddb1f`; post-merge CI run #63 `success`). Review findings H1, M1, M2 closed. |
| WP-S | Sales Representative authorization infrastructure (03 §4.1; OI-77, OI-78, OI-84) | **Authorized; implementation not started.** AUTH-005 granted and active 2026-11-25 (§9 activation record); branch `wp-s/sales-representative` from `005cc36`. |
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
| 03 Security, auth, tenancy | 0.5.8 (OI-77, OI-78, OI-79, OI-83, OI-84; client guard for WP-S) | Approved (03A is supporting evidence) |
| 04 Agreement and billing | 0.9.6 (OI-74, OI-81, OI-82, OI-84; F3–F6; B1; N1) | Approved for implementation and test mode. **Not approved for production:** legal review (DEP-03) and provider verification (DEP-06) remain conditions. |
| 05 Lifecycle and uploads | 0.4.5 (OI-74, OI-79; §5.5 rules 1–9) | Approved |
| 06 Publishing and post-launch | 0.5.2 (OI-79 item 5; G7 clarification; B1 note) | Approved |
| 07 Notifications, privacy, design | 0.4.0 | Approved. Retention periods remain provisional (DEP-05). |
| 08 Decisions and changelog | 0.22.0 | Approved. The provenance caveat in 08 §1 still applies to transcribed decisions. |
| AUTHORIZATIONS, CURRENT-STATE | 1.8.0 (AUTH-002 and AUTH-003 inactive; **AUTH-005 granted and active**, 2026-11-25), 1.10.0 | Approved |
| OWNER-RUNBOOKS | 0.1.0 | **[PROPOSED]** Owner review |
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
| `main` at `0b289f3` (PR #21 merge, documentation only; parents `8ac8143`, `7ba7cb3`; tree identical to the reviewed head). Post-merge CI run #70 (id 45511277460): all 7 jobs `success`, including the full suite. Previously `main` at `8ac8143` (PR #20 merge; parents `bcddb1f`, `aa7a20a`; tree identical to the reviewed head). Post-merge CI run #66 (id 45506039608): all 7 jobs `success`, including migrations applied from scratch (T-MIG-01), pgTAP, integration, and e2e. Earlier: `bcddb1f` (PR #19) run #63 `success`; `77a887b` (PR #18) run #59 `success` | **Verified** via the GitHub API, 2026-11-24 |
| `main` at `19b68cb` (PR #17 merge; parents `3f3b59d`, `33c082b`; tree identical to the reviewed head). Post-merge CI run #43 (id 45322697836): all 7 jobs `success`, including `CI result` | **Verified** via the GitHub API, 2026-11-24 |
| The `spotlight-client-portal-dev` environment: Limited network; allowlist `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; no network secrets; no environment variables | **Verified** via the environment API, 2026-11-24 |
| The Stripe sandbox catalog exists as specified | **Verified** by run `dep01-20261123T220040Z-290aebd0` (04 §6.5) |
| The restricted Stripe keys used for DEP-01 are revoked; no restricted keys remain in live mode; `chris-pribyl` and `spotlight-client-portal-dev` hold no network secrets or environment variables; `api.stripe.com` is not on the `spotlight-client-portal-dev` allowlist | **Owner-reported**, 2026-11-24 |
| The `spotlight-client-portal-dev` allowlist is `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; network access is Limited | **Owner-reported**, 2026-11-24 |
| CI post-merge run #35 on `e7c8d47` concluded `success` | **Verified** via the GitHub API |

## 6. Pending Owner actions

1. Review the WP-S pull request when it is ready (WP-B and Main reviews first); only the Owner merges it. PR #21 and PR #22 are merged; AUTH-005 is granted and active.
2. (Done 2026-11-25) AUTH-005 granted.
2a. Supply the standard scope for each package (DEP-18) and include it in counsel review (DEP-03).
3. Review OWNER-RUNBOOKS (proposed).
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
| **R1 release-candidate blockers (mandatory before R1 acceptance)** | **N1** (04 §15.2.1 rule 9): (a) safe project attribution of deferred refund and dispute events (WP-B follow-up); (b) Owner runs reconciliation before publication (OWNER-RUNBOOKS §5) until DEP-17; (c) the multi-payment linking criterion passes in test mode (AUTH-002). Also: F7 and F8 test-mode criteria (04 §8.2, DEP-06, DEP-15); the integrated R1 browser suite T-E2E-01 to T-E2E-10 (integration stream); DEP-07, DEP-12, DEP-17; DEP-18 package scope content (OI-84(b)); DEP-03 wording, never presented as legally approved until approved (F10) |
| **F2** (integration stream; root cause unconfirmed) | Before the T-E2E work: replace the WP-C integration fixture that swaps `private.project_financial_status` by global DDL with real WP-B records; make WP-C assertions report PostgREST `error`; wait for the schema-cache reload after any test DDL |
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
| Integration (primary session) | Merge order and reviews for WP-S; F2 (§7); then the integrated R1 browser and security suite T-E2E-01 to T-E2E-10 and the T-SALES set; track the R1 release-candidate blockers (§7) | §7, §9; 01 §9.1, §9.1.1 | AUTH-000; AUTH-001 for cross-package tests |
| WP-S (`wp-s/sales-representative`, integration stream) | Implement the **WP-S directive** below; entry recorded (activation record) | 03 §3, §4, §4.1, §13; 04 §4; 08 OI-77, OI-78, OI-84; AUTHORIZATIONS AUTH-005 | **AUTH-005 (granted, active)** |
| WP-B follow-up | N1(a) safe attribution of deferred reversal events, as a small PR before the R1 release candidate | 04 §15.2.1 rules 8–9 | AUTH-001 |

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
