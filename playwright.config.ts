import { defineConfig, devices } from "@playwright/test";

const port = 3100;
const baseURL = `http://localhost:${port}`;

// Production-mode build (APP_ENV=production), created by `pnpm build:production-check`.
// Used only to verify production-only behavior. It is never deployed.
const productionPort = 3101;
const productionURL = `http://localhost:${productionPort}`;

// Local sandboxes may provide a preinstalled Chromium. CI installs browsers with
// `playwright install --with-deps chromium` and leaves this unset.
const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined;
const launchOptions = executablePath ? { executablePath } : {};

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  // Deterministic: no automatic retries that could mask flaky behavior.
  retries: 0,
  ...(process.env.CI ? { workers: 2 } : {}),
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL,
    trace: "off",
    screenshot: "only-on-failure",
  },
  projects: [
    {
      // Phase 2 auth flows need the local Supabase stack (`supabase start`); desktop only.
      name: "auth-setup",
      testMatch: /auth\.setup\.ts/,
    },
    {
      name: "auth",
      testMatch: /auth\.spec\.ts/,
      dependencies: ["auth-setup"],
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      // WP-C pages in the states reachable without WP-B; after the auth project so the two
      // never enroll MFA factors for the same seeded users at the same time.
      name: "wpc",
      testMatch: /wpc\.spec\.ts/,
      dependencies: ["auth"],
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      // WP-B agreement, mocked Checkout and synthetic signed webhook; after WP-C's project so
      // the two never enroll MFA factors for the same seeded Admin at the same time.
      name: "wpb",
      testMatch: /wpb\.spec\.ts/,
      dependencies: ["wpc"],
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      // WP-S Sales Representative area; after WP-B's project so no two projects enroll MFA
      // factors for the same seeded Owner at the same time.
      name: "wps",
      testMatch: /wps\.spec\.ts/,
      dependencies: ["wpb"],
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      name: "desktop-chromium",
      testIgnore: /production-gating|auth\.|wpc\.|wpb\.|wps\./,
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      name: "mobile-chromium",
      testIgnore: /production-gating|auth\.|wpc\.|wpb\.|wps\./,
      use: { ...devices["Pixel 7"], launchOptions },
    },
    {
      name: "production-gating",
      testMatch: /production-gating/,
      use: { ...devices["Desktop Chrome"], baseURL: productionURL, launchOptions },
    },
  ],
  webServer: [
    {
      // Test build created by `pnpm build` (APP_ENV=test).
      command: `pnpm exec next start --port ${port}`,
      url: baseURL,
      // WP-B (AUTH-001): the mocked Stripe gateway, the test-only agreement fixture, and a
      // webhook signing secret generated for this run (OI-63). The test build only: the
      // production-mode server below receives none of them, and its schema rejects the first two.
      env: {
        STRIPE_GATEWAY: "mock",
        AGREEMENT_TEST_FIXTURE: "enabled",
        ...(process.env.E2E_STRIPE_WEBHOOK_SECRET
          ? { STRIPE_WEBHOOK_SECRET: process.env.E2E_STRIPE_WEBHOOK_SECRET }
          : {}),
      },
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
    {
      // Production-mode build created by `pnpm build:production-check`.
      command: `pnpm exec next start --port ${productionPort}`,
      url: productionURL,
      env: {
        APP_ENV: "production",
        NEXT_DIST_DIR: ".next-production",
        NEXT_PUBLIC_SITE_URL: productionURL,
      },
      reuseExistingServer: !process.env.CI,
      timeout: 60_000,
    },
  ],
});
