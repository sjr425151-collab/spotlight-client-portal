import { createHmac } from "node:crypto";

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
 * Each test also checks the authoritative database state and audit evidence behind what the
 * browser shows (PR #19 review M2).
 */
test.describe.configure({ mode: "serial" });

const ADMIN = "admin@example.test";
const CLIENT_A = "client.a@example.test";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
const RUN = Date.now().toString(36);
const EXE = Buffer.from("MZ\x90\x00");

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

/** The newest audit event id: evidence written by a test has a larger id. */
const lastAuditId = () =>
  withDb(async (db) => {
    const { rows } = await db.query(
      "select coalesce(max(id), 0)::text as id from public.audit_events",
    );
    return rows[0].id as string;
  });

type AuditRow = {
  action: string;
  actor: string | null;
  project: string | null;
  summary: Record<string, unknown>;
};
const auditSince = (afterId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select action, actor_user_id::text as actor, project_id::text as project, summary
         from public.audit_events where id > $1::bigint order by id`,
      [afterId],
    );
    return rows as AuditRow[];
  });

const countRows = (table: string, projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select count(*)::int as n from public.${table} where project_id = $1`,
      [projectId],
    );
    return rows[0].n as number;
  });

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
  const before = {
    audit: await lastAuditId(),
    intake: await countRows("intake_submissions", PROJECT_A),
    uploads: await countRows("asset_uploads", PROJECT_A),
  };
  await clientPage.goto(`/portal/projects/${PROJECT_A}`);
  await expect(clientPage.getByTestId("project-status")).toContainText(
    "Available once your deposit and saved payment method are verified",
  );
  await expect(clientPage.getByRole("button", { name: "Submit for review" })).toHaveCount(0);
  await expect(clientPage.getByRole("button", { name: "Upload" })).toHaveCount(0);
  await expectAccessible(clientPage);
  // M2: the database agrees the intake is locked, and viewing it changed nothing.
  await withDb(async (db) => {
    const { rows } = await db.query("select private.wpc_intake_unlocked($1) as unlocked", [
      PROJECT_A,
    ]);
    expect(rows[0].unlocked).toBe(false);
  });
  expect(await countRows("intake_submissions", PROJECT_A)).toBe(before.intake);
  expect(await countRows("asset_uploads", PROJECT_A)).toBe(before.uploads);
  const written = (await auditSince(before.audit)).filter((e) => e.project === PROJECT_A);
  expect(written.filter((e) => /^(intake|upload)\./.test(e.action))).toEqual([]);
});

test("an upload of a disallowed type is rejected by the server (T-UP-01)", async () => {
  const before = {
    audit: await lastAuditId(),
    uploads: await countRows("asset_uploads", PROJECT_A),
  };
  const response = await clientPage.request.post(`/portal/projects/${PROJECT_A}/uploads`, {
    multipart: {
      category: "logo",
      file: {
        name: "tool.exe",
        mimeType: "application/x-msdownload",
        buffer: EXE,
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
  // M2: nothing was reserved, and the refusal is audited in Project A for client A.
  expect(await countRows("asset_uploads", PROJECT_A)).toBe(before.uploads);
  const written = (await auditSince(before.audit)).filter((e) => e.action.startsWith("upload."));
  expect(written).toEqual([
    {
      action: "upload.refused",
      actor: CLIENT_A_ID,
      project: PROJECT_A,
      summary: {
        code: "type_not_allowed",
        category: "logo",
        declared_mime: "application/x-msdownload",
        declared_bytes: EXE.length,
      },
    },
  ]);
});

test("client A is denied Project B's page and asset URLs, and the staff area (T-UP-06)", async () => {
  const before = {
    audit: await lastAuditId(),
    uploadsB: await countRows("asset_uploads", PROJECT_B),
  };
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
  // M2: no denial produced a successful access, a reservation, or any record in Project B.
  const written = await auditSince(before.audit);
  expect(written.filter((e) => ["upload.accessed", "upload.requested"].includes(e.action))).toEqual(
    [],
  );
  expect(written.filter((e) => e.project === PROJECT_B)).toEqual([]);
  expect(await countRows("asset_uploads", PROJECT_B)).toBe(before.uploadsB);
});

test("the staff work queue renders derived items (05 §9)", async () => {
  await staffPage.goto("/staff/queue");
  await expect(staffPage.getByRole("heading", { name: "Work queue" })).toBeVisible();
  await expect(staffPage.getByRole("heading", { name: "In development" })).toBeVisible();
  await expect(staffPage.getByRole("link", { name: `E2E release project ${RUN}` })).toBeVisible();
  await expectAccessible(staffPage);
  // M2: every queue shown matches the database's own derivation for this Admin session.
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
    const { rows } = await db.query("select q from private.operational_queue() q");
    await db.query("rollback");
    const byQueue: Record<string, string[]> = {};
    for (const { q } of rows as { q: { queue: string; project_name: string } }[]) {
      (byQueue[q.queue] ??= []).push(q.project_name);
    }
    return byQueue;
  });
  expect(expected.in_development).toContain(`E2E release project ${RUN}`);
  const shown: Record<string, string[]> = {};
  for (const section of await staffPage.locator("main section[aria-labelledby^='q-']").all()) {
    const queue = (await section.getAttribute("aria-labelledby"))!.slice(2);
    shown[queue] = await section.getByRole("link").allTextContents();
  }
  const sorted = (m: Record<string, string[]>) =>
    Object.fromEntries(
      Object.entries(m)
        .map(([k, v]) => [k, [...v].sort()])
        .sort(),
    );
  expect(sorted(shown)).toEqual(sorted(expected));
});

test("staff record a preview release with SHA, deployment ID, and preview URL (T-LC-15)", async () => {
  // AUTH-023 (setup only, OD-11(ii); Main's Q3 ruling (b)): client A becomes the release
  // project's member and authorized signer through the real WP-B path (r1's pattern: the Owner
  // issues the order summary; the client accepts it and begins the initial Checkout; mock outbound
  // results are recorded; a signed synthetic checkout.session.completed is delivered, OI-63). The
  // Admin then records the scope confirmation and the client acknowledges it through the pages.
  // No financial table is written directly.
  const s5 = await withDb(async (db) => {
    const as = async (userId: string, aal: string) => {
      const sid = (
        await db.query(
          `insert into auth.sessions (id, user_id, created_at, updated_at, aal)
           values (gen_random_uuid(), $1, now(), now(), $2::auth.aal_level) returning id::text`,
          [userId, aal],
        )
      ).rows[0].id as string;
      await db.query(
        `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated',
           'aal', $2::text, 'session_id', $3::text)::text, true)`,
        [userId, aal, sid],
      );
    };
    await db.query("begin");
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, true)`,
      [OWNER_ID],
    );
    await db.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
      releaseProjectId,
      CLIENT_A_ID,
    ]);
    await db.query("commit");
    await db.query("begin");
    await as(OWNER_ID, "aal2");
    await db.query("set local role authenticated");
    const os = await db.query(
      "select public.issue_order_summary($1, 'essential', '[]'::jsonb) as r",
      [releaseProjectId],
    );
    await db.query("commit");
    await db.query("begin");
    await as(CLIENT_A_ID, "aal1");
    await db.query("set local role authenticated");
    const acc = await db.query(
      "select public.accept_agreement($1, true, true, 'Alex Client', $2, 'Owner', true) as r",
      [os.rows[0].r.order_summary_id, `E2E WP-C ${RUN} LLC`],
    );
    const cs = await db.query("select public.begin_initial_checkout($1) as r", [releaseProjectId]);
    await db.query("commit");
    await db.query("begin");
    await db.query(`select set_config('request.jwt.claims', '{"role":"service_role"}', true)`);
    await db.query("set local role service_role");
    const requests = await db.query(
      `select id, purpose from public.outbound_stripe_requests where project_id = $1
        order by (purpose = 'customer_create') desc`,
      [releaseProjectId],
    );
    for (const r of requests.rows) {
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
        [r.id, token, r.purpose === "customer_create" ? `cus_wpc${RUN}` : `cs_test_wpc${RUN}`],
      );
    }
    await db.query("commit");
    return {
      os: os.rows[0].r.order_summary_id as string,
      acceptance: acc.rows[0].r.acceptance_id as string,
      checkout: cs.rows[0].r.checkout_session_id as string,
    };
  });
  const s5Secret = process.env.E2E_STRIPE_WEBHOOK_SECRET ?? "";
  if (!/^whsec_[A-Za-z0-9]+$/.test(s5Secret)) throw new Error("setup: no test-only webhook secret");
  const s5Now = Math.floor(Date.now() / 1000);
  const s5Body = JSON.stringify({
    id: `evt_wpc${RUN}checkout`,
    object: "event",
    type: "checkout.session.completed",
    api_version: "2026-09-30.endive",
    livemode: false,
    created: s5Now,
    data: {
      object: {
        id: `cs_test_wpc${RUN}`,
        object: "checkout.session",
        mode: "subscription",
        currency: "usd",
        amount_total: 25900,
        payment_status: "paid",
        customer: `cus_wpc${RUN}`,
        subscription: `sub_wpc${RUN}`,
        invoice: `in_wpc${RUN}`,
        total_details: { amount_discount: 0, amount_tax: 0 },
        metadata: {
          project_id: releaseProjectId,
          order_summary_id: s5.os,
          acceptance_id: s5.acceptance,
          checkout_record_id: s5.checkout,
        },
      },
    },
  });
  const s5Sig = createHmac("sha256", s5Secret).update(`${s5Now}.${s5Body}`, "utf8").digest("hex");
  const s5Response = await clientPage.request.post("/api/stripe/webhook", {
    data: s5Body,
    headers: { "content-type": "application/json", "stripe-signature": `t=${s5Now},v1=${s5Sig}` },
  });
  if (s5Response.status() !== 200)
    throw new Error(`setup: webhook delivery ${s5Response.status()}`);
  await staffPage.goto(`/staff/projects/${releaseProjectId}`);
  await staffPage.getByLabel("Client requirements").fill("Synthetic client requirements");
  await staffPage
    .getByLabel("Confirmed fulfillment selections (one per line)")
    .fill("Synthetic selection");
  await staffPage.getByRole("button", { name: "Record scope confirmation" }).click();
  await staffPage.waitForURL(/notice=scope_confirmation_recorded/);
  await clientPage.goto(`/portal/projects/${releaseProjectId}`);
  await clientPage.getByLabel(/scope confirmation version 1 and acknowledge it/).check();
  await clientPage.getByRole("button", { name: "Acknowledge scope confirmation" }).click();
  await clientPage.waitForURL(/notice=scope_acknowledged/);
  const before = await lastAuditId();
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
  // M2: exactly one release record, as entered, by the Admin, with its audit event.
  const releases = await withDb(async (db) => {
    const { rows } = await db.query(
      `select id::text, release_number, commit_sha, deployment_id, preview_url, released_by::text,
              withdrawn_at is null as current
         from public.preview_releases where project_id = $1`,
      [releaseProjectId],
    );
    return rows;
  });
  expect(releases).toEqual([
    {
      id: expect.any(String),
      release_number: 1,
      commit_sha: "a".repeat(40),
      deployment_id: `dpl_${RUN}`,
      preview_url: "https://preview.example.test/build",
      released_by: ADMIN_ID,
      current: true,
    },
  ]);
  const written = (await auditSince(before)).filter((e) => e.action === "preview.released");
  expect(written).toEqual([
    {
      action: "preview.released",
      actor: ADMIN_ID,
      project: releaseProjectId,
      summary: expect.any(Object),
    },
  ]);
});
