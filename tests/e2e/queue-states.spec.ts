import { expect, test } from "@playwright/test";
import { Client } from "pg";

import { withDb } from "../support/db";
import { expectAccessible, staffPageAtAal2 } from "../support/e2e";

/**
 * AUTH-026 (OI-131): the staff work queue's four states, each with the WCAG 2.2 AA checks.
 * Runs in its own Playwright project after every project that visits the queue, so the
 * test-only mechanisms below (recorded by Main in FD-14 form) never affect another test:
 *
 * - loading: a test transaction holds ACCESS EXCLUSIVE on public.projects, so the queue's
 *   database call waits and the route-level loading state is shown; releasing it resolves the
 *   page to its result.
 * - failed: the same lock is held past the existing 8 s statement timeout of the
 *   authenticated role (nothing is changed), so the call fails for real; the page shows the
 *   failure with a retry link, never "Nothing needs attention.".
 * - empty: every active project is archived in one committed transaction and exactly those
 *   projects are restored afterwards, so the queue succeeds with no items.
 * - populated: the existing groups.
 *
 * LOCAL Supabase stack and synthetic data only.
 */

const ADMIN = "admin@example.test";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

test.describe.configure({ mode: "serial" });

/** A connection holding ACCESS EXCLUSIVE on public.projects until `release` is called. */
async function holdProjectsLock() {
  const c = new Client({ connectionString: DB_URL });
  await c.connect();
  // WP-I N-1: bounded waits; and if this process dies, the server ends the idle transaction.
  await c.query(
    "set lock_timeout = '15s'; set statement_timeout = '20s'; set idle_in_transaction_session_timeout = '60s'",
  );
  await c.query("begin");
  await c.query("lock table public.projects in access exclusive mode");
  let released = false;
  return {
    release: async () => {
      if (released) return;
      released = true;
      try {
        await c.query("rollback");
      } finally {
        await c.end();
      }
    },
  };
}

test("AUTH-026: loading, then populated", async ({ browser }) => {
  const { page } = await staffPageAtAal2(browser, ADMIN, ADMIN_ID);
  const lock = await holdProjectsLock();
  try {
    const navigation = page.goto("/staff/queue");
    await expect(
      page.getByRole("status").filter({ hasText: "Loading the work queue" }),
    ).toBeVisible();
    await expectAccessible(page);
    await lock.release();
    await navigation;
  } finally {
    await lock.release();
  }
  await expect(page.getByRole("heading", { name: "Work queue" })).toBeVisible();
  await expect(page.locator("main section[aria-labelledby^='q-']").first()).toBeVisible();
  await expect(page.getByText("Nothing needs attention.")).toHaveCount(0);
  await expectAccessible(page);
});

test("AUTH-026: a failed call is shown as a failure with a retry, never as an empty queue", async ({
  browser,
}) => {
  test.setTimeout(90_000);
  const { page } = await staffPageAtAal2(browser, ADMIN, ADMIN_ID);
  const lock = await holdProjectsLock();
  try {
    await page.goto("/staff/queue", { timeout: 60_000 });
    await expect(page.getByRole("heading", { name: "Work queue" })).toBeVisible();
    await expect(page.getByRole("alert")).toContainText("The work queue could not be loaded.");
    await expect(page.getByText("Nothing needs attention.")).toHaveCount(0);
    await expect(page.locator("main section[aria-labelledby^='q-']")).toHaveCount(0);
    await expectAccessible(page);
  } finally {
    await lock.release();
  }
  await page.getByRole("link", { name: "Try again" }).click();
  await expect(page.locator("main section[aria-labelledby^='q-']").first()).toBeVisible();
  await expect(page.getByRole("alert")).toHaveCount(0);
});

test("AUTH-026: a successful, empty result shows Nothing needs attention", async ({ browser }) => {
  const { page } = await staffPageAtAal2(browser, ADMIN, ADMIN_ID);
  const activeCount = () =>
    withDb(
      async (db) =>
        (await db.query("select count(*)::int as n from public.projects where archived_at is null"))
          .rows[0].n as number,
    );
  const before = await activeCount();
  const auditMark = await withDb(
    async (db) =>
      (await db.query("select coalesce(max(id), 0)::text as id from public.audit_events")).rows[0]
        .id as string,
  );
  const archived = await withDb(async (db) =>
    (
      await db.query(
        "update public.projects set archived_at = now() where archived_at is null returning id::text",
      )
    ).rows
      .map((r) => r.id as string)
      .sort(),
  );
  let restored: string[] = [];
  try {
    await page.goto("/staff/queue");
    await expect(page.getByRole("heading", { name: "Work queue" })).toBeVisible();
    await expect(page.getByText("Nothing needs attention.")).toBeVisible();
    await expect(page.getByRole("alert")).toHaveCount(0);
    await expectAccessible(page);
  } finally {
    restored = await withDb(async (db) =>
      (
        await db.query(
          "update public.projects set archived_at = null where id = any($1::uuid[]) returning id::text",
          [archived],
        )
      ).rows
        .map((r) => r.id as string)
        .sort(),
    );
  }
  // FD-14 condition 2: exactly the archived projects are restored, and nothing else changed.
  expect(archived.length).toBe(before);
  expect(restored).toEqual(archived);
  expect(await activeCount()).toBe(before);
  // FD-14 audit ruling (A): the only audit rows written are the append-only project.updated
  // rows of the archive and the restore, exactly two for each archived project.
  const audits = await withDb(
    async (db) =>
      (
        await db.query(
          `select action, project_id::text as project from public.audit_events
            where id > $1::bigint order by id`,
          [auditMark],
        )
      ).rows as { action: string; project: string }[],
  );
  expect([...new Set(audits.map((a) => a.action))]).toEqual(["project.updated"]);
  expect(audits.length).toBe(2 * archived.length);
  const perProject = new Map<string, number>();
  for (const a of audits) perProject.set(a.project, (perProject.get(a.project) ?? 0) + 1);
  expect([...perProject.keys()].sort()).toEqual(archived);
  expect([...perProject.values()].every((n) => n === 2)).toBe(true);
});
