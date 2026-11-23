import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Browser, type Page } from "@playwright/test";

import { clearMailbox, codeFrom, linkFrom, messageCount, waitForEmail } from "../support/mailpit";
import { totp } from "../support/totp";

/**
 * Phase 2 end-to-end flows against the LOCAL Supabase stack with synthetic users
 * (supabase/seed.sql). Emails are read from the local Mailpit; nothing leaves the machine.
 */
test.describe.configure({ mode: "serial" });

const OWNER = "owner@example.test";
const ADMIN = "admin@example.test";
const CLIENT_A = "client.a@example.test";
const RUN = Date.now().toString(36);

declare global {
  interface Window {
    __cspViolations: string[];
  }
}

/** Records every CSP violation the browser reports (T-SEC-04). */
async function watchCsp(page: Page) {
  await page.addInitScript(() => {
    window.__cspViolations = [];
    document.addEventListener("securitypolicyviolation", (event) => {
      window.__cspViolations.push(`${event.violatedDirective} ${event.blockedURI}`);
    });
  });
}

async function expectAccessible(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations.map(({ id, nodes }) => ({ id, count: nodes.length }))).toEqual([]);
}

async function expectNoCspViolations(page: Page) {
  expect(await page.evaluate(() => window.__cspViolations)).toEqual([]);
}

async function signIn(page: Page, email: string) {
  // Supabase allows one code email per address per second locally (auth.email.max_frequency).
  await page.waitForTimeout(1100);
  await clearMailbox(email);
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(email);
  await page.getByRole("button", { name: "Email me a sign-in code" }).click();
  await expect(page.locator("main").getByRole("status")).toContainText(
    "If this email belongs to a portal account",
  );
  const code = codeFrom(await waitForEmail(email));
  await page.getByLabel("Sign-in code").fill(code);
  await page.getByRole("button", { name: "Sign in" }).click();
}

async function newPage(browser: Browser) {
  const context = await browser.newContext();
  const page = await context.newPage();
  await watchCsp(page);
  return page;
}

let ownerTotpSecret = "";

test("CSP uses a fresh nonce per response and no unsafe-inline (T-SEC-03)", async ({ page }) => {
  await watchCsp(page);
  const first = await page.goto("/sign-in");
  const second = await page.request.get("/sign-in");
  const cspA = first!.headers()["content-security-policy"]!;
  const cspB = second.headers()["content-security-policy"]!;
  const nonceA = /'nonce-([^']+)'/.exec(cspA)?.[1];
  const nonceB = /'nonce-([^']+)'/.exec(cspB)?.[1];
  expect(nonceA).toBeTruthy();
  expect(nonceA).not.toBe(nonceB);
  expect(cspA).toContain("'strict-dynamic'");
  expect(cspA).not.toContain("unsafe-inline");

  // Every script on the page carries this response's nonce.
  const scripts = await page
    .locator("script")
    .evaluateAll((nodes) => nodes.map((node) => (node as HTMLScriptElement).nonce));
  expect(scripts.length).toBeGreaterThan(0);
  for (const nonce of scripts) expect(nonce).toBe(nonceA);
  // No inline style attributes in the server HTML (style-src has no 'unsafe-inline').
  expect(await second.text()).not.toMatch(/<[^>]+\sstyle="/);
  await expectAccessible(page);
  await expectNoCspViolations(page);
});

test("private pages are never cached and require sign-in (T-SEC-06)", async ({ page }) => {
  const signIn = await page.request.get("/sign-in");
  expect(signIn.headers()["cache-control"]).toBe("private, no-store");
  const portal = await page.request.get("/portal", { maxRedirects: 0 });
  expect([303, 307]).toContain(portal.status());
  expect(portal.headers()["location"]).toContain("/sign-in");
  const staff = await page.request.get("/staff", { maxRedirects: 0 });
  expect(staff.headers()["location"]).toContain("/sign-in");
});

test("unknown emails get the generic response and no email (T-AUTH-01)", async ({ page }) => {
  const stranger = `stranger.${RUN}@example.test`;
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(stranger);
  await page.getByRole("button", { name: "Email me a sign-in code" }).click();
  await expect(page.locator("main").getByRole("status")).toContainText(
    "If this email belongs to a portal account",
  );
  await page.waitForTimeout(1000);
  expect(await messageCount(stranger)).toBe(0);
});

test("a wrong code is rejected", async ({ page }) => {
  await clearMailbox(CLIENT_A);
  await page.goto("/sign-in");
  await page.getByLabel("Email").fill(CLIENT_A);
  await page.getByRole("button", { name: "Email me a sign-in code" }).click();
  const real = codeFrom(await waitForEmail(CLIENT_A));
  await page.getByLabel("Sign-in code").fill(real === "000000" ? "111111" : "000000");
  await page.getByRole("button", { name: "Sign in" }).click();
  await expect(page.locator("main").getByRole("alert")).toContainText("That code did not work");
});

test("a client signs in with an email code and sees only their own project", async ({ page }) => {
  await watchCsp(page);
  await signIn(page, CLIENT_A);
  await expect(page).toHaveURL(/\/portal$/);
  const projects = page.getByTestId("project-list");
  await expect(projects).toContainText("Project A website");
  await expect(projects).not.toContainText("Project B website");
  await expectAccessible(page);

  // Cookies are HttpOnly: page scripts cannot read the session (spec 03 §6.2).
  expect(await page.evaluate(() => document.cookie)).not.toContain("sb-");
  const cookies = await page.context().cookies();
  const auth = cookies.filter((cookie) => cookie.name.startsWith("sb-"));
  expect(auth.length).toBeGreaterThan(0);
  for (const cookie of auth) expect(cookie.httpOnly).toBe(true);

  const response = await page.request.get("/portal");
  expect(response.headers()["cache-control"]).toBe("private, no-store");

  // A client cannot reach the staff area.
  await page.goto("/staff");
  await expect(page).toHaveURL(/\/portal$/);
  // Project B's staff page is not reachable either (T-TEN-04).
  await page.goto("/staff/projects/20000000-0000-4000-8000-0000000000b0");
  await expect(page).toHaveURL(/\/portal$/);
  await expectNoCspViolations(page);

  await page.getByRole("button", { name: "Sign out" }).click();
  await expect(page).toHaveURL(/\/sign-in\?notice=signed_out/);
  await page.goto("/portal");
  await expect(page).toHaveURL(/\/sign-in$/);
});

test("staff must enroll TOTP and reach aal2 before the staff area (T-AUTH-04)", async ({
  page,
}) => {
  await watchCsp(page);
  await signIn(page, OWNER);
  await expect(page).toHaveURL(/\/mfa/);
  await expect(page.getByRole("heading", { name: "Set up two-step verification" })).toBeVisible();

  // aal1 staff cannot load staff pages.
  await page.goto("/staff/team");
  await expect(page).toHaveURL(/\/mfa\?next=%2Fstaff%2Fteam/);

  await page.getByRole("button", { name: "Set up authenticator app" }).click();
  await expect(page.getByRole("img", { name: "QR code for your authenticator app" })).toBeVisible();
  await expectAccessible(page);
  const secret = (await page.locator("code").textContent())?.trim() ?? "";
  expect(secret).toMatch(/^[A-Z2-7]+=*$/);
  ownerTotpSecret = secret;
  await page.getByLabel("Authenticator code").fill(totp(secret));
  await page.getByRole("button", { name: "Verify and continue" }).click();
  await expect(page).toHaveURL(/\/staff\/team$/);
  await expect(page.getByTestId("staff-list")).toContainText(OWNER);
  await expectAccessible(page);
  await expectNoCspViolations(page);
});

test("an Admin at aal1 is held at MFA", async ({ browser }) => {
  const page = await newPage(browser);
  await signIn(page, ADMIN);
  await expect(page).toHaveURL(/\/mfa/);
  await page.goto("/staff");
  await expect(page).toHaveURL(/\/mfa/);
  await page.context().close();
});

test("staff invite a new client, who accepts with the emailed code (spec 03 §6.1)", async ({
  browser,
}) => {
  expect(ownerTotpSecret).not.toBe("");
  const owner = await newPage(browser);
  await signIn(owner, OWNER);
  await expect(owner).toHaveURL(/\/mfa/);
  await owner.getByLabel("Authenticator code").fill(totp(ownerTotpSecret));
  await owner.getByRole("button", { name: "Verify" }).click();
  await expect(owner).toHaveURL(/\/staff$/);

  const projectName = `E2E project ${RUN}`;
  await owner.getByLabel("Business legal name").fill(`E2E Business ${RUN} LLC`);
  await owner.getByLabel("Project name").fill(projectName);
  await owner.getByRole("button", { name: "Create project" }).click();
  await expect(owner.getByRole("heading", { name: projectName })).toBeVisible();

  const invitee = `invitee.${RUN}@example.test`;
  await clearMailbox(invitee);
  await owner.getByLabel("Full name").fill("E2E Invitee");
  await owner.getByLabel("Email").fill(invitee);
  await owner.getByRole("button", { name: "Send invitation" }).click();
  await expect(owner.locator("main").getByRole("status")).toContainText(
    "Invitation created and emailed",
  );
  await expect(owner.getByText(invitee)).toBeVisible();

  const email = await waitForEmail(invitee);
  const link = linkFrom(email);
  expect(link).toMatch(/\/invite\/accept\?id=[0-9a-f-]{36}&t=[A-Za-z0-9_-]{43}$/);

  const client = await newPage(browser);
  const accept = await client.goto(link);
  expect(accept!.headers()["cache-control"]).toBe("private, no-store");
  await client.getByLabel("Invitation code").fill(codeFrom(email));
  await client.getByRole("button", { name: "Accept invitation" }).click();
  await expect(client).toHaveURL(/\/portal\?notice=invitation_accepted/);
  await expect(client.getByTestId("project-list")).toContainText(projectName);
  await expect(client.getByTestId("project-list")).not.toContainText("Project A website");
  await expectNoCspViolations(client);

  // The link is single use (T-AUTH-06).
  const reuse = await newPage(browser);
  await reuse.goto(link);
  await expect(reuse.locator("main").getByRole("alert")).toContainText(
    "This invitation link is not valid",
  );

  // An existing client invited to the project accepts inside the portal (03A S-06).
  await owner.getByLabel("Full name").fill("Client A");
  await owner.getByLabel("Email").fill(CLIENT_A);
  await owner.getByRole("button", { name: "Send invitation" }).click();
  await expect(owner.locator("main").getByRole("status")).toContainText(
    "already has a portal account",
  );

  const clientA = await newPage(browser);
  await signIn(clientA, CLIENT_A);
  await expect(clientA).toHaveURL(/\/portal$/);
  await clientA.getByRole("button", { name: "Accept invitation" }).click();
  await expect(clientA).toHaveURL(/notice=invitation_accepted/);
  await expect(clientA.getByTestId("project-list")).toContainText(projectName);
  await expect(clientA.getByTestId("project-list")).toContainText("Project A website");

  // Removing the membership takes effect on the client's next request (T-AUTH-03).
  await owner.reload();
  const row = owner.getByRole("listitem").filter({ hasText: CLIENT_A });
  await row.getByRole("button", { name: "Remove from project" }).click();
  await expect(owner.locator("main").getByRole("status")).toContainText("Saved");
  await clientA.reload();
  await expect(clientA.getByTestId("project-list")).not.toContainText(projectName);

  // The audit log recorded the lifecycle.
  await owner.goto("/staff/audit");
  await expect(owner.getByRole("table")).toContainText("invitation.accepted");
  await expect(owner.getByRole("table")).toContainText("membership.revoked");
  await expectAccessible(owner);
  await expectNoCspViolations(owner);
});
