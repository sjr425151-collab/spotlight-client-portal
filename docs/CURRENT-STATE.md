# Current State

| Field | Value |
|---|---|
| Version | 1.4.0 |
| Status | **Canonical status record** (OI-67). Every pull request that changes status updates this file in the same pull request. |
| Last updated | 2026-11-24, by the OI-74 documentation PR (mandatory payment method retention; OI-73 opened), based on `main` at `19b68cb` |

This file replaces the status tables that were previously repeated in CLAUDE.md §1, README, 01 §8, 08 §4, OPEN-ISSUES headers, and 04 §6. Those places now link here. **What is authorized** is in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). **What was decided** is in [08](08-DECISIONS-AND-CHANGELOG.md). Detailed dependency records are in [OPEN-ISSUES.md](../OPEN-ISSUES.md).

Evidence labels: **Verified** (checked from repository or provider evidence, with the source named) · **Owner-reported** (stated by the Owner, not independently checked).

## 1. Authorization summary

| Item | State |
|---|---|
| Architecture | Approved |
| Specifications | All approved, with scope limits in §3 |
| Active authorizations | AUTH-000 (Tier 0, standing); **AUTH-001** (Tier 1: WP-A, WP-0, WP-B and WP-C on local and CI); **AUTH-004** (scoped Tier 2: WP-C storage policies, local and CI) |
| Granted, not yet active | **AUTH-002** (Stripe sandbox), **AUTH-003** (hosted non-production). Activation conditions are in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). |
| Production launch | **Not authorized.** No real client payment may be accepted until production launch authorization (Tier 3) is granted. |
| Deployments | None. Nothing is deployed. |

## 2. Releases and work packages (OI-67, OI-68)

| Item | Scope | State |
|---|---|---|
| Phase 1, Foundation and CI | Tooling, CI, design tokens | **Done** (PR #2) |
| Phase 2, Auth, security, tenancy | Invitation-only OTP, MFA, RLS, audit, nonce CSP, private storage policies | **Done, local only** (PR #4) |
| WP-A | Governance and specification correction | **Done** (PR #14, merge commit `d6d795a`) |
| WP-0 | Shared contracts: domain-event and outbox tables, state-domain types, audit action names, gate-function interfaces | **Done** (PR #15, merge commit `60954d4`; post-merge CI run #39 on `main` concluded `success`, 2026-11-24). OI-71 and OI-72 decided. Integration closed by the integration closure PR. |
| WP-B | Agreements, payments, webhooks, ledger, reconciliation (R1 scope), including **OI-74** (payment authorization, card-only, automatic final charge, setup-mode recovery, revocation; 04 §8.1) | **Ready to start** (§8). Local, mocked, and synthetic-event work under AUTH-001; Stripe sandbox parts need AUTH-002 active. |
| WP-C | Intake, uploads, approvals, publication authorization, admin queue (R1 scope); intake also requires `payment_authorization_ready` (OI-74, 05 §3) | **Ready to start** (§8). AUTH-001, plus AUTH-004 for storage policies; real scanned-file release needs DEP-07. |
| WP-D | Hosted non-production infrastructure, then production readiness | Not started. Needs AUTH-003 active. Production steps are Tier 3. |
| WP-E | Legal, tax, and commercial approvals | Owner. Not started (DEP-03, DEP-04, DEP-05). |
| **R1** release candidate | Complete controlled transaction (01 §9.1) | Not started |
| **R2** release candidate | Fulfillment automation (01 §9.2) | Not started |

Former phases 3–5 map onto these work packages (01 §7). Phase numbers are no longer used for authorization.

## 3. Specifications

| Spec | Version | State |
|---|---|---|
| 01 Project overview | 0.4.1 | Approved (v0.4.1 OI-74 amendment in the OI-74 documentation PR) |
| 02 Architecture and environments | 0.4.0 | Approved |
| 03 Security, auth, tenancy | 0.4.5 | Approved (03A is supporting evidence) |
| 04 Agreement and billing | 0.9.0 (OI-74) | Approved for implementation and test mode. **Not approved for production:** legal review (DEP-03) and provider verification (DEP-06) remain conditions. |
| 05 Lifecycle and uploads | 0.4.2 | Approved (v0.4.2 OI-74 amendment) |
| 06 Publishing and post-launch | 0.5.0 | Approved |
| 07 Notifications, privacy, design | 0.4.0 | Approved. Retention periods remain provisional (DEP-05). |
| 08 Decisions and changelog | 0.16.0 | Approved. The provenance caveat in 08 §1 still applies to transcribed decisions. |
| AUTHORIZATIONS, CURRENT-STATE | 1.1.0, 1.4.0 | Approved |
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

## 5. Verified facts

| Fact | Evidence |
|---|---|
| `main` is protected by ruleset `protect-main`: pull request required (0 approvals), force pushes and deletions blocked, and 5 required status checks with "require branches to be up to date": Lint, types, format, unit tests; Lighthouse budgets; Dependency audit; Secret scan; Database, integration, and e2e tests | **Verified** 2026-11-24 via the GitHub API (`/repos/…/rules/branches/main`) |
| **Discrepancy (open):** the row above predates DEP-16, which reports that the required checks were switched to the aggregate `CI result` (Owner-reported). The agent session cannot read the ruleset's check list. | Owner to confirm from GitHub settings (§6) |
| `main` at `19b68cb` (PR #17 merge; parents `3f3b59d`, `33c082b`; tree identical to the reviewed head). Post-merge CI run #43 (id 45322697836): all 7 jobs `success`, including `CI result` | **Verified** via the GitHub API, 2026-11-24 |
| The `spotlight-client-portal-dev` environment: Limited network; allowlist `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; no network secrets; no environment variables | **Verified** via the environment API, 2026-11-24 |
| The Stripe sandbox catalog exists as specified | **Verified** by run `dep01-20261123T220040Z-290aebd0` (04 §6.5) |
| The restricted Stripe keys used for DEP-01 are revoked; no restricted keys remain in live mode; `chris-pribyl` and `spotlight-client-portal-dev` hold no network secrets or environment variables; `api.stripe.com` is not on the `spotlight-client-portal-dev` allowlist | **Owner-reported**, 2026-11-24 |
| The `spotlight-client-portal-dev` allowlist is `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; network access is Limited | **Owner-reported**, 2026-11-24 |
| CI post-merge run #35 on `e7c8d47` concluded `success` | **Verified** via the GitHub API |

## 6. Pending Owner actions

1. **Decide OI-73** (collection order relative to publication; OPEN-ISSUES Part 2). The exact implications of option A are restated there for confirmation.
2. Review and merge the OI-74 documentation PR; then start WP-B and WP-C in two sessions from its merge commit (§8, §9).
3. Confirm that AUTH-002's permitted "Checkout Sessions" include **setup-mode** sessions for card recovery (OI-74), or amend AUTH-002. Until then, setup-mode sessions are exercised only with the mocked client. Local and CI work is unaffected.
4. Confirm the required status checks on `main` (§5 discrepancy).
5. Engage counsel and a tax advisor (DEP-03, DEP-04, DEP-05); DEP-03 now includes the OI-74 items.
6. When ready for WP-B's Stripe work: meet the AUTH-002 activation conditions.
7. When ready for WP-D: create the accounts in AUTH-003.

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

## 9. Resume here (session handoff, 2026-11-24)

A new session starts by reading CLAUDE.md, this file, and AUTHORIZATIONS.md, then:

| Stream | Next step | Read first | Authorization |
|---|---|---|---|
| Integration (primary session) | Wait for the Owner's OI-73 decision and the OI-74 PR merge. Then own migration ordering, shared-file conflicts, and the end-to-end R1 journey test. Do not start WP-B or WP-C in the integration session. | §8; 08 OI-71, OI-72, OI-74 | AUTH-000; AUTH-001 for cross-package tests |
| WP-B (new session, `wp-b/*`) | Agreements and order summaries → Checkout records (card-only, mocked Stripe) → webhook ingestion → ledger → `payment_authorizations` and recovery (04 §8.1) → final-balance invoice with automatic collection (04 §10) → reconciliation, holds, disputes → financial status interface with G1 and `payment_authorization_ready` | 04 (all), 03 §4, 03 §13, 01 §7, §9.1 | AUTH-001 only. AUTH-002 is **not active**: no Stripe credential or request |
| WP-C (new session, `wp-c/*`) | Intake (precondition includes `payment_authorization_ready`) → uploads and quarantine → releases and approvals (emits `release.approved`) → QA and security evidence → domain readiness (G6) → gate evaluator (G8 fail-closed) → publication authorization and deployment records → derived queues | 05, 06, 03 §4, §13, 01 §7, §9.1 | AUTH-001 and AUTH-004 |

Standing constraints for every stream: no live Stripe and no Stripe request without an active AUTH-002; no production or hosted environment; no change to existing Phase 2 security objects; never merge without Owner approval; never edit a merged migration; OI-73 is open, so do not add a publication precondition to collection.

