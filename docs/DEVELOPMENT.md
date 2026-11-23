# Development Guide

| Field | Value |
|---|---|
| Applies to | Phase 1: Foundation and CI (authorized 2026-11-23) |
| Specifications | [01](01-PROJECT-OVERVIEW.md), [02](02-ARCHITECTURE-AND-ENVIRONMENTS.md), [CLAUDE.md](../CLAUDE.md) |

Read [CLAUDE.md](../CLAUDE.md) first. Only Phase 1 is authorized. No external service (Supabase, Stripe, Resend, Vercel) is connected, and none may be connected without separate written Owner authorization.

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

# 4. Configure the environment (names only in .env.example; no secrets needed in Phase 1)
cp .env.example .env.local

# 5. Run
pnpm dev                  # http://localhost:3000
```

Playwright needs a browser: run `pnpm exec playwright install chromium` once. If your machine already provides a compatible Chromium, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to its path.

## 3. Commands

| Command | Purpose |
|---|---|
| `pnpm dev` | Development server with fast refresh |
| `pnpm build` / `pnpm start` | Production build and server |
| `pnpm lint` | ESLint (zero warnings allowed) |
| `pnpm typecheck` | Strict TypeScript, no emit |
| `pnpm format` / `pnpm format:check` | Prettier write / verify |
| `pnpm test` | Vitest unit and component tests |
| `pnpm test:e2e` | Playwright smoke tests against the production build (run `pnpm build` first) |
| `pnpm check:bundle` | Scans browser-delivered build output for secrets (T-SEC-01) |
| `pnpm lhci` | Lighthouse CI with the spec 02 §7 budgets (run `pnpm build` first) |
| `pnpm verify` | Everything above, except Lighthouse, in CI order |

## 4. Environments and configuration

Configuration is validated at startup and build time by `src/config/env-schema.ts`. **Invalid configuration fails closed.**

| Variable | Phase | Rule |
|---|---|---|
| `APP_ENV` | 1 | One of `development`, `test`, `preview`, `staging`, `production` |
| `NEXT_PUBLIC_SITE_URL` | 1 | Absolute http(s) URL of the deployment |
| `STRIPE_SECRET_KEY` | 3 (not used yet) | If present, a live-mode key outside `production` fails validation (spec 02 §4 rule 2) |
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

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`. All jobs run in parallel, with read-only permissions and no credentials.

| Job | Checks |
|---|---|
| Lint, types, format, unit tests | Frozen-lockfile install, ESLint, `tsc`, Prettier, Vitest |
| Build, client bundle check, Playwright smoke tests | Production build, secret scan of `.next/static`, Playwright on desktop and mobile Chromium, including axe WCAG 2.2 AA, security headers, logo aspect ratio, reduced motion, responsive overflow |
| Lighthouse budgets | 3 mobile runs. Median must reach Performance ≥ 0.90, Accessibility ≥ 0.95, Best Practices ≥ 0.95, SEO ≥ 0.90. Reports kept as a run artifact only. |
| Dependency audit | `pnpm audit --audit-level=high` |
| Secret scan | gitleaks over full git history (checksum-verified binary) |

**Branch protection.** The `protect-main` ruleset requires pull requests. Adding these jobs as *required status checks* is a GitHub settings change for the Owner (DEP-10 follow-up), once the jobs have run successfully on the Phase 1 pull request.

**Checks that cannot run yet:**
- Field Core Web Vitals (RUM): requires a deployed environment and a monitoring vendor (DEP-12).
- p95 read latency: requires the Phase 2+ data layer.

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
  domain/         Business rules. Empty in Phase 1. See README.
  server/         External-service adapters. Empty in Phase 1. See README.
  lib/            Small shared utilities
tests/
  unit/           Vitest (node; jsdom per file where needed)
  e2e/            Playwright smoke tests
scripts/          CI helper scripts
```

**Boundaries** (enforced by ESLint `no-restricted-imports`):
- `components`, `design`, and `domain` must not import `@/server/*`, `@/config/env`, or `server-only`. Server data flows in from server components.
- `domain` stays free of framework and I/O code, so business rules remain portable and unit-testable (spec 02 §1).

**Design tokens.** `src/design/tokens.ts` is the source of truth. `src/app/globals.css` mirrors it in the Tailwind `@theme` block. `tests/unit/tokens.test.ts` fails if the two drift, or if any approved text pair drops below 4.5:1 or any UI pair below 3:1.

**Logo handling.** The Owner-confirmed master (`public/brand/spotlight-marketing-logo.jpg`, SHA-256 `6cc6edb3…b2bd3c`) is a JPEG on a black field. It is rendered at its intrinsic 597:335 ratio and composited with:
- `mix-blend-mode: screen`, so the black field takes the page color
- a horizontal edge fade over the outer 4–5% of the width, which hides the master's cropped glow edge

The artwork itself is not modified. An Owner-approved transparent and vector master (DEP-08) would remove the need for both treatments.

## 7. Future integration boundaries

| Integration | Where | Phase |
|---|---|---|
| Supabase Auth, Postgres/RLS, Storage | `src/server/supabase/*`, server-only | 2 |
| Stripe (test mode), webhooks, ledger | `src/server/stripe/*`, `src/domain/billing/*` | 3 (DEP-01 blocked) |
| Resend, outbox, upload scanning | `src/server/*`, `src/domain/*` | 4 |
| Vercel projects, DNS, production | Owner-controlled infrastructure | 5 and production authorization |

## 8. Known follow-ups and deferred items

| Item | Reason | When |
|---|---|---|
| Nonce-based Content-Security-Policy | Next.js inline bootstrap scripts currently need `'unsafe-inline'`. A nonce policy needs per-request handling. | Phase 2 |
| Add CI jobs as required status checks | GitHub ruleset change (Owner) | After the Phase 1 PR's first successful run |
| ESLint 10 upgrade | Waiting on plugin peer support | When `eslint-config-next` dependencies support it |
| Favicon and app icons | No Owner-approved icon asset. The page declares an empty icon to avoid 404s. | DEP-08 |
| Light theme | Only the dark theme is implemented; the logo master exists only on a black field | OI-48 (Owner decision) |
| Monitoring and RUM vendor | Spec 02 §8 | DEP-12 |
