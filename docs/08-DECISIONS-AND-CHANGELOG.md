# 08 — Decisions and Changelog

| Field | Value |
|---|---|
| Document | Architecture Decision Register and Change Log |
| Version | 0.1.0 (draft for owner review) |
| Status | **Draft — pending owner verification** |
| Applies to | Spotlight Marketing Client Portal (`portal.spotlight-marketing.co`) |
| Related | [OPEN-ISSUES.md](../OPEN-ISSUES.md), [CLAUDE.md](../CLAUDE.md), specifications 01–07 |

---

## 1. Provenance statement

The 24 decisions in this register (OI-01 through OI-24) were **transcribed from the owner-provided approved baseline** supplied to the documentation author on 2026-11-22. That baseline was produced through the owner's ChatGPT-assisted architecture review process.

- These approvals have **not** been independently verified through Git history, signed records, or any other artifact in this repository. Before this change set, the repository contained only a six-line `README.md` (commit `dfc3553`).
- This register is therefore **pending owner verification**. The owner must confirm that each transcribed decision matches what was approved. If a transcription is wrong, the owner's correction prevails and is recorded in §5.
- Approval of this register does **not** authorize implementation (see §4 and OI-01).

## 2. Requirement classification legend

All specifications in this repository use these labels:

| Label | Meaning |
|---|---|
| **[APPROVED OI-nn]** | Owner-approved architectural requirement traced to decision OI-nn. Binding. |
| **[PROPOSED]** | Engineering detail proposed by the documentation author. Not binding until the owner approves the specification containing it. |
| **[PENDING OI-nn]** | Open owner decision tracked in [OPEN-ISSUES.md](../OPEN-ISSUES.md) (OI-25 onward). It must not be assumed. |
| **[DEFERRED]** | Legal, commercial, or brand policy deferred until production readiness. Placeholder only. |
| **[VERIFY-PROVIDER]** | Behavior or capability of a third-party provider (Stripe, Supabase, Vercel, Resend, etc.) that must be verified against current provider documentation and plan limits during authorized implementation. |

## 3. Decision register

The status column uses:
- **Approved** — the decision is complete at the architectural level.
- **Approved with deferrals** — the architecture is decided, but named sub-items remain open or deferred.

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
  - The remaining 80% is collected in a separate payment-mode Checkout.
  - Require signature-verified webhooks, idempotent processing, financial reconciliation, audit history, failed-payment handling, billing holds, and server-side payment verification.
  - A successful redirect is never proof of payment.
  - Refund, cancellation, tax, and dispute policies remain pending.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Billing hold rules (OI-26); Stripe Customer Portal (OI-29); OI-35, OI-36, OI-37.
- **Affected sections:** 04 §8–§14.

### OI-18 — Preview approval

- **Decision:** Client approval is tied to an immutable released preview version. A newly released preview requires renewed approval. Internal drafts do not invalidate an approved release. Historical approvals are preserved. Client silence is never represented as explicit approval. The nonresponsive-client escalation procedure remains unresolved.
- **Status:** Approved with deferrals.
- **Provenance:** Owner-provided baseline.
- **Deferrals:** Nonresponsive client procedure (OI-25).
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

## 4. Current authorization status

| Stage (OI-01) | Status | Evidence |
|---|---|---|
| 1. Architecture approval | **Approved** (per owner-provided baseline; pending verification of this register) | §1 |
| 2. Specification reconciliation | **In progress.** Documentation-only changes authorized. This change set is under owner review. | Draft PR for branch `docs/architecture-specification-reconciliation` |
| 3. Implementation authorization | **Not authorized** for any phase | — |
| 4. Production launch authorization | **Not authorized** | — |

## 5. Change history

| Version | Date | Change | Author | Approved by |
|---|---|---|---|---|
| — | 2026-11-22 | Repository created with minimal README (`dfc3553`) | Owner | — |
| 0.1.0 | 2026-11-22 | Initial transcription of OI-01–OI-24. Specifications 01–07, README, CLAUDE.md, and OPEN-ISSUES.md created. The prior read-only audit's Stripe catalog concern was corrected per the owner: separate deposit and balance prices exist. | Claude Code (documentation author) | Pending owner review |

## 6. Change-control rules

1. **Decision changes.** A change to an OI-01–OI-24 decision requires explicit owner approval. The change is recorded as a new dated entry in §5, and the decision text is amended with a "Revised (date)" note. Original IDs are never reused or renumbered.
2. **New decisions.** New open questions are added to [OPEN-ISSUES.md](../OPEN-ISSUES.md) with the next unused ID (currently OI-42 onward). When the owner resolves one, it is recorded in this register under that same ID.
3. **Specification changes.** Changes to specifications 01–07 go through a pull request. Each spec carries a version and status header. A spec moves from *Draft* to *Approved* only on owner sign-off recorded in §5.
4. **Precedence.** (a) Owner-approved decisions in this register. (b) Approved specifications 01–07. (c) CLAUDE.md for operating procedure. (d) README. A lower-precedence document must never be used to override a higher one.
5. **Conflicts.** Any conflict between documents, or between a document and an owner decision, is **escalated** to the owner as an open issue. It is never silently resolved by an author or agent.
6. **Classification integrity.** A **[PROPOSED]** item becomes binding only when the spec containing it is approved. A **[PENDING]** or **[DEFERRED]** item may be closed only by a recorded owner decision.
7. **Authorization separation.** Approving a document or decision never authorizes implementation or production activity. Those require stage 3 or stage 4 authorization (OI-01), granted per phase (OI-02).
