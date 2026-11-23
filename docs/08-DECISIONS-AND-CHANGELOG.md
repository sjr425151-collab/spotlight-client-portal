# 08 — Decisions and Changelog

| Field | Value |
|---|---|
| Document | Architecture Decision Register and Change Log |
| Version | 0.12.1 (draft for owner review) |
| Status | **Draft — pending owner verification** |
| Applies to | Spotlight Marketing Client Portal (`portal.spotlight-marketing.co`) |
| Related | [OPEN-ISSUES.md](../OPEN-ISSUES.md), [CLAUDE.md](../CLAUDE.md), specifications 01–07 |

---

## 1. Provenance statement

The 24 decisions in this register (OI-01 through OI-24) were **transcribed from the owner-provided approved baseline** supplied to the documentation author on 2026-11-22. That baseline was produced through the owner's ChatGPT-assisted architecture review process.

- These approvals have **not** been independently verified through Git history, signed records, or any other artifact in this repository. Before this change set, the repository contained only a six-line `README.md` (commit `dfc3553`).
- This register is therefore **pending owner verification**. The owner must confirm that each transcribed decision matches what was approved. If a transcription is wrong, the owner's correction prevails and is recorded in §5.
- Approval of this register does **not** authorize implementation (see §4 and OI-01).

The 17 decisions **OI-25 through OI-41** were transcribed from the owner-provided approval instructions supplied on 2026-11-23, which state that the Owner approved them. They carry the same provenance caveat: they are pending owner verification of this transcription, and are not verified through any signed record.

The 5 decisions **OI-42 through OI-46** were transcribed from the owner-provided final reconciliation instructions (2026-11-23), with the same caveat.

## 2. Requirement classification legend

All specifications in this repository use these labels:

| Label | Meaning |
|---|---|
| **[APPROVED OI-nn]** | Owner-approved architectural requirement traced to decision OI-nn. Binding. |
| **[PROPOSED]** | Engineering detail proposed by the documentation author. Not binding until the owner approves the specification containing it. |
| **[PENDING OI-nn]** | Open owner decision tracked in [OPEN-ISSUES.md](../OPEN-ISSUES.md) Part 2 (currently OI-50 to OI-52). It must not be assumed. |
| **DEP-nn** | Implementation or production dependency (verification, review, asset, or setup) tracked in OPEN-ISSUES.md Part 3. It is not an open policy decision. |
| **[DEFERRED]** | Legal, commercial, or brand policy deferred until production readiness. Placeholder only. |
| **[VERIFY-PROVIDER]** | Behavior or capability of a third-party provider (Stripe, Supabase, Vercel, Resend, etc.) that must be verified against current provider documentation and plan limits during authorized implementation. |

## 3. Decision register

The status column uses:
- **Approved** — the decision is complete at the architectural level.
- **Approved with deferrals** — the architecture is decided, but named sub-items remain open or deferred.

Note on **OI-35 (revised 2026-11-23):** wherever any decision entry refers to the "12-business-day transition", that now means milestone **M1** (maintenance cessation). The final transfer and offboarding deadline is milestone **M2** (60 calendar days). See the OI-35 revision below.

Note: the entries for OI-01 to OI-24 are kept as originally transcribed. Where they name OI-25 to OI-41 as deferrals or open items, those items have since been decided (below). Their remaining dependencies are tracked in §3A.

### OI-01 — Specification governance

- **Decision:** There are four distinct approval stages: (1) architecture approval, (2) specification reconciliation, (3) implementation authorization, (4) production launch authorization. The architecture is approved. Specification reconciliation is authorized for documentation changes only. Implementation and production launch remain unauthorized.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline, 2026-11-22. Not yet verified in this document.
- **Deferrals:** None.
- **Affected sections:** 01 §8; README "Authorization status"; CLAUDE.md §1; this document §4.

### OI-02 — Development sequence

- **Decision:** Future development phases are: (1) foundation and CI, (2) authentication, security, and tenant isolation, (3) agreement acceptance and Stripe test-mode billing, (4) intake, fulfillment, previews, final payment, and publishing, (5) hardening and production readiness. Each phase requires separate owner authorization.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 01 §7; CLAUDE.md §3.

### OI-03 — Roles

- **Decision:** The active MVP roles are Owner, Admin, and Client. A future Fulfillment role may be defined but must remain disabled. Use least privilege, server-side authorization, and auditable privileged actions. Financial exceptions and staff management are Owner-only. Only an authorized client may approve their own project's released preview.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 01 §6; 03 §3, §4.

### OI-04 — Notifications

- **Decision:**
  - Resend handles operational transactional notifications.
  - Supabase Auth handles invitation and OTP flows through appropriately configured email delivery.
  - Stripe handles applicable payment receipts.
  - Require durable outbox records, idempotent delivery, retries, logging, verified sender configuration, and environment isolation.
  - Marketing automation sequences are excluded from the MVP.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Final email branding (see OI-12, OI-38).
- **Affected sections:** 07 §1–§4.

### OI-05 — Project states

- **Decision:** Agreement, deposit, intake, development, preview approval, final balance, billing holds, and publication are tracked independently. Administrative queues are derived from authoritative state. A manually editable status field is never used as proof of payment or publication eligibility.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 05 §2, §9; 04 §11, §14; 06 §2.

### OI-06 — README and documentation governance

- **Decision:** README.md is the concise developer-facing entry point. It covers project identity, MVP scope, architecture overview, documentation index, environments, security principles, development workflow, and authorization status. Owner-approved decisions establish architectural requirements. Reconciled specifications define detailed implementation requirements once approved. CLAUDE.md establishes operating instructions. Conflicts must be escalated.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** README; CLAUDE.md §2; 01 §8; this document §6.

### OI-07 — Portal URL

- **Decision:** The portal is an independent application at `https://portal.spotlight-marketing.co`. The main `spotlight-marketing.co` website remains on GoHighLevel. `/clientportal` is not used as the portal deployment path.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** DNS configuration (OI-41).
- **Affected sections:** 01 §1; 02 §1–§2; README.

### OI-08 — Authentication

- **Decision:** Use Supabase Auth with invitation-only, passwordless email OTP. Require project-scoped memberships, session revocation, server-side routing, administrative MFA, and authentication audit trails.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 03 §5–§7.

### OI-09 — Tenancy

- **Decision:** One agency serves multiple isolated client businesses and projects. Use project memberships, Supabase RLS, private storage, and server-side authorization. There is no multi-agency MVP.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 03 §8–§10; 05 §4.

### OI-10 — Hosting and delivery

- **Decision:** Use Vercel and GitHub Actions. Maintain separate development, preview, staging, and production environments. Require protected previews, CI verification, owner-controlled releases, monitoring, rollback, cost controls, and portability.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Production infrastructure and DNS (OI-41); provider plan verification (OI-39).
- **Affected sections:** 02 §4–§8.

### OI-11 — Toolchain

- **Decision:** Node.js 24 LTS, pnpm, Next.js App Router, strict TypeScript, Tailwind CSS, ESLint, Prettier, Vitest, Playwright. Versions must be pinned and verified during separately authorized implementation. No tooling is installed now.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Exact version pins (Phase 1).
- **Affected sections:** 02 §3; CLAUDE.md §6.

### OI-12 — Design system

- **Decision:** A premium, responsive, accessible design system with centralized design tokens and replaceable brand assets. Final logos, colors, fonts, and email branding require separate owner approval.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Brand approval (OI-38).
- **Affected sections:** 07 §10–§12.

### OI-13 — Agreement

- **Decision:** One versioned Website Development & Maintenance Services Agreement, plus a project-specific order summary. Affirmative acceptance with an unchecked checkbox is required before initial checkout. Preserve the agreement version, an immutable document copy and hash, signer identity and authority, client and project identity, the scope and pricing snapshot, the acceptance timestamp, and relevant audit evidence. Material contractual changes require renewed acceptance. Final legal language remains pending approval.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline. An owner-authored draft agreement labeled "Version 1.0 — November 2026" exists outside this repository. It has not been committed and has no recorded legal review.
- **Deferrals:** Signer authority wording (OI-28); agreement finalization (OI-34).
- **Affected sections:** 04 §1–§4.

### OI-14 — Stripe catalog

- **Decision:**
  - Preserve existing live products, prices, customers, and subscriptions.
  - There are five standard packages (Essential $800, Professional $1,495, Advanced $2,495, Signature $3,495, Prestige $4,995) and a $99/month maintenance subscription.
  - The existing live catalog contains separate deposit and final-balance prices for all five packages. The owner-supplied live Price IDs are documented in 04 §5.
  - Do not create new prices or use inline pricing workarounds.
  - Production integration must later verify the mappings against the authorized Stripe environment.
  - Test-mode Price IDs are not yet established.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline. The Price IDs were supplied by the owner as previously verified. They were **not** queried from Stripe in this change set.
- **Deferrals:** Test-mode mapping (OI-30); production verification of mappings (OI-39).
- **Affected sections:** 04 §5–§6.

### OI-15 — Payment calculations

- **Decision:** All money is represented as integer USD cents. The deposit is 20%, rounded half-up to the nearest cent. The final balance equals the package price minus the deposit. Price snapshots are immutable. Discounts, taxes, refunds, disputes, and maintenance charges get separate ledger treatment.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Tax treatment (OI-36).
- **Affected sections:** 04 §7, §12.

### OI-16 — Maintenance subscription

- **Decision:** The $99/month subscription starts at initial purchase, including during development. Prelaunch and postlaunch services must be accurately disclosed. Cancellation and third-party-charge language remains pending final approval.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Cancellation and refund policy (OI-35); agreement finalization (OI-34).
- **Affected sections:** 04 §8–§9.

### OI-17 — Stripe payment workflow

- **Decision:**
  - The initial Checkout uses subscription mode with one one-time 20% deposit price and one recurring $99/month maintenance price.
  - The initial payment charges exactly the deposit plus one $99 maintenance payment (not deposit plus $198). The first maintenance period is included in the initial subscription invoice, and billing is monthly after that.
  - ~~The remaining 80% is collected in a separate payment-mode Checkout.~~ **Revised (2026-11-23, Owner instruction):** the remaining 80% is collected automatically, with no separate checkout:
    - At the initial Checkout, Stripe securely saves the payment method for future off-session collection. The client authorizes this explicitly through the legal-adviser-approved *Authorization for Final Payment* clause in the agreement (04 §3.1).
    - The client's explicit final approval of the completed website (**Approve Website & Authorize Final Payment**) authorizes collection of the previously disclosed outstanding balance. Stripe automatically charges the saved payment method and generates the invoice and payment receipt.
    - A verified Stripe payment is required before publication. If the charge fails or needs additional authentication, the client is given a secure Stripe-hosted payment completion option. The site is not published until payment succeeds.
    - Idempotency and payment-state controls prevent duplicate charges. If publication fails after a successful payment, the paid status is retained and the publication is flagged for recovery, without charging again.
  - Require signature-verified webhooks, idempotent processing, financial reconciliation, audit history, failed-payment handling, billing holds, and server-side payment verification.
  - A successful redirect is never proof of payment.
  - Refund, cancellation, tax, and dispute policies remain pending.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Billing hold rules (OI-26); Stripe Customer Portal (OI-29); OI-35, OI-36, OI-37.
- **Revision provenance:** Owner instruction "Targeted Documentation Amendment: Authorized Final Balance Collection", 2026-11-23. The clause text is legal-adviser-approved per the Owner and is incorporated verbatim.
- **Related decision:** OI-55 (adjusted balances use the automatic final-balance invoice).
- **Affected sections:** 04 §3.1, §8–§14; 05 §2, §7; 06 §2, §8.1; 07 §4; 01 §3; 03 §4.

### OI-18 — Preview approval

- **Decision:** Client approval is tied to an immutable released preview version. A newly released preview requires renewed approval. Internal drafts do not invalidate an approved release. Historical approvals are preserved. Client silence is never represented as explicit approval. The nonresponsive-client escalation procedure remains unresolved.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Nonresponsive client procedure (OI-25).
- **Related:** since the OI-17 revision (2026-11-23), the explicit approval also authorizes the automatic final-balance charge (05 §7). The approval rules above are unchanged.
- **Affected sections:** 05 §6–§7; 06 §2.

### OI-19 — Administrative overrides

- **Decision:**
  - Owner-controlled exceptions require documented reasons, immutable audit trails, and high-risk reauthentication.
  - No override may fabricate payment success, client approval, or QA completion.
  - Mandatory publication gates cannot be bypassed silently.
  - A genuine contractual adjustment to a balance must be separately authorized, documented, and reflected in the financial ledger.
  - There is no general-purpose "mark as paid" override.
  - Final rules for contractual waivers and financial adjustments remain subject to approval.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Contractual balance adjustments (OI-27).
- **Affected sections:** 03 §12; 04 §12; 06 §2.

### OI-20 — Uploads

- **Decision:**
  - Uploads go to private, project-isolated Supabase Storage.
  - Require server authorization, content validation, malware screening, quarantine, safe processing, versioning, and audit history. Nothing is published automatically.
  - Quota: 100 files and 2 GB per project.
  - Per-file limits: logos (PNG/JPG/WEBP/SVG) 15 MB; photos (JPG/PNG/WEBP/HEIC) 25 MB; brand guidelines (PDF) 25 MB; business documents (PDF/DOCX) 20 MB; video (MP4/MOV) 250 MB. Other types require admin approval.
  - Admin exceptions are permitted within approved authorization rules.
  - The scanning vendor and detailed processing mechanisms remain unresolved.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Malware scanning approach (OI-31).
- **Affected sections:** 05 §4–§5.

### OI-21 — Privacy and retention

- **Decision:**
  - Data minimization, least privilege, encryption, client export/correction/deletion procedures, legal holds, secure deletion, backup controls, a vendor inventory, and incident response.
  - Provisional retention defaults are listed in 07 §6. They require legal and provider verification.
  - Account closure does not automatically cancel Stripe billing or delete legally required records.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Privacy and retention legal review (OI-40); provider capability verification (OI-39).
- **Affected sections:** 07 §5–§9.

### OI-22 — Publication

- **Decision:**
  - Publication gates are enforced on the server: valid agreement, verified deposit, current-version client approval, verified final balance, QA passed, domain readiness, security checks passed, and applicable billing holds cleared.
  - Client website deployments are isolated. Explicit Owner authorization is required.
  - Maintain immutable release references, deployment records, post-deployment verification, incident handling, and controlled rollback.
  - The client website hosting/account model remains unresolved.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Hosting/account model (OI-32); QA and security gate criteria (OI-33).
- **Affected sections:** 06 §2–§10.

### OI-23 — Performance

- **Decision:** LCP p75 ≤ 2.5 s; INP p75 ≤ 200 ms; CLS p75 ≤ 0.1; Lighthouse mobile Performance ≥ 90, Accessibility ≥ 95, Best Practices ≥ 95, Public SEO ≥ 90; ordinary application reads p95 < 500 ms. Use accessible motion, performance budgets, repeatable CI checks, and monitoring. Security and payment correctness remain mandatory release gates.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 02 §7; 07 §11.

### OI-24 — Optional post-publication inquiries

- **Decision:** After verified publication, clients may optionally be offered Client Acquisition and Social Presence & Brand Management. This is an authenticated inquiry only, which creates an administrative queue entry and a transactional notification. Nothing is purchased, subscribed, or activated automatically, and no advertising spend is authorized.
- **Status:** Approved.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** None.
- **Affected sections:** 06 §11.

### OI-25 — Nonresponsive preview clients

- **Decision:**
  - Day 0: release the preview and request explicit approval or revisions.
  - Day 3: first reminder.
  - Day 7: second reminder and Admin notification.
  - Day 14: personal follow-up escalation.
  - Day 21: an administrative hold may be applied after documented outreach.
  - Silence never constitutes approval. A hold does not cancel subscriptions, waive balances, or satisfy publication requirements. All events are auditable.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Related decisions:** OI-43 (calendar) and OI-45 (hold authority and effect), both approved.
- **Affected sections:** 05 §7.1, §9; 04 §14; 07 §4; 03 §4.

### OI-26 — Failed maintenance payments

- **Decision:**
  - There is a seven-full-calendar-day recovery period after a failed $99 renewal. Stripe payment status is authoritative.
  - Automated reminders and configured retries run during recovery. A billing hold is placed after the period if the payment is unresolved.
  - While held, new publication and nonessential maintenance are paused. Client account access is maintained, and an already-published site is not disabled automatically.
  - Payment holds clear after verified recovery. Exceptions are Owner-only and documented.
  - Notice requirements must be reconciled with the final agreement.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Related decisions:** OI-43 and OI-46, both approved. **Dependencies:** legal notice alignment (DEP-03); Stripe retry and `past_due` behavior (DEP-06).
- **Affected sections:** 04 §9.1, §14; 06 §2, §8.4; 07 §4.

### OI-27 — Owner-authorized financial adjustments

- **Decision:**
  - Discounts, credits, partial waivers, and full waivers are Owner-only, with fresh reauthentication, a written reason, and an immutable audit record.
  - The original package price and transaction history are preserved.
  - Material financial changes require updated contractual documentation and client acceptance.
  - Remaining amounts require verified payment. Fully waived balances are recorded as waivers, not fabricated Stripe payments.
  - Standard Stripe prices remain unchanged. Adjusted payment amounts require a compliant payment mechanism.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Related decisions:** OI-44 (approved mechanism for the final balance); OI-55 (collection vehicle); **OI-47 (approved 2026-11-23): adjustments apply only to the outstanding final balance; none at the deposit stage.**
- **Affected sections:** 04 §10, §12; 03 §4, §7, §12; 05 §2; 06 §2.

### OI-28 — Signer authority

- **Decision:** Require the signer's full legal name, business legal name, position or title, verified email, and a separate unchecked authority confirmation. Preserve the agreement version, timestamp, identity evidence, authority acknowledgment, and project association. Final wording requires legal review.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-03.
- **Affected sections:** 04 §3.

### OI-29 — Stripe Customer Portal

- **Decision:** The hosted Stripe Customer Portal is in the MVP, with payment-method management, invoice and payment history, and subscription information enabled. Self-service subscription cancellation is disabled until a separately approved cancellation workflow is implemented. The process for submitting and handling cancellation requests is documented.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-03 (agreement §7 wording), DEP-06.
- **Affected sections:** 04 §9.2, §15.1.1; 03 §4; 01 §3.

### OI-30 — Stripe test-mode catalog

- **Decision:**
  - The test catalog matches the approved package values (Essential through Prestige, deposit and balance) and $99/month maintenance.
  - The Owner separately authorized creating matching test-mode products and prices.
  - Requirements: strict test/live isolation; verify the account and test-mode access first; search for existing matches and avoid duplicates; preserve live resources completely; record the test Price IDs; never commit credentials; no real charges; no payment workflow implementation without further authorization.
- **Status:** Approved. **Creation blocked** (DEP-01): a live-mode, invalid credential was supplied, so no Stripe object was created.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Affected sections:** 04 §6; 01 §7; CLAUDE.md §5.

### OI-31 — File upload security

- **Decision:**
  - Uploads go to private, project-isolated Supabase Storage, with server-side type, size, and content validation.
  - Uploads stay in quarantine pending malware scanning. SVGs are sanitized.
  - A failed scan blocks access and fulfillment, with audit records and actionable notifications.
  - The scanning vendor is selected after provider and cost verification.
  - The OI-20 quotas and limits are preserved.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-07.
- **Affected sections:** 05 §4–§5; 07 §4, §8.

### OI-32 — Client hosting

- **Decision:**
  - Agency-managed Vercel hosting, with an independent deployment per client website and separate environment configuration and release history.
  - Per-client domain configuration, rollback capability, and operational isolation.
  - Documented ownership, cancellation, and transfer policies. Hosting automation designed for scale.
  - The agency is not assumed to own a client's domain or intellectual property.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-03, DEP-06.
- **Affected sections:** 02 §2; 06 §4, §8.

### OI-33 — Mandatory publishing QA

- **Decision:**
  - Release-specific QA covers: functional behavior and lead forms; responsive design; branding and content accuracy; performance and accessibility; security; domain and operational readiness; monitoring and rollback.
  - The approved Lighthouse and Core Web Vitals thresholds are preserved, and evidence is recorded against the exact release.
  - Missing client approval, unresolved contractual balances, critical security failures, and failed essential functionality block publication.
  - Documented Owner-approved performance exceptions may be permitted. Security, payment and settlement, and explicit client approval cannot be bypassed.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Affected sections:** 06 §2, §6, §7.

### OI-34 — Agreement versioning

- **Decision:**
  - A version-controlled agreement with a project-specific order summary.
  - Affirmative acceptance and signer-authority confirmation.
  - An immutable agreement copy and hash, with identity and timestamp evidence.
  - Re-acceptance for material changes.
  - Separate electronic acceptance and service-activation events.
  - Qualified legal review before production. The current agreement is not legally finalized.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-03.
- **Affected sections:** 04 §1–§4.

### OI-35 — Cancellation, refunds, and post-cancellation milestones

- **Decision:** When a client cancels the $99/month hosting and maintenance subscription, the client assumes responsibility for hosting and other ongoing website services within 12 business days.
- **Procedure:**
  1. Record the effective cancellation date.
  2. Notify the client of the deadline and the responsibilities that pass to them: hosting, domain registration and renewals, DNS, security, maintenance, backups, monitoring, and other ongoing operational services.
  3. Allow 12 business days for transition.
  4. Provide contractually required transfer materials and reasonable assistance.
  5. After the deadline, the agency may discontinue managed hosting and remove the site, subject to the final agreement and law.
  6. Agency obligations end at the deadline, except those that survive.
- **Safeguards:**
  - The request date and the effective cancellation date are distinct. The clock starts on the effective date unless the final agreement says otherwise.
  - Business days must be defined.
  - No automatic cancellation or deletion of a client-owned domain. Domain rights require contractual treatment.
  - Legal responsibilities do not disappear automatically. Records are preserved.
  - Legal review is required before enforcement.
- **Also covered:** development-deposit refunds, remaining-balance obligations, discretionary refund authority, and cancellation accounting.
- **Revised (2026-11-23).** This revision supersedes the single "12-business-day transition" above. Source: the Owner sign-off record (`docs/OWNER-SIGNOFF-FOUNDATION-2026-11-22.md`) and the Owner's written instruction of 2026-11-23.
  - **M1:** 12 business days after the effective cancellation date. Spotlight may discontinue active maintenance and designated recurring database/infrastructure expenditures, subject to contractual obligations.
  - **M2:** 60 calendar days after the effective cancellation date. This is the final website transfer and offboarding deadline. After the required notices, Spotlight may deactivate the remaining agency-managed services, which may make the website unavailable.
  - **Domain:** the initial domain registration is for one year from its actual purchase or registration date. Registration is separate from hosting. Cancellation must not automatically cancel a client-owned domain.
  - Continued website functionality is not guaranteed once required infrastructure has been discontinued. Intentional website degradation is not implemented.
  - The $99/month maintenance model is commercially reasonable, with no guaranteed uptime percentages or fixed response times.
  - Contract wording is incorporated only from the final counsel-approved agreement.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Related decisions:** OI-43 and OI-46, both approved. **Dependencies:** DEP-03.
- **Affected sections:** 04 §9, §9.1.1, §15.1–§15.2, §16; 06 §5, §8.4; 07 §3, §4, §6; 03 §4, §7, §12; 05 §2, §9; 02 §8, §10, §13.3.

### OI-36 — Tax readiness

- **Decision:**
  - Tax-ready financial architecture, with separate treatment of development, maintenance, and future marketing services.
  - Stripe Tax support where appropriate, and accurate tax records.
  - No assumptions about taxability. No production tax collection without qualified review and authorization.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-04.
- **Affected sections:** 04 §12, §15.3.

### OI-37 — Disputes and chargebacks

- **Decision:**
  - Stripe dispute event tracking, immediate Owner notification, and response deadline tracking.
  - Evidence is collected from agreements, payments, communications, approvals, and fulfillment records.
  - Response and settlement are Owner-only. Outcomes are auditable. Financial-risk holds apply when appropriate.
  - No automatic website takedown merely because a dispute exists. No fabricated evidence and no automatic concession.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-03.
- **Affected sections:** 04 §14, §15.4; 06 §8.4; 07 §4; 03 §4.

### OI-38 — Branding

- **Decision:**
  - Approved direction: premium, minimalist, professional, accessible, and enterprise-grade.
  - The official logo source is the SLM Google Drive folder. Identify and verify the official logo, preserve its proportions and identity, and use it as the design foundation.
  - Do not generate a replacement logo, and do not treat provisional palettes as final.
  - Flag the folder if it is inaccessible or ambiguous. Final visual design requires Owner approval before production.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Findings:** the folder is accessible and contains a single logo file (07 §10.1). **The Owner confirmed it as the official master on 2026-11-23.** Production asset variants and final visual approval remain pending (DEP-08).
- **Affected sections:** 07 §10–§12.

### OI-39 — Provider verification

- **Decision:**
  - Before implementing integrations, verify current APIs, supported features, authentication, webhook capabilities, security controls, usage limits, costs, and recovery and failure behavior.
  - This applies to Stripe, Supabase, Vercel, Resend, and future Google integrations.
  - Material architectural or cost changes are escalated.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-06.
- **Affected sections:** 02 §10; all **[VERIFY-PROVIDER]** items.

### OI-40 — Data governance

- **Decision:**
  - Provisional retention: active records for the relationship; project assets 12 months after closure; abandoned onboarding 90 days; agreements 7 years after termination; financial records 7 years; security logs 12 months; admin audit logs 3 years; failed temporary uploads 7 days; recoverable backups rolling 30 days.
  - Encryption, project isolation, secure deletion, data-request procedures, legal holds, and legal and privacy review.
  - Cancellation does not automatically delete legally required records.
- **Status:** Approved.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Related decisions:** OI-42 (approved; restores the unused-upload rule). **Dependencies:** DEP-05.
- **Affected sections:** 07 §5–§9.

### OI-41 — Production infrastructure

- **Decision:**
  - Architecture: `portal.spotlight-marketing.co`, Vercel, Supabase, Stripe, Resend, GitHub, and independent Vercel deployments for client websites.
  - Requirements: isolated environments, protected DNS, verified authentication and authorization, verified Stripe test-mode payment scenarios, security testing, monitoring, backup and rollback readiness, release-specific QA, and explicit Owner authorization before production deployment.
  - The main agency website remains unchanged.
- **Status:** Approved (architecture). Production deployment is **not authorized**.
- **Provenance:** Owner approval instructions, 2026-11-23.
- **Dependencies:** DEP-09.
- **Affected sections:** 02 §11.

### OI-42 — Unused client upload retention

- **Decision:**
  - Unused client-uploaded assets are retained for 90 days after project closure. Unused assets are those never incorporated into a released website preview or final deliverable.
  - After the period, they are securely deleted unless a legal hold, applicable law, or another documented obligation requires preservation.
  - Assets incorporated into delivered work stay under the 12-month post-closure rule.
  - Requirements: clear used/unused distinction; a defined project closure event; automated enforcement as a future implementation requirement; backup expiry and legal holds accounted for; immutable deletion audit evidence without retaining deleted content.
  - Provisional, and not legally finalized.
- **Status:** Approved.
- **Provenance:** Owner final reconciliation instructions, 2026-11-23.
- **Dependencies:** DEP-05 (legal and privacy review).
- **Affected sections:** 07 §5–§6; 05 §4, §9.

### OI-43 — Business-day and time-zone calendar

- **Decision:**
  - The authoritative time zone is America/Detroit.
  - Business days are Monday–Friday, excluding U.S. federal holidays. Business-day deadlines end at 11:59:59 PM Eastern Time.
  - Calendar-day periods use Michigan local time and include weekends and holidays.
  - This applies to: the 12-business-day transition, the seven-full-calendar-day recovery (which stays calendar days), the day 3/7/14/21 preview milestones, contractual business-day obligations, and administrative deadlines.
  - Timestamps are stored in UTC. Evaluation uses America/Detroit, accounting for DST, with a defined federal holiday calendar. No 24-hour approximation.
  - Calculation boundaries are documented. Whether the trigger date is excluded is defined, subject to legal confirmation. Deadlines are handled consistently across systems.
  - Contract wording is subject to legal review.
- **Status:** Approved.
- **Provenance:** Owner final reconciliation instructions, 2026-11-23.
- **Dependencies:** DEP-03 (trigger-date exclusion and contract wording).
- **Affected sections:** 02 §13; 04 §9.1, §15.1; 05 §7.1; 07 §3.

### OI-44 — Adjusted final-balance payments

- **Decision:**
  - Use Stripe Checkout with Owner-authorized discounts applied to the existing standard final-balance prices, subject to Stripe capability verification. The standard prices remain unchanged.
  - Requirements: Owner-only authorization with reauthentication; record the original package amount, original remaining balance, authorized discount or credit, adjusted amount due, reason, authorizing Owner, and timestamp; immutable history; revised acceptance where materially necessary; verified payment or authorized settlement before publishing; never fabricate payment; the discount applies only to the intended final-balance payment and never to the $99 maintenance subscription; verify Stripe support before implementation.
  - A discount mechanism, not unrestricted inline pricing. Stripe limitations are escalated.
  - No Stripe API changes are authorized.
- **Status:** Approved.
- **Provenance:** Owner final reconciliation instructions, 2026-11-23.
- **Dependencies:** DEP-06 (Stripe discount capability), DEP-03 (disclosure).
- **Related decision:** OI-47 (approved 2026-11-23, Option A): no deposit-stage adjustments; this mechanism is the only adjustment path. **OI-55 (approved 2026-11-23):** after the OI-17 revision, the Owner-authorized discount is applied to the automatic final-balance invoice instead of a Stripe Checkout. Every other requirement above is unchanged. Collection on that invoice is authorized (block lifted 2026-11-23).
- **Affected sections:** 04 §10–§10.1, §12; 03 §4, §12; 06 §2.

### OI-45 — Day-21 preview approval hold

- **Decision:**
  - A project may enter an administrative hold after 21 days of unsuccessful, documented preview outreach.
  - Owner and Admin may apply the hold. The Owner may clear it without a client response. An Admin may not override it without a qualifying client response or Owner authorization.
  - The hold pauses active development and nonessential fulfillment.
  - It preserves portal and preview access and the client's ability to approve or request revisions. Client responses go to administrative review. The explicit-approval gate is preserved.
  - It does not cancel the subscription, waive balances, or affect published sites. Silence is never approval.
  - Audit: creation, actor and authorization, reason, prior outreach evidence, timestamp, client response, removal, and resumption decision.
  - It must not be confused with a billing hold or an approved preview.
- **Status:** Approved.
- **Provenance:** Owner final reconciliation instructions, 2026-11-23.
- **Affected sections:** 05 §7.1–§7.2, §9; 04 §14; 03 §4; 06 §2, §8.4; 07 §4.

### OI-46 — Involuntary subscription cancellation

- **Decision:**
  - Failed maintenance payments never automatically trigger website removal.
  - Lifecycle:
    1. Failed payment.
    2. Seven-full-calendar-day recovery, with notifications and payment-method updates. Sites stay online.
    3. Billing hold: new publishing and nonessential maintenance are paused, and no automatic takedown.
    4. Owner review: continue recovery, authorize an exception, or initiate documented termination.
    5. Only an authorized, documented termination starts the 12-business-day transition, on the documented effective cancellation date, subject to the final agreement.
  - Stripe configuration: prefer a recoverable `past_due` or `unpaid` state, and verify Stripe behavior. Unexpected Stripe cancellations are exceptions for Owner review. A cancellation webhook is never authorization to remove a site.
  - Keep a separate internal service-termination state. Prevent duplicate or contradictory transitions. Keep complete audit history.
  - Legal review of the final terms.
- **Status:** Approved.
- **Provenance:** Owner final reconciliation instructions, 2026-11-23.
- **Dependencies:** DEP-03, DEP-06.
- **Affected sections:** 04 §9.1.1, §11, §15.1; 05 §2, §9; 06 §8.4; 03 §4, §12; 07 §4.

### OI-47 — Adjustments to the initial deposit Checkout

- **Decision (Option A):**
  1. The standard 20% initial deposit is **mandatory** for all five standard website packages.
  2. The initial Stripe Checkout always includes the standard deposit plus the first $99 monthly maintenance payment.
  3. No deposit-stage discounts, credits, or waivers are supported in the MVP.
  4. Owner-authorized project price reductions may be applied **only to the outstanding final balance**, under the existing OI-44 and OI-55 safeguards.
  5. The $99 maintenance subscription must never be reduced by a project discount.
  6. A reduction can **never exceed the outstanding final balance**. A concession larger than that balance is not supported in the MVP; refunds are governed separately (04 §15.2).
- **Status:** Approved.
- **Provenance:** Owner decision, 2026-11-23 ("I formally approve OI-47, Option A"). The Owner confirmed item 6 the same day ("including the restriction that reductions cannot exceed the outstanding balance").
- **Decision history:** opened 2026-11-23 during the OI-42–OI-46 reconciliation, because OI-27 permits adjustments without naming a payment stage while OI-44 approved a mechanism for the final balance only. Options considered:
  - **A (chosen):** no deposit-stage adjustments; reductions only on the final balance.
  - B: a discount on the initial Checkout restricted to the deposit product.
  - C: deposit waivers only, with no deposit line item.

  B and C were not adopted. Both would add new Stripe behavior to the subscription-mode initial Checkout, and B risked reducing the maintenance charge.
- **Relationship to other decisions:** narrows *where* OI-27 adjustments apply. It does not change OI-27's Owner-only, reauthenticated, reasoned, audited rules, or OI-44 / OI-55's mechanism and safeguards.
- **Affected sections:** 04 §8, §10, §10.1, §16 (T-BIL-20, T-BIL-21); 03 §12.

### OI-48 — Theme mode

- **Decision:** The MVP uses a **dark-only** theme. Future light-theme compatibility is preserved:
  - all UI colors come from semantic design tokens, never hard-coded literals (enforced by `tests/unit/brand.test.ts`)
  - a light theme can be added later by redefining the token values
  - a light theme requires an Owner-approved light-background or transparent logo variant (DEP-08)
- **Status:** Approved.
- **Provenance:** Owner instruction, 2026-11-23 (final Phase 1 refinements). Supersedes the **[PROPOSED]** "Light theme required" wording in 07 §10.
- **Dependencies:** DEP-08 (for a future light theme only).
- **Affected sections:** 07 §10; `src/design/tokens.ts`; `docs/DEVELOPMENT.md` §6.

### OI-49 — Temporary logo compositing

- **Decision:** The current logo presentation is approved as a **temporary presentation treatment**: `mix-blend-mode: screen` on the dark canvas, plus a narrow horizontal edge fade that hides the master's cropped glow edge.
  - The original master (`public/brand/spotlight-marketing-logo.jpg`, SHA-256 `6cc6edb3…b2bd3c`) is preserved unmodified. A unit test pins its checksum.
  - The treatment is removed when an Owner-approved transparent or vector master exists.
- **Status:** Approved.
- **Provenance:** Owner instruction, 2026-11-23 (final Phase 1 refinements).
- **Dependencies:** DEP-08.
- **Affected sections:** 07 §10.1; `src/components/brand/logo.tsx`.

### OI-53 — Phase 2 implementation notes (03 §18.1)

- **Decision:** The eight Phase 2 implementation notes N-1 to N-8 in spec 03 §18.1 are **approved**, subject to:
  - **N-8 amended:** security events are recorded only through trusted, server-authorized operations. The server uses the secret key and passes a verified actor; payloads are bounded at the database boundary; no client- or staff-callable audit writer exists (Phase 2 remediation D1).
  - **N-2 retained:** in-portal acceptance by verified email is unchanged. The incorrect client-facing label for staff invitations is corrected (finding D3).
  - **N-6 retained:** 30 per hour per IP for code verification and for invitation attempts, and 10 code verifications per hour per email.
- **Status:** Approved.
- **Provenance:** Owner authorization "Phase 2 Security Remediation Authorization", 2026-11-23.
- **Affected sections:** 03 §6.1, §6.2, §7, §9.1, §9.2, §11, §17, §18.1; 03A §5.

### OI-54 — Marking expired invitations

- **Decision:** The scheduled cleanup job that marks expired invitations (and writes `invitation.expired`) is **deferred to Phase 5**, strictly on the condition that expired invitations are rejected at every authentication and acceptance boundary regardless of cleanup status.
- **Condition as implemented (Phase 2):** every boundary compares `expires_at` with the current time and never reads a cleanup status:
  - Auth user provisioning: the before-user-created hook
  - the invitation link check, used for the page view, code entry, and "send me a new code"
  - acceptance with the link token, and in-portal acceptance without it
  - invitee visibility through RLS, and the per-project pending limit
  An invitation counts as expired at the exact `expires_at` instant. The condition is pinned by `supabase/tests/045_expired_invitations.test.sql` and an integration test against the real Auth API. Any change that weakens it breaks the condition and reopens this decision.
- **Status:** Approved, with condition.
- **Provenance:** Owner instruction, 2026-11-23.
- **Affected sections:** 03 §6.1, §11, §18.1 (N-7).

### OI-55 — Collection vehicle for adjusted final balances

- **Decision (option A):** OI-44 carries over unchanged in substance to the automatic final-balance collection (OI-17, revised 2026-11-23). The Owner-authorized discount is applied to the automatic final-balance **invoice** only:
  - a single line item, the standard balance price
  - restricted to the balance product, with a single redemption
  - never attached to the Stripe Customer or the subscription
  - the invoice total and discount are verified against the authorized adjusted amount, and any mismatch is quarantined
- **Collection:** discounted final balances are collected on the final-balance invoice on the client's approval. An interim block was in place earlier on 2026-11-23 and was **lifted** by the Owner the same day.
- **Status:** Approved.
- **Provenance:** Owner instructions, 2026-11-23: "I approve OI-55 option A - no discounted final balance can be collected"; "Keep in place"; then "Let's just lift it now to allow any collection on the invoice".
- **Dependencies:** DEP-06 (Stripe verification of an invoice-level discount restricted to the balance product).
- **Affected sections:** 04 §10–§10.1, §16 (T-BIL-11); 03 §4; OI-44.

### OI-63 — Webhook testing strategy

- **Decision (hybrid):**
  - CI runs synthetic Stripe-format webhook events, signed with a test-only secret generated for the run. CI never holds a Stripe credential or makes a Stripe request.
  - The same handlers are also verified against real Stripe **test-mode** events. That verification runs separately from CI, under the separate Stripe access authorization.
- **Status:** Approved.
- **Provenance:** Owner decision, 2026-11-23 ("Hybrid approach — synthetic signed events in CI and real Stripe test-mode verification").
- **Dependencies:** DEP-01 (test catalog), DEP-15 (test-mode webhook verification setup), the Stripe access condition (CLAUDE.md §5).
- **Affected sections:** 04 §11, §16 (T-PAY-03 to T-PAY-08).

### OI-64 — Stripe test-mode catalog structure

- **Decision:** the test-mode catalog has **11 Stripe products and 11 prices**: five website deposits, five website final balances, and one recurring $99/month maintenance subscription. Each product carries exactly one price.
- **Scope:** a catalog-design approval only. It authorizes no Stripe request and does not lift the Stripe suspension (CLAUDE.md §5).
- **Status:** Approved.
- **Provenance:** Owner decision, 2026-11-23 ("OI-64: Use 11 Stripe products and 11 prices: five website deposits, five website final balances, and one recurring $99/month maintenance subscription.").
- **Dependencies:** DEP-01 (creation), DEP-02 (live catalog parity, production).
- **Affected sections:** 04 §6.1.

### OI-65 — Stripe test-mode catalog naming, metadata, keys, and versioning

- **Decision:** the product names, metadata, catalog keys, price lookup keys, and versioning scheme proposed in the DEP-01 readiness report §1a are approved, **provided no existing test-mode objects conflict**. They are recorded in 04 §6.1. The conflict proviso is applied as defined in 04 §6.2: any conflict stops the creation run before any write and goes to the Owner.
- **Clarification:** `package_key` is left **unset** on the maintenance product, which is not a package (Owner confirmation, 2026-11-23: "Maintenance product package_key: Leave unset").
- **Scope:** a catalog-design approval only. It authorizes no Stripe request.
- **Status:** Approved.
- **Provenance:** Owner decision, 2026-11-23 ("OI-65: Approve the product naming, metadata, catalog keys, lookup keys, and versioning scheme proposed in DEP-01 readiness report §1a, provided no existing test-mode objects conflict.").
- **Dependencies:** DEP-01; DEP-04 (tax settings deliberately left unset).
- **Affected sections:** 04 §6.1–§6.3.

## 3A. Traceability matrix (OI-01–OI-49, OI-53–OI-55, OI-63–OI-65)

Phase = the earliest OI-02 phase whose implementation the decision governs. "Prod" = production launch.

| ID | Title | Status | Phase | Primary spec sections | Remaining dependencies / open items | Legal or provider verification |
|---|---|---|---|---|---|---|
| OI-01 | Specification governance | Approved | All | 01 §8; CLAUDE.md | — | — |
| OI-02 | Development sequence | Approved | All | 01 §7 | — | — |
| OI-03 | Roles | Approved | 2 | 03 §3–§4 | — | — |
| OI-04 | Notifications | Approved | 4 | 07 §1–§4 | DEP-08 (email branding) | Provider (Resend, Supabase SMTP) |
| OI-05 | Project states | Approved | 3–4 | 05 §2, §9 | — | — |
| OI-06 | Documentation governance | Approved | All | README; 01 §8; §6 | — | — |
| OI-07 | Portal URL | Approved | 1 / Prod | 01 §1; 02 §2 | DEP-09 | — |
| OI-08 | Authentication | Approved | 2 | 03 §5–§7 | — | Provider (Supabase) |
| OI-09 | Tenancy | Approved | 2 | 03 §8–§10 | — | — |
| OI-10 | Hosting and delivery | Approved with deferrals | 1 | 02 §4–§8 | DEP-09 (DEP-10 complete) | Provider (Vercel) |
| OI-11 | Toolchain | Approved | 1 | 02 §3 | DEP-11 | — |
| OI-12 | Design system | Approved with deferrals | 1 | 07 §10–§12 | DEP-08 | — |
| OI-13 | Agreement | Approved with deferrals | 3 | 04 §1–§4 | DEP-03 | Legal |
| OI-14 | Stripe catalog | Approved with deferrals | 3 / Prod | 04 §5 | DEP-02 | Provider (live IDs) |
| OI-15 | Payment calculations | Approved | 3 | 04 §7, §12 | DEP-04 | — |
| OI-16 | Maintenance subscription | Approved with deferrals | 3 | 04 §8–§9 | DEP-03 | Legal |
| OI-17 | Stripe payment workflow (revised 2026-11-23) | Approved with deferrals | 3 | 04 §3.1, §8–§14 | DEP-01, DEP-03 | Provider (Stripe) |
| OI-18 | Preview approval | Approved | 4 | 05 §6–§7 | — | — |
| OI-19 | Administrative overrides | Approved | 2–4 | 03 §12 | — | — |
| OI-20 | Uploads | Approved | 4 | 05 §4–§5 | DEP-07 | Provider (Supabase Storage) |
| OI-21 | Privacy and retention | Approved with deferrals | 4 | 07 §5–§9 | DEP-05 | Legal; provider (backups) |
| OI-22 | Publication | Approved | 4 | 06 §2–§9 | — | Provider (Vercel) |
| OI-23 | Performance | Approved | 1 | 02 §7; 07 §11 | DEP-12 | — |
| OI-24 | Post-publication inquiries | Approved | 4 | 06 §11 | — | — |
| OI-25 | Nonresponsive preview clients | Approved | 4 | 05 §7.1–§7.2 | — | — |
| OI-26 | Failed maintenance payments | Approved | 3 | 04 §9.1–§9.1.1, §14 | DEP-03, DEP-06 | Legal (notice); provider (Stripe retries) |
| OI-27 | Financial adjustments | Approved | 3 | 04 §10–§10.1, §12 | OI-47 (approved) | Provider (discount mechanism) |
| OI-28 | Signer authority | Approved | 3 | 04 §3 | DEP-03 | Legal (wording) |
| OI-29 | Stripe Customer Portal | Approved | 3 | 04 §9.2 | DEP-03 | Provider (portal config) |
| OI-30 | Stripe test-mode catalog | Approved; creation blocked | Pre-3 (authorized exception) | 04 §6 | **DEP-01** | Provider (test account) |
| OI-31 | File upload security | Approved | 4 | 05 §5 | DEP-07 | Provider (scanner, cost) |
| OI-32 | Client hosting | Approved | 4 | 02 §2; 06 §4, §8.4 | DEP-03 | Provider (Vercel limits, cost); legal (ownership) |
| OI-33 | Publishing QA | Approved | 4 | 06 §2, §6–§7 | — | — |
| OI-34 | Agreement versioning | Approved | 3 | 04 §1–§4 | DEP-03 | Legal |
| OI-35 | Cancellation and post-cancellation milestones (revised 2026-11-23) | Approved | 3–4 | 04 §15.1–§15.2; 06 §5, §8.4; 02 §13.3 | DEP-03, DEP-06 | Legal (before enforcement); provider (registrar, infrastructure) |
| OI-36 | Tax readiness | Approved | 3 / Prod | 04 §12, §15.3 | DEP-04 | Tax review; provider (Stripe Tax) |
| OI-37 | Disputes | Approved | 3 | 04 §15.4 | DEP-03 | Legal |
| OI-38 | Branding | Approved | 1 / Prod | 07 §10–§12 | DEP-08 (logo confirmed; production assets pending) | Owner final visual approval |
| OI-39 | Provider verification | Approved | Each phase | 02 §10 | DEP-06 | Provider |
| OI-40 | Data governance | Approved | 4 | 07 §5–§9 | DEP-05 | Legal/privacy |
| OI-41 | Production infrastructure | Approved | 5 / Prod | 02 §11 | DEP-09 | Provider; Owner authorization |
| OI-42 | Unused upload retention | Approved | 4 | 07 §5–§6; 05 §4 | DEP-05 | Legal/privacy |
| OI-43 | Business-day and time-zone calendar | Approved | 3 | 02 §13 | DEP-03 | Legal (trigger-date exclusion, wording) |
| OI-44 | Adjusted final-balance payments | Approved | 3 | 04 §10.1 | DEP-06, DEP-03; OI-47 (approved) | Provider (Stripe discounts) |
| OI-47 | Deposit-stage adjustments (Option A: none) | Approved | 3 | 04 §8, §10 | — | Provider (Checkout without discounts) |
| OI-45 | Day-21 preview approval hold | Approved | 4 | 05 §7.2; 04 §14 | — | — |
| OI-48 | Theme mode: dark-only MVP | Approved | 1 | 07 §10 | DEP-08 (future light variant) | — |
| OI-49 | Temporary logo compositing | Approved | 1 | 07 §10.1 | DEP-08 | Owner asset approval |
| OI-53 | Phase 2 implementation notes (N-1 to N-8) | Approved (N-8 amended) | 2 | 03 §18.1 | — | — |
| OI-54 | Expired-invitation cleanup job | Approved (deferred to Phase 5, with condition) | 2 / 5 | 03 §6.1, §18.1 | — | — |
| OI-55 | Adjusted final-balance collection vehicle | Approved | 3 | 04 §10–§10.1 | DEP-06 | Provider (Stripe invoice discounts) |
| OI-63 | Webhook testing strategy (hybrid) | Approved | 3 | 04 §11, §16 | DEP-01, DEP-15 | Provider (Stripe test mode) |
| OI-64 | Stripe test-mode catalog structure (11 products, 11 prices) | Approved | 3 | 04 §6.1 | DEP-01, DEP-02 | Provider (Stripe test mode) |
| OI-65 | Stripe test-mode catalog naming, metadata, keys, versioning | Approved | 3 | 04 §6.1–§6.3 | DEP-01, DEP-04 | Provider (Stripe test mode) |
| OI-46 | Involuntary subscription cancellation | Approved | 3 | 04 §9.1.1; 06 §8.4 | DEP-03, DEP-06 | Legal; provider (Stripe `past_due` behavior) |

## 4. Current authorization status

| Stage (OI-01) | Status | Evidence |
|---|---|---|
| 1. Architecture approval | **Approved** (per owner-provided baseline; pending verification of this register) | §1 |
| 2. Specification reconciliation | Foundation specs approved (below). **Spec 03** v0.4.0: approved 2026-11-23 (Phase 2 authorization). **Spec 04**: approved 2026-11-23 for **Phase 3 Stripe test-mode implementation only**; not approved for production (legal review DEP-03 and provider verification DEP-06 remain conditions). Specs 05–08: in review. | Owner instructions, 2026-11-23 |
| Foundation specs 01, 02 and CLAUDE.md | **Approved (final)**: 01 v0.3.2, 02 v0.4.0, and CLAUDE.md as reconciled in commit `10868de` and merged through PR #1. | [Sign-off record](OWNER-SIGNOFF-FOUNDATION-2026-11-22.md); Owner's written Phase 1 authorization, 2026-11-23 |
| 3. Implementation authorization | **Phase 1** (Foundation and CI): authorized and merged (PR #2). **Phase 2** (Auth, security, and tenant isolation): authorized 2026-11-23 and merged (PR #4, merge commit `45d05f6`); local Supabase only, not deployed. **Phases 3–5: not authorized.** Approval of spec 04 for test-mode implementation does not authorize Phase 3. | Owner's written Phase 1 and Phase 2 authorizations, 2026-11-23 |
| 4. Production launch authorization | **Not authorized** | — |
| Narrow exception: Stripe **test-mode** catalog creation (OI-30) | **Authorized**, limited to creating test products and prices. **Blocked and suspended.** No Stripe request of any kind is made until (1) it is confirmed that the environment used contains **only** an appropriate Stripe test-mode credential, and (2) the Owner gives a **separate, narrowly scoped** written authorization (Owner instruction, 2026-11-23). The catalog design is approved (OI-64, OI-65). Creation is to run only in the dedicated cloud environment `spotlight-client-portal-dev`, which on 2026-11-23 held no network secret and did not allow `api.stripe.com`. The `chris-pribyl` environment still holds the credential previously identified as live-mode and must not be used (DEP-01). | Owner instructions, 2026-11-23 |

## 5. Change history

| Version | Date | Change | Author | Approved by |
|---|---|---|---|---|
| — | 2026-11-22 | Repository created with minimal README (`dfc3553`) | Owner | — |
| 0.1.0 | 2026-11-22 | Initial transcription of OI-01–OI-24. Specifications 01–07, README, CLAUDE.md, and OPEN-ISSUES.md created. The prior read-only audit's Stripe catalog concern was corrected per the owner: separate deposit and balance prices exist. | Claude Code (documentation author) | Pending owner review |
| 0.2.0 | 2026-11-23 | Transcribed approved decisions OI-25–OI-41 and added the §3A traceability matrix. Reconciled specs 01–07, README, CLAUDE.md, and OPEN-ISSUES. Moved OI-25–OI-41 to decided. Opened OI-42–OI-46 from the cross-document audit. Created the dependency register DEP-01–DEP-12. Recorded the official logo candidate (07 §10.1). Recorded the Stripe test-catalog creation as blocked (DEP-01). | Claude Code (documentation author) | Pending owner review |
| 0.3.0 | 2026-11-23 | Transcribed approved decisions OI-42–OI-46. Extended the §3A matrix to 46 decisions. Added the shared deadline calendar (02 §13), adjusted final-balance Checkout (04 §10.1), the failed-payment-to-termination lifecycle (04 §9.1.1), the day-21 approval hold (05 §7.2), and used/unused retention with the closure event (07 §6). Opened OI-47 (deposit-stage adjustments). Reassessed dependency phases. Recorded the Stripe test-catalog action as suspended. | Claude Code (documentation author) | Pending owner review |
| 0.3.1 | 2026-11-23 | DEP-10 marked complete. The Owner created the active ruleset `protect-main` on the default branch: pull request required with 0 approvals (Owner decision, sole developer), force pushes blocked, deletions restricted, no status checks. The GitHub API confirms `main` is protected. Rule details are Owner-attested. | Claude Code (documentation author) | Pending owner review |
| 0.3.2 | 2026-11-23 | Recorded the Owner's confirmation that the SLM folder logo (Drive file ID `13-UmtqYfcweEZUCwCcYiIsHiTy9RMTKX`, SHA-256 `6cc6edb3…b2bd3c`) is the official master. DEP-08 Phase 1 part complete; production asset variants and final visual approval remain outstanding. | Claude Code (documentation author) | Owner (logo confirmation only) |
| 0.4.0 | 2026-11-23 | Recorded the Owner sign-off of specs 01, 02 and CLAUDE.md (conditional, `OWNER-SIGNOFF-FOUNDATION-2026-11-22.md`). Applied the mandatory reconciliation: OI-35 revised into M1 (12 business days, maintenance and designated infrastructure cessation) and M2 (60 calendar days, final transfer and offboarding), a one-year initial domain term separate from hosting, no guaranteed functionality after discontinuation, no intentional degradation, and a commercially reasonable $99 model with no uptime or response-time guarantees. Updated specs 01–07, tests, README, CLAUDE.md, and OPEN-ISSUES. | Claude Code (documentation author) | Owner (sign-off record; final confirmation pending) |
| 0.5.0 | 2026-11-23 | Recorded the Owner's final approval of 01 v0.3.2, 02 v0.4.0, and CLAUDE.md, and the Phase 1 authorization. Status lines only; approved spec content unchanged. Phase 1 foundation delivered on branch `phase-1/foundation-ci`. DEP-11 complete. OI-48 (theme mode) opened. | Claude Code | Owner (Owner's written Phase 1 authorization, 2026-11-23) |
| 0.6.0 | 2026-11-23 | Final Phase 1 refinements. OI-48 approved (dark-only MVP, light-theme compatibility preserved). OI-49 approved (temporary logo compositing; master preserved). The CSP `'unsafe-inline'` limitation is tracked as the Phase 2 security requirement DEP-13 / T-SEC-03. Production gating test added. | Claude Code | Owner (Owner instruction, 2026-11-23 (final Phase 1 refinements)) |
| 0.7.0 | 2026-11-23 | Phase 2 security specification finalization (documentation only): spec 03 v0.4.0 drafted for Owner sign-off, with Supabase and Next.js provider verification evidence in the new 03A. **No Owner decision changed.** All new design detail is [PROPOSED]. Opened OI-50 to OI-52; added DEP-14; DEP-13 designed. | Claude Code | Pending owner review |
| 0.8.0 | 2026-11-23 | **OI-17 revised (Owner instruction): automatic final-balance collection.** The payment method is saved at the initial Checkout under the legal-adviser-approved *Authorization for Final Payment* clause (04 §3.1, verbatim). The client's final approval (**Approve Website & Authorize Final Payment**) authorizes an automatic charge, with Stripe invoice and receipt, a Stripe-hosted completion option on failure, no publication before verified payment, duplicate-charge controls, and recovery without recharging. The separate final Checkout is removed from 01, 03, 04, 05, 06, 07 and README. Opened OI-55 (OI-44 collection vehicle). Documentation only. | Claude Code | Owner (instruction, 2026-11-23); OI-55 pending |
| 0.8.1 | 2026-11-23 | **OI-55 approved (option A).** Owner-authorized final-balance discounts are applied to the automatic final-balance invoice, with every OI-44 safeguard unchanged. An interim block on collecting discounted final balances was recorded and then **lifted** by the Owner the same day, so collection on the invoice is authorized. 04 §10–§10.1, T-BIL-11 and 03 §4 updated. | Claude Code | Owner (instructions, 2026-11-23) |
| 0.9.0 | 2026-11-23 | Recorded the Owner's approval of spec 03 v0.4.0 (with 03A as supporting evidence) and the **Phase 2 authorization** (local Supabase with synthetic data; CI with the Supabase CLI). Phase 2 implemented on branch `phase-2/auth-security-tenancy` for Owner review: migrations, RLS, invitation-only OTP, staff TOTP MFA, roles, append-only audit, nonce CSP, private storage policies, and automated tests. 03 v0.4.2 adds §18.1 implementation notes pending Owner confirmation (OI-53); 03A v0.2.0 records the spike results. DEP-13 complete. Opened OI-53, OI-54. **No Owner decision changed.** | Claude Code | Owner (spec 03 approval and Phase 2 authorization only; OI-53 pending) |
| 0.9.1 | 2026-11-23 | **OI-54 approved:** the expired-invitation cleanup job is deferred to Phase 5, on the condition that expired invitations are rejected at every authentication and acceptance boundary regardless of cleanup status. The condition is verified by new pgTAP and integration tests. OI-53 is still pending Owner confirmation. | Claude Code | Owner (instruction, 2026-11-23) |
| 0.9.2 | 2026-11-23 | **OI-53 approved** with N-8 amended (security events recorded only by the server with a verified actor; payload bounds) and N-2 / N-6 retained. **Phase 2 remediation:** D1 removed client and staff execution of the security-event writer and bounded audit payloads; D3 corrected the client-facing label for staff invitations. Spec 03 v0.4.3. | Claude Code | Owner (Phase 2 Security Remediation Authorization, 2026-11-23) |
| 0.10.0 | 2026-11-23 | **OI-47 approved (Option A):** the standard 20% deposit is mandatory for all five packages, and the initial Checkout always contains the standard deposit plus the first $99 maintenance payment. No deposit-stage discounts, credits, or waivers. Owner-authorized reductions apply only to the outstanding final balance, under OI-44 / OI-55. The maintenance subscription is never reduced. 04 v0.5.1 (new tests T-BIL-20, T-BIL-21); 03 v0.4.4 (§12 row). Documentation only. | Claude Code | Owner (decision, 2026-11-23) |
| 0.11.0 | 2026-11-23 | Owner instructions: **OI-47** item 6 confirmed (a reduction can never exceed the outstanding final balance). **OI-63 approved** (hybrid webhook testing: signed synthetic events in CI; real Stripe test-mode verification separately). **Spec 04 v0.6.0 approved for Phase 3 Stripe test-mode implementation only**; legal review and provider verification remain production conditions. **Stripe access** requires an environment holding only an appropriate test credential plus a separate, narrowly scoped authorization. §4 authorization table brought up to date (Phase 2 merged). DEP-15 added. Phase 3 is **not** authorized. | Claude Code | Owner (instructions, 2026-11-23) |
| 0.12.0 | 2026-11-23 | **OI-64 approved** (test-mode catalog of 11 products and 11 prices). **OI-65 approved** (naming, metadata, catalog keys, lookup keys, and versioning, provided no existing test-mode object conflicts). 04 v0.7.0 adds the catalog manifest, conflict rules, and execution constraints (§6.1–§6.3). DEP-01 remains **blocked**; its environment reference now names `spotlight-client-portal-dev`, and its credential permissions are listed. Stale Phase 2 status references corrected (CLAUDE.md §1, README, 01 §8 stage table, DEP-13). Owner confirmed that the maintenance product's `package_key` stays unset. The 04 §6.3 test-mode preflight now fails closed and does not rely on an unverified Balance `livemode` field: it requires Owner attestation of an `rk_test_` key, prior documentation confirmation, and an explicit `livemode: false` on every response. Catalog-design approvals only: no Stripe request, no credential, and no Phase 3 work. | Claude Code | Owner (decisions, 2026-11-23) |
| 0.12.1 | 2026-11-23 | **Provider verification recorded (DEP-06, Stripe):** Stripe's official OpenAPI specification (`2026-09-30.endive`, commit `2dcbcfb`) defines `livemode` as a required boolean on the Balance, Product, and Price objects, so 04 §6.3 preflight step 2 is satisfied. 04 §6.1 clarifies that a price's `tax_behavior` cannot be changed once set to `inclusive` or `exclusive`. 04 v0.7.1. The fail-closed preflight, the catalog values, and all restrictions are unchanged. Restricted-key permission scope and idempotency-key retention remain unverified, because `docs.stripe.com` is not reachable from the session environment. Documentation only; DEP-01 remains blocked. | Claude Code | Owner (documentation-correction authorization, 2026-11-23) |

## 6. Change-control rules

1. **Decision changes.** A change to an OI-01–OI-46 decision requires explicit owner approval. The change is recorded as a new dated entry in §5, and the decision text is amended with a "Revised (date)" note. Original IDs are never reused or renumbered.
2. **New decisions.** New open questions are added to [OPEN-ISSUES.md](../OPEN-ISSUES.md) with the next unused ID (currently OI-66 onward; OI-56 to OI-62 are allocated in draft PR #6). Implementation dependencies use DEP-nn IDs (currently DEP-16 onward). When the owner resolves one, it is recorded in this register under that same ID.
3. **Specification changes.** Changes to specifications 01–07 go through a pull request. Each spec carries a version and status header. A spec moves from *Draft* to *Approved* only on owner sign-off recorded in §5.
4. **Precedence.** (a) Owner-approved decisions in this register. (b) Approved specifications 01–07. (c) CLAUDE.md for operating procedure. (d) README. A lower-precedence document must never be used to override a higher one.
5. **Conflicts.** Any conflict between documents, or between a document and an owner decision, is **escalated** to the owner as an open issue. It is never silently resolved by an author or agent.
6. **Classification integrity.** A **[PROPOSED]** item becomes binding only when the spec containing it is approved. A **[PENDING]** or **[DEFERRED]** item may be closed only by a recorded owner decision.
7. **Authorization separation.** Approving a document or decision never authorizes implementation or production activity. Those require stage 3 or stage 4 authorization (OI-01), granted per phase (OI-02).
