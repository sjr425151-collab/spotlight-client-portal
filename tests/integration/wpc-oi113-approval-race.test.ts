import { randomUUID } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";
import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

// The billing service used by createPaidProject imports the admin client module; the same
// mock as tests/integration/wpb-billing.test.ts (the local stack's secret-key client).
vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

import { withDb } from "../support/db";
import { signInWithCode, upgradeToAal2 } from "../support/local-supabase";
import { createPaidProject } from "../support/wpc-fixtures";

/**
 * AUTH-013 (OI-113): two clients approve the same current release at the same time, against the
 * LOCAL stack with real parallel database connections. WP-C's real release_preview and
 * approve_preview, WP-H's real consumer (private.consume_release_approved), and a project paid
 * through the real WP-B workflow (createPaidProject; no financial function is replaced).
 *
 * approve_preview records the first approval inserted under the per-project release lock and
 * emits release.approved for it, once. approved_at is the inserting transaction's start time,
 * so a transaction that began first but took the lock second records the EARLIER approved_at
 * (PR #35 B-1). The fulfillment interface must name the approval the canonical event names in
 * both lock orders, so the consumer creates exactly one obligation.
 *
 *   Inverted: B begins first; A approves and commits; then B approves (B-1's order).
 *   Natural:  A approves and holds the lock; B's approve_preview is seen waiting on a Lock in
 *             pg_stat_activity; A commits; B completes.
 *
 * Each order runs at least 20 times on a fresh paid project and release. A deadlock (40P01) or
 * any other database error fails the test. Created final-balance requests are settled afterwards
 * through the executor's normal path (as in tests/integration/wph-hardening.test.ts).
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const CLIENT_B_ID = "00000000-0000-4000-8000-0000000000b1";
const REPETITIONS = 20;
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

let owner: SupabaseClient;
let clientA: SupabaseClient;
const projects: string[] = [];

// Session-local helpers for one setup transaction: client B's membership (as the Owner), WP-C's
// real intake (client A saves and submits; the Admin accepts) and release_preview (the Admin).
const SETUP_HELPERS = `
create function pg_temp.act_as(p_uid uuid, p_aal text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'it-oi113', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', '[]'::jsonb)::text, true);
  set local role authenticated;
end; $$;
create function pg_temp.release_ready(p_project uuid, p_sha text) returns uuid language plpgsql as $$
declare v_draft uuid; v_sub uuid; v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"${OWNER_ID}","role":"authenticated","aal":"aal2"}', true);
  insert into public.project_memberships (project_id, user_id) values (p_project, '${CLIENT_B_ID}');
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_draft := (public.save_intake_draft(p_project, jsonb_build_object('business_legal_name', 'OI-113 LLC',
    'business_display_name', 'OI-113', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
    'address', '1 Test Street', 'service_areas', 'Test City', 'services_offered', 'Testing',
    'domain_status', 'needs_domain')) ->> 'draft_id')::uuid;
  v_sub := (public.submit_intake(p_project, v_draft) ->> 'submission_id')::uuid;
  reset role;
  perform pg_temp.act_as('${ADMIN_ID}', 'aal2');
  if not coalesce((public.review_intake(v_sub, 'accepted', 'Accepted') ->> 'ok')::boolean, false) then
    raise exception 'fixture: intake for % was not accepted', p_project;
  end if;
  v := public.release_preview(p_project, p_sha, 'dpl_oi113_' || left(p_sha, 12), 'https://preview.example.test/oi113', '{}');
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: release_preview failed: %', v;
  end if;
  return (v ->> 'release_id')::uuid;
end; $$;`;

const sha = () => (randomUUID() + randomUUID()).replace(/-/g, "").slice(0, 40);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** A fresh paid project (real WP-B flow), with clients A and B, accepted intake and release 1. */
async function paidRelease(label: string): Promise<{ projectId: string; releaseId: string }> {
  await withDb((db) => db.query("delete from private.rate_limits"));
  const { projectId } = await createPaidProject({
    label,
    owner,
    client: clientA,
    clientUserId: CLIENT_A_ID,
  });
  projects.push(projectId);
  const releaseId = await withDb(async (db) => {
    await db.query("begin");
    await db.query(SETUP_HELPERS);
    const { rows } = await db.query("select pg_temp.release_ready($1, $2) as r", [
      projectId,
      sha(),
    ]);
    await db.query("commit");
    return rows[0].r as string;
  });
  return { projectId, releaseId };
}

async function dbSession(userId: string): Promise<string> {
  const sid = randomUUID();
  await withDb((db) =>
    db.query(
      "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), 'aal1')",
      [sid, userId],
    ),
  );
  return sid;
}

/** A connection inside an open transaction as client `userId`; returns it and its backend PID. */
async function openClientTx(userId: string): Promise<{ c: Client; pid: number }> {
  const sid = await dbSession(userId);
  const c = new Client({ connectionString: DB_URL });
  await c.connect();
  const pid = (await c.query("select pg_backend_pid() as pid")).rows[0].pid as number;
  await c.query("begin");
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: "authenticated", aal: "aal1", session_id: sid, amr: [] }),
  ]);
  await c.query("set local role authenticated");
  return { c, pid };
}
async function finish(c: Client) {
  await c.query("commit");
  await c.end();
}
type Approval = { ok: boolean; approval_id: string; existing: boolean };
const approve = async (c: Client, releaseId: string) =>
  (await c.query("select public.approve_preview($1) as r", [releaseId])).rows[0].r as Approval;

/** Waits until backend `pid` is waiting on a heavyweight lock (the release advisory lock). */
async function waitingOnLock(pid: number): Promise<boolean> {
  for (let i = 0; i < 40; i++) {
    const waiting = await withDb(
      async (db) =>
        (
          await db.query(
            "select wait_event_type = 'Lock' as w from pg_stat_activity where pid = $1",
            [pid],
          )
        ).rows[0]?.w === true,
    );
    if (waiting) return true;
    await sleep(25);
  }
  return false;
}

type Evidence = {
  events: { dedupe_key: string; approval_id: string }[];
  interfaceApproval: string | null;
  approvedAt: Record<string, string>;
};
async function evidence(projectId: string, releaseId: string): Promise<Evidence> {
  return withDb(async (db) => {
    const events = await db.query(
      `select dedupe_key, payload ->> 'approval_id' as approval_id from public.domain_events
        where event_type = 'release.approved' and subject_id = $1 order by id`,
      [releaseId],
    );
    const ful = await db.query(
      `select (s).current_release_id as release_id, (s).current_release_approval_id as approval_id
         from (select private.project_fulfillment_status($1::uuid) as s) f`,
      [projectId],
    );
    expect(ful.rows[0].release_id).toBe(releaseId);
    const at = await db.query(
      "select id, approved_at::text as at from public.preview_approvals where release_id = $1",
      [releaseId],
    );
    return {
      events: events.rows,
      interfaceApproval: ful.rows[0].approval_id,
      approvedAt: Object.fromEntries(at.rows.map((r) => [r.id, r.at])),
    };
  });
}

/** WP-H's real consumer, in its own committed transaction as the job context. */
async function consumeCanonical(releaseId: string): Promise<string> {
  return withDb(async (db) => {
    await db.query("begin");
    const { rows } = await db.query(
      `select private.consume_release_approved(id) as o from public.domain_events
        where dedupe_key = 'release.approved:' || $1::text`,
      [releaseId],
    );
    await db.query("commit");
    return rows[0].o as string;
  });
}

async function effects(projectId: string) {
  return withDb(async (db) => {
    const { rows } = await db.query(
      `select (select count(*)::int from public.final_balance_invoices where project_id = $1) as obligations,
              (select count(*)::int from public.outbound_stripe_requests where project_id = $1
                 and purpose = 'final_balance_invoice_create') as creates,
              (select count(*)::int from public.domain_events where project_id = $1
                 and event_type = 'payment.balance_due') as balance_due,
              (select count(*)::int from public.audit_events where project_id = $1
                 and action = 'balance.collection_authorized') as collection_authorized,
              (select approval_id from public.final_balance_invoices where project_id = $1) as approval_id`,
      [projectId],
    );
    return rows[0] as {
      obligations: number;
      creates: number;
      balance_due: number;
      collection_authorized: number;
      approval_id: string;
    };
  });
}

/** The per-repetition assertions shared by both orders. `first` took the release lock first. */
async function expectOneInitiation(
  projectId: string,
  releaseId: string,
  first: Approval,
  second: Approval,
) {
  expect(first.ok && second.ok).toBe(true);
  expect(first.existing || second.existing).toBe(false);
  const ev = await evidence(projectId, releaseId);
  expect(ev.events).toEqual([
    { dedupe_key: `release.approved:${releaseId}`, approval_id: first.approval_id },
  ]);
  expect(ev.interfaceApproval).toBe(first.approval_id);
  expect(await consumeCanonical(releaseId)).toBe("created");
  expect(await effects(projectId)).toEqual({
    obligations: 1,
    creates: 1,
    balance_due: 1,
    collection_authorized: 1,
    approval_id: first.approval_id,
  });
  return ev;
}

/** B begins first; `delayMs` later A approves and commits; then B approves and commits. */
async function invertedRace(label: string, delayMs: number) {
  const { projectId, releaseId } = await paidRelease(label);
  const b = await openClientTx(CLIENT_B_ID);
  await b.c.query("select now()");
  await sleep(delayMs);
  const a = await openClientTx(CLIENT_A_ID);
  const first = await approve(a.c, releaseId);
  await finish(a.c);
  const second = await approve(b.c, releaseId);
  await finish(b.c);
  const ev = await expectOneInitiation(projectId, releaseId, first, second);
  // The inversion happened: the second-locked approval has the earlier approved_at.
  expect(ev.approvedAt[second.approval_id]! < ev.approvedAt[first.approval_id]!).toBe(true);
}

/** A approves and holds the lock; B is seen waiting; A commits; B completes. */
async function naturalRace(label: string) {
  const { projectId, releaseId } = await paidRelease(label);
  const a = await openClientTx(CLIENT_A_ID);
  const first = await approve(a.c, releaseId);
  const b = await openClientTx(CLIENT_B_ID);
  const pending = approve(b.c, releaseId);
  expect(await waitingOnLock(b.pid)).toBe(true);
  await finish(a.c);
  const second = await pending;
  await finish(b.c);
  await expectOneInitiation(projectId, releaseId, first, second);
}

async function settleRequests() {
  if (projects.length === 0) return;
  await withDb(async (db) => {
    await db.query("begin");
    await db.query("select set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)");
    await db.query("set local role service_role");
    const { rows } = await db.query(
      `select id from public.outbound_stripe_requests
        where project_id = any($1::uuid[]) and purpose = 'final_balance_invoice_create' and status = 'pending'`,
      [projects],
    );
    for (const { id } of rows as { id: string }[]) {
      // AUTH-009 (setup): claim, confirm with the one-time token, then record with it. The
      // token stays in memory and is never logged or asserted.
      const claim = await db.query(
        "select public.outbound_request_for_execution($1) ->> 'claim_token' as token",
        [id],
      );
      const token = (claim.rows[0] as { token: string | null }).token;
      await db.query("select public.confirm_outbound_dispatch($1, $2)", [id, token]);
      await db.query(
        "select public.record_outbound_result($1, $2, 'succeeded', $3, false, 200, null, '{}')",
        [id, token, `in_OI113${id.slice(0, 8)}`],
      );
    }
    await db.query("commit");
  });
}

beforeAll(async () => {
  await withDb((db) => db.query("delete from private.rate_limits"));
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
  clientA = await signInWithCode("client.a@example.test");
  owner = await signInWithCode("owner@example.test");
  await upgradeToAal2(owner, new Map());
});

afterAll(async () => {
  await settleRequests();
  await withDb((db) => db.query("delete from private.rate_limits"));
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
});

describe("OI-113: two clients approve one release concurrently (AUTH-013 acceptance 2 and 3)", () => {
  it(`inverted lock order (PR #35 B-1), ${REPETITIONS} repetitions: one canonical approval, one initiation`, async () => {
    for (let i = 0; i < REPETITIONS; i++) await invertedRace(`OI-113 inverted ${i}`, 50);
  }, 600_000);

  it(`natural lock order, ${REPETITIONS} repetitions: one canonical approval, one initiation`, async () => {
    for (let i = 0; i < REPETITIONS; i++) await naturalRace(`OI-113 natural ${i}`);
  }, 600_000);

  it("WP-C's original reproduction (B begins, A approves 200 ms later, then B) returns created", async () => {
    await invertedRace("OI-113 reproduction", 200);
  });
});
