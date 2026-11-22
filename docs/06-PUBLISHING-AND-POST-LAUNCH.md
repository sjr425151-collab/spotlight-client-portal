# 06 — Publishing and Post-Launch

| Field | Value |
|---|---|
| Version | 0.1.0 |
| Status | **Draft — pending owner sign-off** |
| Decisions | OI-03, OI-05, OI-18, OI-19, OI-22, OI-24 |
| Open issues | OI-26, OI-27, OI-32, OI-33, OI-41 |

## 1. Scope

This document covers publishing a **client website**. Client websites are separate deployment targets from the portal (02 §2). The portal records and controls publication. It does not host client sites. **[APPROVED OI-22]**

## 2. Publication eligibility gates **[APPROVED OI-22]**

Gates are evaluated **on the server** by a single gate evaluator, at authorization time **and** again immediately before deployment starts **[PROPOSED]**. Every gate must pass. Evaluating a gate reads authoritative records only.

| # | Gate | Passes when | Source |
|---|---|---|---|
| G1 | Valid agreement | Agreement state `effective` for the current order summary; no `reacceptance_required` | 04 §1 |
| G2 | Verified deposit | Deposit `verified` (webhook-derived ledger entry) and not fully refunded | 04 §11–§12 |
| G3 | Current-version client approval | A client approval exists for the **current** released preview, and that release is the artifact being published | 05 §6–§7 |
| G4 | Verified final balance | Balance `verified` via webhook, **or** a balance adjustment under **[PENDING OI-27]** such that paid + adjusted = owed. The gate output always discloses an adjustment. | 04 §12 |
| G5 | QA passed | A recorded QA checklist result for this release ID, checklist version current, all mandatory items passed | §6, **[PENDING OI-33]** |
| G6 | Domain readiness | The domain readiness check for this project passed within the freshness window | §5 |
| G7 | Security checks passed | A recorded security check result for this release ID, all mandatory items passed | §7, **[PENDING OI-33]** |
| G8 | Billing holds cleared | No active hold of a publication-blocking type | 04 §14, **[PENDING OI-26]** |

Rules:
- **[APPROVED OI-19]** No override can mark G1–G8 as passed. There is no "force publish."
- **[APPROVED OI-19]** Results for G2–G4 cannot be fabricated. G5 and G7 are evidence records produced by the checks; they are not toggles.
- **[PROPOSED]** The evaluator returns a structured result (each gate, pass/fail, evidence IDs). The result is stored with the authorization record.

## 3. Owner authorization **[APPROVED OI-22, OI-03]**

| Element | Specification |
|---|---|
| Actor | Owner only |
| Preconditions | All gates pass. Fresh high-risk reauthentication (03 §7). |
| Inputs | Release ID, confirmation |
| Records | `publication_authorizations` (release ID, gate result snapshot, owner ID, timestamp) — insert-only |
| Concurrency | One active authorization per project. A new release or a gate change invalidates the pending authorization. |
| Failure | Any gate fails → authorization rejected, with the failing gates listed |
| Audit | `publication.authorized`, `publication.authorization_rejected` |

## 4. Release artifact identity and deployment isolation **[APPROVED OI-22]**

- The published artifact is the **same** immutable release the client approved. **[PROPOSED]** It is identified by release number, commit SHA, and build artifact or deployment ID. Rebuilding from a different SHA is a new release that requires new approval.
- Every client website deploys to an **isolated** target. There are no shared runtime, credentials, or data with the portal or with other clients.
- The hosting platform and account model are **[PENDING OI-32]**.
- **[PROPOSED]** Deployment credentials for client sites are held server-side, scoped per target, and never exposed to clients or Admins.

## 5. Domain readiness **[APPROVED OI-22; checks PROPOSED]**

Checks:
- DNS records point to the intended target.
- TLS certificate issued and valid.
- `www`/apex redirect policy configured.
- The domain registrant record is in the client's name where feasible (draft agreement §5).
- Third-party domain charges are disclosed and approved.

Results are recorded with timestamps. **[PROPOSED]** Freshness window: 24 hours.

## 6. Internal QA **[APPROVED OI-22; criteria PENDING OI-33]**

**[PROPOSED]** starting checklist (versioned):
- All pages from the order scope are present.
- Forms deliver to the client's contact.
- No broken links.
- Mobile, tablet, and desktop layouts checked.
- Lighthouse thresholds for the client site (adopt the OI-23 targets as goals **[PROPOSED]**).
- Accessibility automated scan: no critical violations.
- Content proofread against intake.
- Favicon and metadata present.
- Analytics and SEO basics present per package.
- Approved assets only (no quarantined or rejected assets).

The result records the checklist version, release ID, staff actor, item results, and evidence links.

## 7. Security gate **[APPROVED OI-22; criteria PENDING OI-33]**

**[PROPOSED]** starting checklist:
- HTTPS enforced, with HSTS.
- Security headers present.
- No exposed secrets in the built output.
- Dependency vulnerability scan: no high or critical issues without a recorded exception.
- Form endpoints have spam and abuse protection.
- No debug endpoints.
- Admin and CMS surfaces (if any) protected.

## 8. Publication execution, rollback, and incidents

**Execution** **[PROPOSED]**:
1. Re-evaluate the gates. Abort if any fails.
2. Record `deployment.started` with the release ID and target.
3. Deploy the approved artifact. The job is idempotent, keyed by authorization ID.
4. Record the deployment ID, `deployment.succeeded` or `deployment.failed`.
5. Run live verification (§9).

**Rollback** **[APPROVED OI-22; detail PROPOSED]**:
- Owner-initiated, with reauthentication.
- Target is the previous `live_verified` release for that project.
- Records the reason and the incident reference.
- A rollback never deletes release or approval history.
- Rolling back to a release that has never been live requires the full gate process.

**Incidents** **[APPROVED OI-22]**:
- Severity classification (**[PROPOSED]** SEV1 site down or security issue; SEV2 major functionality broken; SEV3 minor).
- The Owner is notified for SEV1/SEV2.
- An incident record is kept with timeline and resolution.
- The client is notified when the client-facing impact warrants it.

## 9. Live verification **[APPROVED OI-22]**

**[PROPOSED]** checks after deployment:
- HTTP 200 on the configured domain(s).
- Valid TLS.
- The served build identifier matches the release ID (for example, a build meta tag or header).
- Key pages respond.
- Forms reachable.

On success → `live_verified`. On failure → `failed`, which creates an Owner queue item and incident record, and blocks the confirmation notification.

## 10. Publication confirmation

After `live_verified`, the client receives a confirmation notification and in-portal confirmation screen (07 §4). **[APPROVED OI-24]** The confirmation screen is never blocked by service offers.

## 11. Optional marketing service inquiries **[APPROVED OI-24]**

| Element | Specification |
|---|---|
| Availability | Only after publication `live_verified` |
| Services | Client Acquisition; Social Presence & Brand Management |
| Actor | Authenticated client with membership |
| Inputs | Selected service(s), optional message, preferred contact method |
| Records | `service_inquiries` (project, user, services, message, timestamp) |
| Effects | An Admin queue entry and a transactional notification to staff, plus an acknowledgment to the client |
| Prohibited effects | No Stripe customer, price, subscription, or payment. No service activation. No advertising spend authorization. |
| Idempotency | Duplicate submission within a short window returns the existing inquiry **[PROPOSED]** |
| Audit | `inquiry.submitted` |

## 12. Acceptance tests **[PROPOSED]**

| ID | Test |
|---|---|
| T-PUB-01 | With each gate G1–G8 individually failing (all others passing), authorization and deployment are both rejected |
| T-PUB-02 | Admin cannot authorize publication. A client cannot trigger it. |
| T-PUB-03 | Owner authorization without fresh reauthentication is rejected |
| T-PUB-04 | No API or parameter exists that skips gate evaluation ("force"), verified by code search and negative tests |
| T-PUB-05 | Releasing a new preview after authorization invalidates the pending authorization |
| T-PUB-06 | The deployed artifact's identifier equals the approved release ID. A mismatch fails verification. |
| T-PUB-07 | Gates are re-evaluated immediately before deployment. A hold placed after authorization blocks deployment. |
| T-PUB-08 | Live verification failure prevents the confirmation notification and creates an incident |
| T-PUB-09 | Rollback requires the Owner and reauthentication, targets the last verified release, and preserves history |
| T-PUB-10 | A deployment job retried with the same authorization ID does not deploy twice |
| T-INQ-01 | Inquiry options appear only after `live_verified` |
| T-INQ-02 | Submitting an inquiry creates a queue entry and notifications and creates no Stripe objects (asserted with a Stripe mock showing no calls) |
| T-INQ-03 | Client A cannot submit or view inquiries for project B |
