import { randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { withDb } from "../support/db";

/**
 * WP-H (AUTH-006) integration tests against the local stack, with real concurrent database
 * connections (synthetic sessions, as in pgTAP and tests/integration/wps-sales.test.ts).
 *
 * OI-86: issue_order_summary locks the project row FOR NO KEY UPDATE (20261126120000). Each case
 * below runs both orders deterministically: the first transaction holds its lock while the
 * second is shown to wait; the first commits; the second's outcome is asserted. A deadlock
 * abort (40P01) is never a passing outcome: every statement must return normally.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const RUN = Date.now().toString(36);

async function clearLimits() {
  await withDb((db) =>
    db.query("delete from private.rate_limits where bucket like 'sales-%' or bucket = $1", [
      `invite:${SALES_ID}`,
    ]),
  );
}
beforeEach(clearLimits);
afterAll(clearLimits);

async function dbSession(userId: string, aal: "aal1" | "aal2" = "aal2"): Promise<string> {
  const sid = randomUUID();
  await withDb(async (db) => {
    await db.query(
      "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), $3)",
      [sid, userId, aal],
    );
    if (aal === "aal2") {
      await db.query(
        `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
         select gen_random_uuid(), $1, 'it-wph', 'totp', 'verified', now(), now()
         where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
        [userId],
      );
    }
  });
  return sid;
}

/** A connection inside an open transaction, acting as `userId` in session `sid`. */
async function openTx(userId: string, sid: string): Promise<Client> {
  const url =
    process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("local only");
  const c = new Client({ connectionString: url });
  await c.connect();
  await c.query("begin");
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: "authenticated", aal: "aal2", session_id: sid, amr: [] }),
  ]);
  await c.query("set local role authenticated");
  return c;
}
async function close(c: Client, commit: boolean) {
  await c.query(commit ? "commit" : "rollback");
  await c.end();
}
type Result = { ok: boolean; error?: string } & Record<string, unknown>;
async function rpc(c: Client, sql: string, params: unknown[] = []): Promise<Result> {
  const { rows } = await c.query(`select (${sql}) as r`, params);
  return rows[0].r as Result;
}
async function once(userId: string, sid: string, sql: string, params: unknown[] = []) {
  const c = await openTx(userId, sid);
  try {
    return await rpc(c, sql, params);
  } finally {
    await close(c, true);
  }
}
/** Starts a call that is expected to block; reports whether it was still pending after 400 ms. */
async function startBlocked<T>(p: Promise<T>): Promise<{ result: Promise<T>; blocked: boolean }> {
  let settled = false;
  const result = p.finally(() => {
    settled = true;
  });
  await new Promise((r) => setTimeout(r, 400));
  return { result, blocked: !settled };
}

async function newClientUser(email: string): Promise<string> {
  const id = randomUUID();
  await withDb((db) =>
    db.query(
      `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
         raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
         email_change_token_new, email_change, email_change_token_current, reauthentication_token,
         phone_change, phone_change_token)
       values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2, '', now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '')`,
      [id, email],
    ),
  );
  return id;
}

/** A Sales project with a presented Sales order summary and a client member. */
async function salesProject(label: string) {
  await clearLimits();
  const sid = await dbSession(SALES_ID);
  const ownerSid = await dbSession(OWNER_ID);
  const legalName = `WPH ${label} ${RUN} LLC`;
  const project = await once(SALES_ID, sid, "public.sales_create_customer_project($1, null, $2)", [
    legalName,
    `${label} site`,
  ]);
  expect(project.ok).toBe(true);
  const projectId = project.project_id as string;
  const summary = await once(SALES_ID, sid, "public.issue_order_summary($1, 'essential')", [
    projectId,
  ]);
  expect(summary.ok).toBe(true);
  const email = `wph.${label.toLowerCase()}.${RUN}@example.test`;
  const inv = await once(SALES_ID, sid, "public.create_invitation('client', $1, 'Client', $2)", [
    email,
    projectId,
  ]);
  const clientId = await newClientUser(email);
  const clientSid = await dbSession(clientId, "aal1");
  expect(
    (
      await once(clientId, clientSid, "public.accept_invitation($1, $2)", [
        inv.invitation_id,
        inv.token,
      ])
    ).ok,
  ).toBe(true);
  return {
    sid,
    ownerSid,
    projectId,
    orderSummaryId: summary.order_summary_id as string,
    clientId,
    clientSid,
    legalName,
  };
}

const salesIssue = "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'oi86')";
const ownerIssue =
  "public.issue_order_summary($1, 'professional', '[\"Scope\"]'::jsonb, null, 'oi86')";
const acceptSql = "public.accept_agreement($1, true, true, 'Client Signer', $2, 'Owner', true)";

const presented = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select count(*)::int as n, max(revision)::int as revision,
              (array_agg(issued_by::text order by revision desc))[1] as issued_by
         from public.order_summaries where project_id = $1 and status = 'presented'`,
      [projectId],
    );
    return rows[0] as { n: number; revision: number; issued_by: string };
  });

/**
 * Runs `first` in an open transaction, shows `second` waits on it, commits `first`, and returns
 * both outcomes. Any database error (including 40P01) fails the test.
 */
async function serialize(
  first: { user: string; sid: string; sql: string; params: unknown[] },
  second: { user: string; sid: string; sql: string; params: unknown[] },
) {
  const a = await openTx(first.user, first.sid);
  const firstResult = await rpc(a, first.sql, first.params);
  const b = await openTx(second.user, second.sid);
  const pending = await startBlocked(rpc(b, second.sql, second.params));
  expect(pending.blocked).toBe(true);
  await close(a, true);
  const secondResult = await pending.result;
  await close(b, true);
  return { firstResult, secondResult };
}

describe("OI-86: issue_order_summary serializes with every project-lock caller (two connections)", () => {
  it("end_sales_assignment first: the Sales issuance waits, then is refused", async () => {
    const p = await salesProject("EndFirst");
    const assignment = await withDb((db) =>
      db.query("select id from public.project_sales_assignments where project_id = $1 and active", [
        p.projectId,
      ]),
    );
    const { firstResult, secondResult } = await serialize(
      {
        user: OWNER_ID,
        sid: p.ownerSid,
        sql: "public.end_sales_assignment($1, 'oi86')",
        params: [assignment.rows[0].id],
      },
      { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult).toMatchObject({ ok: false, error: "forbidden" });
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 1 });
  });

  it("Sales issuance first: end_sales_assignment waits, then ends the assignment", async () => {
    const p = await salesProject("IssueBeforeEnd");
    const assignment = await withDb((db) =>
      db.query("select id from public.project_sales_assignments where project_id = $1 and active", [
        p.projectId,
      ]),
    );
    const { firstResult, secondResult } = await serialize(
      { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] },
      {
        user: OWNER_ID,
        sid: p.ownerSid,
        sql: "public.end_sales_assignment($1, 'oi86')",
        params: [assignment.rows[0].id],
      },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult.ok).toBe(true);
    // The issuance happened while the assignment was active; it was then ended.
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 2, issued_by: SALES_ID });
    const active = await withDb((db) =>
      db.query(
        "select count(*)::int as n from public.project_sales_assignments where project_id = $1 and active",
        [p.projectId],
      ),
    );
    expect(active.rows[0].n).toBe(0);
  });

  it("assign_sales_representative and issuance serialize in both orders", async () => {
    const p = await salesProject("Assign");
    const assign = {
      user: OWNER_ID,
      sid: p.ownerSid,
      sql: "public.assign_sales_representative($1, $2, 'oi86')",
      params: [p.projectId, SALES_ID],
    };
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    const one = await serialize(assign, issue);
    expect(one.firstResult).toMatchObject({ ok: true, existing: true });
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, assign);
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult).toMatchObject({ ok: true, existing: true });
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("begin_initial_checkout first: the Owner replacement waits, then supersedes the unpaid summary", async () => {
    const p = await salesProject("CheckoutFirst");
    expect(
      (await once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName])).ok,
    ).toBe(true);
    const { firstResult, secondResult } = await serialize(
      {
        user: p.clientId,
        sid: p.clientSid,
        sql: "public.begin_initial_checkout($1)",
        params: [p.projectId],
      },
      { user: OWNER_ID, sid: p.ownerSid, sql: ownerIssue, params: [p.projectId] },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult.ok).toBe(true);
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 2, issued_by: OWNER_ID });
    // The checkout created first stays bound to the summary it was created for.
    const cs = await withDb((db) =>
      db.query(
        "select order_summary_id::text from public.checkout_sessions where project_id = $1",
        [p.projectId],
      ),
    );
    expect(cs.rows).toEqual([{ order_summary_id: p.orderSummaryId }]);
  });

  it("Owner replacement first: begin_initial_checkout waits, then requires the new acceptance", async () => {
    const p = await salesProject("ReplaceBeforeCheckout");
    expect(
      (await once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName])).ok,
    ).toBe(true);
    const { firstResult, secondResult } = await serialize(
      { user: OWNER_ID, sid: p.ownerSid, sql: ownerIssue, params: [p.projectId] },
      {
        user: p.clientId,
        sid: p.clientSid,
        sql: "public.begin_initial_checkout($1)",
        params: [p.projectId],
      },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult).toMatchObject({ ok: false, error: "acceptance_required" });
    const cs = await withDb((db) =>
      db.query("select count(*)::int as n from public.checkout_sessions where project_id = $1", [
        p.projectId,
      ]),
    );
    expect(cs.rows[0].n).toBe(0);
  });

  it("begin_payment_method_recovery and issuance serialize in both orders", async () => {
    const p = await salesProject("Recovery");
    const recovery = {
      user: p.clientId,
      sid: p.clientSid,
      sql: "public.begin_payment_method_recovery($1)",
      params: [p.projectId],
    };
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    // The recovery takes its project lock before its eligibility checks, so it holds the lock
    // (and is refused: no deposit yet) while the issuance waits, and the reverse.
    const one = await serialize(recovery, issue);
    expect(one.firstResult).toMatchObject({ ok: false, error: "deposit_required" });
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, recovery);
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult).toMatchObject({ ok: false, error: "deposit_required" });
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("create_invitation and issuance serialize in both orders", async () => {
    const p = await salesProject("Invite");
    const invite = (n: number) => ({
      user: SALES_ID,
      sid: p.sid,
      sql: "public.create_invitation('client', $1, 'Client', $2)",
      params: [`wph.invite${n}.${RUN}@example.test`, p.projectId],
    });
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    const one = await serialize(invite(1), issue);
    expect(one.firstResult.ok).toBe(true);
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, invite(2));
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult.ok).toBe(true);
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("revoke_invitation and issuance serialize in both orders", async () => {
    const p = await salesProject("Revoke");
    const pending = async (n: number) =>
      (
        await once(SALES_ID, p.sid, "public.create_invitation('client', $1, 'Client', $2)", [
          `wph.revoke${n}.${RUN}@example.test`,
          p.projectId,
        ])
      ).invitation_id as string;
    const revoke = (id: string) => ({
      user: SALES_ID,
      sid: p.sid,
      sql: "public.revoke_invitation($1)",
      params: [id],
    });
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    const one = await serialize(revoke(await pending(1)), issue);
    expect(one.firstResult.ok).toBe(true);
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, revoke(await pending(2)));
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult.ok).toBe(true);
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("the acceptance's foreign-key lock no longer conflicts with the issuer's project lock", async () => {
    // The mechanism of the deadlock, isolated: a connection holds only the lock issuance now
    // takes on the project row. The acceptance's insert takes FOR KEY SHARE through its foreign
    // key and must proceed at once; under the former FOR UPDATE it waited (control below).
    const url =
      process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    for (const [mode, expectWait] of [
      ["for no key update", false],
      ["for update", true],
    ] as const) {
      const p = await salesProject(mode === "for update" ? "LockControl" : "LockNoKey");
      const holder = new Client({ connectionString: url });
      await holder.connect();
      await holder.query("begin");
      await holder.query(`select 1 from public.projects where id = $1 ${mode}`, [p.projectId]);
      const accept = await startBlocked(
        once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName]),
      );
      expect(accept.blocked).toBe(expectWait);
      await holder.query("rollback");
      await holder.end();
      expect((await accept.result).ok).toBe(true);
    }
  });
});
