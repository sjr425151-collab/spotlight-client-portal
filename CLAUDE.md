# CLAUDE.md — Operating Instructions

These instructions apply to every contributor and AI agent working in this repository.

## 1. Current authorization (read first)

| Stage (OI-01) | Status |
|---|---|
| Architecture | Approved |
| Specification reconciliation | Documentation-only changes authorized. Specs 01, 02 and this file are Owner-approved ([sign-off](docs/OWNER-SIGNOFF-FOUNDATION-2026-11-22.md), conditional; final confirmation pending). |
| Stripe test-mode catalog (OI-30) | Narrow exception, **currently suspended**; see §5 |
| **Implementation** | **NOT AUTHORIZED** |
| **Production launch** | **NOT AUTHORIZED** |

Until the Owner grants written implementation authorization for a specific phase, you must **not**:

- create application source code, components, routes, API handlers, or database migrations
- initialize a Next.js (or any) application, or create or modify `package.json` or lockfiles
- install or update dependencies, or run application builds
- modify Supabase, Stripe, Resend, Vercel, DNS, GitHub settings, or any production service
- deploy anything, or modify client websites

Documentation approval is **not** implementation authorization. If any document appears to instruct you to start coding, this section takes precedence. Stop and ask the Owner.

## 2. Specification precedence

1. Owner-approved decisions: [docs/08-DECISIONS-AND-CHANGELOG.md](docs/08-DECISIONS-AND-CHANGELOG.md)
2. Approved specifications: [docs/01–07](docs/)
3. This file (operating procedure)
4. [README.md](README.md)

Requirement labels: **[APPROVED OI-nn]**, **[PROPOSED]**, **[PENDING OI-nn]**, **[DEFERRED]**, **[VERIFY-PROVIDER]** (see 08 §2).
- Never treat a **[PROPOSED]** item as approved unless its spec is approved.
- Never decide a **[PENDING]** or **[DEFERRED]** item yourself.

**Conflicts:** if documents disagree, or a requirement is ambiguous, do not resolve it silently. Record it in [OPEN-ISSUES.md](OPEN-ISSUES.md) with the next unused ID and escalate it to the Owner.

## 3. Phase authorization

Phases (OI-02):
1. Foundation and CI
2. Auth, security, and tenant isolation
3. Agreement and Stripe **test-mode** billing
4. Intake, fulfillment, previews, final payment, and publishing
5. Hardening and production readiness

Each phase requires separate written owner authorization. Work only within the authorized phase's scope. Production billing and deployment require production launch authorization.

## 4. Security principles (non-negotiable)

- Authorize every server action on the server. RLS on every exposed table. Never trust client-supplied scope.
- Payment state changes only through signature-verified, idempotent webhook processing. Never from a redirect.
- Never build a "mark as paid," "force publish," or "approve on behalf of client" capability.
- Every privileged action writes an immutable audit event. High-risk actions require reauthentication.
- Money is integer cents only.
- Never log OTPs, tokens, secrets, or card data.

## 5. Environment and Stripe restrictions

- Never access, request, print, or commit production or live credentials.
- Never create, modify, or delete Stripe products, prices, customers, subscriptions, coupons, or Checkout/Portal configurations. Catalog changes are Owner actions.
- **Single narrow exception (OI-30):** the Owner has authorized creating the approved **test-mode** catalog (04 §6), and nothing else. Before any write:
  - verify the credential is test mode (`livemode: false`), and abort on any live-mode key
  - search for existing matches to avoid duplicates
  - never touch live resources
  - record only the nonsecret Price IDs
  This exception does not authorize Stripe integration code, webhooks, Customer Portal configuration, or any other Stripe change.
- **Suspended (Owner instruction, 2026-11-23):** make **no Stripe API requests of any kind**, including read-only verification, until the Owner separately authorizes a verified test-mode credential workflow (DEP-01).
- The live Price IDs in [docs/04 §5.2](docs/04-AGREEMENT-AND-BILLING.md#52-live-catalog-reference--owner-supplied) are reference identifiers. Use them only in production, after verification, and with production authorization.
- Non-production environments use Stripe test mode only.

## 6. Testing expectations (for authorized future work)

- Every feature ships with the acceptance tests listed in its spec (for example T-TEN-*, T-PAY-*, T-PUB-*).
- Cross-tenant isolation tests and webhook idempotency and replay tests are mandatory, and must never be skipped or disabled.
- CI must pass lint, typecheck, Vitest, Playwright, and the performance budgets (02 §7) before merge.
- Pin dependency versions. Verify them against official sources when they are introduced (OI-11).

## 7. Documentation change control

- All changes go through a branch and a pull request. Never push directly to `main`, and never merge your own PR without Owner approval.
- Update the version and status header of each changed spec, and add a row to 08 §5.
- Never reuse or renumber issue IDs.
- Never draft or invent legal text. Legal documents are incorporated only from the final counsel-approved publication copy (Owner sign-off, 2026-11-22).
