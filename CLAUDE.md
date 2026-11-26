# CLAUDE.md — Operating Instructions

These instructions apply to every contributor and AI agent working in this repository.

## 1. Before you start (required reading)

Read, in this order:
1. This file.
2. [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md): what is done, in progress, and pending.
3. [docs/AUTHORIZATIONS.md](docs/AUTHORIZATIONS.md): what you may do now.
4. Only the specifications and decisions the active authorization names for your task. You do not need to read every document.

If no active authorization covers the task, you may do only Tier 0 work (documentation, formatting, read-only research). Stop and ask the Owner for anything else.

## 2. Authorization and precedence

- Work only within the scope, environments, credentials, and expiry of an **active** record in AUTHORIZATIONS.md (risk tiers 0–4, OI-67). A record that is granted but not yet active authorizes nothing.
- When a **stop condition** occurs, stop and report. Do not retry, broaden scope, or find a workaround.
- If an action does not clearly fit a record, treat it as the next tier up and ask.
- Approving a document or decision never authorizes work by itself.

Precedence: (1) Owner decisions in [08](docs/08-DECISIONS-AND-CHANGELOG.md); (2) approved specifications 01–07; (3) this file; (4) README. AUTHORIZATIONS.md is authoritative for what is authorized; if it and any other document disagree about authorization, the more restrictive reading applies.

Requirement labels: **[APPROVED OI-nn]**, **[PROPOSED]**, **[PENDING OI-nn]**, **[DEFERRED]**, **[VERIFY-PROVIDER]**, plus **[R1]** and **[R2]** release tags (08 §2).
- Never treat a **[PROPOSED]** item as approved unless its spec is approved.
- Never decide a **[PENDING]** or **[DEFERRED]** item yourself.

**Conflicts:** if documents disagree, or a requirement is ambiguous, do not resolve it silently. Record it in [OPEN-ISSUES.md](OPEN-ISSUES.md) with the next unused ID and escalate it to the Owner.

## 3. Security principles (non-negotiable)

- Authorize every server action on the server. RLS on every exposed table. Never trust client-supplied scope.
- Payment state changes only through signature-verified, idempotent webhook processing. Never from a redirect or a client-provided assertion.
- Never build a "mark as paid," "force publish," or "approve on behalf of client" capability.
- Every privileged action writes an immutable audit event. High-risk actions require reauthentication.
- Money is integer cents only.
- Never log OTPs, tokens, secrets, or card data.
- Every new table and storage path ships with cross-tenant isolation tests. Isolation and webhook idempotency and replay tests are never skipped or disabled.

## 4. Environment and Stripe restrictions

- Never access, request, print, or commit production or live credentials. No live credential is ever placed in a development, CI, preview, or staging environment.
- **Stripe API requests are allowed only under an active Tier 2 Stripe authorization** (currently AUTH-002, once its activation conditions are met), only with a confirmed test-mode credential, and only for the operations it lists. Every run starts with the fail-closed `livemode: false` preflight (04 §6.3) and aborts on any live-mode signal.
- Never create, modify, or delete Stripe products, prices, coupons, or promotion codes, or live-mode objects of any kind. Catalog changes and Dashboard settings are Owner actions.
- CI never holds a Stripe credential. Webhook tests in CI use synthetic events signed with a test-only secret (OI-63).
- The live Price IDs in [04 §5.2](docs/04-AGREEMENT-AND-BILLING.md#52-live-catalog-reference--owner-supplied) are reference identifiers, used only in production, after verification (DEP-02), with production authorization.
- Non-production environments use Stripe test mode and synthetic data only.
- Hosted environments, DNS, Vercel, Supabase, Resend, and GitHub settings change only under the tier the action requires (AUTHORIZATIONS.md §1). Production actions are Tier 3; destructive or irreversible actions are Tier 4.

## 5. Legal text and test fixtures (OI-69)

- Never draft or invent legal text. Legal documents are incorporated only from the final counsel-approved publication copy (Owner sign-off, 2026-11-22).
- Authoritative legal text, publication copies, counsel correspondence and approval evidence never enter Git, including the substantive text of external reconstruction drafts. The repository may hold only approved non-sensitive identifiers, version references, integrity hashes and provenance metadata (OI-106). No migration is a contractual-content loading path.
- Tests and non-production environments may use a **test-only agreement fixture**. Its body is a non-legal placeholder ("TEST FIXTURE — NOT AN AGREEMENT"). It may contain only the verbatim, already-approved clause text in 04 §3.1. It is labeled on every screen that shows it.
- A fixture must be **technically prevented** from production use: the environment schema rejects it when `APP_ENV=production`, the database refuses to mark a fixture version `approved` for production use, and a CI test proves both.

## 6. Testing

- Every feature ships with the acceptance tests listed in its spec (T-TEN-*, T-PAY-*, T-LC-*, T-PUB-*, and so on).
- Merging requires the aggregate `CI result` check. It runs lint, typecheck, format, unit tests, the dependency audit, and the secret scan on every change, and the database, integration, end-to-end, and Lighthouse suites on every change that is not documentation-only (OI-70).
- Never claim a test passed unless it ran. Report the commands and results. A suite that did not run is reported as not run.

## 7. Change control and evidence

- All changes go through a branch and a pull request. Never push directly to `main`, and never merge your own PR without Owner approval. Owner-approved standing and conditional merge authority, documentation-only activation, implementation-equivalence carry-forward and Main's bounded delegated authority are defined in [AUTHORIZATIONS.md §2A](docs/AUTHORIZATIONS.md) (OM-1 to OM-7).
- **An implementation PR carries its own evidence and documentation updates**: test results, verification records, provider run IDs, and the matching updates to [CURRENT-STATE.md](docs/CURRENT-STATE.md) and the affected specs. Do not open separate status-only PRs when the implementation PR can carry the update.
- A changed spec gets a new version and status header and a row in 08 §5.
- Never reuse or renumber issue, dependency, or authorization IDs.
- Each implementation PR description records effort: AI session hours, Owner review hours, and administrative hours (OI-67).

## 8. Dependencies

- Pin dependency versions exactly, and verify them against official sources when they are introduced or changed (OI-11).
- Change `package.json` or the lockfile only under an active authorization that covers it, or under the **dependency security patch exception** (AUTHORIZATIONS.md §4): a patch or minor fix for a high or critical advisory, with full CI and Owner merge. Major upgrades always need a work-package authorization.
- Do not add vendors, services, or dependencies that the active authorization does not name.
