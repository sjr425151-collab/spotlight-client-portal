# Owner Runbooks

| Field | Value |
|---|---|
| Version | 0.5.0 |
| Status | **[PROPOSED]** Operational procedures recorded from the WP-C and WP-B reviews (2026-11-24), for Owner review. They describe how existing, approved controls are used; they create no new permission, override, or payment path. Legal and contractual effects stay with counsel (DEP-03). |
| Related | [CURRENT-STATE.md](CURRENT-STATE.md), 04, 05, 06 |

Every procedure below is an Owner action recorded in the audit log. None marks a payment received, forces publication, or approves on a client's behalf (CLAUDE.md §3).

## 1. Revoked asset already on a published client site (05 §5.5; review item 11)

A malicious verdict revokes the file in the portal and blocks future publication of any release that includes it (G5). The live client site is outside the portal's control.
1. Read the `upload.access_revoked` alert and identify the affected releases and live deployments from the dispute evidence and deployment records.
2. Decide, as a Tier 3 production action, whether to roll back to the previous verified deployment (06 §8) or publish a corrected release through the normal gates.
3. Notify the client through the recorded outreach channel; record the decision and its reason.

## 2. Deletion of a revoked object that has `failed` (05 §5.5 rule 8; item 15)

The object is unreadable by every user but still stored.
1. Retry from the staff project page while retries remain (Owner, `aal2`).
2. After the retries are exhausted, remove the object manually in the storage provider as a Tier 4 destructive action with recorded verification, then record the outcome against the deletion row.

## 3. Signer replacement or lost account access (04 §8.1 F4; item 19)

1. Verify the requester's identity and authority out of band, and record how.
2. Record the revocation as the Owner (fresh MFA, reason) if automatic collection must stop.
3. The client business's new authorized signer accepts the current agreement version.
4. The client completes setup-mode recovery; a new authorization is established only from that newer acceptance and a verified card (F5).

## 4. Rejected `release.approved` consumption (04 §10; item 22)

A consumption rejected because a precondition failed at that moment (for example, the deposit or the agreement was not satisfied) is permanent for that event, and no final-balance invoice exists. Resolve the cause, then have staff release a new preview and the client approve it; the new approval event is consumed normally.

## 5. Reconciliation before publication (R1, until DEP-17; 04 §15.2.1 rule 9; item 27)

Immediately before authorizing a publication, run the project's reconciliation and confirm the evaluator still reports G2 and G4 as passing. Mandatory for R1 release-candidate acceptance (N1).

## 6. Known limitations (item 29)

- **Several projects of one client business:** an unrecorded refund on one project can appear in a sibling project's reconciliation and block it (fail closed, same tenant). Resolve by attributing it after review.
- **Clock mixing:** observation ordering mixes Stripe event times and local detection times; in practice conservative, because reconciliation items block until reviewed.
- **Reported but unrealized reversal:** a reversal Stripe reports as in effect blocks its gate until a later Stripe observation ends it (refund failed or canceled, dispute won). Confirm with Stripe before any action.

## 7. Direct role and membership writes (OI-90; required before R1 release-candidate acceptance)

**Use the authorized functions** wherever possible: `create_invitation`, `accept_invitation`, `revoke_invitation`, `set_staff_role`, and the membership revocation function. They authorize, audit, and serialize every role and membership change.

**An authorized direct operator write** to `public.staff_roles` or `public.project_memberships` (database owner, a Tier 3 action in production) must, in one transaction:

1. take the per-user lock first, before touching any affected row: `select pg_advisory_xact_lock(hashtextextended('wps-role-membership:' || <user_id>::text, 0));`
2. then perform the insert or update;
3. commit.

**Limitations.** The OI-85 triggers refuse a Sales role together with an active membership for every writer, but they do not protect against a database owner who disables or replaces them, and an operator `UPDATE` that skips step 1 can deadlock with a concurrent invitation acceptance or role change for the same user.

**Retry.** A deadlock (SQLSTATE `40P01`) aborts one transaction and leaves nothing behind. Re-read the user's current role and memberships, then retry the whole transaction from step 1. A refusal with SQLSTATE `42501` from the OI-85 triggers means the change would break the separation; do not retry, resolve the conflict through the authorized functions instead.

## 8. Approved release withdrawn or superseded after final-balance initiation (OI-92(e))

Before any final-balance dispatch runs, check the audit log for `preview.withdrawn` on projects with a pending final-balance obligation. If the approved release was withdrawn or superseded after the obligation was created: the obligation stands (no void, refund, or cancellation); contact the client, record the outcome in the project's communications log, and follow counsel's guidance (DEP-03). Existing authorization, revocation, and card safeguards apply unchanged.

## 9. Conflicting reversal attribution (OI-93)

A refund or dispute whose authoritative relationships point to more than one project is quarantined (`attribution_conflict`), and every candidate project's G2 and G4 stay blocked. Before reviewing it: reconcile the provider evidence in Stripe (refund or dispute, charge, payment intent, invoice), establish the actual financial impact per project, and keep the supporting evidence. Then record the review with `resolve_quarantined_event` (fresh MFA, a reason citing the evidence). In R1 the review is recorded but the candidate blocks **remain**, because no authorized mechanism can yet represent the impact in the ledger; escalate to the Owner decision on a representation mechanism (OI-93). Never allocate or post money by hand.

## 10. Additional work in R1, outside automated billing (OI-101)

**[PROPOSED procedure; Owner direction 2026-11-25]** Automated additional-work billing (PWP-6) is post-R1. In R1, additional work after a verified deposit is handled outside the portal's automated billing workflow:

1. Record the request and confirm it is outside the accepted entitlements and confirmed selections (05 §3A).
2. Obtain the client's separate acceptance of the additional work at $125 per hour or a separately accepted fixed price (CD-14), under counsel-approved terms (DEP-03). Until counsel-approved terms exist, do not represent any wording as legally approved.
3. Collect payment only through a compliant, separately authorized payment mechanism. **Never** mark anything paid in the portal, change a payment state, issue or alter an order summary, or change the accepted development price (OI-81).
4. Keep the evidence outside the portal's contractual snapshot and outside Git.

## 11. Repository visibility change (FD-03, OI-106)

**[PROPOSED checklist; Owner action, Tier 3 (GitHub settings); not performed]** The repository is to become private. Changing visibility does not remove copies already cloned, cached or archived, and history is not rewritten without a separate Tier 4 authorization.

Before the change:
1. Confirm that the GitHub plan still enforces the `protect-main` ruleset and the required checks on a private repository (DEP-10, DEP-16); if not, decide how `main` stays protected before changing visibility.
2. Confirm the GitHub Actions minutes available to a private repository for the full CI suite.
3. Confirm secret scanning and push protection availability for a private repository; the CI gitleaks full-history scan continues regardless.
4. Confirm that the Claude GitHub App and any other integrations keep their access.

Exposure assessment:
5. Treat everything committed so far as having been public. Review pull request bodies, comments and Actions logs, which the gitleaks scan does not cover.
6. If any real credential is found to have been exposed, rotate or revoke it (Tier 4, with recorded verification). Do not record credential values anywhere.

After the change:
7. Verify that an unauthenticated request for the repository fails; the branch rules on `main` are unchanged; a test pull request runs the required checks; integrations still work.
8. Record the evidence in CURRENT-STATE. Authoritative legal text, publication copies and counsel evidence still stay outside Git (CLAUDE.md §5).

## 12. Final-balance initiation blocked by `approval_mismatch` (OI-113 option (c); emergency recovery only)

**[PROPOSED]** Recorded from AUTH-013 (Owner, 2026-11-25). This is an emergency recovery procedure, never a resolution: OI-113 was resolved by the interface correction (PR #38, `7226d6f`), after which a legitimate approval no longer produces this block. It creates no new permission, override or payment path, and never marks anything paid or approved on a client's behalf.

- **Trigger:** `payment.final_balance_blocked` with the audit detail `approval_mismatch`.
- **Before acting:** confirm the block is not a genuine defect (for example, a withdrawn or superseded release), and record the audit event identifiers.
- **Procedure:** staff re-release the same build through the normal release action (`preview_releases` has no `commit_sha` uniqueness); one client member approves the new release through the normal approval action; the consumer then initiates through its normal path.
- **Unverified contractual effect (DEP-03):** the effect of a re-release after an approval on revision accounting is unverified and is checked with counsel before this procedure is used.
- **Never:** fabricate, replay, replace or repair a `release.approved` event; edit an approval; or bypass the gate or WP-H's cross-check.
