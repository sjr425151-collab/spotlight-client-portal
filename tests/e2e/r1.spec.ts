import { createHmac, randomBytes } from "node:crypto";

import { expect, test, type Browser, type ConsoleMessage, type Page } from "@playwright/test";

import { runBillingJobsOnce } from "../support/billing-job-runner";
import { withDb } from "../support/db";
import {
  auditSince,
  countRows,
  expectAccessible,
  lastAuditId,
  newPage,
  signIn,
  staffPageAtAal2,
} from "../support/e2e";
import { clearMailbox, codeFrom, linkFrom, waitForEmail } from "../support/mailpit";
import { totp } from "../support/totp";

/**
 * Integrated R1 browser acceptance, T-E2E-01 to T-E2E-10 (01 §9.1.1; AUTH-008 I-2), as one
 * Sales-assisted journey on a fresh, isolated customer: Sales customer → order summary →
 * invitation → client acceptance → agreement → deposit (mocked gateway, synthetic signed
 * webhooks, OI-63) → card → intake → upload and mock scan → release → approval and automatic
 * final charge (billing-job runner, seam (a)) → fulfillment evidence → publication
 * authorization → deployment record and live verification (mock live verifier, seam (b)).
 *
 * LOCAL Supabase stack, synthetic users and data only; no Stripe or other provider request.
 * Every step also asserts the server-side outcome (database state and audit events), never
 * only the page. Counts are scoped to this run's fresh IDs (AUTH-008 I-2 disposition (iv)).
 * T-E2E-10's Lighthouse thresholds run in the CI Lighthouse job (lighthouserc.json).
 */
test.describe.configure({ mode: "serial" });

const SALES = "sales@example.test";
const ADMIN = "admin@example.test";
const OWNER = "owner@example.test";
const CLIENT_B = "client.b@example.test";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const CLIENT_B_ID = "00000000-0000-4000-8000-0000000000b1";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const RUN = `${Date.now().toString(36)}${randomBytes(2).toString("hex")}`;
const LEGAL_NAME = `E2E R1 ${RUN} LLC`;
const PROJECT_NAME = `E2E R1 ${RUN} website`;
const CLIENT_EMAIL = `r1.client.${RUN}@example.test`;
const SHA_1 =
  "1".repeat(32) +
  RUN.padEnd(8, "0")
    .slice(0, 8)
    .replace(/[^0-9a-f]/g, "e");
const SHA_2 =
  "2".repeat(32) +
  RUN.padEnd(8, "0")
    .slice(0, 8)
    .replace(/[^0-9a-f]/g, "e");
const SHA_OTHER = "f".repeat(40);
const APPROVE = "Approve Website & Authorize Final Payment";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function webhookSecret(): string {
  const secret = process.env.E2E_STRIPE_WEBHOOK_SECRET;
  // Never skipped (CLAUDE.md §3): without the run's secret the suite fails.
  if (!secret || !/^whsec_[A-Za-z0-9]+$/.test(secret)) {
    throw new Error("E2E_STRIPE_WEBHOOK_SECRET must be set to a test-only whsec_ value");
  }
  return secret;
}

/** A synthetic Stripe-format event signed with this run's test-only secret (OI-63). */
function signed(type: string, object: Record<string, unknown>) {
  const now = Math.floor(Date.now() / 1000);
  const body = JSON.stringify({
    id: `evt_r1${RUN}${randomBytes(5).toString("hex")}`,
    object: "event",
    type,
    api_version: "2026-09-30.endive",
    livemode: false,
    created: now,
    data: { object },
  });
  const v1 = createHmac("sha256", webhookSecret()).update(`${now}.${body}`, "utf8").digest("hex");
  return { body, header: `t=${now},v1=${v1}` };
}

async function deliver(page: Page, type: string, object: Record<string, unknown>) {
  const event = signed(type, object);
  const response = await page.request.post("/api/stripe/webhook", {
    data: event.body,
    headers: { "content-type": "application/json", "stripe-signature": event.header },
  });
  expect(response.status(), `${type} delivery`).toBe(200);
  return (await response.json()) as { received: boolean; duplicate: boolean };
}

/** Console errors per page; T-E2E-10 requires none on the journey's pages. */
const consoleErrors: string[] = [];
function watchConsole(page: Page, label: string) {
  page.on("console", (message: ConsoleMessage) => {
    if (message.type() === "error") consoleErrors.push(`${label}: ${message.text()}`);
  });
  page.on("pageerror", (error) => consoleErrors.push(`${label}: ${error.message}`));
}

const status = (page: Page) => page.locator("main").getByRole("status").first();

type Financial = {
  deposit: string;
  verified: boolean;
  ready: boolean;
  balance: string;
  balance_verified: boolean;
};
const financial = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select f.deposit_state::text as deposit, f.deposit_verified as verified,
              f.payment_authorization_ready as ready, f.final_balance_state::text as balance,
              f.balance_verified_or_settled as balance_verified
         from private.project_financial_status($1) f`,
      [projectId],
    );
    return rows[0] as Financial;
  });
const intakeUnlocked = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query("select private.wpc_intake_unlocked($1) as unlocked", [
      projectId,
    ]);
    return rows[0].unlocked as boolean;
  });
const failingGates = (projectId: string, releaseId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select coalesce(string_agg(g ->> 'gate' || ':' || coalesce(g ->> 'reason', ''), ',' order by g ->> 'gate'), '') as failing
         from jsonb_array_elements(private.evaluate_publication_gates($1, $2) -> 'gates') g
        where not (g ->> 'passed')::boolean`,
      [projectId, releaseId],
    );
    return rows[0].failing as string;
  });
const audited = async (since: string, action: string) =>
  (await auditSince(since)).filter((e) => e.action === action && e.project === projectId);

/** A minimal valid PNG; `text` goes in a tEXt chunk (unique bytes per upload). */
function png(text: string): Buffer {
  const u32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
  const chunk = (type: string, data: number[]) => [
    ...u32(data.length),
    ...[...type].map((c) => c.charCodeAt(0)),
    ...data,
    0,
    0,
    0,
    0,
  ];
  return Buffer.from([
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ...chunk("IHDR", [...u32(4), ...u32(4), 8, 6, 0, 0, 0]),
    ...chunk(
      "tEXt",
      [...text].map((c) => c.charCodeAt(0)),
    ),
    ...chunk("IEND", []),
  ]);
}
// The public EICAR anti-malware test string, which the mocked scanner flags (05 §5.5).
const EICAR = "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";

/** Owner TOTP reauthentication when an action requires a fresh check (03 §7). */
async function reauthenticateIfAsked(page: Page) {
  if (!/\/mfa\?reauth=1/.test(page.url())) return;
  // A new 30-second window, so the code differs from the last one Auth accepted.
  const window = Math.floor(Date.now() / 30_000);
  while (Math.floor(Date.now() / 30_000) === window) await page.waitForTimeout(500);
  await page.getByLabel("Authenticator code").fill(totp(ownerTotp));
  await page.getByRole("button", { name: "Verify" }).click();
  await expect(page).toHaveURL(/\/staff\/projects\//);
}

// ---------------------------------------------------------------------------
// State shared by the serial journey
// ---------------------------------------------------------------------------
let sales: Page;
let admin: Page;
let owner: Page;
let ownerTotp = "";
let client: Page;
let clientB: Page;
let projectId = "";
let clientId = "";
let release1 = "";
let release2 = "";
let validUpload = "";
let flaggedUpload = "";

test.beforeAll(async ({ browser }: { browser: Browser }) => {
  webhookSecret();
  await withDb((db) => db.query("delete from private.rate_limits"));
  ({ page: sales } = await staffPageAtAal2(browser, SALES, SALES_ID, /\/sales$/));
  ({ page: admin } = await staffPageAtAal2(browser, ADMIN, ADMIN_ID));
  ({ page: owner, totpSecret: ownerTotp } = await staffPageAtAal2(browser, OWNER, OWNER_ID));
  watchConsole(sales, "sales");
  watchConsole(admin, "admin");
  watchConsole(owner, "owner");
  clientB = await newPage(browser);
  await signIn(clientB, CLIENT_B);
  await expect(clientB).toHaveURL(/\/portal$/);
});

test.afterAll(async () => {
  for (const page of [sales, admin, owner, client, clientB]) await page?.context().close();
});

// ---------------------------------------------------------------------------
// T-E2E-01 Onboarding (Sales-assisted)
// ---------------------------------------------------------------------------
test("T-E2E-01: Sales creates the customer, issues the order summary and invites the client, who signs in with an email code", async ({
  browser,
}) => {
  const since = await lastAuditId();
  await sales.goto("/sales");
  await sales.getByLabel("Business legal name").fill(LEGAL_NAME);
  await sales.getByLabel("Project name").fill(PROJECT_NAME);
  await sales.getByRole("button", { name: "Create customer" }).click();
  await expect(sales).toHaveURL(/\/sales\/projects\/[0-9a-f-]{36}\?notice=customer_created/);
  projectId = /projects\/([0-9a-f-]{36})/.exec(sales.url())![1]!;

  await sales.getByLabel("Package").selectOption("professional");
  await sales.getByRole("button", { name: "Issue order summary" }).click();
  await expect(sales).toHaveURL(/notice=order_summary_issued/);
  await expect(sales.getByTestId("sales-order-summary")).toContainText("$1,495.00");

  await clearMailbox(CLIENT_EMAIL);
  await sales.getByLabel("Full name").fill("Riley Client");
  await sales.getByLabel("Email").fill(CLIENT_EMAIL);
  await sales.getByRole("button", { name: "Send invitation" }).click();
  await expect(sales).toHaveURL(/notice=invite_sent/);
  await expectAccessible(sales);

  // Server side: the customer, the Sales assignment, the order summary and the invitation.
  const { rows } = await withDb((db) =>
    db.query(
      `select p.created_by::text as project_by, a.sales_user_id::text as assigned, a.active,
              o.package_key, o.package_total_cents::int as total, o.deposit_cents::int as deposit,
              o.issued_by::text as issued_by, i.status::text as invitation, i.created_by::text as invited_by
         from public.projects p
         join public.project_sales_assignments a on a.project_id = p.id
         join public.order_summaries o on o.project_id = p.id and o.status = 'presented'
         join public.invitations i on i.project_id = p.id and i.email = $2
        where p.id = $1`,
      [projectId, CLIENT_EMAIL],
    ),
  );
  expect(rows).toEqual([
    {
      project_by: SALES_ID,
      assigned: SALES_ID,
      active: true,
      package_key: "professional",
      total: 149500,
      deposit: 29900,
      issued_by: SALES_ID,
      invitation: "pending",
      invited_by: SALES_ID,
    },
  ]);
  expect(
    (await auditSince(since))
      .filter((e) => e.project === projectId)
      .map((e) => e.action)
      .filter((a) =>
        ["sales.customer_created", "order_summary.issued", "invitation.created"].includes(a),
      ),
  ).toEqual(["sales.customer_created", "order_summary.issued", "invitation.created"]);

  // The client receives the invitation (Mailpit) and accepts it with the emailed code.
  const email = await waitForEmail(CLIENT_EMAIL);
  client = await newPage(browser);
  watchConsole(client, "client");
  await client.goto(linkFrom(email));
  await client.getByLabel("Invitation code").fill(codeFrom(email));
  await client.getByRole("button", { name: "Accept invitation" }).click();
  await expect(client).toHaveURL(/\/portal\?notice=invitation_accepted/);
  await expect(client.getByTestId("project-list")).toContainText(PROJECT_NAME);
  await expect(client.getByTestId("project-list")).not.toContainText("Project A website");

  const accepted = await withDb((db) =>
    db.query(
      `select u.id::text as id, i.status::text as invitation,
              exists (select 1 from public.project_memberships m where m.project_id = $1 and m.user_id = u.id) as member
         from auth.users u join public.invitations i on i.email = u.email and i.project_id = $1
        where u.email = $2 and i.status = 'accepted'`,
      [projectId, CLIENT_EMAIL],
    ),
  );
  expect(accepted.rows).toEqual([{ id: expect.any(String), invitation: "accepted", member: true }]);
  clientId = accepted.rows[0].id as string;

  // Later sign-ins use an emailed code as well.
  await client.context().clearCookies();
  await signIn(client, CLIENT_EMAIL);
  await expect(client).toHaveURL(/\/portal$/);
  await expect(client.getByTestId("project-list")).toContainText(PROJECT_NAME);
  await expectAccessible(client);
});

// ---------------------------------------------------------------------------
// T-E2E-02 Agreement and payment readiness
// ---------------------------------------------------------------------------
test("T-E2E-02: the client accepts the agreement and pays the deposit; only the signed webhook unlocks intake", async () => {
  await client.goto(`/portal/projects/${projectId}/billing`);
  await expect(client.getByText("$1,495.00").first()).toBeVisible();
  await expect(client.getByTestId("test-fixture-label").first()).toBeVisible();
  const accepted = client.getByLabel(/I have read and accept this agreement/);
  const authority = client.getByLabel(/I confirm that I am authorized/);
  await expect(accepted).not.toBeChecked();
  await expect(authority).not.toBeChecked();
  await expectAccessible(client);
  await client.getByLabel("Your full legal name").fill("Riley Client");
  await client.getByLabel("Business legal name").fill(LEGAL_NAME);
  await client.getByLabel("Your position or title").fill("Owner");
  await accepted.check();
  await authority.check();
  await client.getByRole("button", { name: "Accept agreement" }).click();
  await expect(status(client)).toContainText("Agreement accepted.");
  const acceptance = await withDb((db) =>
    db.query(
      `select signer_user_id::text as signer, business_name_matches from public.agreement_acceptances
        where project_id = $1`,
      [projectId],
    ),
  );
  expect(acceptance.rows).toEqual([{ signer: clientId, business_name_matches: true }]);

  await client.route("https://checkout.stripe.com/**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "text/html",
      body: '<!doctype html><html lang="en"><title>Intercepted</title><main><h1>Intercepted Stripe Checkout</h1></main></html>',
    }),
  );
  await client.getByRole("button", { name: "Pay $398.00 securely with Stripe" }).click();
  await expect(client).toHaveURL(/^https:\/\/checkout\.stripe\.com\/c\/pay\/cs_test_mock/);

  // The success redirect alone shows "processing" and leaves intake locked.
  await client.goto(`/portal/projects/${projectId}/billing?checkout=returned`);
  await expect(client.getByTestId("payment-status")).toContainText("Payment processing");
  await client.goto(`/portal/projects/${projectId}`);
  await expect(client.getByTestId("project-status")).toContainText(
    "Available once your deposit and saved payment method are verified",
  );
  expect(await financial(projectId)).toMatchObject({
    deposit: "pending",
    verified: false,
    ready: false,
  });
  expect(await intakeUnlocked(projectId)).toBe(false);

  const { session, customer } = await withDb(async (db) => {
    const s = await db.query(
      `select stripe_checkout_session_id as id, order_summary_id::text, acceptance_id::text, id::text as record_id
         from public.checkout_sessions where project_id = $1`,
      [projectId],
    );
    const c = await db.query(
      `select c.stripe_customer_id as id from public.stripe_customers c
         join public.projects p on p.client_business_id = c.client_business_id where p.id = $1`,
      [projectId],
    );
    return { session: s.rows[0], customer: c.rows[0].id as string };
  });
  expect(
    await deliver(client, "checkout.session.completed", {
      id: session.id,
      object: "checkout.session",
      mode: "subscription",
      currency: "usd",
      amount_total: 39800,
      payment_status: "paid",
      customer,
      subscription: `sub_r1${RUN}01`,
      invoice: `in_r1${RUN}01`,
      total_details: { amount_discount: 0, amount_tax: 0 },
      metadata: {
        project_id: projectId,
        order_summary_id: session.order_summary_id,
        acceptance_id: session.acceptance_id,
        checkout_record_id: session.record_id,
      },
    }),
  ).toEqual({ received: true, duplicate: false });
  expect(await financial(projectId)).toMatchObject({
    deposit: "verified",
    verified: true,
    ready: true,
  });
  expect(await intakeUnlocked(projectId)).toBe(true);
  const ledger = await withDb((db) =>
    db.query(
      `select entry_type::text, amount_cents::int as amount from public.ledger_entries
        where project_id = $1 order by id`,
      [projectId],
    ),
  );
  expect(ledger.rows).toEqual([
    { entry_type: "deposit_charge", amount: 29900 },
    { entry_type: "maintenance_charge", amount: 9900 },
  ]);
  await client.goto(`/portal/projects/${projectId}/billing`);
  await expect(client.getByTestId("payment-status")).toContainText("Received");
  await expect(client.getByTestId("payment-authorization")).toContainText(
    "Your card is saved for the final balance.",
  );
});

test("T-E2E-02: a verified deposit without a reusable card leaves intake locked", async () => {
  // A second fresh project for client B. Its Checkout session is recorded through the real
  // WP-B functions as client B, so the test server's mocked gateway holds no card for it: the
  // server's card lookup after the signed webhook finds none.
  const tag = `nocard${RUN}`;
  const ids = await withDb(async (db) => {
    const session = async (userId: string) =>
      (
        await db.query(
          `select id from auth.sessions where user_id = $1 order by created_at desc limit 1`,
          [userId],
        )
      ).rows[0].id as string;
    const as = async (userId: string, aal: string) =>
      db.query(
        `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated',
           'aal', $2::text, 'session_id', $3::text)::text, true)`,
        [userId, aal, await session(userId)],
      );
    await db.query("begin");
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, true)`,
      [OWNER_ID],
    );
    const business = await db.query(
      "insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id",
      [`E2E R1 ${tag} LLC`],
    );
    const project = await db.query(
      "insert into public.projects (client_business_id, name) values ($1, $2) returning id",
      [business.rows[0].id, `E2E R1 ${tag} website`],
    );
    const id = project.rows[0].id as string;
    await db.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
      id,
      CLIENT_B_ID,
    ]);
    await db.query("commit");
    await db.query("begin");
    await as(OWNER_ID, "aal2");
    await db.query("set local role authenticated");
    const os = await db.query(
      "select public.issue_order_summary($1, 'essential', '[]'::jsonb) as r",
      [id],
    );
    await db.query("commit");
    await db.query("begin");
    await as(CLIENT_B_ID, "aal1");
    await db.query("set local role authenticated");
    const acc = await db.query(
      "select public.accept_agreement($1, true, true, 'Bailey Client', $2, 'Owner', true) as r",
      [os.rows[0].r.order_summary_id, `E2E R1 ${tag} LLC`],
    );
    const cs = await db.query("select public.begin_initial_checkout($1) as r", [id]);
    await db.query("commit");
    await db.query("begin");
    await db.query(`select set_config('request.jwt.claims', '{"role":"service_role"}', true)`);
    await db.query("set local role service_role");
    const requests = await db.query(
      `select id, purpose from public.outbound_stripe_requests where project_id = $1
        order by (purpose = 'customer_create') desc`,
      [id],
    );
    for (const r of requests.rows) {
      // AUTH-009 (setup): claim, confirm with the one-time token, then record with it. The
      // token stays in memory and is never logged or asserted.
      const claim = await db.query(
        "select public.outbound_request_for_execution($1) ->> 'claim_token' as token",
        [r.id],
      );
      const token = (claim.rows[0] as { token: string | null }).token;
      await db.query("select public.confirm_outbound_dispatch($1, $2)", [r.id, token]);
      await db.query(
        r.purpose === "customer_create"
          ? `select public.record_outbound_result($1, $2, 'succeeded', $3, false, 200, null, '{}')`
          : `select public.record_outbound_result($1, $2, 'succeeded', $3, false, 200, null,
               jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/' || $3::text))`,
        [r.id, token, r.purpose === "customer_create" ? `cus_r1${tag}` : `cs_test_r1${tag}`],
      );
    }
    await db.query("commit");
    return {
      id,
      os: os.rows[0].r.order_summary_id as string,
      acceptance: acc.rows[0].r.acceptance_id as string,
      checkout: cs.rows[0].r.checkout_session_id as string,
    };
  });
  expect(ids.checkout).toMatch(/^[0-9a-f-]{36}$/);
  await deliver(clientB, "checkout.session.completed", {
    id: `cs_test_r1${tag}`,
    object: "checkout.session",
    mode: "subscription",
    currency: "usd",
    amount_total: 25900,
    payment_status: "paid",
    customer: `cus_r1${tag}`,
    subscription: `sub_r1${tag}`,
    invoice: `in_r1${tag}`,
    total_details: { amount_discount: 0, amount_tax: 0 },
    metadata: {
      project_id: ids.id,
      order_summary_id: ids.os,
      acceptance_id: ids.acceptance,
      checkout_record_id: ids.checkout,
    },
  });
  expect(await financial(ids.id)).toMatchObject({
    deposit: "verified",
    verified: true,
    ready: false,
  });
  expect(await intakeUnlocked(ids.id)).toBe(false);
  await clientB.goto(`/portal/projects/${ids.id}`);
  await expect(clientB.getByTestId("project-status")).toContainText(
    "Available once your deposit and saved payment method are verified",
  );
  await expect(clientB.getByRole("button", { name: "Submit for review" })).toHaveCount(0);
});

// ---------------------------------------------------------------------------
// T-E2E-03 Intake
// ---------------------------------------------------------------------------
test("T-E2E-03: intake save and resume, submit, changes requested, resubmit, accepted; another client is denied", async () => {
  await client.goto(`/portal/projects/${projectId}`);
  await client.getByLabel("Business legal name").fill(LEGAL_NAME);
  await client.getByLabel("Business display name").fill(`R1 ${RUN}`);
  await client.getByRole("button", { name: "Save and finish later" }).click();
  await expect(client).toHaveURL(/notice=intake_saved/);
  await client.reload();
  await expect(client.getByLabel("Business legal name")).toHaveValue(LEGAL_NAME);
  await expect(client.getByLabel("Business display name")).toHaveValue(`R1 ${RUN}`);
  const statuses = () =>
    withDb(
      async (db) =>
        (
          await db.query(
            "select version, status::text from public.intake_submissions where project_id = $1 order by version",
            [projectId],
          )
        ).rows,
    );
  // Saved, not submitted: one draft and nothing for staff to review.
  expect(await statuses()).toEqual([{ version: 1, status: "draft" }]);

  await client.getByLabel("Contact phone").fill("555-0100");
  await client.getByLabel("Contact email").fill(CLIENT_EMAIL);
  await client.getByLabel("Business address").fill("1 Test Street, Test City");
  await client.getByLabel("Service areas").fill("Test City");
  await client.getByLabel("Services offered").fill("Testing");
  await client.locator("select[name=domain_status]").selectOption("needs_domain");
  await expectAccessible(client);
  await client.getByRole("button", { name: "Submit for review" }).click();
  await expect(client).toHaveURL(/notice=intake_submitted/);
  expect(await statuses()).toEqual([{ version: 1, status: "submitted" }]);

  const since = await lastAuditId();
  await admin.goto(`/staff/projects/${projectId}`);
  await admin
    .getByLabel("Note to the client (required to request changes)")
    .fill("Please add a second phone number.");
  await admin.getByRole("button", { name: "Request changes" }).click();
  await expect(admin).toHaveURL(/notice=saved/);

  await client.goto(`/portal/projects/${projectId}`);
  await expect(client.locator("main")).toContainText(
    "Changes requested: Please add a second phone number.",
  );
  await client.getByLabel("Contact phone").fill("555-0100, 555-0101");
  await client.getByRole("button", { name: "Submit for review" }).click();
  await expect(client).toHaveURL(/notice=intake_submitted/);

  await admin.goto(`/staff/projects/${projectId}`);
  await admin.getByRole("button", { name: "Accept intake" }).click();
  await expect(admin).toHaveURL(/notice=saved/);
  await expectAccessible(admin);

  const intake = await withDb((db) =>
    db.query(
      `select s.version, s.status::text, s.content ->> 'contact_phone' as phone,
              (select r.decision::text from public.intake_reviews r where r.submission_id = s.id) as decision,
              (select r.reviewed_by::text from public.intake_reviews r where r.submission_id = s.id) as reviewer
         from public.intake_submissions s where s.project_id = $1 and s.status <> 'draft' order by s.version`,
      [projectId],
    ),
  );
  expect(intake.rows).toEqual([
    {
      version: 1,
      status: expect.any(String),
      phone: "555-0100",
      decision: "changes_requested",
      reviewer: ADMIN_ID,
    },
    {
      version: 2,
      status: expect.any(String),
      phone: "555-0100, 555-0101",
      decision: "accepted",
      reviewer: ADMIN_ID,
    },
  ]);
  const decisions = (await auditSince(since)).filter(
    (e) => e.project === projectId && e.action.startsWith("intake."),
  );
  expect(decisions.map((e) => e.actor)).toContain(ADMIN_ID);

  // Another project's client cannot reach this project's intake.
  const denied = await clientB.goto(`/portal/projects/${projectId}`);
  expect(denied?.status()).toBe(404);
  expect((await statuses()).filter((r) => r.status !== "draft")).toHaveLength(2);
});

// ---------------------------------------------------------------------------
// T-E2E-04 Uploads
// ---------------------------------------------------------------------------
test("T-E2E-04: a clean file becomes available; a flagged file is never served; a type mismatch is rejected by content; a guessed URL is denied", async () => {
  const upload = async (name: string, mimeType: string, buffer: Buffer) => {
    const response = await client.request.post(`/portal/projects/${projectId}/uploads`, {
      multipart: { category: "logo", file: { name, mimeType, buffer } },
      maxRedirects: 0,
    });
    expect(response.status()).toBe(303);
    return response.headers().location!;
  };
  const row = (name: string) =>
    withDb(async (db) => {
      const { rows } = await db.query(
        `select id::text, status::text, rejection_code from public.asset_uploads
          where project_id = $1 and original_name = $2`,
        [projectId, name],
      );
      return rows;
    });

  await upload(`logo-${RUN}.png`, "image/png", png(`r1 clean ${RUN}`));
  const clean = await row(`logo-${RUN}.png`);
  expect(clean).toEqual([{ id: expect.any(String), status: "available", rejection_code: null }]);
  validUpload = clean[0].id as string;
  const served = await client.request.get(`/portal/projects/${projectId}/assets/${validUpload}`, {
    maxRedirects: 0,
  });
  expect(served.status()).toBe(200);
  expect(served.headers()["content-type"]).toContain("image/png");

  await upload(`flagged-${RUN}.png`, "image/png", png(`${EICAR} ${RUN}`));
  const flagged = await row(`flagged-${RUN}.png`);
  expect(flagged).toEqual([
    { id: expect.any(String), status: "rejected", rejection_code: expect.any(String) },
  ]);
  flaggedUpload = flagged[0].id as string;
  const blocked = await client.request.get(
    `/portal/projects/${projectId}/assets/${flaggedUpload}`,
    {
      maxRedirects: 0,
    },
  );
  expect(blocked.status()).toBe(404);

  await upload(`fake-${RUN}.png`, "image/png", Buffer.from(`not a png ${RUN}`));
  const mismatch = await row(`fake-${RUN}.png`);
  expect(mismatch).toEqual([
    { id: expect.any(String), status: "rejected", rejection_code: expect.any(String) },
  ]);
  expect(mismatch[0].rejection_code).not.toBe(flagged[0].rejection_code);

  await client.goto(`/portal/projects/${projectId}`);
  const list = client.getByTestId("upload-list");
  await expect(list.locator("li", { hasText: `logo-${RUN}.png` })).toContainText("Ready");
  await expect(list.locator("li", { hasText: `flagged-${RUN}.png` })).toContainText("Rejected");
  await expect(list.locator("li", { hasText: `fake-${RUN}.png` })).toContainText("Rejected");
  await expect(
    list.locator("li", { hasText: `flagged-${RUN}.png` }).getByRole("link", { name: "Download" }),
  ).toHaveCount(0);
  await expectAccessible(client);

  // A guessed URL for another project's asset is denied, and nothing is recorded as served.
  const since = await lastAuditId();
  const guessed = await clientB.request.get(`/portal/projects/${projectId}/assets/${validUpload}`, {
    maxRedirects: 0,
  });
  expect(guessed.status()).toBe(404);
  const ownGuess = await clientB.request.get(
    `/portal/projects/${PROJECT_A}/assets/${validUpload}`,
    { maxRedirects: 0 },
  );
  expect(ownGuess.status()).toBe(404);
  expect((await auditSince(since)).filter((e) => e.action === "upload.accessed")).toEqual([]);
});

// ---------------------------------------------------------------------------
// T-E2E-05 Approval
// ---------------------------------------------------------------------------
test("T-E2E-05: staff release; a superseded release cannot be approved; a double submission creates one approval", async () => {
  const releaseAs = async (sha: string, n: number) => {
    await admin.goto(`/staff/projects/${projectId}`);
    await admin.getByLabel("Commit SHA (40 characters)").fill(sha);
    await admin.getByLabel("Deployment ID").fill(`dpl_r1_${RUN}_${n}`);
    await admin.getByLabel("Protected preview URL").fill(`https://preview-${n}.r1.example.test/`);
    await admin.getByRole("button", { name: "Release preview to client" }).click();
    await expect(status(admin)).toContainText("The preview was released to the client.");
  };
  await releaseAs(SHA_1, 1);
  await client.goto(`/portal/projects/${projectId}`);
  await expect(client.getByTestId("project-status")).toContainText(
    "Version 1 ready for your review",
  );
  await releaseAs(SHA_2, 2);
  await expect(admin.getByText(`Release 1 · ${SHA_1.slice(0, 12)} · superseded`)).toBeVisible();
  const releases = await withDb((db) =>
    db.query(
      `select id::text, release_number from public.preview_releases where project_id = $1 order by release_number`,
      [projectId],
    ),
  );
  expect(releases.rows.map((r) => r.release_number)).toEqual([1, 2]);
  release1 = releases.rows[0].id;
  release2 = releases.rows[1].id;

  await client.goto(`/portal/projects/${projectId}`);
  await expect(client.getByTestId("project-status")).toContainText(
    "Version 2 ready for your review",
  );
  await expect(client.getByTestId("final-balance-disclosure")).toBeVisible();
  await expectAccessible(client);

  // The superseded release: the approval form, pointed at release 1, is refused server-side.
  const form = client.locator("form", { has: client.getByRole("button", { name: APPROVE }) });
  await form
    .locator("input[name=releaseId]")
    .evaluate((el, id) => ((el as HTMLInputElement).value = id), release1);
  await form.getByLabel(/I have reviewed version 2 and approve it/).check();
  await form.getByRole("button", { name: APPROVE }).click();
  await expect(client).toHaveURL(/error=/);
  expect(await countRows("preview_approvals", projectId)).toBe(0);

  // Release 2, submitted twice at once: exactly one approval and one release.approved event.
  await client.goto(`/portal/projects/${projectId}`);
  const again = client.locator("form", { has: client.getByRole("button", { name: APPROVE }) });
  await again.getByLabel(/I have reviewed version 2 and approve it/).check();
  await again.evaluate((f) => {
    const formElement = f as HTMLFormElement;
    formElement.requestSubmit();
    formElement.requestSubmit();
  });
  await expect(client).toHaveURL(/notice=preview_approved|error=/);
  await expect.poll(() => countRows("preview_approvals", projectId), { timeout: 10_000 }).toBe(1);
  const approval = await withDb((db) =>
    db.query(
      `select a.release_id::text as release, a.user_id::text as client,
              (select count(*)::int from public.domain_events e where e.project_id = a.project_id
                 and e.event_type = 'release.approved') as events
         from public.preview_approvals a where a.project_id = $1`,
      [projectId],
    ),
  );
  expect(approval.rows).toEqual([{ release: release2, client: clientId, events: 1 }]);
  await client.goto(`/portal/projects/${projectId}`);
  await expect(client.getByTestId("project-status")).toContainText("Version 2 approved");
});

// ---------------------------------------------------------------------------
// T-E2E-06 Final balance
// ---------------------------------------------------------------------------
test("T-E2E-06: approval creates one final invoice and one automatic charge; an action-required charge shows the hosted link and blocks publication; invoice.paid verifies", async () => {
  const first = runBillingJobsOnce();
  expect(first.ok).toBe(true);
  expect(first.gatewayCalls.filter((m) => m === "invoices.create_finalize_send")).toHaveLength(1);
  const second = runBillingJobsOnce();
  expect(second.gatewayCalls.filter((m) => m === "invoices.create_finalize_send")).toHaveLength(0);

  const invoice = await withDb(async (db) => {
    const { rows } = await db.query(
      `select id::text, stripe_invoice_id, stripe_customer_id, order_summary_id::text, amount_cents::int as amount,
              collection_mode::text as mode, release_id::text as release, hosted_invoice_url,
              default_payment_method_id
         from public.final_balance_invoices where project_id = $1`,
      [projectId],
    );
    return rows;
  });
  expect(invoice).toEqual([
    expect.objectContaining({ amount: 119600, mode: "automatic", release: release2 }),
  ]);
  const fbi = invoice[0];
  expect(fbi.hosted_invoice_url).toMatch(/^https:\/\/invoice\.stripe\.com\//);
  expect(
    await withDb(
      async (db) =>
        (
          await db.query(
            `select count(*)::int as n from public.outbound_stripe_requests
            where project_id = $1 and purpose = 'final_balance_invoice_create'`,
            [projectId],
          )
        ).rows[0].n,
    ),
  ).toBe(1);

  const metadata = {
    project_id: projectId,
    order_summary_id: fbi.order_summary_id,
    final_balance_invoice_id: fbi.id,
  };
  const since = await lastAuditId();
  await deliver(client, "invoice.payment_action_required", {
    id: fbi.stripe_invoice_id,
    object: "invoice",
    billing_reason: "manual",
    currency: "usd",
    amount_due: 119600,
    customer: fbi.stripe_customer_id,
    hosted_invoice_url: fbi.hosted_invoice_url,
    metadata,
  });
  expect((await financial(projectId)).balance_verified).toBe(false);
  expect((await audited(since, "balance.action_required")).length).toBe(1);
  await client.goto(`/portal/projects/${projectId}/billing`);
  const pay = client.getByRole("link", { name: "Pay the final balance of $1,196.00 on Stripe" });
  await expect(pay).toHaveAttribute("href", fbi.hosted_invoice_url);
  await expectAccessible(client);
  // Publication stays blocked, server-side: the Owner's authorization is refused with G4.
  expect(await failingGates(projectId, release2)).toContain("G4:balance_not_verified");

  await deliver(client, "invoice.paid", {
    id: fbi.stripe_invoice_id,
    object: "invoice",
    billing_reason: "manual",
    currency: "usd",
    amount_paid: 119600,
    customer: fbi.stripe_customer_id,
    default_payment_method: fbi.default_payment_method_id,
    payment_intent: `pi_r1${RUN}fb01`,
    metadata,
    lines: {
      data: [
        { quantity: 1, pricing: { price_details: { price: "price_1Uf5HzK5j4r4WkVPRH6Wkz6D" } } },
      ],
    },
  });
  expect(await financial(projectId)).toMatchObject({ balance: "verified", balance_verified: true });
  await client.goto(`/portal/projects/${projectId}/billing`);
  await expect(client.getByTestId("payment-status")).toContainText("Received");
  expect(await failingGates(projectId, release2)).not.toContain("G4");
});

// ---------------------------------------------------------------------------
// T-E2E-07 Fulfillment evidence
// ---------------------------------------------------------------------------
test("T-E2E-07: QA, security and domain readiness are recorded; the admin queue shows derived states only", async () => {
  const projectPage = `/staff/projects/${projectId}`;
  // Each form posts back to the project page with notice=saved; load it fresh first so the
  // notice proves this submission.
  const submit = async (
    button: string,
    fill: (form: ReturnType<Page["locator"]>) => Promise<void>,
  ) => {
    await admin.goto(projectPage);
    const form = admin.locator("form", { has: admin.getByRole("button", { name: button }) });
    await fill(form);
    await form.getByRole("button", { name: button }).click();
    await expect(admin).toHaveURL(/notice=saved/);
  };
  const allPass = async (form: ReturnType<Page["locator"]>) => {
    for (const select of await form.locator("select").all()) await select.selectOption("pass");
  };
  await submit("Record QA result", allPass);
  await submit("Record security result", allPass);
  await submit("Record domain check", async (form) => {
    await form.locator("input[name=domain]").fill(`r1-${RUN}.example.test`);
    for (const label of [
      "DNS points to the client's target",
      "TLS certificate valid",
      "www/apex redirect configured",
      "Registrant in the client's name",
      "Third-party domain charges disclosed and approved",
    ]) {
      await form.getByLabel(label).check();
    }
  });

  const evidence = await withDb((db) =>
    db.query(
      `select (select count(*)::int from public.qa_results where release_id = $2 and recorded_by = $3) as qa,
              (select count(*)::int from public.security_check_results where release_id = $2 and recorded_by = $3) as security,
              (select count(*)::int from public.domain_readiness_checks where project_id = $1 and recorded_by = $3) as domain,
              (s).qa_passed, (s).security_passed, (s).domain_ready
         from (select private.project_fulfillment_status($1) as s) f`,
      [projectId, release2, ADMIN_ID],
    ),
  );
  expect(evidence.rows).toEqual([
    { qa: 1, security: 1, domain: 1, qa_passed: true, security_passed: true, domain_ready: true },
  ]);
  expect(await failingGates(projectId, release2)).toBe("");

  await admin.goto("/staff/queue");
  await expect(admin.getByRole("heading", { name: "Work queue" })).toBeVisible();
  // The queues shown for this project are exactly the database's own derivation for this
  // Admin session.
  const expected = await withDb(async (db) => {
    const { rows: session } = await db.query(
      `select id from auth.sessions where user_id = $1 and aal = 'aal2' order by created_at desc limit 1`,
      [ADMIN_ID],
    );
    await db.query("begin");
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated',
         'aal', 'aal2', 'session_id', $2::text)::text, true)`,
      [ADMIN_ID, session[0].id],
    );
    const { rows } = await db.query(
      "select q ->> 'queue' as queue from private.operational_queue() q where q ->> 'project_id' = $1",
      [projectId],
    );
    await db.query("rollback");
    return rows.map((r) => r.queue as string).sort();
  });
  expect(expected.length).toBeGreaterThan(0);
  const shown: string[] = [];
  for (const section of await admin.locator("main section[aria-labelledby^='q-']").all()) {
    const links = await section.getByRole("link", { name: PROJECT_NAME }).count();
    const queue = (await section.getAttribute("aria-labelledby"))!.slice(2);
    for (let i = 0; i < links; i++) shown.push(queue);
  }
  expect(shown.sort()).toEqual(expected);
  // Derived states only: no amounts, ledger or payment-authorization detail.
  await expect(admin.locator("main")).not.toContainText("$");
  await expect(admin.getByTestId("owner-financial-detail")).toHaveCount(0);
  await expectAccessible(admin);
});

// ---------------------------------------------------------------------------
// P-3 (Owner ruling, 2026-11-26): the browser `pattern` and the server rule agree
// ---------------------------------------------------------------------------
test("P-3: the deployment-target field's browser pattern and the database rule accept and reject the same inputs", async () => {
  const cases: [string, boolean][] = [
    ["abc", true],
    ["my-site_1", true],
    ["a".repeat(100), true],
    ["ab", false],
    ["-abc", false],
    ["_abc", false],
    ["Abc", false],
    ["a b c", false],
    ["abc.def", false],
    ["a".repeat(101), false],
  ];
  await owner.goto(`/staff/projects/${projectId}`);
  const input = owner.getByLabel("Client deployment target (project reference)");
  // The server rule is the database's own check constraint on client_site_targets.target_ref.
  const serverRule = await withDb(async (db) => {
    const { rows } = await db.query(
      `select pg_get_constraintdef(c.oid) as def from pg_constraint c
        where c.conrelid = 'public.client_site_targets'::regclass and c.contype = 'c'
          and pg_get_constraintdef(c.oid) like '%target_ref%'`,
    );
    expect(rows).toHaveLength(1);
    return /'(\^.*\$)'/.exec(rows[0].def as string)![1]!;
  });
  expect(serverRule).toBe("^[a-z0-9][a-z0-9_-]{2,99}$");
  for (const [value, valid] of cases) {
    await input.fill(value);
    const browserAccepts = await input.evaluate(
      (el) => !(el as HTMLInputElement).validity.patternMismatch,
    );
    const serverAccepts = await withDb(async (db) => {
      const { rows } = await db.query("select $1::text ~ $2::text as ok", [value, serverRule]);
      return rows[0].ok as boolean;
    });
    expect({ value, browserAccepts, serverAccepts }).toEqual({
      value,
      browserAccepts: valid,
      serverAccepts: valid,
    });
  }
  await input.fill("");
});

// ---------------------------------------------------------------------------
// T-E2E-08 Publication
// ---------------------------------------------------------------------------
test("T-E2E-08: the Owner, freshly reauthenticated, authorizes exactly the approved release; the deployment is recorded and verified; a mismatched build fails", async () => {
  const projectPage = `/staff/projects/${projectId}`;
  await owner.goto(projectPage);
  const OUTCOME = /\/mfa\?reauth=1|[?&](notice|error)=/;
  const registerTarget = async () => {
    await owner.getByLabel("Client deployment target (project reference)").fill(`r1-${RUN}-site`);
    await owner.getByRole("button", { name: "Register target" }).click();
    await owner.waitForURL(OUTCOME);
  };
  await registerTarget();
  if (/\/mfa\?reauth=1/.test(owner.url())) {
    await reauthenticateIfAsked(owner);
    await registerTarget();
  }
  await expect(owner).toHaveURL(/notice=saved/);
  await expect(owner.getByTestId("gate-list")).not.toContainText("Blocked");

  const authorize = async () => {
    await owner.goto(projectPage);
    await owner.getByLabel(/Authorize publication of release 2 exactly as approved/).check();
    await owner.getByRole("button", { name: "Authorize publication" }).click();
    await owner.waitForURL(OUTCOME);
    if (/\/mfa\?reauth=1/.test(owner.url())) {
      await reauthenticateIfAsked(owner);
      await owner.getByLabel(/Authorize publication of release 2 exactly as approved/).check();
      await owner.getByRole("button", { name: "Authorize publication" }).click();
    }
    await expect(owner).toHaveURL(/notice=publication_authorized/);
  };
  const deploy = async (url: string) => {
    await owner.getByRole("button", { name: "Start deployment" }).click();
    await expect(owner).toHaveURL(/notice=deployment_started/);
    await owner
      .getByLabel("Provider deployment ID")
      .fill(`dpl_prod_r1_${randomBytes(3).toString("hex")}`);
    await owner.getByLabel("Production URL").fill(url);
    await owner.getByRole("button", { name: "Record success" }).click();
    await expect(owner).toHaveURL(/notice=saved/);
    const newest = await withDb(
      async (db) =>
        (
          await db.query(
            "select id::text from public.publication_deployments where project_id = $1 order by seq desc limit 1",
            [projectId],
          )
        ).rows[0].id as string,
    );
    await owner
      .locator("form", { has: owner.locator(`input[name=deploymentId][value="${newest}"]`) })
      .getByRole("button", { name: "Verify live site" })
      .click();
    await expect(owner).toHaveURL(/notice=verification_recorded/);
  };

  const since = await lastAuditId();
  await authorize();
  const auth = await withDb((db) =>
    db.query(
      `select release_id::text as release, authorized_by::text as by from public.publication_authorizations
        where project_id = $1`,
      [projectId],
    ),
  );
  expect(auth.rows).toEqual([{ release: release2, by: OWNER_ID }]);
  expect((await audited(since, "publication.authorized")).length).toBe(1);

  // A mismatched build fails live verification (seam (b)) and opens an incident.
  await deploy(`https://${SHA_OTHER}.live.r1.example.test/`);

  // AUTH-015 (OI-114): the Owner recovers the failed publication through the page (fresh
  // MFA, a reason, an explicit confirmation). The recovery closes the used authorization; the
  // normal authorization flow then re-runs every gate (D3) before the release deploys again.
  const recover = async () => {
    await owner.goto(projectPage);
    await owner.getByLabel("Recovery reason").fill("The live site served a different build");
    await owner
      .getByLabel(/Close this deployment's authorization so the release can be authorized again/)
      .check();
    await owner.getByRole("button", { name: "Recover failed publication" }).click();
    await owner.waitForURL(OUTCOME);
  };
  await recover();
  if (/\/mfa\?reauth=1/.test(owner.url())) {
    await reauthenticateIfAsked(owner);
    await recover();
  }
  await expect(owner).toHaveURL(/notice=publication_recovery_opened/);
  expect((await audited(since, "publication.recovery_opened")).length).toBe(1);
  await authorize();
  const auths = await withDb((db) =>
    db.query(
      `select release_id::text as release, invalidated_reason from public.publication_authorizations
        where project_id = $1 order by authorized_at, id`,
      [projectId],
    ),
  );
  expect(auths.rows).toEqual([
    { release: release2, invalidated_reason: "failed_publication_recovery" },
    { release: release2, invalidated_reason: null },
  ]);

  // The served build matches the authorized release on the new deployment.
  await deploy(`https://${SHA_2}.live.r1.example.test/`);
  const verified = await withDb((db) =>
    db.query(
      `select v.build_matches, v.verified, v.served_build_id, d.commit_sha
         from public.deployment_verifications v join public.publication_deployments d on d.id = v.deployment_id
        where v.project_id = $1 order by v.seq`,
      [projectId],
    ),
  );
  expect(verified.rows).toEqual([
    { build_matches: false, verified: false, served_build_id: SHA_OTHER, commit_sha: SHA_2 },
    { build_matches: true, verified: true, served_build_id: SHA_2, commit_sha: SHA_2 },
  ]);
  const all = await withDb((db) =>
    db.query(
      `select v.build_matches, v.verified from public.deployment_verifications v
        where v.project_id = $1 order by v.seq`,
      [projectId],
    ),
  );
  expect(all.rows).toEqual([
    { build_matches: false, verified: false },
    { build_matches: true, verified: true },
  ]);
  const incidents = await withDb((db) =>
    db.query("select kind::text, summary from public.publication_incidents where project_id = $1", [
      projectId,
    ]),
  );
  expect(incidents.rows).toEqual([
    { kind: "verification_failed", summary: "Served build does not match the authorized release" },
  ]);
  expect((await audited(since, "deployment.verification_recorded")).length).toBe(2);
  await expectAccessible(owner);
});

// ---------------------------------------------------------------------------
// T-E2E-09 Role separation
// ---------------------------------------------------------------------------
test("T-E2E-09: Admin sees derived states and agreed pricing only; client B is denied; Sales sees only assigned customers", async () => {
  await admin.goto(`/staff/projects/${projectId}`);
  await expect(admin.getByTestId("derived-payment-states")).toContainText("Deposit requirement");
  await expect(admin.getByText(/Total \$1,495\.00/)).toBeVisible();
  await expect(admin.getByTestId("owner-financial-detail")).toHaveCount(0);
  await expect(admin.getByText("$398.00")).toHaveCount(0);

  for (const path of [`/portal/projects/${projectId}`, `/portal/projects/${projectId}/billing`]) {
    const response = await clientB.goto(path);
    expect(response?.status(), path).toBe(404);
  }
  const asset = await clientB.request.get(`/portal/projects/${projectId}/assets/${validUpload}`, {
    maxRedirects: 0,
  });
  expect(asset.status()).toBe(404);

  await sales.goto("/sales");
  await expect(sales.getByTestId("sales-customers")).toContainText(PROJECT_NAME);
  await expect(sales.getByTestId("sales-customers")).not.toContainText("Project A website");
  // A deliberate 404, on a separate page of the same session, so the journey's console
  // check (T-E2E-10) sees only unexpected errors.
  const probe = await sales.context().newPage();
  const unassigned = await probe.goto(`/sales/projects/${PROJECT_A}`);
  expect(unassigned?.status()).toBe(404);
  await probe.close();
  const assignments = await withDb((db) =>
    db.query(
      `select count(*)::int as n from public.project_sales_assignments
        where sales_user_id = $1 and active and project_id = $2`,
      [SALES_ID, projectId],
    ),
  );
  expect(assignments.rows[0].n).toBe(1);
});

// ---------------------------------------------------------------------------
// T-E2E-10 Quality
// ---------------------------------------------------------------------------
test("T-E2E-10: the journey's pages logged no console errors (Lighthouse thresholds run in the CI Lighthouse job)", () => {
  expect(consoleErrors).toEqual([]);
  expect(flaggedUpload).not.toBe("");
});
