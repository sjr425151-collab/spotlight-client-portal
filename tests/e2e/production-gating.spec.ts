import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

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

  test("the production build contains neither the billing-job runner nor any test support module (AUTH-008 I-2)", () => {
    // Seam (a) is test harness only. Seam (b), `verifierFor`, ships in the build but selects the
    // stub only for an affirmative development/test classification (tests/unit/wpi-live-verifier.test.ts);
    // this server runs with APP_ENV=production, as the /design-system 404 below shows.
    const root = ".next-production";
    expect(existsSync(join(root, "server"))).toBe(true);
    const files = (dir: string): string[] =>
      readdirSync(dir).flatMap((name) => {
        const path = join(dir, name);
        return statSync(path).isDirectory() ? files(path) : [path];
      });
    const built = files(root).filter((f) => /\.(js|mjs|cjs|json|html|map)$/.test(f));
    expect(built.length).toBeGreaterThan(20);
    const offenders = built.filter((file) =>
      /wpi-billing-job-runner|billing-job-runner\.job|tests\/support\//.test(
        readFileSync(file, "utf8"),
      ),
    );
    expect(offenders).toEqual([]);
  });

  test("/design-system renders the branded 404 page in a browser", async ({ page }) => {
    const response = await page.goto("/design-system");
    expect(response?.status()).toBe(404);
    await expect(page.getByRole("heading", { level: 1 })).toHaveText(
      "This page could not be found.",
    );
  });
});
