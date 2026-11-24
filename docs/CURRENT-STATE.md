# Current State

| Field | Value |
|---|---|
| Version | 1.1.0 |
| Status | **Canonical status record** (OI-67). Every pull request that changes status updates this file in the same pull request. |
| Last updated | 2026-11-24, by the WP-0 shared contracts PR, based on `main` at `d6d795a` |

This file replaces the status tables that were previously repeated in CLAUDE.md §1, README, 01 §8, 08 §4, OPEN-ISSUES headers, and 04 §6. Those places now link here. **What is authorized** is in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). **What was decided** is in [08](08-DECISIONS-AND-CHANGELOG.md). Detailed dependency records are in [OPEN-ISSUES.md](../OPEN-ISSUES.md).

Evidence labels: **Verified** (checked from repository or provider evidence, with the source named) · **Owner-reported** (stated by the Owner, not independently checked).

## 1. Authorization summary

| Item | State |
|---|---|
| Architecture | Approved |
| Specifications | All approved, with scope limits in §3 |
| Active authorizations | AUTH-000 (Tier 0, standing); **AUTH-001** (Tier 1: WP-A, WP-0, WP-B and WP-C on local and CI) |
| Granted, not yet active | **AUTH-002** (Stripe sandbox), **AUTH-003** (hosted non-production). Activation conditions are in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). |
| Production launch | **Not authorized.** No real client payment may be accepted until production launch authorization (Tier 3) is granted. |
| Deployments | None. Nothing is deployed. |

## 2. Releases and work packages (OI-67, OI-68)

| Item | Scope | State |
|---|---|---|
| Phase 1, Foundation and CI | Tooling, CI, design tokens | **Done** (PR #2) |
| Phase 2, Auth, security, tenancy | Invitation-only OTP, MFA, RLS, audit, nonce CSP, private storage policies | **Done, local only** (PR #4) |
| WP-A | Governance and specification correction | **Done** (PR #14, merge commit `d6d795a`) |
| WP-0 | Shared contracts: domain-event and outbox tables, state-domain types, audit action names, gate-function interfaces | **In review** (this PR). Migration `20261124120000_wp0_shared_contracts.sql`; contracts in `src/domain/contracts/`. Open point for WP-C: OI-71. |
| WP-B | Agreements, payments, webhooks, ledger, reconciliation (R1 scope) | Not started. Local and CI parts covered by AUTH-001; Stripe parts need AUTH-002 active. |
| WP-C | Intake, uploads, approvals, publication authorization, admin queue (R1 scope) | Not started. Covered by AUTH-001; release of scanned uploads needs DEP-07. |
| WP-D | Hosted non-production infrastructure, then production readiness | Not started. Needs AUTH-003 active. Production steps are Tier 3. |
| WP-E | Legal, tax, and commercial approvals | Owner. Not started (DEP-03, DEP-04, DEP-05). |
| **R1** release candidate | Complete controlled transaction (01 §9.1) | Not started |
| **R2** release candidate | Fulfillment automation (01 §9.2) | Not started |

Former phases 3–5 map onto these work packages (01 §7). Phase numbers are no longer used for authorization.

## 3. Specifications

| Spec | Version | State |
|---|---|---|
| 01 Project overview | 0.4.0 | Approved |
| 02 Architecture and environments | 0.4.0 | Approved |
| 03 Security, auth, tenancy | 0.4.4 | Approved (03A is supporting evidence) |
| 04 Agreement and billing | 0.8.0 | Approved for implementation and test mode. **Not approved for production:** legal review (DEP-03) and provider verification (DEP-06) remain conditions. |
| 05 Lifecycle and uploads | 0.4.0 | Approved |
| 06 Publishing and post-launch | 0.5.0 | Approved |
| 07 Notifications, privacy, design | 0.4.0 | Approved. Retention periods remain provisional (DEP-05). |
| 08 Decisions and changelog | 0.13.0 | Approved. The provenance caveat in 08 §1 still applies to transcribed decisions. |
| AUTHORIZATIONS, CURRENT-STATE | 1.0.0 | Approved |
| CLAUDE.md | rewritten 2026-11-24 | Approved |

## 4. Dependencies

| ID | Item | State |
|---|---|---|
| DEP-01 | Stripe sandbox catalog | **Complete.** 11 products and 11 prices verified (04 §6.5). |
| DEP-02 | Live Price ID verification | Not started (Tier 3, before production) |
| DEP-03 | Legal review of the agreement and policies | Not started. **Start now** (longest external lead time). Includes the R1 hosted-payment wording question (OI-68). |
| DEP-04 | Tax review and Stripe Tax configuration | Not started. Start now. |
| DEP-05 | Privacy and retention legal review | Not started. Start now. |
| DEP-06 | Provider verification | In progress. Stripe items run under AUTH-002. Vercel, Resend, Storage items run under AUTH-003 and WP-C. |
| DEP-07 | Malware scanning vendor | Not started. A verified shortlist is a WP-A follow-up deliverable; the Owner selects before the R1 release candidate. |
| DEP-08 | Brand assets for production | Production part outstanding |
| DEP-09 | Production infrastructure | Not started (Tier 3) |
| DEP-10 | Branch protection | **Complete.** See §5. |
| DEP-12 | Monitoring vendor | Not started. Shortlist with DEP-07. |
| DEP-14 | Hosted Supabase staging | Not started. Unblocked by OI-50 and OI-51 (decided); runs under AUTH-003. |
| DEP-15 | Real test-mode webhook verification | Not started. Runs under AUTH-002. |
| DEP-16 | Switch required status checks to `CI result` | **Owner action, not yet confirmed.** WP-A is merged (PR #14). The ruleset cannot be read from the agent session; the Owner confirms the switch (§6). |

## 5. Verified facts

| Fact | Evidence |
|---|---|
| `main` is protected by ruleset `protect-main`: pull request required (0 approvals), force pushes and deletions blocked, and 5 required status checks with "require branches to be up to date": Lint, types, format, unit tests; Lighthouse budgets; Dependency audit; Secret scan; Database, integration, and e2e tests | **Verified** 2026-11-24 via the GitHub API (`/repos/…/rules/branches/main`) |
| The Stripe sandbox catalog exists as specified | **Verified** by run `dep01-20261123T220040Z-290aebd0` (04 §6.5) |
| The restricted Stripe keys used for DEP-01 are revoked; no restricted keys remain in live mode; `chris-pribyl` and `spotlight-client-portal-dev` hold no network secrets or environment variables; `api.stripe.com` is not on the `spotlight-client-portal-dev` allowlist | **Owner-reported**, 2026-11-24 |
| The `spotlight-client-portal-dev` allowlist is `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`; network access is Limited | **Owner-reported**, 2026-11-24 |
| CI post-merge run #35 on `e7c8d47` concluded `success` | **Verified** via the GitHub API |

## 6. Pending Owner actions

1. **Confirm DEP-16** (WP-A is merged): switch the required status checks (DEP-16): require `CI result`, `Lint, types, format, unit tests`, `Dependency audit`, and `Secret scan (gitleaks, full history)`; remove `Database, integration, and e2e tests (local Supabase)` and `Lighthouse budgets (spec 02 §7)` from the required list. GitHub reports a skipped job as passing, so those two must not stay required once they can be skipped. Until the switch is made, do not merge documentation-only PRs.
2. Engage counsel and a tax advisor (DEP-03, DEP-04, DEP-05).
3. When ready for WP-B's Stripe work: meet the AUTH-002 activation conditions.
4. When ready for WP-D: create the accounts in AUTH-003.

## 7. Known follow-ups

| Item | When |
|---|---|
| `supabase/.temp` files tracked although ignored | **Done in WP-0.** `postgres-version` stays tracked on purpose (it pins the database image CI tests against, 17.4.1.054) with an explicit `.gitignore` exception; `cli-latest`, an empty update-check cache, is untracked. |
| DEP-07 and DEP-12 verified vendor shortlist | WP-A follow-up |
| PR #6 (AI operations proposal): header corrected to the current next unused ID; remains a draft outside the release path (OI-67) | Done in PR #6 |
| Time tracking: each implementation PR description records AI session hours, Owner review hours, and admin hours (OI-67) | From WP-0 onward |
