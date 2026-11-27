import { randomUUID } from "node:crypto";

import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Browser, type Page } from "@playwright/test";

import { withDb } from "../support/db";
import { clearMailbox, codeFrom, messageCount, waitForEmail } from "../support/mailpit";
import { withSchemaCacheSync } from "../support/postgrest-sync";
import { totp } from "../support/totp";

/**
 * WP-S browser tests (WP-S directive item 10; 03 §4.1, §13), against the LOCAL Supabase stack
 * with synthetic users. Each step checks the authoritative database state and audit rows
 * behind what the browser shows, not just the page:
 * - forced MFA enrollment for a Sales Representative; /staff and /portal deny it (T-SALES-03,
 *   T-SALES-12)
 * - create a customer (atomic customer, project, and self-assignment; T-SALES-04)
 * - issue an order summary by package key with the derived scope (T-SALES-06, T-SALES-31)
 * - invite the client and resend as revoke and reissue (T-SALES-07, T-SALES-33)
 * - an unassigned project is a 404 (T-SALES-05)
 * - the Owner ends the assignment; the same signed-in session loses the project at once
 *   (T-SALES-14, T-SALES-26, T-SALES-28)
 */
test.describe.configure({ mode: "serial" });

const SALES = "sales@example.test";
const OWNER = "owner@example.test";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const RUN = Date.now().toString(36);
const LEGAL_NAME = `E2E WP-S ${RUN} LLC`;
const PROJECT_NAME = `E2E WP-S ${RUN} website`;
const CLIENT_EMAIL = `wps.client.${RUN}@example.test`;

let sales: Page;
let projectId = "";

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

async function enrollTotp(page: Page, home: RegExp) {
  await expect(page).toHaveURL(/\/mfa/);
  await page.getByRole("button", { name: "Set up authenticator app" }).click();
  const secret = (await page.locator("code").textContent())?.trim() ?? "";
  await page.getByLabel("Authenticator code").fill(totp(secret));
  await page.getByRole("button", { name: "Verify and continue" }).click();
  await expect(page).toHaveURL(home);
}

async function ownerPage(browser: Browser): Promise<Page> {
  await withDb((db) => db.query("delete from auth.mfa_factors where user_id = $1", [OWNER_ID]));
  const page = await (await browser.newContext()).newPage();
  await signIn(page, OWNER);
  await enrollTotp(page, /\/staff/);
  return page;
}

async function lastAudit(action: string) {
  const { rows } = await withDb((db) =>
    db.query(
      `select actor_user_id, actor_role, project_id, summary from public.audit_events
        where action = $1 order by id desc limit 1`,
      [action],
    ),
  );
  return rows[0];
}

test.beforeAll(async () => {
  await withDb(async (db) => {
    await db.query("delete from auth.mfa_factors where user_id = $1", [SALES_ID]);
    await db.query("delete from private.rate_limits where bucket like 'sales-%'");
  });
});

test("T-SALES-03 / T-SALES-12: a Sales Representative must enroll MFA and reaches only /sales", async ({
  browser,
}) => {
  sales = await (await browser.newContext()).newPage();
  await signIn(sales, SALES);
  // aal1: every route sends the representative to MFA enrollment first.
  await expect(sales).toHaveURL(/\/mfa\?next=%2Fsales/);
  await expect(sales.getByRole("heading", { name: "Set up two-step verification" })).toBeVisible();
  for (const path of ["/sales", "/staff", "/portal"]) {
    await sales.goto(path);
    await expect(sales, path).toHaveURL(/\/mfa/);
  }
  await enrollTotp(sales, /\/sales$/);
  const factors = await withDb((db) =>
    db.query(
      "select count(*)::int as n from auth.mfa_factors where user_id = $1 and status = 'verified'",
      [SALES_ID],
    ),
  );
  expect(factors.rows[0].n).toBe(1);

  // aal2: the staff area and the client portal still deny the representative.
  await sales.goto("/staff");
  await expect(sales).toHaveURL(/\/sales$/);
  await sales.goto("/staff/team");
  await expect(sales).toHaveURL(/\/sales$/);
  await sales.goto("/portal");
  await expect(sales).toHaveURL(/\/sales$/);
  await expect(sales.getByRole("heading", { name: "Your customers" })).toBeVisible();
  await expectAccessible(sales);
});

test("T-SALES-04: the representative creates a customer, project, and its own assignment", async () => {
  await sales.getByLabel("Business legal name").fill(LEGAL_NAME);
  await sales.getByLabel("Project name").fill(PROJECT_NAME);
  await sales.getByRole("button", { name: "Create customer" }).click();
  await expect(sales).toHaveURL(/\/sales\/projects\/[0-9a-f-]{36}\?notice=customer_created/);
  projectId = /projects\/([0-9a-f-]{36})/.exec(sales.url())![1]!;
  await expect(sales.getByRole("heading", { name: PROJECT_NAME })).toBeVisible();

  const { rows } = await withDb((db) =>
    db.query(
      `select p.created_by as project_by, b.created_by as business_by, b.legal_name,
              a.sales_user_id, a.assigned_by, a.active
         from public.projects p join public.client_businesses b on b.id = p.client_business_id
         join public.project_sales_assignments a on a.project_id = p.id
        where p.id = $1`,
      [projectId],
    ),
  );
  expect(rows).toEqual([
    {
      project_by: SALES_ID,
      business_by: SALES_ID,
      legal_name: LEGAL_NAME,
      sales_user_id: SALES_ID,
      assigned_by: SALES_ID,
      active: true,
    },
  ]);
  expect(await lastAudit("sales.customer_created")).toMatchObject({
    actor_user_id: SALES_ID,
    actor_role: "sales",
    project_id: projectId,
  });
  await expectAccessible(sales);
});

test("T-SALES-06 / T-SALES-31: the order summary takes the package key; pricing and scope are derived", async () => {
  // The form offers no scope, note, amount, or price field (OI-84(b)).
  for (const label of ["Scope", "Project notes", "Amount", "Price", "Discount"]) {
    await expect(sales.getByLabel(label, { exact: true })).toHaveCount(0);
  }
  await sales.getByLabel("Package").selectOption("professional");
  await sales.getByRole("button", { name: "Issue order summary" }).click();
  await expect(sales).toHaveURL(/notice=order_summary_issued/);
  const summary = sales.getByTestId("sales-order-summary");
  await expect(summary).toContainText("$1,495.00");
  await expect(summary).toContainText("$299.00");
  await expect(summary).toContainText("$1,196.00");
  await expect(summary).toContainText("TEST FIXTURE — NOT A DELIVERABLE");

  const { rows } = await withDb((db) =>
    db.query(
      `select package_key, package_total_cents, deposit_cents, balance_cents, maintenance_monthly_cents,
              scope_items, project_notes, issued_by
         from public.order_summaries where project_id = $1 and status = 'presented'`,
      [projectId],
    ),
  );
  const scope = await withDb((db) =>
    db.query(
      `select jsonb_agg(item_text order by position) as items from private.billing_package_scope
        where package_key = 'professional'
          and scope_version = (select max(scope_version) from private.billing_package_scope where package_key = 'professional')`,
    ),
  );
  expect(rows).toEqual([
    {
      package_key: "professional",
      package_total_cents: 149500,
      deposit_cents: 29900,
      balance_cents: 119600,
      maintenance_monthly_cents: 9900,
      scope_items: scope.rows[0].items,
      project_notes: null,
      issued_by: SALES_ID,
    },
  ]);
  expect((await lastAudit("order_summary.issued")).summary).toMatchObject({
    package_key: "professional",
    scope_version: 1,
  });
});

test("T-SALES-07 / T-SALES-33: invite the client, then resend as revoke and reissue", async () => {
  await sales.getByLabel("Full name").fill("WP-S Client");
  await sales.getByLabel("Email").fill(CLIENT_EMAIL);
  await sales.getByRole("button", { name: "Send invitation" }).click();
  await expect(sales).toHaveURL(/notice=invite_sent|notice=invite_existing_user/);
  const invitations = sales.getByTestId("sales-invitations");
  await expect(invitations).toContainText(CLIENT_EMAIL);

  const pending = async () =>
    (
      await withDb((db) =>
        db.query(
          "select id, created_by, status from public.invitations where email = $1 order by created_at",
          [CLIENT_EMAIL],
        ),
      )
    ).rows;
  const before = await pending();
  expect(before).toEqual([{ id: expect.any(String), created_by: SALES_ID, status: "pending" }]);
  expect(await lastAudit("invitation.created")).toMatchObject({
    actor_role: "sales",
    project_id: projectId,
  });

  await invitations.getByRole("button", { name: "Resend" }).click();
  await expect(sales).toHaveURL(/notice=invitation_resent/);
  const after = await pending();
  expect(after.map((r) => r.status)).toEqual(["revoked", "pending"]);
  expect(after[0]!.id).toBe(before[0]!.id);
  expect(after[1]!.id).not.toBe(before[0]!.id);
  expect(await lastAudit("invitation.revoked")).toMatchObject({
    actor_role: "sales",
    project_id: projectId,
  });
  await expectAccessible(sales);
});

test("T-SALES-05: an unassigned project is not found", async () => {
  const response = await sales.goto(`/sales/projects/${PROJECT_A}`);
  expect(response?.status()).toBe(404);
  const staffView = await sales.goto(`/staff/projects/${PROJECT_A}`);
  await expect(sales).toHaveURL(/\/sales$/);
  expect(staffView?.ok()).toBe(true);
  await expect(sales.getByTestId("sales-customers")).not.toContainText("Project A website");
});

test("T-SALES-24 (OI-85): the portal asset route refuses a Sales session holding an inconsistent membership", async () => {
  // Controlled local-only fixture: a separate project with an available upload and a Sales
  // membership, inserted with the C2 trigger disabled by name only inside that one transaction.
  const fixtureProject = randomUUID();
  const fixtureUpload = randomUUID();
  // The committed trigger toggle makes PostgREST reload its schema cache (pgrst_ddl_watch);
  // wait for that reload to finish before any request through PostgREST (AUTH-008 I-1).
  await withSchemaCacheSync(() =>
    withDb(async (db) => {
      await db.query("begin");
      await db.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ sub: OWNER_ID, role: "authenticated" }),
      ]);
      const business = await db.query(
        "insert into public.client_businesses (legal_name, display_name) values ($1, 'OI-85') returning id",
        [`OI-85 e2e ${RUN} LLC`],
      );
      await db.query(
        "insert into public.projects (id, client_business_id, name) values ($1, $2, 'OI-85 e2e site')",
        [fixtureProject, business.rows[0].id],
      );
      await db.query(
        `insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
         original_name, status, quarantine_path, released_path, size_bytes, sha256, released_sha256, released_bytes,
         completed_at, uploaded_by)
       values ($1, $2, gen_random_uuid(), 1, 'logo', 'image/png', 100, 'f.png', 'available', $3, $4, 100,
         repeat('3', 64), repeat('3', 64), 100, now(), $5)`,
        [
          fixtureUpload,
          fixtureProject,
          `quarantine/${fixtureProject}/${fixtureUpload}`,
          `${fixtureProject}/assets/${fixtureUpload}`,
          OWNER_ID,
        ],
      );
      await db.query(
        "alter table public.project_memberships disable trigger project_memberships_sales_separation",
      );
      await db.query(
        "insert into public.project_memberships (project_id, user_id) values ($1, $2)",
        [fixtureProject, SALES_ID],
      );
      await db.query(
        "alter table public.project_memberships enable trigger project_memberships_sales_separation",
      );
      await db.query("commit");
    }),
  );
  try {
    // Requested with the signed-in browser context's own cookies (a download route, not a page).
    const response = await sales.request.get(
      `/portal/projects/${fixtureProject}/assets/${fixtureUpload}`,
      { maxRedirects: 0 },
    );
    expect(response.status()).toBe(404);
    expect(response.headers()["content-disposition"]).toBeUndefined();
    // The portal page itself sends the representative to its own area (requireClient).
    await sales.goto(`/portal/projects/${fixtureProject}`);
    await expect(sales).toHaveURL(/\/sales$/);
    const { rows } = await withDb((db) =>
      db.query(
        "select count(*)::int as n from public.audit_events where action = 'upload.accessed' and target_id = $1",
        [fixtureUpload],
      ),
    );
    expect(rows[0].n).toBe(0);
  } finally {
    await withDb((db) =>
      db.query("delete from public.project_memberships where project_id = $1 and user_id = $2", [
        fixtureProject,
        SALES_ID,
      ]),
    );
  }
});

test("T-SALES-14 / T-SALES-26 / T-SALES-28: ending the assignment removes access from the open session", async ({
  browser,
}) => {
  const owner = await ownerPage(browser);
  await owner.goto("/staff/team");
  const row = owner.getByTestId("sales-assignments").locator("li", { hasText: PROJECT_NAME });
  await expect(row).toHaveCount(1);
  await row.getByRole("button", { name: "End assignment" }).click();
  await expect(owner).toHaveURL(/notice=assignment_ended/);
  await expect(
    owner.getByTestId("sales-assignments").locator("li", { hasText: PROJECT_NAME }),
  ).toHaveCount(0);

  const { rows } = await withDb((db) =>
    db.query(
      `select a.active, a.ended_by,
              (select array_agg(event order by id) from public.project_sales_assignment_history h where h.assignment_id = a.id) as history,
              (select issued_by from public.order_summaries o where o.project_id = a.project_id and o.status = 'presented') as issued_by
         from public.project_sales_assignments a where a.project_id = $1`,
      [projectId],
    ),
  );
  expect(rows).toEqual([
    { active: false, ended_by: OWNER_ID, history: ["created", "ended"], issued_by: SALES_ID },
  ]);
  expect(await lastAudit("sales_assignment.ended")).toMatchObject({
    actor_user_id: OWNER_ID,
    actor_role: "owner",
    project_id: projectId,
  });

  // The representative's existing, still-valid session: no sign-in again.
  const response = await sales.goto(`/sales/projects/${projectId}`);
  expect(response?.status()).toBe(404);
  await sales.goto("/sales");
  await expect(sales.getByTestId("sales-customers")).not.toContainText(PROJECT_NAME);

  // The invitation the representative sent stays pending for the agency (OI-78).
  await owner.goto(`/staff/projects/${projectId}`);
  await expect(owner.getByRole("main")).toContainText(CLIENT_EMAIL);
  const pending = await withDb((db) =>
    db.query(
      "select count(*)::int as n from public.invitations where email = $1 and status = 'pending'",
      [CLIENT_EMAIL],
    ),
  );
  expect(pending.rows[0].n).toBe(1);
});

// OI-95 (AUTH-012): the /sales customer list is accessible when empty and when populated. A fresh,
// isolated Sales Representative is created for this test only, so neither state depends on what
// earlier tests or suites did with the seeded representative. Each state runs the same WCAG scan
// as expectAccessible and checks that axe's `list` rule was evaluated (not skipped).
async function expectAccessibleWithListRule(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations.map(({ id, nodes }) => ({ id, count: nodes.length }))).toEqual([]);
  // The `list` rule ran on this page (it passed, or nothing on the page is a list); it was not skipped.
  expect([...results.passes, ...results.inapplicable].map((r) => r.id)).toContain("list");
}

test("OI-95: the customer list is accessible when empty and when populated", async ({
  browser,
}) => {
  const id = randomUUID();
  const email = `wps.oi95.${RUN}@example.test`;
  await withDb(async (db) => {
    await db.query(
      `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
         raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
         email_change_token_new, email_change, email_change_token_current, reauthentication_token,
         phone_change, phone_change_token)
       values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2, '', now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '')`,
      [id, email],
    );
    await db.query(
      "insert into public.profiles (id, email, full_name) values ($1, $2, 'OI-95 Sales')",
      [id, email],
    );
    await db.query("insert into public.staff_roles (user_id, role) values ($1, 'sales')", [id]);
  });
  const page = await (await browser.newContext()).newPage();
  await signIn(page, email);
  await enrollTotp(page, /\/sales$/);

  // Empty: the message is shown outside any list, and no list is rendered.
  const customers = page.getByTestId("sales-customers");
  await expect(customers).toContainText("No assigned customers yet.");
  await expect(customers.getByRole("list")).toHaveCount(0);
  await expectAccessibleWithListRule(page);

  // Populated: one customer of this representative, rendered as a list with one item.
  const projectName = `E2E OI-95 ${RUN} website`;
  await page.getByLabel("Business legal name").fill(`E2E OI-95 ${RUN} LLC`);
  await page.getByLabel("Project name").fill(projectName);
  await page.getByRole("button", { name: "Create customer" }).click();
  // As in T-SALES-04: the action finishes on the new project's page; then back to the list.
  await expect(page).toHaveURL(/\/sales\/projects\/[0-9a-f-]{36}\?notice=customer_created/);
  await page.goto("/sales");
  await expect(customers.getByRole("list")).toHaveCount(1);
  await expect(customers.getByRole("listitem")).toHaveCount(1);
  await expect(customers).toContainText(projectName);
  await expect(customers).not.toContainText("No assigned customers yet.");
  await expectAccessibleWithListRule(page);
});

// OI-88 option A (AUTH-017): a former client whose only membership was revoked is invited again.
// Supabase sends no email to an existing account (03A S-06), so the invitee accepts from
// /invitations, reached from the "No portal access" card. Fresh, isolated synthetic users: a
// Sales Representative (the inviter) and the former client, created as in the OI-95 test.
async function syntheticUser(email: string, fullName: string): Promise<string> {
  const id = randomUUID();
  await withDb(async (db) => {
    await db.query(
      `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
         raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
         email_change_token_new, email_change, email_change_token_current, reauthentication_token,
         phone_change, phone_change_token)
       values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2, '', now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '')`,
      [id, email],
    );
    await db.query("insert into public.profiles (id, email, full_name) values ($1, $2, $3)", [
      id,
      email,
      fullName,
    ]);
  });
  return id;
}

test("OI-88: a re-invited former client accepts from /invitations; without an invitation nothing can be accepted", async ({
  browser,
}) => {
  const formerEmail = `wps.oi88.former.${RUN}@example.test`;
  const formerId = await syntheticUser(formerEmail, "OI-88 Former Client");
  const salesEmail = `wps.oi88.sales.${RUN}@example.test`;
  const salesId = await syntheticUser(salesEmail, "OI-88 Sales");
  const oldProject = `E2E OI-88 ${RUN} old website`;
  await withDb(async (db) => {
    await db.query("insert into public.staff_roles (user_id, role) values ($1, 'sales')", [
      salesId,
    ]);
    // SYNTHETIC setup: the former client's earlier project, created as the seeded Owner, with
    // the membership already revoked (as staff do with revoke_membership).
    await db.query("begin");
    await db.query("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ sub: OWNER_ID, role: "authenticated", aal: "aal2" }),
    ]);
    const business = await db.query(
      "insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id",
      [`E2E OI-88 ${RUN} old LLC`],
    );
    const project = await db.query(
      "insert into public.projects (client_business_id, name) values ($1, $2) returning id",
      [business.rows[0].id, oldProject],
    );
    await db.query(
      `insert into public.project_memberships (project_id, user_id, status, revoked_at)
       values ($1, $2, 'revoked', now())`,
      [project.rows[0].id, formerId],
    );
    await db.query("commit");
  });

  // Without an invitation: the strict portal guard refuses, the card offers the invitations
  // page, and that page lists nothing and offers nothing to accept.
  const former = await (await browser.newContext()).newPage();
  await signIn(former, formerEmail);
  await expect(former).toHaveURL(/\/sign-in\?notice=no_active_project/);
  await expect(former.getByRole("heading", { name: "No portal access" })).toBeVisible();
  await expect(former.locator("main")).toContainText("open your invitations");
  await expectAccessible(former);
  await former.getByRole("link", { name: "Your invitations" }).click();
  await expect(former).toHaveURL(/\/invitations$/);
  await expect(former.getByTestId("no-invitations")).toBeVisible();
  await expect(former.getByRole("button", { name: "Accept invitation" })).toHaveCount(0);
  await expectAccessible(former);
  await former.goto("/portal");
  await expect(former).toHaveURL(/\/sign-in\?notice=no_active_project/);

  // The inviter: a new customer, then an invitation to the former client's existing account.
  const inviter = await (await browser.newContext()).newPage();
  await signIn(inviter, salesEmail);
  await enrollTotp(inviter, /\/sales$/);
  const newProject = `E2E OI-88 ${RUN} website`;
  await inviter.getByLabel("Business legal name").fill(`E2E OI-88 ${RUN} LLC`);
  await inviter.getByLabel("Project name").fill(newProject);
  await inviter.getByRole("button", { name: "Create customer" }).click();
  await expect(inviter).toHaveURL(/\/sales\/projects\/[0-9a-f-]{36}\?notice=customer_created/);
  const newProjectId = /projects\/([0-9a-f-]{36})/.exec(inviter.url())![1]!;
  await clearMailbox(formerEmail);
  await inviter.getByLabel("Full name").fill("OI-88 Former Client");
  await inviter.getByLabel("Email").fill(formerEmail);
  await inviter.getByRole("button", { name: "Send invitation" }).click();
  await expect(inviter).toHaveURL(/notice=invite_existing_user/);
  // The inviter's message is accurate: no email was sent, and it says where the invitee looks.
  const notice = inviter.locator("main").getByRole("status");
  await expect(notice).toContainText("no email was sent");
  await expect(notice).toContainText("Your invitations");
  expect(await messageCount(formerEmail)).toBe(0);
  await expectAccessible(inviter);

  // A staff role never uses the invitations page.
  await inviter.goto("/invitations");
  await expect(inviter).toHaveURL(/\/sales$/);

  // The former client accepts from /invitations and is a client of the new project only.
  await former.goto("/invitations");
  const list = former.getByTestId("invitation-list");
  await expect(list.getByRole("listitem")).toHaveCount(1);
  await expect(list).toContainText("You have been invited to a new project.");
  await expectAccessible(former);
  await list.getByRole("button", { name: "Accept invitation" }).click();
  await expect(former).toHaveURL(/\/portal\?notice=invitation_accepted/);
  await expect(former.getByTestId("project-list")).toContainText(newProject);
  await expect(former.getByTestId("project-list")).not.toContainText(oldProject);
  await expectAccessible(former);

  const { rows } = await withDb((db) =>
    db.query(
      `select i.status::text as invitation,
              (select count(*)::int from public.project_memberships m
                where m.user_id = $2 and m.status = 'active') as active_memberships,
              (select m.project_id::text from public.project_memberships m
                where m.user_id = $2 and m.status = 'active') as project
         from public.invitations i where i.project_id = $1 and i.email = $3`,
      [newProjectId, formerId, formerEmail],
    ),
  );
  expect(rows).toEqual([{ invitation: "accepted", active_memberships: 1, project: newProjectId }]);
  expect(await lastAudit("invitation.accepted")).toMatchObject({
    actor_user_id: formerId,
    project_id: newProjectId,
  });

  // Accepted: the invitations page is empty again.
  await former.goto("/invitations");
  await expect(former.getByTestId("no-invitations")).toBeVisible();
});
