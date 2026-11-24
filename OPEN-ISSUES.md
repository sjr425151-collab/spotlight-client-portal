# Open Issues and Dependencies Register

| Field | Value |
|---|---|
| Version | 0.15.0 |
| Status | Current (updated with the governance correction, OI-67). Overall status is in [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md). |
| Next unused issue ID | **OI-73** (OI-56 to OI-62 are allocated in draft PR #6, the AI operations proposal) |
| Next unused dependency ID | **DEP-17** |
| Decision record | [docs/08-DECISIONS-AND-CHANGELOG.md](docs/08-DECISIONS-AND-CHANGELOG.md) |

Rules:
- IDs are never reused.
- An **open issue** (OI-nn) needs an Owner decision. It closes only when the decision is recorded in 08.
- A **dependency** (DEP-nn) is work or verification that must happen before a named phase or production. Dependencies are not Owner policy decisions. Recommendations are proposals only.

---

## Part 1 — Decided issues (OI-01 to OI-55, OI-63 to OI-72)

All 65 issues listed here are decided at the architectural level. The authoritative text is in [08 §3](docs/08-DECISIONS-AND-CHANGELOG.md#3-decision-register), and phase and dependency traceability is in [08 §3A](docs/08-DECISIONS-AND-CHANGELOG.md#3a-traceability-matrix-oi-01oi-55-oi-63oi-72).

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

---

## Part 2 — Open issues requiring Owner decision

OI-50 (option A), OI-51 (option A), and OI-52 (option C) were decided on 2026-11-23 in the consolidated execution plan approval; their decisions are recorded in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The options considered remain in this file's Git history.

**None open.** OI-72 was decided on 2026-11-24 (option A); its decision is in [08](docs/08-DECISIONS-AND-CHANGELOG.md). The options considered remain in this file's Git history.

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
| DEP-07 | Malware scanning **vendor selection** after provider and cost verification (OI-31) | Owner (selection); implementer prepares a verified shortlist | WP-C (before scanned uploads can be released; before the R1 release candidate) | Not started |
| DEP-08 | **Brand assets**: Owner confirmation of the official logo master (Phase 1); vector and variant assets and final visual approval (Prod) | Owner | Phase 1 (confirmation); Prod (final approval) | Phase 1 part **complete**: logo master confirmed 2026-11-23. Production part **outstanding**. |
| DEP-09 | **Production infrastructure** prerequisites P-1–P-9 (02 §11) | Owner + implementer | Phase 5 (Prod) | Not started |
| DEP-10 | **Branch protection** on `main` | Owner (GitHub settings) | Phase 1 | **Complete (2026-11-23)**. See detail below. |
| DEP-11 | Toolchain **version pins** verified against official sources (OI-11) | Implementer | Phase 1 | **Complete (2026-11-23).** See [docs/DEVELOPMENT.md §1](docs/DEVELOPMENT.md#1-toolchain). |
| DEP-12 | Monitoring, error-tracking, and RUM **vendor selection** (02 §8, OI-23) | Owner; implementer prepares a verified shortlist | Before the R1 release candidate (Owner-critical alerts use it in R1, OI-68) | Not started |
| DEP-13 | **Nonce-based Content-Security-Policy**: remove `'unsafe-inline'` from `script-src` (03 §13 T-SEC-03) | Implementer | **Phase 2 (required security work)** | **Complete (2026-11-23; merged to `main` in PR #4, merge commit `45d05f6`).** `src/proxy.ts` sets a per-request nonce CSP with `'strict-dynamic'` and no `'unsafe-inline'` for scripts or styles; no inline style attributes remain. Verified by T-SEC-03 and T-SEC-04 (e2e) and the Lighthouse budgets (T-PERF-01). |
| DEP-14 | **Hosted Supabase projects** (dev, staging): creation, configuration (sign-up disabled, OTP expiry, signing keys, TOTP, IP forwarding, SMTP), and migration pushes | Owner authorization; implementer executes | Before any hosted environment | Granted under AUTH-003 (not yet active). OI-50 and OI-51 decided. |
| DEP-15 | **Stripe test-mode webhook verification** (OI-63): a test-mode webhook signing secret, a way to deliver real test-mode events to a local server (for example the Stripe CLI), and a recorded verification run of the webhook handlers | Owner (credential and access authorization); implementer executes | WP-B | Not started. Runs under AUTH-002 once its activation conditions are met. |
| DEP-16 | Switch the required status checks to the aggregate `CI result` (OI-70): require `CI result`, `Lint, types, format, unit tests`, `Dependency audit`, and `Secret scan (gitleaks, full history)`; remove the e2e and Lighthouse jobs from the required list, because GitHub reports a skipped job as passing | Owner (GitHub settings, Tier 3) | Immediately after the governance correction PR merges | **Complete** (Owner-reported, 2026-11-24). `main` reports `protected: true` via the GitHub API; the ruleset check list is not readable from the agent session. |

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
- **R1 final-payment wording (OI-68):** confirm that the 04 §3.1 *Authorization for Final Payment* clause is consistent with R1, where the client's approval makes the balance due and the client pays on the Stripe-hosted invoice page rather than by automatic charge, and approve the R1 approval-button and screen wording (04 §10, 05 §7).
- Unused-upload deletion terms (OI-42), coordinated with DEP-05.

### DEP-06 detail — provider verification items added by OI-43 to OI-46

- **Stripe:** a Checkout Session-level discount restricted to the balance product with a single redemption, which must never attach to the customer or subscription (OI-44). *Superseded by OI-55: verify the invoice-level discount in the next item instead.*
- **Stripe (OI-47, approved 2026-11-23):** a subscription-mode Checkout Session created with no discounts and with promotion codes disabled, so neither the deposit nor the maintenance line can be reduced.
- **Stripe (OI-17 revised, 2026-11-23):** saving the payment method in subscription-mode Checkout for a later off-session, one-off charge; an automatically charged one-off invoice using the standard balance Price ID; the events for failed charges and required authentication; the Stripe-hosted page for completing the same invoice; idempotency keys; and, for OI-55 (approved, option A), an invoice-level discount restricted to the balance product.
- **Stripe:** the subscription state after exhausted retries (`past_due` / `unpaid` vs cancellation) and the related events (OI-46).
- **Supabase / Postgres:** time-zone database support for America/Detroit evaluation (OI-43). Backup expiry behavior for deleted data (OI-42).
- **Domain registrar (to be selected; revised OI-35):** registration date and expiry data, auto-renew settings, the transfer (auth code) process, and confirmation that hosting deactivation cannot affect a registration.
- **Vercel / infrastructure (revised OI-35):** discontinuing designated per-client resources at M1 independently of the remaining hosting.

### DEP-06 detail — Phase 2 Supabase verification (2026-11-23)

- 31 provider facts are verified with source citations in `docs/03A-SUPABASE-PROVIDER-VERIFICATION.md`.
- Verification used the official documentation source in the vendors' GitHub repositories, because `supabase.com` and `nextjs.org` are blocked by this environment's network policy.
- U-01 to U-05 and U-11 were **resolved by the Phase 2 local verification spike on 2026-11-23** (03A §5, S-01 to S-08). No result contradicted an approved decision; the implementation notes were approved by the Owner on 2026-11-23 (OI-53, with N-8 amended).
- U-06 to U-08 and U-10 still need hosted or dashboard access, or Owner checks (DEP-14, OI-50). U-09 is not needed.

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
