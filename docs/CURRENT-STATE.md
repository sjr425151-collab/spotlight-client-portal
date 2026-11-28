# Current State

| Field | Value |
|---|---|
| Version | 1.47.0 |
| Status | **Canonical status record** (OI-67). Every pull request that changes status updates this file in the same pull request. |
| Last updated | 2026-11-28, by the test-disposition batch record (B-1a to B-1c, B-2, B-3). Earlier: 2026-11-28, by the contractual architecture wave grant record (OD-1 to OD-19; AUTH-021 to AUTH-024 granted). Earlier: 2026-11-28, by the PWP investigation record (OI-124 to OI-129 opened; 04 v0.10.6 and DEP-18 status corrected). Earlier: 2026-11-28, by the milestone acceptance record (Owner directive; §3, §6 and §7 corrected under Tier 0; AUTH-020 diff-hash limitation). Earlier: 2026-11-28, by the AUTH-020 completion record (OI-122 closed). Earlier: 2026-11-28, by the AUTH-016 completion and AUTH-020 grant record (OI-115 local part, OI-119 and OI-123 closed). Earlier: 2026-11-28, by the AUTH-018 and AUTH-019 completion record (OI-120 closed; OI-122 and OI-123 opened). Earlier: 2026-11-27, by the consolidated completion record (AUTH-002 Stage A attempt 3 passed and Stage A completed; AUTH-010 and AUTH-015 completed; OI-93, OI-114 and OI-121 closed). Earlier: 2026-11-27, by the Stage A attempt 3 prerequisite record (the Owner's no-other-operation statement and WP-B designation; not active) and the AUTH-010 I-1 correction. Earlier: 2026-11-27, by the consolidated Owner decisions record (AUTH-019 granted; AUTH-010 Amendments 1 and 2; AUTH-015 Amendment 1; Stage A attempt 3 key creation authorized, creation only) and the AUTH-017 completion record (PR #53; OI-88 closed), and the AUTH-002 Stage A attempt 3 Gate A record (attestation received; not active). Earlier: 2026-11-27, by the OI-118 closure (cause H1, sandbox mismatch) and the AUTH-002 Stage A attempt 3 amendment (not active). Earlier: 2026-11-27, by the R1 execution grant record (AUTH-010 and AUTH-015 to AUTH-018 granted; D-a to D-c dispositions; DEP-07 and DEP-12 conditional selections; AUTH-003 executor). Earlier: 2026-11-27, by the AUTH-002 Stage A attempt 2 closure record (OI-118 opened) and the AUTH-014 completion record (PR #45; OI-116 closed). Earlier: 2026-11-27, by the AUTH-002 Stage A attempt 2 Gate A record (new key attestation; OI-117 option A; baseline `18c4215`; not active). Earlier: 2026-11-27, by the AUTH-002 Stage A attempt 1 termination and administrative closure record (Owner-approved evidence limitation), the attempt 2 remediation record (runner revision 4 accepted) and the attempt 2 amendment (not active). Earlier: 2026-11-26, by the AUTH-002 Stage A Gate A record (attestation and acknowledgments recorded; not active). Earlier: 2026-11-26, by the AUTH-002 Stage A credential mechanism amendment (no activation). Earlier: 2026-11-26, by the R1 completion and allocation record (PRs #40 to #43 merged; AUTH-008 I-2 and AUTH-009 completed; OI-91 closed; AUTH-010 mandatory for R1; AUTH-014 granted). Earlier: 2026-11-26, by the AUTH-009 and AUTH-008 I-2 grant record. Earlier: 2026-11-26, by the post-merge record for PRs #36, #27 and #38 (AUTH-013 activated and completed; AUTH-007 completed; OI-113 closed; D-1 ratified; Stage A attestation wording approved). Earlier: 2026-11-25, by the WP-C OI-113 PR (AUTH-013 active; implementation record §18), synchronized with `main` at `05b32e9` (after PR #27). Earlier: the WP-D18 PR (AUTH-007 and Amendments 1 to 3; §17), synchronized with `main` at `19f6103` (after PR #36); D-1 ratified (§17E). Earlier: the post-merge record for PRs #33, #34, #28, #37 and #35 (activations reconciled; F2 and OI-95 closed; AUTH-012 completed; WP-H merged; AUTH-013 granted, activation pending) |

This file replaces the status tables that were previously repeated in CLAUDE.md §1, README, 01 §8, 08 §4, OPEN-ISSUES headers, and 04 §6. Those places now link here. **What is authorized** is in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). **What was decided** is in [08](08-DECISIONS-AND-CHANGELOG.md). Detailed dependency records are in [OPEN-ISSUES.md](../OPEN-ISSUES.md).

Evidence labels: **Verified** (checked from repository or provider evidence, with the source named) · **Owner-reported** (stated by the Owner, not independently checked).

## 1. Authorization summary

| Item | State |
|---|---|
| Architecture | Approved |
| Specifications | All approved, with scope limits in §3 |
| Active authorizations | AUTH-000 (Tier 0, standing); **AUTH-001** (Tier 1: WP-A, WP-0, WP-B and WP-C on local and CI); **AUTH-004** (scoped Tier 2: WP-C storage policies, local and CI); **AUTH-021** (PWP-1, DEP-18 session), **AUTH-022** (PWP-2, WP-B), **AUTH-023** (PWP-5a, WP-C) and **AUTH-024** (PWP-5b, WP-C; starts after AUTH-023 merges), Tier 1, local and CI, granted 2026-11-28 and effective on the verified merge of the contractual architecture wave grant record; **Completed:** **AUTH-020** (OI-122, PR #64 `2ae3639`, post-merge CI 46103910059), **AUTH-016** (OI-115 local, OI-119, OI-123; PR #55 `b294d33`, post-merge CI 46089426391), **AUTH-019** (OI-120, PR #61 `19b173b`, post-merge CI 46086549947), **AUTH-018** (PR #57 `23346ef`, post-merge CI 46085126236), **AUTH-010** (OI-93 and OI-121, PR #59 `30ee417`, post-merge CI 46080015419), **AUTH-015** (OI-114, PR #54 `b5d8078`, post-merge CI 46077031048), **AUTH-017** (OI-88, PR #53 `8ebcced`, post-merge CI 46062083448), **AUTH-014** (OI-116, PR #45 `eacc8b5`, post-merge CI 46054458273), AUTH-006 (WP-H, PR #35 `30414c7`), AUTH-007 (WP-D18, PR #27 `05b32e9`), **AUTH-008** (I-1 PR #28 `b027e41`; I-2 PR #42 `48a8c04`), **AUTH-009** (OI-91, PR #43 `3545d0a`), AUTH-012 (OI-95, PR #37 `e3a7508`), AUTH-013 (OI-113, PR #38 `7226d6f`). **Expired:** AUTH-005 (WP-S). **Recorded, not active:** AUTH-002 Stage A (attempt 1 terminated and administratively closed under the Owner-approved evidence limitation of 2026-11-27, §13 "Stage A attempt 1 termination record"; attempt 2 amendment recorded, not active; corrected runner revision 4 accepted by SHA-256 after independent review, §13 "attempt 2 remediation record"; attempt 2 Gate A record, §13; **attempt 2 executed and closed (STOPPED: http_404, 2 requests, cleanup and reconciliation complete; §13 "attempt 2 execution and closure record"); catalog re-verification not achieved; cause OI-118**; no further attempt without a new Owner decision). AUTH-003 executor: WP-I after AUTH-016, from the dedicated `spotlight-staging-ops` environment (not active until the Owner's accounts and credentials) |
| Granted, not yet active | **AUTH-002** (Stripe sandbox; scope amended 2026-11-24 to include setup-mode recovery sessions; **Stage A completed 2026-11-27: attempt 3 passed**, the rest of AUTH-002 not active), **AUTH-003** (hosted non-production). Activation conditions are in [AUTHORIZATIONS.md](AUTHORIZATIONS.md). |
| Production launch | **Not authorized.** No real client payment may be accepted until production launch authorization (Tier 3) is granted. |
| Deployments | None. Nothing is deployed. |

## 2. Releases and work packages (OI-67, OI-68)

**Readiness levels (kept distinct):** *implemented* = merged with its package suites passing (Phase 2, WP-0, WP-C, WP-B, WP-S); *integrated R1 verification* = the cross-package browser and security suite T-E2E-01 to T-E2E-10 (**delivered**, PR #42 `48a8c04`) and the R1 release-candidate blockers (§7), **still open**; *production readiness* = legal, provider, hosted-environment, and Tier 3 launch steps, **not authorized**.

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

Versions as of `main` `59b9aac` (corrected 2026-11-28, Tier 0; Owner milestone directive). Each document's own header holds its full change history.

| Spec | Version | State |
|---|---|---|
| 01 Project overview | 0.4.3 (v0.4.3: PWP-0 to PWP-6 in §7; §9.1 criterion 18, contractual architecture, OI-112) | Approved |
| 02 Architecture and environments | 0.4.1 (v0.4.1: §8 monitoring signals, OI-108) | Approved (final approval v0.4.0) |
| 03 Security, auth, tenancy | 0.6.1 (v0.6.0: §4 standardized issuance direction, PWP-0) | Approved (03A v0.2.0 is supporting evidence) |
| 04 Agreement and billing | 0.11.0 (v0.11.0: §4A canonical contractual lock hierarchy, OD-3) | Approved for implementation and test mode. **Not approved for production:** legal review (DEP-03) and provider verification (DEP-06) remain conditions. |
| 05 Lifecycle and uploads | 0.5.2 (v0.5.0: scope confirmation and acknowledgment before preview release, PWP-0; v0.5.2: OI-113) | Approved |
| 06 Publishing and post-launch | 0.5.5 (v0.5.5: §8.1 controlled recovery, OI-114) | Approved |
| 07 Notifications, privacy, design | 0.4.2 (v0.4.1: OI-110) | Approved. Retention periods remain provisional (DEP-05). |
| 08 Decisions and changelog | 0.62.0 | Approved. The provenance caveat in 08 §1 still applies to transcribed decisions. |
| AUTHORIZATIONS | 1.42.0 | Approved. AUTH-002 (beyond Stage A) and AUTH-003 granted, not active |
| CURRENT-STATE | 1.47.0 | Canonical status record |
| OPEN-ISSUES | 0.49.0 | Current |
| R1-HANDOFFS | 0.7.0 | Active handoffs (historical for the completed packages) |
| OWNER-RUNBOOKS | 0.5.0 (§1 to §12; §5 reconciliation before publication; §7 direct role and membership writes, OI-90) | **[PROPOSED]** Owner review, including §5 and §7 |
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
| DEP-07 | Malware scanning vendor | **Conditionally selected (Owner, 2026-11-27): Scanii Basic**, US region; conditions in §13 "R1 execution grant record"; no account, credential or integration authorized. Earlier: Not started. A verified shortlist is a WP-A follow-up deliverable; the Owner selects before the R1 release candidate. |
| DEP-08 | Brand assets for production | Production part outstanding |
| DEP-09 | Production infrastructure | Not started (Tier 3) |
| DEP-10 | Branch protection | **Complete.** See §5. |
| DEP-12 | Monitoring vendor | **Conditionally selected (Owner, 2026-11-27): Sentry Team**, US region; conditions in §13 "R1 execution grant record"; no account, credential or integration authorized |
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

Corrected 2026-11-28 (Tier 0; Owner milestone directive). Completed items were removed; their records are in §13 and Git history (WP-S merge; AUTH-006 to AUTH-020; AUTH-002 Stage A, completed 2026-11-27 by attempt 3; the DEP-07 and DEP-12 conditional selections; the AUTH-014 merge). The consolidated, sequenced checklist for items 4 to 6 is in the next-wave execution plan prepared for Owner review.

1. **Engage counsel, a tax advisor and privacy review** (DEP-03, DEP-04, DEP-05). DEP-03 includes the OI-74 items, the OI-82 refund and allocation terms, revocation effects, the interim payment wording (F10), the contractual package-scope language (A4) and the counsel and publication evidence for PWP-3.
2. **Supply the standard scope for each package** (DEP-18: Essential, Professional, Advanced, Signature, Prestige) and include it in counsel review. The AUTH-018 loader exists; loading real content needs its own authorization.
3. (Done 2026-11-28) PWP-1, PWP-2 and PWP-5 granted as AUTH-021 to AUTH-024 (DEP-19). Remaining Owner rulings: OI-127 (AUTH-003 prerequisites) and OI-128 (the rest of AUTH-002), and the individually reserved assertion dispositions when presented.
4. **AUTH-003 (hosted staging; executor WP-I):** create the staging Supabase project (Pro plan, OI-50) and record its region; create the Vercel portal project with protected preview and staging (02 §4); set up Resend SMTP on a separate auth sending subdomain (OI-51; DNS records are Tier 3 Owner actions); enter each credential only through the secure credential form; record the accounts and plans (no credential values) so Main can record activation. Hosted projects receive reviewed migrations only: no seed, no reset (A3).
5. **Rest of AUTH-002 (F7, F8, N1(c), DEP-15; executor WP-B):** a new restricted test key with the AUTH-002 permissions, `api.stripe.com` and any verified Stripe CLI hosts on the allowlist, no live credential, a checksum-pinned CLI if used, with the Stage A attestation and reconciliation discipline.
6. **Vendor accounts:** authorize account creation and integration for Scanii Basic (DEP-07) and Sentry Team (DEP-12) when ready; the conditional selections authorize nothing.
7. **Review OWNER-RUNBOOKS v0.5.0** ([PROPOSED]), including §7 (OI-90, required before R1 release-candidate acceptance) and §5 (reconciliation before publication until DEP-17).
8. **Repository visibility change** (OWNER-RUNBOOKS §11, FD-03): recorded as not performed; Main holds no evidence that it has been done.
9. **Brand assets** (DEP-08), before production.

## 7. Known follow-ups

| Item | When |
|---|---|
| `supabase/.temp` files tracked although ignored | **Done in WP-0.** `postgres-version` stays tracked on purpose (it pins the database image CI tests against, 17.4.1.054) with an explicit `.gitignore` exception; `cli-latest`, an empty update-check cache, is untracked. |
| DEP-07 and DEP-12 verified vendor shortlist | **Done** (verified 2026-11-26 under a temporary documentation-host allowlist, added and removed with the Owner's approval; conditional selections 2026-11-27) |
| PR #6 (AI operations proposal): header corrected to the current next unused ID; remains a draft outside the release path (OI-67) | Done in PR #6 |
| Time tracking: each implementation PR description records AI session hours, Owner review hours, and admin hours (OI-67) | From WP-0 onward |
| **R1 release-candidate blockers (mandatory before R1 acceptance)** | Corrected 2026-11-28 (Tier 0). **Open:** **DEP-19** contractual architecture, PWP-1, PWP-2 and PWP-5 (criterion 18; **authorized 2026-11-28 as AUTH-021 to AUTH-024**, in implementation); PWP-3 counsel and publication evidence (DEP-03); **DEP-18** closure through PWP-4 non-production materialization and end-to-end verification (R-04; needs PWP-2, PWP-3, AUTH-003 and the Owner's scope content); N1(c), F7, F8 and DEP-15 (test mode, rest of AUTH-002); DEP-14 and DEP-17 and the hosted part of **OI-115** (AUTH-003); N1(b) (the Owner runs reconciliation before publication, OWNER-RUNBOOKS §5, until DEP-17); DEP-07 and DEP-12 integrations (vendors conditionally selected; no account authorized); the staging Lighthouse run (criterion 17); **OI-90** operator runbook (OWNER-RUNBOOKS §7, Owner review); DEP-03 wording, never presented as legally approved until approved (F10). **Delivered:** the integrated R1 browser suite T-E2E-01 to T-E2E-10 (PR #42 `48a8c04`); N1(a) (WP-H, PR #35 `30414c7`); OI-86 and OI-87 (PR #35); OI-91 (AUTH-009, PR #43 `3545d0a`); OI-113 (PR #38 `7226d6f`); OI-95 (PR #37 `e3a7508`); DEP-18 version sealing (PR #27 `05b32e9`) and interim scope loading and activation infrastructure (AUTH-018, PR #57 `23346ef`); OI-88 (AUTH-017, PR #53); OI-93 and OI-121 (AUTH-010, PR #59); OI-114 (AUTH-015, PR #54); OI-115 local part, OI-119, OI-123 (AUTH-016, PR #55); OI-120 (AUTH-019, PR #61). Test reliability: OI-116 (AUTH-014), OI-122 (AUTH-020, PR #64) |
| **F2** (integration stream; **closed 2026-11-25** by the Owner's conditional decision after the PR #28 merge and its post-merge CI; §13, §14) | **Cause (reproduced):** after `supabase db reset`, PostgREST answers `503 PGRST001` while it reconnects from dead pooled connections (11 of 12 consecutive cold-reset runs failed before the readiness gate). **Resolution (PR #28, AUTH-008 I-1, Amendment 1, W-1, B-1):** real WP-B records replace the global `private.project_financial_status` fixture; WP-C RPC helpers report the PostgREST `error`; a deadline-bounded readiness gate per integration file (60 s overall, each request bounded and aborted, three consecutive successes required, every failure recorded, fail closed at the deadline; WPI-P1); a deterministic, deadline-bounded schema-cache sync with client-side database bounds and `ddl()` excluded from the budget. **Evidence:** 12/12 cold-reset runs at `c829fdb`, `99615e2`, `d45e624` and the combined candidate `cb541df` (no PGRST code in any test output; every 503 a gate probe); WP-C's independent 10/10 series and stall probes; exact-head CI 45671161028 and post-merge CI 45675171938, 7/7 with the full suite; reviews Main 7170555427, WP-B 7170586962, WP-C 7170778407. Main did not run the cold-reset series itself (no Docker daemon in its container). **Carried forward (not closed):** (1) right after a local stack restart the gate waited 19.9 s (187 × `503 PGRST002`, schema cache loading) before the first test, inside its 60 s deadline; a wait beyond 60 s fails closed and visibly; (2) N-1/N-2: the guarded use of pg 8.16.3's internal `connection.stream` must be re-verified on any pg upgrade; (3) O-1 (non-RPC reads in the WP-C files ignore `error`) and O-2 (the reload end signal) for I-2; (4) WP-C's optional N-1 (the close message does not name budget exhaustion); (5) WPI-P2 (informational); (6) O-3 (the `/sales` empty state) was OI-95, closed by PR #37 (`e3a7508`) |
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

**OI-113 (closed 2026-11-26; PR #38 `7226d6f`).** The limitation below is kept as the record at the time.
- **When it happens:** two client members of one project approve the same release concurrently, and the earlier-started transaction takes the release lock second.
- **What goes wrong:** WP-C's emitting approval and `project_fulfillment_status.current_release_approval_id` disagree. The WP-H cross-check then rejects the initiation with **`approval_mismatch`**.
- **Effect:** it fails closed, with no obligation, no outbound request and no charge. The automatic initiation does not happen, and the Owner receives `payment.final_balance_blocked`.
- **Decision (Owner, 2026-11-25):** option (a), a separately authorized WP-C interface correction (AUTH-013, proposed). WP-H's strict approval matching is kept, and WP-H does not change for it. Option (c), re-release and re-approval, is an emergency recovery procedure only, never closure.
- **Correction:** implemented under AUTH-013 (§18) and merged in PR #38 at `7226d6f60dcbf014033b1eb24b1e0e630d945942`; post-merge CI run 45725850769 (#131) 7/7. OI-113 closed; AUTH-013 completed. Option (c) is OWNER-RUNBOOKS §12 (emergency recovery only).

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

**Consolidated cycle activation record (2026-11-25):** the record above activated when PR #33 merged at `f37cf7ecf13c7f25e37477684731a2e7d11e0943` (parents `c89bf56`, `b4b6b98`; tree identical) and post-merge CI run 45583992649 (#103) passed 7/7 with the full suite: AUTH-006 Amendment 2, AUTH-007 Amendment 3 (D-1 unratified) and AUTH-012 (implementation after WP-I-1) active; the AUTH-008 Amendment 1 clarification recorded without new authority. Authorization boundaries unchanged.

**PR #34 merge record (2026-11-25):** merged by Main under the Owner's pinned authorization at head `951d7dd49e3711b53520cc61372c3ec29a1e09ec`; merge commit `a5dfad0ccdef3aa669588c49976fb784d43bfbbc` (parents `f37cf7e`, `951d7dd`; tree identical; documentation only); post-merge CI run 45665855580 (#112) 7/7 with the full suite. **Active:** the AUTH-007 Amendment 3 correction (the exact three-file exemption). **Recorded, not active:** AUTH-002 Stage A (Gate A prerequisites (1) and (2) satisfied by this merge and CI; every other prerequisite unmet; no provider execution authorized). **Proposed only (non-executable):** AUTH-009, AUTH-010, AUTH-013. **Open:** OI-113 (mandatory R1 release-candidate blocker). WP-D18 was told its held D-1 patch may proceed within Amendment 3; D-1 stays unratified.

**PR #28 merge record (2026-11-25):** merged by Main under the Owner's pinned authorization at head `38537bde26cd79fe9da1e80bfdcb452d163eefad` (base `a5dfad0`; exact-head CI 45671161028 (#114) 7/7); merge commit `b027e4192fe3100d89dec106b7ae7686f82a974a` (parents `a5dfad0`, `38537bd`; tree identical, `d16633d`); post-merge CI run 45675171938 (#116), all seven jobs passed (Classify changes, Lint/types/format/unit tests, Dependency audit, Secret scan, Lighthouse budgets, Database/integration/e2e with migrations from scratch, pgTAP, integration, both builds, the bundle check and e2e, CI result). Reviews: Main 7170555427, WP-B 7170586962, WP-C 7170778407 (none blocking). **F2 closed** (§7) under the Owner's conditional decision, with its residual items carried forward. **AUTH-012 implementation released** within its approved scope (R1-HANDOFFS §4). **Next in the merge order:** WP-H (PR #35) synchronizes onto `b027e41` with full verification and fresh WP-S, WP-C and Main records, then WP-D18 (PR #27).

**PR #37 merge record (2026-11-25):** merged by Main under the Owner's pinned authorization at head `39a8fdf6394121e9b9a58429bd2f09cc60cf1069` (base `b027e41`; exact-head CI 45678633347 (#119) 7/7; Main review 7171553267); merge commit `e3a750883a90e52c7138dc72be11fcff3f1290d9` (parents `b027e41`, `39a8fdf`; tree identical, `eebc4b2`); post-merge CI run 45682383873 (#120), all seven jobs passed with the full suite. **OI-95 closed; AUTH-012 completed** (expired on merge). **Carried forward:** O-1 for I-2 (the OI-95 e2e test leaves its Sales user and customer project in the database). **O-2 reconciled:** PR #37 added §16 without changing this header; the header version is allocated sequentially by the next record to merge, preserving every existing record.

**PR #35 merge record (2026-11-25):** merged by Main under the Owner's pinned authorization at head `85ec6cef1ecd27e45fb037edf36d42b8db8eadaa` (base `e3a7508`; exact-head CI 45687359888 (#122) 7/7); merge commit `30414c78b80594a735c8031a3a285a3e88d8f6cb` (parents `e3a7508`, `85ec6ce`; tree identical, `c001ec1`); post-merge CI run 45689577718 (#123), all seven jobs passed with the full suite. Reviews: Main 7159127341 / 7171414144 / 7172719700; WP-S 7168757687 / 7171526296 / 7172733325; WP-C 7168769499 / 7171448905 / 7172730201 (none blocking). **Delivered:** OI-86 (project lock `FOR NO KEY UPDATE`), OI-87 (`change_reason` column privilege), N1(a) attribution at receipt with conflict candidates, and the release-approval cross-check (which closes the pre-WP-H gap where an approval of a superseded or withdrawn release could initiate collection). **AUTH-006 completed.** **OI-113 open** (mandatory R1 release-candidate blocker; fails closed). **AUTH-013 granted**, activation pending this record's merge and post-merge CI. **Next:** WP-D18 (PR #27) synchronizes onto this baseline and adds F5; AUTH-013 implementation after activation; the AUTH-009 grant package (inventory drafted).

**PR #36 merge record (2026-11-25):** merged by Main under the Owner's pinned authorization at head `e83ad45ca2036c52c45c8f77793a47c12e4d6742` (base `30414c7`; exact-head CI 45690705575, documentation-only set); merge commit `19f6103385dd8778f449fdacae35add01ea0785a` (parents `30414c7`, `e83ad45`; tree identical, `9b448bc`; documentation only); post-merge CI run 45694804255 (#126), all seven jobs passed with the full suite. **AUTH-013 activated** on that result; WP-C released to implementation.

**PR #27 merge record (2026-11-25):** merged by Main under the Owner's pinned authorization at head `3ff957a8cd991c40fd34e02817a98a62d83d3912` (base `19f6103`; exact-head CI 45696075220 (#127) 7/7); merge commit `05b32e9f62d409c88015c40ccddd33a852818e07` (parents `19f6103`, `3ff957a`; tree identical, `917a4ad`); post-merge CI run 45706248054 (#129), all seven jobs passed with the full suite, including the F5 isolated concurrent-commit step. Reviews: Main 7173329865, 7173468443, 7173970147; WP-B 7173416670, 7173986888. **D-1 ratified** (Owner, 2026-11-25) separately from the merge (§17E). **AUTH-007 completed.** DEP-18 content stays a mandatory R1 blocker.

**PR #38 merge record (2026-11-26):** merged by Main under the Owner's pinned authorization at head `ae6c474a46ab8cb4c919758111e3e4cf0395ef7a` (base `05b32e9`; exact-head CI 45707874799 7/7; non-documentation patch ID `e53552ab…` unchanged across the synchronization; migration SHA-256 `eed29d43…`); merge commit `7226d6f60dcbf014033b1eb24b1e0e630d945942` (parents `05b32e9`, `ae6c474`; tree identical, `67ac4bf`); post-merge CI run 45725850769 (#131), all seven jobs passed with the full suite. Reviews: Main 7174631431, 7175740664; WP-S 7174769687, 7175762944; WP-B 7174846470, 7175757171. **OI-113 closed; AUTH-013 completed.** Informational findings are kept in AUTHORIZATIONS AUTH-013 "Completion". **Stage A:** prerequisite 3 met by option (a) and the eight-point attestation wording approved (mechanism only; no key creation, credential entry, provider access or execution). **Next:** the AUTH-009 and I-2 authorization decisions (Owner).

**PR #39 merge record (2026-11-26):** merged by Main under the Owner's pinned authorization at head `dbc0821789f9fae149ad0841c634257302a0c33a` (base `7226d6f`; exact-head CI 45727012129, documentation-only set); merge commit `779fe614b2f2e023139e1aac5838f124862312de` (parents `7226d6f`, `dbc0821`; tree identical, `0a19da4`); post-merge CI run 45729483714 (#133), all seven jobs passed with the full suite. The closure record (OI-113 closed; AUTH-013 and AUTH-007 completed) is in effect.

**AUTH-009 and AUTH-008 I-2 granted (Owner, 2026-11-26); activation pending** this record's merge and post-merge CI. On activation, WP-B implements AUTH-009 and WP-I implements I-2, concurrently. They share no file. Migration `20261127120000` is reserved for AUTH-009; I-2 adds no migration. AUTH-009's independent financial reviewer is WP-S or a separate session. AUTH-010 stays non-executable.

**R1 completion and allocation record (2026-11-26):** PR #40 merged at `2d27d0714681d8c8a4bc7c04dee22270acfc31ba` (head `12a43c5`, base `779fe61`; documentation only), post-merge CI 45731539779 (#136) 7/7: AUTH-009 and AUTH-008 I-2 active. PR #41 merged at `9e8569ca4b33feedba3828ec6fb3d11f7ab5c0d2` (head `1c822be`, base `2d27d07`; documentation only, OM-6(a)), post-merge CI 45732432770 (#138) 7/7: OM-1 to OM-7 in effect. PR #42 merged at `48a8c0461e7c440d83e76672d564880cdb16f8f4` (head `3ecfd69`, base `9e8569c`; exact-head CI 45742034442 7/7); post-merge CI run 45744252813 (#148) 7/7 with the full suite: AUTH-008 completed (§19). PR #43 merged at `3545d0a0fc63f63a059c3409cc67c4fc9c65ff54` (head `655c816`, base `48a8c04`; reviewed head `1d51f97`, CI 45743274091; one synchronization, setup-only; exact-head CI 45745385436 7/7); post-merge CI run 45745975920 (#150) 7/7 with the full suite: AUTH-009 completed, **OI-91 closed** (§20). Owner decisions of 2026-11-26 (08): AUTH-010 mandatory for R1 (readiness preparation by WP-B); OI-114 and OI-115 in R1 (proposals by WP-C and WP-I); AUTH-014 granted (OI-116). Allocation: WP-B AUTH-010 readiness package, then AUTH-002 Stage A when the Owner completes §6 item 5; WP-C DEP-07 shortlist and the OI-114 proposal; WP-I DEP-12 shortlist, AUTH-014 and the OI-115 proposal (WP-D scope); WP-S OI-88 reassessment; Main records and reviews. No provider, hosted or production access.

**AUTH-002 Stage A Gate A record (2026-11-26; Main):** recorded before Gate A, as AUTHORIZATIONS AUTH-002 "Stage A: activation" and "Stage A: credential mechanism amendment" require. **Not active:** this record authorizes no credential entry and no Stripe request; Main notifies the Owner when secure credential activation is authorized.

*Owner attestation, verbatim (message of 2026-11-26, "AUTH-002 Stage A — Formal Owner Attestation"):*

> I confirm the following:
>
> * Previous restricted test key: revoked.
> * New credential creation timestamp: 2026-11-26T03:54:00Z.
> * Sandbox: Spotlight Client Portal - Development.
> * Environment mode: Test.
> * Unique key name: SLM-AUTH-002-STAGE-A-20261126-01.
> * Displayed credential prefix: rk_test_.
> * Balance: Read.
> * Products: Read.
> * Prices: Read.
> * All other resources: None.
> * No permissions set to Write.
> * The new credential has not been pasted, committed or entered anywhere.
> * No other Stripe operation is in progress.
>
> I authorize WP-B (session_01RCnsL4vnvrx7b11HRxeo8T) on spotlight-client-portal-dev as the sole executing session for AUTH-002 Stage A, conditional upon satisfaction of all remaining Gate A prerequisites.

*Owner confirmation of points 1 and 4, verbatim (second message, 2026-11-26):*

> I explicitly confirm attestation points 1 and 4.
>
> Point 1: I personally created the new restricted test key directly in the Stripe Dashboard within the Spotlight Client Portal - Development sandbox on November 26, 2026, at 03:54 UTC.
>
> Point 4: I confirm the permission labels are copied word for word from the Stripe Dashboard:
>
> * Balance: Read
> * Prices: Read
> * Products: Read
>
> All other resources are set to None. No permissions are set to Write.
>
> The credential remains unactivated in the Claude Code environment.

| Gate A prerequisite | State |
|---|---|
| (1) Amendment merged; (2) post-merge CI | **Met** (PR #34 `a5dfad0`, CI 45665855580); mechanism amendment PR #46 `3902da8`, CI 45749645350 7/7 |
| (3) Credential-permission verification | **Met** (option (a), 2026-11-25); Bearer support verified (docs.stripe.com/api/authentication, 2026-11-26, SHA-256 `79251fa4…87cc34a`) |
| (4) Credential attestation, points 1 to 8 | **Met for points 1 to 6** by the two messages above (points 1 and 4 confirmed explicitly); point 7 (exactly one `api.stripe.com` credential, by names only) is verified by Main after entry; point 8 (any discrepancy stops) stands |
| (5) Execution baseline | **`main` at `3902da8f6f144cb0506147544fc2cb7479e0f582`**, post-merge CI 45749645350 7/7 with the full suite; no unmerged change to the catalog migrations or to 04 §6.1 or §6.5 (open PRs: #45, one integration test; #6, draft proposal). Main re-verifies at activation that `main` contains no such change since `3902da8` |
| (6) No other Stripe operation in progress | **Met** (Owner, above) |
| (7) Secure credential entry | **Pending** Main's activation notice: Network secret on `spotlight-client-portal-dev`, host `api.stripe.com`, Bearer, path prefixes `/v1/balance`, `/v1/products`, `/v1/prices` |
| (8) Execution go-ahead naming the session and environment | **Given** (WP-B `session_01RCnsL4vnvrx7b11HRxeo8T`, `spotlight-client-portal-dev`), conditional on the remaining prerequisites |
| Control 1: acknowledgments from every other active session on the environment | **Met:** `ACK Stage A no-Stripe <session>` from WP-I `session_01RCnsL7k3rDKjjpTicExTsF` (03:55:56Z), DEP-18 review `session_01RCnsL6oDLGr84wJPQZT3im` (03:55:59Z), Node.js verification `session_01RCnsL97ZSD9t59G2ipBD8Y` (03:56:01Z), WP-C `session_01RCnsL4zY9edGTBFKQUbXM6` (03:56:03Z), WP-S `session_01RCnsL8EFk2jME7uNLi46as` (03:56:08Z). Main (`session_01RCnsL4ywSjuERyt4yrCwbM`) sends no Stripe request. Archived sessions cannot act |
| Before activation (Main) | Review of WP-B's run plan and runner (sequential `GET` only; no client `Authorization` header; `Stripe-Version: 2026-09-30.endive`; hard stop at 30 requests; fail-closed preflight; no retry; evidence fields only) |

The execution window (credential entry to removal, UTC), the request evidence, the Owner's Dashboard request-log reconciliation, the removal of the Network secret and its allow rule, and the key revocation are recorded in the Stage A closure record.

**AUTH-002 Stage A attempt 1 termination record (2026-11-26; Main):**

| Item | Record |
|---|---|
| Credential entry | Owner message "credential entered", received 04:12:19Z (window start at or before that time). Main verified by names at 04:12:19Z: exactly one Network secret, host `api.stripe.com`, header `Authorization`, label "api.stripe.com/v1/balance"; nothing else changed. The path prefixes are not visible to Main |
| Execution | WP-B (`session_01RCnsL4vnvrx7b11HRxeo8T`), once, at 04:13:14Z, after verifying the accepted runner SHA-256 `446b15ef…033884efb`; command `python3 -I stage_a_runner.py --execute --baseline 3902da8f…` |
| Outcome | **STOPPED: runner defect.** A pre-send assertion (`h.lower()` over `req.header_items()` tuples) raised `AttributeError` before the first request was opened; exit code 1; no summary or evidence JSON written. **WP-B reported 0 requests sent.** Root cause: the offline tests stubbed the request function, so the real request path was never exercised; Main's acceptance review did not catch it |
| Cleanup | Owner confirmation (2026-11-26): the Network secret removed, the automatically created allow rule removed, the key `SLM-AUTH-002-STAGE-A-20261126-01` revoked, the Dashboard log reconciliation completed. The Owner's attestation of 2026-11-27 (next row) clarifies that the key-specific request count is not accessible in the Owner's Dashboard, so no key-specific Dashboard count was independently verified. Main verified by names at 04:18:27Z: no Network secret; allowed hosts exactly `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`, `pkg-containers.githubusercontent.com`; no `api.stripe.com` |
| Owner evidence for formal closure (Owner attestation, 2026-11-27) | "I confirm that the original restricted Stripe test key was revoked. I cannot access the historical revocation timestamp or the key-specific request count through my Stripe Dashboard. Record both as unavailable, not independently verified." **Revocation time (UTC): unavailable, not independently verified.** **Key-specific Stripe Dashboard request count: unavailable, not independently verified.** The Owner approved this evidence limitation for administrative closure of attempt 1, with no further investigation unless a material security concern emerges |
| Request evidence (distinguished) | **Runner-reported (WP-B):** 0 requests; the runner stopped on a pre-send assertion before the first request was opened (exit code 1; no evidence JSON). This is the executing session's report and the runner's code path, preserved as evidence that execution ended before the first network request. **Independently verified Stripe Dashboard count:** none; unavailable (above). No other count is substituted |
| Status | **Attempt 1 administratively closed** on this record's verified merge, under the Owner-approved evidence limitation (2026-11-27). This is not a successful Stage A closure under control (3), because no key-specific Dashboard reconciliation exists. Attempt 1 is never resumed. A further attempt only under the attempt 2 amendment (AUTHORIZATIONS AUTH-002); the reconciliation method for attempt 2 is OI-117 |

**AUTH-002 Stage A attempt 2 remediation record (2026-11-26; Main; offline only, no Stripe request, no credential):**

| Item | Record |
|---|---|
| Condition (2): defect corrected, adjacent defects reviewed | The `header_items()` defect was fixed in revision 2. Independent review by WP-I (`session_01RCnsL7k3rDKjjpTicExTsF`) and Main across revisions 2 to 4 found and closed further items: N-1 (a Proxy-Authorization header added by `ProxyHandler` is now refused in `https_open`), N-2 (SIGTERM, SIGINT and SIGHUP handled from `--out` acceptance to the last evidence write), N-3 (`request_count_note`: the count is of attempted requests), H-1 and H-2 (signal and send-time `not_proxied` cases), and H3-1 (argparse accepted the abbreviations `--e`, `--ex` and `--exe` as `--execute`; fixed with `ArgumentParser(allow_abbrev=False)`). N-4 (SIGALRM cannot interrupt a blocking proxy-host `getaddrinfo`) is documented and accepted |
| Conditions (3) and (4): real request path against a local stub | A local integration harness runs the **unmodified** runner's real `urllib` request path over TLS through a local CONNECT proxy to a loopback stub (test-only CA, `make_certs.sh`; no private key shipped). It verifies the preflight, GET-only enforcement, the endpoint allowlist, the 30-request ceiling, that the runner sends no `Authorization` or `Proxy-Authorization` header of its own, the failure and stop paths, no retry, signal handling and evidence on every exit path. The test-only `--test-base-url` (loopback only) is refused together with `--execute`. Every harness launch, and the mutation script's harness launch, goes through `no_execute()`, which refuses `--execute` and any abbreviation of it |
| Results (revision 4) | Harness **87 of 87** cases passed (exit 0). Mutation check: **36 of 36** runner mutants caught (exit 0); M36 (`allow_abbrev=False` removed) is caught by the static case `static_allow_abbrev_false`. WP-B ran both once, and WP-I reran both independently (`env -i`, `python3 -I`, Python 3.13.18, loopback only) with identical results. The repository was untouched throughout |
| Condition (5): independent review and acceptance | WP-I final verdict **ACCEPT** (2026-11-26T06:33Z). Main decoded and hashed every file itself and reviewed each revision's diff. **Accepted by SHA-256:** `stage_a_runner.py` `5094817abbebd4f9c97144b8562f682cd3f5254ecabfa24e98b72eb16cc310ca`; `test/harness.py` `e47abe78443fef62a20734900c091a5f7e36c17ca28a18a999c24975cf92a8e9`; `test/mutate_runner.py` `8b3dd133a4d40e75a8c8348dee9c71172f8f9f78aad0a315046dd488ec960687`; `test/make_certs.sh` `aac172145a42376df48b3ad95e28820c0ee9d26fb580b88a2a0494ab55e4ce92`. The files are held outside the repository, in WP-B's scratchpad; any change voids the acceptance. Acceptance authorizes no execution |
| Deviation during remediation (recorded) | At about 05:19Z, while no credential existed (removed by 04:18:27Z), WP-B reran two former harness cases contrary to Main's no-`--execute` instruction: case 80 invoked `--execute` against the loopback proxy, which received one `CONNECT api.stripe.com:443` and refused it locally (403); nothing left the container to Stripe; and case 58. That run was voided. Remedies: the `no_execute()` guard; case 80 removed; case 58 replaced by a static AST check (`static_execute_test_url_refusal`); case 75 (in-process `EXECUTE` construction, which sends nothing) kept with a no-traffic assertion |
| Residual risks not testable offline (for the Owner's execution decision) | The real upstream proxy, its credential injection and its CA; Stripe's real response format, including the `Stripe-Version` response header; SIGKILL (the IN_PROGRESS record then remains with its note) |
| Remaining before attempt 2 activation | Condition (1): satisfied by the Owner's attestation and evidence-limitation approval (2026-11-27) on this record's merge with post-merge CI 7/7. **OI-117:** the Owner's decision on how attempt 2 will be reconciled under control (3), given that key-specific Dashboard counts are not accessible to the Owner. Condition (7): a fresh restricted test key with a new unique name, a fresh Owner attestation (points 1 to 8), fresh acknowledgments from every other active session, and a freshly verified execution baseline; then Main's activation notice |

**AUTH-002 Stage A attempt 2 Gate A record (2026-11-27; Main; not active):** this is the consolidated record the attempt 2 amendment (AUTHORIZATIONS AUTH-002, condition (7)) requires. It authorizes no credential entry and no Stripe request. Main notifies the Owner when secure credential entry is authorized.

*Owner attestation, verbatim (message of 2026-11-27, "Owner attestation — AUTH-002 Stage A attempt 2"):*

> 1. I personally created a new restricted test key directly in the Stripe Dashboard on 2026-11-27 at 10:57 UTC.
> 2. Sandbox: Spotlight Client Portal - Development. Environment mode: Test (not live mode).
> 3. Displayed credential prefix: rk_test_. No other part of the key is disclosed.
> 4. Dashboard permissions: Balance: Read; Prices: Read; Products: Read. All other resources: None. No Write permissions.
> 5. Unique key name: SLM-AUTH-002-STAGE-A-20261127-02. Never previously used and separate from every earlier AUTH-002 key.
> 6. The key has not been pasted into chat, committed or entered anywhere. It will be entered only through the secure credential form after Main's activation notice.
> 7. I understand Main must confirm by names only that exactly one credential exists for api.stripe.com.
> 8. I understand any discrepancy means Gate A is not met, no request is sent and I am notified.
>
> No other Stripe operation is in progress.
>
> OI-117 decision: Option A approved. The per-key View request logs view is available and shows zero requests.
>
> I authorize WP-B (session_01RCnsL4vnvrx7b11HRxeo8T) on spotlight-client-portal-dev as the sole executing session for AUTH-002 Stage A attempt 2, conditional on all remaining Gate A prerequisites.

*Discrepancy and correction (point 8):* Main received the attestation before 04:00Z on 2026-11-27, so a creation time of 10:57 UTC was in the future. Main held Gate A and asked the Owner for the exact UTC time. *Owner correction, verbatim (second message, 2026-11-27):*

> Corrected Owner attestation — Point 1:
>
> I personally created the new restricted test key directly in the Stripe Dashboard on 2026-11-27 at 03:57 UTC.
>
> All other attestation points remain unchanged.

| Gate A prerequisite | State |
|---|---|
| (1) Amendment merged; (2) post-merge CI | **Met:** PR #48 at `18c4215f9d215f9d39b39631243d42c7f9d159da` (parents `9eb71cc`, `8e6e847`; tree equal to the reviewed head); post-merge CI run 45935443149 (#159) passed 7 of 7, including the full suite |
| (3) Credential-permission verification | **Met** (option (a), 2026-11-25; unchanged). Per-key request logs: docs.stripe.com/keys, read 2026-11-27, SHA-256 `22ff383f2faa88dff821a7797d1a27ed43770d7e6cb0e7d6f6015c566136d46c` ("View API request logs for a key … click the overflow menu for any key, then select View request logs"; this opens Workbench). That is documentation, not a verified view of the Owner's Dashboard |
| Runner | **Met:** revision 4, accepted by SHA-256 `5094817abbebd4f9c97144b8562f682cd3f5254ecabfa24e98b72eb16cc310ca` (§13 "attempt 2 remediation record"); frozen and held read-only by WP-B |
| OI-117: reconciliation method under control (3) | **Decided: option A** (Owner, 2026-11-27). The Owner confirmed that the key's "View request logs" view is available and shows zero requests before entry. **Cleanup order for attempt 2:** (i) immediately after the run, remove the Network secret and its allow rule; (ii) open the key's "View request logs" and record the count, methods, paths and first and last request times (UTC); (iii) expire the key promptly. Any discrepancy, or a view that cannot be read, prevents successful closure (control (3), unchanged) |
| (4) Credential attestation, points 1 to 8 (new key) | **Met for points 1 to 6** by the attestation and the Owner's point 1 correction above. The key is `SLM-AUTH-002-STAGE-A-20261127-02`, created **2026-11-27T03:57Z** (corrected; the first attestation's 10:57 UTC was in the future when received). Point 4's labels ("Balance: Read; Prices: Read; Products: Read") are identical to the labels the Owner confirmed word for word from this sandbox's Dashboard on 2026-11-26, so there is no naming or grouping difference to record. Point 7 (exactly one `api.stripe.com` credential, by names only) is verified by Main after entry. Point 8 stands. Before entry, Main verified by names that the environment has no Network secret and no `api.stripe.com` allowed host (2026-11-27) |
| (5) Execution baseline | **`main` at `18c4215f9d215f9d39b39631243d42c7f9d159da`**, post-merge CI 45935443149 7/7 (Owner accepted, 2026-11-27). Open PRs: #45 (one integration test) and #6 (draft proposal); neither changes the catalog migrations or 04 §6.1 or §6.5. At activation, Main re-verifies that `main` has gained no such change since `18c4215` |
| (6) No other Stripe operation in progress | **Met** (Owner, above) |
| (7) Secure credential entry | **Pending** Main's activation notice: Network secret on `spotlight-client-portal-dev`, host `api.stripe.com`, Bearer, path prefixes `/v1/balance`, `/v1/products`, `/v1/prices` |
| (8) Execution go-ahead naming the session and environment | **Given** (WP-B `session_01RCnsL4vnvrx7b11HRxeo8T`, `spotlight-client-portal-dev`), conditional on the remaining prerequisites. WP-B runs the accepted revision 4 runner once, unchanged |
| Control 1: acknowledgments from every other active session | **Collected by Main immediately before the activation notice**, recorded with session IDs and UTC times |

**AUTH-002 Stage A attempt 2 execution and closure record (2026-11-27; Main):**

| Item | Record |
|---|---|
| Acknowledgments (control 1) | `ACK Stage A attempt 2 no-Stripe <session>` from DEP-18 review `session_01RCnsL6oDLGr84wJPQZT3im` (04:15:00Z), WP-C `session_01RCnsL4zY9edGTBFKQUbXM6` (04:15:17Z), WP-I `session_01RCnsL7k3rDKjjpTicExTsF` (04:15:20Z), WP-S `session_01RCnsL8EFk2jME7uNLi46as` (04:15:22Z). Node.js verification `session_01RCnsL97ZSD9t59G2ipBD8Y`: its exact acknowledgment was blocked by that session's own permission check at 04:14:56Z and never delivered. Main read its transcript directly: it commits to no Stripe request, and the session was idle and disconnected, awaiting the Owner. Recorded as **effectively suspended** (control 1 permits acknowledgment or effective suspension) |
| Activation and credential | Main's activation notice at about 04:21Z. Owner "credential entered". At 19:11:54Z Main verified by names exactly one Network secret (host `api.stripe.com`, header `Authorization`, label "api.stripe.com/v1/balance") and unchanged allowed hosts (point 7). Baseline `18c4215`: `main` was then `eacc8b5`, and since the baseline it had changed only documentation and `tests/integration/auth-tenancy.test.ts`, with nothing under `supabase/` and nothing in 04 |
| Execution | WP-B (`session_01RCnsL4vnvrx7b11HRxeo8T`), once, after Main's GO. Runner SHA-256 verified (`5094817a…10ca`). Command: `python3 -I stage_a_runner.py --execute --baseline 18c4215f9d215f9d39b39631243d42c7f9d159da`. Run `stageA-20261127T191328Z-7e160ccc` |
| Outcome | **STOPPED: http_404** (exit code 20), **2 requests** (ceiling 30), start and end 19:13:28Z. (1) `GET /v1/balance`: HTTP 200, `livemode` present and exactly `false`, response `Stripe-Version` `2026-09-30.endive` (Gate A preflight passed). (2) `GET /v1/prices/price_1Uf5HxK5j4r4WkVPkRUJ4gnZ` (`essential.deposit`, the first recorded price): HTTP 404, a stop condition; nothing further was sent and nothing was retried. The price and product checks and duplicate detection were not reached. Evidence: WP-B's scratchpad, 1,190 bytes, SHA-256 `0f3d009e5c01edd428618a2c98402e79686ff2539ee7c8f5e59264000fd358f2` |
| Cleanup (Owner) | Network secret removed 19:15 UTC; restricted test key removed 19:17 UTC (minute precision). Main verified by names afterwards (2026-11-27): no Network secret; allowed hosts exactly `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`, `pkg-containers.githubusercontent.com`; no `api.stripe.com` |
| Reconciliation (control 3, option A) | Owner, Stripe Workbench: **2 requests**: `GET /v1/balance` HTTP 200 at 19:13:28Z and `GET /v1/prices/price_1Uf5HxK5j4r4WkVPkRUJ4gnZ` HTTP 404 at 19:13:28Z; first and last 19:13:28Z. These match the runner's evidence. The Owner states that the 404 originated from Stripe, not from the network proxy |
| Evidence limitations | (a) Cleanup times are to the minute only. (b) The Owner's screenshot supports the count, methods, paths, statuses and timestamps, but the per-key filter and the credential identity are not fully visible in it. (c) The accepted runner records no per-request status or time; those come from the Dashboard. (d) The Owner reported removing the Network secret; Main's check by names shows no `api.stripe.com` allowed host, but cannot see the proxy's internal allow rule directly. (e) **Attestation point 2 was inaccurate:** it named "Spotlight Client Portal - Development", but the requests are recorded in the "Setmore [Test mode]" Workbench (OI-118, H1). The key was removed at 19:17 UTC; "Setmore [Test mode]" is visible to all team members, and it held no catalog objects |
| Status | **Attempt 2 closed** on this record's verified merge: terminated on a stop condition, cleanup complete, reconciliation matches (with limitations (a) to (d)). **Stage A's objective, catalog re-verification, was not achieved.** The cause is OI-118. No retry, rerun or further Stage A attempt without a new Owner decision |

**OI-118 root-cause investigation (Main, read-only, 2026-11-27):**

| Finding | Evidence |
|---|---|
| The ID was correct when recorded | DEP-01 run `dep01-20261123T220040Z-290aebd0` (Main's preserved output, SHA-256 `3ae7dd2a…0c64`): `POST /v1/prices` for `essential.deposit` returned 200 (request `req_M5NtFvLIMLyB0D`), and the independent verification `GET /v1/prices/price_1Uf5HxK5j4r4WkVPkRUJ4gnZ` returned **200** (request `req_N54g8ivXQuoBgo`) on 2026-11-23 at 22:00Z, with `livemode: false`. The same ID string appears in 04 §6.5, migration `20261124160000` (line 311), the mock gateway and the pgTAP tests. There is no transcription error |
| Stripe's meaning of 404 | "The requested resource doesn't exist" (docs.stripe.com/api/errors, read 2026-11-27, SHA-256 `4e557c38…c832`). A permission problem is 403 |
| How a price can become missing | "You can only delete prices that you've never used" (docs.stripe.com/products-prices/manage-prices, read 2026-11-27, SHA-256 `7631c8b5…1b4c`); these prices were never used. Sandboxes are isolated from one another, and sandboxes can be deleted and created from the Dashboard (docs.stripe.com/sandboxes, read 2026-11-27, SHA-256 `62d63164…47d1`) |
| Hypotheses (not yet distinguished) | **H1:** the attempt 2 key was created in a different sandbox from the one holding the catalog (for example, a second sandbox with the same name, or the test-mode sandbox rather than a general sandbox). **H2:** the sandbox holding the catalog was deleted and recreated under the same name. **H3:** the `essential.deposit` price (and perhaps others) was deleted in the Dashboard. Each yields a Stripe 404 with a successful `livemode: false` preflight |
| Discriminating checks (Owner, Dashboard only, no API and no key) | (1) In each sandbox named "Spotlight Client Portal - Development", search for `price_1Uf5HxK5j4r4WkVPkRUJ4gnZ` and `prod_VgKrmaWefVnWy1`, and for the other ten recorded product IDs. (2) On the Sandboxes overview, list the sandboxes with that name and their creation dates (catalog created 2026-11-23). (3) Search Workbench logs for request `req_N54g8ivXQuoBgo` (2026-11-23 22:00Z) |
| Owner findings (2026-11-27, Dashboard only; screenshots held by the Owner) | **C1:** two distinct test environments exist under Spotlight Marketing LLC, "Spotlight Client Portal - Development" (private access) and "Setmore [Test mode]" (all team members), with distinct Stripe account IDs; creation dates were not visible. **C2:** "Setmore [Test mode]" holds no products, active or archived. "Spotlight Client Portal - Development" holds all 11 expected catalog products; `essential.deposit` has product `prod_VgKrmaWefVnWy1`, a price that visually matches `price_1Uf5HxK5j4r4WkVPkRUJ4gnZ`, $160.00 USD one-time, metadata `catalog_key` `essential.deposit`, `catalog_version` 1, `expected_unit_amount` 16000; product created 2026-11-23. No catalog modification was made. **C3:** the Development Workbench shows multiple HTTP 200 product and price retrievals on 2026-11-23 at about 22:00 UTC (the individual request `req_N54g8ivXQuoBgo` was not located). The **Setmore [Test mode]** Workbench shows both attempt 2 requests: `GET /v1/balance` 200 and `GET /v1/prices/price_1Uf5HxK5j4r4WkVPkRUJ4gnZ` 404, both 2026-11-27 19:13:28 UTC |
| **Established cause (Owner, 2026-11-27): H1, sandbox mismatch** | The attempt 2 key belonged to "Setmore [Test mode]", not to "Spotlight Client Portal - Development", although attestation point 2 named the latter. The catalog, the repository price IDs, the migrations and the accepted runner are correct and are preserved unchanged. The fail-closed design worked: a `livemode: false` preflight passes in any test-mode account, and the first catalog read stopped the run with nothing written. **Lesson recorded:** a sandbox name is not an identity; attempt 3 binds the key to the dedicated sandbox's Stripe account ID (AUTHORIZATIONS AUTH-002, "Stage A: attempt 3 amendment") |

**R1 execution grant record (Owner, 2026-11-27; Main):** the Owner's consolidated authorization ("Consolidated Owner authorization — R1 execution"). Grants are in AUTHORIZATIONS (AUTH-010, AUTH-015 to AUTH-018, AUTH-003 executor rows); each takes effect on this record's verified merge (OM-1). Baseline `main` at `55138a8`.

| Item | Record |
|---|---|
| Decision 1 | AUTH-010 (WP-B, OI-93, with U-1 to U-4; the four Owner function names and signatures recorded in the grant), AUTH-015 (WP-C, OI-114), AUTH-016 (WP-I, OI-115 local), AUTH-017 (WP-S, OI-88 option A), with their enumerated specification amendments, test additions, setup changes, design decisions and reserved migrations. Conditional merges pre-authorized under OM-6(b). OM-2 applies to additions-only shared-file catch-up |
| Decision 4: DEP-07 | **Scanii Basic**, $49 a month (verified pricing, 2026-11-26), **US** processing region. The absence of SOC 2 is accepted for R1 conditionally, subject to a satisfactory DPA review, a security assessment and verified data-handling controls **before any real client file is processed**. The checksum algorithm is to be verified, and never substitutes for the authoritative SHA-256 integrity controls. Metadata retention and deletion controls are to be established. Selection only: no purchase, account, credential, integration or real data transfer |
| Decision 4: DEP-12 | **Sentry Team**, $26 a month equivalent on annual billing (verified pricing, 2026-11-26), **US** data region. Paid SMS and telephone paging deferred. A satisfactory DPA and subprocessor review is required before account commitment or real data processing. Open questions to resolve: framework compatibility (Next 16), the monthly-billing price, and Supabase data capture. Mandatory exclusion of sensitive request bodies, server-action results, credentials, authorization tokens, claim tokens, confidential commercial content and other sensitive data, demonstrated with synthetic test events before production eligibility. Selection only, as above |
| Decision 5 | WP-I is the WP-D executor under AUTH-003 after AUTH-016's verified completion, from the dedicated `spotlight-staging-ops` environment. Before activation: Main confirms technical isolation; WP-I identifies the exact least-privilege provider permissions. All AUTH-003 restrictions and stop conditions are unchanged |
| Decision 8a | AUTH-018 (Tier 1 with AUTH-001 Tier 2 database security controls): the refined interim architecture in 04 §4A ("R1 interim scope loading and activation"); D11 synthetic non-legal test content for local and CI verification only |
| OI-118 | Unchanged: the Owner's Dashboard checks C1 to C3 follow separately; no Stripe request, credential, catalog change or Stage A rerun is authorized. No grant above waits on it |

**Individual assertion dispositions for AUTH-018 (FD-14 format; approved by the Owner, 2026-11-27):**

**D-a: FD-14 compensating control (`tests/unit/wps-sales.test.ts`, function at line 413 and test at line 422, at `55138a8`).**
- *Original:* `scopeContentViolations` exempts only `20261126140000_wpd18_scope_version_sealing.sql`; every other migration must match none of the `constructor`, `marker` and `label` patterns.
- *Replacement (approved text):* add `LOADER_MIGRATION = "20261127160000_dep18_scope_loader_activation.sql"`, `LOADER_CONSTRUCTOR_CALL = "private.create_package_scope_version(p_package_key, p_items, false)"` and `CONSTRUCTOR_ANY = /create[\W_]*package[\W_]*scope[\W_]*version/gi`; a function `loaderConstructorViolations(sql)` that passes only when `CONSTRUCTOR_ANY` matches exactly once, the literal call occurs exactly once, and the call lies inside the body of `create function private.load_package_scope_version(` (up to its closing `\n$$;`); `scopeContentViolations` skips only the `constructor` pattern for the exact file `LOADER_MIGRATION` and adds `loaderConstructorViolations` for that file. The test at line 422 adds `expect(migrations).toContain(LOADER_MIGRATION)` and its title names the bounded exemption. Every existing assertion is unchanged.
- *Original guarantee:* outside the one sealing migration, no migration calls the constructor, uses the construction marker, or carries the fixture label in any recognizable form.
- *Replacement guarantee:* the same, except that the exact file `LOADER_MIGRATION` may name the constructor exactly once, as that literal call with `false`, inside `load_package_scope_version`; the `marker` and `label` controls stay fully enforced on it.
- *Exposure:* the exemption is one literal call in one exactly named file; the call takes only parameters, so no content can enter through a migration. Runtime behavior is bounded by the construction guard, the expected-hash check and Owner gating. The lexical control is defense in depth, not a substitute for runtime authorization and integrity enforcement (Owner).
- *Compensating coverage:* seven new synthetic cases that must each fail: two constructor calls in the loader file; the call with `true`; the call outside the loader function; the constructor built by dynamic concatenation in the loader file; the marker in the loader file; the label in the loader file; the identical call in any other migration name, including a similarly named file. The real loader migration must pass.
- *Authorization:* approved by the Owner, 2026-11-27, exactly as above. Unrelated controls and assertions preserved.
- *Evidence (required in the AUTH-018 PR):* the unit suite on the exact head; a scratch run showing each of the seven cases failing and the loader migration passing; exact-head CI 7/7; Main's diff review confirming no other `expect(` changed.

**D-b: isolated-test restore allowlist (`supabase/tests-isolated/wpd18-restore-allowlist.txt`).**
- *Original:* exactly 37 descriptors (the closure of 4 tables and 7 functions).
- *Replacement (approved):* add exactly these six lines, and change the expected count in `scripts/wpd18-isolated-commit-test.sh` from 37 to **43**: `TABLE private billing_package_scope_eligibility postgres`; `TABLE DATA private billing_package_scope_eligibility postgres`; `CONSTRAINT private billing_package_scope_eligibility billing_package_scope_eligibility_pkey postgres`; `FK CONSTRAINT private billing_package_scope_eligibility billing_package_scope_eligibility_version_fkey postgres`; `TRIGGER private billing_package_scope_eligibility billing_package_scope_eligibility_append_only postgres`; `TRIGGER private billing_package_scope_eligibility billing_package_scope_eligibility_no_truncate postgres`.
- *Original guarantee:* the disposable copy restores exactly the package-scope closure, no more and no less.
- *Replacement guarantee:* the same, for the closure that now includes the eligibility table the resolver reads.
- *Exposure:* none beyond the new table; the approvals table and the new Owner functions are deliberately outside the closure (the eligibility table stores the approved hash and has no foreign key to approvals).
- *Compensating coverage:* the script still requires every line to match exactly one dump entry and the exact count.
- *Authorization:* approved by the Owner, 2026-11-27: no additional descriptors, removals or privilege expansion; any deviation is escalated.
- *Evidence:* the isolated test passing on the exact head; Main checks the six lines against the PR's `pg_restore -l` listing.

**D-c: parity check (`supabase/tests-isolated/wpd18_parity.sql`).**
- *Original:* the fingerprint covers 4 tables and 7 functions in exactly 67 lines; the state section covers headers, items, resolved scope and totals.
- *Replacement (approved):* add `'private.billing_package_scope_eligibility'::regclass` to the table set; add its `select` and `insert` privileges to the privilege row; add a `state` row listing eligibility events. The fingerprint line count becomes the **measured** value.
- *Original guarantee:* source and copy are byte-identical for the tested objects and state.
- *Replacement guarantee:* the same, including the eligibility table.
- *Exposure:* the projection of 83 lines is not an acceptance value (Owner).
- *Compensating coverage:* Main independently verifies the actual count and that every added fingerprint line belongs to the authorized eligibility-table change.
- *Authorization:* approved by the Owner, 2026-11-27.
- *Evidence:* the isolated test passing on the exact head; Main's line-by-line check of the added fingerprint lines.

**Consolidated Owner decisions record (Owner, 2026-11-27; Main):** the Owner's "Consolidated Owner Decisions & Implementation Authorization". Grants and amendments are in AUTHORIZATIONS; each takes effect on this record's verified merge (OM-1). Baseline `main` at `8ebcced`.

| Item | Record |
|---|---|
| AUTH-017 completion | PR #53 merged under OM-6(b) at `8ebccedbadc40e5e9d6997810225ec2b159e69cc` (parents `e67bddd`, `186d728`; tree identical to the reviewed head); exact-head CI 46060779579 7/7 with the full suite (the earlier "CI result" failure was run 46060553913 on the superseded head `80a7786`, cancelled by the synchronization); reviews Main 7227098117 and WP-C 7227207833, none blocking; post-merge CI 46062083448 7/7 with the full suite. **AUTH-017 completed; OI-88 closed** (§21) |
| Item 1: AUTH-019 | Granted as proposed (OI-120): the `private.is_owner()` root-function correction only, DEP-18 session, migration `20261127125000`, pgTAP `420`; reviews WP-C, WP-B and Main; OM-6(b); with the Owner's additional verification requirements. OI-120 blocks hosted migration deployment under AUTH-003 and R1 release-candidate acceptance |
| Item 2: AUTH-010 Amendment 1 | OI-121 option A: the per-refund charge.refunded dedupe key; refund-event keys preserved; cross-event and arrival-order non-duplication verified; anything beyond escalated |
| Item 3: AUTH-010 Amendment 2 | I-3 option A: `financial_conflict.decision_refused` (04 v0.10.4) |
| Item 4: AUTH-015 Amendment 1 | M-1 option B: the recovery bypass is closed inside AUTH-015 before merge (PR #54) |
| Item 5: Stage A attempt 3 | Key creation only is authorized (`SLM-AUTH-002-STAGE-A-20261127-03`, `acct_1UexHZK5j4r4WkVP`, Balance, Prices and Products Read, everything else None). **Not authorized:** credential entry, Stripe requests or execution, until the attestation, the Gate A record and fresh baseline, the acknowledgments and Main's activation notice. Readiness verified by Main: the attempt 3 amendment merged (PR #52, `e67bddd`) with post-merge CI 46059931020 7/7; Main's copy of `stage_a_runner.py` hashes to the accepted `5094817a…`; the environment holds no network secret |
| Item 6 | Independently authorized work continues with no global pause; decisions are relayed to the implementation sessions |
| Open reviews | PR #54 (AUTH-015; Main 7227401266, M-1 now decided); PR #55 (AUTH-016; Main 7227478327, no blocking finding, corrections R-1 and R-2) |

**AUTH-002 Stage A attempt 3 Gate A record (2026-11-27; Main; not active):** the consolidated record the attempt 3 amendment (AUTHORIZATIONS AUTH-002, "Stage A: attempt 3 amendment" (5)) requires. It authorizes no credential entry and no Stripe request. Main notifies the Owner when secure credential entry is authorized.

*Owner attestation, verbatim (message of 2026-11-27, "Owner Attestation — AUTH-002 Stage A Attempt 3"):*

> 1. I personally created the new restricted credential on November 27, 2026, at approximately 15:20 EST (20:20 UTC). The recorded time is approximate.
> 2. The credential was created within the dedicated private Stripe sandbox, Spotlight Client Portal - Development, account ID acct_1UexHZK5j4r4WkVP. I verified its account association and confirmed it is not listed in the separate Setmore sandbox.
> 3. The credential has the restricted test-mode prefix rk_test_.
> 4. The only granted permissions are Balance — Read, Prices — Read and Products — Read. All other permissions are None, with no Write permissions.
> 5. The credential is newly created and uniquely named SLM-AUTH-002-STAGE-A-20261127-03. Its request logs show zero requests.
> 6. I have not disclosed the credential value in chat, committed it to a repository or entered it into any execution environment. I will enter it only through the authorized secure credential form after Main's activation notice.
> 7. I understand Main must verify that exactly one authorized api.stripe.com network credential exists before execution, without inspecting or exposing its secret value.
> 8. I understand that any discrepancy leaves Gate A unmet. No Stripe requests or execution are authorized until all prerequisites are satisfied and Main issues the explicit activation notice.

| Gate A prerequisite | State |
|---|---|
| Amendment merged; post-merge CI | **Met:** attempt 3 amendment in PR #52 at `e67bddd` (post-merge CI 46059931020 7/7); key creation authorized by the Owner (consolidated decisions, item 5; this record's PR) |
| Sandbox identity, amendment (1) to (3) | **Met:** point 2 names the sandbox **and** account ID `acct_1UexHZK5j4r4WkVP`, matching the Owner's sandbox identification; the key is confirmed in that account and not in "Setmore [Test mode]" |
| Credential attestation, points 1 to 8 | **Met for points 1 to 6.** Key `SLM-AUTH-002-STAGE-A-20261127-03`, new and unique, zero requests in its request log before entry. Point 4's labels match the labels the Owner confirmed from this sandbox's Dashboard on 2026-11-26; no naming or grouping difference. Point 7 is verified by Main after entry (exactly one `api.stripe.com` credential, by names only). Point 8 stands. Before entry, Main verified by names that the environment has no Network secret and no `api.stripe.com` allowed host (2026-11-27T20:30Z) |
| Evidence limitation (f), point 1 | The creation time is approximate (about 20:20Z, Owner-reported). Main cannot verify it, nor its order relative to the Owner's written creation authorization, which Main received a few minutes after 20:20Z. The key is the Owner's own Dashboard action under the Owner's own decision; its freshness rests on the zero-request log (point 5) and the unique name. Recorded, not treated as a discrepancy; the Owner may correct it |
| Runner | **Met:** revision 4, SHA-256 `5094817abbebd4f9c97144b8562f682cd3f5254ecabfa24e98b72eb16cc310ca`; Main's copy re-hashed 2026-11-27; WP-B reconfirms its copy in its acknowledgment |
| Reconciliation and cleanup | Unchanged: per-key "View request logs" in the Workbench of `acct_1UexHZK5j4r4WkVP` (amendment (4)); a request in any other account blocks successful closure. Cleanup order: Network secret and allow rule, request log, key expiry |
| Execution baseline | **`main` at `8ebccedbadc40e5e9d6997810225ec2b159e69cc`**, post-merge CI 46062083448 7/7, plus this documentation-only record. No catalog migration and no 04 §6.1 or §6.5 change since `e67bddd`. At activation Main re-verifies `main` |
| No other Stripe operation in progress | **Met** (Owner, "Consolidated Owner Directive", 2026-11-27): "I confirm that no other Stripe operation is currently in progress under my control." |
| Execution go-ahead naming the session and environment | **Given** (Owner, same message): "I designate WP-B as the sole authorized executor of Stage A attempt 3, subject to all established Gate A prerequisites and activation requirements." WP-B is `session_01RCnsL4vnvrx7b11HRxeo8T`; the environment is `spotlight-client-portal-dev`, fixed by the carried-forward credential mechanism (the only environment holding the Network secret). The Owner also directed that the frozen runner, the verified sandbox identity, the read-only restrictions, the request ceiling, the single-execution limit, independent reconciliation and credential cleanup be preserved |
| Acknowledgments from every other active session (control 1) | **Collected by Main immediately before the activation notice**, recorded with session IDs and UTC times |
| Secure credential entry | **Pending** Main's activation notice: Network secret on `spotlight-client-portal-dev`, host `api.stripe.com`, Bearer, path prefixes `/v1/balance`, `/v1/products`, `/v1/prices` |

**AUTH-002 Stage A attempt 3 execution and closure record (2026-11-27; Main): PASSED; Stage A completed.**

| Item | Record |
|---|---|
| Activation and credential | Activation notice (secure entry authorized) at 20:53Z; Owner "credential entered"; at 20:56:28Z Main verified by names exactly one Network secret (host `api.stripe.com`, header `Authorization`, label "api.stripe.com/v1/balance") and unchanged allowed hosts (point 7). Execution go-ahead to WP-B at 20:56Z on baseline `208d7e7` |
| Delay before execution | WP-B's session reached the account usage limit at 20:59:10Z, before issuing the run (Main confirmed from its transcript: no `--execute`). The limit reset at 22:20Z; Main re-verified the baseline and the single credential at 22:29Z and WP-B resumed. The credential stayed on the environment, unused, in the interval; the control-1 acknowledgments remained in force |
| Execution | One run, unchanged (accepted revision 4, `5094817a…`): `python3 -I stage_a_runner.py --execute --baseline 208d7e7475ddbb5d81ac87453bff53cf2e42396c --out <outside any Git work tree>`. Runner fields: run ID `stageA-20261127T223034Z-44a150dd`; `mode` EXECUTE; `overall` **PASS**; `stop_condition`, `internal_error` and `signal` null; exit status 0; `request_count` **25** (ceiling 30); `start_utc` 22:30:34Z; `end_utc` 22:30:38Z; `api_version` `2026-09-30.endive`; `execution_baseline` `208d7e7`; no-write confirmation ("GET only: the request function refuses every other method before it is counted or sent; no request body, no idempotency key and no write endpoint was sent") |
| Baseline note | Main merged PR #54 (AUTH-015, publication recovery only) at 22:31Z, while the run was pending. It has no catalog migration and no 04 §6.1 or §6.5 change, so the baseline stayed `208d7e7` (as in attempt 2) |
| Requests (runner) | 1: `GET /v1/balance` (`livemode` false); 2–12: `GET /v1/prices/<id>` (11); 13–23: `GET /v1/products/<id>` (11); 24: `GET /v1/prices?active=true&limit=100`; 25: `GET /v1/products?limit=100` |
| Evidence file | `stage-a-attempt3-evidence.json`, 15,805 bytes, SHA-256 `50db31c035046b966afc7e5d3b67ca5c52c9b9b55f52b5d83bb815a533b7602d`, mode 0444, held by WP-B outside Git; contains no headers, key material or customer data |
| Owner cleanup | Owner confirmation (2026-11-27): the `api.stripe.com` Network secret removed; its allow rule removed; the key `SLM-AUTH-002-STAGE-A-20261127-03` expired. Main verified by names at 23:22:11Z: no Network secret; allowed hosts exactly `github.com`, `api.github.com`, `registry.npmjs.org`, `nodejs.org`, `docs.stripe.com`, `pkg-containers.githubusercontent.com`; no `api.stripe.com` |
| Workbench reconciliation (Owner, account `acct_1UexHZK5j4r4WkVP`) | 25 key-specific requests, all GET, 25 HTTP 200; balance 1, price retrievals 11, product retrievals 11, price list 1, product list 1; writes 0; failures 0; first 22:30:35Z, last 22:30:38Z; API version `2026-09-30.endive`. **Reconciles with the runner** (count, methods, paths by class, window 22:30:34–22:30:38Z, API version) and with amendment (4) (the dedicated sandbox's account): no discrepancy |
| Duplicate detection (runner, pass) | Prices: `COMPLETE`, 11 listed; for each of the 11 catalog keys exactly one active price, equal to the only active price on its product, with the ID below (`unique` true). Products: `COMPLETE`, 11 listed; for each key exactly one active product with the ID below, `inactive_products` empty (`unique` true) |
| Evidence limitations | (a) The cleanup times (secret removal, allow-rule removal, key expiry) were not recorded by the Owner; none is invented here. (b) The Network secret's path prefixes are not visible to Main (labels only, as in attempts 1 and 2). (c) The runner records most checks as booleans, not observed values (except `unit_amount` and the `recorded` flags). (d) Limitation (f) of the Gate A record (approximate creation time) stands. (e) The proxy's internal allow rule is not directly visible to Main; its removal is Owner-reported and the allowed-host list is verified |
| Closure | **Stage A completed: PASSED.** The 11 test-mode Products and 11 test-mode Prices recorded in 04 §6.5 are re-verified against 04 §6.1 in the dedicated sandbox: every object `livemode` false, every runner check true, every ID and unit amount equal to 04 §6.5 (Main cross-checked all 22 IDs and the 11 amounts against 04 §6.5 and the catalog migration). Stage A is not reactivated without a new amendment. Main announces closure to every acknowledging session; WP-B keeps the evidence unchanged. The rest of AUTH-002 (the broader sandbox scope) stays **not active** |

*Per-object results (runner fields; no headers, key material or customer data).* Every price row: `livemode` false; checks `product`, `currency`, `unit_amount`, `active`, `type` and `recurring_interval` true; `tax_behavior` `unspecified`; `lookup_key_matches` true. Every product row: `livemode` false; `active` true; `name_matches` and `metadata_catalog_key_matches` true.

| Catalog key | Price ID | `unit_amount` (recorded = expected) | Product ID | Result |
|---|---|---|---|---|
| `essential.deposit` | `price_1Uf5HxK5j4r4WkVPkRUJ4gnZ` | 16000 | `prod_VgKrmaWefVnWy1` | pass (price and product) |
| `essential.balance` | `price_1Uf5HyK5j4r4WkVPfrkvOv7h` | 64000 | `prod_VgSCAxhfEGdaad` | pass (price and product) |
| `professional.deposit` | `price_1Uf5HyK5j4r4WkVPOtk24lGw` | 29900 | `prod_VgSCeNeWEAgD5n` | pass (price and product) |
| `professional.balance` | `price_1Uf5HzK5j4r4WkVPRH6Wkz6D` | 119600 | `prod_VgSCfdhERuVy2D` | pass (price and product) |
| `advanced.deposit` | `price_1Uf5HzK5j4r4WkVP35jgGOiy` | 49900 | `prod_VgSC96cbyhUzC9` | pass (price and product) |
| `advanced.balance` | `price_1Uf5I0K5j4r4WkVPZLs7eS9w` | 199600 | `prod_VgSC3IZmhX2qpb` | pass (price and product) |
| `signature.deposit` | `price_1Uf5I0K5j4r4WkVPW6smdGo2` | 69900 | `prod_VgSCeFVATAQD5p` | pass (price and product) |
| `signature.balance` | `price_1Uf5I1K5j4r4WkVPB0lY2MgL` | 279600 | `prod_VgSCqRM6FGup6G` | pass (price and product) |
| `prestige.deposit` | `price_1Uf5I1K5j4r4WkVPyCBIiYGP` | 99900 | `prod_VgSCyf8mCcu9mc` | pass (price and product) |
| `prestige.balance` | `price_1Uf5I1K5j4r4WkVPDvIUmRD9` | 399600 | `prod_VgSCGIcK8EA2g5` | pass (price and product) |
| `maintenance.monthly` | `price_1Uf5I2K5j4r4WkVPJodSnaBe` | 9900 | `prod_VgSCHvgDEvac7A` | pass (price and product) |

**Consolidated completion record (2026-11-27; Main):** AUTH-015 completed (PR #54 at `b5d8078`; post-merge CI 46077031048; OI-114 closed); AUTH-010 completed (PR #59 at `30ee417`; post-merge CI 46080015419; OI-93 and OI-121 closed); AUTH-002 Stage A completed (record above). Details in AUTHORIZATIONS "Completion" rows and §5. Open at this record: PR #55 (AUTH-016, the Owner's allowlist decision), PR #57 (AUTH-018, synchronization and the integration re-runs), AUTH-019 (DEP-18 session, awaiting a push branch).

**AUTH-018 and AUTH-019 completion record (2026-11-28; Main):** PR #57 (AUTH-018) merged at `23346ef` (exact-head CI 46084394471 7/7; post-merge CI 46085126236); PR #61 (AUTH-019) merged at `19b173b` (exact-head CI 46085906358 7/7; post-merge CI 46086549947): **OI-120 closed**, no longer blocking hosted migration deployment or R1 release-candidate acceptance. 04 v0.10.5 marks §4A interim loading and §15.2.1 rule 10 as implemented. Opened: **OI-122** (AUTH-009 test helper race; test-only fix proposed) and **OI-123** (AUTH-016 × AUTH-018 test 330 classification disagreement; setup-only additions proposed with the PR #55 allowlist change); both await the Owner. AUTH-003 gains a migration-order note. Informational: WP-B's `20261124160100`:3712 note (AUTHORIZATIONS AUTH-019 "Completion"). Open at this record: PR #55 (AUTH-016).

**AUTH-016 completion and AUTH-020 grant record (2026-11-28; Main):** PR #55 (AUTH-016) merged at `b294d33` (exact-head CI 46088750091 7/7; post-merge CI 46089426391), with the Owner's two approved FD-14 changes verified byte-identical to the reviewed diffs: **OI-115 (local part), OI-119 and OI-123 closed**. AUTH-020 (OI-122, test-only) granted by the Owner exactly as proposed, with acceptance A1 to A7 (AUTHORIZATIONS AUTH-020). Every granted R1 implementation package is now merged; per the Owner, no further major implementation wave starts before the milestone assessment that follows AUTH-016 and AUTH-020.

**AUTH-020 completion record (2026-11-28; Main):** AUTH-020 activated on the verified merge of PR #63 (`8107841`; post-merge CI 46091035098). PR #64 (WP-B) merged under OM-6(b) at `2ae3639` (head `d2b986a`, base `8107841`; tree identical; exact-head CI 46094951319 7/7; post-merge CI 46103910059). The patched file is `27d324b0…` from the base `bd596cff…`, the 70 assertions are unchanged, and A1 to A7 are met (§27). WP-I's independent review and Main's final review found nothing blocking. **OI-122 closed.** The non-blocking notes are in AUTHORIZATIONS AUTH-020 (Completion).

**Milestone acceptance record (2026-11-28; Owner directive "Milestone Acceptance and Next Development Wave"; Main):** the Owner acknowledged the verified completion of AUTH-016 and AUTH-020 and the closure of OI-122, and accepted **`59b9aac`** as the milestone baseline (post-merge CI 46104833504 with the full suite). §3, §6 and §7 were corrected under Tier 0. **Diff-hash verification limitation (Owner, 2026-11-28):** the approved diff SHA-256 `3675e8f8…` is as reported by WP-B and was **not independently verified** by Main or WP-I, because it depends on the exact patch formatting and is not reproduced by `git diff` (which gives `492b0423…`). It is not represented as independently verified. The independently verified evidence is the base file SHA-256 `bd596cff…` on `8107841` and the patched file SHA-256 `27d324b0…` on `2ae3639`, which together determine the change exactly. The Owner authorized read-only investigation and the preparation of readiness-complete grant packages for PWP-1, PWP-2 and PWP-5, a consolidated Owner action checklist for AUTH-003, the rest of AUTH-002 and the vendor accounts, and a commercial-readiness inventory. **No implementation authority, real contractual content loading, provider operation or production activation is granted.**

**PWP investigation record (2026-11-28; Main; read-only, under the milestone directive):**
- **Investigation:** four read-only investigations covered the PWP-1, PWP-2 and PWP-5 specification requirements, the implementation surfaces on `main`, the Owner provider checklist and the commercial-readiness inventory. No file was changed by them and no provider was contacted.
- **New open issues:** conflicts and gaps were recorded under CLAUDE.md §2 as **OI-124** (contractual lock order), **OI-125** (fixture bundles versus staging verification), **OI-126** (the DEP-03 release-candidate gate), **OI-127** (AUTH-003 execution prerequisites), **OI-128** (the rest of AUTH-002) and **OI-129** (PWP specification gaps). All await the Owner.
- **Status corrections:** 04 v0.10.6 and the DEP-18 row.
- **For Owner review:** the next-wave execution plan and the readiness-complete grant packages. Nothing is granted.

**Contractual architecture wave grant record (2026-11-28; Owner directive "Contractual Architecture Implementation Wave"; Main):**
- **Decisions:** the Owner approved OD-1 to OD-19 exactly as recommended (08) and granted AUTH-021 (PWP-1), AUTH-022 (PWP-2), AUTH-023 (PWP-5a) and AUTH-024 (PWP-5b), Tier 1, exactly as presented, with verification requirements A to F (AUTHORIZATIONS).
- **Spec change:** 04 §4A v0.11.0 records the canonical lock hierarchy (OD-3), including the timing of acceptance's implicit foreign-key lock.
- **Open issues:** OI-125 and OI-126 are closed as decided. OI-124 and OI-129 are decided and stay open until implemented. OI-127 and OI-128 stay open.
- **Effective:** on the verified merge of this record and its post-merge CI (OM-1). Main then dispatches: AUTH-021 (DEP-18 session); the AUTH-022 test-only preparation (WP-B); AUTH-023 (WP-C).
- **Not authorized:** real or counsel-derived content, hosted operations, staging or production eligibility, production activation or provider execution.

**Test-disposition batch record (2026-11-28; Main):**
- **Owner decisions:** the Owner approved B-1a to B-1c (050 additions), B-2 (D-1 to D-9; D-4 conditional, D-8 coordinated) and B-3 (the AUTH-022 T-SALES-31 correction), with four verification clarifications (08; the AUTHORIZATIONS dispositions rows).
- **Main rulings within OM-4:**
  - the PWP-1 interface freeze F1–F5, approved 05:05Z;
  - AUTH-021 Q1–Q8, including the T-CON-11 split: PWP-1 provides the staff reader and the negative half, PWP-2 the positive client reader as a new object;
  - the OD-8 mapping: limits checked at bundle sealing and in verification, with the scope-version level covered by the WP-S constraints and the `order_summaries` 8,192-byte check;
  - AUTH-023 Q1–Q3.
- **PR #69 (AUTH-021, head `d9b6dce`):**
  - reviews by WP-B and WP-I, with no blocking findings;
  - CI run 46111723026 failed only on 050 test 8, which B-1a resolves. The isolated, integration and e2e CI stages did **not** run and are not treated as verified. AUTH-016 and AUTH-020 are both verified complete, so the Owner's milestone checkpoint is reached: the comprehensive milestone assessment comes next, and no further major implementation wave starts before it.

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
| PWP-1 Contractual instruments, bundles, governance events | Required | **Authorized: AUTH-021** (2026-11-28) |
| PWP-2 Standardized issuance and snapshot v2 | Required | **Authorized: AUTH-022** (2026-11-28); core after the PWP-1 interface freeze; merges after AUTH-021 |
| PWP-3 Counsel and publication evidence | Required | Not authorized; needs final publication artifacts |
| PWP-4 Non-production materialization and verification | Required | Not authorized; needs PWP-2, PWP-3, AUTH-003 |
| PWP-5 Scope confirmation, operational notes, inactivity reconciliation | Required | **Authorized: AUTH-023 (PWP-5a) and AUTH-024 (PWP-5b)** (2026-11-28; OD-1 split; 5a in parallel with PWP-1, 5b after 5a merges) |
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

### 17E. D-1 ratification (Owner, 2026-11-25)

**Decision (Owner, 2026-11-25, relayed by Main; quoted):**

> **D-1 is RATIFIED by the Owner** as implemented and reviewed: the exact-filename exemptions, the stricter lexical detection, the mutation evidence and the disclosed residual limitations. The static guard is accepted as defense in depth, not as an exhaustive SQL security boundary. The database construction guard remains the authoritative runtime enforcement. The ratification is recorded separately from the merge authorization, and the residual limitations must stay in the durable record. No further D-1 implementation or review is needed.

> **PR #27 is approved in principle.** The final pinned merge authorization waits for the exact new coordinates.

This supersedes the "D-1 remains unratified" statements in §17A to §17D, which are kept as the record at the time. The Owner's decision record is in 08, which Main maintains. This section grants no merge authority.

**Evidence:**

| Item | Reference |
|---|---|
| Corrected D-1 check: exact-filename exemption, compensating controls, mutation tests | `d2077d2` |
| Stricter lexical rule (option (a), PR #34): three exact-name exemptions, quote-aware comment stripping, mutation tests | `1508ede` |
| Main's independent implementation review at `41c5978` | PR #27 comment 7173468443 |
| WP-B review at `41c5978` | PR #27 comment 7173416670 |
| Exact-head CI at `41c5978` | Run 45691819713 (#125), 7/7, F1 25/25 |

**Residual limitations (kept in the durable record, as the decision requires).** The static check is lexical. It does not recognize:
- table names assembled from fragments, for example by string concatenation in dynamic SQL;
- names built with `chr()` or `format()`;
- Unicode-escape identifiers (`U&"…"` with `\XXXX` escapes; Main's observation in 7173468443).

The runtime construction guard on `private.billing_package_scope` rejects every such insert outside the constructor. It remains the authoritative control.

**Synchronization.** This section was added with the documentation-only merge of `main` at `19f6103` (PR #36). No implementation or test file changed: the non-documentation diff against `main` is patch-identical to `41c5978` against `30414c7` (`git patch-id --stable`).

**Effort (OI-67):** AI session about 0.2 h; Owner: none.

## 18. WP-C OI-113 implementation record (AUTH-013)

Implemented by the WP-C session on `wp-c/oi-113-approval-identity`, from the verified `main` at `19f6103385dd8778f449fdacae35add01ea0785a`. §17 is reserved by PR #27.

**Entry (verified read-only):**
- AUTH-013's activation conditions hold:
  - PR #35 merged at `30414c7`, post-merge CI run 45689577718;
  - the grant record (PR #36) merged at `19f6103`;
  - post-merge CI run 45694804255 on `19f6103` completed `success`.
- `git diff --name-only 30414c7 19f6103` lists only `.md` files.
- Migration `20261127110000` and pgTAP file `235` were unused.
- Main confirmed the documentation scope:
  - "the interface definition" is 05 §7, the "Gate rule" row;
  - OWNER-RUNBOOKS and OPEN-ISSUES are outside the file list. Main records the option (c) runbook entry and the OI-113 closure separately.

**Change (files exactly as authorized):**

| File | Change |
|---|---|
| `supabase/migrations/20261127110000_wpc_oi113_authoritative_approval.sql` | `create or replace function private.project_fulfillment_status`. Only the approval selection changes: the approval named by the canonical event, under the six conditions, with no fallback. Every other line is byte-identical to `20261124140200` (`diff` shows only that hunk). The file has no DML, grant, revoke or schema statement. SHA-256 `eed29d43c5710523be3825e92c0e4753e6d7e693d42ebf99ebff7856140d5c35` |
| `supabase/tests/235_wpc_oi113_approval_identity.test.sql` | New, 67 assertions (below) |
| `tests/integration/wpc-oi113-approval-race.test.ts` | New, 3 tests (below) |
| `supabase/tests/120`, `130`, `150`, `160` | Moves 1 to 4: the same `pg_temp.genuine_release_approved` text in all four, following the fixture-integrity rule. Only a genuinely new first approval emits the canonical key; a canonical event is never fabricated, replaced or repaired. The helper raises unless (a) the canonical event is consistent and (b) the interface reports the release and approval as current. Plans and assertions are unchanged |
| `supabase/tests/150_wpb_jobs_evidence.test.sql` | Move 5: the direct emission's key `'release.approved:t150'` becomes `'release.approved:' \|\| <rel>` |
| `tests/integration/wpb-billing.test.ts` | Move 6: the first emission uses `` `release.approved:${rel.id}` ``. The unchanged `current` query and `expect` follow it; the second emission keeps `` `release.approved:${RUN}:2` `` |
| `docs/05-PROJECT-LIFECYCLE-AND-UPLOADS.md` | v0.5.2: the §7 "Gate rule" row (**[APPROVED OI-113]**) |
| This section and 08 | The record |

**Unchanged:**
- WP-H's cross-check and its equality rule;
- `approve_preview`, `release_preview`, `withdraw_preview`;
- every WP-B and WP-S function;
- `src/domain/contracts/gates.ts`, 01 §7, the seed, dependencies and workflows.

**Why the moves are needed:** the four helpers as they stand at `19f6103`, run against the new migration, fail closed, each at its first release: 120, 130 and 160 raise `fixture: release … is not WP-C current`, and 150 reports 4 failures. The rule is doing its job; the old fixtures never wrote the canonical event.

**pgTAP 235 (67 assertions, one rolled-back transaction).** Projects are paid through the real WP-B workflow and use WP-C's real intake, `release_preview` and `approve_preview`. States WP-C never produces are labelled SYNTHETIC.

| Case | Expectation verified |
|---|---|
| R1, RP | The `approve_preview` approval is current, equals the canonical event's `approval_id` and passes G3. A second client's approval and a repeat approval emit nothing and change nothing. The consumer returns `created` (1/1/1/1, as below); a replay returns `already_consumed` and adds nothing |
| R2 (B-1) | Client B's approval has the earlier `approved_at`; the interface still reports the canonical approval A |
| RA (F-1, refinement A) | A well-formed non-canonical event naming B's approval is consumed **before** any obligation exists: `rejected` / `approval_mismatch`, audited and notified, 0/0/0/0. The canonical event then returns `created`, with exactly one obligation, for A |
| R3, R4 / C1 | An approval without a canonical event, and then with only a non-canonical one, is not approved (`false:null`); G3 fails `release_not_approved`. Consumption: `rejected` / `approval_mismatch`, audited and notified, 0/0/0/0 |
| R5 | A later non-canonical event naming another approval never changes the identification |
| C2 to C6c | A canonical-key event failing exactly one condition: another event type; another subject type; another subject; another project; an approval of another release; an approval row of this release recorded under another project; and an unrecorded, missing or non-UUID approval. Each case: not approved, G3 fails, the defective event rejected, a well-formed non-canonical event rejected `approval_mismatch`. Together: 18 rejections, each audited and notified, with 0/0/0/0 |
| W, S | Withdrawal and supersession are unchanged. A superseding release is not approved until its own `approve_preview`. The superseded release's event is rejected with `release_superseded` |
| H1 to H5 | The helper raises: **H1** for a missing canonical event (and fabricates nothing); **H2** for one naming another release's approval, or belonging to another project (check (a)); **H3** for the reserved key; **H5** when the interface does not report the release as current (check (b)). **H4:** a new first approval emits exactly one canonical event; a re-delivery keeps its non-canonical key |
| G | `approve_preview` is the only database function that emits `release.approved`. Only `emit_domain_event` inserts into `domain_events` |
| RD (refinement D) | Events, consumptions, approvals and publication evidence keep their guard triggers. The interface is `STABLE` (it cannot write, replay or re-emit). A consumed event's outcome is unchanged |
| X | The composite attributes, the ACL (no API role) and `contract_version` 2 are unchanged |

1/1/1/1 is one `final_balance_invoices` row, one `final_balance_invoice_create`, one `payment.balance_due` and one `balance.collection_authorized`; 0/0/0/0 is none of each.

**Invariant, documented rather than manufactured:** `dedupe_key` is unique (asserted from the catalog), so two canonical events for one release cannot exist.

**Race test (refinement A2, acceptance 2 and 3).** Each repetition uses a fresh project paid through `createPaidProject`, client B as a second member, and WP-C's real intake and `release_preview`. Two `pg` connections run WP-C's real `approve_preview`, then WP-H's real consumer runs.
- **Inverted order, 20 repetitions:** B begins first; 50 ms later A approves and commits; then B approves. The test asserts B's `approved_at` is earlier, so the inversion happened.
- **Natural order, 20 repetitions:** A approves and holds the lock. B is observed waiting on `Lock` in `pg_stat_activity`. A commits, then B completes.
- **WP-C's original reproduction** (PR #35 comment 7168769499; B begins and A approves 200 ms later): returns `created`.

Every repetition asserts:
- exactly one `release.approved` event, with the canonical key, naming the first-locked approval;
- the interface names that approval;
- the consumer returns `created`, with 1/1/1/1;
- no 40P01, and no other database error.

Created requests are settled through the executor afterwards.

**Mutations (refinement B; scratch copies of 235 inside its rolled-back transaction, and a temporary function replacement for the race test, restored from the migration file afterwards). Every mutation is caught:**

| Mutation | Fails |
|---|---|
| (1) key condition removed | R4 / C1 and C2 to C6 (15 assertions) |
| (2) event type removed | C2 |
| (3) subject type removed | C3 |
| (4) subject removed | C4 |
| (5) project removed | C5 (and H2's project variant) |
| (6) the approval's release removed | C6a |
| (6) the approval's project removed | C6b |
| (6) the approval join replaced by a direct cast | C6a, C6b, C6c, then a cast error on the non-UUID |
| `approved_at` ordering restored | R2, RA, R3 and 24 more in 235; the race test's inverted order and the reproduction (natural order passes, as expected) |
| Timestamp fallback added | R3, R4 / C1, C2 to C6 (20 assertions) |
| Helper check (a) removed | H1 and both H2 variants |
| Helper reserved-key guard removed | H3 |
| Helper emits the canonical key for existing approvals | H1 (it would repair the missing event), H2, H3, H4 |
| Helper check (b) removed | H5 |

**Suites (local, fresh `supabase db reset`, Supabase CLI 3.2.0, CI order):**

| Command | Result |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 17 files, 303 passed (unchanged) |
| `pnpm audit --audit-level=high`; `./scripts/check-migrations.sh origin/main` | No known vulnerabilities; no merged migration changed |
| `supabase db reset`; `./scripts/run-db-tests.sh` | 31 files, 1,672 assertions, all pass (main: 30 files, 1,605; plus 235's 67; every existing file's plan unchanged) |
| `pnpm test:integration` | 8 files, 99 passed (main: 7 files, 96; plus the race file's 3) |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` | 52 passed (unchanged) |
| Lighthouse | Not run locally; runs in CI |

Remote CI for the exact head is recorded in the pull request.

**Reviews required (AUTH-013):**
- an independent WP-C-domain review by a session other than WP-C;
- a WP-B read-only review of the consumer integration;
- Main.

Each is a durable non-approval record. WP-C does not merge. OI-113 closes only on the verified merge and its post-merge CI.

**Effort (OI-67):** AI session about 1.5 h; Owner review: none yet; administrative about 0.1 h (two documentation-scope questions to Main).

## 19. WP-I I-2 implementation record (AUTH-008 I-2)

Implemented by the dedicated integration session (`https://claude.ai/code/session_01RCnsL7k3rDKjjpTicExTsF`; not Main) on `wp-i/r1-e2e`, from the verified `main` at `9e8569c` (PR #41; I-2 active on PR #40's merge at `2d27d07` with post-merge CI run 45731539779, 7/7, verified by this session). Section number appended per OM-5; Main may renumber at merge if another record takes §19.

**Scope (AUTHORIZATIONS AUTH-008 "I-2 grant", "I-2 carried-forward dispositions", "I-2 scope decisions"):**

| Item | Files | Change |
|---|---|---|
| T-E2E-01 to T-E2E-10 | `tests/e2e/r1.spec.ts` (new) | One Sales-assisted journey on a fresh customer: Sales customer, order summary and invitation; Mailpit invitation and email-code sign-in; agreement; Checkout (intercepted) and a signed `checkout.session.completed`; card; intake save, resume, changes requested, resubmit, accept; uploads (clean, EICAR-flagged, content mismatch, guessed URL); releases (superseded release refused, double submission gives one approval); final balance through the billing-job runner (one invoice and one charge; an `invoice.payment_action_required` shows the hosted link and keeps G4 failing; `invoice.paid` verifies); QA, security and domain evidence and the derived admin queue; Owner authorization with fresh reauthentication, deployment record and live verification (matching build verified; mismatched build fails with an incident); role separation; console errors. Every step asserts the database state and audit events; counts are scoped to the run's fresh IDs (disposition (iv)). A second fresh project for client B proves T-E2E-02's "verified deposit without a reusable card leaves intake locked" (its Checkout is recorded through the real WP-B functions, so the server's card lookup finds none) |
| Seam (a) billing-job runner | `tests/support/billing-job-runner.ts`, `.job.ts`, `.config.mts` (new) | One pass of the existing `runBillingJobs` in a Vitest subprocess with the in-memory mocked gateway. Affirmative `development`/`test` only; local stack only; refused with a Stripe credential present |
| Seam (b) mock live verifier | `src/server/publication/verifier.ts` (+38: `mockLiveFetch`, `verifierFor`); `src/server/services/fulfillment.ts` (**exactly 2 lines**: the l.7 import and the l.98 call `verifierFor(env.APP_ENV)(deployment.production_url)`, confirmed within P-1 by Main) | The stub answers only for reserved `.test` hosts and serves the build ID from a 40-hex first host label; every classification other than an exact `development` or `test` selects the unchanged real verifier |
| Isolation evidence | `tests/unit/wpi-live-verifier.test.ts` (20), `tests/unit/wpi-billing-job-runner.test.ts` (19, including the static check that nothing under `src/` imports the runner or any `tests/support` module), `tests/e2e/production-gating.spec.ts` (+1 test: the production build contains neither the runner nor any test-support module) | Mutations caught: 8 of 8 (preview allowed, case-insensitive match, any host served, `.test` without the dot, staging allowed, host check skipped, Stripe key allowed, `pg` version changed) |
| Fail-closed paths | `supabase/tests/400_wpi_r1_fail_closed.test.sql` (new, 33), `tests/unit/wpi-scanner-fail-closed.test.ts` (new, 12) | Publication blocked by an unconsumed approval (G4 is the only failing gate, the Owner's authorization is refused and audited, consumption alone does not unblock); `no_usable_agreement_version` in a production-classified database; agreement of `private.runtime_environment` and `private.environment_settings` and their fail-closed absence; `scannerFor` outside development and test |
| Disposition (i) | `tests/support/rpc.ts` (`selectOk`), `tests/integration/wpc-uploads.test.ts`, `tests/integration/wpc-delivery.test.ts` | The six non-RPC reads report the PostgREST error. `expect(` counts unchanged (42 and 70); no assertion line in the diff; storage-denial checks unchanged |
| Disposition (iii) | `tests/unit/wpi-pg-version.test.ts` (new, 3) | Fails unless the resolved and pinned `pg` is 8.16.3 and `connection.stream` exists; a change requires explicit re-verification, not a freeze |
| Dispositions (ii), (v) | none | Recorded only (WP-C O-2; the 19.9 s PostgREST startup observation) |
| Authenticated Lighthouse (P-2) | `lighthouserc.json` (one assertion entry; collect URLs unchanged), `.github/workflows/ci.yml` (Lighthouse job only), `tests/support/lighthouse-auth.mjs` (new) | Public pages keep their signed-out collection and thresholds. The script signs the seed client in with Playwright (email code from local Mailpit, never logged), checks each page (HTTP 200, own route, page-specific content; stop condition otherwise), hands the session in memory to a separate Chrome on 127.0.0.1 only (temporary profile, deleted), runs `lhci collect --additive` for the three pages, and verifies every report (runs per page, own route, HTTP 200, no token, cookie name or profile path). The Job runs four steps without `if:`: collect public, the auth script, `lhci assert`, `lhci upload`. The LHCI `puppeteerScript` first proposed needs a `puppeteer` dependency (not resolvable under pnpm), so Main approved this mechanism under OM-4 (same files, pages, thresholds and safeguards; no dependency change) |

**Findings for the Owner (raised to Main):**
- **P-3 (resolved; Owner ruling 2026-11-26, "Authorize the one-line pattern correction in fulfillment-panel.tsx:599. Preserve the intended validation semantics and server-side validation. Verify representative valid and invalid inputs and successful T-E2E-10 execution. Do not weaken validation or suppress the console error"):** `src/app/staff/projects/[projectId]/fulfillment-panel.tsx:599` `pattern="[a-z0-9][a-z0-9_-]{2,99}"` was invalid under the `v` flag browsers use for `pattern` (a console error on every Owner view; the pattern was ignored). Changed to `[a-z0-9][a-z0-9_\-]{2,99}` (exactly one line; the database check `^[a-z0-9][a-z0-9_-]{2,99}$` unchanged). A new `r1.spec.ts` test proves the real browser's `validity.patternMismatch` and the database's own check constraint accept `abc`, `my-site_1` and a 100-character value and reject `ab`, `-abc`, `_abc`, `Abc`, `a b c`, `abc.def` and a 101-character value; T-E2E-10 passes unchanged.
- **O-3:** after a deployment its authorization stays active, so the staff page offers no new authorization for the same release (no UI path to redeploy after a failed live verification). T-E2E-08's second authorization is labelled test setup through the real `authorize_publication` under the Owner's real aal2 session.
- **OI-116 (pre-existing; allocated by Main):** T-AUTH-11 in `auth-tenancy.test.ts` is clock-dependent: `private.consume_rate_limit` uses hour-aligned windows, so when its 7-send loop crosses a whole hour the count restarts (run 45739220187: 2 + 5 = 7 codes). Not caused by this PR; test and function unchanged.
- **O-3 is OI-114; O-4 is OI-115** (allocated by Main).
- **O-4:** the database does not enforce that the two environment classifications agree; the seed sets both, and `400` asserts agreement and fail-closed absence.

**Verification (local stack, Supabase CLI 3.2.0, synthetic data only), at `16dada6` from a fresh `supabase db reset`:**

| Command | Result |
|---|---|
| `./scripts/run-db-tests.sh` (pgTAP) | 1,754 assertions, 0 files failing (`400`: 33/33) |
| `pnpm test:integration` | 8 files, 99 passed |
| `pnpm test` | 21 files, 366 passed |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm exec playwright test` | 63 passed, 1 failed: T-E2E-10 on P-3 only (before the P-3 fix). After it: `--project r1`, 12 passed, including T-E2E-10 and the P-3 agreement test |
| `lhci collect`, `lighthouse-auth.mjs`, `lhci assert` | 5 URLs × 3 runs; every assertion passes; report verification clean. Medians: performance 0.97–1.00, accessibility 1.00, best practices 1.00 |
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |

Not run locally: the dependency audit and gitleaks (CI only).

**Effort (OI-67):** AI session about 3 h; Owner review: none yet; administrative about 0.4 h (P-1, P-2 and P-3 questions to Main; the OI-116 root cause).

## 20. WP-B AUTH-009 implementation record (OI-91; S1 and S2 ruled by the Owner)

Implemented by the WP-B session in PR #43 (branch `claude/wp-b-client-portal-xjftil`), from the verified `main` at `9e8569c` (after PR #41).

**Entry (verified read-only):**
- The grant record (PR #40) merged at `2d27d07`.
- Post-merge CI run 45731539779 (#136) completed `success`, 7/7.
- Migration `20261127120000` and pgTAP `191` were unused.

**Owner rulings on S1 and S2 (2026-11-26, relayed by Main; recorded here under OM-3 and OM-5, with no separate grant PR).** S1 and S2 were stop conditions reported earlier the same day.

- **S1 (quoted):** "Approve the recommended new Owner-only stop-retry function, subject to all previously approved AUTH-009 guarantees:
  * Owner authorization, fresh MFA and mandatory reason.
  * Fresh attempt-specific idempotency key.
  * Deterministic concurrency and duplicate-request protection.
  * Retry restricted to eligible unresolved collection-stop operations.
  * No automatic retry or reactivation of automatic collection.
  * Existing financial holds remain effective until authoritative resolution.
  * Durable audit evidence.
  Approve the fresh WP-S financial review, focused on this addition and its interaction with the previously reviewed financial behavior."
- **S2 (quoted):** "Approve outbound.claim_token_rejected and the corresponding additions to audit-actions.ts and specification 04 §6.4. Preserve the previously approved audit and notification obligations. Never expose plaintext claim tokens or token hashes in audit records, notifications or logs."
- **Implementation boundaries (approved with the recommendation):**
  - `public.retry_final_balance_stop(uuid, text)`, `authenticated` only;
  - the lock hierarchy and a fresh attempt key;
  - only an unresolved stop is eligible; anything else is a typed refusal with no write;
  - a duplicate or concurrent call returns the existing attempt;
  - only the stop-specific item clears, and only on authoritative evidence; holds stay;
  - no reactivation and nothing scheduled;
  - an audit event with the reason;
  - a pure addition to the `050` D1 list;
  - a new migration file.
- **M-1 (Main's review):** the notification type `outbound.claim_token_rejected`, at l.247 and l.345, is the registered audit name exactly.

**S3, an OM-4 delegated addition (Main, 2026-11-26):** setup-only changes in `supabase/tests/235_wpc_oi113_approval_identity.test.sql` (helper loop) and `tests/integration/wpc-oi113-approval-race.test.ts` (settle loop). They follow the same claim, confirm and record template, and no assertion changes.

**Delivered (grant items 1 to 7, with S1 and S2):**

| Area | Change |
|---|---|
| Schema | `claim_token_sha256` and `dispatch_confirmed_at`, both set once. Format and confirmed-implies-claimed constraints. `outbound_guard`: two set-once columns added; the hash may be set only by the claim (no backfill); confirmation only on a pending, token-bearing request. |
| Claim (A2) | `outbound_request_for_execution`:<br>- lock order changed to authorizations (the project's rows, in id order), then invoice, then the claim update;<br>- returns `claim_token` once, storing only its SHA-256;<br>- OI-92(e) detection after a final-balance claim;<br>- `lock_timeout` 5 s. |
| Confirmation (A3) | New `confirm_outbound_dispatch(uuid, uuid)` and its wrapper (`service_role` only).<br>- Checks, in order: pending, claimed, legacy, token, already confirmed, 5-minute window.<br>- Re-checks eligibility under the same locks: an automatic create whose authorization changed after the claim is superseded by the hosted-only attempt; a stop for a paid invoice is dropped.<br>- Sets the confirmation once and returns `send_by` (30 s). |
| Recording (A1, R1) | New `record_outbound_result(uuid, uuid, …)`. The old private and public 7-argument signatures are dropped.<br>- Check order: pending, token, livemode (the abort is unchanged), confirmation.<br>- An unconfirmed result is recorded `ambiguous` (`unconfirmed_dispatch`), as is a success after `claimed_at` + 6 min (`late_result`). Either way the evidence is stored, with no domain effect, the existing audit action and an Owner notification.<br>- An identical resubmission returns the stored outcome and applies nothing.<br>- A legacy claim is refused (`legacy_claim`) and goes through the stale rule. |
| Lock order | The hierarchy (authorization → invoice → outbound) now holds in all six functions:<br>- `reconcile_outbound_request` and `record_outbound_result` no longer lock the outbound row first;<br>- `handle_invoice_failed` no longer locks the invoice before the authorization;<br>- `handle_final_balance_paid` takes the authorization lock first;<br>- the claim's order is reversed (above).<br>`reconcile_outbound_request` keeps its `authenticated` grant and its Owner, fresh-MFA and live-session check. |
| Stop reconciliation | Item 8 in `project_financial_anomalies`, `automatic_stop_unresolved` (G4): a stop reconciled absent keeps G4 blocked unless its invoice is paid, or a **later attempt** for the same invoice was confirmed by Stripe (`succeeded`) or reconciled present. That later attempt is the authoritative evidence of cessation, and it answers WP-S F-1. Only that item clears. Unconfirmed stop results are ambiguous through the generic path. |
| Stop retry (S1) | New migration `20261127120100`: `private.retry_final_balance_stop(uuid, text)` and its wrapper, `authenticated` only (re-authorized inside), never anon, PUBLIC or `service_role`. It is SECURITY DEFINER with `lock_timeout` 5 s.<br>- **Checks:** Owner, fresh MFA, a live session and a reason. Then the lock hierarchy (authorizations, invoice, stop rows).<br>- **Duplicate or concurrent call:** while an attempt is `pending`, it returns that attempt and creates nothing.<br>- **Typed refusals (no write):** `not_found`; `not_eligible` (no stop, or no invoice to stop); `not_needed` (the invoice is paid or void, or the latest stop succeeded); `reconciliation_required` (the latest stop is ambiguous or failed, so reconcile first); `attempts_exhausted`.<br>- **Eligible:** only a latest stop that the Owner reconciled as absent.<br>- **Effect:** one new stop request with a fresh attempt key, `wpb-final-balance-stop-<invoice>-a<n>`, and `auto_advance` false. It is audited as `outbound.request_retried` with the reason. Collection stays hosted-only, no charge is queued, and holds are untouched. |
| Token rejection audit (S2) | Each rejection at confirmation or recording writes `outbound.claim_token_rejected` (financial; summary `{operation, purpose}`, never a token or a hash). The action is registered in `audit-actions.ts` (04 §6.4). The Owner notification is unchanged (deduplicated per request). Spec **04 v0.10.2** adds the §6.4 line; there is an 08 §5 row. |
| OI-92(e) | New internal `note_final_balance_release_change(uuid)`, with no wrapper and no API role.<br>- Read-only, with no lock.<br>- Uses WP-C `current_release` semantics.<br>- Sends one deduplicated Owner notification (`final_balance.release_changed`, reason `withdrawn` or `superseded`). The obligation stands.<br>- Called at the claim and in `record_project_reconciliation`. |
| Application | `src/server/services/billing.ts`:<br>- claim, then validations, then the monotonic 30 s deadline from the start of the confirmation call, confirm, send, record with the token;<br>- pre-send validation failures confirm, then record `failed`;<br>- a deadline overrun records `failed` / `dispatch_not_initiated`;<br>- a late or unconfirmed success reports `reconciliation_required`;<br>- one identical resubmission when a call returns an error and no result (the comment corrected per WP-S F-4);<br>- the token stays in memory.<br>`src/server/stripe/gateway.ts`: contract comment only. |

**Migration hashes (SHA-256).** `20261127120000_wpb_oi91_dispatch.sql`: `b7a13d1e8f5081240c28185e8ad3aa9909af27e0fa4239e33c15cf562361ab31` (amended for S1 and S2 before merge; previously `faf0d73f…5ac4` at `43b4bee`). `20261127120100_wpb_oi91_stop_retry.sql`: `95fb62c2ae7728344c6f3ae9c4c3163824f3de852e7875c98512257e50e8c115`. Four bodies are generated from the merged definitions by asserted exact substitutions, so their diffs are only the stated change: `handle_final_balance_paid`, `handle_invoice_failed`, `record_project_reconciliation` and `project_financial_anomalies`.

**Dispositions (byte-identity verified by statement comparison against `main`; plans unchanged):**
- Exactly 13 assertion statements changed:
  - the 11 approved sites;
  - the additive `100:60` entry (`confirm_outbound_dispatch` joins the server-only list);
  - the S1 addition to the `050` D1 list (`retry_final_balance_stop`), as the Owner ruled.
- Every other assertion in 050, 100, 110, 120, 130, 140, 150, 160, 180, 190 and 235 is byte-identical.

| Approved site (inventory at `85ec6ce`) | On `main` | On this branch |
|---|---|---|
| 100:88 | 88 | 88 |
| 110:230, 232, 238, 263 | 230, 232, 238, 263 | 251, 254, 260, 287 |
| 120:285 | 309 | 332 |
| 130:259, 302, 448, 457 | 283, 326, 472, 481 | 300, 343, 489, 498 |
| 160:389 | 413 | 430 |

The 130 claim sites stay byte-identical: the `pg_temp.svc` helper stores and confirms the token and strips it from the result. Recording sites read the token through `pg_temp.token(%1$L)` inside the executed text, so no token ever appears in a statement, a diagnostic or a printed result. The unit and integration diffs add lines only; the one removed line is a comment in `wpb-static`.

**New tests:**
- `supabase/tests/191_wpb_dispatch_ownership.test.sql`, 105 assertions. This is the grant's `191_wpb_oi91_dispatch` renamed under OM-4 (Main, 2026-11-26) to satisfy the existing WP-B naming assertion:
  - signatures and exact ACLs;
  - the token; confirmation;
  - recording order and outcomes; resubmission;
  - legacy claims and the guard;
  - the eligibility re-check;
  - stop reconciliation; OI-92(e);
  - **S2:** the audit event at each rejection (financial, on its request), the deduplicated notification, and no accepted or submitted token or token hash in any audit record or notification;
  - **S1:** privileges; Owner-only refusals (the client, another tenant's client, Admin, stale MFA, no live session, a blank reason, an unknown invoice), each writing nothing; the duplicate call while pending or in flight; reconcile-first for failed and ambiguous stops; not eligible without a stop; the fresh attempt key; the deterministic duplicate; the audit with the reason; no reactivation; the hold and the stop item preserved while in flight; clearing on Stripe's confirmation only; a failed retry clearing nothing; not needed after success or payment.
- `tests/integration/oi91-dispatch-revocation.test.ts`, 23 tests:
  - each changed function raced against the Owner's recorded revocation in both commit orders (12);
  - a direct hierarchy probe for each function: it must wait for a higher lock while holding no lower one, so out-of-order locking aborts with 40P01;
  - the 5 s lock timeout;
  - the 30 s send deadline with a fake clock;
  - **S1:** simultaneous Owner retries (the second waits on the authorization row, then returns the first's attempt; one request; one audit) and the retry's hierarchy probe;
  - **S2:** no claim token in any console output during a full execution (every method captured, and the capture is shown to work).
- The `wpb-static` guard: payment invariants over both AUTH-009 migrations, hash-only storage, confirmation before the gateway on the send path, no token in logs, every audit action registered as financial, and no token identifier in any audit or notification call.

**Routine technical decisions (OM-4, recorded):**
- The project's authorization rows are locked in id order, so callers that lock one row cannot deadlock with callers that lock all of them.
- The database allows any number of identical replays, each with no effect; the executor resubmits at most once.
- `lock_timeout` 5 s is set on the four dispatch functions and the stop retry only. The webhook handlers keep the session setting, so their contention behavior is unchanged.
- **Statement timeout (verified locally):** a function-level `statement_timeout` would not govern the running statement, so it is not set.
  - The effective limit for these RPCs is the PostgREST login role's `statement_timeout` of 8 s (local Supabase defaults; `service_role` has no override). That is stricter than the 30 s target.
  - No role or connection setting was changed. The hosted values are for WP-D to verify.
- The token hash stays readable to the Owner through the existing select policy (table row only). The plaintext is never stored, and neither the token nor the hash is ever placed in an audit record, a notification or a log (S2).
- **WP-S findings at `43b4bee`:** F-1 is handled by the item-8 rule above. F-4 is fixed (the comment now states the behavior). F-3 (hosted parameter and statement logging), F-6 (the real gateway's timeout and retries) and F-7 (statement timeout) are for WP-D or the real-gateway authorization. F-2 and F-5 are informational, with no change.

**Mutation checks** (each mutated function installed locally, the targeted checks run, the original restored). All 51 were caught (47 SQL and 4 executor; rerun in full after S1 and S2):
- **Lock order:** claim invoice-first; confirmation and recording outbound-first; recording invoice-first; reconciliation outbound-first; `invoice.payment_failed` with the merged order; `invoice.paid` without the authorization lock; no lock timeout.
- **Token:** any token accepted at recording or confirmation; livemode before token; legacy recordable; no rejection notification; no hash stored.
- **Confirmation:** unconfirmed effect applied; no late boundary; repeated confirmation; no window; no authorization re-check; paid-stop confirmation.
- **Resubmission:** a replay without the token; a replay re-applying the effect. The second was first missed because the Customer insert is idempotent; the 191 replay test was moved to a Checkout create, whose effect is audited.
- **Guard:** backfill; hash not set once; confirmation not set once.
- **Stop:** absent clears; payment does not clear.
- **OI-92(e):** no detection at the claim; no dedupe; no supersession detection; no detection in reconciliation.
- **S1:** no fresh MFA; no live session; no reason; a duplicate creating a second attempt; an unreconciled stop retried blind; a succeeded stop retried; no authorization lock; collection re-enabled; no audit; a hold cleared; a later attempt never clearing; an in-flight retry already clearing.
- **S2:** no audit at confirmation; no audit at recording; the submitted token in the audit summary; the stored hash in the notification.
- **Executor:** no deadline check; the gateway without confirmation (the static guard was first too loose and was tightened to the send path); the record without the token; a refused confirmation still sending.

**Suites after S1 and S2** (local, fresh `supabase db reset`, Supabase CLI 3.2.0, CI order):

| Command | Result |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 17 files, 313 passed |
| `pnpm audit --audit-level=high`; `./scripts/check-migrations.sh origin/main` | No known vulnerabilities; no merged migration changed |
| `./scripts/run-db-tests.sh` | 32 files, 1,826 assertions, 0 failed (main: 1,721; plus 191's 105) |
| `pnpm test:integration` | 9 files, 122 passed (main: 99; plus 23) |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` | 52 passed |
| Lighthouse | Not run locally; runs in CI |

Exact-head CI is recorded in the pull request. At `43b4bee`, run 45738752135 was 7/7.

**Reviews required (grant):**
- WP-S's independent financial review: recorded at `43b4bee` (7180423952). The Owner approved a fresh, focused WP-S review of S1.
- WP-C's read-only review: recorded at `43b4bee` (7180305233), covering the S3 files.
- Main: recorded at `43b4bee` (7180343349), with M-1 to be reconciled with S2 (done).

Each is a durable non-approval record. OI-91 stays open until the merge and its post-merge CI.
## 21. WP-S OI-88 option A implementation record (AUTH-017)

Implemented by the WP-S session (`session_01RCnsL8EFk2jME7uNLi46as`) under AUTH-017 (Owner, 2026-11-27, Decision 1; effective on the verified merge of PR #51 at `12601a6`, OM-1), on `claude/wp-s-sales-representative-hbhex5` from `12601a6`. Local and CI only; synthetic data; no provider, hosted-environment or production access; no database change; no dependency, `package.json` or required-check change.

**The gap (WP-S reassessment, 2026-11-26).** A confirmed account with no active membership (a former client whose memberships were revoked, or an acceptance interrupted after the email was confirmed) who is invited again receives no email: Supabase refuses `inviteUserByEmail` for an existing account (03A S-06), and the app records `auth.invite_email_not_sent`. The strict `requireClient` sends that user to the "No portal access" card, so the in-portal invitation list was unreachable and the invitation could not be accepted. The inviter was told the invitee "will see the invitation after signing in", which was not true for this population.

**Change:**

| File | Change |
|---|---|
| `src/server/auth/guards.ts` | New `rejectStaff(ctx)` (Owner and Admin to `/staff`, Sales to `/sales`, any other staff role value to `/sign-in?notice=inactive`, the same order and targets as `requireClient`) and `requireInvitee()` (`requireUser` plus `rejectStaff`; no membership requirement). **`requireClient` is unchanged.** |
| `src/app/invitations/page.tsx` (new) | `/invitations`, behind `requireInvitee`: the caller's own pending invitations, read through RLS (`invitations_select`: pending, unexpired, the caller's verified email), each with an Accept button; an empty state when there are none; Sign out |
| `src/app/invitations/actions.ts` (new) | `acceptListedInvitationAction`: `requireUser` then `rejectStaff`, then the existing email-bound `accept_invitation` with no link token (the same path as the in-portal acceptance). Client to `/portal?notice=invitation_accepted`; staff to MFA first; any refusal to one generic message |
| `src/app/sign-in/page.tsx` | The "No portal access" card links to `/invitations` for `no_active_project` only |
| `src/lib/messages.ts` | `invite_existing_user` now says no email was sent and that the invitee finds the invitation under "Your invitations" after signing in; `no_active_project` points to the invitations, not to an email; new `invitation_unavailable` |
| `tests/unit/oi88-invitations.test.ts` (new) | 10 tests: the guard (non-staff with or without a membership admitted; Owner, Admin, Sales and unknown staff roles refused; signed-out, ended session and inactive refused; `requireClient` still refuses a memberless user), the action (email-bound, no token; staff to MFA; generic refusal; no database call for staff or signed-out callers), the messages and the card link |
| `tests/e2e/wps.spec.ts` | One new test (additions only; the import line gains `messageCount`). Fresh synthetic Sales Representative and former client (revoked membership). Without an invitation: `/portal` is refused, the card links to `/invitations`, which lists nothing and offers no Accept button. The representative invites the former client: `invite_existing_user` with the accurate text, and no email (Mailpit count 0). A Sales session on `/invitations` is sent to `/sales`. The former client accepts from `/invitations`: `/portal` shows the new project only; the invitation is `accepted`, exactly one active membership, and the `invitation.accepted` audit names the former client. axe (WCAG 2.2 AA tags) on the card, the empty and populated invitations page, the inviter's page and the portal |

**Security.** No database, RLS, grant or function change. The page reads only what RLS already lets the caller read, and acceptance uses the reviewed definer function, which binds the invitation to the verified `auth.users` email, serializes with the WP-S role and membership lock and refuses an active Sales role. Every client page and action keeps the strict `requireClient`; `/invitations` grants no project access. The static guard rule (`tests/unit/static-security.test.ts`) is unchanged: the new action's first statement is `await requireUser()`. `/invitations` is served `private, no-store` (the proxy's `/invite` prefix). 03 §6.1 step 2 ("the invitee signs in normally and sees the pending invitation") now holds for this population; no specification text changes.

**Local results** (fresh `supabase db reset`, Supabase CLI 3.2.0; test build with `NEXT_PUBLIC_SITE_URL=http://localhost:3100`, as in CI):

| Command | Result |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 22 files, **380** passed (370 on `main` plus 10). The 10 new tests fail against `main`'s code (non-vacuous) |
| `pnpm build`, `pnpm build:production-check` | Pass |
| `pnpm exec playwright test --trace off` | **66 passed**, including the new OI-88 test |
| pgTAP, integration, Lighthouse | Not run locally (no database or server-side data change); CI runs them |

One local e2e run failed before any changed code ran (no sign-in email for the seeded Sales user immediately after the preceding run); it passed on a fresh reset. A second local run failed only because the local `.env.local` site URL differed from CI's; rebuilt with CI's value, all 66 passed.

**Shared file.** `src/lib/messages.ts` is shared with AUTH-015; whichever PR merges second makes an additions-only catch-up (OM-2).

**Reviews required (AUTH-017):** WP-C and Main, durable non-approval records. Merge: OM-6(b), by Main once every condition is met. OI-88 closes on the verified merge and its post-merge CI.

**Effort (OI-67):** AI session about 0.8 h; Owner review: none; administrative about 0.1 h (a Docker recovery).

## 22. WP-C OI-114 implementation record (AUTH-015)

Implemented by the WP-C session on `wp-c/oi-114-publication-recovery`, from the verified `main` at `12601a65d7dd892840a7d74ff9de3a0073bd56ac` (the R1 execution grant record, PR #51).

**Entry (verified read-only):**
- AUTH-015 was granted in PR #51, merged at `12601a6` (OM-1); Main announced it active.
- Migration `20261127140000` (reserved) and pgTAP file `240` were unused.

**Change (files exactly as authorized):**

| File | Change |
|---|---|
| `supabase/migrations/20261127140000_wpc_oi114_publication_recovery.sql` | **New** `private.reopen_failed_publication(uuid, text)` with its security-invoker `public` wrapper, granted only to `authenticated`. **Replaced** (`create or replace`) `private.authorize_publication` and `private.record_live_verification`, one hunk each; every other line of both is byte-identical to `20261124140200` (`diff` shows only those hunks). No table, column, index, policy or trigger change, and no DML. SHA-256 `8ebad3ac85bc4aa8f58f36d309937c4a25118e0e4a7165a01458fde85f70c05a` |
| `src/app/staff/projects/[projectId]/fulfillment-actions.ts`, `fulfillment-panel.tsx` | The Owner's "Recover failed publication" card. It needs a reason and an explicit confirmation, and the action requires fresh MFA. "Start deployment" is offered only for an authorization without a deployment |
| `src/domain/contracts/audit-actions.ts`, `src/lib/messages.ts` | `publication.recovery_opened` and `publication.recovery_rejected`; four messages |
| `supabase/tests/220_wpc_publication_gates.test.sql` | Setup only: two Owner recoveries before the two existing re-authorizations. `plan(117)` and every assertion are unchanged |
| `supabase/tests/050_security_events.test.sql` | One addition to the WP-C reviewed RPC list: `reopen_failed_publication` |
| `supabase/tests/240_wpc_oi114_publication_recovery.test.sql` | **New**, 65 assertions (below) |
| `tests/integration/wpc-oi114-recovery-race.test.ts` | **New**, 2 tests (below) |
| `tests/e2e/r1.spec.ts` | T-E2E-08 reworked through the UI, under the Owner's disposition (below) |
| `docs/06-PUBLISHING-AND-POST-LAUNCH.md` | v0.5.5: the §8.1 "Controlled recovery" rule (**[APPROVED OI-114]**, D6) |
| This section and 08 | The record |

**Behavior (D1 to D4):**
- **D1 (with Amendment 1: M-1 and N-1, option B).** `authorize_publication` refuses a release when the project's latest deployment is of that release and has not been recovered, whatever its outcome (started, failed, or succeeded with an unverified, failed or passing verification). It returns `recovery_required`, writes an audit event and issues no authorization. This holds whether that deployment's authorization is still active or a gate failure has closed it (`gates_failed`, `gates_failed_at_start`). All gates are still evaluated first, as before. A deployment counts as recovered when it has its append-only `publication.recovery_opened` audit event. All three checks match the exact action, `target_type = 'publication_deployments'`, `target_id` = the deployment and the project, so they use the existing `(project_id, occurred_at)` index. No table or helper is added. The record is trustworthy: `audit_events` is append-only (triggers refuse update, delete and truncate), no API role can insert into it or execute `record_audit_event`, and only `reopen_failed_publication` emits that action. 240 asserts all of this from the catalog.
- **D2.** `reopen_failed_publication` lets only the Owner (aal2, an active session, fresh MFA) recover a deployment, and requires a reason. Every guard is NULL-safe (`… is not true`; OI-120): `private.is_owner()` is NULL, not false, for a non-staff caller. It takes the per-project release lock, then the deployment row `FOR UPDATE`, then its authorization. The deployment must be the latest deployment of the current release, recorded as failed or with a failed latest verification. An authorization closed by a gate failure is still recoverable; any other closure is not. Otherwise the call returns `not_recoverable` with a detail (`authorization_closed`, `not_latest_deployment`, `release_not_current`, `deployment_in_progress`, `live_unverified` or `live_verified`) and audits the refusal. A stale-MFA refusal is also audited. A repeated recovery returns the existing one.
- **D3.** A recovery only closes the authorization (`failed_publication_recovery`) and audits `publication.authorization_invalidated` and `publication.recovery_opened`. An authorization a gate failure already closed keeps that single invalidation, and only `publication.recovery_opened` is written, with `authorization_closed_by`. The latter records the reason, the failure and the open incident IDs. Re-authorization and deployment are the unchanged normal flow, which re-runs G1 to G8.
- **D4.** A release whose latest verification passed can be neither recovered nor re-authorized.
- **Late verification.** `record_live_verification` reads the deployment `FOR SHARE` and refuses a recovered deployment (`deployment_closed`), recording nothing. The check keys on the recovery event, not the authorization's invalidation reason. A succeeded deployment whose authorization a gate failure closed while it was `started` (N-1) is therefore covered too.

**pgTAP 240 (65 assertions, one rolled-back transaction).** It uses 220's fixtures (the test-only WP-B financial interface fixture, so G2 and G4 can be flipped) and WP-C's real functions.

| Case | Expectation verified |
|---|---|
| D1 | A same-release re-authorization after a failed deployment returns `recovery_required`. It is audited and issues no authorization |
| Denials | The Admin, a client and the Owner at aal1 are refused (`forbidden`). **OI-120:** so are a client and a revoked former staff member, each at aal2 with a verified TOTP factor, fresh MFA and a live session. Stale MFA returns `reauthentication_required` and is audited. A blank reason and an unknown deployment are refused. No refused call closes the authorization |
| M-1 | A gate failure after the failed deployment closes its authorization (`gates_failed`). With the gates passing again, re-authorization is still refused with `recovery_required` and issues nothing. The Owner recovers that deployment: the recovery is recorded with `authorization_closed_by: gates_failed`, the authorization keeps its single invalidation, and a repeat returns the existing recovery. Authorization then succeeds for the same release identity |
| N-1 | A gate failure closes a `started` deployment's authorization (`gates_failed`). With the gates passing again, re-authorization is refused with `recovery_required` and issues nothing, and the running deployment cannot be recovered (`deployment_in_progress`). That deployment later succeeds and fails verification. Its recovery is recorded, a late verification of it is refused with `deployment_closed`, and authorization then succeeds |
| Not recoverable | A deployment in progress; an unverified deployment; a superseded release; a deployment whose authorization was closed other than by a gate failure (SYNTHETIC: a withdrawal). Each refusal leaves the authorization unchanged |
| D2, D3 | The recovery returns `existing: false`, closes the authorization and audits the reason, the failure and the open incident. It creates no authorization, deployment, verification, notification or domain event. A repeat returns `existing: true` and writes nothing. The incident stays open |
| G2, G4 | After recovery, authorization fails on G2, then on G4; with both passing, a new authorization is issued for the same release identity, and `start_deployment` records a new deployment of the same commit |
| Verification failure | It is recoverable (`verification_failed`). The late verification is refused with `deployment_closed`, recording nothing and announcing nothing. The new deployment does not inherit an earlier verification and needs its own |
| D4 | After a passing verification, recovery returns `live_verified` and re-authorization returns `recovery_required` |
| Isolation, catalog | Client B sees no Project A audit event, and every recovery audit of a Project A deployment belongs to Project A. Counts are scoped to Project A, so committed rows of other test files never interfere. Only `authenticated` can execute the functions (not `anon` or `service_role`). The recovery is security definer with an empty `search_path` |

**Invariant, documented rather than manufactured:** `not_latest_deployment` is defensive. A newer deployment needs a new authorization, and a new authorization for the same release needs the latest deployment recovered first. A deployment that is not the latest has therefore been recovered (`existing`), or its authorization was closed other than by a gate failure (`authorization_closed`).

**Race test (two real connections, 10 repetitions per order, each on a fresh project paid through the real WP-B workflow).** Release 1 comes from WP-C's real intake and `release_preview`. The authorization and succeeded deployment rows are inserted directly; this is **SYNTHETIC** setup, since the gates are covered by pgTAP. The first, failed verification goes through the real `record_live_verification`.
- **Recovery first:** the Owner's recovery holds the row. The verifier's call is seen waiting on `Lock` in `pg_stat_activity`. Once the recovery commits, the verification returns `deployment_closed`, with no new verification, no `publication.live` and the state still `failed`.
- **Verification first:** a passing verification holds the row, and the recovery is seen waiting. Once the verification commits, the recovery returns `not_recoverable` / `live_verified`, closes nothing and is audited. The state is `live_verified`.
- In both orders: no 40P01 and no other database error.

**T-E2E-08 assertion disposition (FD-14; Owner, 2026-11-27, relayed by Main).** The flow now runs through the page:
1. authorize;
2. deploy `SHA_OTHER`, which fails verification;
3. recover (reason, confirmation, fresh MFA);
4. authorize;
5. deploy `SHA_2`, which is verified.

The old database-level second authorization (test setup) is removed. Unchanged: :1071, :1072, :1131 and the `deployment.verification_recorded` count of 2; no other assertion in `r1.spec.ts` changed.

| Field | Record |
|---|---|
| Original | :1084 `verified.rows` equals `[{true, true, SHA_2, SHA_2}]`, right after the first deployment. :1122 `all.rows` equals `[{true, true}, {false, false}]` |
| Replacement | :1084 moves to after the `SHA_2` deployment and equals `[{false, false, SHA_OTHER, SHA_2}, {true, true, SHA_2, SHA_2}]`. :1122 becomes `[{false, false}, {true, true}]`. Added: `publication.recovery_opened` count 1, and two authorization rows for release 2, the first closed with `failed_publication_recovery` and the second active |
| Original guarantee | The authorized commit's deployment verifies when the served build matches; a mismatched build fails verification and opens an incident; both verifications are recorded |
| Replacement guarantee | The same, in the order D1 and D4 permit. A mismatched build fails verification and opens the incident. Only an explicit Owner recovery through the page lets the same release be authorized again. The redeployment then verifies with its own verification, against the authorized commit |
| Exposure | Verification of a first deployment that passes immediately is no longer shown in T-E2E-08. It is covered by pgTAP 220 (unchanged) and 240 |
| Compensating coverage | pgTAP 240 (D1, D4, recovery eligibility, late verification); the race test; pgTAP 220 unchanged |
| Authorization | Owner, 2026-11-27 (AUTH-015 assertion disposition, relayed by Main) |
| Evidence | Local e2e run below; exact-head CI in the pull request |

**Mutations (26; each installed locally, the targeted tests run, the original restored). 25 caught:**

| Mutation | Caught by |
|---|---|
| Authorize recovery check disabled | 240 (18 assertions) |
| Authorize check ignores `started` deployments (N-1) | 240 (3) |
| Authorize recovery marker ignores the deployment | 240 (6) |
| `deployment_closed` check removed | 240 (2) and the race test (recovery first) |
| `deployment_closed` keyed on the authorization's reason (the pre-N-1 form) | 240 (2) |
| Verification `FOR SHARE` removed | The race test (recovery first); 240 is single-session |
| Recovery `FOR UPDATE` on the deployment removed | The race test (both orders) |
| **OI-120: the NULL-unsafe guard (`if not (…)`) restored** | 240 (9, including both OI-120 denials) |
| Fresh-MFA check removed | 240 (9) |
| Owner check widened | 240 (10) |
| aal2 check removed | 240 (2) |
| Reason check removed | 240 (8) |
| `authorization_closed` check removed; every closed authorization made recoverable | 240 (1 each: the SYNTHETIC withdrawal) |
| Gate-failure closures made unrecoverable | 240 (26) |
| Recovery existing-marker never matches; ignores the deployment | 240 (3; 22) |
| Current-release check removed | 240 (2) |
| In-progress check removed | 240 (2) |
| Unverified treated as recoverable | 240 (3) |
| Passing verification treated as recoverable (D4) | 240 (5) |
| Refusal audit removed; stale-MFA refusal audit removed | 240 (1 each) |
| The recovery does not close an active authorization | 240 (2) |
| `publication.recovery_opened` audit removed | 240 (26) |
| Latest-deployment check removed | **Not caught, as expected:** the defensive invariant above |

Every mutation was installed by `create or replace` from a mutated copy of the migration and restored from the migration file. The baseline passes after the restore.

**Suites (local, fresh `supabase db reset`, Supabase CLI 3.2.0, CI order), on the branch synchronized with `main` at `2d5705e` (PR #56), with Amendment 1 (option B, M-1 and N-1):**

| Command | Result |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 22 files, 380 passed |
| `pnpm audit --audit-level=high`; `./scripts/check-migrations.sh origin/main` | No known vulnerabilities; no merged migration changed |
| `supabase db reset`; `./scripts/run-db-tests.sh` | 34 files, 1,924 assertions, 0 failed (240: 65/65; 220: 117/117 and 050: 24/24, plans unchanged; rerun on a fresh reset after the two catalog assertions were added) |
| `pnpm test:integration` | 10 files, 124 passed (including the race file's 2) |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` | 66 passed, including T-E2E-08 with its axe check |
| Lighthouse | Not run locally; runs in CI |

Before option B, the same suites passed on the head before the sync (`7af10b5`). An earlier local run showed two timing failures in WP-B's `oi91-dispatch-revocation` lock probes. That file passed 23/23 on its own and has not failed again in any full run. The sync with `8ebcced` (PR #53, AUTH-017) caused one documentation conflict, this section's number (§21 is WP-S's record). `src/lib/messages.ts` merged cleanly as an additions-only catch-up (OM-2).

Remote CI for the exact head is recorded in the pull request.

**M-1 (Main review 7227401266) and N-1 (WP-I review 7227508627): closed under option B (Owner, 2026-11-27; AUTH-015 Amendment 1, PR #56).** N-1: a gate failure also closes a `started` deployment's authorization, because `invalidate_authorizations` spares only `succeeded` deployments. The release could then be re-authorized and started while the first deployment was still running. The refusal condition is now stated on the release's latest deployment, whatever its outcome. For M-1: The path: a failed deployment, then a gate failure that closes its authorization (`gates_failed`), then a passing authorization. Previously this re-issued the same release with no recovery record, and the recovery refused that deployment as `authorization_closed`. Now the re-authorization is refused with `recovery_required` until the Owner records a recovery, and the recovery accepts a gate-closed authorization. The change stays within AUTH-015's two hunks, the new recovery function and 240. No existing assertion changes.

**Reported to Main, outside AUTH-015 (not changed):** the OI-120 pattern also appears as `if not private.is_owner() or not …` in `private.set_staff_role` (`20261125120100`:468) and `private.revoke_staff` (`20261123060000`:715). A rolled-back local probe showed two privilege escalations. A client at aal2 with fresh MFA promoted the Admin's existing staff row to Owner. A revoked former Admin re-granted itself Owner. Existing functions are left to the separate fix grant (Main's OI-120 directive).

**Shared files:** `050` and `audit-actions.ts` are shared with AUTH-010; whichever PR merges second makes an additions-only catch-up (OM-2). `messages.ts` is shared with AUTH-017, which merged first (PR #53, `8ebcced`): this PR's change to it is the additions-only catch-up (OM-2).

**Reviews required (AUTH-015):** WP-I, WP-B and Main. Each is a durable non-approval record. WP-C does not merge. OI-114 closes only on the verified merge and its post-merge CI; OPEN-ISSUES is updated by Main.

**Effort (OI-67):** AI session about 4.5 h; Owner review: the T-E2E-08 disposition and Amendment 1; administrative about 0.4 h (one escalation, one scope question, the OI-120 reports, the M-1 and N-1 coordination).

## 23. WP-B AUTH-010 implementation record (OI-93; Amendments 1 and 2; OI-120, OI-121)

Implemented by the WP-B session on branch `claude/wp-b-client-portal-xjftil`. It started from `main` at `12601a6` (the PR #51 grant merge; post-merge CI run 46058960366 `success`) and is merged up to `2d5705e` (PR #56: Amendments 1 and 2 active). Local and CI only, synthetic data; no provider, hosted or production access; no dependency, `package.json` or required-check change.

**Delivered (grant scope):**

| Area | Change |
|---|---|
| Records (`20261127130000`) | Four private, insert-only tables with no API privilege (update, delete and truncate refused by trigger): `financial_conflict_decisions` (one per event, immutable), `financial_conflict_applications` (durable attempts 1 to 10, unique `(decision_id, attempt_no)` and `attempt_request_id`, at most one success, `terminal_reason = 'exhausted'` exactly on a tenth non-success row), `financial_conflict_effects` (one recognition per effect key: provider object, effect type, amount) and `financial_conflict_application_entries` (the exact ledger entries posted, `new`, or cited, `cited`, with their recorded values; a ledger entry is `new` in at most one application). |
| Extraction | `apply_refund_for_project` and `apply_dispute_for_project` are the WP-H handler bodies verbatim, with `v_project` passed as `p_project_id` (static proof in `wpb-static`). `handle_refund`, `handle_dispute` and `handle_charge_refunded` keep the attribution step unchanged and delegate. `charge_refunded_objects` is the WP-H refund expansion, byte-identical and shared by the handler and the attempt (I-8). Equivalence: pgTAP 140, 160, 180, 190 and 191 pass unchanged. |
| Amendment 1 (OI-121) | The only behavior change to those handlers: the `payment.refund_recorded` key is passed in by the caller. refund.* events keep `'payment.refund_recorded:' || stripe_event_id`. A charge.refunded event uses `… || ':' || <refund id>`, so a charge.refunded with several refunds now posts each refund once instead of failing with 23505. Across refund.* and charge.refunded events each refund is recognized financially once in either arrival order (the counted-once rule); the domain event and audit stay once per event, as before. |
| Classifier and fingerprint | `financial_conflict_classify` (S1 refunds, S2 disputes; every unsupported class; the expected money effect per object, I-5) over `financial_conflict_scope`; `oi93.fp.v1` = SHA-256 of canonical JSON (`oi93_canonical_json`: keys by code point, no whitespace, explicit nulls) over the decision, the event and its raw-body hash, the candidates, the payment links, the obligations and balances, the relevant ledger entries, the refund and dispute rows, the refund decisions and lines, and the effect recognitions. |
| Owner functions (`20261127130100`, U-2) | `record_financial_conflict_decision(bigint, uuid, jsonb, text)`, `retry_financial_conflict_application(uuid, uuid, text)`, `financial_conflict_attempt_status(uuid)` (VOLATILE: a shared try-lock, then a fresh read), `financial_conflict_events()`. Each private function is SECURITY DEFINER with `search_path=''` and a NULL-safe guard (OI-120): `(is_owner() and is_aal2() and mfa_is_fresh() and session_is_active()) is not true`, plus the reason. Each INVOKER wrapper is granted to `authenticated` only and carries `lock_timeout` 5 s (I-1). Added to the `050` list as a new group (additions only). |
| Decision rules | Refused with no row, returned (never raised) and audited as `financial_conflict.decision_refused` with the event, the chosen project and the classifier reason (Amendment 2): already decided, not eligible, not a candidate, unsupported (`conflict_unsupported`) and, when no project holds the obligations yet, `not_yet_resolvable` (I-4: decide again once the charge is posted). |
| Attempt | Lock order: the attempt-request advisory lock, the decision row, the event row, then the merged reversal order (refund or dispute row, the charge advisory lock, `refund_decisions`); no AUTH-009 lock. Refusals with no row, audited as `attempt_refused`: already applied, permanently unsupported, 10 attempts, within 60 s, and `awaiting_evidence` with an unchanged fingerprint. One protected step: classification; the extracted path per object; the re-check under the charge lock (nothing under another project); recognition by exact match (project, object, type, amount, exact entry IDs; entries of another recognition never re-recognized, I-6); the expected money effect present (I-5); the entries and the attempt row. Any unsupported or awaiting object or failed proof rolls the whole step back; the outcome is the most severe; detail per object. An exception is `operational_failure` (SQLSTATE only). |
| Clearing | `financial_conflict_cleared`: only a `posted` or `represented` application that `financial_conflict_application_verified` re-verifies against the ledger as it is then. `project_financial_anomalies` items 1 and 7 exclude a cleared event; items 2 to 6 and 8 are byte-identical to `20261127120000`. A decision alone, or a failed or interrupted attempt, never clears. |
| Application | `src/app/staff/billing/conflicts/` (Owner, fresh MFA): the list, the decision form and the apply form. After `outcome_unknown` only a status read or a resubmission of the same `attempt_request_id` is offered. `src/server/services/billing.ts`: the 45 s deadline (`CONFLICT_ACTION_DEADLINE_MS`), starting immediately after the action's guard (the 03 §10 guard-first rule), with a client-side abort; recorded, refused, rolled back (`attempt_rolled_back`) and `outcome_unknown` are kept apart. `messages.ts` and `audit-actions.ts` (U-1 and Amendment 2: four financial actions). No provider call. |

**Main's OM-4 rulings on I-1 to I-9 (2026-11-27), dispositions:**
- **I-1:** wrapper placement, with Main's corrected condition (c):
  - (a) 55P03 at about 5 s through PostgREST: the decision call on the event row, the attempt on the event row, on the decision row, and on its `attempt_request_id` lock;
  - 57014 at about 8 s as a separate case;
  - (b) and (c) shape and ACL assertions in 195: the wrappers INVOKER with `lock_timeout=5s`; the private functions SECURITY DEFINER, executable by `authenticated` only (never anon, service_role or PUBLIC); the helpers by no API role;
  - (c) `private` is not an exposed API schema (`wpb-static`, `supabase/config.toml`);
  - (d) removing either wrapper's SET is caught;
  - 191 is unchanged.
- **I-2:** every attempt, the first included, goes through `retry_financial_conflict_application`.
- **I-3:** Amendment 2 (above).
- **I-4:** `not_yet_resolvable` (above); `awaiting_evidence` is only an attempt-time evidence gap.
- **I-5:** the expected effect is derived from the event; zero-entry `posted` is accepted only where no effect is expected; a fault-injected succeeded refund that posts nothing fails closed.
- **I-6:** exact match, no re-recognition of another recognition's entries, the check against another project before and after posting under the charge lock; provenance (the cited entries' source event) shown in 195.
- **I-7:** `195_wpb_conflict_decision.test.sql`.
- **I-8:** the helpers stay in the two migrations and are revoked from every API role; no other existing assertion changed.
- **I-9:** the status read is VOLATILE and non-blocking; concurrent attempts with different ids (one money effect, the other refused, no 40P01), a resubmission of the same id while the first runs (it waits, then returns the recorded attempt, one row), and `in_progress` during a running attempt (integration).

**Migration hashes (SHA-256):** `20261127130000_wpb_oi93_conflict_decisions.sql` `fd06c52bb8c0d33800555b80cd140c8c3b772b100d3ab3378c87ec47d415f267`; `20261127130100_wpb_oi93_conflict_attempts.sql` `747c33857f8dc861c64d6acd1b377c2bf4ee0439703ac19825b3be757250acac`.

**Existing assertions:** only the `050` additions (U-2). Every other assertion in every existing suite is unchanged.

**New tests:**
- `supabase/tests/195_wpb_conflict_decision.test.sql`, 157 assertions: records and privileges; OI-120 denials on all four functions (a fresh-MFA client, a revoked former Owner, Admin, Sales, an Owner without fresh MFA); decisions and refusals with their durable, bounded audit (WP-C U-3 I-1: the first 20 object reasons and the total); every outcome; a refusal whose only reason is obligations held under another candidate (WP-S F-1); S0, S1 and S2 (dispute opened, then won: cited and new); overlapping events; recognition under another project; mixed charge.refunded (new and cited) and the whole-step rollback; idempotency; the 60 s interval, the fingerprint rule and the tenth attempt; a second holder appearing after the decision; item-1 and item-7 clearing; fingerprint stability and sensitivity per input class; fabricated and corrupted clearance never clearing; OI-121 normal-path regressions in both arrival orders; the I-5 fault injection.
- `tests/integration/oi93-conflict-decision.test.ts`, 15 tests: the Owner's real session through PostgREST (Admin refused); two attempts and one `attempt_request_id` raced on one decision; the attempt against the same refund's webhook in both orders; the attempt against `invoice.paid` on the same project in both orders, with no AUTH-009 lock held; the re-check under the charge lock; U-4 (55P03 at about 5 s on four locks; 57014 at about 8 s); the 45 s deadline (fake clock), a client abort, the inconclusive status read and recovery by the same id.
- `tests/unit/wpb-static.test.ts` (one case): the payment invariants, exactly four replaced functions, no guard or ledger change, the verbatim extraction with only the Amendment 1 key change, the key rule in both callers, NULL-safe guards, registered financial audit actions, `private` not exposed, and the Owner screen's guards and deadline.
- `tests/e2e/wpb.spec.ts` (one test): the signed webhook quarantines a conflict; Admin is redirected; the Owner decides and applies it; axe on each state; the database agrees.

**Mutation checks:** 43 of 43 caught (the 42nd, an unbounded refusal summary, added after WP-C's U-3 note I-1; the 43rd, the classifier's obligations-other-project branch removed, added after WP-S's F-1). They cover:
- the Owner checks and the OI-120 `if not (…)` form;
- each refusal rule;
- the cap and `exhausted`;
- classification ignored; the whole-step rollback; the post-check; the S0 exact match;
- clearing (always true; a success row alone);
- items 1 and 7;
- canonical key order; the candidates and ledger classes of the fingerprint;
- idempotency; the in-progress status;
- each wrapper's `lock_timeout`;
- the classifier's livemode, refund-decision, other-project, several-holder and event-type checks;
- OI-121's shared key; I-4; Amendment 2's audit; I-5; I-6;
- the extracted refund-row lock (static).

Two misses during development were real gaps and were closed by new tests: item-1 clearing on a renewal charge (item 1 gives a renewal charge no gate) and an unisolated ledger-sensitivity case. One unreachable in-attempt check was removed; clearing re-verifies.

**Shared files:** AUTH-015 (PR #54) also adds to `050`, `audit-actions.ts` and `messages.ts`. A trial merge with its head `2b59ef3` is clean and both sets of additions coexist (WP-B review comment 7227962518).

**Suites** (local, fresh `supabase db reset`, CI order, at `c15ec68`):

| Command | Result |
|---|---|
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Pass |
| `pnpm test` | 22 files, 383 passed |
| `pnpm audit --audit-level=high`; `./scripts/check-migrations.sh origin/main` | No known vulnerabilities; no merged migration changed |
| `./scripts/run-db-tests.sh` | 2,081 assertions, 0 files failed (195: 157), after the `b5d8078` sync |
| `pnpm test:integration` | 10 files, 137 passed (oi93: 15) |
| `pnpm build`, `pnpm check:bundle`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e --trace off` | 67 passed |
| Lighthouse | Not run locally; runs in CI |

Exact-head CI is recorded in the pull request.

## 24. DEP-18 AUTH-018 implementation record (R1 interim scope loading and activation)

Implemented by the DEP-18 Review & Resolution session (`session_01RCnsL6oDLGr84wJPQZT3im`) on `claude/magical-mendel-glggv7`, from `main` at `12601a6` (PR #51, the R1 execution grant record). Grant: AUTH-018 (Decision 8a; 04 §4A "R1 interim scope loading and activation"; FD-05). Local and CI only, synthetic data only. No real content, no real approval evidence, no activation outside tests, no hosted operation and no production eligibility. Renumbered to 24 under OM-2 (§21 AUTH-017, §22 AUTH-015 and §23 WP-I PR #55 were taken first).

**Delivered:**
- Migration `20261127160000_dep18_scope_loader_activation.sql`, infrastructure only:
  - **Tables.** `private.billing_package_scope_approvals` has PK (package_key, scope_version) and an FK to `billing_packages`. `private.billing_package_scope_eligibility` has PK (package_key, scope_version, event, classification), FK `billing_package_scope_eligibility_version_fkey` to the sealed versions only, and a CHECK that `activated` rows are `development` or `test` only. Both tables are append-only, cannot be truncated and carry no API privileges.
  - **Owner functions.** Four Owner-only functions, each requiring fresh MFA and a live session: `record_package_scope_approval`, `load_package_scope_version`, `activate_package_scope_version` and `withdraw_package_scope_version`. Each has a security-invoker `public.` wrapper granted to `authenticated`, following the `create_agreement_version` pattern.
  - **Resolver.** A new body for `private.current_package_scope(text)`. Its name, arguments and return type are unchanged.
- Tests:
  - new pgTAP `supabase/tests/330_dep18_scope_loader_activation.test.sql` (137 assertions, including the F-1 review fix);
  - new integration `tests/integration/dep18-scope-loader-race.test.ts`: 5 concurrency scenarios, 5 repetitions each, real parallel connections;
  - the dispositions D-a to D-c and B-1 to B-4b below.

**Design decisions (Main rulings and Owner acceptance, 2026-11-27):**
- **C-1, serialization.**
  - **Locks.** Every governance function takes `dep18-scope-eligibility:<pkg>` exclusively, then the AUTH-007 sealing key `wpd18-scope-version:<pkg>` exclusively, always in that order. The resolver takes only the eligibility key, shared, held until commit. Plain AUTH-007 sealing still takes only the sealing key.
  - **Volatility.** The resolver changes from STABLE to VOLATILE, so that it reads only after its lock is granted. A STABLE function would read the calling query's earlier snapshot and miss a withdrawal committed while it waited.
  - **Reader guarantee.** Readers never wait on standalone AUTH-007 sealing: the existing race-test cases pass unchanged. Readers do wait on governance operations (approve, load, activate, withdraw), which hold the eligibility lock until they commit.
  - **Lock order.** Issuance takes the project row, then the shared eligibility lock. Governance takes eligibility, then sealing. There is no cycle.
- **C-2, the expected hash.** The expected hash comes only from the recorded approval for the exact (package, scope_version). The canonical hash already includes the version. The load request has no hash parameter, so it cannot supply or override it. A load without an approval, with different content, or for a version other than the next one fails closed and is audited.
- **OM-4 choices (accepted by Main):**
  - Refusals are returned as `{"ok": false, "error": code}` after an audit event committed with the call; they are never raised.
  - The constructor call runs inside a sub-block, so any sealing error rolls back only the partial version. It is audited by code and SQLSTATE only, because a constraint message could echo item text.
  - The eligibility table has no identity, index or comment, so the D-b closure stays at exactly six descriptors.
  - Fixtures resolve only in `development` and `test`, and can never be approved or activated. Any withdrawal makes a version unresolvable in every classification.
  - The Owner guards are NULL-safe (`… is not true`; OI-120). The tests cover a signed-in user with no staff role and an Owner whose role is revoked.
- The test choice for D11: synthetic non-legal strings (`PGTAP SYNTHETIC …`, `IT SYNTHETIC …`). The integration race uses only `prestige`, which no other integration or e2e test uses, because its records are append-only.

**Individual assertion dispositions (FD-14 format; Owner, 2026-11-27, relayed by Main):**

**B-1: D-1 stricter lexical rule (`tests/unit/wps-sales.test.ts`, `SCOPE_TABLE_MIGRATIONS`).**
- *Original:* the exemption covers exactly three migration files that may name the package-scope tables.
- *Replacement:* four exact names, adding `20261127160000_dep18_scope_loader_activation.sql`, plus one synthetic case showing that `20270101000000_dep18_scope_loader_activation_v2.sql` is still caught.
- *Original guarantee:* no other migration names the package-scope tables in any lexical form.
- *Replacement guarantee:* the same, except the exact loader file, which must define the new tables and the resolver body.
- *Exposure:* the loader file may name the tables. The D-a constructor, marker and label controls stay enforced on it. Runtime controls (no API privileges, construction guard, Owner gating, the approval-supplied hash) are unchanged.
- *Compensating coverage:* the similarly named case, and the existing loop over every migration.
- *Authorization:* Owner, 2026-11-27, exactly as proposed.
- *Evidence:* unit suite, 22/22 in `wps-sales.test.ts`.

**B-2: public RPC surface (`supabase/tests/050_security_events.test.sql`, test 8).**
- *Original:* the reviewed list of `public` functions executable by `authenticated`.
- *Replacement:* adds a "DEP-18 (AUTH-018 …)" group with exactly `activate_package_scope_version`, `load_package_scope_version`, `record_package_scope_approval` and `withdraw_package_scope_version`.
- *Original guarantee:* the signed-in RPC surface is exactly the reviewed list, with no audit writers.
- *Replacement guarantee:* the same, for the list including the four granted wrappers.
- *Exposure:* four new entry points, each re-authorizing inside its definer function.
- *Compensating coverage (required):* in 330, all four functions return `forbidden` for:
  - a signed-in user without a staff role;
  - a client, Sales, Admin and a revoked Owner;
  - the Owner at aal1, with a stale MFA verification, and with an ended session.
  Each of those is fresh MFA unless stated. anon cannot execute any wrapper (42501), so nothing runs. All 32 refusals are audited with the caller.
- *Authorization:* Owner, 2026-11-27, exactly as proposed.
- *Evidence:* 050 24/24 and 330 137/137.

**B-3: T-SALES-36 (`supabase/tests/310_wps_sales_commercial.test.sql`, test 165).**
- *Original:* "non-fixture rows are not affected by the allowlist"; a non-fixture version resolved under a missing classification.
- *Replacement:* the same setup, asserting that `scope_rows('signature') = 0`, titled "a non-fixture version without activation does not resolve, and never under a missing classification".
- *Original guarantee:* the fixture allowlist does not affect non-fixture rows.
- *Replacement guarantee:* the fixture allowlist is unchanged. Eligibility (04 §4A items 4 and 7) is a new, stricter gate.
- *Exposure:* none; behavior is stricter.
- *Compensating coverage (required), in 330:*
  - Positive: a non-fixture version that is independently approved, loaded and explicitly activated resolves in `development` and in `test`.
  - Negative: it does not resolve with no activation, under a missing classification (shown to read as `production`), under `staging`, when withdrawn (including withdrawal after activation), or when tampered.
- *Authorization:* Owner, 2026-11-27, exactly as proposed.
- *Evidence:* 310 217/217 and 330 137/137.

**B-4: header truncation (`supabase/tests/310_wps_sales_commercial.test.sql`, test 180).**
- *Original:* `truncate private.billing_package_scope_versions` fails with 42501.
- *Replacement:* it fails with 0A000, because the D-b eligibility foreign key refuses it before the trigger runs.
- *Original guarantee:* sealed headers cannot be truncated.
- *Replacement guarantee:* unchanged; truncation is still refused.
- *Exposure:* none.
- *Compensating coverage (required), in 330:* `truncate … cascade` is refused by the no-truncate triggers (42501). Row counts and content hashes of the headers and the eligibility events are equal before and after both attempts.
- *Authorization:* Owner, 2026-11-27, exactly as proposed.
- *Evidence:* 310 217/217 and 330 137/137.

**B-4b: header truncation in the isolated race (`supabase/tests-isolated/wpd18_commit_race.test.sql:168-169`, test 21).**
- *Original:* `like '42501 %'`.
- *Replacement:* `like '0A000 %'`, plus a CASCADE case expecting 42501 and a data-preservation case (row counts and content hashes). The file's plan and recorded count go from 25 to 27, as does `expected_plan` in `scripts/wpd18-isolated-commit-test.sh`. The immutability range comment is renumbered from 18-23 to 18-25, and the bounded-failure comment from 24-25 to 26-27.
- *Original guarantee:* sealed headers cannot be truncated.
- *Replacement guarantee:* unchanged.
- *Exposure:* none. Every concurrency assertion (tests 6-13) and every other assertion is unchanged.
- *Compensating coverage:* the two added cases.
- *Authorization:* Owner, 2026-11-27, on the same terms as B-4.
- *Evidence:* the isolated test PASS 27/27.

**D-a, D-b and D-c (approved in §13 "R1 execution grant record") as implemented:**
- **D-a:** the exact approved replacement. The real loader migration passes. The seven negative cases each fail: two calls; the call with `true`; the call outside the function; dynamic concatenation; the marker; the label; a similarly named file. No existing `expect(` changed.
- **D-b:** exactly the six approved lines; `expected_entries` changes from 37 to 43. Two allowlist comment lines now read "5 tables" and "43". Measured: "selected 43 of 719 dump entries", and the restore completed with no errors.
- **D-c:** the eligibility table is in the table set, its select and insert privileges are in the privilege row, and an eligibility `state` row is added. The measured fingerprint is **84 lines**, against a projection of 83. `expected_fingerprint_lines` changes from 67 to 84, and the parity comment reads "exactly 84 lines". Parity is identical: 84 fingerprint lines and 26 state lines. Main verifies each added line.

**Owner acceptance requirements, and where each is shown:**
- **Durable refusal auditing.** All refusals are returned with a committed audit event: 330 section 2, and the reasons in sections 3 to 7.
- **Serialization of load, activate, withdraw and issue, with no reactivation after withdrawal.** The integration race shows:
  - a withdrawal committed while issuance waits is seen, and issuance fails closed;
  - an issuance committed first stays valid while the withdrawal waits;
  - a load committed while issuance waits suspends issuance;
  - a withdrawal first makes a waiting activation fail with `withdrawn`;
  - concurrent identical activations and loads produce one record and one event.
  Both commit orders are covered, with no deadlock. The waits are observed in `pg_locks`.
- **Idempotent replay.** Approval, load, activation and withdrawal replays return `replayed: true`, with no new version or event: 330 and the integration race.
- **No item text.** None in audit events, refusal results or errors: 330 section 8, and the load error is reported by SQLSTATE only.
- **Approval binding.** The approval binds the exact package, version and content hash. The approval is the expected hash for loading (C-2), and activation requires it to equal the sealed hash, re-verified from the items.
- **No ineligible version issuable.** Sales issuance returns `scope_definition_missing` for inactive and withdrawn versions, and a newer loaded version suspends issuance. There is no fallback, and fixtures resolve only in `development` and `test`.

**Verification (local stack: Supabase CLI 3.2.0, checksum verified; a fresh `supabase db reset` before each suite; CI order; re-run on the merge with `main` at `2d5705e`):**
- `pnpm lint`, `pnpm typecheck` and `pnpm format:check`: pass.
- `pnpm test` (unit): 22 files, 381 tests, pass on the merged tree.
- `supabase test db`: 34 files, 1996 tests, PASS (on the F-1 head merged with `main` at `208d7e7`; 1988 before F-1).
- `./scripts/wpd18-isolated-commit-test.sh`: PASS 27/27.
- `pnpm test:integration`: 10 files, 127 tests, pass.
- `pnpm build`, `pnpm check:bundle` and `pnpm build:production-check`: pass.
- `pnpm test:e2e --trace off`: 66 passed on the merged tree (65 before the merge). The local run used the container's preinstalled Chromium build 1243, not the 1255 build pinned by Playwright 1.65.1; CI uses its own install.
- Not run locally: the Lighthouse job, the dependency audit and the secret scan. Exact-head CI is authoritative.

**Review fix F-1 (WP-C security review, confirmed by Main; OM-4 within the grant):** the four governance functions build the audit `target_id` only from a package key validated against `private.billing_packages` (otherwise `invalid`) and the integer version (otherwise `invalid`), so no refusal can write caller-supplied or unbounded text into the immutable audit log. 330 section 9: a 200,000-character key from a client and from the Owner yields exactly one refusal row per call with a bounded target, and no row carries the key. Mutation (raw key restored in all four functions): 3 of the 8 F-1 assertions fail. The migration header also records that the C-1 reader guarantee assumes READ COMMITTED (the PostgREST default).

**Not changed:** `private.is_owner()` and every other existing function and migration outside AUTH-018 (OI-120 is separate); `issue_order_summary`; AUTH-007 sealing objects; `seed.sql`; dependencies; CI workflows and required checks.

## 25. WP-I AUTH-016 implementation record (OI-115 local part; OI-119 dispositions)

Implemented by WP-I (`https://claude.ai/code/session_01RCnsL7k3rDKjjpTicExTsF`) on `wp-i/oi-115-env-consistency`, branched from `12601a65d7dd892840a7d74ff9de3a0073bd56ac` (the verified merge of the R1 execution grant record). Local and CI only: no provider, hosted-environment or production access, no dependency or `package.json` change, no change to required checks.

### 25.1 Scope delivered

| Part | Delivered |
|---|---|
| Migration `20261127150000_wpd_oi115_environment_consistency.sql` (reserved) | `private.environment_consistent()`: true when `private.runtime_environment` (C2) is absent, or C2 and `private.environment_settings` (C1) hold the same value. **D1:** `private.app_environment()` raises 42501 `environment classification disagreement (OI-115)` otherwise, so every consumer (`is_production`, `stripe_mode`, `expected_livemode`, fixture guards, package-scope resolution, billing evidence stamps, termination paths) fails closed unedited. `private.scanner_permitted()` also requires agreement. `private.environment_classification()` (definer) and a security-invoker `public.environment_classification()` return the raw `{c1, c2}` without raising; execute for `service_role` only (T-TEN-06 holds). No table, trigger or constraint change; the seed and hosted provisioning are unaffected. **D2:** staging keeps no explicit row (both absent reads as `production`) |
| Application check | `src/server/environment-consistency.ts`: strict parsing of the RPC response; the OI-119 point 1 rule; a per-process memo that caches a pass only (an OM-4 engineering choice; a failure is never cached, so every later use is checked again). Called first in `acceptUpload`, `retryUploadScan` and `verifyLiveDeployment` (`fulfillment.ts`), and in `getStripeGateway()` before the mock exists (point 2). The billing-job test runner checks before its mock |
| OI-119 option A | Setup and restoration statements only, in the six approved files and sites (25.2) |
| New tests | pgTAP `410_wpi_oi115_environment_consistency.test.sql` (37); unit `wpi-environment-consistency.test.ts` (123) and `wpi-oi115-seams-fail-closed.test.ts` (10) |
| Hosted part | Deferred to AUTH-003: record on staging that neither row exists (`public.environment_classification()` returns `{c1: null, c2: null}`) |

### 25.2 OI-119 individual dispositions (FD-14 format; approved by the Owner, 2026-11-27)

**Option A: setup-only restores in six existing pgTAP files.** Line numbers are at the base `12601a6` (insertions only; `git diff` removes no line).
- *Original:* each site moves C1 away from `development` (to `staging`, `preview`, `test` or absent) while the seeded C2 `development` row stays (210: C2 `test` while C1 stays `development`). Under D1 these are disagreements, so the first environment read raised and the remainder of each file aborted (6 of 33 files, 247 subtests).
- *Replacement:* at each site the C2 row is saved to a per-site temporary table and removed with the C1 change, and restored from that table after C1's own restoration, followed by `pg_temp.oi119_assert_restored(<site>)`, a setup-only guard that raises unless both tables again hold exactly one `development` row (it adds no pgTAP assertion). Sites and inserted lines:
  - 100: after l.138 (+15: guard function, save, remove) and after l.143 (+2: restore, guard);
  - 110: after l.105 (+15) and after l.111 (+2);
  - 120: after l.553 (+15) and after l.559 (+2);
  - 210: after l.311 (+2: `update private.environment_settings set app_env = 'test'`, so C1 agrees with the runtime `test` row it inserts; the file never restored C2 and the transaction rolls back);
  - 310: after l.618 (+15), l.649 (+1: `insert … runtime_environment ('test')` beside C1 `test`), l.653 (+3: remove, restore, guard), l.761 (+3), l.768 (+2), l.802 (+3), l.827 (+2);
  - 400: after l.298 (+15) and after l.307 (+2).
- *Original guarantee:* each block's assertions about staging, preview, test, missing (production) and development classifications.
- *Replacement guarantee:* identical. No assertion, expected value, description or plan count changes (plans 42, 142, 106, 81, 217, 33 unchanged), and the C2 row is absent exactly where C1 says non-development, which is the only state D1 allows.
- *Exposure:* none. The guard aborts the file if a restore is missing, so no later assertion can run under contaminated state.
- *Compensating coverage:* pgTAP 410 tests the disagreement cases directly.
- *Evidence:* each file passes in isolation at its plan count and the full suite passes in sequence (25.3); mutation: deleting the 100 restore line makes the file fail with `OI-119: classifications not restored at 100`.

**Point 1: the application rule.**
- *Rule (approved):* with `APP_ENV` development or test, both classifications must be present, agree, and be development or test. With staging, preview or production, C2 must be absent and C1 absent or equal to `APP_ENV`. Anything else, an unreadable classification or a malformed response is refused.
- *Guarantee:* no mock scanner, mock verifier or mock gateway activates on disagreement, and none activates in staging, preview or production. AUTH-003's hosted-staging requirements (migrations only, no seed, no row) are preserved.
- *Evidence:* `wpi-environment-consistency.test.ts` enumerates all 105 `APP_ENV` × C1 × C2 combinations (9 pass), covering missing, unknown, conflicting and disallowed values, plus strict-parse refusals, read and RPC errors, and pass-only memoization. `wpi-oi115-seams-fail-closed.test.ts` shows that in preview, staging and production the scanner is null, the verifier is the real one, and the environment schema refuses `STRIPE_GATEWAY=mock`.

**Point 2: async gateway acquisition.**
- *Change (approved):* `getStripeGateway()` becomes `async` and awaits the environment check before the mock is created, with an `await` at the three call sites: `src/app/api/stripe/webhook/route.ts` and `src/app/portal/projects/[projectId]/billing/actions.ts` (×2).
- *Consumer inventory:*
  - direct: those three sites only;
  - indirect (receive the gateway as a parameter, unchanged): `startInitialCheckoutAsCaller`, `beginPaymentMethodRecoveryAsCaller` and `receiveStripeWebhook` → `executeOutboundRequest`, `verifyPrices`, `runPaymentMethodLookups`, `runBillingJobs`, `runReconciliation` (`src/server/services/billing.ts`);
  - tests and harness construct `MockStripeGateway` directly (`wpb-billing`, `oi91-dispatch-revocation`, `wpb-billing-service`, `wpc-fixtures`, the billing-job runner, which now checks first).
- *Guarantee:* a failed check rejects inside `getStripeGateway()`. The checkout and recovery actions rethrow before reaching `startInitialCheckoutAsCaller` or `beginPaymentMethodRecoveryAsCaller`, so no outbound row is claimed or confirmed and no provider request starts. The webhook route keeps verifying and storing the event, with a `null` gateway (card lookups wait for the job, as when no gateway is configured). Payment logic, authorization, idempotency, webhook verification and financial state transitions are unchanged (no change to `billing.ts`, `gateway.ts` or `mock-gateway.ts`).
- *Evidence:* `wpi-oi115-seams-fail-closed.test.ts` shows that on a failed check the mock is never constructed and the global holder stays empty, neither billing service is called, and the webhook service receives `null`; with agreement the same mock is passed on unchanged.

**WP-D18 isolated-copy allowlist, 43 → 48 (approved by the Owner, Consolidated Owner Directive, 2026-11-28).**
- *Original:* `supabase/tests-isolated/wpd18-restore-allowlist.txt` restores exactly 43 descriptors (`expected_entries=43` in `scripts/wpd18-isolated-commit-test.sh`; fingerprint 84 lines, plan 27). The closure holds `private.app_environment()` and `environment_settings` but not `runtime_environment`.
- *Replacement (approved):* add exactly `FUNCTION private environment_consistent() postgres`, `ACL private FUNCTION environment_consistent() postgres`, `TABLE private runtime_environment postgres`, `TABLE DATA private runtime_environment postgres` and `CONSTRAINT private runtime_environment runtime_environment_pkey postgres`, and set `expected_entries=48`. Fingerprint (84), state (26 lines) and plan (27) unchanged.
- *Original guarantee:* the disposable copy restores exactly the package-scope closure, no more and no less.
- *Replacement guarantee:* the same, for the closure that now includes what the D1 body of `private.app_environment()` reads.
- *Exposure:* none beyond the two objects `app_environment()` depends on.
- *Compensating coverage:* the script still requires each line to match exactly one dump entry and the exact count; parity stays byte-identical.
- *Evidence:* without the change the copy fails with `function private.environment_consistent() does not exist`; with it, "selected 48 of 799", "identical: 84 fingerprint lines and 26 state lines", PASS (27/27).

**OI-123: setup-only restores in `330_dep18_scope_loader_activation.test.sql` (approved by the Owner, Consolidated Owner Directive, 2026-11-28).** Line numbers at `23346ef`; insertions only.
- *Original:* four sites change `private.environment_settings` while the seeded runtime row stays `development`: S1 l.356–369 (staging, preview, absent, development), S2 l.387–398 (test, staging, absent, development), S3 l.405–410 (test, development), S4 l.442–447 (test, development). Under D1 the file aborted at l.358 after 76 of 137 tests.
- *Replacement:* a setup-only guard `pg_temp.oi123_assert_restored(site)` (adds no assertion); at each site the runtime row is saved and removed with the change (and set to `test` where the billing row is `test`, so the two agree), then restored from the saved row and the guard runs. +40 lines, none removed.
- *Original guarantee:* the B-3 and per-classification activation and withdrawal cases.
- *Replacement guarantee:* identical: no assertion, expected value, description or plan (137) changes.
- *Exposure:* none; the guard aborts the file if a restore is missing.
- *Evidence:* 330 137/137; guard mutation (S3 restore removed) fails with `OI-123: classifications not restored at s3`; full suite in 25.3.

### 25.3 Verification (local, fresh reset in CI order; rerun after merging `main` at `df39d14` with a merge commit, with both 25.2 Owner-approved changes applied)

| Suite | Result |
|---|---|
| `supabase db reset` (every migration plus the seed) | Pass |
| `supabase test db` | 38 files, 2,315 tests, all pass (330: 137/137) |
| `scripts/wpd18-isolated-commit-test.sh` | 48 entries; identical 84 fingerprint lines and 26 state lines; PASS (27/27) |
| The six edited files in isolation | 42, 142, 106, 81, 217, 33: all pass |
| pgTAP 410 mutations | M1 (no raise): 9 failures; M2 (scanner without the consistency term): 3; M3 (reader granted to `authenticated`): 3 |
| `pnpm audit --audit-level=high` | Pass |
| `pnpm test` | 517 tests, all pass |
| `pnpm test:integration` | 12 files, 144 tests, all pass |
| `pnpm lint`, `pnpm typecheck`, `pnpm format:check` | Clean |
| `pnpm build`, `pnpm build:production-check` | Pass |
| `pnpm test:e2e` | **Not run locally:** the pinned Playwright expects a Chromium build that is not installed in this container (`browserType.launch: Executable doesn't exist`); no test executed. The exact-head CI run is the evidence |

Exact-head CI and the WP-C (security) and Main reviews are recorded in the PR. Merge is Main's under OM-6(b) once every condition holds.

## 26. OI-120 AUTH-019 implementation record (`private.is_owner()` NULL-safe)

Implemented by the DEP-18 Review & Resolution session (`session_01RCnsL6oDLGr84wJPQZT3im`), originally from `main` at `2d5705e` (PR #56, which records AUTH-019), re-applied on `main` at `23346ef` after PR #57 merged. Numbered §26, the next free section (§25 is claimed by WP-I PR #55; OM-2).

**Change:** migration `20261127125000_oi120_is_owner_null_safe.sql` runs `create or replace function private.is_owner()` with the body `select coalesce(private.staff_role_of((select auth.uid())) = 'owner', false);`. Every attribute is unchanged: language sql, stable, security definer, `search_path=""`, owner `postgres`, ACL `{postgres=X/postgres,authenticated=X/postgres}`, signature `() → boolean`. No call site, policy, grant or other function changes, `staff_role_of` included. A hosted database receives all migrations from scratch in filename order under AUTH-003, so `20261127125000` applies correctly whatever the merge order relative to AUTH-018's `20261127160000`.

**Inventory: all 45 sites named in AUTH-019 inherit the fix (27 direct sites and the 18 `owner_ok()` callers); the re-check against the migrations merged after the grant (AUTH-010 `20261127130000` and `20261127130100`, AUTH-015 `20261127140000`, AUTH-018 `20261127160000`) adds one more inheriting site and nine already NULL-safe sites (rows (a′) and (f)):**

| Class | Sites | Before (NULL) | After (false) |
|---|---|---|---|
| (a) Conjunctive guard: `if not (is_owner() and …)`, including the staff-invitation form `p_kind = 'staff' and not (is_owner() and mfa_is_fresh())` | `20261123060000` :510, :658, :742; `20261125120100` :278, :367; `20261124140000` :1475; `20261124140200` :1212, :1286, :1317, :1527, :1797; `20261124160000` :216, :239; `20261124160100` :2167, :2214, :3326; `20261126120200` :432; `20261127120000` :430; `20261127120100` :26 | `not NULL` is NULL, so the IF is skipped and the refusal is bypassed | the refusal fires |
| (b) Disjunctive guard: `if not is_owner() or not … or not …` | `20261123060000` :688, :715; `20261125120100` :468 | `NULL or false or false` is NULL, so the refusal is bypassed | the refusal fires |
| (b′) Mixed guard: `if not is_owner() and v_resp.response_id is null` | `20261124140200` :1136 | `NULL and true` is NULL, so the rejection is bypassed | the rejection fires (bypass-closing semantics, as in (a) and (b)) |
| (c) Expression feeding other guards | `20261124160100` :3638 (the `owner_ok()` body; its 18 callers at :1724, :1739, :3648, :3682, :3712, :3758, :3796, :3854, :3882, :3926, :3950, :3981, :4017, :4036, :4069, :4136, :4200, :4380 all use `if not private.owner_ok(…)`); :4709 (`(is_owner() and …) or (member path)`) | `owner_ok()` is NULL, so each caller's refusal is bypassed. At :4709, `NULL or false` is NULL (bypassed); `NULL or true` is true | `owner_ok()` is false, so every caller refuses. At :4709 the member path is unchanged; only the bypass closes |
| (d) Already equivalent | `20261124140200` :777 (`redact_gate_result(…, is_owner())` uses `case when p_owner`, so NULL already takes the redacted branch); :1635 (`v_owner` inside `operational_queue`, after the `wpc_is_staff_aal2()` gate, so the caller is staff and `is_owner()` is never NULL; `case when v_owner` also treats NULL as false) | the same as false | unchanged behavior |
| (a′) Conjunctive guard, merged after the grant | `20261127140000`:137 (`authorize_publication`, current body, AUTH-015; it replaces the earlier body at `20261124140200`:1797) | `not NULL` is NULL, so the refusal is bypassed | the refusal fires |
| (f) Already NULL-safe, merged after the grant | `20261127130100` :166, :278, :483, :506 (AUTH-010: `record_financial_conflict_decision`, `retry_financial_conflict_application`, `financial_conflict_attempt_status`, `financial_conflict_events`); `20261127140000`:39 (AUTH-015: `reopen_failed_publication`); `20261127160000` :107, :186, :289, :377 (AUTH-018: the four package-scope governance functions). `20261127130000` has no call site | `(… ) is not true` / `is_owner() is not true` already refuses NULL | unchanged behavior |
| (e) Outside the 45: RLS policies and ACL lists | policies `20261123060000`:1014, `20261124120000`:445 and :447, `20261124160100`:4778 and :4786–:4792 (`(select is_owner()) or …`); `20261123060000`:903 (revoke list) | in USING, NULL denies just as false does; `NULL or X` equals `false or X` whenever it decides | unchanged behavior; no change needed |

**Tests:** `supabase/tests/420_oi120_owner_guard_null_safety.test.sql`, 60 assertions.
- **Regressions:**
  1. A fresh-MFA client cannot create an agreement version.
  2. A fresh-MFA client cannot promote the Admin (`…0002`) to Owner through `set_staff_role` (the reproduced case).
  3. A revoked former staff member, the Admin revoked using the 225/240 pattern, cannot re-grant itself Owner.
  Extra guard: the Admin promoting itself is refused, as it already was before the fix.
- **Representatives:** `create_agreement_version` and `create_invitation('staff', …)` (class a, contractual and staff invitation); `register_client_site_target` (class a, WP-C); `set_staff_role` (class b); `place_billing_hold` (class c, an `owner_ok()` caller); `project_billing_status` (class c, :4709). The callers are:
  - a fresh-MFA client, Sales, an Admin and a revoked former staff member, each refused by all six with no privileged state change: agreement versions, invitations, site targets, billing holds and every staff role compared before and after;
  - anon, which cannot execute any of them (42501).
- **Genuine Owner (fresh MFA):** succeeds on all six, and restores the revoked Admin. The Owner without fresh MFA is still refused.
- `is_owner()` and `owner_ok(false|true)` are false, never NULL, for every non-Owner, and true for the Owner.
- The attributes and ACL match the pre-fix values recorded above.

**Mutation test (scratch run, repeated on `main` at `23346ef`):** with the original body restored on the local database, 420 fails 30 of 60, including all three regressions and the no-state-change checks. Because the client's escalation then succeeds first, the later Admin cases fail as a consequence. With the fix, 60 of 60 pass.

**Verification (local stack, Supabase CLI 3.2.0; fresh `supabase db reset`; CI order; `main` at `23346ef` plus this change only):**
- lint, typecheck and format: pass.
- unit: 384 tests, pass.
- check-migrations: pass.
- pgTAP: 37 files, 2278 tests, PASS. That is `main`'s existing 2218 unchanged, plus 420's 60. No existing assertion changed.
- isolated WP-D18: PASS 27/27.
- integration: 144 tests, pass.
- build, check:bundle and build:production-check: pass.
- e2e: 67 passed. The local run used the preinstalled Chromium 1243, not the 1255 build Playwright 1.65.1 pins.
- Not run locally: Lighthouse, the dependency audit and the secret scan.

## 27. WP-B AUTH-020 implementation record (OI-122, test-only)

Implemented by WP-B (`session_01RCnsL4vnvrx7b11HRxeo8T`) from `main` at `8107841` (PR #63). Numbered §27, the next free section.

**Change (one file, exactly the approved diff):** `tests/integration/oi91-dispatch-revocation.test.ts`, base SHA-256 `bd596cff…acbe`, diff SHA-256 `3675e8f8…8c5c` (as reported by WP-B; not independently verified, see the Main note below), patched file SHA-256 `27d324b01a9278a99199a2e713dbaf928f3287cf9da0fada6efbf6d948cd77fb` (verified).

*Main note (2026-11-28):* **Diff-hash verification limitation (Owner, 2026-11-28):** the approved diff SHA-256 `3675e8f8…` is as reported by WP-B and was **not independently verified** by Main or WP-I, because it depends on the exact patch formatting and is not reproduced by `git diff` (which gives `492b0423…`). It is not represented as independently verified. The independently verified evidence is the base file SHA-256 `bd596cff…` on `8107841` and the patched file SHA-256 `27d324b0…` on `2ae3639`, which together determine the change exactly.
- **R1:** `waitsOnRowOf` keeps polling past an unidentified sample within the same 40 × 50 ms deadline, and still returns `"unknown"` or `null` when the table is never identified.
- **R2:** an `abandon` helper and `try/finally` in `probe()` and `race()`. On failure only: the holders roll back first, the call under test is awaited for at most 10 s, a runner whose call settled is rolled back, and every connection is ended. Only cleanup errors are swallowed.
- **Unchanged:** all 70 `expect(` assertions and their expected values (byte-identical), the success path (the same statements in the same commit order), the lock-order guarantees and the 5 s lock-timeout test. No production code, migration, permission, financial behavior, workflow, dependency or other test file changes.

**Acceptance evidence (local stack, Supabase CLI 3.2.0, PostgreSQL 17.4, synthetic data; the local-only copies, runners and logs are kept with the session evidence, never committed):**

| Item | Result |
|---|---|
| A1, before the fix (`main`'s file, SHA-256 `bd596cff…`) | Under the reproducing load (6 parallel instances of the describe): **2 of 42 runs failed**, `expected 'unknown' to be 'final_balance_invoices'` and `expected 'unknown' to be 'payment_authorizations'`. A synthetic lock-churn load generator did not reproduce it (0 of 40) and is not used as the A2 load |
| A2, after the fix | **0 of 40** failed alone; **0 of 42** under the same 6-way parallel load |
| A3, the counter (diff `fba5c391…`) | Under the same load, 42 of 42 passed; 4 transient `"unknown"` samples occurred (4 distinct waits), each followed by identification of the expected table (the assertion passed). A second local-only variant that also records the resolving sample (diff `839e3927…`): 42 of 42 passed, 3 transient samples, each identified as `payment_authorizations` on the next sample |
| A4 (i) | `private.confirm_outbound_dispatch` locally redefined to lock the outbound row first: "the confirmation" fails with `deadlock detected` (40P01); the other 5 pass. The original body was restored (source MD5 `248795b3…` and ACL match the pre-control values) |
| A4 (ii), (iii) | An advisory-lock wait (never a tuple lock) returns `"unknown"` and the probe fails with `expected 'unknown' to be 'payment_authorizations'`; a never-blocked call returns `null` and fails with `expected null to be 'payment_authorizations'` |
| A5 | A deliberately wrong expected table in `probe()` on a real fixture, and an unidentified wait in `race()`, each fail with the original assertion; afterwards `pg_stat_activity` shows no idle-in-transaction or lock-waiting session and `pg_locks` no advisory or row lock on the tables involved. In that same file run, every later suite (the file's 23 tests) passed with no 55P03 (31 of 31) |
| A6 | After a fresh `supabase db reset`: the full file twice, 23 of 23 each time; the full `pnpm test:integration`, 12 files, 144 passed, no 55P03. Exact-head CI is recorded in the PR |

**A7 (cleanup is bounded, never commits, leaves nothing and never hides the original error):**
- **Mechanism:**
  - Every connection in the file runs inside an explicit `begin`; only `done()` commits. `abandon()` issues only `rollback` and `end()`.
  - Holder rollback: the holder is idle when cleanup starts (each of its queries is awaited), and `ROLLBACK` takes no lock, so it returns in one round trip.
  - The wait: an explicit 10 s timer raced against the call, then cleared.
  - Runner rollback: sent only when the call has settled, so the runner is idle.
  - `end()` (`pg@8.16.3` `Client.end`): with an active query it destroys the socket; otherwise it sends Terminate and resolves on socket close. An already-ended client resolves at once.
  - The server rolls back the transaction of any session whose client is gone.
  - In this file the runner can wait only on the holder (or `first`), which cleanup rolls back first; files run without parallelism (`fileParallelism: false`); and the dispatch functions carry `lock_timeout = 5s`.
  - Outer bound: the integration `testTimeout` and `hookTimeout` of 60 s.
- **Measured (local-only timing copy, diff `3e66adb9…`):**
  - Five failed checks whose call settled: complete cleanup in 2.5–12.0 ms. Holder rollback was at most 1.4 ms, and `end()` at most 6.4 ms.
  - One case where the runner was blocked by a **foreign** connection, so its call never settled: the wait ended at 10.005 s, the runner rollback was skipped, `end()` took 3.3 ms, and cleanup took 10.01 s in total. The failure reached the test 12.6 s after the call started, within the 60 s bound. The runner's backend remained only while the foreign blocker held its lock, and was gone 11 ms after the blocker released.
  - The runners' inserted rows were absent afterwards in both cases, so nothing committed. `pg_stat_activity` and `pg_locks` were clean after every failure.
- **The original error is never suppressed:**
  - Assertions: A4 (ii), A4 (iii) and A5.
  - A database error raised by the call under test (`division by zero`) propagates unchanged.
  - The deadlock in A4 (i) is reported as `deadlock detected`.

## 28. PWP-1 AUTH-021 implementation record (contractual instruments, bundles, governance events, withdrawal)

Implemented by the DEP-18 Review & Resolution session (`session_01RCnsL6oDLGr84wJPQZT3im`) on `claude/magical-mendel-glggv7`, from `main` at `dbf7e9e` (PR #68). Grant: AUTH-021 (OD-1 to OD-12, OD-18; OI-98, OI-99, OI-103, OI-104, OI-106, OI-109; FD-15; 04 §4A v0.11.0). Local and CI only; synthetic and fixture data only. No real or counsel-derived content, approval evidence, hosted operation, staging or production eligibility, domain event or dependency. Numbered §28, the next free section; it may be renumbered under OM-2.

**Delivered:** migration `20261128100000_pwp1_contract_instruments.sql` (infrastructure only; SHA-256 recorded in the PR), seed fixtures, pgTAP `340_pwp1_contract_instruments.test.sql` (174 assertions), unit `tests/unit/pwp1-contracts.test.ts` (golden vectors and lexical guards), integration `tests/integration/pwp1-contract-race.test.ts` (six scenarios, five repetitions each), ten audit actions in `src/domain/contracts/audit-actions.ts`, and the pre-approved D-1 exemption (OD-11(i)) in `tests/unit/wps-sales.test.ts`.

**Objects (all new; no existing object changed):**
- Tables (private, no API privileges, append-only, no truncate): `contract_instrument_versions` (package specification per package, maintenance specification, shared terms; sealed on creation; canonicalization version, SHA-256, fixture flag, provision identifiers; CR rejected), `contract_bundles` (exactly one agreement version, a package instrument of its own package, a maintenance and a shared-terms instrument, a sealed scope version and its hash, the scope-to-provision map, the bundle hash), `contract_bundle_approvals` (legal approval: reference and evidence hash only, bound to the bundle hash), `contract_bundle_eligibility` (activation, `development` and `test` only by CHECK; irreversible withdrawal with actor, reason, time and authorization reference). Content rows are accepted only through the internal constructors (transaction-local marker) and fixture rows only under a consistent `development` or `test` classification.
- Canonicalization (OI-109): `spotlight.contract_instrument.v1` and `spotlight.contract_bundle.v1`, length-prefixed fields in a fixed order, UTF-8 as supplied, no normalization; golden vectors in 340 and, independently recomputed, in the unit suite.
- Interface (frozen by Main, 2026-11-28): F1 `private.current_contract_bundle(text)` (VOLATILE; shared `dep18-scope-eligibility:<pkg>` lock; newest sealed bundle if eligible, otherwise nothing; nothing under an inconsistent classification or in production); F2 `contract_bundle_verifies(uuid)` and F3 `contract_bundle_withdrawn(uuid)` (STABLE; to be called in a statement after the one that takes the shared lock); F4 the lock key; F5 the snapshot v2 component identifiers (bundle id, hash and canonicalization; agreement id and text hash; the three instrument ids and hashes; package, scope version and scope hash).
- Owner functions (fresh MFA, live session, NULL-safe guards, consistent `development`/`test` classification, refusals returned with a committed audit event, security-invoker wrappers): `create_contract_instrument_version` (the OD-5 loader, option (a): expected hash verified before anything is written; fixture-labelled content refused), `seal_contract_bundle`, `record_contract_bundle_approval`, `activate_contract_bundle`, `withdraw_contract_bundle` (consistent classification required; not limited to development and test, since it only removes eligibility). Staff reader `contract_bundle_documents` (Owner and Admin; fixtures only under `development`/`test`).
- Seed (OD-9): one fixture maintenance and one fixture shared-terms instrument, a fixture package instrument per package and a fixture bundle per package (fixture agreement and fixture scope version 1), through the internal constructors with the fixture flag.

**Rulings applied (Main, 2026-11-28, OM-4):** Q1 option (a); Q2 the 8,192-byte check at bundle sealing and in F2 only (the scope-version side is covered by the WP-S table constraints and `order_summaries`); Q3 as amended (no client predicate stub; the staff reader and the negative half of T-CON-11 here, the positive client path a new object in PWP-2); Q4 the seed and a new lexical guard test; Q5 the OD-10 scope approval checked read-only at sealing; Q6 no foreign key to the scope versions (function-verified); Q7 two governance tables; Q8 `classification_inconsistent` before any `app_environment()` call.

**Lock order (OD-3, OD-4):** instrument construction takes only `contract-instrument:<kind>:<pkg|*>`, held alone; sealing, approval, activation and withdrawal take the per-package lock exclusively, then the bundle row `FOR UPDATE`; the resolver takes the per-package lock shared, held to commit. No payment, invoice, release or Sales lock.

**Acceptance evidence (local; full numbers in the PR):** T-CON-01 (no refused seal leaves a bundle), T-CON-03 (recomputed hashes; tampered instrument, scope item and agreement each fail closed with no fallback; activation refuses a tampered bundle), T-CON-04, T-CON-05 (a 40-item scope over 8,192 bytes rejected at sealing), T-CON-06 (Owner only, irreversible, audited, content unchanged, no reactivation, no fallback), T-CON-08 (identical replays return the existing record; conflicting loads and approvals fail closed and are audited), T-CON-11 (staff path; clients, Sales and no-role users read nothing; fixtures unreadable under staging, production and inconsistent classifications), T-CON-12 and requirement F (fixture bundles never resolve under staging, preview, production or an inconsistent classification; fixtures cannot be created there; a fixture bundle can never be approved or activated), golden vectors; T-CON-02 and the withdrawal side of T-CON-07 and requirement A in the integration suite (real connections, both orders, five repetitions, waits observed in `pg_locks`, no 40P01 or timeout). The isolated restore is unchanged (48 descriptors, 84 fingerprint lines, 27/27); 330 is unchanged at 137/137.

**050 (B-1a, Owner-approved 2026-11-28):** the three approved lines are inserted immediately before the existing DEP-18 (AUTH-018) group comment, adding the six public wrappers; no existing entry, plan or description changed. Local pgTAP after the change and the WP-I notes: 0 files failed, 2,489 assertions.

**Test-order correction:** the integration race test first approved its synthetic agreement effective `current_date`, so in CI order it became the newest usable agreement and the e2e T-AGR-01/T-AGR-08 test failed. It is now effective 2026-11-01, before the fixture agreement; test-only, no product change. Local CI order after the fix: integration 150/150, e2e 67/67.

**WP-I non-blocking notes (applied with Main's approval, own new files only):** N-1, the race test pins the issuance-versus-governance outcome to `scope_definition_missing` in both orders, because the synthetic scope version is loaded but never activated. N-2, 340 adds activation and fixture-instrument creation refusals under `preview` (172 → 174 assertions). N-3, every race scenario rolls back both connections in a `finally`, so one failed check cannot hold locks into later scenarios.

## 29. WP-C AUTH-023 implementation record (PWP-5a: scope confirmation, signer acknowledgment, operational notes, release gate)

Implemented by WP-C (`session_01RCnsL4zY9edGTBFKQUbXM6`) from `main` at `5c47d16`, under AUTH-023 with Main's rulings Q1 to Q4 and the Owner's B-1c disposition. Numbered §29, the next free section (renumbered from §28 under OM-2 after PR #69 merged at `459e66c`; main merged into this branch with a merge commit). Local and CI only, synthetic data only. No provider request and no hosted operation.

**Delivered (05 §3A, OI-111; OD-14, OD-15):**
- **Migration** `20261128110000_wpc_pwp5a_scope_confirmation.sql`, at the reserved timestamp (OD-12). It adds three insert-only tables, each with a non-null `project_id`, RLS and the restrictive `_staff_aal2` and `_active_user` policies:
  - `scope_confirmations`: immutable versions, numbered per project. Each one carries:
    - the client requirements, the fulfillment selections and the separately authorized amendment references;
    - the bound effective order summary, by id and `order_summary_sha256`;
    - the accepted intake submission;
    - a `spotlight.scope_confirmation.v1` SHA-256 content hash.
  - `scope_confirmation_acknowledgments`: one per version. Each one records:
    - the authorized signer (`agreement_acceptances.signer_user_id` of the effective summary, ruling Q1) and the signer's verified email;
    - two checks, `acknowledged` and `checkbox_unchecked_by_default`, both forced true by CHECK;
    - the IP address, user agent and request id.
  - `project_operational_notes`: staff-only and append-only, outside the contractual snapshot (OI-100).
- **Entry points** (each private implementation re-authorizes the caller with NULL-safe guards, OI-120):
  - `record_scope_confirmation`: Owner or Admin, at aal2. Intake must be `accepted_by_staff` and the agreement `effective`. An unchanged confirmation is refused.
  - `acknowledge_scope_confirmation`: the authorized signer only, for the exact current version. It requires a verified email and both explicit flags, and it is refused for a superseded, stale or changed version.
  - `record_operational_note`: Owner or Admin, at aal2.
  - `scope_confirmation_status`: staff, or a member of the project.

  Every success and every business refusal is audited. No audit event contains confirmation or note text.
- **Gate.** One hunk in `release_preview`, placed after the `release:` lock. It refuses every actor (`scope_confirmation_required`, `scope_confirmation_stale` or `scope_acknowledgment_required`) unless the latest version is bound to the current effective summary, by id and hash, and acknowledged (ruling Q2).
  - Confirmation and acknowledgment take the same lock, so the three operations serialize.
  - Any new version needs a renewed acknowledgment (OD-14).
  - No bypass, override or on-behalf path exists (T-LC-19).
- **Queue.** One hunk in `operational_queue` adds `awaiting_scope_acknowledgment`. The earlier `scope_confirmation_needed` item was dropped; Main accepted that, since the gate refuses either way and no queue assertion changes.
- **Privileges** (Owner verification clarification 3, as ruled by Main):
  - public wrapper: SECURITY INVOKER, `search_path=''`, execute by `authenticated` only;
  - private implementation: SECURITY DEFINER, `search_path=''`, execute by `authenticated` only (no anon, service_role or PUBLIC), re-authorizing with NULL-safe guards;
  - internal helpers: no API-role execute. The one accepted exception is `private.current_scope_confirmation_id`, granted to `authenticated` for the RLS policy. It returns nothing for a caller without `can_access_project`.
- **Read access (OD-15):**
  - Staff (Owner and Admin) read every version.
  - Client members read the current version.
  - Notes are staff-only.
  - Sales read nothing.
- **UI:**
  - staff project page: "Scope confirmation" and "Operational notes (staff only)";
  - client project page: "Your project scope confirmation", with an acknowledgment checkbox that is unchecked by default. A non-signer member sees that only the person who accepted the agreement can acknowledge.
  - Notices, errors and audit-action entries were added to match.
- **Not changed:**
  - the order summary, its hash, the price, the ledger and every financial table (T-LC-20);
  - every AUTH-021 and AUTH-022 object;
  - dependencies.

  Entitlement checks are not implemented: they wait for SLM-CPS-002. No contractual text was added. 05 §3A status labels are left for Main's status record.

**Requirement A (lock hierarchy).** AUTH-023's paths take no row lock before the release lock. Their inserts take `FOR KEY SHARE` on the project and order-summary rows, through foreign keys, after it. Neither the financial nor the contractual row-lock paths take the release lock, so no cycle can form. The race test proves it with real connections, in both orders.

**OD-11(ii) setup-only dispositions (verified by Main before push)**

# FD-14 record: AUTH-023 OD-11(ii) setup-only additions (Main, 2026-11-28 ~05:41Z)

- **Source:** WP-C branch `wp-c/pwp5a-scope-confirmation`, local commits 9889c9b and 8e2fe95 on 77eb9cd.
- **Authority:** OD-11(ii) as approved by the Owner on 2026-11-28, plus Main's Q3 ruling. Verification requirement E and the Owner's disposition-control clarification apply: existing assertions, expected values, plans and descriptions stay byte-identical, and WP-I re-verifies independently.

## Common fields for all 12 sites
1. **Original:** the existing test, unchanged. No existing line is modified or removed (`git diff --numstat` shows 0 deletions in every file).
2. **Replacement:** additions only, as below. No `expect`, pgTAP assertion, plan, description or expected value is added or changed. Setup failures raise or throw.
3. **Original guarantee:** whatever each test asserts today.
4. **Replacement guarantee:** identical assertions, now run past the AUTH-023 release gate, which requires an acknowledged current scope confirmation.
5. **Exposure:** the setup creates synthetic confirmations and acknowledgments. Paths B and F also reach the effective agreement through the real WP-B path:
   - Owner `issue_order_summary`; client `accept_agreement` and `begin_initial_checkout`;
   - as `service_role`, `outbound_request_for_execution`, `confirm_outbound_dispatch` and `record_outbound_result`;
   - a synthetic `checkout.session.completed`, through `ingest_stripe_event` and `process_stripe_event` (B), or posted to `/api/stripe/webhook` signed with the run's test-only `E2E_STRIPE_WEBHOOK_SECRET` (F, OI-63).

   There is no direct INSERT or UPDATE to the ledger, `deposit_charge`, payment, invoice or any other financial table. The only direct inserts are `auth.sessions` and `auth.mfa_factors` (the existing act_as pattern), plus `public.project_memberships` in wpc.spec only (Q3(b)).
6. **Compensating coverage:**
   - the Q3(c) intended-state probe for 215, 220 and 240: identical fixture financial status and identical G1–G8 results and eligibility; only the agreement and scope inputs change;
   - 225 is unchanged (its T-LC-16 refusals come before the gate).
7. **Authorization:** OD-11(ii), pre-approved by the Owner. Main verified and recorded it here before the push.
8. **Evidence (WP-C, local):** pgTAP passes apart from 050, which waits on B-1c, now approved. 250 83/83; 190 47/47; 215 63/63; 220 117/117; 235 67/67; 240 65/65; 400 33/33; integration 150/150; e2e 67/67.

## Sites
| # | File | Hunks | Lines | Path | Added-text SHA-256 (16 chars, from WP-C) |
|---|---|---|---|---|---|
| 1 | supabase/tests/190_wpb_release_crosscheck.test.sql | -181,0 +182,29; -185,0 +215 | +30 | A | d61a9e3183e2ed48 |
| 2 | supabase/tests/235_wpc_oi113_approval_identity.test.sql | -169,0 +170,29; -173,0 +203 | +30 | A | d61a9e3183e2ed48 |
| 3 | supabase/tests/400_wpi_r1_fail_closed.test.sql | -154,0 +155,29; -158,0 +188 | +30 | A | d61a9e3183e2ed48 |
| 4 | supabase/tests/215_wpc_approvals_holds.test.sql | -89,0 +90,105 | +105 | B (S5A215) | 1447d9e571245182 |
| 5 | supabase/tests/220_wpc_publication_gates.test.sql | -481/-483,0 +484,104 | +104 | B (S5A220) | f1e8f572116b1abe |
| 6 | supabase/tests/240_wpc_oi114_publication_recovery.test.sql | -380/-382,0 +383,104 | +104 | B (S5A240) | 3a5cfab2c7fb5c44 |
| 7 | tests/integration/oi91-dispatch-revocation.test.ts | -113,0 +114,11 | +11 | C | f2def6028e623b20 (before condition 1) |
| 8 | tests/integration/wph-hardening.test.ts | -481,0 +482,11 | +11 | C | f2def6028e623b20 (before condition 1) |
| 9 | tests/integration/wpc-oi113-approval-race.test.ts | -83,0 +84,11 | +11 | D | c761ec0c754db7bd (before condition 1) |
| 10 | tests/integration/wpc-oi114-recovery-race.test.ts | -82,0 +83,11 | +11 | D | c761ec0c754db7bd (before condition 1) |
| 11 | tests/e2e/r1.spec.ts | -727,0 +728,13 | +13 | E | e47fa5f8357f7464 |
| 12 | tests/e2e/wpc.spec.ts | -0,0 +1,2; -293,0 +296,127 | +129 | F | b356cec34e68339e |

## Conditions (Main)
1. **Paths C and D (sites 7 to 10) must check their results like A and B.** For example, wrap each call: `if not coalesce((public.record_scope_confirmation(...) ->> 'ok')::boolean, false) then raise exception 'fixture: ...'; end if;`, and the same for `acknowledge_scope_confirmation`. This keeps "setup failures raise" consistent. It is still additions only, so the line counts and hashes for 7 to 10 change. Report the new numstat and hashes after the push.
2. **After the push, Main re-verifies mechanically:** 0 deletions in every listed file; no other existing test file touched; the additions match this record. WP-I verifies the same independently.
3. **Clarification 3 terminology (corrected 05:43Z):**
   - public wrapper: SECURITY INVOKER, search_path '', execute by authenticated only;
   - private implementation: SECURITY DEFINER, search_path '', execute by authenticated only (no anon, service_role or PUBLIC), with NULL-safe re-authorization;
   - internal helpers: no API-role execute, except private.current_scope_confirmation_id (an RLS helper granted to authenticated, which returns nothing without can_access_project).
4. **050 (B-1c):** apply exactly the approved two lines, mid-array, keeping every existing entry and any AUTH-021 group already on main (clarification 4).
5. **D-8 (tests/support/wpc-fixtures.ts):** resolved at 05:43Z. AUTH-023 does not touch the file, so WP-B applies D-8 independently.

**Condition 1 applied (WP-C, after Main's record):** sites 7 to 10 now check both results and raise. They are still additions only, with 0 deletions. Sites 7 and 8: hunk -113,0 +114,16 and -481,0 +482,16, +16, added-text SHA-256 `d4779fbe4cd671cd`. Sites 9 and 10: hunk -83,0 +84,16 and -82,0 +83,16, +16, `30ff9138f7e4ff7b`. Method: the added lines without their `+` prefix, newline-terminated, through SHA-256. Sites 1 to 3, 5, 6, 11 and 12 reproduce the recorded hashes by this method. Site 4 (215) is unchanged since the setup commit. Its recorded `1447d9e571245182` excludes the final newline of its last added line, which is blank; the newline-terminated method gives `c79191b84f205602` for the same content. The other recorded evidence (250 and integration) is updated in the table below.

**B-1c (Owner, 2026-11-28).** Test 050 gains the two approved lines, immediately after the existing WP-C group. No existing line, plan or description changed. At the base `5c47d16`, neither AUTH-021's group nor AUTH-022's is on `main`; a later rebase keeps every merged group (clarification 4). 050 passes 24/24.

**Acceptance evidence (local stack, Supabase CLI 3.2.0, PostgreSQL 17.4, synthetic data; fresh `supabase db reset` before each database run):**

| Item | Result |
|---|---|
| Lint, typecheck, format | Pass |
| Unit | 24 files, 517 passed |
| pgTAP (full) | 2,401 assertions, 0 files failed (050 24/24 included) |
| Test 250 (new) | 86/86. It covers:<br>• T-LC-16, T-LC-19 and T-LC-20 (a fingerprint over the project's order summaries, with their hash and price, its acceptances, ledger entries and payment obligations, identical before and after);<br>• OD-14 and OD-15;<br>• refusals for Sales, a client, a non-signer member and a revoked Admin;<br>• an integrity tamper (stale);<br>• immutability, the notes, isolation across two projects and two clients, and the catalog and privilege layers |
| Race test (new, `wpc-pwp5a-scope-race`) | 9 cases × 5 repetitions on real connections, each on a fresh project paid through the real WP-B flow. Every waiter was seen on a heavyweight Lock before the holder committed. No 40P01, timeout or unexpected refusal.<br>• A to F: acknowledgment, a new version and release, in both orders.<br>• G to J: payment-method recovery (project row `FOR UPDATE`) against a new version and against the acknowledgment.<br>• K, L: an acceptance replay (order-summary row `FOR UPDATE`) against both |
| Integration (full) | 13 files, 153 passed (the race file adds 9) |
| Build, bundle check, production-check build | Pass (the bundle check scanned 13 files and found no secrets) |
| E2E (full) | 67 passed (T-E2E-01 to T-E2E-10 and the WP-C specs, past the gate, with sites 11 and 12) |
| Exact-head CI | Recorded in the PR |

**Effort (OI-67):** AI session about 4.5 h. Owner review and administrative hours are recorded by Main.
