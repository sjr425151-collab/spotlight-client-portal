# Owner Runbooks

| Field | Value |
|---|---|
| Version | 0.1.0 |
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
