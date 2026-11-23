import { expect, test } from "@playwright/test";

/**
 * Runs only against the production-mode build (APP_ENV=production, `pnpm
 * build:production-check`) served by the "production-gating" Playwright project.
 * Availability in non-production environments is covered by smoke.spec.ts (APP_ENV=test)
 * and by the per-environment unit tests in tests/unit/env-schema.test.ts.
 */
test.describe("production gating (APP_ENV=production)", () => {
  test("the production build is serving (control)", async ({ request }) => {
    const response = await request.get("/");
    expect(response.status()).toBe(200);
  });

  test("/design-system returns HTTP 404", async ({ request }) => {
    const response = await request.get("/design-system");
    expect(response.status()).toBe(404);
    expect(await response.text()).not.toContain("Internal reference");
  });

  test("/design-system renders the branded 404 page in a browser", async ({ page }) => {
    const response = await page.goto("/design-system");
    expect(response?.status()).toBe(404);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "This page could not be found.",
    );
  });
});
