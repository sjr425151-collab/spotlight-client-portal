# 06 — Publishing and Post-Launch

| Field | Value |
|---|---|
| Version | 0.5.5 |
| Status | **Approved** (Owner, 2026-11-23, consolidated execution plan approval). v0.5.0: R1 staff-assisted publication against a server-issued authorization (OI-22 revised by OI-68); R2 automation tags. Earlier: v0.4.1 publication after the automatic final payment and recovery without recharging (OI-17 revised). v0.5.1 (**OI-79 item 5**, Owner decision 2026-11-24): every failed high or critical security finding blocks G7; no override or exception mechanism (§2, §7). v0.5.2 (documentation reconciliation, 2026-11-24): G7 clarification (failed medium and low findings do not fail G7, Owner-confirmed); B1 financial-integrity note for G2 and G4. v0.5.3 (PWP-0, AUTH-011; Owner direction 2026-11-25): §5 and §8.5 record Owner-reported post-launch commercial direction (CD-10, CD-12, CD-13, CD-22 to CD-24; INT-02) pending individual reconciliation and counsel-approved wording (OI-108, OI-110). No gate, check or implemented behavior changes. v0.5.4 (2026-11-25, Main, PR #32 review reconciliation): the Decisions header lists OI-108 and OI-110. No rule changed. v0.5.5 (**OI-114**, AUTH-015, Owner 2026-11-26 and 2026-11-27; D1 to D4 and D6): §8.1 controlled recovery after a failed deployment or a failed live verification. |
| Decisions | OI-03, OI-05, OI-18, OI-19, OI-22–OI-27, OI-32, OI-33, OI-35, OI-37, OI-41, OI-44–OI-46, OI-68, OI-108, OI-110, OI-114 |
| Open issues | None |
| Dependencies | DEP-03, DEP-06, DEP-09 |

**Release placement [APPROVED OI-68]:** everything in this document is **[R1]** unless tagged **[R2]**. R2 items: portal-driven deployment (§8.1), email confirmation (§10), and service inquiries (§11).

## 1. Scope

This document covers publishing a **client website**. Client websites are separate deployment targets from the portal (02 §2). The portal records and controls publication. It does not host client sites. **[APPROVED OI-22]**

## 2. Publication eligibility gates **[APPROVED OI-22]**

Gates are evaluated **on the server** by a single gate evaluator, at authorization time **and** again immediately before deployment starts **[PROPOSED]**. In R1, "before deployment starts" is the staff **Start deployment** action in the portal (§8.1), which must succeed before staff deploy. Every gate must pass. Evaluating a gate reads authoritative records only.

| # | Gate | Passes when | Source |
|---|---|---|---|
| G1 | Valid agreement | Agreement state `effective` for the current order summary; no `reacceptance_required` | 04 §1 |
| G2 | Verified deposit | Deposit `verified` (webhook-derived ledger entry) and not fully refunded | 04 §11–§12 |
| G3 | Current-version client approval | A client approval exists for the **current** released preview, and that release is the artifact being published | 05 §6–§7 |
| G4 | Verified final balance (no unresolved contractual balance) | Balance `verified` via webhook (the automatic final-balance charge or its Stripe-hosted completion, 04 §10), **or** `settled_by_adjustment`: verified payments + Owner-authorized discounts, credits, or waivers = owed **[APPROVED OI-27, OI-44]**. The gate output always discloses an adjustment. | 04 §10, §12 |
| G5 | QA passed | A recorded, release-specific QA result for this release ID (§6), all blocking items passed **[APPROVED OI-33]** | §6 |
| G6 | Domain readiness | The domain readiness check for this project passed within the freshness window | §5 |
| G7 | Security checks passed | A recorded security result for this release ID with **no failed high or critical finding**; no override or exception **[APPROVED OI-33; OI-79 item 5]**. Failed medium and low findings are recorded and visible but do not fail G7 (Owner-confirmed, 2026-11-24); no other gate changes | §7 |
| G8 | Holds cleared | No active publication-blocking hold: `maintenance_payment_hold`, `dispute_risk_hold`, `owner_manual_hold` **[APPROVED OI-26, OI-37]**, and `approval_nonresponsive_hold` **[OI-45; inclusion in G8 PROPOSED]** | 04 §14 |

**G2 and G4 financial integrity (B1, Owner direction 2026-11-24):** WP-B's financial interface reports G2 or G4 as failed while any unresolved financial-integrity anomaly concerns that charge, and both when the charge cannot be determined (04 §15.2.1). An Owner review never re-establishes payment by itself.

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
| Execution **[R1, OI-68]** | The Owner or an Admin carries out the authorized deployment (§8.1). Executing a deployment never substitutes for, or creates, an authorization. |
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
| Scale | Project creation and configuration are automatable and idempotent (**[PROPOSED]** a provisioning record per client site), built only under an active authorization that covers it (R2 deployment orchestration) |

- **[PROPOSED]** Deployment credentials for client sites are held server-side, scoped to the minimum needed, and never exposed to clients or Admins.
- **[VERIFY-PROVIDER OI-39]** Check Vercel team, project, and domain limits, plan costs at scale, and rollback semantics (DEP-06).

## 5. Domain readiness **[APPROVED OI-22; checks PROPOSED]**

Checks:
- DNS records point to the intended target.
- TLS certificate issued and valid.
- `www`/apex redirect policy configured.
- The domain registrant record is in the client's name where feasible (draft agreement §5).
- Where Spotlight registered the domain: the actual registration date and the registrar-reported expiry are recorded. The initial term is one year from actual registration (04 §15.1). Domain registration is tracked separately from hosting.
- Third-party domain charges are disclosed and approved. **[Owner-reported direction, CD-12; OI-110; pending reconciliation]** An eligible standard domain carries a $25 annual expense allowance; amounts beyond it, and non-standard domains, follow the counsel-approved terms. Not implemented and not represented as a contractual commitment until approved and published.

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
- Dependency vulnerability scan: no high or critical issues. **No exception mechanism (OI-79 item 5 supersedes the earlier "without a recorded exception").**
- Form endpoints have spam and abuse protection.
- No debug endpoints.
- Admin and CMS surfaces (if any) protected.

## 8. Publication execution, rollback, incidents, and live-site continuity

### 8.1 Execution **[PROPOSED]**

**[R1, OI-68] Staff-assisted publication.** The portal controls the authorization and records every step; staff perform the deployment.
1. **Start deployment** (Owner or Admin, in the portal): re-evaluates the gates against the active authorization. Abort if any gate fails or the authorization is no longer valid. Records `deployment.started` with the authorization ID, release ID, commit SHA, and the client's isolated target. Idempotent per authorization ID.
2. Staff deploy **exactly** the release's commit SHA to the client's isolated Vercel project (§4), using the agency's deployment access. Deploying any other commit, or without a started deployment, is prohibited.
3. **Record deployment** (Owner or Admin): the Vercel deployment ID and production URL. Records `deployment.succeeded` or `deployment.failed`.
4. Live verification (§9) runs from the portal. It confirms that the served build identifier equals the authorized release. A mismatch fails verification and opens an incident.
5. The rollback reference (the previous `live_verified` release and its deployment ID) is recorded with the deployment.

**[R2]** The portal performs steps 2 and 3 itself through scoped server-side deployment credentials:
1. Re-evaluate the gates. Abort if any fails.
2. Record `deployment.started` with the release ID and target.
3. Deploy the approved artifact. The job is idempotent, keyed by authorization ID.
4. Record the deployment ID, `deployment.succeeded` or `deployment.failed`.
5. Run live verification (§9).

**Publication failure after successful payment [APPROVED OI-17, revised 2026-11-23]:** if deployment or live verification fails after the final balance is `verified`, the balance **keeps its paid status**. The publication is flagged for recovery (state `failed`, an Owner queue item, and an incident record, §9). Recovery re-runs the gates and the deployment with no new charge: publication never creates, retries, or re-attempts a Stripe payment.

**Controlled recovery [APPROVED OI-114] [R1]** (AUTH-015; D1 to D4):
1. **No silent re-authorization (D1).** While the project's latest deployment is of a release and has not been recovered, authorizing that release again is refused (`recovery_required`) and audited. No new authorization is issued. This holds whatever that deployment's outcome (started, failed or succeeded), and whether its authorization is still active or a gate failure has closed it.
2. **Owner-only recovery (D2).** The Owner, with fresh reauthentication and a reason, may recover only the **latest** deployment of the **current** release, and only when that deployment failed or its latest live verification failed. Recovery is refused, and audited (`publication.recovery_rejected`), for a deployment that is in progress, unverified, or superseded by a later deployment or release. It is also refused when the deployment's authorization was closed other than by a gate failure. A deployment whose authorization a gate failure closed can still be recovered. A repeated recovery returns the existing one.
3. **Two steps (D3).** Recovery only closes that deployment's authorization (`failed_publication_recovery`; an authorization a gate failure closed keeps that closure) and records `publication.recovery_opened` with the reason, the failure and the open incident references. It issues no authorization, deployment, verification, notification or charge. The normal authorization (§3) and deployment flow then re-run every gate G1 to G8, including G2 and G4, against the same release identity. A new deployment needs its own live verification (§9); an earlier verification is never reused.
4. **No redeploy of a verified release (D4).** A release whose latest live verification passed can be neither recovered nor re-authorized.
5. **No late verification.** Once a deployment has been recovered, a live verification of that deployment is refused (`deployment_closed`) and records nothing. The deployment row lock orders a concurrent recovery and verification.

Nothing redeploys automatically. Recovery does not resolve open incidents (§8.3).

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

### 8.4 Live-site continuity, discontinuation, and deactivation

| Situation | Effect on an already-published website |
|---|---|
| `maintenance_payment_hold`, including during Owner review | **None.** The site stays online. New publication and nonessential maintenance are paused. **[APPROVED OI-26, OI-46]** |
| Stripe subscription cancelled with no authorized termination | **None.** An Owner exception review is created and no transition starts. **[APPROVED OI-46]** |
| Open dispute or `dispute_risk_hold` | **None.** No takedown merely because a dispute exists. **[APPROVED OI-37]** |
| `approval_nonresponsive_hold` | **None.** Already-published websites are unaffected. **[APPROVED OI-45]** |
| Effective cancellation (confirmed client cancellation or Owner-authorized termination), before M1 | Site stays online. Maintenance and transition assistance continue. **[APPROVED OI-35, OI-46]** |
| Between M1 (12 business days) and M2 (60 calendar days) | Maintenance and designated recurring infrastructure **may** be discontinued. The site is not deliberately taken offline, but **continued functionality is not guaranteed**. No intentional degradation. **[APPROVED OI-35, revised]** |
| After M2, once the required notices are recorded | The agency **may** deactivate the remaining agency-managed services, which may make the site unavailable, subject to the final agreement and applicable law (DEP-03). The domain registration is unaffected. |

Discontinuation (M1) and deactivation (M2) actions **[PROPOSED]**:
- Each is an Owner-authorized action with reauthentication and an audit event.
- Maintenance and designated-infrastructure discontinuation checks that M1 has passed. Deactivating the remaining services checks that M2 has passed **and** that the required notices are recorded. Both check that no legal hold applies.
- It requires a confirmed client cancellation or an Owner-authorized termination record. A failed payment or a Stripe cancellation webhook **alone never qualifies**. **[APPROVED OI-46]**
- Deactivation confirms that the transfer materials were provided.
- Neither action ever changes, cancels, or transfers a client-owned domain registration.
- Neither action ever applies intentional degradation.
- Records are retained per 07 §6.

### 8.5 Post-launch commercial direction **[Owner-reported, 2026-11-25; OI-108, OI-110; pending individual reconciliation and counsel-approved wording]**

The items below are preserved as approved commercial direction. Each needs reconciliation against recoverable source evidence or a later explicit Owner decision (08, CD cross-reference). None is implemented, and none is represented as a contractual commitment or as technically verified.

| Item | Direction | Status |
|---|---|---|
| Launch stabilization (CD-10) | A 30-day launch stabilization period after publication | Needs source wording; terms in the maintenance or governing instrument once approved |
| Domain (CD-12, CD-23) | Eligible standard domain with a $25 annual expense allowance; client domain ownership preserved; no automatic cancellation, transfer or lapse (04 §15.1, unchanged) | Allowance needs source; ownership rules recoverable (OI-32, OI-35) |
| Hosting resources (CD-13, INT-02) | Provisional: 5 GB website asset storage; 100 GB monthly transfer; 2,000 monthly form submissions; usage measured by the supported provider's documented methodology | Provisional pending TV-03 (OPEN-ISSUES DEP-06 detail) |
| Maintenance operating frequencies (CD-22) | Provisional: five-minute availability monitoring; daily recoverable backups; a 30-day backup retention target; weekly vulnerability checks; monthly website health, technical SEO and routine maintenance reviews | Provisional pending TV-03; never an unconditional service level (OI-108) |
| Intellectual property (CD-23) | A hybrid intellectual property model | Needs source wording (DEP-03) |
| Export and migration (CD-24) | One eligible standard website export; migration services separately priced | Transfer materials recoverable (04 §15.1); export terms need source |

## 9. Live verification **[APPROVED OI-22]**

**[PROPOSED]** checks after deployment:
- HTTP 200 on the configured domain(s).
- Valid TLS.
- The served build identifier matches the release ID (for example, a build meta tag or header).
- Key pages respond.
- Forms reachable.

On success → `live_verified`. On failure → `failed`, which creates an Owner queue item and incident record, and blocks the confirmation notification.

## 10. Publication confirmation

After `live_verified`, the client sees the in-portal confirmation screen **[R1]** and receives a confirmation notification **[R2]** (07 §4). **[APPROVED OI-24]** The confirmation screen is never blocked by service offers.

## 11. Optional marketing service inquiries **[APPROVED OI-24] [R2]**

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
| T-PUB-14 | Maintenance discontinuation is rejected before M1. Deactivating remaining services is rejected before M2, without recorded notices, under a legal hold, or by anyone but the Owner. (OI-35) |
| T-PUB-15 | Each client site deploys to its own project. Environment variables of one client project are not readable from another. (OI-32) |
| T-PUB-16 | Discontinuation and deactivation are rejected when the only basis is a payment failure or a Stripe cancellation event (OI-46) |
| T-PUB-17 | While an approval hold is active, publication is blocked by G8, and the gate output identifies it as a fulfillment hold, not a billing hold (OI-45) |
| T-PUB-18 | A deployment failure after a verified final payment leaves the balance `verified`, flags the publication for recovery, and creates no Stripe invoice or charge on recovery (asserted with a Stripe mock) |
| T-PUB-19 | **[R1]** Start deployment is rejected without a valid authorization or when any gate fails at that moment. Recording a deployment whose served build identifier differs from the authorized release fails live verification and opens an incident. A client cannot start or record a deployment, and an Admin cannot create an authorization. |
| T-PUB-20 | **[OI-79]** A recorded security result with any failed high or critical finding fails G7; no function or role can record an exception or override |
| T-INQ-01 | **[R2]** Inquiry options appear only after `live_verified` |
| T-INQ-02 | **[R2]** Submitting an inquiry creates a queue entry and notifications and creates no Stripe objects (asserted with a Stripe mock showing no calls) |
| T-INQ-03 | **[R2]** Client A cannot submit or view inquiries for project B |
