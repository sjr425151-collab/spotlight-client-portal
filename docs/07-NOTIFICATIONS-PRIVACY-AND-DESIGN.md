# 07 — Notifications, Privacy, and Design

| Field | Value |
|---|---|
| Version | 0.4.0 |
| Status | **Approved** (Owner, 2026-11-23, consolidated execution plan approval). Retention periods remain provisional (DEP-05). v0.4.0: notification delivery sequenced by release (OI-04 revised by OI-68); Resend SMTP for Supabase Auth email (OI-51). Earlier: v0.3.4 final-payment notifications for the automatic charge (OI-17 revised). |
| Decisions | OI-04, OI-12, OI-21, OI-23, OI-25, OI-26, OI-31, OI-35, OI-37, OI-38, OI-40, OI-42, OI-43, OI-45, OI-46, OI-51, OI-68 |
| Open issues | None |
| Dependencies | DEP-05, DEP-07, DEP-08 |

---

## Part A — Notifications

## 1. Transactional notification architecture **[APPROVED OI-04]**

| Channel | Responsibility |
|---|---|
| Supabase Auth email | Invitation and OTP emails, sent through a properly configured custom SMTP sender per environment: **Resend SMTP** on a separate auth sending subdomain **[APPROVED OI-51; VERIFY-PROVIDER]** |
| Resend | All other operational transactional email |
| Stripe | Applicable payment receipts and invoices **[VERIFY-PROVIDER: receipt settings]** |

- **Excluded from the MVP:** marketing automation sequences, newsletters, and drip campaigns. **[APPROVED OI-04]**

**Delivery by release [APPROVED OI-04, revised by OI-68]:**

| | R1 | R2 |
|---|---|---|
| Invitation and OTP email | Supabase Auth through Resend SMTP | Same |
| Stripe receipts and invoices | Stripe | Same |
| Outbox | Every event is written to `notification_outbox` in the same transaction as its state change (§2) | Same, and drained by the delivery worker |
| Client and staff lifecycle events | Shown in the portal (client status page and derived queues). Required outreach is performed by staff and recorded (05 §7.1). | Resend email for the full §4 catalog |
| Owner-critical alerts: dispute opened, reconciliation mismatch, webhook processing failure, publication or verification failure | Monitoring alert channel (DEP-12), plus the portal queue | Resend email as well |
| Upload rejected (OI-31) | In-portal notice to the client with re-upload guidance, and a staff queue item | Resend email as well |
- **[APPROVED OI-04]** Sender domains are verified (SPF/DKIM/DMARC) for each environment. Non-production environments cannot email real clients **[PROPOSED: allow-list or sink]**.

## 2. Durable outbox **[APPROVED OI-04]**

- Business transactions write a `notification_outbox` row **in the same database transaction** as the state change that triggers it **[PROPOSED]**.
- Each row holds: event type, recipient(s), template key and version, payload reference (no secrets, minimal personal data), an idempotency key, status (`pending → sending → sent` / `failed` / `dead`), attempt count, `next_attempt_at`, the provider message ID, and the last error.
- A worker drains the outbox **[R2]**. Delivery logs are retained per §6. **[PROPOSED]** In R1, rows are written with status `recorded` and are never sent. R2 sends only rows created after delivery is enabled, so no stale notification is delivered retroactively.

## 3. Delivery retries and idempotency **[APPROVED OI-04]**

- **[PROPOSED]** The idempotency key is `event_type + subject_id + version`, for example `preview.released:<release_id>`. The key is passed to Resend as an idempotency key **[VERIFY-PROVIDER]**.
- **[PROPOSED]** Exponential backoff (1 min, 5 min, 30 min, 2 h, 12 h), then `dead`, which raises an Admin queue item.
- A duplicate enqueue with the same key is a no-op.
- **Scheduling [APPROVED OI-43]:** deadline-driven notifications (preview reminders, payment recovery, cancellation milestones M1 and M2, dispute deadlines) take their due times from the shared deadline calendar (02 §13) in America/Detroit. Due times and `next_attempt_at` are stored in UTC. Retries never move a contractual or administrative deadline.
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
| Final payment action required: the automatic charge failed or needs authentication, with the secure Stripe-hosted payment link (04 §10) | Client | Resend |
| Final balance itemized invoice and payment receipt | Client | Stripe |
| Final payment verified | Client, Staff | Resend |
| Maintenance payment failed and recovery reminders during the 7-day period | Client, Owner | Stripe and/or Resend (OI-26) |
| Hold placed / cleared | Client (payment holds), Owner | Resend |
| Upload rejected: failed scan or invalid type, with actionable re-upload guidance (OI-31) | Client, Staff | Resend |
| Cancellation request received / confirmed (OI-35) | Client, Owner | Resend |
| Cancellation milestones (M1, M2) and responsibilities notice (OI-35) | Client | Resend |
| M1 reached: maintenance cessation (OI-35) | Client, Owner | Resend |
| M2 approaching (required notices, per final agreement) / passed (OI-35) | Client, Owner | Resend |
| Domain initial term approaching expiry (Spotlight-registered domains) **[PROPOSED]** | Client, Owner | Resend |
| Dispute opened: **immediate** (OI-37) | Owner | Resend |
| Dispute evidence deadline reminders (OI-37) | Owner | Resend |
| Approval hold placed / cleared (OI-45) | Client, Owner, Admin | Resend |
| Client responded during approval hold (OI-45) | Admin, Owner | Resend |
| Billing hold Owner review required (OI-46) | Owner | Resend |
| Unexpected Stripe cancellation exception (OI-46) | Owner | Resend |
| Service termination authorized / effective, with M1 and M2 dates (OI-46) | Client, Owner | Resend |
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
- **Secure deletion:** delete from the database and storage, and propagate to derivatives.
  - Deleted content can persist in backups only until the rolling 30-day backup window expires **[APPROVED OI-42 requires accounting for backup expiry; detail PROPOSED]**.
  - Any restore from backup must re-apply the deletion log before the restored data is used **[PROPOSED]**.
  - **Deletion evidence [APPROVED OI-42]:** an immutable audit record holding **metadata only** (asset ID, category, size, content hash, retention policy, deletion time, job ID). The deleted content itself is never retained.
- **Backup controls:** rolling 30 days, subject to provider capabilities **[VERIFY-PROVIDER OI-39]**. Restore testing in Phase 5.

## 6. Provisional retention schedule **[APPROVED OI-21, OI-40 — provisional pending legal and privacy review, DEP-05]**

| Data | Retention | Source |
|---|---|---|
| Active client and project records | Duration of the relationship | OI-21, OI-40 |
| Project assets **used** in a released preview or final deliverable | 12 months after project closure | OI-21, OI-40, OI-42 |
| **Unused** client uploads (never incorporated into a released preview or final deliverable) | 90 days after project closure, then secure deletion unless a legal hold, applicable law, or another documented obligation requires preservation | OI-21, OI-42 |
| Abandoned onboarding / intake | 90 days | OI-21, OI-40 |
| Agreements and acceptance evidence | 7 years after termination | OI-21, OI-40 |
| Financial records (ledger, webhook events, disputes, refunds, adjustments) | 7 years | OI-21, OI-40 |
| Security logs | 12 months | OI-21, OI-40 |
| Administrative audit logs | 3 years | OI-21, OI-40 |
| Failed temporary uploads | 7 days | OI-21, OI-40 |
| Recoverable backups | Rolling 30 days, subject to provider capabilities (DEP-06) | OI-21, OI-40 |

- **[APPROVED OI-40]** Subscription cancellation and account closure do **not** automatically delete legally required records.
- **Project closure event.** **[APPROVED OI-42]** requires a defined closure event; the definition below is **[PROPOSED]**. Retention clocks start at an explicit, audited `project.closed` event recorded by the Owner or an Admin. It may be recorded only when no development work remains outstanding, and either:
  - (a) for a project with a maintenance subscription: the 60-calendar-day offboarding deadline (M2) has passed (04 §15.1), or the client has completed transfer; or
  - (b) for a project cancelled before publication: the cancellation is effective and cancellation accounting is complete.

  Subscription cancellation alone is not closure.
- **Automated enforcement.** **[APPROVED OI-42]** This is a future implementation requirement for Phase 4. A scheduled retention job classifies each asset as used or unused, evaluates due dates in America/Detroit (02 §13), skips anything under legal hold, and writes metadata-only deletion evidence. No retention deletion runs until the job is implemented and authorized.
- These periods are provisional and **not legally finalized** (DEP-05).
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
| Presentation | Temporary compositing (screen blend plus a narrow edge fade) **[APPROVED OI-49]**. The master file is never modified, and its checksum is pinned by a test. |
| Status | **Confirmed by the Owner as the official logo master (2026-11-23).** The Owner confirmed in writing in the documentation session; no signed record exists. The confirmation applies to the file identified by the Drive file ID and SHA-256 above. |

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
- Responsive layouts from 320 px upward. **Dark-only theme for the MVP [APPROVED OI-48].** Light-theme compatibility is preserved through semantic tokens; a light theme requires an approved logo variant (DEP-08).
- Components cover the full client journey (01 §3) with consistent states: loading, empty, error, success, and "payment processing."

## 11. Accessibility and performance **[APPROVED OI-12, OI-23]**

- **[PROPOSED]** Target WCAG 2.2 AA. Lighthouse Accessibility ≥ 95 **[APPROVED OI-23]**.
- Keyboard operability, visible focus, form error association, and sufficient contrast with the final brand palette (re-verified at OI-38).
- **[APPROVED OI-23]** Accessible, restrained motion. All non-essential animation is disabled under `prefers-reduced-motion`.
- Performance budgets are in 02 §7.

## 12. Brand approval dependencies **[APPROVED OI-38; final approval DEP-08]**

Before production, the Owner must:
- ~~confirm the official logo file (§10.1)~~: confirmed 2026-11-23
- supply or approve logo variants
- approve the color palette, typography and font licensing, email template branding, favicon, and social preview imagery

**Final visual design requires Owner approval before production.** Until then, implementation uses the confirmed logo (§10.1) with provisional, clearly labeled design tokens. Confirming the logo does **not** approve the final palette, typography, or visual design.

## 13. Acceptance tests **[PROPOSED]**

| ID | Test |
|---|---|
| T-NOT-01 | A state change and its outbox row commit atomically. If one rolls back, so does the other. |
| T-NOT-02 | **[R2]** Enqueuing the same idempotency key twice produces one send |
| T-NOT-03 | **[R2]** A provider failure retries on schedule, then marks the row dead and raises a queue item |
| T-NOT-04 | **[R2]** Non-production environments cannot deliver to non-allow-listed addresses |
| T-NOT-05 | No marketing or automated sequence templates exist in the MVP catalog |
| T-PRV-01 | Retention jobs delete failed uploads after 7 days and skip records under legal hold |
| T-PRV-02 | Account closure does not call any Stripe cancellation API |
| T-PRV-03 | Exports contain only the requesting user's authorized projects |
| T-PRV-04 | Logs and error reports contain no OTPs, tokens, or full card data |
| T-DES-01 | Swapping the brand token and asset configuration changes the UI with no component code changes |
| T-DES-02 | Automated a11y scans report no critical violations on all journey pages |
| T-DES-03 | With reduced motion enabled, non-essential animations are disabled |
| T-DES-04 | Logo renders at its original aspect ratio (597:335) at every breakpoint, with no CSS distortion (OI-38) |
| T-NOT-06 | **[R2]** Every event in §4 for OI-25, OI-26, OI-31, OI-35, and OI-37 has a template and is enqueued by its trigger |
| T-PRV-05 | Subscription cancellation triggers no deletion of agreements, financial records, or audit logs (OI-40) |
| T-PRV-06 | Unused assets are deleted 90 days after `project.closed`. Used assets are kept until 12 months after closure. Legal holds block both. (OI-42) |
| T-PRV-07 | Deletion evidence contains metadata only. No deleted content is recoverable from audit records. |
