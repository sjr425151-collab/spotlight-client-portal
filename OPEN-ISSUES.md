# Open Issues Register

| Field | Value |
|---|---|
| Version | 0.1.0 (draft for owner review) |
| Status | Draft |
| Next unused ID | **OI-42** |
| Decision record | [docs/08-DECISIONS-AND-CHANGELOG.md](docs/08-DECISIONS-AND-CHANGELOG.md) |

Rules:
- IDs are never reused.
- An issue closes only by a recorded owner decision. The decision is then transcribed into the decision register.
- Recommendations below are **proposals only**. None of them has been adopted.

---

## Part 1 — Original issues (decided at the architectural level)

All 24 original issues are decided at the architectural level, per the owner-provided baseline. The authoritative text is in [08 §3](docs/08-DECISIONS-AND-CHANGELOG.md#3-decision-register). Sub-items still open are cross-referenced here.

| ID | Title | Status | Open sub-items |
|---|---|---|---|
| OI-01 | Specification governance | Decided | — |
| OI-02 | Development sequence | Decided | — |
| OI-03 | Roles | Decided | — |
| OI-04 | Notifications | Decided | OI-38 |
| OI-05 | Project states | Decided | — |
| OI-06 | README and documentation governance | Decided | — |
| OI-07 | Portal URL | Decided | OI-41 |
| OI-08 | Authentication | Decided | — |
| OI-09 | Tenancy | Decided | — |
| OI-10 | Hosting and delivery | Decided with deferrals | OI-39, OI-41 |
| OI-11 | Toolchain | Decided | — |
| OI-12 | Design system | Decided with deferrals | OI-38 |
| OI-13 | Agreement | Decided with deferrals | OI-28, OI-34 |
| OI-14 | Stripe catalog | Decided with deferrals | OI-30, OI-39 |
| OI-15 | Payment calculations | Decided | OI-36 |
| OI-16 | Maintenance subscription | Decided with deferrals | OI-34, OI-35 |
| OI-17 | Stripe payment workflow | Decided with deferrals | OI-26, OI-29, OI-35, OI-36, OI-37 |
| OI-18 | Preview approval | Decided with deferrals | OI-25 |
| OI-19 | Administrative overrides | Decided with deferrals | OI-27 |
| OI-20 | Uploads | Decided with deferrals | OI-31 |
| OI-21 | Privacy and retention | Decided with deferrals | OI-39, OI-40 |
| OI-22 | Publication | Decided with deferrals | OI-32, OI-33 |
| OI-23 | Performance | Decided | — |
| OI-24 | Optional post-publication inquiries | Decided | — |

---

## Part 2 — Unresolved issues

**Earliest phase affected** is the first OI-02 phase whose *specification or implementation* cannot be completed until the issue is resolved. **Blocks** shows whether the issue blocks implementation authorization for that phase or only production launch.

| ID | Title | Earliest phase | Blocks | Status |
|---|---|---|---|---|
| OI-25 | Nonresponsive client preview approval | 4 | Phase 4 implementation | Open |
| OI-26 | Subscription billing holds | 3 | Phase 3 implementation | Open |
| OI-27 | Contractual balance adjustments and waivers | 3 | Phase 3 implementation | Open |
| OI-28 | Signer authority wording | 3 | Phase 3 implementation (wording); production (legal) | Open |
| OI-29 | Stripe Customer Portal MVP inclusion | 3 | Phase 3 implementation | Open |
| OI-30 | Test-mode Price ID mapping | 3 | Phase 3 implementation | Open |
| OI-31 | Malware scanning approach | 4 | Phase 4 implementation | Open |
| OI-32 | Client website hosting/account model | 4 | Phase 4 implementation | Open |
| OI-33 | QA and security gate criteria | 4 | Phase 4 implementation | Open |
| OI-34 | Agreement finalization | 3 | Production launch | Open — deferred |
| OI-35 | Cancellation and refund policies | 3 | Production launch | Open — deferred |
| OI-36 | Tax treatment | 3 | Production launch | Open — deferred |
| OI-37 | Dispute handling | 3 | Production launch | Open — deferred |
| OI-38 | Brand approval | 1 | Production launch | Open — deferred |
| OI-39 | Provider capability verification | 1 | Varies by item; production for live items | Open |
| OI-40 | Privacy and retention legal review | 4 | Production launch | Open — deferred |
| OI-41 | Production infrastructure and DNS | 5 | Production launch | Open — deferred |

---

### OI-25 — Nonresponsive client preview approval

- **Description:** OI-18 forbids treating silence as approval. The owner-authored draft agreement (v1.0, §3) gives the client five business days to identify material deviations and says failure to give feedback does not waive their rights. No procedure exists for a client who never approves.
- **Options:**
  - A. Reminder cadence only. The project stays blocked indefinitely.
  - B. Reminder cadence, then an Owner escalation queue entry, then an Owner-initiated outreach record. The project stays blocked until explicit approval.
  - C. A contractual "deemed acceptance" clause. This conflicts with OI-18 unless OI-18 is revised, and it is not recommended.
- **Recommendation:** **B.** Approval is never inferred. After N reminders (proposed: day 3, day 7, day 14 after release), an `approval_stalled` queue entry is created for the Owner. Any commercial consequence, such as pausing development, is handled under the agreement, not by system inference.
- **Impacted documents:** 05 §7, 07 §4, 04 (draft agreement §3 language).
- **Owner decision required:** Choice of option, reminder schedule, and whether the agreement needs wording changes (legal).
- **Status:** Open.

### OI-26 — Subscription billing holds

- **Description:** OI-17 and OI-22 require billing holds, but no hold types, triggers, or effects are defined. The draft agreement §12 allows suspension seven calendar days after written notice of an overdue amount.
- **Options:**
  - A. Hold only on an unpaid development balance.
  - B. Typed holds: `subscription_past_due`, `subscription_canceled_unpaid`, `dispute_open`, `refund_pending_review`, `owner_manual_hold`. Each has a defined trigger, effect (blocks publication / blocks intake / informational), and clearing condition.
  - C. As B, plus an automated suspension of hosting after the §12 notice period.
- **Recommendation:** **B for the MVP.** Holds are derived from webhook-recorded state. `owner_manual_hold` can only *add* a hold, never clear a system hold. Automated hosting suspension (C) waits until OI-32 and OI-35 are resolved.
- **Impacted documents:** 04 §14, 05 §9, 06 §2.
- **Owner decision required:** Hold types, whether `subscription_past_due` blocks publication, and the notice record procedure.
- **Status:** Open.

### OI-27 — Contractual balance adjustments and waivers

- **Description:**
  - OI-19 forbids fabricated payment and any "mark as paid" override. It allows genuine contractual adjustments that are separately authorized, documented, and in the ledger.
  - The draft agreement §3 says the balance is due before publication "unless otherwise agreed in writing."
  - The mechanism for a legitimate adjustment (discount, write-off, alternative arrangement) is undefined.
- **Options:**
  - A. No adjustments in the MVP. The full balance must be paid by Stripe.
  - B. An Owner-only `balance_adjustment` ledger entry. It requires a reason, a reference to a written amendment, high-risk reauthentication, and an immutable audit event. The final-balance gate is satisfied when *paid + adjusted = owed*. The gate output always shows that an adjustment contributed.
  - C. Re-issue the order summary at the new price, with client re-acceptance.
- **Recommendation:** **B, combined with C for material scope or price changes.** Never mark a payment as received when it was not.
- **Impacted documents:** 03 §12, 04 §12, 06 §2.
- **Owner decision required:** Options, limits, and agreement wording (legal).
- **Status:** Open.

### OI-28 — Signer authority wording

- **Description:** OI-13 requires signer authority evidence. The draft agreement identifies the Client as "the individual or business identified during checkout" and has no authority representation.
- **Options:**
  - A. A separate required, unchecked checkbox: "I am authorized to enter into this Agreement on behalf of [Business Legal Name]."
  - B. The authority statement embedded in the main acceptance checkbox.
  - C. Capture the signer's title as well as the representation.
- **Recommendation:** **A + C.** Record the signer's full name, title, business legal name, and the authority representation in the acceptance evidence.
- **Impacted documents:** 04 §2–§3.
- **Owner decision required:** Wording (legal), and whether title is required.
- **Status:** Open.

### OI-29 — Stripe Customer Portal MVP inclusion

- **Description:** The draft agreement §7 refers to cancellation "through the designated billing portal." It is undecided whether the Stripe-hosted Customer Portal (payment method update, invoices, cancellation) is in the MVP.
- **Options:**
  - A. Include it with a restricted configuration: payment method update and invoice history only. Cancellation is by written request.
  - B. Include it with self-service cancellation at period end.
  - C. Exclude it. All billing changes go through the Owner.
- **Recommendation:** **A** for Phase 3 test mode. Decide B or C together with OI-35.
- **Impacted documents:** 04 §9, 07 §4.
- **Owner decision required:** Yes.
- **Status:** Open.

### OI-30 — Test-mode Price ID mapping

- **Description:** Only live Price IDs are documented (04 §5). Phase 3 must run in Stripe test mode, so equivalent test-mode prices must exist and be mapped. OI-14 forbids creating *duplicate live* prices and inline pricing.
- **Options:**
  - A. The Owner creates matching test-mode products and prices in the Stripe test environment (an Owner action, separately authorized) and supplies the IDs.
  - B. The Owner uses Stripe's copy-to-test-mode or sandbox tooling, if available [VERIFY-PROVIDER].
- **Recommendation:** **A or B**, performed by the Owner outside this change set. IDs are recorded in 04 §6 with amounts verified to match.
- **Impacted documents:** 04 §6, 02 §4.
- **Owner decision required:** Authorize and perform test-mode catalog setup.
- **Status:** Open.

### OI-31 — Malware scanning approach

- **Description:** OI-20 requires malware screening and quarantine. Supabase Storage has no native malware scanning [VERIFY-PROVIDER].
- **Options:**
  - A. A third-party scanning API (file sent to the vendor).
  - B. A self-hosted ClamAV worker (container or serverless).
  - C. A cloud-provider object scanning service with a storage relay.
- **Recommendation:** Owner chooses after a vendor review covering data processing terms, file size support (250 MB video), latency, and cost. Until then, uploads stay in quarantine and are not usable.
- **Impacted documents:** 05 §5, 07 §8.
- **Owner decision required:** Yes.
- **Status:** Open.

### OI-32 — Client website hosting/account model

- **Description:** OI-22 requires isolated client website deployments but no platform or account ownership model. The draft agreement says the Provider supplies hosting (§4) and registers domains in the client's name when feasible (§5).
- **Options:**
  - A. One Vercel project per client site, in a dedicated Spotlight "client-sites" team separate from the portal's team.
  - B. A separate hosting account per client, owned by the client, with delegated access.
  - C. Another hosting provider.
- **Recommendation:** **A** for operational simplicity, with transfer procedures supporting agreement §8. Owner and legal confirmation needed.
- **Impacted documents:** 02 §2, 06 §4–§9.
- **Owner decision required:** Yes.
- **Status:** Open.

### OI-33 — QA and security gate criteria

- **Description:** OI-22 requires "QA passed" and "security checks passed" gates with no defined criteria.
- **Options:** Define versioned checklists (proposed in 06 §6–§7). Results are recorded as evidence, never toggled.
- **Recommendation:** Adopt 06 §6–§7 as the starting checklist versions, subject to owner edits.
- **Impacted documents:** 06 §6–§7.
- **Owner decision required:** Approve the checklist contents.
- **Status:** Open.

### OI-34 — Agreement finalization

- **Description:** Final legal language is pending (OI-13). A v1.0 draft exists outside the repository, as an editable document with no hash and no recorded legal review. It also lacks tax, dispute/chargeback, and privacy-policy references.
- **Options:** Legal review, then a frozen, versioned, hashed artifact.
- **Recommendation:** After legal approval, commit the final text as a versioned artifact with a SHA-256 hash recorded in the agreement-versions record (04 §2). A test-mode draft may be used in Phase 3 with a visible "DRAFT — not for production" marker.
- **Impacted documents:** 04 §1–§4.
- **Owner decision required:** Yes (legal).
- **Status:** Open — deferred to production.

### OI-35 — Cancellation and refund policies

- **Description:** Commercial cancellation, refund, and third-party-charge terms are pending (OI-16, OI-17). Draft agreement §7 contains proposed terms that are not final.
- **Recommendation:** Finalize with legal. The ledger supports refund entries regardless of policy (04 §12).
- **Impacted documents:** 04 §9, §12.
- **Owner decision required:** Yes.
- **Status:** Open — deferred to production.

### OI-36 — Tax treatment

- **Description:** Sales tax applicability to website development and maintenance services, and whether to use Stripe Tax, are undecided. The draft agreement does not address tax.
- **Recommendation:** Get tax advice. The ledger reserves separate tax entries (OI-15). Phase 3 test mode runs without tax collection.
- **Impacted documents:** 04 §7, §12.
- **Owner decision required:** Yes (tax advisor).
- **Status:** Open — deferred to production.

### OI-37 — Dispute handling

- **Description:** Chargeback and dispute response procedures, evidence packaging, and the effect on service are undefined.
- **Recommendation:** Record disputes in the ledger, raise `dispute_open` holds (OI-26), and define an Owner response runbook before production.
- **Impacted documents:** 04 §11–§12, §14, 07 §9.
- **Owner decision required:** Yes.
- **Status:** Open — deferred to production.

### OI-38 — Brand approval

- **Description:** Final logos, colors, typography, and email branding require owner approval (OI-12).
- **Recommendation:** Build with placeholder tokens and assets. Brand approval is a production blocker, not an implementation blocker.
- **Impacted documents:** 07 §10–§12.
- **Owner decision required:** Yes.
- **Status:** Open — deferred to production.

### OI-39 — Provider capability verification

- **Description:** Several requirements depend on provider behavior and plan limits that have not been verified. Each item is marked **[VERIFY-PROVIDER]** in the specs. They include:
  - Supabase: Auth OTP configuration and custom SMTP, MFA (AAL2) enforcement, backup/PITR retention versus the 30-day target, Storage resumable uploads and per-object size limits.
  - Vercel: plan support for protected previews, rollback, and separate environments.
  - Resend: verified-domain and environment isolation.
  - Stripe: one-time prices in subscription-mode Checkout, webhook event set.
  - Live Price ID amounts versus 04 §5.
- **Recommendation:** Verify each item during the phase that first depends on it. Record the results in the relevant spec.
- **Impacted documents:** 02, 03, 04, 05, 07.
- **Owner decision required:** Plan and tier selection, where costs are involved.
- **Status:** Open.

### OI-40 — Privacy and retention legal review

- **Description:** The retention defaults are provisional (OI-21). There is no privacy policy or portal terms of use. Category overlaps need definitions, for example "project assets: active + 12 months" versus "unused uploads: 90 days after closure."
- **Recommendation:** Legal review. Define "unused upload" as an asset never referenced by a released preview. Consider aligning audit records of financial actions with the 7-year transaction retention.
- **Impacted documents:** 07 §5–§7.
- **Owner decision required:** Yes (legal).
- **Status:** Open — deferred to production.

### OI-41 — Production infrastructure and DNS

- **Description:** DNS for `portal.spotlight-marketing.co` must be configured alongside the GoHighLevel-hosted apex domain. Production Supabase, Vercel, Resend, and Stripe live configuration are not yet established.
- **Recommendation:** Prepare a production readiness runbook in Phase 5. Add a CNAME for the `portal` subdomain only. The apex and GoHighLevel records remain unchanged.
- **Impacted documents:** 02 §4, §8.
- **Owner decision required:** Yes (production launch authorization).
- **Status:** Open — deferred to production.
