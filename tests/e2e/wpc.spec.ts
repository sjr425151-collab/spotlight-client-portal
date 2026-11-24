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
