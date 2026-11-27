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
 * AUTH-015 (OI-114): the Owner's recovery of a failed live verification races a late live
 * verification of the same deployment, against the LOCAL stack with real parallel database
 * connections. WP-C's real reopen_failed_publication and record_live_verification; a project
 * paid through the real WP-B workflow, with WP-C's real intake and release_preview.
 *
 * The recovery locks the deployment row FOR UPDATE; the verification reads it FOR SHARE. A late
 * verification therefore either commits first (and the recovery then sees a passing
 * verification and is refused, D4) or waits for the recovery and is refused (deployment_closed).
 * It never counts after a recovery.
 *
 *   Recovery first:     the Owner's recovery holds the row; the verifier's call is seen waiting
 *                       on a Lock in pg_stat_activity; the recovery commits; the verification
 *                       returns deployment_closed and records nothing.
 *   Verification first: a passing verification holds the row; the recovery is seen waiting; the
 *                       verification commits; the recovery returns not_recoverable/live_verified
 *                       and closes nothing.
 *
 * SYNTHETIC setup: the authorization and succeeded deployment rows are inserted directly (the
 * gates are covered by pgTAP 220 and 240; this file tests only the lock). The first, failed
 * verification is recorded through the real record_live_verification. Each order runs 10 times
 * on a fresh project. A deadlock (40P01) or any other database error fails the test.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const REPETITIONS = 10;
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

let owner: SupabaseClient;
let clientA: SupabaseClient;

// Session-local helpers for one setup transaction: WP-C's real intake (client A saves and
// submits; the Admin accepts) and release_preview (the Admin).
const SETUP_HELPERS = `
create function pg_temp.act_as(p_uid uuid, p_aal text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'it-oi114', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', '[]'::jsonb)::text, true);
  set local role authenticated;
end; $$;
create function pg_temp.release_ready(p_project uuid, p_sha text) returns uuid language plpgsql as $$
declare v_draft uuid; v_sub uuid; v jsonb;
begin
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_draft := (public.save_intake_draft(p_project, jsonb_build_object('business_legal_name', 'OI-114 LLC',
    'business_display_name', 'OI-114', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
    'address', '1 Test Street', 'service_areas', 'Test City', 'services_offered', 'Testing',
    'domain_status', 'needs_domain')) ->> 'draft_id')::uuid;
  v_sub := (public.submit_intake(p_project, v_draft) ->> 'submission_id')::uuid;
  reset role;
  perform pg_temp.act_as('${ADMIN_ID}', 'aal2');
  if not coalesce((public.review_intake(v_sub, 'accepted', 'Accepted') ->> 'ok')::boolean, false) then
    raise exception 'fixture: intake for % was not accepted', p_project;
  end if;
  v := public.release_preview(p_project, p_sha, 'dpl_oi114_' || left(p_sha, 12), 'https://preview.example.test/oi114', '{}');
  reset role;
  if not coalesce((v ->> 'ok')::boolean, false) then
    raise exception 'fixture: release_preview failed: %', v;
  end if;
  return (v ->> 'release_id')::uuid;
end; $$;`;

const sha = () => (randomUUID() + randomUUID()).replace(/-/g, "").slice(0, 40);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Fixture = { projectId: string; deploymentId: string; authorizationId: string; commit: string };

/** A paid project's release 1, deployed (SYNTHETIC rows) and failing live verification (real). */
async function failedVerification(label: string): Promise<Fixture> {
  await withDb((db) => db.query("delete from private.rate_limits"));
  const { projectId } = await createPaidProject({
    label,
    owner,
    client: clientA,
    clientUserId: CLIENT_A_ID,
  });
  const commit = sha();
  return withDb(async (db) => {
    await db.query("begin");
    await db.query(SETUP_HELPERS);
    const releaseId = (
      await db.query("select pg_temp.release_ready($1, $2) as r", [projectId, commit])
    ).rows[0].r as string;
    await db.query("reset role");
    // SYNTHETIC: the authorization and the succeeded deployment of exactly that commit.
    const authorizationId = (
      await db.query(
        `insert into public.publication_authorizations (project_id, release_id, gate_result, authorized_by)
         values ($1, $2, '{"synthetic": true}', $3) returning id::text`,
        [projectId, releaseId, OWNER_ID],
      )
    ).rows[0].id as string;
    const deploymentId = (
      await db.query(
        `insert into public.publication_deployments (authorization_id, project_id, release_id, commit_sha,
           target_ref, start_gate_result, started_by, outcome, provider_deployment_id, production_url,
           recorded_by, recorded_at)
         values ($1, $2, $3, $4, 'oi114-site', '{"synthetic": true}', $5, 'succeeded', 'dpl_oi114',
           'https://oi114.example.test', $5, now()) returning id::text`,
        [authorizationId, projectId, releaseId, commit, ADMIN_ID],
      )
    ).rows[0].id as string;
    await db.query("commit");
    // The real verifier records a mismatched build: the publication is failed.
    const first = await verify(deploymentId, sha());
    expect(first).toMatchObject({ ok: true, verified: false });
    return { projectId, deploymentId, authorizationId, commit };
  });
}

/** A connection inside an open transaction as the Owner (aal2, TOTP one minute ago). */
async function openOwnerTx(): Promise<{ c: Client; pid: number }> {
  const sid = randomUUID();
  await withDb(async (db) => {
    await db.query(
      "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), 'aal2')",
      [sid, OWNER_ID],
    );
  });
  const c = new Client({ connectionString: DB_URL });
  await c.connect();
  const pid = (await c.query("select pg_backend_pid() as pid")).rows[0].pid as number;
  await c.query("begin");
  const now = Math.floor(Date.now() / 1000);
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({
      sub: OWNER_ID,
      role: "authenticated",
      aal: "aal2",
      session_id: sid,
      amr: [{ method: "totp", timestamp: now - 60 }],
    }),
  ]);
  await c.query("set local role authenticated");
  return { c, pid };
}
/** A connection inside an open transaction as the server verifier (service_role). */
async function openServerTx(): Promise<{ c: Client; pid: number }> {
  const c = new Client({ connectionString: DB_URL });
  await c.connect();
  const pid = (await c.query("select pg_backend_pid() as pid")).rows[0].pid as number;
  await c.query("begin");
  await c.query(`select set_config('request.jwt.claims', '{"role":"service_role"}', true)`);
  await c.query("set local role service_role");
  return { c, pid };
}
async function finish(c: Client) {
  await c.query("commit");
  await c.end();
}

type Result = { ok: boolean; error?: string; detail?: string; verified?: boolean };
const reopen = async (c: Client, deploymentId: string) =>
  (
    await c.query("select public.reopen_failed_publication($1, $2) as r", [
      deploymentId,
      "Live verification failed; redeploying",
    ])
  ).rows[0].r as Result;
const verifyOn = async (c: Client, deploymentId: string, build: string) =>
  (
    await c.query(
      "select public.record_live_verification($1, $2, $3, true, true, true, true) as r",
      [deploymentId, ADMIN_ID, build],
    )
  ).rows[0].r as Result;
async function verify(deploymentId: string, build: string): Promise<Result> {
  const { c } = await openServerTx();
  const r = await verifyOn(c, deploymentId, build);
  await finish(c);
  return r;
}

/** Waits until backend `pid` is waiting on a heavyweight lock (the deployment row). */
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
  verifications: { verified: boolean }[];
  invalidatedReason: string | null;
  opened: number;
  rejected: string[];
  live: number;
  state: string;
};
async function evidence(f: Fixture): Promise<Evidence> {
  return withDb(async (db) => {
    const v = await db.query(
      "select verified from public.deployment_verifications where deployment_id = $1 order by seq",
      [f.deploymentId],
    );
    const a = await db.query(
      "select invalidated_reason from public.publication_authorizations where id = $1",
      [f.authorizationId],
    );
    const audits = await db.query(
      `select action, summary ->> 'detail' as detail from public.audit_events
        where project_id = $1 and action like 'publication.recovery_%' order by id`,
      [f.projectId],
    );
    const live = await db.query(
      `select count(*)::int as n from public.notification_outbox
        where notification_type = 'publication.live' and idempotency_key like $1`,
      [`publication.live:${f.deploymentId}:%`],
    );
    const s = await db.query("select private.publication_state_of($1)::text as s", [f.projectId]);
    return {
      verifications: v.rows,
      invalidatedReason: a.rows[0].invalidated_reason,
      opened: audits.rows.filter((r) => r.action === "publication.recovery_opened").length,
      rejected: audits.rows
        .filter((r) => r.action === "publication.recovery_rejected")
        .map((r) => r.detail as string),
      live: live.rows[0].n,
      state: s.rows[0].s,
    };
  });
}

async function recoveryFirst(label: string) {
  const f = await failedVerification(label);
  const recovery = await openOwnerTx();
  expect(await reopen(recovery.c, f.deploymentId)).toMatchObject({ ok: true, existing: false });
  const late = await openServerTx();
  const pending = verifyOn(late.c, f.deploymentId, f.commit);
  expect(await waitingOnLock(late.pid)).toBe(true);
  await finish(recovery.c);
  expect(await pending).toEqual({ ok: false, error: "deployment_closed" });
  await finish(late.c);
  expect(await evidence(f)).toEqual({
    verifications: [{ verified: false }],
    invalidatedReason: "failed_publication_recovery",
    opened: 1,
    rejected: [],
    live: 0,
    state: "failed",
  });
}

async function verificationFirst(label: string) {
  const f = await failedVerification(label);
  const late = await openServerTx();
  expect(await verifyOn(late.c, f.deploymentId, f.commit)).toMatchObject({
    ok: true,
    verified: true,
  });
  const recovery = await openOwnerTx();
  const pending = reopen(recovery.c, f.deploymentId);
  expect(await waitingOnLock(recovery.pid)).toBe(true);
  await finish(late.c);
  expect(await pending).toEqual({ ok: false, error: "not_recoverable", detail: "live_verified" });
  await finish(recovery.c);
  expect(await evidence(f)).toEqual({
    verifications: [{ verified: false }, { verified: true }],
    invalidatedReason: null,
    opened: 0,
    rejected: ["live_verified"],
    live: 1,
    state: "live_verified",
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
  await withDb((db) => db.query("delete from private.rate_limits"));
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
});

describe("OI-114: a recovery and a late live verification race (AUTH-015)", () => {
  it(`recovery first, ${REPETITIONS} repetitions: the late verification is refused and records nothing`, async () => {
    for (let i = 0; i < REPETITIONS; i++) await recoveryFirst(`OI-114 recovery-first ${i}`);
  }, 600_000);

  it(`verification first, ${REPETITIONS} repetitions: the recovery sees the passing verification and is refused`, async () => {
    for (let i = 0; i < REPETITIONS; i++) await verificationFirst(`OI-114 verification-first ${i}`);
  }, 600_000);
});
