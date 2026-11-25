# Development Guide

| Field | Value |
|---|---|
| Applies to | Phase 1: Foundation and CI (merged); Phase 2: Auth, security, and tenant isolation (authorized 2026-11-23) |
| Specifications | [01](01-PROJECT-OVERVIEW.md), [02](02-ARCHITECTURE-AND-ENVIRONMENTS.md), [03](03-SECURITY-AUTH-AND-TENANCY.md) with [03A](03A-SUPABASE-PROVIDER-VERIFICATION.md), [CLAUDE.md](../CLAUDE.md) |

Read [CLAUDE.md](../CLAUDE.md) first. Phase 2 uses a **local** Supabase stack only, with synthetic data. No hosted service (hosted Supabase, Stripe, Resend or SMTP, Vercel) is connected, and none may be connected without separate written Owner authorization.

## 1. Toolchain

All versions are pinned exactly. They were verified on 2026-11-23 against the official sources listed.

| Tool | Version | Source verified | Notes |
|---|---|---|---|
| Node.js | **24.22.3** (LTS "Krypton") | nodejs.org/dist/index.json; tarball checked against SHASUMS256.txt | Approved runtime (OI-11). Node 26 is now the newer active LTS line; staying on 24 follows the Owner's decision. Pinned in `.node-version` and `engines`. |
| pnpm | **12.21.0** | npm registry `latest` dist-tag | Pinned in `packageManager`; activated with Corepack |
| Next.js | 16.4.6 | npm registry | App Router, Turbopack builds |
| React / React DOM | 19.3.1 | npm registry | Within Next.js peer range |
| TypeScript | **6.0.3** | npm registry | 7.0.2 is newer, but `typescript-eslint` (via `eslint-config-next`) supports only `<6.1.0` |
| Tailwind CSS / `@tailwindcss/postcss` | 4.3.5 | npm registry | CSS-first `@theme` tokens |
| ESLint | **9.39.5** | npm registry | ESLint 10 is current, but `eslint-plugin-react`, `-import`, and `-jsx-a11y` (required by `eslint-config-next`) declare support only up to ESLint 9. Upgrade when they do. |
| eslint-config-next | 16.4.6 | npm registry | Matches Next.js |
| Prettier | 3.10.1 | npm registry | |
| Vitest | 5.1.1 | npm registry | jsdom 31.0.1 for component tests |
| Testing Library | react 16.3.3, dom 10.4.2 | npm registry | |
| Playwright | 1.65.1 | npm registry | CI installs Chromium with `playwright install --with-deps chromium` |
| @axe-core/playwright | 4.14.0 | npm registry | WCAG 2.2 AA checks in smoke tests |
| @lhci/cli | 0.16.1 | npm registry | Lighthouse budgets (spec 02 §7) |
| zod | 4.6.7 | npm registry | Environment validation |
| server-only | 0.0.1 | npm registry | Build-time guard for server modules |
| @supabase/supabase-js | 2.119.2 | npm registry | Phase 2. Server-side only. |
| @supabase/ssr | 0.12.7 | npm registry | Phase 2. Cookie sessions in `src/proxy.ts` and server code (03A F-19) |
| pg / @types/pg (dev) | 8.16.3 / 8.15.6 | npm registry | Test setup against the local database only |
| Supabase CLI | 3.2.0 | GitHub release `supabase/cli`, SHA-256 from `checksums.txt` | Local stack and CI. Needs Docker. Not an npm dependency. |
| gitleaks (CI only) | 8.30.1 | GitHub release, SHA-256 checksum | Downloaded and verified in CI |

GitHub Actions are pinned to commit SHAs: `actions/checkout` v7.0.1, `actions/setup-node` v7.1.0, `pnpm/action-setup` v6.1.1, `actions/upload-artifact` v7.0.2.

Fonts (Inter, Montserrat) are self-hosted from `@fontsource-variable/*` 5.3.0, Latin subset only, under the SIL Open Font License (see `src/app/fonts/LICENSE-*`). They are vendored, so builds make no font network requests.

## 2. Local setup

```bash
# 1. Use Node.js 24.22.3 (for example: fnm use / nvm use, which read .node-version)
node --version            # v24.22.3

# 2. Activate the pinned pnpm
corepack enable
pnpm --version            # 12.21.0

# 3. Install exactly what the lockfile specifies
pnpm install --frozen-lockfile

# 4. Start the local Supabase stack (Docker required; migrations and the synthetic seed apply)
supabase start            # prints the local API URL and the local publishable/secret keys
supabase db reset         # re-apply every migration and supabase/seed.sql from scratch

# 5. Configure the environment from `supabase status` (names in .env.example)
cp .env.example .env.local   # then fill in the three Supabase values printed by `supabase status`

# 6. Run
pnpm dev                  # http://localhost:3000
```

**Local sign-in.** Seeded synthetic users (`supabase/seed.sql`): `owner@example.test` (Owner), `admin@example.test` (Admin), `sales@example.test` (Sales Representative, WP-S; no assignment until it creates a customer at `/sales`), `client.a@example.test` (Project A), `client.b@example.test` (Project B). Sign-in codes and invitation emails arrive in the local Mailpit at http://127.0.0.1:54324. Staff, including Sales Representatives, are asked to enroll an authenticator app (TOTP) at first sign-in. The seed also loads test-only package scope fixtures (labeled "TEST FIXTURE — NOT A DELIVERABLE"), which the database accepts only because the seed classifies the database as `development`. The local keys printed by `supabase status` are well-known development defaults. They are never committed: `.env.local` is gitignored.

Playwright needs a browser: run `pnpm exec playwright install chromium` once. If your machine already provides a compatible Chromium, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to its path.

## 3. Commands

| Command | Purpose |
|---|---|
| `pnpm dev` | Development server with fast refresh |
| `pnpm build` / `pnpm start` | Production build and server |
| `pnpm lint` | ESLint (zero warnings allowed) |
| `pnpm typecheck` | Strict TypeScript, no emit |
| `pnpm format` / `pnpm format:check` | Prettier write / verify |
| `pnpm test` | Vitest unit, component, and static security tests (no services needed) |
| `supabase test db` | pgTAP database tests in `supabase/tests` (RLS, roles, MFA, sessions, invitations, audit). `pnpm test:db` runs the same files through `psql` in the database container, for machines that cannot pull the pgTAP runner image. The suites assume a **freshly reset** database (`supabase db reset`), as CI runs them; run after the integration suite, some fail on the synthetic rows those tests leave. |
| `pnpm test:integration` | Vitest integration tests against the local stack (real Auth sessions, Mailpit, storage) |
| `pnpm build:production-check` | Builds a production-mode copy (`APP_ENV=production`) into `.next-production/`, used only by the gating tests and never deployed |
| `pnpm test:e2e` | Playwright: smoke tests, the Phase 2 auth flows (`auth` project, needs the local stack), the WP-C and WP-B browser tests, and production-gating tests (run both builds first). The WP-B project needs `E2E_STRIPE_WEBHOOK_SECRET` set to a generated test-only `whsec_` value (for example `whsec_$(openssl rand -hex 24)`); the test-build server receives it with `STRIPE_GATEWAY=mock` and `AGREEMENT_TEST_FIXTURE=enabled`, and the production-mode server receives none of them |
| `scripts/check-migrations.sh [base]` | Fails if a migration already on the base branch was edited, renamed, or deleted (T-MIG-02) |
| `pnpm check:bundle` | Scans browser-delivered build output for secrets (T-SEC-01) |
| `pnpm lhci` | Lighthouse CI with the spec 02 §7 budgets (run `pnpm build` first) |
| `pnpm verify` | Everything above, except Lighthouse, in CI order |

## 4. Environments and configuration

Configuration is validated at startup and build time by `src/config/env-schema.ts`. **Invalid configuration fails closed.**

| Variable | Phase | Rule |
|---|---|---|
| `APP_ENV` | 1 | One of `development`, `test`, `preview`, `staging`, `production` |
| `NEXT_PUBLIC_SITE_URL` | 1 | Absolute http(s) URL of the deployment |
| `NEXT_PUBLIC_SUPABASE_URL` | 2 | Absolute URL. Outside `staging` and `production` it must be a local host (spec 03 §15). |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | 2 | Must start with `sb_publishable_` |
| `SUPABASE_SECRET_KEY` | 2 | Must start with `sb_secret_`. Server-only; read only by `src/server/supabase/admin.ts`. |
| `STRIPE_SECRET_KEY` | 3 (not used yet) | If present, a live-mode key outside `production` fails validation (spec 02 §4 rule 2) |
| `STRIPE_WEBHOOK_SECRET` | WP-B | Optional; `whsec_...`. Without it `/api/stripe/webhook` returns 503 (fail closed). Locally and in CI, a generated test-only value; a real test-mode secret only under AUTH-002 |
| `STRIPE_GATEWAY` | WP-B | `disabled` (default when absent) or `mock`. `mock` simulates Stripe with no network request and is accepted only in `development` and `test`. No real gateway exists until AUTH-002 |
| `AGREEMENT_TEST_FIXTURE` | WP-B | `enabled` or `disabled` (default when absent). Presents the OI-69 test-only fixture; rejected when `APP_ENV=production` (T-AGR-08) |
| any `NEXT_PUBLIC_*` | All | Must not contain secret-shaped values (spec 02 §9 rule 3) |

Environment separation (spec 02 §4):

| Environment | `APP_ENV` | Stripe | Data | Status |
|---|---|---|---|---|
| Development | `development` | Test mode only | Synthetic | Local only |
| Preview | `preview` | Test mode only | Synthetic | Not provisioned. Vercel is not authorized. |
| Staging | `staging` | Test mode only | Synthetic | Not provisioned |
| Production | `production` | Live mode (requires launch authorization) | Real | Not provisioned. Not authorized. |
| CI | `test` | None | None | GitHub Actions |

Each environment gets its own credentials, set in the hosting provider's secret store, never in the repository. Rules:
- `.env*` files are gitignored except `.env.example`.
- Server-only modules import `server-only`.
- `@/config/env` is the only place that reads `process.env`.

## 5. Continuous integration

`.github/workflows/ci.yml` runs on every pull request, on pushes to `main`, and on manual runs. Jobs have read-only permissions and no credentials. The workflow is path-aware and fails closed (OI-70).

| Job | Runs | Checks |
|---|---|---|
| Classify changes | Always | Lists the pull request's changed paths (`git diff --no-renames` against the base) with `scripts/ci/classify-changes.mjs` **taken from the base commit**. Scope is `docs` only when every path is `docs/**/*.md` or a root `*.md`. Anything else, a push, a manual run, an unknown commit, or any error gives `full`. |
| Lint, types, format, unit tests | Always | Frozen-lockfile install, ESLint, `tsc`, Prettier, Vitest |
| Dependency audit | Always | `pnpm audit --audit-level=high` |
| Secret scan | Always | gitleaks over full git history (checksum-verified binary) |
| Database, integration, and e2e tests (local Supabase) | Scope `full` | Migration immutability (T-MIG-02); Supabase CLI 3.2.0 (checksum verified); `supabase start`; `supabase db reset` (T-MIG-01); `supabase test db` (pgTAP); integration tests; test build; secret scan of `.next/static` (T-SEC-01, including `sb_secret_`); production-mode build; Playwright smoke tests on desktop and mobile Chromium, the auth flows (OTP via Mailpit, invitations, staff MFA, revocation, nonce CSP T-SEC-03/04, `Cache-Control` T-SEC-06, WCAG), and production gating. Playwright browsers are cached by Playwright version; the install is capped at 5 minutes per attempt with one retry, and the e2e step at 15 minutes. |
| Lighthouse budgets | Scope `full` | 3 mobile runs each for `/` and `/sign-in`. Median must reach Performance ≥ 0.90, Accessibility ≥ 0.95, Best Practices ≥ 0.95, and SEO ≥ 0.90 (SEO for `/` only; private pages are `noindex`). Reports kept as a run artifact only. |
| **CI result** | Always (after all others) | The required aggregate check. It uses the base commit's evaluator and passes only if classification succeeded, every always-run job passed, and, for scope `full`, the e2e and Lighthouse jobs passed. Its summary lists each suite as "ran: passed" or "not run (documentation-only change)". Without a trusted evaluator on the base commit (or outside a pull request), it requires every job to have run and passed. |

Superseded pull request runs are cancelled. Runs on `main` always complete.

**Branch protection.** The `protect-main` ruleset requires pull requests and, as of 2026-11-24, requires the five original jobs. After this workflow merges, the Owner switches the required checks to `CI result`, `Lint, types, format, unit tests`, `Dependency audit`, and `Secret scan (gitleaks, full history)` (DEP-16). The e2e and Lighthouse jobs must not stay required, because GitHub reports a skipped job as passing.

**Checks that cannot run yet:**
- Field Core Web Vitals (RUM): requires a deployed environment and a monitoring vendor (DEP-12).
- p95 read latency: requires a hosted data layer (DEP-14).
- Hosted Supabase settings (rate limits, OTP expiry range, plan gating): U-06 to U-08 and U-10 need a hosted project (DEP-14, OI-50).

## 6. Architecture

```text
src/
  app/            Routes, layouts, metadata (Next.js App Router). Server components by default.
    design-system/  Internal primitives reference. 404 when APP_ENV=production.
    fonts/        Self-hosted OFL fonts
  components/
    ui/           Reusable primitives: Button, ButtonLink, TextField, Card, Eyebrow
    layout/       Layout primitives: Container
    brand/        Official logo
    site/         Site chrome: header, footer
  config/         env-schema (pure, tested), env (server-only), security headers, site metadata
  design/         Design tokens (single source of truth) and WCAG contrast helpers
  domain/         Business rules. Empty until Phase 3. See README.
  server/         Server-only code
    supabase/     clients.ts (publishable key: user and sessionless clients); admin.ts (secret key)
    auth/         context (getClaims + live auth_context), guards, rate limits, security events
    services/     sign-in, invitations, staff administration, MFA
  proxy.ts        Per-request nonce CSP, Supabase session refresh, Cache-Control (Next.js 16 proxy)
  lib/            Small shared utilities, user-facing message codes
supabase/
  config.toml     Local stack: sign-up disabled, OTP 10 min, JWT 15 min, TOTP, before-user-created hook
  migrations/     Forward-only SQL migrations (never edited after merge, T-MIG-02)
  seed.sql        Synthetic users, businesses, and projects
  templates/      Code-based invitation and sign-in emails
  tests/          pgTAP tests
tests/
  unit/           Vitest (node; jsdom per file where needed), including static security checks
  integration/    Vitest against the local stack
  e2e/            Playwright smoke tests and Phase 2 auth flows
  support/        Local-only helpers: Mailpit, TOTP, local database
scripts/          CI helper scripts
```

**Phase 2 security model (spec 03).**
- The browser never calls Supabase. All Supabase calls run on the server; auth cookies are HttpOnly.
- Identity comes from `getClaims()` (verified JWT); role, status, session liveness, and MFA freshness come from `public.auth_context()` on every request. `getSession()` is never used for authorization (static test, T-AUTH-13).
- Every page and server action calls a guard from `src/server/auth/guards.ts` (`requireUser`, `requireClient`, `requireStaff({ fresh })`, `requireOwner`, `requireProjectAccess`). A static test fails if an exported server action has no guard (T-TEN-04).
- RLS applies to every table. Security-definer code lives in the unexposed `private` schema with `search_path = ''`; the app calls `public` SECURITY INVOKER wrappers.
- The secret-key client is importable only from `src/server/**` (ESLint rule and static test).
- Security events are written only through `recordSecurityEvent` (secret key, verified actor). No API role, client or staff, can execute an audit-writing function (`supabase/tests/050_security_events.test.sql`).

**Boundaries** (enforced by ESLint `no-restricted-imports`):
- `components`, `design`, and `domain` must not import `@/server/*`, `@/config/env`, or `server-only`. Server data flows in from server components.
- `app`, `lib`, `config`, and `proxy.ts` must not import `@/server/supabase/admin` (spec 03 §10).
- `domain` stays free of framework and I/O code, so business rules remain portable and unit-testable (spec 02 §1).

**Design tokens.** `src/design/tokens.ts` is the source of truth. `src/app/globals.css` mirrors it in the Tailwind `@theme` block. `tests/unit/tokens.test.ts` fails if the two drift, or if any approved text pair drops below 4.5:1 or any UI pair below 3:1.

**Theme.** Dark-only for the MVP (OI-48). Components use semantic token utilities only. `tests/unit/brand.test.ts` rejects hard-coded color literals in `src/app` and `src/components`, so a light theme can later be added by redefining token values.

**Logo handling (OI-49, temporary).** The Owner-confirmed master (`public/brand/spotlight-marketing-logo.jpg`, SHA-256 `6cc6edb3…b2bd3c`) is a JPEG on a black field. It is rendered at its intrinsic 597:335 ratio and composited with:
- `mix-blend-mode: screen`, so the black field takes the page color
- a horizontal edge fade over the outer 4–5% of the width, which hides the master's cropped glow edge

The artwork itself is not modified, and a unit test pins the master's SHA-256. An Owner-approved transparent and vector master (DEP-08) would remove the need for both treatments.

## 7. Future integration boundaries

| Integration | Where | Phase |
|---|---|---|
| Supabase Auth, Postgres/RLS, Storage (local) | `src/server/supabase/*`, server-only | 2 (implemented) |
| Hosted Supabase projects | Owner-controlled (DEP-14) | Not authorized |
| Stripe (test mode), webhooks, ledger | `src/server/stripe/*`, `src/domain/billing/*` | 3 (DEP-01 blocked) |
| Resend, outbox, upload scanning | `src/server/*`, `src/domain/*` | 4 |
| Vercel projects, DNS, production | Owner-controlled infrastructure | 5 and production authorization |

## 8. Known follow-ups and deferred items

| Item | Reason | When |
|---|---|---|
| Phase 2 implementation notes (**OI-53**, approved 2026-11-23) | Approved with N-8 amended: security events are recorded only by the server (`service_role`) with a verified actor and bounded payloads | Done |
| Marking expired invitations (**OI-54**, decided) | Deferred on condition: expired invitations must stay rejected at every boundary regardless of cleanup status (`supabase/tests/045_expired_invitations.test.sql`) | Phase 5 |
| Invitation emails to existing users | Supabase cannot email confirmed users (03A S-06); they accept in the portal. Notification email needs Resend. | Phase 4 |
| Switch required checks to `CI result` (DEP-16) | GitHub ruleset change (Owner) | Immediately after the governance correction PR merges |
| ESLint 10 upgrade | Waiting on plugin peer support | When `eslint-config-next` dependencies support it |
| Favicon and app icons | No Owner-approved icon asset. The page declares an empty icon to avoid 404s. | DEP-08 |
| Light theme | Dark-only for the MVP (**OI-48 approved**). Token-only colors keep a future light theme possible. | Needs an approved logo variant (DEP-08) |
| Logo compositing | Temporary treatment (**OI-49 approved**). Remove when a transparent or vector master exists. | DEP-08 |
| Monitoring and RUM vendor | Spec 02 §8 | DEP-12 |
