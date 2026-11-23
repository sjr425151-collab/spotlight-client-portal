# 07 — Notifications, Privacy, and Design

| Field | Value |
|---|---|
| Version | 0.2.0 |
| Status | **Draft — pending owner sign-off** |
| Decisions | OI-04, OI-12, OI-21, OI-23, OI-25, OI-26, OI-31, OI-35, OI-37, OI-38, OI-40 |
| Open issues | OI-42 |
| Dependencies | DEP-05, DEP-07, DEP-08 |

---

## Part A — Notifications

## 1. Transactional notification architecture **[APPROVED OI-04]**

| Channel | Responsibility |
|---|---|
| Supabase Auth email | Invitation and OTP emails, sent through a properly configured custom SMTP sender per environment **[VERIFY-PROVIDER]** |
| Resend | All other operational transactional email |
| Stripe | Applicable payment receipts and invoices **[VERIFY-PROVIDER: receipt settings]** |

- **Excluded from the MVP:** marketing automation sequences, newsletters, and drip campaigns. **[APPROVED OI-04]**
- **[APPROVED OI-04]** Sender domains are verified (SPF/DKIM/DMARC) for each environment. Non-production environments cannot email real clients **[PROPOSED: allow-list or sink]**.

## 2. Durable outbox **[APPROVED OI-04]**

- Business transactions write a `notification_outbox` row **in the same database transaction** as the state change that triggers it **[PROPOSED]**.
- Each row holds: event type, recipient(s), template key and version, payload reference (no secrets, minimal personal data), an idempotency key, status (`pending → sending → sent` / `failed` / `dead`), attempt count, `next_attempt_at`, the provider message ID, and the last error.
- A worker drains the outbox. Delivery logs are retained per §6.

## 3. Delivery retries and idempotency **[APPROVED OI-04]**

- **[PROPOSED]** The idempotency key is `event_type + subject_id + version`, for example `preview.released:<release_id>`. The key is passed to Resend as an idempotency key **[VERIFY-PROVIDER]**.
- **[PROPOSED]** Exponential backoff (1 min, 5 min, 30 min, 2 h, 12 h), then `dead`, which raises an Admin queue item.
- A duplicate enqueue with the same key is a no-op.
- Bounces and complaints from provider webhooks are recorded **[PROPOSED]**.

## 4. Event catalog **[PROPOSED]**

| Event | Recipient | Channel |
|---|---|---|
| Invitation | Client | Supabase Auth |
| OTP code | User | Supabase Auth |
| Agreement accepted (copy of version and order summary) | Client, Owner | Resend |
| Deposit and first maintenance receipt | Client | Stripe |
| Deposit verified / intake unlocked | Client | Resend |
| Intake submitted | Staff | Resend |
| Intake changes requested | Client | Resend |
| Preview released | Client | Resend |
| Approval reminder: day 3, day 7 (OI-25) | Client | Resend |
| Approval pending: Admin notification, day 7 (OI-25) | Admin | Resend |
| Approval personal follow-up due, day 14 (OI-25) | Staff | Resend |
| Preview approved | Staff | Resend |
| Final payment due | Client | Resend |
| Final payment receipt | Client | Stripe |
| Final payment verified | Client, Staff | Resend |
| Maintenance payment failed and recovery reminders during the 7-day period | Client, Owner | Stripe and/or Resend (OI-26) |
| Hold placed / cleared | Client (payment holds), Owner | Resend |
| Upload rejected: failed scan or invalid type, with actionable re-upload guidance (OI-31) | Client, Staff | Resend |
| Cancellation request received / confirmed (OI-35) | Client, Owner | Resend |
| Transition deadline and responsibilities notice (OI-35) | Client | Resend |
| Transition deadline approaching / passed (OI-35) | Client, Owner | Resend |
| Dispute opened: **immediate** (OI-37) | Owner | Resend |
| Dispute evidence deadline reminders (OI-37) | Owner | Resend |
| Publication live | Client, Owner | Resend |
| Publication / verification failed | Owner | Resend |
| Service inquiry received | Staff | Resend |
| Service inquiry acknowledgment | Client | Resend |
| Reconciliation mismatch | Owner | Resend |
| Data request received / completed | Client, Owner | Resend |

---

## Part B — Privacy and retention

## 5. Privacy controls **[APPROVED OI-21]**

- **Data minimization:** collect only the intake fields needed to build the website. No payment card data is stored in the portal; Stripe holds it.
- **Least privilege:** 03 §4 and §9.
- **Encryption:** in transit (TLS) and at rest (provider-managed) **[VERIFY-PROVIDER]**.
- **Legal holds:** a legal hold on a project or user suspends every deletion and retention job for the affected records. Placing and removing holds is Owner-only and audited **[PROPOSED]**.
- **Secure deletion:** delete from the database and storage, and propagate to derivatives. Backups expire on their rolling schedule **[PROPOSED]**.
- **Backup controls:** rolling 30 days, subject to provider capabilities **[VERIFY-PROVIDER OI-39]**. Restore testing in Phase 5.

## 6. Provisional retention schedule **[APPROVED OI-21, OI-40 — provisional pending legal and privacy review, DEP-05]**

| Data | Retention | Source |
|---|---|---|
| Active client and project records | Duration of the relationship | OI-21, OI-40 |
| Project assets | 12 months after project closure | OI-21, OI-40 |
| Unused uploads | 90 days after closure. This is in OI-21 but **absent from OI-40**, so whether it still applies is **[PENDING OI-42]**. | OI-21 |
| Abandoned onboarding / intake | 90 days | OI-21, OI-40 |
| Agreements and acceptance evidence | 7 years after termination | OI-21, OI-40 |
| Financial records (ledger, webhook events, disputes, refunds, adjustments) | 7 years | OI-21, OI-40 |
| Security logs | 12 months | OI-21, OI-40 |
| Administrative audit logs | 3 years | OI-21, OI-40 |
| Failed temporary uploads | 7 days | OI-21, OI-40 |
| Recoverable backups | Rolling 30 days, subject to provider capabilities (DEP-06) | OI-21, OI-40 |

- **[APPROVED OI-40]** Subscription cancellation and account closure do **not** automatically delete legally required records.
- The retention clock for project assets starts at project closure, which is distinct from subscription cancellation. **[PROPOSED]** Closure is recorded explicitly, no earlier than the transition deadline (04 §15.1).
- Legal holds suspend every retention deletion (§5).

- **[APPROVED OI-21]** Account closure does **not** automatically cancel Stripe billing or delete legally required records.
- **[PROPOSED]** Retention jobs are idempotent, respect legal holds, and write audit events summarizing what was deleted (counts and IDs, not content).

## 7. Data subject request handling **[APPROVED OI-21]**

| Request | Procedure **[PROPOSED]** |
|---|---|
| Export | Client requests in the portal. Identity confirmed by an active session plus OTP. Admin prepares a machine-readable export (profile, intake, assets list, agreements, payment history). Delivered through a time-limited private link. |
| Correction | Client edits where permitted. Otherwise an Admin edit with an audit event. |
| Deletion | Client requests. The Owner reviews against retention obligations and legal holds. Deletable data is deleted. Legally required records (agreements, transactions) are retained and their restriction is noted. Stripe billing is handled separately (§6). |

SLAs and legal applicability require legal and privacy review (DEP-05).

## 8. Vendor inventory **[APPROVED OI-21]**

| Vendor | Purpose | Data categories | Status |
|---|---|---|---|
| Vercel | Portal hosting | Request logs, application traffic | Approved (OI-10) |
| Supabase | Auth, database, storage | All portal data | Approved (OI-08, 09) |
| Stripe | Payments | Billing identity, payment data | Approved (OI-14, 17) |
| Resend | Transactional email | Email address, notification content | Approved (OI-04) |
| GitHub | Source and CI | Code, no client data **[PROPOSED rule]** | Approved (OI-10) |
| Malware scanner | Upload screening | Uploaded files | Required (OI-31). Vendor selection is DEP-07. |
| Monitoring / error tracking | Observability | Error context, which must be scrubbed of personal data | To be selected (02 §8) |
| Vercel (client sites) | Client website hosting | Approved site content | Approved (OI-32) |
| Google Workspace / Drive (future) | Future integrations only; not in the MVP | — | Requires OI-39 verification before any use |

DPAs and subprocessor terms must be reviewed before production (DEP-05).

## 9. Incident response **[APPROVED OI-21]**

**[PROPOSED]** phases: detect → triage (severity, 06 §8.3) → contain (revoke sessions, rotate keys, disable affected features) → assess personal-data impact → notify (Owner; affected clients and regulators as legally required, DEP-05) → recover → post-incident review recorded.

---

## Part C — Design system

## 10. Premium design system requirements **[APPROVED OI-12, OI-38]**

**Approved direction [OI-38]:** premium, minimalist, professional, accessible, and enterprise-grade.

### 10.1 Official logo source **[APPROVED OI-38]**

| Item | Value |
|---|---|
| Official source folder | Google Drive folder "SLM": `https://drive.google.com/drive/folders/1SGrxZ6fOI6PZUVk76XYaEFS4pQ26LvGu` |
| Contents at inspection (2026-11-23) | **One** file: `66108F14-6E43-4109-97F1-8134E04549F7.jpeg` (Drive file ID `13-UmtqYfcweEZUCwCcYiIsHiTy9RMTKX`) |
| Format | JPEG, 597 × 335 px, 72 dpi, RGB. No transparency. |
| SHA-256 (as downloaded) | `6cc6edb39da3a8a6e5412d14989c590039632aff85e4114812c21a2ce8b2bd3c` |
| Visual description | White "SPOTLIGHT" wordmark (bold, italic, geometric sans), with "MARKETING" below in widely letter-spaced capitals. Both sit within a glowing white/blue-white crescent ("eclipse") arc, on a solid black background. |
| Candidate status | A single unambiguous candidate. **Identified, not yet confirmed by the Owner as the official master** (DEP-08). |

Rules **[APPROVED OI-38]**:
- Use this logo as the foundation of the portal's visual design. Preserve its original proportions and visual identity: no stretching, recoloring, redrawing, or effects.
- **Do not generate a replacement logo**, and do not trace or vectorize it without Owner approval.
- Colors sampled from the logo (black, white, blue-white glow) may inform the palette. They are **not** final brand colors until the Owner approves them.

Asset gaps (DEP-08) for production-quality use:
- No vector master (SVG, AI, or PDF).
- No transparent-background version.
- No light-background or monochrome variant.
- No favicon or app icon.
- 597 px width is below retina needs for large hero usage.

The Owner must supply or approve these. The JPEG is not committed to this repository.

- Centralized design tokens (color, typography, spacing, radius, elevation, motion) are the single source for the portal UI and the email templates **[PROPOSED]**.
- Brand assets (logos, imagery, fonts) are replaceable through configuration, without code changes to components **[APPROVED OI-12]**.
- Responsive layouts from 320 px upward. Light theme required. Dark theme optional **[PROPOSED]**.
- Components cover the full client journey (01 §3) with consistent states: loading, empty, error, success, and "payment processing."

## 11. Accessibility and performance **[APPROVED OI-12, OI-23]**

- **[PROPOSED]** Target WCAG 2.2 AA. Lighthouse Accessibility ≥ 95 **[APPROVED OI-23]**.
- Keyboard operability, visible focus, form error association, and sufficient contrast with the final brand palette (re-verified at OI-38).
- **[APPROVED OI-23]** Accessible, restrained motion. All non-essential animation is disabled under `prefers-reduced-motion`.
- Performance budgets are in 02 §7.

## 12. Brand approval dependencies **[APPROVED OI-38; final approval DEP-08]**

Before production, the Owner must:
- confirm the official logo file (§10.1)
- supply or approve logo variants
- approve the color palette, typography and font licensing, email template branding, favicon, and social preview imagery

**Final visual design requires Owner approval before production.** Until then, implementation uses the identified logo (once confirmed) with provisional, clearly labeled design tokens.

## 13. Acceptance tests **[PROPOSED]**

| ID | Test |
|---|---|
| T-NOT-01 | A state change and its outbox row commit atomically. If one rolls back, so does the other. |
| T-NOT-02 | Enqueuing the same idempotency key twice produces one send |
| T-NOT-03 | A provider failure retries on schedule, then marks the row dead and raises a queue item |
| T-NOT-04 | Non-production environments cannot deliver to non-allow-listed addresses |
| T-NOT-05 | No marketing or automated sequence templates exist in the MVP catalog |
| T-PRV-01 | Retention jobs delete failed uploads after 7 days and skip records under legal hold |
| T-PRV-02 | Account closure does not call any Stripe cancellation API |
| T-PRV-03 | Exports contain only the requesting user's authorized projects |
| T-PRV-04 | Logs and error reports contain no OTPs, tokens, or full card data |
| T-DES-01 | Swapping the brand token and asset configuration changes the UI with no component code changes |
| T-DES-02 | Automated a11y scans report no critical violations on all journey pages |
| T-DES-03 | With reduced motion enabled, non-essential animations are disabled |
| T-DES-04 | Logo renders at its original aspect ratio (597:335) at every breakpoint, with no CSS distortion (OI-38) |
| T-NOT-06 | Every event in §4 for OI-25, OI-26, OI-31, OI-35, and OI-37 has a template and is enqueued by its trigger |
| T-PRV-05 | Subscription cancellation triggers no deletion of agreements, financial records, or audit logs (OI-40) |
