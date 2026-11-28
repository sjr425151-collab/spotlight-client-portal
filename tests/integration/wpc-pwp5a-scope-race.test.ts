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
 * AUTH-023 (PWP-5a; OI-111, OD-14): the scope-confirmation gate under real concurrency, against
 * the LOCAL stack with real parallel database connections. Recording a confirmation version,
 * acknowledging one and releasing a preview all take WP-C's per-project release lock
 * (hashtextextended('release:' || project_id, 0)), and release_preview checks the gate only
 * after taking it, so the three serialize:
 *
 *   A. New version first: the signer's acknowledgment of the previous version waits, then is
 *      refused (confirmation_superseded); the new version stays unacknowledged.
 *   B. Acknowledgment first: the new version waits, then is recorded; it is unacknowledged.
 *   C. Acknowledgment first: the release waits, then succeeds.
 *   D. Release first (no acknowledgment yet): it is refused; the acknowledgment waits, then succeeds.
 *   E. New version first (the previous one acknowledged): the release waits, then is refused
 *      (scope_acknowledgment_required, OD-14).
 *   F. Release first (acknowledged): it succeeds; the new version waits, then is recorded.
 *
 * Requirement A (lock hierarchy): neither path holds a row lock before the release lock, and
 * neither the financial nor the contractual row-lock paths take the release lock, so no cycle can
 * form. The confirmation and acknowledgment inserts take FOR KEY SHARE on the project and
 * order-summary rows through their foreign keys, after the release lock. Both orders run against
 * the real paths that hold those rows exclusively:
 *
 *   G, H. Payment-method recovery (the project row FOR UPDATE, 04 §4A) against a new version.
 *   I, J. Payment-method recovery against the acknowledgment.
 *   K, L. An acceptance replay (the order-summary row FOR UPDATE) against the acknowledgment and a
 *         new version.
 *
 * Every waiter is seen on a heavyweight Lock in pg_stat_activity before the holder commits. Each
 * case runs REPETITIONS times on a fresh project paid through the real WP-B workflow, with WP-C's
 * real intake. A deadlock (40P01), a lock timeout or any unexpected refusal fails the test.
 */

const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const REPETITIONS = 5;
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

let owner: SupabaseClient;
let clientA: SupabaseClient;

// Session-local helpers for one setup transaction: WP-C's real intake (client A saves and
// submits; the Admin accepts).
const SETUP_HELPERS = `
create function pg_temp.act_as(p_uid uuid, p_aal text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'it-pwp5a', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', '[]'::jsonb)::text, true);
  set local role authenticated;
end; $$;
create function pg_temp.intake_accepted(p_project uuid) returns void language plpgsql as $$
declare v_draft uuid; v_sub uuid;
begin
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_draft := (public.save_intake_draft(p_project, jsonb_build_object('business_legal_name', 'PWP-5a LLC',
    'business_display_name', 'PWP-5a', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
    'address', '1 Test Street', 'service_areas', 'Test City', 'services_offered', 'Testing',
    'domain_status', 'needs_domain')) ->> 'draft_id')::uuid;
  v_sub := (public.submit_intake(p_project, v_draft) ->> 'submission_id')::uuid;
  reset role;
  perform pg_temp.act_as('${ADMIN_ID}', 'aal2');
  if not coalesce((public.review_intake(v_sub, 'accepted', 'Accepted') ->> 'ok')::boolean, false) then
    raise exception 'fixture: intake for % was not accepted', p_project;
  end if;
  reset role;
end; $$;`;

const sha = () => (randomUUID() + randomUUID()).replace(/-/g, "").slice(0, 40);
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Result = {
  ok: boolean;
  error?: string;
  confirmation_id?: string;
  content_sha256?: string;
  release_id?: string;
};

/** A connection inside an open transaction as `userId` (staff at aal2, a client at aal1). */
async function openTx(userId: string, aal: "aal1" | "aal2"): Promise<{ c: Client; pid: number }> {
  const sid = randomUUID();
  await withDb((db) =>
    db.query(
      "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), $3::auth.aal_level)",
      [sid, userId, aal],
    ),
  );
  const c = new Client({ connectionString: DB_URL });
  await c.connect();
  const pid = (await c.query("select pg_backend_pid() as pid")).rows[0].pid as number;
  await c.query("begin");
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: "authenticated", aal, session_id: sid, amr: [] }),
  ]);
  await c.query("set local role authenticated");
  return { c, pid };
}
async function finish(c: Client) {
  await c.query("commit");
  await c.end();
}

const record = async (c: Client, projectId: string, requirements: string) =>
  (
    await c.query("select public.record_scope_confirmation($1, $2, $3, '{}') as r", [
      projectId,
      requirements,
      ["Synthetic selection"],
    ])
  ).rows[0].r as Result;
const acknowledge = async (c: Client, confirmationId: string, contentSha: string) =>
  (
    await c.query("select public.acknowledge_scope_confirmation($1, $2, true, true) as r", [
      confirmationId,
      contentSha,
    ])
  ).rows[0].r as Result;
const release = async (c: Client, projectId: string) =>
  (
    await c.query(
      "select public.release_preview($1, $2, 'dpl_pwp5a', 'https://preview.example.test/pwp5a', '{}') as r",
      [projectId, sha()],
    )
  ).rows[0].r as Result;

const recover = async (c: Client, projectId: string) =>
  (await c.query("select public.begin_payment_method_recovery($1) as r", [projectId])).rows[0]
    .r as Result;
const acceptAgain = async (c: Client, orderSummaryId: string) =>
  (
    await c.query(
      "select public.accept_agreement($1, true, true, 'Alex Client', 'PWP-5a LLC', 'Owner', true) as r",
      [orderSummaryId],
    )
  ).rows[0].r as Result & { acceptance_id?: string; existing?: boolean };
const effectiveSummary = async (projectId: string) =>
  withDb(
    async (db) =>
      (
        await db.query("select (private.scope_effective_order_summary($1)).id::text as id", [
          projectId,
        ])
      ).rows[0].id as string,
  );

/** Each call in its own committed transaction. */
async function once<T>(
  userId: string,
  aal: "aal1" | "aal2",
  fn: (c: Client) => Promise<T>,
): Promise<T> {
  const { c } = await openTx(userId, aal);
  const r = await fn(c);
  await finish(c);
  return r;
}

/** Waits until backend `pid` is waiting on a heavyweight lock (the release advisory lock). */
async function waitingOnLock(pid: number): Promise<boolean> {
  for (let i = 0; i < 80; i++) {
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

type Evidence = { versions: number; acks: number; releases: number; state: string };
async function evidence(projectId: string): Promise<Evidence> {
  return withDb(async (db) => {
    const { rows } = await db.query(
      `select (select count(*)::int from public.scope_confirmations where project_id = $1) as versions,
              (select count(*)::int from public.scope_confirmation_acknowledgments where project_id = $1) as acks,
              (select count(*)::int from public.preview_releases where project_id = $1) as releases,
              private.scope_confirmation_state($1) as state`,
      [projectId],
    );
    return rows[0] as Evidence;
  });
}

/** A paid project (real WP-B flow) with accepted intake and confirmation version 1, unacknowledged. */
async function readyProject(label: string, acknowledged: boolean) {
  await withDb((db) => db.query("delete from private.rate_limits"));
  const { projectId } = await createPaidProject({
    label,
    owner,
    client: clientA,
    clientUserId: CLIENT_A_ID,
  });
  await withDb(async (db) => {
    await db.query("begin");
    await db.query(SETUP_HELPERS);
    await db.query("select pg_temp.intake_accepted($1)", [projectId]);
    await db.query("commit");
  });
  const v1 = await once(ADMIN_ID, "aal2", (c) => record(c, projectId, "Version 1 requirements"));
  expect(v1).toMatchObject({ ok: true });
  if (acknowledged) {
    expect(
      await once(CLIENT_A_ID, "aal1", (c) =>
        acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
      ),
    ).toMatchObject({ ok: true });
  }
  return { projectId, v1 };
}

/** The holder runs first and keeps its transaction open; the waiter must be seen on the lock. */
async function race<H, W>(
  holder: { user: string; aal: "aal1" | "aal2"; run: (c: Client) => Promise<H> },
  waiter: { user: string; aal: "aal1" | "aal2"; run: (c: Client) => Promise<W> },
): Promise<{ held: H; waited: W }> {
  const h = await openTx(holder.user, holder.aal);
  const held = await holder.run(h.c);
  const w = await openTx(waiter.user, waiter.aal);
  const pending = waiter.run(w.c);
  expect(await waitingOnLock(w.pid)).toBe(true);
  await finish(h.c);
  const waited = await pending;
  await finish(w.c);
  return { held, waited };
}

beforeAll(async () => {
  await withDb((db) => db.query("delete from private.rate_limits"));
  clientA = await signInWithCode("client.a@example.test");
  owner = await signInWithCode("owner@example.test");
  await upgradeToAal2(owner, new Map());
});

afterAll(async () => {
  await withDb((db) => db.query("delete from private.rate_limits"));
  await withDb((db) =>
    db.query("delete from auth.mfa_factors where user_id = '00000000-0000-4000-8000-000000000001'"),
  );
});

describe("AUTH-023: the scope-confirmation gate under real concurrency (T-LC-19, OD-14)", () => {
  it(`A. new version first: a late acknowledgment of the previous version is refused (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      const { projectId, v1 } = await readyProject(`PWP5a A ${i}`, false);
      const { held, waited } = await race(
        { user: ADMIN_ID, aal: "aal2", run: (c) => record(c, projectId, "Version 2 requirements") },
        {
          user: CLIENT_A_ID,
          aal: "aal1",
          run: (c) => acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
        },
      );
      expect(held).toMatchObject({ ok: true });
      expect(waited).toEqual({ ok: false, error: "confirmation_superseded" });
      expect(await evidence(projectId)).toEqual({
        versions: 2,
        acks: 0,
        releases: 0,
        state: "unacknowledged",
      });
    }
  }, 600_000);

  it(`B. acknowledgment first: the new version waits and needs its own acknowledgment (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      const { projectId, v1 } = await readyProject(`PWP5a B ${i}`, false);
      const { held, waited } = await race(
        {
          user: CLIENT_A_ID,
          aal: "aal1",
          run: (c) => acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
        },
        { user: ADMIN_ID, aal: "aal2", run: (c) => record(c, projectId, "Version 2 requirements") },
      );
      expect(held).toMatchObject({ ok: true });
      expect(waited).toMatchObject({ ok: true });
      expect(await evidence(projectId)).toEqual({
        versions: 2,
        acks: 1,
        releases: 0,
        state: "unacknowledged",
      });
    }
  }, 600_000);

  it(`C. acknowledgment first: the release waits, then succeeds (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      const { projectId, v1 } = await readyProject(`PWP5a C ${i}`, false);
      const { held, waited } = await race(
        {
          user: CLIENT_A_ID,
          aal: "aal1",
          run: (c) => acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
        },
        { user: ADMIN_ID, aal: "aal2", run: (c) => release(c, projectId) },
      );
      expect(held).toMatchObject({ ok: true });
      expect(waited).toMatchObject({ ok: true });
      expect(await evidence(projectId)).toEqual({
        versions: 1,
        acks: 1,
        releases: 1,
        state: "acknowledged",
      });
    }
  }, 600_000);

  it(`D. release first: refused without an acknowledgment; the acknowledgment waits, then succeeds (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      const { projectId, v1 } = await readyProject(`PWP5a D ${i}`, false);
      const { held, waited } = await race(
        { user: ADMIN_ID, aal: "aal2", run: (c) => release(c, projectId) },
        {
          user: CLIENT_A_ID,
          aal: "aal1",
          run: (c) => acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
        },
      );
      expect(held).toEqual({ ok: false, error: "scope_acknowledgment_required" });
      expect(waited).toMatchObject({ ok: true });
      expect(await evidence(projectId)).toEqual({
        versions: 1,
        acks: 1,
        releases: 0,
        state: "acknowledged",
      });
    }
  }, 600_000);

  it(`E. new version first: the release waits, then is refused until it is acknowledged (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      const { projectId } = await readyProject(`PWP5a E ${i}`, true);
      const { held, waited } = await race(
        { user: ADMIN_ID, aal: "aal2", run: (c) => record(c, projectId, "Version 2 requirements") },
        { user: ADMIN_ID, aal: "aal2", run: (c) => release(c, projectId) },
      );
      expect(held).toMatchObject({ ok: true });
      expect(waited).toEqual({ ok: false, error: "scope_acknowledgment_required" });
      expect(await evidence(projectId)).toEqual({
        versions: 2,
        acks: 1,
        releases: 0,
        state: "unacknowledged",
      });
    }
  }, 600_000);

  it(`F. release first: it succeeds; the new version waits, then is recorded (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      const { projectId } = await readyProject(`PWP5a F ${i}`, true);
      const { held, waited } = await race(
        { user: ADMIN_ID, aal: "aal2", run: (c) => release(c, projectId) },
        { user: ADMIN_ID, aal: "aal2", run: (c) => record(c, projectId, "Version 2 requirements") },
      );
      expect(held).toMatchObject({ ok: true });
      expect(waited).toMatchObject({ ok: true });
      expect(await evidence(projectId)).toEqual({
        versions: 2,
        acks: 1,
        releases: 1,
        state: "unacknowledged",
      });
    }
  }, 600_000);

  it(`G, H. payment-method recovery (project row FOR UPDATE) against a new version, both orders (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const recoveryFirst of [true, false]) {
        const { projectId } = await readyProject(`PWP5a GH ${i} ${recoveryFirst}`, true);
        const alone = await withDb(
          async (db) =>
            (
              await db.query(
                "select count(*)::int as n from public.recovery_sessions where project_id = $1",
                [projectId],
              )
            ).rows[0].n as number,
        );
        const recovery = {
          user: CLIENT_A_ID,
          aal: "aal1" as const,
          run: (c: Client) => recover(c, projectId),
        };
        const version = {
          user: ADMIN_ID,
          aal: "aal2" as const,
          run: (c: Client) => record(c, projectId, "Version 2 requirements"),
        };
        const { held, waited } = recoveryFirst
          ? await race(recovery, version)
          : await race(version, recovery);
        const [r, v] = recoveryFirst ? [held, waited] : [waited, held];
        expect(r).toEqual({ ok: false, error: "authorization_active" });
        expect(v).toMatchObject({ ok: true });
        expect(await evidence(projectId)).toEqual({
          versions: 2,
          acks: 1,
          releases: 0,
          state: "unacknowledged",
        });
        expect(
          await withDb(
            async (db) =>
              (
                await db.query(
                  "select count(*)::int as n from public.recovery_sessions where project_id = $1",
                  [projectId],
                )
              ).rows[0].n as number,
          ),
        ).toBe(alone);
      }
    }
  }, 600_000);

  it(`I, J. payment-method recovery against the acknowledgment, both orders (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const recoveryFirst of [true, false]) {
        const { projectId, v1 } = await readyProject(`PWP5a IJ ${i} ${recoveryFirst}`, false);
        const recovery = {
          user: CLIENT_A_ID,
          aal: "aal1" as const,
          run: (c: Client) => recover(c, projectId),
        };
        const ack = {
          user: CLIENT_A_ID,
          aal: "aal1" as const,
          run: (c: Client) => acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
        };
        const { held, waited } = recoveryFirst
          ? await race(recovery, ack)
          : await race(ack, recovery);
        const [r, a] = recoveryFirst ? [held, waited] : [waited, held];
        expect(r).toEqual({ ok: false, error: "authorization_active" });
        expect(a).toMatchObject({ ok: true });
        expect(await evidence(projectId)).toEqual({
          versions: 1,
          acks: 1,
          releases: 0,
          state: "acknowledged",
        });
      }
    }
  }, 600_000);

  it(`K, L. an acceptance replay (order-summary row FOR UPDATE) against the acknowledgment and a new version (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const acceptFirst of [true, false]) {
        const { projectId, v1 } = await readyProject(`PWP5a KL ${i} ${acceptFirst}`, false);
        const os = await effectiveSummary(projectId);
        const accept = {
          user: CLIENT_A_ID,
          aal: "aal1" as const,
          run: (c: Client) => acceptAgain(c, os),
        };
        const ack = {
          user: CLIENT_A_ID,
          aal: "aal1" as const,
          run: (c: Client) => acknowledge(c, v1.confirmation_id!, v1.content_sha256!),
        };
        const version = {
          user: ADMIN_ID,
          aal: "aal2" as const,
          run: (c: Client) => record(c, projectId, "Version 2 requirements"),
        };
        for (const other of [ack, version]) {
          const { held, waited } = acceptFirst
            ? await race(accept, other)
            : await race(other, accept);
          const [p, o] = acceptFirst ? [held, waited] : [waited, held];
          expect(p).toMatchObject({ ok: true, existing: true });
          expect(o).toMatchObject({ ok: true });
        }
        expect(await evidence(projectId)).toEqual({
          versions: 2,
          acks: 1,
          releases: 0,
          state: "unacknowledged",
        });
        expect(await effectiveSummary(projectId)).toBe(os);
      }
    }
  }, 600_000);
});
