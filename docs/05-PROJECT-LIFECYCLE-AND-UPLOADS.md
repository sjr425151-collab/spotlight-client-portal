# 05 — Project Lifecycle and Uploads

| Field | Value |
|---|---|
| Version | 0.3.2 |
| Status | **Draft — pending owner sign-off.** v0.3.2: final approval authorizes the automatic final payment (Owner instruction, 2026-11-23; OI-17 revised). |
| Decisions | OI-05, OI-09, OI-18, OI-20, OI-25, OI-26, OI-31, OI-39, OI-42, OI-43, OI-45, OI-46 |
| Open issues | None |
| Dependencies | DEP-06, DEP-07 |

## 1. Principle **[APPROVED OI-05]**

Each lifecycle dimension has its **own** state, derived from authoritative records. There is **no** single editable "project status" field. Any displayed summary status is computed, and it is never used to decide payment or publication eligibility.

## 2. Independent state machines

| Dimension | States | Authoritative source |
|---|---|---|
| Agreement | `not_presented → presented → accepted_pending_payment → effective` (+ `superseded`, `reacceptance_required`, `expired`) | Acceptance and order summary records (04 §1) |
| Deposit | `not_started → pending → verified` (+ `failed`, `refunded`, `disputed`) | Webhook-derived ledger (04 §11–§12) |
| Intake | `locked → open → submitted → accepted_by_staff` (+ `changes_requested`) | Intake records |
| Development | `not_started → in_progress → ready_for_preview` (+ `paused`) | Staff-recorded milestones (informational, never a gate) |
| Preview approval | Per release: `released → approved` / `superseded` / `withdrawn` | Preview release and approval records (§6–§7) |
| Final balance | `not_due → due → pending → verified` (+ `failed`, `refunded`, `disputed`, `settled_by_adjustment` **[APPROVED OI-27]**, meaning paid + Owner-authorized adjustments = owed, never a fabricated payment). **[APPROVED OI-17, revised 2026-11-23]** `due` on the client's final approval (§7); `pending` once the automatic charge is attempted; `failed` → `pending` when the client completes payment on the Stripe-hosted page for the same invoice (04 §10). | Webhook-derived ledger |
| Holds | Zero or more active holds (billing and fulfillment holds are distinct types) | Hold records (04 §14) **[APPROVED OI-25, OI-26, OI-37, OI-45]** |
| Service termination | `none → under_owner_review → termination_authorized → effective → maintenance_ceased → offboarded / transferred` (+ `withdrawn`). Independent of the Stripe subscription status. | Owner-authorized termination records (04 §9.1.1) **[APPROVED OI-46]** |
| Publication | `not_eligible → eligible → authorized → deploying → live_unverified → live_verified` (+ `failed`, `rolled_back`) | Gate evaluation and deployment records (06) |

```mermaid
stateDiagram-v2
  direction LR
  state Deposit {
    [*] --> not_started
    not_started --> pending: Checkout created
    pending --> verified: verified webhook
    pending --> failed: payment failed / expired
    failed --> pending: new Checkout
    verified --> refunded: refund webhook
    verified --> disputed: dispute webhook
  }
```

Transition rules:
- **[APPROVED OI-05, OI-17]** The deposit and final balance states change **only** through webhook processing (04 §11).
- **[PROPOSED]** Development milestones can be set by staff, but they do not satisfy any gate.

## 3. Intake requirements

| Element | Specification |
|---|---|
| Actors | Client (primary), Admin (audited corrections) |
| Preconditions | Deposit `verified` **[APPROVED baseline journey step 6]** |
| Inputs | Business legal and display name, contact info (phone, email, address), service areas, services offered, logo(s), photos, brand guidelines (optional), website preferences (style references, color preferences, pages wanted), domain information (existing domain / needs domain) |
| Records | `intake_submissions` (versioned drafts; the submitted version is immutable) |
| States | `open → submitted → accepted_by_staff` or `changes_requested → submitted` |
| Autosave | Drafts are saved server-side **[PROPOSED]** |
| Failure states | Validation errors per field; upload errors (§5) |
| Audit | `intake.submitted`, `intake.changes_requested`, `intake.accepted`, `intake.edited_by_staff` |
| Retention | Abandoned intake: 90 days (07 §6) |

The exact field list and required/optional flags are **[PROPOSED]** above, for owner refinement.

## 4. Project asset uploads **[APPROVED OI-20]**

- Storage is private Supabase Storage, isolated per project by path prefix and policy (03 §8–§9).
- Uploads are authorized on the server. **[PROPOSED]** The server issues a short-lived, single-object upload URL scoped to the project path, only after checking type, size, and quota.
- **Versioning:** a replaced asset creates a new version. Prior versions are retained per 07 §6.
- **Usage tracking [APPROVED OI-42]:** used and unused assets must be clearly distinguished. **[PROPOSED]** Each asset version carries a `used` flag. The flag is set irreversibly when the version is incorporated into any released preview or final deliverable, derived from that release's asset manifest. Assets never incorporated are **unused**, and follow the 90-day post-closure retention rule (07 §6).
- **No automatic publication.** An asset reaches a client website only through a staff-built preview release and the publication gates (06).
- Upload and access history are audited.

## 5. File limits, validation, and quarantine **[APPROVED OI-20]**

### 5.1 Quotas

| Limit | Value |
|---|---|
| Files per project | 100 |
| Storage per project | 2 GB |
| Exceptions | Admin-approved, within authorization rules, audited |

### 5.2 Per-file limits

| Category | Types | Max size |
|---|---|---|
| Logos | PNG, JPG, WEBP, SVG | 15 MB |
| Photos | JPG, PNG, WEBP, HEIC | 25 MB |
| Brand guidelines | PDF | 25 MB |
| Business documents | PDF, DOCX | 20 MB |
| Video | MP4, MOV | 250 MB |
| Other | Any | Admin approval required |

### 5.3 Pipeline

```mermaid
stateDiagram-v2
  [*] --> uploading
  uploading --> failed_upload: incomplete / error
  uploading --> quarantined: upload complete
  quarantined --> rejected: type/size/content check fails
  quarantined --> scanning
  scanning --> rejected: malware detected
  scanning --> processing: clean
  processing --> available: derivatives created
  processing --> rejected: processing fails safely
  failed_upload --> [*]: purge after 7 days
```

Rules:
1. **[APPROVED]** Validate actual content, not just extension or declared MIME type. **[PROPOSED]** Check magic bytes; reject mismatches and polyglots.
2. **[APPROVED OI-31]** Every upload stays in quarantine until malware scanning finishes. A **failed scan blocks both access and fulfillment**: the asset becomes `rejected` and cannot be downloaded, previewed, or used in a release. A failed scan produces an audit record and an **actionable notification** to the client (re-upload guidance) and to staff (07 §4). The scanning **vendor is selected after provider and cost verification** (DEP-07). Until a vendor is in place, nothing leaves `quarantined` in any environment that handles real client data.
3. **[APPROVED]** SVG must be sanitized. **[PROPOSED]** Strip scripts, event handlers, external references, and `foreignObject`. Keep the original in quarantine storage, and serve only the sanitized output.
4. **[APPROVED]** HEIC must be handled. **[PROPOSED]** Convert to JPEG/WEBP derivatives and keep the original.
5. **[APPROVED]** Safe image/video processing. **[PROPOSED]** Run in an isolated worker with dimension and pixel limits (decompression-bomb protection), and strip EXIF location metadata from derivatives.
6. **[APPROVED]** Resumable large uploads must be addressed. **[VERIFY-PROVIDER OI-39]** Check Supabase Storage resumable (TUS) support and object size limits against the 250 MB video limit.
7. Quota is checked at upload-URL issuance and again at completion **[PROPOSED]**. Concurrent uploads must not exceed quota (a transactional reservation).

## 6. Preview release versioning **[APPROVED OI-18]**

- A **preview release** is an immutable, uniquely identified artifact released to the client. **[PROPOSED]** It is identified by a sequential release number per project, the source commit SHA, the deployment ID, and the preview URL.
- **Internal drafts** (unreleased builds) are not visible to the client, and they do not affect existing approvals.
- Releasing a new preview marks earlier releases `superseded` for approval purposes. Their records and approvals are preserved.
- Release records are insert-only. Only `withdrawn` (with a reason) may be applied after release.

## 7. Client approval workflow **[APPROVED OI-18, OI-03]**

| Element | Specification |
|---|---|
| Actors | Client with active membership on the project |
| Preconditions | A release in `released` state is the project's current release |
| Inputs | Explicit approval action on that release ID, plus an optional comment. The action is labeled **Approve Website & Authorize Final Payment** **[APPROVED OI-17, revised 2026-11-23]**. |
| Payment authorization **[APPROVED OI-17, revised 2026-11-23]** | The approval also authorizes automatic collection of the previously disclosed outstanding balance (04 §3.1, §10). **[PROPOSED]** The approval screen shows that amount from the order summary snapshot before the client confirms. Approving an already-approved release, or approving after the balance is pending, verified, or settled, never starts a second charge. |
| Records | `preview_approvals` (release ID, user ID, timestamp, IP/UA **[PROPOSED]**) — insert-only. The final-balance charge record references the approval ID (04 §10). |
| Gate rule | The approval gate passes only if an approval exists **for the current released release ID** |
| Silence | **Never** treated as approval. No timer converts silence into approval. **[APPROVED OI-18, OI-25]** |
| Nonresponsive client | §7.1 **[APPROVED OI-25]** |
| Permissions | Owner/Admin cannot approve on a client's behalf |
| Concurrency | Approving a release that was superseded between page load and submission is rejected with a reload prompt |
| Idempotency | A repeat approval of the same release by the same user returns the existing record |
| Audit | `preview.released`, `preview.approved`, `preview.superseded`, `preview.withdrawn` |

The owner-authored draft agreement §3 gives the client five business days to identify material deviations. **[PROPOSED]** The portal shows this as an informational review window only. It does not change the explicit-approval rule.

### 7.1 Nonresponsive client escalation **[APPROVED OI-25]**

Days are calendar days in America/Detroit, counted from the local release date of the **current** released preview. Day *N* is the release date + *N* (02 §13). **[APPROVED OI-43]** Releasing a new preview restarts the schedule.

| Day | Action | Actor | Audit event |
|---|---|---|---|
| 0 | Preview released. The client is asked to give explicit approval or request revisions. | System / staff | `preview.released` |
| 3 | First reminder to the client | System (outbox) | `approval.reminder_1_sent` |
| 7 | Second reminder to the client, plus an Admin notification | System (outbox) | `approval.reminder_2_sent`, `approval.admin_notified` |
| 14 | Personal follow-up escalation. Staff record the outreach (channel, date, summary). | Staff | `approval.personal_followup_recorded` |
| 21+ | An `approval_nonresponsive_hold` **may** be applied, but only after documented outreach exists (§7.2) | Owner or Admin **[APPROVED OI-45]** | `approval_hold.placed` |

Rules **[APPROVED OI-25]**:
- Silence never constitutes approval.
- The hold does **not** cancel the subscription, waive any balance, or satisfy any publication requirement.
- A client response (approval or revision request) stops the schedule.
- Every step is auditable.

### 7.2 Day-21 approval hold **[APPROVED OI-45]**

`approval_nonresponsive_hold` is a **fulfillment** hold. It is a separate type from every billing hold, and it never represents an approved preview.

| Aspect | Rule |
|---|---|
| Preconditions | Day ≥ 21 for the current release, and documented outreach exists, including the day-14 personal follow-up record |
| Apply | Owner or Admin, with a reason |
| Pauses | Active development work and nonessential fulfillment activity. **[PROPOSED]** Publication is also blocked through G8 while the hold is active (06 §2). |
| Preserved | Client portal access; preview access; the client's ability to approve or to request revisions; the explicit-approval gate G3 |
| Never | Cancels the maintenance subscription; waives balances; affects already-published websites; treats silence as approval |
| Client response | An approval or revision request from an authorized client on the current release is recorded normally. An approval made during the hold is a valid G3 approval. Either response creates an `approval_hold_review` queue item for administrative review. |
| Qualifying client response | An explicit approval or revision request on the current release by an authorized client **[PROPOSED definition]** |
| Clear | Owner at any time, with a reason. Admin only after a qualifying client response. |
| Resumption | A recorded resumption decision, for example: resume development, proceed to final payment, or remain held |
| Audit | `approval_hold.placed` (actor, authorization, reason, outreach evidence IDs, timestamp); `approval_hold.client_response`; `approval_hold.cleared`; `approval_hold.resumption_decided` |
| Display | **[PROPOSED]** Labeled "Paused: awaiting your preview response". It is never shown as a billing status or as approved. |

## 8. Revision handling **[PROPOSED]**

- The client may submit revision requests against a release. Each request is linked to the release ID, with structured comments.
- Staff classify each request as in-scope or out-of-scope. Out-of-scope work requires a new order summary and re-acceptance (04 §4) before it is performed under a price change.
- A revision cycle ends with a new released preview, which requires a new approval.

## 9. Derived administrative queues **[APPROVED OI-05]**

Queues are **computed** from authoritative state. They are never maintained by hand. **[PROPOSED]** set:

| Queue | Derivation |
|---|---|
| Awaiting acceptance | Order summary `presented`, no acceptance |
| Awaiting deposit | Acceptance exists, deposit not `verified` |
| Intake pending | Deposit `verified`, intake not `submitted` |
| Intake review | Intake `submitted` |
| In development | Intake accepted, no current release |
| Awaiting client approval | Current release with no approval |
| Approval follow-up due | Current release unapproved at day 14 with no recorded personal follow-up (OI-25) |
| Approval hold eligible | Current release unapproved at day 21+ with documented outreach (OI-25) |
| Payment recovery | Failed maintenance renewal within the 7-day recovery period (OI-26) |
| Cancellation milestones | Effective cancellations with M1 (12 business days) or M2 (60 calendar days) approaching or passed, or required notices due (OI-35) |
| Domain expiries | Spotlight-registered domains approaching the end of their initial one-year term **[PROPOSED]** |
| Disputes | Open disputes, ordered by evidence due date (OI-37) |
| Approval hold review | A client responded while `approval_nonresponsive_hold` is active (OI-45) |
| Billing hold Owner review | `maintenance_payment_hold` is active and no Owner decision is recorded (OI-46) |
| Stripe cancellation exceptions | A Stripe subscription was deleted without an authorized termination (OI-46) |
| Retention due | Unused assets 90 days after closure; used assets 12 months after closure (OI-42) |
| Awaiting final payment | Approval current, balance not `verified` |
| Ready for publication review | All gates pass except Owner authorization |
| Blocked by hold | Any active blocking hold |
| Publication verification failed | Publication `failed` or verification failed |
| Upload review | Assets `quarantined` beyond the SLA or `rejected`; type-exception requests |
| Reconciliation mismatches | 04 §13 |
| Service inquiries | 06 §11 |

## 10. Client notification triggers

The event catalog is in [07 §4](07-NOTIFICATIONS-PRIVACY-AND-DESIGN.md#4-event-catalog-proposed). Lifecycle triggers: deposit verified, intake changes requested, preview released, approval reminders, final payment action required (failed charge or authentication needed), final payment verified, publication live.

## 11. Acceptance tests **[PROPOSED]**

| ID | Test |
|---|---|
| T-LC-01 | Intake routes and actions are denied until the deposit is `verified` |
| T-LC-02 | No API exists to set deposit or balance state directly. Only the webhook handler changes them. |
| T-LC-03 | Derived queues match the state for seeded fixture projects in every combination |
| T-LC-04 | A submitted intake version is immutable. Staff edits create audited new versions. |
| T-LC-05 | A client can approve only the current released preview of their own project |
| T-LC-06 | After release *n+1*, the approval gate fails until *n+1* is approved. The approval for *n* is still stored. |
| T-LC-07 | An unreleased internal draft does not supersede the current approval |
| T-LC-08 | No scheduled job or timer creates an approval |
| T-LC-09 | Staff cannot create an approval record |
| T-LC-14 | The approval action is labeled "Approve Website & Authorize Final Payment". Approving the current release starts exactly one final-balance charge (04 T-PAY-13). Approving a superseded release starts none. |
| T-UP-01 | Each category rejects files over its size limit and disallowed types |
| T-UP-02 | Renamed executables, extension/MIME mismatches, and polyglots are rejected |
| T-UP-03 | Malicious SVG (script, `onload`, external `href`) is sanitized. The sanitized output contains no active content. |
| T-UP-04 | The 101st file and uploads beyond 2 GB are rejected, including under concurrent uploads |
| T-UP-05 | Assets in `quarantined` or `scanning` cannot be downloaded by clients or used in releases |
| T-UP-06 | Cross-tenant: client A cannot upload into, list, or download from project B paths |
| T-UP-07 | Failed uploads are purged after 7 days |
| T-UP-08 | Uploading an asset never changes any preview or live site |
| T-UP-09 | A failed scan makes the asset `rejected`, blocks its download and release use, and sends client and staff notifications (OI-31) |
| T-LC-10 | Reminders are sent on days 3 and 7, the Admin notification on day 7, and the follow-up queue entry appears on day 14. A new release restarts the schedule. (OI-25) |
| T-LC-11 | The approval hold cannot be placed without a recorded personal follow-up. Placing it never creates an approval or alters billing. |
| T-LC-12 | During an approval hold, the client can view the preview, approve it, or request revisions. The approval satisfies G3, and a review queue item is created. (OI-45) |
| T-LC-13 | An approval hold does not change portal access, subscription status, balances, or any published site |
| T-UP-10 | Incorporating an asset into a released preview sets `used`. The flag never reverts. Assets that were never incorporated are reported as unused. (OI-42) |
