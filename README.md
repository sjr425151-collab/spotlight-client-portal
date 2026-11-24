# Spotlight Marketing Client Portal

A secure client portal for Spotlight Marketing LLC. It takes each website client from agreement acceptance and payment through onboarding, preview approval, final payment, and Owner-authorized publication.

- **Production URL:** `https://portal.spotlight-marketing.co`. This is a standalone application, separate from the agency website.
- **Agency website:** `https://spotlight-marketing.co`. It remains on GoHighLevel and is not part of this repository.

## Status and authorization

- **Current state:** [docs/CURRENT-STATE.md](docs/CURRENT-STATE.md) is the single, canonical status record.
- **What is authorized:** [docs/AUTHORIZATIONS.md](docs/AUTHORIZATIONS.md) (risk tiers 0–4, OI-67).
- **Production launch is not authorized.** No real client payment may be accepted until it is.

This repository contains the approved specifications, the application foundation, and the authentication, security, and tenant-isolation layer. Everything runs against a **local** Supabase stack with synthetic data; no hosted service is connected. Read [CLAUDE.md](CLAUDE.md) before making any change, and [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) to run it.

## Releases (OI-68)

**R1, a complete controlled transaction:**
1. Invitation-only sign-in with passwordless email OTP.
2. Acceptance of a versioned services agreement and project order summary.
3. Stripe Checkout for the 20% development deposit plus the first $99 monthly maintenance payment.
4. Intake and secure, scanned asset uploads, unlocked by verified payment.
5. Client status tracking and a derived administrative fulfillment queue.
6. Explicit client approval of a specific, immutable preview release.
7. Final balance charged automatically to the card authorized and saved at the deposit Checkout, on a single invoice with a Stripe-hosted fallback, verified by webhook (OI-74).
8. Owner publication authorization behind server-enforced gates, then staff-executed deployment of exactly the authorized release, with audit evidence and live verification.

**R2, fulfillment automation:** automated preview delivery and reminders, payment recovery and the Stripe Customer Portal, adjusted balances, deployment orchestration, transactional email through Resend, and post-publication inquiries.

**Not in scope:** a full client dashboard, AI agents, Google Sheets/Drive or CRM integrations, marketing automation, automatic upsell purchases, and multi-agency tenancy. See [01 §4](docs/01-PROJECT-OVERVIEW.md#4-exclusions-and-future-roadmap).

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
| [03A — Supabase and Next.js Provider Verification](docs/03A-SUPABASE-PROVIDER-VERIFICATION.md) | Phase 2 provider evidence with source citations |
| [04 — Agreement and Billing](docs/04-AGREEMENT-AND-BILLING.md) | Agreement evidence, pricing, Stripe catalog, Checkout, webhooks, ledger |
| [05 — Project Lifecycle and Uploads](docs/05-PROJECT-LIFECYCLE-AND-UPLOADS.md) | State machines, intake, uploads, previews, approvals, queues |
| [06 — Publishing and Post-Launch](docs/06-PUBLISHING-AND-POST-LAUNCH.md) | Publication gates, deployment, verification, rollback, inquiries |
| [07 — Notifications, Privacy, and Design](docs/07-NOTIFICATIONS-PRIVACY-AND-DESIGN.md) | Outbox, event catalog, retention, privacy, design system |
| [08 — Decisions and Changelog](docs/08-DECISIONS-AND-CHANGELOG.md) | Decision register, traceability, change history, change control |
| [CURRENT-STATE](docs/CURRENT-STATE.md) | Canonical status: releases, work packages, specs, dependencies, pending Owner actions |
| [AUTHORIZATIONS](docs/AUTHORIZATIONS.md) | Risk tiers and active authorizations |
| [OPEN-ISSUES.md](OPEN-ISSUES.md) | Decided issues, open Owner decisions (Part 2), and implementation dependencies (DEP-nn) |
| [CLAUDE.md](CLAUDE.md) | Operating instructions for contributors and AI agents |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Local setup, toolchain, commands, CI, architecture |

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

Setup, toolchain versions, commands, CI, and architecture are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

```bash
corepack enable && pnpm install --frozen-lockfile
cp .env.example .env.local
pnpm dev          # http://localhost:3000
pnpm verify       # lint, typecheck, format, unit, build, bundle check, e2e
```

1. Work on a feature branch under an active authorization. Open a PR against `main`.
2. The required `CI result` check must pass. Documentation-only PRs skip the database, end-to-end, and Lighthouse suites, which are reported as not run; every other change runs everything (OI-70).
3. The PR carries its own evidence and updates CURRENT-STATE. The Owner reviews and merges. Production promotion is Owner-controlled (Tier 3).
4. Specification changes follow [08 §6](docs/08-DECISIONS-AND-CHANGELOG.md#6-change-control-rules). Conflicts are escalated, never silently resolved.
