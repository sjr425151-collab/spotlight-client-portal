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
      name: "desktop-chromium",
      testIgnore: /production-gating/,
      use: { ...devices["Desktop Chrome"], launchOptions },
    },
    {
      name: "mobile-chromium",
      testIgnore: /production-gating/,
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
