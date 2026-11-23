# 06 — Publishing and Post-Launch

| Field | Value |
|---|---|
| Version | 0.3.0 |
| Status | **Draft — pending owner sign-off** |
| Decisions | OI-03, OI-05, OI-18, OI-19, OI-22–OI-27, OI-32, OI-33, OI-35, OI-37, OI-41, OI-44–OI-46 |
| Open issues | None |
| Dependencies | DEP-03, DEP-06, DEP-09 |

## 1. Scope

This document covers publishing a **client website**. Client websites are separate deployment targets from the portal (02 §2). The portal records and controls publication. It does not host client sites. **[APPROVED OI-22]**

## 2. Publication eligibility gates **[APPROVED OI-22]**

Gates are evaluated **on the server** by a single gate evaluator, at authorization time **and** again immediately before deployment starts **[PROPOSED]**. Every gate must pass. Evaluating a gate reads authoritative records only.

| # | Gate | Passes when | Source |
|---|---|---|---|
| G1 | Valid agreement | Agreement state `effective` for the current order summary; no `reacceptance_required` | 04 §1 |
| G2 | Verified deposit | Deposit `verified` (webhook-derived ledger entry) and not fully refunded | 04 §11–§12 |
| G3 | Current-version client approval | A client approval exists for the **current** released preview, and that release is the artifact being published | 05 §6–§7 |
| G4 | Verified final balance (no unresolved contractual balance) | Balance `verified` via webhook, **or** `settled_by_adjustment`: verified payments + Owner-authorized discounts, credits, or waivers = owed **[APPROVED OI-27, OI-44]**. The gate output always discloses an adjustment. | 04 §10, §12 |
| G5 | QA passed | A recorded, release-specific QA result for this release ID (§6), all blocking items passed **[APPROVED OI-33]** | §6 |
| G6 | Domain readiness | The domain readiness check for this project passed within the freshness window | §5 |
| G7 | Security checks passed | A recorded security result for this release ID, no critical failures **[APPROVED OI-33]** | §7 |
| G8 | Holds cleared | No active publication-blocking hold: `maintenance_payment_hold`, `dispute_risk_hold`, `owner_manual_hold` **[APPROVED OI-26, OI-37]**, and `approval_nonresponsive_hold` **[OI-45; inclusion in G8 PROPOSED]** | 04 §14 |

Rules:
- **[APPROVED OI-19]** No override can mark G1–G8 as passed. There is no "force publish."
- **[APPROVED OI-19]** Results for G2–G4 cannot be fabricated. G5 and G7 are evidence records produced by the checks; they are not toggles.
- **[APPROVED OI-33]** The only permitted exception is a **documented, Owner-approved performance exception** within G5: performance items that miss the OI-23 thresholds. It must reference the release ID, the measured values, and a reason. **Security, payment and settlement, and explicit client approval can never be bypassed.**
- QA evidence (G5) and Owner publication authorization (§3) are separate records. Passing QA does not authorize publication, and authorization cannot be recorded without a passing QA result.
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

**Client hosting model [APPROVED OI-32]:**

| Requirement | Specification |
|---|---|
| Platform | **Agency-managed Vercel hosting** |
| Isolation | An **independent Vercel deployment (project) per client website**, with separate environment configuration and release history. **[PROPOSED]** Client projects live in a Vercel team separate from the portal's. |
| Domains | Per-client domain configuration on that client's project |
| Rollback | Supported per client project (§8.2) |
| Operational isolation | No shared environment variables, secrets, or build caches across clients **[PROPOSED]** |
| Ownership | The agency is **not** assumed to own the client's domain or intellectual property. Ownership, cancellation, and transfer follow the final agreement (draft §5, §8; DEP-03) and §8.4. |
| Scale | Project creation and configuration are automatable and idempotent (**[PROPOSED]** a provisioning record per client site), built only under Phase 4 authorization |

- **[PROPOSED]** Deployment credentials for client sites are held server-side, scoped to the minimum needed, and never exposed to clients or Admins.
- **[VERIFY-PROVIDER OI-39]** Check Vercel team, project, and domain limits, plan costs at scale, and rollback semantics (DEP-06).

## 5. Domain readiness **[APPROVED OI-22; checks PROPOSED]**

Checks:
- DNS records point to the intended target.
- TLS certificate issued and valid.
- `www`/apex redirect policy configured.
- The domain registrant record is in the client's name where feasible (draft agreement §5).
- Third-party domain charges are disclosed and approved.

Results are recorded with timestamps. **[PROPOSED]** Freshness window: 24 hours.

## 6. Release-specific QA **[APPROVED OI-22, OI-33]**

QA is recorded **against the exact release ID**. The approved mandatory coverage areas are:

| Area | Blocking? |
|---|---|
| Functional behavior and **lead forms** | Yes. Failed essential functionality blocks. |
| Responsive design | Yes |
| Branding and content accuracy | Yes |
| Performance (OI-23 Lighthouse and Core Web Vitals thresholds) | Yes, unless a documented Owner-approved performance exception exists (§2) |
| Accessibility | Yes |
| Security (§7) | Yes. Critical failures cannot be bypassed. |
| Domain and operational readiness (§5) | Yes |
| Monitoring and rollback readiness (uptime check configured; previous release available for rollback) | Yes |

Also blocking, through other gates: missing client approval (G3) and unresolved contractual balances (G4).

**[PROPOSED]** detailed checklist items (versioned; the Owner may amend them):
- All pages from the order scope are present.
- Forms deliver to the client's contact.
- No broken links.
- Mobile, tablet, and desktop layouts checked.
- Lighthouse and Core Web Vitals thresholds for the client site use the OI-23 values **[APPROVED OI-33]**.
- Accessibility automated scan: no critical violations.
- Content proofread against intake.
- Favicon and metadata present.
- Analytics and SEO basics present per package.
- Approved assets only (no quarantined or rejected assets).

The result records the checklist version, release ID, staff actor, item results, and evidence links.

## 7. Security gate **[APPROVED OI-22, OI-33]**

Critical security failures always block publication. No exception exists.

**[PROPOSED]** starting checklist:
- HTTPS enforced, with HSTS.
- Security headers present.
- No exposed secrets in the built output.
- Dependency vulnerability scan: no high or critical issues without a recorded exception.
- Form endpoints have spam and abuse protection.
- No debug endpoints.
- Admin and CMS surfaces (if any) protected.

## 8. Publication execution, rollback, incidents, and live-site continuity

### 8.1 Execution **[PROPOSED]**
1. Re-evaluate the gates. Abort if any fails.
2. Record `deployment.started` with the release ID and target.
3. Deploy the approved artifact. The job is idempotent, keyed by authorization ID.
4. Record the deployment ID, `deployment.succeeded` or `deployment.failed`.
5. Run live verification (§9).

### 8.2 Rollback **[APPROVED OI-22, OI-32; detail PROPOSED]**
- Owner-initiated, with reauthentication.
- Target is the previous `live_verified` release for that project.
- Records the reason and the incident reference.
- A rollback never deletes release or approval history.
- Rolling back to a release that has never been live requires the full gate process.

### 8.3 Incidents **[APPROVED OI-22]**
- Severity classification (**[PROPOSED]** SEV1 site down or security issue; SEV2 major functionality broken; SEV3 minor).
- The Owner is notified for SEV1/SEV2.
- An incident record is kept with timeline and resolution.
- The client is notified when the client-facing impact warrants it.

### 8.4 Live-site continuity and decommissioning

| Situation | Effect on an already-published website |
|---|---|
| `maintenance_payment_hold`, including during Owner review | **None.** The site stays online. New publication and nonessential maintenance are paused. **[APPROVED OI-26, OI-46]** |
| Stripe subscription cancelled with no authorized termination | **None.** An Owner exception review is created and no transition starts. **[APPROVED OI-46]** |
| Open dispute or `dispute_risk_hold` | **None.** No takedown merely because a dispute exists. **[APPROVED OI-37]** |
| `approval_nonresponsive_hold` | **None.** Already-published websites are unaffected. **[APPROVED OI-45]** |
| Confirmed client cancellation, or Owner-authorized termination effective, with the transition deadline not yet reached | Site stays online. Transition assistance continues. **[APPROVED OI-35, OI-46]** |
| Transition deadline passed (04 §15.1) | The agency **may** discontinue managed hosting and remove the site, subject to the final agreement and applicable law (DEP-03). |

Decommissioning **[PROPOSED]**:
- An Owner-authorized action with reauthentication and an audit event.
- It checks that the transition deadline has passed and that no legal hold applies.
- It requires a confirmed client cancellation or an Owner-authorized termination record. A failed payment or a Stripe cancellation webhook **alone never qualifies**. **[APPROVED OI-46]**
- It confirms that the transfer materials were provided.
- It **never** changes or cancels a client-owned domain registration.
- Records are retained per 07 §6.

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
| T-PUB-11 | A performance exception is accepted only from the Owner, with a release ID and reason. No exception mechanism exists for security, payment, or approval items. (OI-33) |
| T-PUB-12 | QA results attach to one release ID. A new release requires new QA evidence. |
| T-PUB-13 | No billing hold, dispute, or approval hold triggers any undeploy or domain change on a live site (OI-26, OI-37) |
| T-PUB-14 | Decommissioning is rejected before the transition deadline, under a legal hold, or by anyone but the Owner (OI-35) |
| T-PUB-15 | Each client site deploys to its own project. Environment variables of one client project are not readable from another. (OI-32) |
| T-PUB-16 | Decommissioning is rejected when the only basis is a payment failure or a Stripe cancellation event (OI-46) |
| T-PUB-17 | While an approval hold is active, publication is blocked by G8, and the gate output identifies it as a fulfillment hold, not a billing hold (OI-45) |
| T-INQ-01 | Inquiry options appear only after `live_verified` |
| T-INQ-02 | Submitting an inquiry creates a queue entry and notifications and creates no Stripe objects (asserted with a Stripe mock showing no calls) |
| T-INQ-03 | Client A cannot submit or view inquiries for project B |
