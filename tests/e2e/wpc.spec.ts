import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Browser, type Page } from "@playwright/test";

import { withDb } from "../support/db";
import { clearMailbox, codeFrom, waitForEmail } from "../support/mailpit";
import { totp } from "../support/totp";

/**
 * WP-C pages in the states reachable without WP-B (CURRENT-STATE §9, WP-C directive item 7),
 * against the LOCAL Supabase stack with synthetic users. The full journey (T-E2E-01 to
 * T-E2E-10) belongs to the integration stream.
 *
 * - intake locked for an unpaid project (T-LC-01)
 * - the staff work queue (05 §9)
 * - recording a preview release (T-LC-15)
 * - upload type rejection (T-UP-01)
 * - cross-project denial for pages and asset URLs (T-UP-06, T-TEN-04)
 */
test.describe.configure({ mode: "serial" });

const ADMIN = "admin@example.test";
const CLIENT_A = "client.a@example.test";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
const RUN = Date.now().toString(36);

async function expectAccessible(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations.map(({ id, nodes }) => ({ id, count: nodes.length }))).toEqual([]);
}

async function signIn(page: Page, email: string) {
  await page.waitForTimeout(1100);
  await clearMailbox(email);
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Email me a sign-in code" }).click();
  await expect(page.locator("main").getByRole("status")).toContainText(
    "If this email belongs to a portal account",
  );
  await page.getByLabel("Sign-in code").fill(codeFrom(await waitForEmail(email)));
  await page.getByRole("button", { name: "Sign in" }).click();
}

async function newPage(browser: Browser) {
  return (await browser.newContext()).newPage();
}

/** Signs the Admin in at aal2, enrolling a TOTP factor for this run. */
async function adminPage(browser: Browser): Promise<Page> {
  await withDb((db) =>
    db.query("delete from auth.mfa_factors where user_id = '00000000-0000-4000-8000-000000000002'"),
  );
  const page = await newPage(browser);
  await signIn(page, ADMIN);
  await expect(page).toHaveURL(/\/mfa/);
  await page.getByRole("button", { name: "Set up authenticator app" }).click();
  const secret = (await page.locator("code").textContent())?.trim() ?? "";
  await page.getByLabel("Authenticator code").fill(totp(secret));
  await page.getByRole("button", { name: "Verify and continue" }).click();
  await expect(page).toHaveURL(/\/staff/);
  return page;
}

let clientPage: Page;
let staffPage: Page;
let releaseProjectId = "";

test.beforeAll(async ({ browser }) => {
  // A synthetic project whose intake staff have accepted (no client member).
  releaseProjectId = await withDb(async (db) => {
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, false)`,
      [OWNER_ID],
    );
    const business = await db.query(
      `insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id`,
      [`E2E WP-C ${RUN} LLC`],
    );
    const project = await db.query(
      `insert into public.projects (client_business_id, name) values ($1, $2) returning id`,
      [business.rows[0].id, `E2E release project ${RUN}`],
    );
    const id = project.rows[0].id as string;
    const intake = await db.query(
      `insert into public.intake_submissions (project_id, version, status, content, created_by, submitted_by, submitted_at)
       values ($1, 1, 'submitted', '{}', $2, $2, now()) returning id`,
      [id, OWNER_ID],
    );
    await db.query(
      `insert into public.intake_reviews (project_id, submission_id, decision, reviewed_by) values ($1, $2, 'accepted', $3)`,
      [id, intake.rows[0].id, "00000000-0000-4000-8000-000000000002"],
    );
    await db.query("delete from private.rate_limits");
    return id;
  });
  clientPage = await newPage(browser);
  await signIn(clientPage, CLIENT_A);
  await expect(clientPage).toHaveURL(/\/portal$/);
  staffPage = await adminPage(browser);
});

test.afterAll(async () => {
  await clientPage?.context().close();
  await staffPage?.context().close();
});

test("an unpaid project shows intake locked, with no intake form or uploads (T-LC-01)", async () => {
  await clientPage.goto(`/portal/projects/${PROJECT_A}`);
  await expect(clientPage.getByTestId("project-status")).toContainText(
    "Available once your deposit and saved payment method are verified",
  );
  await expect(clientPage.getByRole("button", { name: "Submit for review" })).toHaveCount(0);
  await expect(clientPage.getByRole("button", { name: "Upload" })).toHaveCount(0);
  await expectAccessible(clientPage);
});

test("an upload of a disallowed type is rejected by the server (T-UP-01)", async () => {
  const response = await clientPage.request.post(`/portal/projects/${PROJECT_A}/uploads`, {
    multipart: {
      category: "logo",
      file: {
        name: "tool.exe",
        mimeType: "application/x-msdownload",
        buffer: Buffer.from("MZ\x90\x00"),
      },
    },
    maxRedirects: 0,
  });
  expect(response.status()).toBe(303);
  expect(response.headers().location).toContain("error=type_not_allowed");
  await clientPage.goto(response.headers().location!);
  await expect(clientPage.locator("main").getByRole("alert")).toContainText(
    "That file type is not allowed for this category.",
  );
});

test("client A is denied Project B's page and asset URLs, and the staff area (T-UP-06)", async () => {
  const page = await clientPage.goto(`/portal/projects/${PROJECT_B}`);
  expect(page?.status()).toBe(404);
  const asset = await clientPage.request.get(
    `/portal/projects/${PROJECT_B}/assets/00000000-0000-4000-8000-00000000000b`,
    { maxRedirects: 0 },
  );
  expect(asset.status()).toBe(404);
  const ownAsset = await clientPage.request.get(
    `/portal/projects/${PROJECT_A}/assets/00000000-0000-4000-8000-00000000000a`,
    { maxRedirects: 0 },
  );
  expect(ownAsset.status()).toBe(404);
  const upload = await clientPage.request.post(`/portal/projects/${PROJECT_B}/uploads`, {
    multipart: {
      category: "logo",
      file: { name: "x.png", mimeType: "image/png", buffer: Buffer.from("x") },
    },
    maxRedirects: 0,
  });
  expect(upload.status()).toBe(404);
  await clientPage.goto(`/staff/projects/${PROJECT_A}`);
  await expect(clientPage).toHaveURL(/\/portal$/);
});

test("the staff work queue renders derived items (05 §9)", async () => {
  await staffPage.goto("/staff/queue");
  await expect(staffPage.getByRole("heading", { name: "Work queue" })).toBeVisible();
  await expect(staffPage.getByRole("heading", { name: "In development" })).toBeVisible();
  await expect(staffPage.getByRole("link", { name: `E2E release project ${RUN}` })).toBeVisible();
  await expectAccessible(staffPage);
});

test("staff record a preview release with SHA, deployment ID, and preview URL (T-LC-15)", async () => {
  await staffPage.goto(`/staff/projects/${releaseProjectId}`);
  await staffPage.getByLabel("Commit SHA (40 characters)").fill("a".repeat(40));
  await staffPage.getByLabel("Deployment ID").fill(`dpl_${RUN}`);
  await staffPage.getByLabel("Protected preview URL").fill("https://preview.example.test/build");
  await staffPage.getByRole("button", { name: "Release preview to client" }).click();
  await expect(staffPage.locator("main").getByRole("status").first()).toContainText(
    "The preview was released to the client.",
  );
  await expect(staffPage.getByText(`Release 1 · ${"a".repeat(12)} · current`)).toBeVisible();
  await expectAccessible(staffPage);
});
