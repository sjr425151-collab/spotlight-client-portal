# 07 — Notifications, Privacy, and Design

| Field | Value |
|---|---|
| Version | 0.1.0 |
| Status | **Draft — pending owner sign-off** |
| Decisions | OI-04, OI-12, OI-21, OI-23 |
| Open issues | OI-38, OI-39, OI-40 |

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
| Approval reminder (OI-25) | Client | Resend |
| Approval stalled | Owner | Resend |
| Preview approved | Staff | Resend |
| Final payment due | Client | Resend |
| Final payment receipt | Client | Stripe |
| Final payment verified | Client, Staff | Resend |
| Maintenance payment failed | Client, Owner | Stripe and/or Resend (OI-26) |
| Billing hold placed / cleared | Owner | Resend |
| Upload rejected (malware/type) | Client, Staff | Resend |
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

## 6. Provisional retention schedule **[APPROVED OI-21 — provisional pending OI-40]**

| Data | Retention |
|---|---|
| Active profiles and projects | Duration of the active relationship |
| Project assets | Active project + 12 months |
| Unused uploads | 90 days after closure (definition **[PENDING OI-40]**) |
| Abandoned intake | 90 days |
| Agreements and acceptance evidence | 7 years after termination |
| Transaction records (ledger, webhook events) | 7 years |
| Security logs | 12 months |
| Administrative audit logs | 3 years |
| Failed uploads | 7 days |
| Backups | Rolling 30 days, subject to provider capabilities |

- **[APPROVED OI-21]** Account closure does **not** automatically cancel Stripe billing or delete legally required records.
- **[PROPOSED]** Retention jobs are idempotent, respect legal holds, and write audit events summarizing what was deleted (counts and IDs, not content).

## 7. Data subject request handling **[APPROVED OI-21]**

| Request | Procedure **[PROPOSED]** |
|---|---|
| Export | Client requests in the portal. Identity confirmed by an active session plus OTP. Admin prepares a machine-readable export (profile, intake, assets list, agreements, payment history). Delivered through a time-limited private link. |
| Correction | Client edits where permitted. Otherwise an Admin edit with an audit event. |
| Deletion | Client requests. The Owner reviews against retention obligations and legal holds. Deletable data is deleted. Legally required records (agreements, transactions) are retained and their restriction is noted. Stripe billing is handled separately (§6). |

SLAs and legal applicability are **[DEFERRED OI-40]**.

## 8. Vendor inventory **[APPROVED OI-21]**

| Vendor | Purpose | Data categories | Status |
|---|---|---|---|
| Vercel | Portal hosting | Request logs, application traffic | Approved (OI-10) |
| Supabase | Auth, database, storage | All portal data | Approved (OI-08, 09) |
| Stripe | Payments | Billing identity, payment data | Approved (OI-14, 17) |
| Resend | Transactional email | Email address, notification content | Approved (OI-04) |
| GitHub | Source and CI | Code, no client data **[PROPOSED rule]** | Approved (OI-10) |
| Malware scanner | Upload screening | Uploaded files | **[PENDING OI-31]** |
| Monitoring / error tracking | Observability | Error context, which must be scrubbed of personal data | To be selected (02 §8) |
| Client site hosting | Client websites | Approved site content | **[PENDING OI-32]** |

DPAs and subprocessor terms must be reviewed before production **[DEFERRED OI-40]**.

## 9. Incident response **[APPROVED OI-21]**

**[PROPOSED]** phases: detect → triage (severity, 06 §8) → contain (revoke sessions, rotate keys, disable affected features) → assess personal-data impact → notify (Owner; affected clients and regulators as legally required **[DEFERRED OI-40]**) → recover → post-incident review recorded.

---

## Part C — Design system

## 10. Premium design system requirements **[APPROVED OI-12]**

- Centralized design tokens (color, typography, spacing, radius, elevation, motion) are the single source for the portal UI and the email templates **[PROPOSED]**.
- Brand assets (logos, imagery, fonts) are replaceable through configuration, without code changes to components **[APPROVED OI-12]**.
- Responsive layouts from 320 px upward. Light theme required. Dark theme optional **[PROPOSED]**.
- Components cover the full client journey (01 §3) with consistent states: loading, empty, error, success, and "payment processing."

## 11. Accessibility and performance **[APPROVED OI-12, OI-23]**

- **[PROPOSED]** Target WCAG 2.2 AA. Lighthouse Accessibility ≥ 95 **[APPROVED OI-23]**.
- Keyboard operability, visible focus, form error association, and sufficient contrast with the final brand palette (re-verified at OI-38).
- **[APPROVED OI-23]** Accessible, restrained motion. All non-essential animation is disabled under `prefers-reduced-motion`.
- Performance budgets are in 02 §7.

## 12. Brand approval dependencies **[DEFERRED OI-38]**

Before production, the Owner must approve: logo variants, color palette, typography and font licensing, email template branding, favicon, and social preview imagery. Implementation uses placeholder tokens until then.

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
