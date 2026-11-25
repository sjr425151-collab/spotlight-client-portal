import AxeBuilder from "@axe-core/playwright";
import { expect, type Browser, type Page } from "@playwright/test";

import { withDb } from "./db";
import { clearMailbox, codeFrom, waitForEmail } from "./mailpit";
import { totp } from "./totp";

/**
 * Shared browser-test helpers for the integrated R1 suite (AUTH-008 I-1 item 4; used by the
 * isolated `r1` Playwright project in I-2). LOCAL Supabase stack and synthetic users only.
 * The same steps as the per-package specs (wpc.spec.ts, wpb.spec.ts, wps.spec.ts), which keep
 * their own copies unchanged.
 */

/** WCAG 2.2 AA checks (spec 02 §7); every violation is reported by rule and node count. */
export async function expectAccessible(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "wcag22aa"])
    .analyze();
  expect(results.violations.map(({ id, nodes }) => ({ id, count: nodes.length }))).toEqual([]);
}

/** A page in a new, isolated browser context. */
export async function newPage(browser: Browser): Promise<Page> {
  return (await browser.newContext()).newPage();
}

/**
 * Signs in with an emailed code read from the local Mailpit. Waits past the local Auth's
 * one-second `max_frequency` between codes for one address (supabase/config.toml).
 */
export async function signIn(page: Page, email: string) {
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

/**
 * Signs a staff user in at aal2 in a new context, enrolling a fresh TOTP factor for this run
 * (any earlier factor of that synthetic user is removed first). Returns the page and the
 * enrolled secret, so a later reauthentication step can produce codes.
 */
export async function staffPageAtAal2(
  browser: Browser,
  email: string,
  userId: string,
  landing: RegExp = /\/staff/,
): Promise<{ page: Page; totpSecret: string }> {
  await withDb((db) => db.query("delete from auth.mfa_factors where user_id = $1", [userId]));
  const page = await newPage(browser);
  await signIn(page, email);
  await expect(page).toHaveURL(/\/mfa/);
  await page.getByRole("button", { name: "Set up authenticator app" }).click();
  const totpSecret = (await page.locator("code").textContent())?.trim() ?? "";
  await page.getByLabel("Authenticator code").fill(totp(totpSecret));
  await page.getByRole("button", { name: "Verify and continue" }).click();
  await expect(page).toHaveURL(landing);
  return { page, totpSecret };
}

/** The newest audit event id: evidence written after this point has a larger id. */
export const lastAuditId = () =>
  withDb(async (db) => {
    const { rows } = await db.query(
      "select coalesce(max(id), 0)::text as id from public.audit_events",
    );
    return rows[0].id as string;
  });

export type AuditRow = {
  action: string;
  actor: string | null;
  project: string | null;
  summary: Record<string, unknown>;
};

/** Audit events written after `afterId`, oldest first. */
export const auditSince = (afterId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select action, actor_user_id::text as actor, project_id::text as project, summary
         from public.audit_events where id > $1::bigint order by id`,
      [afterId],
    );
    return rows as AuditRow[];
  });

/** Rows of a `public` table that belong to one project (table names are fixed identifiers). */
export const countRows = (table: string, projectId: string) => {
  if (!/^[a-z_]+$/.test(table)) throw new Error(`countRows: invalid table name ${table}`);
  return withDb(async (db) => {
    const { rows } = await db.query(
      `select count(*)::int as n from public.${table} where project_id = $1`,
      [projectId],
    );
    return rows[0].n as number;
  });
};
