import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

const WCAG_TAGS = ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"];

async function expectNoAccessibilityViolations(page: Page) {
  const results = await new AxeBuilder({ page }).withTags(WCAG_TAGS).analyze();
  expect(
    results.violations.map(({ id, impact, nodes }) => ({ id, impact, count: nodes.length })),
  ).toEqual([]);
}

function collectConsoleErrors(page: Page): string[] {
  const errors: string[] = [];
  page.on("console", (message) => {
    if (message.type() === "error") errors.push(message.text());
  });
  page.on("pageerror", (error) => errors.push(error.message));
  return errors;
}

test.describe("home page", () => {
  test("renders the branded foundation without errors", async ({ page }) => {
    const errors = collectConsoleErrors(page);
    const response = await page.goto("/");

    expect(response?.status()).toBe(200);
    await expect(page).toHaveTitle("Spotlight Marketing Client Portal");
    await expect(page.getByRole("heading", { level: 1 })).toContainText("Your website project");
    await expect(page.getByText("Access is by invitation")).toBeVisible();
    await expect(page.getByRole("list").getByRole("listitem")).toHaveCount(4);
    expect(errors).toEqual([]);
  });

  test("shows the official logo at its original aspect ratio (T-DES-04)", async ({ page }) => {
    await page.goto("/");
    const logo = page.getByRole("img", { name: "Spotlight Marketing" });
    await expect(logo).toBeVisible();

    const box = await logo.boundingBox();
    expect(box).not.toBeNull();
    const ratio = box!.width / box!.height;
    expect(ratio).toBeGreaterThan(597 / 335 - 0.02);
    expect(ratio).toBeLessThan(597 / 335 + 0.02);
  });

  test("has no WCAG 2.2 AA violations (T-DES-02)", async ({ page }) => {
    await page.goto("/");
    await expectNoAccessibilityViolations(page);
  });

  test("has no horizontal overflow (responsive layout)", async ({ page }) => {
    await page.goto("/");
    const overflow = await page.evaluate(
      () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
    );
    expect(overflow).toBeLessThanOrEqual(0);
  });

  test("sends the security headers (T-SEC-02)", async ({ page }) => {
    const response = await page.goto("/");
    const headers = response!.headers();
    expect(headers["content-security-policy"]).toContain("frame-ancestors 'none'");
    expect(headers["strict-transport-security"]).toContain("max-age=");
    expect(headers["x-content-type-options"]).toBe("nosniff");
    expect(headers["x-frame-options"]).toBe("DENY");
    expect(headers["referrer-policy"]).toBe("strict-origin-when-cross-origin");
    expect(headers["x-powered-by"]).toBeUndefined();
  });

  test("offers a keyboard skip link to the main content", async ({ page }) => {
    await page.goto("/");
    await page.keyboard.press("Tab");
    const skipLink = page.getByRole("link", { name: "Skip to content" });
    await expect(skipLink).toBeFocused();
    await expect(skipLink).toBeVisible();
  });
});

test.describe("reduced motion", () => {
  const countAnimated = (page: Page) =>
    page.evaluate(
      () =>
        Array.from(document.querySelectorAll("*")).filter((element) => {
          const style = getComputedStyle(element);
          return style.animationName !== "none" && parseFloat(style.animationDuration) > 0.01;
        }).length,
    );

  test("runs the decorative animation when motion is allowed (control)", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "no-preference" });
    await page.goto("/");
    expect(await countAnimated(page)).toBeGreaterThan(0);
  });

  test("disables decorative animation when the user prefers reduced motion (T-DES-03)", async ({
    page,
  }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/");
    expect(await countAnimated(page)).toBe(0);
  });
});

test.describe("design system reference (non-production only)", () => {
  test("renders the primitives accessibly", async ({ page }) => {
    const errors = collectConsoleErrors(page);
    const response = await page.goto("/design-system");
    expect(response?.status()).toBe(200);
    await expect(page.getByRole("heading", { level: 1, name: "Design system" })).toBeVisible();
    await expect(page.getByRole("textbox", { name: "Website" })).toHaveAttribute(
      "aria-invalid",
      "true",
    );
    await expectNoAccessibilityViolations(page);
    expect(errors).toEqual([]);
  });

  test("is excluded from indexing", async ({ page }) => {
    await page.goto("/design-system");
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
  });
});

test("unknown routes return the branded 404 page", async ({ page }) => {
  const response = await page.goto("/this-route-does-not-exist");
  expect(response?.status()).toBe(404);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("This page could not be found.");
});
