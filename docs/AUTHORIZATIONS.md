# Authorizations

| Field | Value |
|---|---|
| Version | 1.1.0 |
| Status | **Approved** (Owner, 2026-11-23, consolidated execution plan: reply "APPROVE") |
| Decision | [OI-67](08-DECISIONS-AND-CHANGELOG.md#oi-67--risk-based-authorization-and-execution-model) (amends OI-01, OI-02) |
| Next unused ID | **AUTH-005** |

This file is the single source of truth for **what work is authorized**. It replaces per-phase authorization statements elsewhere. Approving a document or decision never authorizes work by itself; only an active record below does. If this file and any other document disagree about authorization, the more restrictive reading applies and the conflict is escalated (CLAUDE.md §2).

## 1. Risk tiers

| Tier | Covers | Environments | Credentials | Approval |
|---|---|---|---|---|
| **0** | Documentation, formatting, read-only research and inspection, status corrections that change no decision | Repository branches; read-only access to public sources | None | **Standing** (§2). The Owner's normal PR merge. |
| **1** | Isolated application development and testing: code, tests, non-sensitive migrations, CI configuration, and the dependency security patch exception (§4) | Local stack and CI only | Synthetic data and local development keys only | One written grant per work package |
| **2** | Sensitive implementation: RLS, storage policies, authentication, and authorization changes; Stripe **sandbox** operations; creating or configuring **non-production** hosted environments | Local, CI, the single Stripe sandbox, hosted dev and staging | Test-mode or non-production credentials only, entered by the Owner through the secure credential form. **No live credential, ever.** | One written grant naming the exact operations, credentials, stop conditions, and expiry |
| **3** | Production financial, infrastructure, and publication actions: live Stripe configuration, production Supabase/Vercel/DNS/Resend, publishing a client website, issuing refunds, GitHub repository settings | Production | Handled by the Owner | Explicit Owner approval **per action**, with reauthentication where the portal supports it, and an audit record |
| **4** | Destructive, irreversible, or critical security actions: deleting data or projects, credential rotation or revocation, history rewrites, disabling or weakening a security control, production rollback | Any | — | Individual Owner approval **plus** recorded verification of the result |

Rules for every tier:
- The security principles in CLAUDE.md §3 and the environment and Stripe restrictions in CLAUDE.md §4 apply in full. No authorization can waive them.
- A **stop condition** ends the authorized activity immediately. The agent reports to the Owner and does not retry, broaden scope, or work around it.
- An action that does not clearly fit a record's scope is **not** authorized. Treat it as the next tier up and ask.
- Evidence of authorized work (commands, results, IDs, test output) travels in the implementation pull request that performs it. Separate status-only pull requests are not used when an implementation PR can carry the evidence (OI-67).

## 2. Standing authorization

### AUTH-000 — Tier 0 standing authorization

| Field | Value |
|---|---|
| Tier | 0 |
| Scope | Documentation edits and corrections, formatting, read-only repository and provider-documentation research, read-only GitHub inspection, status corrections that change no decision |
| Permitted | Branches and pull requests for the above |
| Not permitted | Changing any Owner decision or approved requirement; any file outside the documentation allowlist (OI-70); any provider request other than reading public documentation |
| Stop conditions | The change would alter a decision, a requirement, or anything outside the allowlist |
| Expiry | None (revocable by the Owner at any time) |
| Granted | Owner, 2026-11-23 (OI-67) |

## 3. Active authorizations

### AUTH-001 — Tier 1: governance correction, shared contracts, payments, and fulfillment (local and CI)

| Field | Value |
|---|---|
| Tier | 1, with the Tier 2 controls below for database security work |
| Work packages | **WP-A** governance and specification correction; **WP-0** shared contracts; **WP-B** agreements, payments, webhooks, and ledger (local and CI parts); **WP-C** intake, uploads, approvals, publication authorization, and the admin fulfillment queue |
| Specs in scope | 01, 04, 05, 06, 07, 08, this file, [CURRENT-STATE.md](CURRENT-STATE.md); 03 for the isolation rules every new table must meet |
| Permitted | Application code, tests, and migrations for **new** tables, functions, and storage paths owned by these work packages, including their RLS policies; CI changes; synthetic Stripe-format webhook events signed with a test-only secret (OI-63); Stripe calls only through a mocked client |
| Tier 2 controls for database security work | RLS and storage policies only for tables and paths the work package creates. Every new table and path ships with cross-tenant isolation tests (03 §13). **Existing** Phase 2 tables, policies, functions, and authentication flows are **not** modified without a separate Tier 2 grant. |
| Environments | Local Supabase stack and CI only |
| Credentials | None. Local development keys only. No Stripe credential (CLAUDE.md §4). |
| Stop conditions | A spec conflict or ambiguity; a failing isolation, security, or idempotency test that cannot be fixed within scope; any need for a credential, hosted service, or provider request; any change to existing Phase 2 security objects |
| Expiry | R1 release-candidate acceptance by the Owner, or 2027-01-31, whichever comes first |
| Granted | Owner, 2026-11-23 (consolidated execution plan approval, item 6) |

### AUTH-002 — Tier 2: Stripe sandbox verification and integration (WP-B)

| Field | Value |
|---|---|
| Tier | 2 |
| Status | **Granted, not yet active.** It becomes active only when every activation condition below is met and recorded in [CURRENT-STATE.md](CURRENT-STATE.md). |
| Purpose | Verify the Stripe behavior the R1 design depends on (DEP-06 Stripe items), run the real test-mode webhook verification (DEP-15, T-PAY-16), and exercise the R1 payment journey end to end in test mode |
| Activation conditions | (1) The Owner creates a **restricted sandbox key** (`rk_test_…`) in sandbox "Spotlight Client Portal - Development" with the permissions below, and enters it only through the secure credential form for `api.stripe.com` on `spotlight-client-portal-dev`. (2) The Owner adds `api.stripe.com`, and any further hosts the Stripe CLI is verified to need, to that environment's allowlist. (3) The environment holds no live-mode credential. (4) The Stripe CLI, if used, is installed at a pinned version verified against its official release checksums. |
| Key permissions **[PROPOSED; confirmed on the Dashboard at key creation]** | Read: Balance, Products, Prices, Events, Payment Intents, Payment Methods, Setup Intents, Charges. Write: Customers, Checkout Sessions, Invoices, Invoice Items, Subscriptions (test cancellation and status checks only), Test Clocks, Webhook Endpoints (test endpoints only). Everything else: None. |
| Permitted | Test customers, Checkout Sessions, invoices (including the final-balance invoice in both hosted and automatic collection modes, for verification), Test Clocks, test refunds and test disputes using Stripe's documented test payment methods, event retrieval, and Stripe CLI event forwarding to a local server |
| Owner-only (Dashboard, sandbox) | Customer Portal and Smart Retries settings. The agent records the settings the Owner applied; it does not change them. |
| Not permitted | Any live-mode request or object; creating or changing products, prices, coupons, or promotion codes; concurrent runs; automatic retry of an ambiguous create (04 §6.4); storing, printing, or committing the key |
| Stop conditions | Any `livemode: true` signal; a permission error (never broaden the key mid-run); an ambiguous create (reconcile first); an unexpected object; any request outside the permitted list |
| Every run | Starts with the fail-closed `livemode: false` preflight (04 §6.3), uses idempotency keys, and records a run ID, request count, and results in the WP-B pull request |
| Expiry | R1 release-candidate acceptance, or 2027-01-31, whichever comes first. The Owner revokes the key at expiry. |
| Granted | Owner, 2026-11-23 (consolidated execution plan approval, item 6) |

### AUTH-003 — Tier 2: hosted non-production environments (WP-D)

| Field | Value |
|---|---|
| Tier | 2 |
| Status | **Granted, not yet active.** Active once the Owner has created the accounts and projects below and recorded them in [CURRENT-STATE.md](CURRENT-STATE.md). |
| Scope | Hosted **staging** Supabase project on the Pro plan (OI-50), with the configuration in 03 §15 and DEP-14; Vercel portal project with protected preview and staging environments (02 §4); Resend SMTP on a separate auth sending subdomain for staging auth email (OI-51); migration pushes to staging; a monitoring and error-tracking integration once DEP-12 is selected |
| Owner-only | Account creation, plan selection, billing, DNS records (Tier 3), and entering any credential |
| Not permitted | Any production project, credential, domain, or data; real client data in any non-production environment; live Stripe credentials anywhere |
| Stop conditions | Any production resource would be touched; a cost above the plan the Owner selected; a provider fact contradicting an approved decision (escalate) |
| Expiry | R1 release-candidate acceptance, or 2027-01-31, whichever comes first |
| Granted | Owner, 2026-11-23 (consolidated execution plan approval, item 6) |

### AUTH-004 — Tier 2: WP-C storage security policies (local and CI)

| Field | Value |
|---|---|
| Tier | 2 (scoped) |
| Work package | **WP-C** uploads and quarantine (05 §4–§5) |
| Scope | Storage security policies for WP-C upload functionality inside the existing private `project-assets` bucket |
| Permitted | Add narrowly scoped `storage.objects` policies for **newly introduced** upload and quarantine paths only. Enforce project membership, tenant isolation, and least privilege. Implement the private quarantine area and the scanner integration contract. Implement upload validation and storage security tests, including mocked scanning and quarantine-release tests. |
| Prohibited | Broadening any existing Phase 2 access permission; modifying the existing `project_assets_select` or `project_assets_staff_aal2` policies or any other unrelated Phase 2 security object; making any bucket or quarantine path public; letting an unscanned or unsuccessfully scanned file reach approved asset storage; letting a client self-certify a scan result; any production or hosted storage |
| Environments | Local Supabase stack and CI only |
| Credentials | None (local development keys only) |
| Stop conditions | The implementation would need to **modify an existing Phase 2 policy** rather than add a narrowly scoped one: stop that operation and report the exact change required. Also any AUTH-001 stop condition. |
| Dependencies | DEP-07 blocks **real** scanned-file release only. The quarantine architecture and the mocked scanner interface proceed now. |
| Expiry | WP-C completion, or Owner revocation |
| Granted | Owner, 2026-11-24 (integration closure authorization, item 4) |

## 4. Dependency security patch exception (standing, Tier 1)

Applies when `pnpm audit` reports a **high or critical** advisory against a pinned dependency (OI-70).

| Condition | Rule |
|---|---|
| Change | A patch or minor version that fixes the advisory. **Major upgrades are excluded.** |
| Files | `package.json` and `pnpm-lock.yaml` only |
| Verification | The new version is verified against the official registry and release notes before use (OI-11) |
| Validation | Full CI (dependency files always classify as "full") |
| Pull request | Labeled as a security patch, naming the advisory |
| Merge | The Owner reviews and merges |

## 5. Expired and completed authorizations

| ID | Scope | Outcome |
|---|---|---|
| Phase 1 authorization (2026-11-23) | Foundation and CI | Completed (PR #2) |
| Phase 2 authorization (2026-11-23) | Auth, security, and tenant isolation, local only | Completed (PR #4) |
| OI-30 catalog execution authorizations (2026-11-23) | Create the 11-product, 11-price sandbox catalog | Completed and expired (DEP-01; PRs #12, #13). Restricted keys revoked (Owner-reported, 2026-11-24). |
