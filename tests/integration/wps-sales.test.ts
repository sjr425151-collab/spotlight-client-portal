import { randomUUID } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";
import { Client } from "pg";
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";

import { withDb } from "../support/db";
import { accessToken, adminClient, signInWithCode, upgradeToAal2 } from "../support/local-supabase";

/**
 * WP-S integration tests (03 §4.1, §13; AUTH-005) against the local stack. Real Auth sessions
 * (emailed codes, TOTP) for the Sales flows; two real database connections for the concurrency
 * cases, with deterministic interleavings: the first transaction holds its row locks while the
 * second is shown to wait, then the first commits and the second's outcome is asserted.
 */

vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

const OWNER = "owner@example.test";
const ADMIN = "admin@example.test";
const SALES = "sales@example.test";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const RUN = Date.now().toString(36);
const SITE = "http://localhost:3100";

const totpSecrets = new Map<string, string>();
let owner: SupabaseClient;
let admin: SupabaseClient;
let sales: SupabaseClient;

const services = () => import("@/server/services/sales");
const invitationServices = () => import("@/server/services/invitations");

async function resetLocalState() {
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(`delete from auth.mfa_factors where user_id in ($1, $2, $3)`, [
      OWNER_ID,
      "00000000-0000-4000-8000-000000000002",
      SALES_ID,
    ]);
  });
}

beforeAll(async () => {
  await resetLocalState();
  owner = await signInWithCode(OWNER);
  await upgradeToAal2(owner, totpSecrets);
  admin = await signInWithCode(ADMIN);
  await upgradeToAal2(admin, totpSecrets);
  sales = await signInWithCode(SALES);
});

afterAll(resetLocalState);

// ---------------------------------------------------------------------------
// Database sessions for the concurrency cases (synthetic sessions, as in pgTAP)
// ---------------------------------------------------------------------------
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
         select gen_random_uuid(), $1, 'it-wps', 'totp', 'verified', now(), now()
         where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
        [userId],
      );
    }
  });
  return sid;
}

/** A connection inside an open transaction, acting as `userId` in session `sid`. */
async function openTx(userId: string, sid: string, fresh = false): Promise<Client> {
  const url =
    process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("local only");
  const c = new Client({ connectionString: url });
  await c.connect();
  await c.query("begin");
  const amr = fresh ? [{ method: "totp", timestamp: Math.floor(Date.now() / 1000) }] : [];
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: "authenticated", aal: "aal2", session_id: sid, amr }),
  ]);
  await c.query("set local role authenticated");
  return c;
}
async function close(c: Client, commit: boolean) {
  await c.query(commit ? "commit" : "rollback");
  await c.end();
}
async function rpc(c: Client, sql: string, params: unknown[] = []) {
  const { rows } = await c.query(`select (${sql}) as r`, params);
  return rows[0].r as { ok: boolean; error?: string } & Record<string, unknown>;
}
/** Runs `fn` against a fresh committed transaction. */
async function once(userId: string, sid: string, sql: string, params: unknown[] = []) {
  const c = await openTx(userId, sid);
  try {
    return await rpc(c, sql, params);
  } finally {
    await close(c, true);
  }
}
/** Starts a query that is expected to block; reports whether it was still pending after 400 ms. */
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
async function salesProjectWithClient(label: string) {
  const sid = await dbSession(SALES_ID);
  const project = await once(SALES_ID, sid, "public.sales_create_customer_project($1, null, $2)", [
    `${label} ${RUN} LLC`,
    `${label} site`,
  ]);
  expect(project.ok).toBe(true);
  const projectId = project.project_id as string;
  const summary = await once(SALES_ID, sid, "public.issue_order_summary($1, 'essential')", [
    projectId,
  ]);
  expect(summary.ok).toBe(true);
  const email = `${label.toLowerCase()}.${RUN}@example.test`;
  const inv = await once(SALES_ID, sid, "public.create_invitation('client', $1, 'Client', $2)", [
    email,
    projectId,
  ]);
  const clientId = await newClientUser(email);
  const clientSid = await dbSession(clientId, "aal1");
  const accepted = await once(clientId, clientSid, "public.accept_invitation($1, $2)", [
    inv.invitation_id,
    inv.token,
  ]);
  expect(accepted.ok).toBe(true);
  return {
    sid,
    projectId,
    orderSummaryId: summary.order_summary_id as string,
    clientId,
    clientSid,
    legalName: `${label} ${RUN} LLC`,
  };
}

const acceptSql = "public.accept_agreement($1, true, true, 'Client Signer', $2, 'Owner', true)";

// ---------------------------------------------------------------------------
describe("WP-S with real Auth sessions (T-SALES-03, T-SALES-17, T-SALES-26, T-SALES-29, T-SALES-33)", () => {
  it("T-SALES-03: every Sales function refuses the aal1 session; aal2 is accepted", async () => {
    const { data } = await sales.rpc("sales_list_customers");
    expect(data).toMatchObject({ ok: false, error: "forbidden" });
    await upgradeToAal2(sales, totpSecrets);
    const { data: after } = await sales.rpc("sales_list_customers");
    expect(after.ok).toBe(true);
  });

  it("T-SALES-29: the per-user creation limit holds under 12 concurrent requests", async () => {
    await withDb((db) => db.query("delete from private.rate_limits"));
    const mark = await withDb((db) =>
      db.query("select coalesce(max(id), 0)::bigint as id from public.audit_events"),
    );
    const { createCustomerProject } = await services();
    const results = await Promise.all(
      Array.from({ length: 12 }, (_, i) =>
        createCustomerProject(sales, { legalName: `Burst ${RUN} ${i} LLC`, projectName: "Burst" }),
      ),
    );
    expect(results.filter((r) => r.ok)).toHaveLength(10);
    expect(results.filter((r) => !r.ok && r.error === "rate_limited")).toHaveLength(2);
    const audited = await withDb((db) =>
      db.query(
        "select count(*)::int as n from public.audit_events where action = 'sales.rate_limited' and actor_user_id = $1 and id > $2",
        [SALES_ID, mark.rows[0].id],
      ),
    );
    expect(audited.rows[0].n).toBe(2);
  });

  it("T-SALES-17: concurrent duplicate creation requests create exactly one set", async () => {
    await withDb((db) => db.query("delete from private.rate_limits"));
    const { createCustomerProject } = await services();
    const input = { legalName: `Twin ${RUN} LLC`, projectName: "Twin website" };
    const results = await Promise.all(
      Array.from({ length: 5 }, () => createCustomerProject(sales, input)),
    );
    expect(results.every((r) => r.ok)).toBe(true);
    const ids = new Set(results.map((r) => (r.ok ? r.project_id : null)));
    expect(ids.size).toBe(1);
    const counts = await withDb((db) =>
      db.query(
        `select (select count(*)::int from public.client_businesses where legal_name = $1) as b,
                (select count(*)::int from public.project_sales_assignments a
                   join public.projects p on p.id = a.project_id
                   join public.client_businesses c on c.id = p.client_business_id
                  where c.legal_name = $1) as a`,
        [input.legalName],
      ),
    );
    expect(counts.rows[0]).toEqual({ b: 1, a: 1 });
  });

  it("T-SALES-26: an authenticated session loses access at its next call after the assignment ends", async () => {
    const { createCustomerProject, projectProgress } = await services();
    const created = await createCustomerProject(sales, {
      legalName: `Ending ${RUN} LLC`,
      projectName: "Ending site",
    });
    if (!created.ok) throw new Error(created.error);
    expect((await projectProgress(sales, created.project_id)).ok).toBe(true);

    const token = await accessToken(sales);
    const exp = JSON.parse(Buffer.from(token.split(".")[1]!, "base64url").toString()).exp as number;
    const { data: assignment } = await owner
      .from("project_sales_assignments")
      .select("id")
      .eq("project_id", created.project_id)
      .eq("active", true)
      .single();
    const { data: ended } = await owner.rpc("end_sales_assignment", {
      p_assignment_id: assignment!.id,
      p_reason: "integration",
    });
    expect(ended.ok).toBe(true);

    expect(exp * 1000).toBeGreaterThan(Date.now()); // the token is still unexpired
    expect(await projectProgress(sales, created.project_id)).toMatchObject({ ok: false });
    const { data: list } = await sales.rpc("sales_list_customers");
    expect(list.customers.map((c: { project_id: string }) => c.project_id)).not.toContain(
      created.project_id,
    );
    const { data: invite } = await sales.rpc("create_invitation", {
      p_kind: "client",
      p_email: `after.end.${RUN}@example.test`,
      p_full_name: "After End",
      p_project_id: created.project_id,
    });
    expect(invite).toMatchObject({ ok: false, error: "forbidden" });
  });

  it("T-SALES-33: resend revokes and reissues, for Sales, Owner, and Admin", async () => {
    await withDb((db) => db.query("delete from private.rate_limits"));
    const { createCustomerProject, resendClientInvitation } = await services();
    const { resendInvitation } = await invitationServices();
    const created = await createCustomerProject(sales, {
      legalName: `Resend ${RUN} LLC`,
      projectName: "Resend site",
    });
    if (!created.ok) throw new Error(created.error);
    const email = `resend.${RUN}@example.test`;
    const { data: first } = await sales.rpc("create_invitation", {
      p_kind: "client",
      p_email: email,
      p_full_name: "Resend Client",
      p_project_id: created.project_id,
    });
    expect(first.ok).toBe(true);

    const bySales = await resendClientInvitation(
      { user: sales, siteUrl: SITE },
      created.project_id,
      first.invitation_id,
    );
    expect(bySales.ok).toBe(true);
    const { data: oldLink } = await adminClient().rpc("check_invitation_link", {
      p_invitation_id: first.invitation_id,
      p_token: first.token,
    });
    expect(oldLink.ok).toBe(false);

    const pending = async () =>
      withDb((db) =>
        db.query(
          "select id, created_by, expires_at from public.invitations where email = $1 and status = 'pending'",
          [email],
        ),
      );
    const afterSales = (await pending()).rows;
    expect(afterSales).toHaveLength(1);
    expect(afterSales[0].id).not.toBe(first.invitation_id);
    expect(afterSales[0].created_by).toBe(SALES_ID);

    for (const [who, client] of [
      ["owner", owner],
      ["admin", admin],
    ] as const) {
      const current = (await pending()).rows[0];
      const result = await resendInvitation(
        { user: client, siteUrl: SITE },
        {
          id: current.id,
          kind: "client",
          email,
          fullName: "Resend Client",
          projectId: created.project_id,
        },
      );
      expect(result.ok, who).toBe(true);
      const now = (await pending()).rows;
      expect(now, who).toHaveLength(1);
      expect(now[0].id, who).not.toBe(current.id);
    }
    const audit = await withDb((db) =>
      db.query(
        `select actor_role, action from public.audit_events
          where target_type = 'invitations' and action in ('invitation.revoked', 'invitation.created')
            and project_id = $1 order by id`,
        [created.project_id],
      ),
    );
    const roles = new Set(audit.rows.map((r) => r.actor_role));
    expect(roles).toEqual(new Set(["sales", "owner", "admin"]));
  });
});

// ---------------------------------------------------------------------------
describe("WP-S concurrency (two connections)", () => {
  // Setup creates many projects; the per-user limit itself is tested above.
  beforeEach(() =>
    withDb((db) => db.query("delete from private.rate_limits where bucket like 'sales-%'")),
  );

  it("T-SALES-32: acceptance first, then a Sales replacement: the replacement is rejected", async () => {
    const p = await salesProjectWithClient("AcceptFirst");
    const client = await openTx(p.clientId, p.clientSid);
    const accepted = await rpc(client, acceptSql, [p.orderSummaryId, p.legalName]);
    expect(accepted.ok).toBe(true); // holds the order-summary row lock, not committed
    const rep = await openTx(SALES_ID, p.sid);
    const pending = await startBlocked(
      rpc(rep, "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'race')", [
        p.projectId,
      ]),
    );
    expect(pending.blocked).toBe(true);
    await close(client, true);
    const replaced = await pending.result;
    await close(rep, true);
    expect(replaced).toMatchObject({ ok: false, error: "replacement_after_acceptance" });
  });

  it("T-SALES-32: a Sales replacement first, then acceptance: the acceptance is refused", async () => {
    const p = await salesProjectWithClient("ReplaceFirst");
    const rep = await openTx(SALES_ID, p.sid);
    const replaced = await rpc(
      rep,
      "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'race')",
      [p.projectId],
    );
    expect(replaced.ok).toBe(true); // supersedes the presented summary, not committed
    const client = await openTx(p.clientId, p.clientSid);
    const pending = await startBlocked(rpc(client, acceptSql, [p.orderSummaryId, p.legalName]));
    expect(pending.blocked).toBe(true);
    await close(rep, true);
    const accepted = await pending.result;
    await close(client, true);
    expect(accepted).toMatchObject({ ok: false, error: "order_summary_superseded" });
  });

  /** Outcome of one side of a race: ok, refused, or aborted by the database (deadlock). */
  async function side(p: Promise<{ ok: boolean; error?: string }>) {
    try {
      const r = await p;
      return r.ok ? "ok" : `refused:${r.error}`;
    } catch (error) {
      return `aborted:${(error as { code?: string }).code}`;
    }
  }

  // A true race. The WP-B lock order (project row, then order-summary row, in
  // issue_order_summary; order-summary row, then the project's key-share lock through the
  // acceptance foreign key, in accept_agreement) can deadlock; PostgreSQL then aborts one side.
  // Either way exactly one side succeeds and the aborted side leaves no partial state.
  for (const caller of ["sales", "owner"] as const) {
    it(`T-SALES-32: a true race never lets both succeed (${caller} replacement)`, async () => {
      const ownerSid = await dbSession(OWNER_ID);
      const outcomes: string[] = [];
      for (let i = 0; i < 4; i += 1) {
        const p = await salesProjectWithClient(`Race${caller}${i}`);
        const [accept, replace] = await Promise.all([
          side(once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName])),
          side(
            caller === "sales"
              ? once(
                  SALES_ID,
                  p.sid,
                  "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'race')",
                  [p.projectId],
                )
              : once(
                  OWNER_ID,
                  ownerSid,
                  "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'race')",
                  [p.projectId],
                ),
          ),
        ]);
        outcomes.push(`${accept}|${replace}`);
        const state = await withDb((db) =>
          db.query(
            `select (select count(*)::int from public.agreement_acceptances where project_id = $1) as acceptances,
                    (select count(*)::int from public.order_summaries where project_id = $1 and status = 'presented') as presented,
                    (select status::text from public.order_summaries where id = $2) as original`,
            [p.projectId, p.orderSummaryId],
          ),
        );
        const row = state.rows[0];
        expect(row.presented).toBe(1);
        if (caller === "sales") {
          // OI-84(c): never both an acceptance and a Sales replacement.
          expect([accept, replace].filter((o) => o === "ok")).toHaveLength(1);
          expect(row.acceptances === 1 && row.original === "superseded").toBe(false);
        } else {
          // Owner path unchanged (04 §4): a replacement after acceptance is allowed (reacceptance).
          expect(accept === "ok" || replace === "ok").toBe(true);
        }
        expect(row.acceptances).toBe(accept === "ok" ? 1 : 0);
      }
      console.warn(`T-SALES-32 race outcomes (${caller}): ${outcomes.join(", ")}`);
    });
  }

  it("concurrent assignment termination and a Sales write: the write waits and is refused", async () => {
    const p = await salesProjectWithClient("Terminate");
    const ownerSid = await dbSession(OWNER_ID);
    const assignment = await withDb((db) =>
      db.query("select id from public.project_sales_assignments where project_id = $1 and active", [
        p.projectId,
      ]),
    );
    const staff = await openTx(OWNER_ID, ownerSid);
    expect(
      (await rpc(staff, "public.end_sales_assignment($1, 'race')", [assignment.rows[0].id])).ok,
    ).toBe(true);
    const rep = await openTx(SALES_ID, p.sid);
    const issue = await startBlocked(
      rpc(rep, "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'race')", [
        p.projectId,
      ]),
    );
    expect(issue.blocked).toBe(true);
    await close(staff, true);
    expect(await issue.result).toMatchObject({ ok: false, error: "forbidden" });
    await close(rep, true);
  });

  it("concurrent assignment termination and a Sales invitation: the invitation waits and is refused", async () => {
    const sid = await dbSession(SALES_ID);
    const created = await once(
      SALES_ID,
      sid,
      "public.sales_create_customer_project($1, null, 'T2')",
      [`Terminate2 ${RUN} LLC`],
    );
    const ownerSid = await dbSession(OWNER_ID);
    const assignment = await withDb((db) =>
      db.query("select id from public.project_sales_assignments where project_id = $1 and active", [
        created.project_id,
      ]),
    );
    const staff = await openTx(OWNER_ID, ownerSid);
    await rpc(staff, "public.end_sales_assignment($1, 'race')", [assignment.rows[0].id]);
    const rep = await openTx(SALES_ID, sid);
    const invite = await startBlocked(
      rpc(rep, "public.create_invitation('client', $1, 'X', $2)", [
        `t2.${RUN}@example.test`,
        created.project_id,
      ]),
    );
    expect(invite.blocked).toBe(true);
    await close(staff, true);
    expect(await invite.result).toMatchObject({ ok: false, error: "forbidden" });
    await close(rep, true);
  });

  it("concurrent invitation revocation and acceptance: revocation first wins, the acceptance fails", async () => {
    const sid = await dbSession(SALES_ID);
    const created = await once(
      SALES_ID,
      sid,
      "public.sales_create_customer_project($1, null, 'RA')",
      [`RevokeAccept ${RUN} LLC`],
    );
    const email = `revoke.accept.${RUN}@example.test`;
    const inv = await once(SALES_ID, sid, "public.create_invitation('client', $1, 'X', $2)", [
      email,
      created.project_id,
    ]);
    const clientId = await newClientUser(email);
    const clientSid = await dbSession(clientId, "aal1");
    const rep = await openTx(SALES_ID, sid);
    expect((await rpc(rep, "public.revoke_invitation($1)", [inv.invitation_id])).ok).toBe(true);
    const client = await openTx(clientId, clientSid);
    const accept = await startBlocked(
      rpc(client, "public.accept_invitation($1, $2)", [inv.invitation_id, inv.token]),
    );
    expect(accept.blocked).toBe(true);
    await close(rep, true);
    expect(await accept.result).toMatchObject({ ok: false, error: "invalid" });
    await close(client, true);
    const members = await withDb((db) =>
      db.query("select count(*)::int as n from public.project_memberships where user_id = $1", [
        clientId,
      ]),
    );
    expect(members.rows[0].n).toBe(0);
  });

  it("concurrent invitation acceptance and revocation: acceptance first wins, the revocation finds nothing", async () => {
    const sid = await dbSession(SALES_ID);
    const created = await once(
      SALES_ID,
      sid,
      "public.sales_create_customer_project($1, null, 'AR')",
      [`AcceptRevoke ${RUN} LLC`],
    );
    const email = `accept.revoke.${RUN}@example.test`;
    const inv = await once(SALES_ID, sid, "public.create_invitation('client', $1, 'X', $2)", [
      email,
      created.project_id,
    ]);
    const clientId = await newClientUser(email);
    const clientSid = await dbSession(clientId, "aal1");
    const client = await openTx(clientId, clientSid);
    expect(
      (await rpc(client, "public.accept_invitation($1, $2)", [inv.invitation_id, inv.token])).ok,
    ).toBe(true);
    const rep = await openTx(SALES_ID, sid);
    const revoke = await startBlocked(
      rpc(rep, "public.revoke_invitation($1)", [inv.invitation_id]),
    );
    expect(revoke.blocked).toBe(true);
    await close(client, true);
    expect(await revoke.result).toMatchObject({ ok: false, error: "not_found" });
    await close(rep, true);
  });

  it("T-SALES-24: a Sales user and a client invitation never overlap under a race", async () => {
    // The Owner grants the Sales role while the user accepts a client invitation.
    const email = `overlap.${RUN}@example.test`;
    const userId = await newClientUser(email);
    await withDb(async (db) => {
      await db.query(
        "insert into public.profiles (id, email, full_name) values ($1, $2, 'Overlap')",
        [userId, email],
      );
      await db.query("insert into public.staff_roles (user_id, role) values ($1, 'admin')", [
        userId,
      ]);
    });
    const ownerSid = await dbSession(OWNER_ID);
    const inv = await once(
      OWNER_ID,
      ownerSid,
      "public.create_invitation('client', $1, 'Overlap', '20000000-0000-4000-8000-0000000000a0')",
      [email],
    );
    expect(inv.ok).toBe(true);
    const userSid = await dbSession(userId);
    const [roleChange, accept] = await Promise.all([
      (async () => {
        const c = await openTx(OWNER_ID, ownerSid, true);
        try {
          return await rpc(c, "public.set_staff_role($1, 'sales', 'race')", [userId]);
        } finally {
          await close(c, true);
        }
      })(),
      once(userId, userSid, "public.accept_invitation($1, $2)", [inv.invitation_id, inv.token]),
    ]);
    const state = await withDb((db) =>
      db.query(
        `select (select role::text from public.staff_roles where user_id = $1 and status = 'active') as role,
                (select count(*)::int from public.project_memberships where user_id = $1 and status = 'active') as m`,
        [userId],
      ),
    );
    // Either order is allowed, but never a Sales role together with a membership.
    expect(state.rows[0].role === "sales" && state.rows[0].m > 0).toBe(false);
    expect([roleChange.ok, accept.ok].filter(Boolean).length).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// OI-85 (CURRENT-STATE §12): integrity triggers under concurrency, and authorization that holds
// without them. Direct writers are the migration owner (privileged writer) on two connections.
// ---------------------------------------------------------------------------
async function ownerTx(): Promise<Client> {
  const url =
    process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("local only");
  const c = new Client({ connectionString: url });
  await c.connect();
  await c.query("begin");
  return c;
}
async function freshUser(label: string, role?: "admin" | "sales"): Promise<string> {
  const email = `${label}.${RUN}.${Math.random().toString(36).slice(2, 7)}@example.test`;
  const id = await newClientUser(email);
  await withDb(async (db) => {
    await db.query("insert into public.profiles (id, email, full_name) values ($1, $2, 'OI-85')", [
      id,
      email,
    ]);
    if (role)
      await db.query("insert into public.staff_roles (user_id, role) values ($1, $2)", [id, role]);
  });
  return id;
}
const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
const outcome = async (p: Promise<unknown>) => {
  try {
    await p;
    return "ok";
  } catch (error) {
    return `error:${(error as { code?: string }).code}`;
  }
};

describe("OI-85 integrity triggers under concurrency (T-SALES-24)", () => {
  it("a membership write first, then a Sales role grant: the grant waits and is refused", async () => {
    const user = await freshUser("oi85-m-first", "admin");
    const t1 = await ownerTx();
    await t1.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
      PROJECT_B,
      user,
    ]);
    const t2 = await ownerTx();
    const grant = await startBlocked(
      outcome(t2.query("update public.staff_roles set role = 'sales' where user_id = $1", [user])),
    );
    expect(grant.blocked).toBe(true);
    await close(t1, true);
    expect(await grant.result).toBe("error:42501");
    await close(t2, false);
  });

  it("a Sales role grant first, then a membership write: the membership waits and is refused", async () => {
    const user = await freshUser("oi85-r-first", "admin");
    const t1 = await ownerTx();
    await t1.query("update public.staff_roles set role = 'sales' where user_id = $1", [user]);
    const t2 = await ownerTx();
    const member = await startBlocked(
      outcome(
        t2.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
          PROJECT_B,
          user,
        ]),
      ),
    );
    expect(member.blocked).toBe(true);
    await close(t1, true);
    expect(await member.result).toBe("error:42501");
    await close(t2, false);
  });

  it("true races between direct writers never leave a Sales role together with a membership", async () => {
    for (let i = 0; i < 6; i += 1) {
      const user = await freshUser(`oi85-race-${i}`, "admin");
      const run = async (sql: string) => {
        const c = await ownerTx();
        try {
          await c.query(sql, [user]);
          await c.query("commit");
          return "ok";
        } catch (error) {
          await c.query("rollback");
          return `error:${(error as { code?: string }).code}`;
        } finally {
          await c.end();
        }
      };
      const results = await Promise.all([
        run("update public.staff_roles set role = 'sales' where user_id = $1"),
        run(
          `insert into public.project_memberships (project_id, user_id) values ('${PROJECT_B}', $1)`,
        ),
      ]);
      expect(results.filter((r) => r === "ok")).toHaveLength(1);
      expect(results.filter((r) => r === "error:42501")).toHaveLength(1);
      const state = await withDb((db) =>
        db.query(
          `select (select role::text from public.staff_roles where user_id = $1 and status = 'active') as role,
                  (select count(*)::int from public.project_memberships where user_id = $1 and status = 'active') as m`,
          [user],
        ),
      );
      expect(state.rows[0].role === "sales" && state.rows[0].m > 0).toBe(false);
    }
  });

  it("service_role writes are refused by the triggers in both directions", async () => {
    const client = await freshUser("oi85-svc-client");
    await withDb((db) =>
      db.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
        PROJECT_B,
        client,
      ]),
    );
    const svc = adminClient();
    const role = await svc.from("staff_roles").insert({ user_id: client, role: "sales" });
    expect(role.error?.code).toBe("42501");
    expect(role.error?.message).toMatch(/cannot hold an active Sales role/);
    const member = await svc
      .from("project_memberships")
      .insert({ project_id: PROJECT_B, user_id: SALES_ID });
    expect(member.error?.code).toBe("42501");
    expect(member.error?.message).toMatch(/cannot hold an active project membership/);
  });
});

describe("OI-85 authorization without the triggers: released-file access (T-SALES-24)", () => {
  it("a real Sales session holding an inconsistent membership is refused the released file", async () => {
    // Controlled local-only fixture: a separate project, an available upload row, and a Sales
    // membership inserted with the C2 trigger disabled by name only inside that one transaction
    // (DDL is transactional: no other session ever sees the trigger disabled). Removed after.
    const projectId = randomUUID();
    const uploadId = randomUUID();
    await withDb(async (db) => {
      await db.query("begin");
      await db.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ sub: OWNER_ID, role: "authenticated" }),
      ]);
      const business = await db.query(
        "insert into public.client_businesses (legal_name, display_name) values ($1, 'OI-85') returning id",
        [`OI-85 ${RUN} LLC`],
      );
      await db.query(
        "insert into public.projects (id, client_business_id, name) values ($1, $2, 'OI-85 site')",
        [projectId, business.rows[0].id],
      );
      await db.query(
        `insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
           original_name, status, quarantine_path, released_path, size_bytes, sha256, released_sha256, released_bytes,
           completed_at, uploaded_by)
         values ($1, $2, gen_random_uuid(), 1, 'logo', 'image/png', 100, 'f.png', 'available', $3, $4, 100,
           repeat('4', 64), repeat('4', 64), 100, now(), $5)`,
        [
          uploadId,
          projectId,
          `quarantine/${projectId}/${uploadId}`,
          `${projectId}/assets/${uploadId}`,
          OWNER_ID,
        ],
      );
      await db.query(
        "alter table public.project_memberships disable trigger project_memberships_sales_separation",
      );
      await db.query(
        "insert into public.project_memberships (project_id, user_id) values ($1, $2)",
        [projectId, SALES_ID],
      );
      await db.query(
        "alter table public.project_memberships enable trigger project_memberships_sales_separation",
      );
      await db.query("commit");
    });
    try {
      const { deliverAsset } = await import("@/server/uploads/delivery");
      expect(await deliverAsset(sales, adminClient(), projectId, uploadId)).toEqual({
        ok: false,
        error: "not_found",
      });
      const { data: rpc } = await sales.rpc("record_asset_access", { p_upload_id: uploadId });
      expect(rpc).toMatchObject({ ok: false });
      const { data: status } = await sales.rpc("project_status", { p_project_id: projectId });
      expect(status).toMatchObject({ ok: false });
      // requireProjectAccess resolves the project through RLS: nothing, so the route is a 404.
      const { data: projects } = await sales.from("projects").select("id").eq("id", projectId);
      expect(projects).toEqual([]);
      const { data: uploads } = await sales.from("asset_uploads").select("id").eq("id", uploadId);
      expect(uploads).toEqual([]);
      const audit = await withDb((db) =>
        db.query(
          "select count(*)::int as n from public.audit_events where action = 'upload.accessed' and target_id = $1",
          [uploadId],
        ),
      );
      expect(audit.rows[0].n).toBe(0);
      const trigger = await withDb((db) =>
        db.query(
          "select tgenabled::text as e from pg_trigger where tgname = 'project_memberships_sales_separation'",
        ),
      );
      expect(trigger.rows[0].e).toBe("O");
    } finally {
      await withDb((db) =>
        db.query("delete from public.project_memberships where project_id = $1 and user_id = $2", [
          projectId,
          SALES_ID,
        ]),
      );
    }
  });
});
