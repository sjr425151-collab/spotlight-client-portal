# Open Issues and Dependencies Register

| Field | Value |
|---|---|
| Version | 0.7.0 (draft for owner review) |
| Status | Draft |
| Next unused issue ID | **OI-53** |
| Next unused dependency ID | **DEP-15** |
| Decision record | [docs/08-DECISIONS-AND-CHANGELOG.md](docs/08-DECISIONS-AND-CHANGELOG.md) |

Rules:
- IDs are never reused.
- An **open issue** (OI-nn) needs an Owner decision. It closes only when the decision is recorded in 08.
- A **dependency** (DEP-nn) is work or verification that must happen before a named phase or production. Dependencies are not Owner policy decisions. Recommendations are proposals only.

---

## Part 1 — Decided issues (OI-01 to OI-46)

All 46 issues are decided at the architectural level. The authoritative text is in [08 §3](docs/08-DECISIONS-AND-CHANGELOG.md#3-decision-register), and phase and dependency traceability is in [08 §3A](docs/08-DECISIONS-AND-CHANGELOG.md#3a-traceability-matrix-oi-01oi-46-oi-48oi-49).

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
| OI-27 | Owner-authorized financial adjustments | Decided | DEP-03, DEP-06; OI-47 (open) |
| OI-28 | Signer authority | Decided | DEP-03 (final wording) |
| OI-29 | Stripe Customer Portal | Decided | DEP-03, DEP-06 |
| OI-30 | Stripe test-mode catalog | Decided; creation **blocked** | DEP-01 |
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
| OI-48 | Theme mode: dark-only MVP | Decided (2026-11-23) | DEP-08 (light variant, future) |
| OI-49 | Temporary logo compositing treatment | Decided (2026-11-23) | DEP-08 |

---

## Part 2 — Open issues requiring Owner decision

OI-42 to OI-46 were approved on 2026-11-23 and are recorded in 08. OI-47 remains open (deposit-stage adjustments). OI-48 (theme mode) was approved on 2026-11-23; see 08. Phase 2 specification work (03 v0.4.0, with evidence in 03A) raised **OI-50 to OI-52**, where provider facts require an Owner choice.

| ID | Title | Earliest phase | Status |
|---|---|---|---|
| OI-47 | Adjustments to the initial deposit Checkout | 3 | Open |
| OI-50 | Supabase plan for hosted environments | 2 (hosted only; local work unaffected) | Open |
| OI-51 | Custom SMTP provider for Supabase Auth email | 2 (hosted only) | Open |
| OI-52 | CAPTCHA on OTP requests | 2 | Open |

### OI-50 — Supabase plan for hosted environments

- **Description:** Verified: time-boxed sessions, inactivity timeout, and single-session-per-user are "only available on Pro Plans and up" (03A F-16). Spec 03 §6.2 proposes staff and client idle and absolute limits. Prices and other plan gating could not be verified, because the pricing page was unreachable (03A U-07, U-08).
- **Options:**
  - A. Pro (or higher) for hosted staging and production: provider-enforced session limits.
  - B. Free for hosted dev, with app-enforced session limits only.
  - C. Decide later. Phase 2 uses the local stack only, where app-level limits are implemented regardless.
- **Recommendation:** C now, then A before any hosted staging. The Owner confirms current prices on `supabase.com/pricing`.
- **Impacted documents:** 03 §6.2, §15; 02 §4.
- **Owner decision required:** Yes, before any hosted project (DEP-14). It does not block local Phase 2 work.
- **Status:** Open.

### OI-51 — Custom SMTP provider for Supabase Auth email

- **Description:** Verified: the built-in Supabase SMTP delivers only to project team addresses, is rate-limited, has no SLA, and is "not meant for production use" (03A F-07). OI-04 requires appropriately configured auth email delivery. Local development uses the CLI's email testing server, so no provider is needed locally.
- **Options:**
  - A. Resend SMTP (the OI-04 vendor), on a separate auth sending subdomain (03A F-08).
  - B. Another SMTP provider.
- **Recommendation:** A, configured only when hosted environments are authorized. Resend changes remain unauthorized until then.
- **Impacted documents:** 03 §5; 07 §1.
- **Owner decision required:** Yes, before hosted staging.
- **Status:** Open.

### OI-52 — CAPTCHA on OTP requests

- **Description:** Supabase supports hCaptcha and Cloudflare Turnstile on auth forms (03A F-10). Spec 03 §17 already proposes rate limits and generic responses. CAPTCHA would add a third-party vendor (DPA, privacy review), and its client script must be allowed by the nonce CSP.
- **Options:**
  - A. No CAPTCHA in the MVP; rate limits only.
  - B. Turnstile on the OTP request form.
  - C. Enable only if abuse is observed.
- **Recommendation:** C. Implement the hooks for it, but leave it disabled.
- **Impacted documents:** 03 §14, §17; 07 §8 (vendor inventory).
- **Owner decision required:** Yes.
- **Status:** Open.

### OI-47 — Adjustments to the initial deposit Checkout

- **Description:**
  - OI-27 permits Owner-authorized discounts, credits, and waivers without limiting them to a payment stage.
  - OI-44 approves a mechanism only for the **final balance**: a discount on the standard balance price in a payment-mode Checkout.
  - The initial Checkout is **subscription mode** and combines the deposit with the $99 maintenance subscription. A discount there risks reducing the maintenance charge, which OI-44 forbids for the final balance.
  - No approved mechanism exists for reducing the deposit.
- **Options:**
  - A. Deposit-stage adjustments are not supported in the MVP. Any agreed reduction is applied to the final balance through the OI-44 mechanism. The deposit is always the standard deposit price.
  - B. Allow a discount on the initial Checkout, restricted to the deposit product. This needs Stripe verification (DEP-06) and the same safeguards as OI-44.
  - C. Allow deposit waivers only: no initial Checkout deposit line item. This changes the subscription-start flow and needs further design.
- **Recommendation:** A. It adds no new Stripe behavior and keeps the maintenance subscription untouched.
- **Impacted documents:** 04 §8, §10; 03 §12.
- **Owner decision required:** Yes. Until it is decided, the specs treat deposit-stage adjustments as unsupported.
- **Status:** Open.

---

## Part 3 — Implementation and production dependencies

Earliest phase = the first OI-02 phase whose **implementation** cannot proceed without the dependency. "Prod" = production launch authorization. Every dependency below is **incomplete** unless its status says otherwise.

| ID | Dependency | Action owner | Earliest phase | Status |
|---|---|---|---|---|
| DEP-01 | Stripe **test-mode** catalog created and test Price IDs recorded (OI-30) | Owner-authorized operator with a verified **test-mode** credential | Phase 3 | **Blocked / suspended** |
| DEP-02 | Verify the live Price IDs (04 §5.2) against the live catalog | Owner / authorized implementer | Phase 5 (Prod) | Not started |
| DEP-03 | Qualified **legal review** of the agreement and related policies | Owner + counsel | Phase 5 (Prod; before enforcement) | Not started |
| DEP-04 | Qualified **tax review**; Stripe Tax production configuration (OI-36) | Owner + tax advisor | Phase 5 (Prod tax collection) | Not started |
| DEP-05 | **Legal/privacy review** of retention, deletion, data requests, DPAs, incident notification (OI-21, OI-40, OI-42) | Owner + counsel | Phase 5 (Prod) | Not started |
| DEP-06 | **Provider verification** per OI-39 (02 §10) | Implementer; escalations to the Owner | Phase 1 (Vercel, GitHub Actions); Phase 2 (Supabase); Phase 3 (Stripe); Phase 4 (Resend, Storage, client-site Vercel) | **In progress.** GitHub Actions: actions pinned to verified commit SHAs (Phase 1). Vercel: not verified, because Vercel access is not authorized in Phase 1. |
| DEP-07 | Malware scanning **vendor selection** after provider and cost verification (OI-31) | Owner (selection) | Phase 4 | Not started |
| DEP-08 | **Brand assets**: Owner confirmation of the official logo master (Phase 1); vector and variant assets and final visual approval (Prod) | Owner | Phase 1 (confirmation); Prod (final approval) | Phase 1 part **complete**: logo master confirmed 2026-11-23. Production part **outstanding**. |
| DEP-09 | **Production infrastructure** prerequisites P-1–P-9 (02 §11) | Owner + implementer | Phase 5 (Prod) | Not started |
| DEP-10 | **Branch protection** on `main` | Owner (GitHub settings) | Phase 1 | **Complete (2026-11-23)**. See detail below. |
| DEP-11 | Toolchain **version pins** verified against official sources (OI-11) | Implementer | Phase 1 | **Complete (2026-11-23).** See [docs/DEVELOPMENT.md §1](docs/DEVELOPMENT.md#1-toolchain). |
| DEP-12 | Monitoring, error-tracking, and RUM **vendor selection** (02 §8, OI-23) | Owner | Phase 5 (required); may be proposed earlier | Not started |
| DEP-13 | **Nonce-based Content-Security-Policy**: remove `'unsafe-inline'` from `script-src` (03 §13 T-SEC-03) | Implementer | **Phase 2 (required security work)** | **Designed** in 03 §14 (v0.4.0, pending sign-off). Implementation is not started. Phase 1 intentionally keeps the documented limitation. |
| DEP-14 | **Hosted Supabase projects** (dev, staging): creation, configuration (sign-up disabled, OTP expiry, signing keys, TOTP, IP forwarding, SMTP), and migration pushes | Owner authorization; implementer executes | Before any hosted environment. Phase 2 itself runs on local Supabase only. | Not authorized. Depends on OI-50 and OI-51. |

### DEP-01 detail — Stripe test-mode catalog

- **Authorized scope:** create only the missing test-mode products and prices matching 04 §5.1, following 04 §6.
- **History (2026-11-23):**
  1. `api.stripe.com` was first blocked by the session network policy.
  2. A credential was then saved to the session environment. A single read-only verification request showed it was a **live-mode** key, and Stripe rejected it as invalid.
  3. No search, create, or update request was sent, and no Stripe object was created or modified.
- **Current status:**
  - The Owner has chosen to leave the environment configuration unchanged for now, so the live-mode credential remains saved for `api.stripe.com` on that environment.
  - The Owner has instructed that **no Stripe API requests** be made until a verified test-mode credential workflow is separately authorized.
- **To unblock:**
  - The Owner authorizes a test-mode credential workflow, replacing the live credential with a test-mode key (`sk_test_…`) or a restricted test key with write access to Products and Prices.
  - Then the authorized creation is run as a separately identifiable action.

### DEP-03 detail — legal review scope

- Final agreement text and versioning (OI-34) and signer authority wording (OI-28).
- Payment-hold notice terms (draft §12 vs OI-26) and the Owner-authorized termination path after failed payment (OI-46).
- Draft §7 "designated billing portal" wording vs disabled self-service cancellation (OI-29).
- Draft §7 "discontinue hosting after the current paid period" vs the revised OI-35 milestones: M1 (12 business days, maintenance and designated infrastructure cessation) and M2 (60 calendar days, final transfer and offboarding). Also: the definition of the effective cancellation date, the definition of designated recurring infrastructure, the required notices before M2, and the one-year initial domain term with renewal responsibility. Incorporate only from the final counsel-approved copy.
- The calendar convention, including trigger-date exclusion (OI-43).
- Disclosure of adjusted final balances (OI-44).
- Refund terms (OI-35), domain ownership and transfer, IP ownership (OI-32; draft §5, §8), and dispute terms (OI-37).
- Unused-upload deletion terms (OI-42), coordinated with DEP-05.

### DEP-06 detail — provider verification items added by OI-43 to OI-46

- **Stripe:** a Checkout Session-level discount restricted to the balance product with a single redemption, which must never attach to the customer or subscription (OI-44).
- **Stripe:** the subscription state after exhausted retries (`past_due` / `unpaid` vs cancellation) and the related events (OI-46).
- **Supabase / Postgres:** time-zone database support for America/Detroit evaluation (OI-43). Backup expiry behavior for deleted data (OI-42).
- **Domain registrar (to be selected; revised OI-35):** registration date and expiry data, auto-renew settings, the transfer (auth code) process, and confirmation that hosting deactivation cannot affect a registration.
- **Vercel / infrastructure (revised OI-35):** discontinuing designated per-client resources at M1 independently of the remaining hosting.

### DEP-06 detail — Phase 2 Supabase verification (2026-11-23)

- 31 provider facts are verified with source citations in `docs/03A-SUPABASE-PROVIDER-VERIFICATION.md`.
- Verification used the official documentation source in the vendors' GitHub repositories, because `supabase.com` and `nextjs.org` are blocked by this environment's network policy.
- Items U-01 to U-11 remain unverified. U-01 to U-05 and U-11 are resolved by the Phase 2 local verification spike (03 §18). U-06 to U-08 and U-10 need hosted or dashboard access, or Owner checks.

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
| Required status checks | None, because no CI exists yet | Owner-attested |

**Verification limits:** the session's GitHub tools can confirm the branch's protected status, but cannot read ruleset rule details. The individual rules above are recorded from the Owner's confirmation, and they have not been tested with a write attempt against `main`.

**Follow-ups [PROPOSED]:**
- Add the Phase 1 CI checks as required status checks once they exist (Phase 1 exit).
- Raise required approvals to 1 when a second reviewer joins.
