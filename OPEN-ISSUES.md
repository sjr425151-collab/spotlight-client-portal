# Open Issues and Dependencies Register

| Field | Value |
|---|---|
| Version | 0.2.0 (draft for owner review) |
| Status | Draft |
| Next unused issue ID | **OI-47** |
| Next unused dependency ID | **DEP-13** |
| Decision record | [docs/08-DECISIONS-AND-CHANGELOG.md](docs/08-DECISIONS-AND-CHANGELOG.md) |

Rules:
- IDs are never reused.
- An **open issue** (OI-nn) needs an Owner decision. It closes only when the decision is recorded in 08.
- A **dependency** (DEP-nn) is work or verification that must happen before a named phase or production. Dependencies are not Owner policy decisions. Recommendations are proposals only.

---

## Part 1 — Decided issues (OI-01 to OI-41)

All 41 issues are decided at the architectural level. The authoritative text is in [08 §3](docs/08-DECISIONS-AND-CHANGELOG.md#3-decision-register), and phase and dependency traceability is in [08 §3A](docs/08-DECISIONS-AND-CHANGELOG.md#3a-traceability-matrix-oi-01oi-41).

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
| OI-10 | Hosting and delivery | Decided | DEP-06, DEP-09, DEP-10 |
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
| OI-21 | Privacy and retention | Decided | DEP-05; OI-42 |
| OI-22 | Publication | Decided | DEP-06 |
| OI-23 | Performance | Decided | DEP-12 |
| OI-24 | Optional post-publication inquiries | Decided | — |
| OI-25 | Nonresponsive preview clients | Decided | OI-43, OI-45 |
| OI-26 | Failed maintenance payments | Decided | DEP-03, DEP-06; OI-43 |
| OI-27 | Owner-authorized financial adjustments | Decided | OI-44; DEP-03 |
| OI-28 | Signer authority | Decided | DEP-03 (final wording) |
| OI-29 | Stripe Customer Portal | Decided | DEP-03, DEP-06 |
| OI-30 | Stripe test-mode catalog | Decided; creation **blocked** | DEP-01 |
| OI-31 | File upload security | Decided | DEP-07 |
| OI-32 | Client hosting | Decided | DEP-03, DEP-06 |
| OI-33 | Mandatory publishing QA | Decided | — |
| OI-34 | Agreement versioning | Decided | DEP-03 |
| OI-35 | Cancellation, refunds, 12-business-day transition | Decided | DEP-03; OI-43, OI-46 |
| OI-36 | Tax readiness | Decided | DEP-04 |
| OI-37 | Disputes and chargebacks | Decided | DEP-03 |
| OI-38 | Branding | Decided | DEP-08 |
| OI-39 | Provider verification | Decided | DEP-06 |
| OI-40 | Data governance | Decided | DEP-05; OI-42 |
| OI-41 | Production infrastructure | Decided | DEP-09 |

---

## Part 2 — Open issues requiring Owner decision

These came out of the 2026-11-23 cross-document audit. Each is a gap or conflict that the approved decisions do not resolve.

| ID | Title | Earliest phase | Status |
|---|---|---|---|
| OI-42 | "Unused uploads" retention: OI-21 vs OI-40 | 4 | Open |
| OI-43 | Business-day and time-zone calendar | 3 | Open |
| OI-44 | Payment mechanism for adjusted (reduced) amounts | 3 | Open |
| OI-45 | Authority and effect of the day-21 approval hold | 4 | Open |
| OI-46 | Involuntary cancellation and the 12-business-day transition | 3 | Open |

### OI-42 — "Unused uploads" retention: OI-21 vs OI-40

- **Description:** OI-21 sets "unused uploads: 90 days after closure". OI-40, which restates the retention schedule, omits that category. All other categories match.
- **Options:**
  - A. Keep the 90-day rule (OI-40's omission was unintentional).
  - B. Drop it; unused uploads follow "project assets: 12 months after closure".
- **Recommendation:** A, because it supports data minimization. Define "unused upload" as an asset never included in any released preview.
- **Impacted documents:** 07 §6.
- **Owner decision required:** Yes. Also confirm under legal review (DEP-05).

### OI-43 — Business-day and time-zone calendar

- **Description:** Several approved rules depend on a calendar definition, which OI-35 requires to be set out explicitly:
  - OI-35: 12 business days
  - OI-26: seven full calendar days
  - OI-25: day 3/7/14/21 schedule
  - draft agreement §3: five business days
- **Options:**
  - A. Monday–Friday, excluding U.S. federal holidays, in America/Detroit (the draft agreement is governed by Michigan law).
  - B. Same, plus Spotlight-observed holidays published annually.
  - C. Use the client's local time zone.
- **Recommendation:** A. The deadline is the end of the business day (23:59:59, America/Detroit). Calendar-day periods use the same time zone.
- **Impacted documents:** 04 §9.1, §15.1; 05 §7.1.
- **Owner decision required:** Yes, plus legal confirmation for the agreement (DEP-03).

### OI-44 — Payment mechanism for adjusted (reduced) amounts

- **Description:** OI-27 requires a "compliant payment mechanism" for adjusted remaining amounts. OI-14 forbids creating new prices or using inline pricing, and keeps the standard prices unchanged. With a fixed balance Price ID, Checkout cannot charge a reduced amount on its own.
- **Options:**
  - A. A Stripe **coupon or discount** applied to the standard balance price in Checkout. The price is unchanged; the coupon is a separate Stripe object created per adjustment or from a predefined set.
  - B. A Stripe **Invoice** for the adjusted amount, using a credit balance or credit note against the standard price.
  - C. Allow inline amounts only for Owner-authorized adjustments. This needs an explicit amendment to OI-14.
- **Recommendation:** A, if verified (DEP-06). It keeps standard prices intact and makes the adjustment visible in Stripe. Creating coupons is a Stripe change and needs separate authorization.
- **Impacted documents:** 04 §10, §12; 06 §2 (G4).
- **Owner decision required:** Yes.

### OI-45 — Authority and effect of the day-21 approval hold

- **Description:** OI-25 lets an "administrative hold" be applied from day 21 after documented outreach. It does not say who may apply or clear the hold, or what the hold pauses. Publication is already blocked by the missing approval (G3).
- **Options:**
  - A. Owner or Admin may apply. Only the Owner may clear without a client response. The hold pauses active development work and is shown in queues. It never affects a live site.
  - B. Owner only, for both applying and clearing.
  - C. Informational status only, with no operational effect.
- **Recommendation:** A.
- **Impacted documents:** 03 §4; 04 §14; 05 §7.1; 06 §2, §8.4.
- **Owner decision required:** Yes.

### OI-46 — Involuntary cancellation and the 12-business-day transition

- **Description:** If maintenance payment recovery fails, Stripe may eventually cancel the subscription automatically, depending on its retry settings. OI-35 defines the transition for client-initiated cancellation. OI-26 keeps live sites online during holds. It is undefined whether an involuntary cancellation starts the 12-business-day transition, and on what date.
- **Options:**
  - A. Configure Stripe to leave the subscription past due or unpaid rather than cancelling it, so the hold persists until the Owner decides.
  - B. Involuntary cancellation is the effective cancellation date and starts the transition.
  - C. The Owner decides case by case. The transition starts only when the Owner records it.
- **Recommendation:** A combined with C, so that no automatic decommissioning path exists.
- **Impacted documents:** 04 §9.1, §15.1; 06 §8.4.
- **Owner decision required:** Yes, plus legal confirmation (DEP-03).

---

## Part 3 — Implementation and production dependencies

| ID | Dependency | Owner of action | Needed before | Status |
|---|---|---|---|---|
| DEP-01 | Stripe **test-mode** catalog creation and recorded test Price IDs (OI-30) | Claude Code or Owner, with a valid **test-mode** key | Phase 3 implementation | **Blocked** (see below) |
| DEP-02 | Verify the live Price IDs (04 §5.2) against the live catalog | Owner / authorized implementer | Production launch | Not started |
| DEP-03 | Qualified **legal review** of the agreement | Owner + counsel | Production launch (enforcement) | Not started |
| DEP-04 | Qualified **tax review**; Stripe Tax production configuration (OI-36) | Owner + tax advisor | Production tax collection | Not started |
| DEP-05 | **Legal/privacy review** of retention, data requests, DPAs, incident notification (OI-21, OI-40) | Owner + counsel | Production launch | Not started |
| DEP-06 | **Provider verification** per OI-39 (02 §10) | Implementer | The phase that first uses each provider | Not started |
| DEP-07 | Malware scanning **vendor selection** after provider and cost verification (OI-31) | Owner (selection), implementer (evaluation) | Phase 4 implementation | Not started |
| DEP-08 | **Brand assets** | Owner | Production launch | Partially done: logo candidate identified |
| DEP-09 | **Production infrastructure** prerequisites P-1–P-9 (02 §11) | Owner + implementer | Production launch | Not started |
| DEP-10 | **Branch protection** on `main` with required review and status checks | Owner (GitHub settings) | Phase 1 | Not started |
| DEP-11 | Toolchain **version pins** verified against official sources (OI-11) | Implementer | Phase 1 | Not started |
| DEP-12 | Monitoring, error-tracking, and RUM **vendor selection** (02 §8, OI-23) | Owner | Phase 1 (proposal), Phase 5 (active) | Not started |

### DEP-01 detail — Stripe test-mode catalog

- **Authorized scope:** create only the missing test-mode products and prices matching 04 §5.1, following the procedure in 04 §6.
- **What happened on 2026-11-23:**
  1. The session environment's network policy refused connections to `api.stripe.com` (proxy 403).
  2. A credential was then provided through the secure environment form.
  3. A read-only verification call (`GET /v1/balance`) returned an authentication error. Stripe identified the key as **live mode** (`sk_live_` prefix) and as invalid.
  4. Work stopped there. No search, create, or update request was sent.
- **Required next steps:**
  - The Owner removes the live credential from the environment's network secrets and rolls the key in Stripe if it may still be valid.
  - The Owner supplies a **test-mode** secret key (`sk_test_…`) or a restricted test key with write access to Products and Prices.
  - The authorized creation action is then re-run as a separately identifiable step.

### DEP-03 detail — legal review scope

- Final agreement text and versioning (OI-34).
- Signer authority wording (OI-28).
- Notice terms for payment holds (draft §12 vs OI-26).
- Draft §7 "designated billing portal" wording vs disabled self-service cancellation (OI-29).
- Draft §7 "discontinue hosting after the current paid period" vs the 12-business-day transition (OI-35).
- Effective-cancellation definition.
- Refund terms (OI-35).
- Domain ownership and transfer, IP ownership (OI-32, draft §5, §8).
- Dispute terms (OI-37).
- The calendar definition (OI-43).
- The involuntary cancellation treatment (OI-46).

### DEP-08 detail — brand assets

- One logo candidate has been identified in the official SLM folder (07 §10.1).
- Still required:
  - Owner confirmation that this file is the official master
  - a vector master
  - transparent and light-background variants
  - a favicon and app icon
  - Owner approval of palette, typography, email branding, and the final visual design
