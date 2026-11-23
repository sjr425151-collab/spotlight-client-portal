# Spotlight Marketing Client Portal

A secure client portal for Spotlight Marketing LLC. It takes each website client from agreement acceptance and payment through onboarding, preview approval, final payment, and Owner-authorized publication.

- **Production URL:** `https://portal.spotlight-marketing.co`. This is a standalone application, separate from the agency website.
- **Agency website:** `https://spotlight-marketing.co`. It remains on GoHighLevel and is not part of this repository.

## Authorization status

| Stage | Status |
|---|---|
| Architecture approval | Approved: decisions OI-01–OI-41 (register pending owner verification) |
| Specification reconciliation | **In progress.** Documentation only. |
| Implementation | **Not authorized.** No phase may begin without separate written owner authorization. |
| Production launch | **Not authorized** |
| Stripe test-mode catalog (narrow exception, OI-30) | Authorized; **blocked** pending a valid test-mode key (DEP-01) |

This repository currently contains **documentation only**. See [CLAUDE.md](CLAUDE.md) before making any change.

## MVP scope

1. Invitation-only sign-in with passwordless email OTP.
2. Acceptance of a versioned services agreement and project order summary.
3. Stripe Checkout for the 20% development deposit plus the first $99 monthly maintenance payment.
4. Onboarding intake and secure asset uploads, unlocked by verified payment.
5. Immutable versioned previews with explicit client approval.
6. A separate Checkout for the remaining 80% balance.
7. Owner-authorized publication behind server-enforced gates, followed by live verification.
8. Publication confirmation, with optional, inquiry-only service offers.
9. Billing self-service through the hosted Stripe Customer Portal: payment methods, invoices, and subscription details. Self-service cancellation is disabled; cancellation is handled by request, with a 12-business-day hosting transition.

**Not in the MVP:** a full client dashboard, AI agents, Google Sheets/Drive or CRM integrations, marketing automation, automatic upsell purchases, and multi-agency tenancy. See [01 §4](docs/01-PROJECT-OVERVIEW.md#4-exclusions-and-future-roadmap).

## Architecture overview

| Layer | Technology |
|---|---|
| App | Next.js App Router, strict TypeScript, Tailwind CSS |
| Runtime / tooling | Node.js 24 LTS, pnpm, ESLint, Prettier, Vitest, Playwright |
| Auth / data / files | Supabase Auth (email OTP), Postgres with RLS, private Storage |
| Payments | Stripe Checkout, Billing, and Customer Portal (signature-verified webhooks) |
| Email | Resend (operational), Supabase Auth (auth flows), Stripe (receipts) |
| Hosting / CI | Vercel, GitHub Actions |

Client websites are **separate, isolated deployments**: agency-managed Vercel, one project per client. They are not pages inside the portal.

**Brand:** the official logo source is the Google Drive "SLM" folder (`https://drive.google.com/drive/folders/1SGrxZ6fOI6PZUVk76XYaEFS4pQ26LvGu`). See [07 §10.1](docs/07-NOTIFICATIONS-PRIVACY-AND-DESIGN.md#101-official-logo-source-approved-oi-38). Final visual design requires Owner approval.

## Documentation index

| Document | Purpose |
|---|---|
| [01 — Project Overview](docs/01-PROJECT-OVERVIEW.md) | Scope, journey, roles, phases, governance, MVP acceptance criteria |
| [02 — Architecture and Environments](docs/02-ARCHITECTURE-AND-ENVIRONMENTS.md) | System architecture, environments, deployment, performance, secrets |
| [03 — Security, Auth, and Tenancy](docs/03-SECURITY-AUTH-AND-TENANCY.md) | Threat model, permissions, auth, RLS, audit, overrides |
| [04 — Agreement and Billing](docs/04-AGREEMENT-AND-BILLING.md) | Agreement evidence, pricing, Stripe catalog, Checkout, webhooks, ledger |
| [05 — Project Lifecycle and Uploads](docs/05-PROJECT-LIFECYCLE-AND-UPLOADS.md) | State machines, intake, uploads, previews, approvals, queues |
| [06 — Publishing and Post-Launch](docs/06-PUBLISHING-AND-POST-LAUNCH.md) | Publication gates, deployment, verification, rollback, inquiries |
| [07 — Notifications, Privacy, and Design](docs/07-NOTIFICATIONS-PRIVACY-AND-DESIGN.md) | Outbox, event catalog, retention, privacy, design system |
| [08 — Decisions and Changelog](docs/08-DECISIONS-AND-CHANGELOG.md) | Decision register OI-01–OI-24, change control |
| [OPEN-ISSUES.md](OPEN-ISSUES.md) | Decided issues, open Owner decisions (OI-42 onward), and implementation dependencies (DEP-nn) |
| [CLAUDE.md](CLAUDE.md) | Operating instructions for contributors and AI agents |

## Environments

| Environment | Stripe | Data |
|---|---|---|
| Development | Test mode | Synthetic |
| Preview (per PR, protected) | Test mode | Synthetic |
| Staging | Test mode | Synthetic |
| Production | Live mode (requires launch authorization) | Real |

Details are in [02 §4](docs/02-ARCHITECTURE-AND-ENVIRONMENTS.md#4-environment-isolation-approved-oi-10).

## Security principles

- All authorization happens on the server, with Supabase RLS as defense in depth. No client sees another project's data.
- Payment is verified **only** from signature-verified Stripe webhooks. A redirect is never proof of payment.
- No one, including the Owner, can fabricate a payment, client approval, or QA result, or bypass a publication gate.
- Privileged actions require MFA, reauthentication for high-risk actions, and immutable audit records.
- No secrets in the repository. Production credentials never reach non-production environments.

## Development workflow

Once implementation is separately authorized (it is not yet):

1. Work on a feature branch. Open a PR against `main`.
2. CI must pass lint, typecheck, unit, e2e, and performance/security checks.
3. The Owner reviews and merges. Production promotion is Owner-controlled.
4. Specification changes follow [08 §6](docs/08-DECISIONS-AND-CHANGELOG.md#6-change-control-rules). Conflicts are escalated, never silently resolved.
