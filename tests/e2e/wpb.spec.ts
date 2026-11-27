import { createHmac } from "node:crypto";

import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Browser, type Page } from "@playwright/test";

import { withDb } from "../support/db";
import { clearMailbox, codeFrom, waitForEmail } from "../support/mailpit";
import { totp } from "../support/totp";

/**
 * WP-B browser tests (WP-B directive item 7), against the LOCAL Supabase stack with
 * synthetic users, the mocked Stripe gateway (no network request; the Stripe-hosted page is
 * intercepted), and a synthetic Stripe-format event signed with a secret generated for
 * this run (OI-63). Nothing here is verified against Stripe (DEP-06, DEP-15, AUTH-002).
 *
 * - Admin issues the order summary from the staff billing section and sees only the derived
 *   states and the agreed pricing (OI-72, OI-83)
 * - the client reads the fixture agreement, accepts it, and starts the initial Checkout
 * - returning from Stripe alone leaves the deposit pending and intake locked (T-PAY-04)
 * - only the signed webhook verifies the deposit; the saved card is recorded and the client
 *   billing page and intake reflect it (T-PAY-03, T-PAY-05, T-PAY-18)
 * Each step also checks the authoritative database state behind what the browser shows.
 */
test.describe.configure({ mode: "serial" });

const ADMIN = "admin@example.test";
const CLIENT_A = "client.a@example.test";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const RUN = Date.now().toString(36);
const LEGAL_NAME = `E2E WP-B ${RUN} LLC`;

function webhookSecret(): string {
  const secret = process.env.E2E_STRIPE_WEBHOOK_SECRET;
  // Never skipped (CLAUDE.md §3): without the run's secret the suite fails.
  if (!secret || !/^whsec_[A-Za-z0-9]+$/.test(secret)) {
    throw new Error("E2E_STRIPE_WEBHOOK_SECRET must be set to a test-only whsec_ value");
  }
  return secret;
}

function signed(type: string, object: Record<string, unknown>) {
  const now = Math.floor(Date.now() / 1000);
  const body = JSON.stringify({
    id: `evt_e2e${RUN}${Math.random().toString(36).slice(2, 10)}`,
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

async function adminPage(browser: Browser): Promise<Page> {
  await withDb((db) => db.query("delete from auth.mfa_factors where user_id = $1", [ADMIN_ID]));
  const page = await (await browser.newContext()).newPage();
  await signIn(page, ADMIN);
  await expect(page).toHaveURL(/\/mfa/);
  await page.getByRole("button", { name: "Set up authenticator app" }).click();
  const secret = (await page.locator("code").textContent())?.trim() ?? "";
  await page.getByLabel("Authenticator code").fill(totp(secret));
  await page.getByRole("button", { name: "Verify and continue" }).click();
  await expect(page).toHaveURL(/\/staff/);
  return page;
}

type Financial = { deposit: string; verified: boolean; ready: boolean; auth: string };
const financial = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select f.deposit_state::text as deposit, f.deposit_verified as verified,
              f.payment_authorization_ready as ready, f.payment_authorization_state as auth
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

let clientPage: Page;
let staffPage: Page;
let projectId = "";

test.beforeAll(async ({ browser }) => {
  webhookSecret();
  projectId = await withDb(async (db) => {
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, false)`,
      [OWNER_ID],
    );
    const business = await db.query(
      `insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id`,
      [LEGAL_NAME],
    );
    const project = await db.query(
      `insert into public.projects (client_business_id, name) values ($1, $2) returning id`,
      [business.rows[0].id, `E2E billing project ${RUN}`],
    );
    const id = project.rows[0].id as string;
    await db.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
      id,
      CLIENT_A_ID,
    ]);
    await db.query("delete from private.rate_limits");
    return id;
  });
  staffPage = await adminPage(browser);
  clientPage = await (await browser.newContext()).newPage();
  await signIn(clientPage, CLIENT_A);
  await expect(clientPage).toHaveURL(/\/portal$/);
});

test.afterAll(async () => {
  await clientPage?.context().close();
  await staffPage?.context().close();
});

test("Admin issues the order summary and sees only derived states and agreed pricing (OI-72, OI-83)", async () => {
  await staffPage.goto(`/staff/projects/${projectId}`);
  await staffPage.getByLabel("Package").selectOption("essential");
  await staffPage.getByLabel("Included scope (one item per line)").fill("Five-page website");
  await staffPage.getByRole("button", { name: "Issue order summary" }).click();
  await expect(staffPage.locator("main").getByRole("status").first()).toContainText(
    "Order summary issued.",
  );
  await expect(
    staffPage.getByText(/Total \$800\.00, deposit \$160\.00, balance \$640\.00/),
  ).toBeVisible();
  await expect(staffPage.getByTestId("derived-payment-states")).toContainText(
    "Deposit requirement",
  );
  // Admin never receives ledger, holds or the payment authorization (OI-72).
  await expect(staffPage.getByTestId("owner-financial-detail")).toHaveCount(0);
  await expectAccessible(staffPage);
  const summary = await withDb(async (db) => {
    const { rows } = await db.query(
      `select package_key, package_total_cents::int as total, deposit_cents::int as deposit,
              balance_cents::int as balance, issued_by::text as issued_by
         from public.order_summaries where project_id = $1`,
      [projectId],
    );
    return rows;
  });
  expect(summary).toEqual([
    { package_key: "essential", total: 80000, deposit: 16000, balance: 64000, issued_by: ADMIN_ID },
  ]);
});

test("the client accepts the labeled fixture agreement explicitly (T-AGR-01, T-AGR-08)", async () => {
  await clientPage.goto(`/portal/projects/${projectId}/billing`);
  await expect(clientPage.getByTestId("test-fixture-label").first()).toBeVisible();
  const accepted = clientPage.getByLabel(/I have read and accept this agreement/);
  const authority = clientPage.getByLabel(/I confirm that I am authorized/);
  await expect(accepted).not.toBeChecked();
  await expect(authority).not.toBeChecked();
  await expectAccessible(clientPage);
  await clientPage.getByLabel("Your full legal name").fill("Alex Client");
  await clientPage.getByLabel("Business legal name").fill(LEGAL_NAME);
  await clientPage.getByLabel("Your position or title").fill("Owner");
  await accepted.check();
  await authority.check();
  await clientPage.getByRole("button", { name: "Accept agreement" }).click();
  await expect(clientPage.locator("main").getByRole("status").first()).toContainText(
    "Agreement accepted.",
  );
  const acceptance = await withDb(async (db) => {
    const { rows } = await db.query(
      `select signer_user_id::text as signer, business_name_matches from public.agreement_acceptances
        where project_id = $1`,
      [projectId],
    );
    return rows;
  });
  expect(acceptance).toEqual([{ signer: CLIENT_A_ID, business_name_matches: true }]);
});

test("starting Checkout reaches the Stripe-hosted page; returning alone leaves intake locked (T-PAY-04)", async () => {
  // The mocked gateway returns a checkout.stripe.com URL; the browser never leaves the test.
  await clientPage.route("https://checkout.stripe.com/**", (route) =>
    route.fulfill({
      status: 200,
      contentType: "text/html",
      body: "<!doctype html><title>Intercepted</title><main><h1>Intercepted Stripe Checkout</h1></main>",
    }),
  );
  await clientPage.getByRole("button", { name: "Pay $259.00 securely with Stripe" }).click();
  await expect(clientPage).toHaveURL(/^https:\/\/checkout\.stripe\.com\/c\/pay\/cs_test_mock/);
  const session = await withDb(async (db) => {
    const { rows } = await db.query(
      `select stripe_checkout_session_id as id, status::text, order_summary_id::text, acceptance_id::text,
              id::text as record_id
         from public.checkout_sessions where project_id = $1`,
      [projectId],
    );
    return rows;
  });
  expect(session).toHaveLength(1);
  expect(clientPage.url()).toContain(session[0].id);

  await clientPage.goto(`/portal/projects/${projectId}/billing?checkout=returned`);
  await expect(clientPage.getByText(/^Payment processing\./)).toBeVisible();
  await expect(clientPage.getByTestId("payment-status")).toContainText("Payment processing");
  await clientPage.goto(`/portal/projects/${projectId}`);
  await expect(clientPage.getByTestId("project-status")).toContainText(
    "Available once your deposit and saved payment method are verified",
  );
  expect(await financial(projectId)).toEqual({
    deposit: "pending",
    verified: false,
    ready: false,
    auth: "none",
  });
  expect(await intakeUnlocked(projectId)).toBe(false);
});

test("only the signed webhook verifies the deposit; the saved card makes intake available (T-PAY-03, T-PAY-05, T-PAY-18)", async () => {
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
  const object = {
    id: session.id,
    object: "checkout.session",
    mode: "subscription",
    currency: "usd",
    amount_total: 25900,
    payment_status: "paid",
    customer,
    subscription: `sub_e2e${RUN}01`,
    invoice: `in_e2e${RUN}01`,
    total_details: { amount_discount: 0, amount_tax: 0 },
    metadata: {
      project_id: projectId,
      order_summary_id: session.order_summary_id,
      acceptance_id: session.acceptance_id,
      checkout_record_id: session.record_id,
    },
  };

  // An unsigned delivery is refused and changes nothing.
  const forged = signed("checkout.session.completed", object);
  const refused = await clientPage.request.post("/api/stripe/webhook", {
    data: forged.body,
    headers: {
      "content-type": "application/json",
      "stripe-signature": forged.header.replace(/v1=[0-9a-f]{64}/, `v1=${"0".repeat(64)}`),
    },
  });
  expect(refused.status()).toBe(400);
  expect((await financial(projectId)).deposit).toBe("pending");

  const event = signed("checkout.session.completed", object);
  const response = await clientPage.request.post("/api/stripe/webhook", {
    data: event.body,
    headers: { "content-type": "application/json", "stripe-signature": event.header },
  });
  expect(response.status()).toBe(200);
  expect(await response.json()).toEqual({ received: true, duplicate: false });
  // A replay is acknowledged as a duplicate and posts nothing again (T-PAY-05).
  const replay = await clientPage.request.post("/api/stripe/webhook", {
    data: event.body,
    headers: { "content-type": "application/json", "stripe-signature": event.header },
  });
  expect(await replay.json()).toEqual({ received: true, duplicate: true });

  expect(await financial(projectId)).toEqual({
    deposit: "verified",
    verified: true,
    ready: true,
    auth: "active",
  });
  expect(await intakeUnlocked(projectId)).toBe(true);
  const ledger = await withDb(async (db) => {
    const { rows } = await db.query(
      `select entry_type::text, amount_cents::int as amount from public.ledger_entries
        where project_id = $1 order by id`,
      [projectId],
    );
    return rows;
  });
  expect(ledger).toEqual([
    { entry_type: "deposit_charge", amount: 16000 },
    { entry_type: "maintenance_charge", amount: 9900 },
  ]);

  await clientPage.goto(`/portal/projects/${projectId}/billing`);
  await expect(clientPage.getByTestId("payment-status")).toContainText("Received");
  await expect(clientPage.getByTestId("payment-authorization")).toContainText(
    "Your card is saved for the final balance.",
  );
  await expect(
    clientPage.getByRole("button", { name: "Turn off automatic final payment" }),
  ).toBeVisible();
  await expectAccessible(clientPage);
  await clientPage.goto(`/portal/projects/${projectId}`);
  await expect(clientPage.getByTestId("project-status")).not.toContainText(
    "Available once your deposit and saved payment method are verified",
  );
});

test("the staff billing section shows Admin the derived states only after payment (OI-72)", async () => {
  await staffPage.goto(`/staff/projects/${projectId}`);
  const states = staffPage.getByTestId("derived-payment-states");
  await expect(states).toContainText("Deposit requirement");
  await expect(states.getByText("Satisfied").first()).toBeVisible();
  await expect(staffPage.getByTestId("owner-financial-detail")).toHaveCount(0);
  await expect(staffPage.getByText("$259.00")).toHaveCount(0);
  await expectAccessible(staffPage);
  // The database agrees: the Admin session's derived row says the deposit is satisfied.
  const derived = await withDb(async (db) => {
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
      "select s.deposit_requirement_satisfied, s.payment_recovery_required from private.operational_payment_states(array[$1::uuid]) s",
      [projectId],
    );
    await db.query("rollback");
    return rows;
  });
  expect(derived).toEqual([
    { deposit_requirement_satisfied: true, payment_recovery_required: false },
  ]);
});

// AUTH-010 (OI-93): the Owner's conflict screen. A refund naming this project's payment intent
// and another project's recorded charge arrives through the signed webhook route and is
// quarantined as a conflict; the Owner records a decision and applies it; the block clears.
test("the Owner decides and applies an attribution conflict; Admin cannot open the screen (AUTH-010)", async ({
  browser,
}) => {
  const tag = `e2e${RUN}`;
  const otherProject = await withDb(async (db) => {
    const record = await db.query(
      "select id::text, stripe_invoice_id from public.checkout_sessions where project_id = $1",
      [projectId],
    );
    // The initial invoice's payment link for this project, and a recorded renewal charge of
    // another project whose obligation is not posted (synthetic records, as in pgTAP 195).
    await db.query(
      `insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
       values ($1, $2, 'initial', $3, $4) on conflict do nothing`,
      [`pi_${tag}a`, projectId, record.rows[0].id, record.rows[0].stripe_invoice_id],
    );
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, false)`,
      [OWNER_ID],
    );
    const business = await db.query(
      `insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id`,
      [`E2E conflict ${RUN} LLC`],
    );
    const other = await db.query(
      `insert into public.projects (client_business_id, name) values ($1, $2) returning id`,
      [business.rows[0].id, `E2E other project ${RUN}`],
    );
    await db.query(
      `insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
       values ($1, $2, 'renewal', null, $3)`,
      [`ch_${tag}b`, other.rows[0].id, `in_${tag}brenew`],
    );
    return other.rows[0].id as string;
  });
  const event = signed("refund.updated", {
    id: `re_${tag}c1`,
    object: "refund",
    amount: 500,
    currency: "usd",
    status: "succeeded",
    payment_intent: `pi_${tag}a`,
    charge: `ch_${tag}b`,
    metadata: {},
  });
  const delivered = await clientPage.request.post("/api/stripe/webhook", {
    data: event.body,
    headers: { "content-type": "application/json", "stripe-signature": event.header },
  });
  expect(delivered.status()).toBe(200);
  const quarantined = await withDb(async (db) => {
    const { rows } = await db.query(
      "select processing_status::text, quarantine_reason from public.webhook_events where stripe_event_id = $1",
      [JSON.parse(event.body).id],
    );
    return rows[0];
  });
  expect(quarantined).toEqual({
    processing_status: "quarantined",
    quarantine_reason: "attribution_conflict",
  });

  // Admin is not the Owner: the screen redirects.
  await staffPage.goto("/staff/billing/conflicts");
  await expect(staffPage).toHaveURL(/\/staff\?notice=forbidden/);

  // The Owner signs in with a new authenticator (fresh MFA).
  await withDb((db) => db.query("delete from auth.mfa_factors where user_id = $1", [OWNER_ID]));
  const ownerPage = await (await browser.newContext()).newPage();
  try {
    await signIn(ownerPage, "owner@example.test");
    await expect(ownerPage).toHaveURL(/\/mfa/);
    await ownerPage.getByRole("button", { name: "Set up authenticator app" }).click();
    const secret = (await ownerPage.locator("code").textContent())?.trim() ?? "";
    await ownerPage.getByLabel("Authenticator code").fill(totp(secret));
    await ownerPage.getByRole("button", { name: "Verify and continue" }).click();
    await expect(ownerPage).toHaveURL(/\/staff/);

    await ownerPage.goto("/staff/billing/conflicts");
    await expect(ownerPage.getByRole("heading", { name: "Financial conflicts" })).toBeVisible();
    const card = ownerPage.getByRole("listitem").filter({ hasText: `re_${tag}c1` });
    await expect(card).toContainText("Blocked");
    await expect(card).toContainText(`E2E billing project ${RUN}`);
    await expect(card).toContainText(`E2E other project ${RUN}`);
    await expectAccessible(ownerPage);

    await card.getByLabel(`E2E billing project ${RUN}`).check();
    await card
      .getByLabel("Evidence references")
      .fill("Stripe Dashboard: refund and charge reviewed");
    await card.getByLabel("Reason").fill("The refund belongs to this project's initial charge");
    await card.getByRole("button", { name: "Record decision" }).click();
    await expect(ownerPage.locator("main")).toContainText("Decision recorded.");
    const decided = ownerPage.getByRole("listitem").filter({ hasText: `re_${tag}c1` });
    await expect(decided).toContainText("Blocked");
    await expectAccessible(ownerPage);

    await decided.getByLabel("Reason").fill("Apply the recorded decision");
    await decided.getByRole("button", { name: "Apply decision" }).click();
    await expect(ownerPage.locator("main")).toContainText("Applied: the event was posted");
    await expect(ownerPage.getByRole("listitem").filter({ hasText: `re_${tag}c1` })).toContainText(
      "Cleared",
    );
    await expectAccessible(ownerPage);
  } finally {
    await ownerPage.context().close();
  }

  // The database agrees: posted once under this project by the existing ledger rules; the
  // original event stays quarantined; the other project has nothing.
  const after = await withDb(async (db) => {
    const { rows } = await db.query(
      `select (select string_agg(a.outcome, ',') from private.financial_conflict_applications a
                where a.webhook_event_id = w.id) as outcomes,
              (select count(*)::int from public.ledger_entries l where l.stripe_object_id = $2 and l.project_id = $3) as here,
              (select count(*)::int from public.ledger_entries l where l.stripe_object_id = $2 and l.project_id = $4) as there,
              w.processing_status::text as status, private.financial_conflict_cleared(w.id) as cleared
         from public.webhook_events w where w.stripe_event_id = $1`,
      [JSON.parse(event.body).id, `re_${tag}c1`, projectId, otherProject],
    );
    return rows[0];
  });
  expect(after).toEqual({
    outcomes: "posted",
    here: 1,
    there: 0,
    status: "quarantined",
    cleared: true,
  });
});
