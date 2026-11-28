import { randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { withDb } from "../support/db";

/**
 * AUTH-024 (PWP-5b; OI-110, OI-45; requirement A): the revised inactivity schedule under real
 * concurrency, against the LOCAL stack with real parallel database connections.
 *
 * Lock order of record_inactivity_milestone: the release:<project> advisory lock, then the
 * release row FOR UPDATE. Approval takes the same advisory lock; a revision request takes FOR KEY
 * SHARE on the release row through its foreign key; withdrawal takes the release row FOR UPDATE
 * and never the advisory lock. place_approval_hold keeps its existing order (the advisory lock,
 * then reads). None of these paths takes a lock another holds while waiting for one this path
 * holds, so no cycle can form:
 *
 *   A, B. A milestone against a client approval, both orders.
 *   C, D. A milestone against a revision request, both orders.
 *   E, F. A milestone against a withdrawal, both orders.
 *   G, H. The day-30 administrative suspension against a client approval, both orders.
 *
 * Every waiter is seen on a heavyweight Lock before the holder commits. Each case runs
 * REPETITIONS times on a fresh synthetic project whose release is 40 local days old (revised
 * schedule). A deadlock (40P01), a lock or statement timeout, or any unexpected refusal fails the
 * test. Each connection sets lock and statement timeouts (WP-I N-1) and every race rolls back and
 * closes both connections in a finally block (WP-I N-2). The Admin's MFA factor this file inserts
 * is removed afterwards and the synthetic projects are archived (OI-130).
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const FACTOR_NAME = "it-pwp5b";
const REPETITIONS = 5;
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

const created: string[] = [];
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

type Result = { ok: boolean; error?: string };

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
  await c.query("set lock_timeout = '15s'; set statement_timeout = '20s'");
  const pid = (await c.query("select pg_backend_pid() as pid")).rows[0].pid as number;
  await c.query("begin");
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: "authenticated", aal, session_id: sid, amr: [] }),
  ]);
  await c.query("set local role authenticated");
  return { c, pid };
}

const milestone = async (c: Client, releaseId: string, kind: string) =>
  (
    await c.query(
      `select public.record_inactivity_milestone($1, $2, 'email',
         ((select released_at from public.preview_releases where id = $1) at time zone 'America/Detroit')::date
           + private_day.d, 'Recorded') as r
         from (select case $2 when 'reminder' then 7 when 'admin_notified' then 7 else 3 end as d) private_day`,
      [releaseId, kind],
    )
  ).rows[0].r as Result;
const approve = async (c: Client, releaseId: string) =>
  (await c.query("select public.approve_preview($1) as r", [releaseId])).rows[0].r as Result;
const revise = async (c: Client, releaseId: string) =>
  (
    await c.query("select public.request_revisions($1, 'Please change the header') as r", [
      releaseId,
    ])
  ).rows[0].r as Result;
const withdraw = async (c: Client, releaseId: string) =>
  (
    await c.query("select public.withdraw_preview($1, 'Superseded by a new build') as r", [
      releaseId,
    ])
  ).rows[0].r as Result;
const suspend = async (c: Client, projectId: string) =>
  (
    await c.query(
      "select public.place_approval_hold($1, 'No response after the formal notice') as r",
      [projectId],
    )
  ).rows[0].r as Result;

/** Waits until backend `pid` is waiting on a heavyweight lock. */
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

/** The holder runs first and keeps its transaction open; the waiter must be seen on the lock. */
async function race<H, W>(
  holder: { user: string; aal: "aal1" | "aal2"; run: (c: Client) => Promise<H> },
  waiter: { user: string; aal: "aal1" | "aal2"; run: (c: Client) => Promise<W> },
): Promise<{ held: H; waited: W }> {
  const h = await openTx(holder.user, holder.aal);
  let w: { c: Client; pid: number } | undefined;
  let pending: Promise<W> | undefined;
  try {
    const held = await holder.run(h.c);
    w = await openTx(waiter.user, waiter.aal);
    pending = waiter.run(w.c);
    expect(await waitingOnLock(w.pid)).toBe(true);
    await h.c.query("commit");
    const waited = await pending;
    await w.c.query("commit");
    return { held, waited };
  } finally {
    await Promise.allSettled([h.c.query("rollback"), w?.c.query("rollback")]);
    if (pending) await Promise.allSettled([pending]);
    await Promise.allSettled([h.c.end(), w?.c.end()]);
  }
}

/** A synthetic project of client A's business with one release 40 local days old (revised schedule). */
async function readyProject(label: string, formalNotice: boolean) {
  return withDb(async (db) => {
    await db.query("begin");
    await db.query(
      `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, true)`,
      [OWNER_ID],
    );
    const projectId = (
      await db.query(
        `insert into public.projects (client_business_id, name, created_by)
         select client_business_id, $2, $3 from public.projects where id = $1 returning id::text`,
        [PROJECT_A, `PWP-5b race ${label}`, OWNER_ID],
      )
    ).rows[0].id as string;
    await db.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
      projectId,
      CLIENT_A_ID,
    ]);
    const releaseId = (
      await db.query(
        `insert into public.preview_releases (project_id, release_number, commit_sha, deployment_id, preview_url,
           released_by, released_at)
         values ($1, 1, $2, 'dpl_pwp5b_race', 'https://preview.example.test/pwp5b', $3, now() - interval '40 days')
         returning id::text`,
        [projectId, randomUUID().replace(/-/g, "").padEnd(40, "0"), ADMIN_ID],
      )
    ).rows[0].id as string;
    await db.query("commit");
    created.push(projectId);
    if (formalNotice) {
      const { c } = await openTx(ADMIN_ID, "aal2");
      try {
        const r = (
          await c.query(
            `select public.record_inactivity_milestone($1, 'formal_notice', 'email',
               ((select released_at from public.preview_releases where id = $1) at time zone 'America/Detroit')::date + 14,
               'Formal notice sent') as r`,
            [releaseId],
          )
        ).rows[0].r as Result;
        if (!r.ok) throw new Error(`setup: formal notice ${JSON.stringify(r)}`);
        await c.query("commit");
      } finally {
        await c.end();
      }
    }
    return { projectId, releaseId };
  });
}

async function evidence(projectId: string, releaseId: string) {
  return withDb(async (db) => {
    const { rows } = await db.query(
      `select (select count(*)::int from public.inactivity_milestones where release_id = $2) as milestones,
              (select count(*)::int from public.preview_approvals where release_id = $2) as approvals,
              (select count(*)::int from public.preview_revision_requests where release_id = $2) as revisions,
              (select count(*)::int from public.approval_holds where project_id = $1 and cleared_at is null) as holds,
              (select withdrawn_at is not null from public.preview_releases where id = $2) as withdrawn`,
      [projectId, releaseId],
    );
    return rows[0] as {
      milestones: number;
      approvals: number;
      revisions: number;
      holds: number;
      withdrawn: boolean;
    };
  });
}

beforeAll(async () => {
  await withDb((db) =>
    db.query(
      `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
       select gen_random_uuid(), $1, $2, 'totp', 'verified', now(), now()
       where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
      [ADMIN_ID, FACTOR_NAME],
    ),
  );
});

afterAll(async () => {
  await withDb(async (db) => {
    await db.query("delete from auth.mfa_factors where friendly_name = $1", [FACTOR_NAME]);
    await db.query("update public.projects set archived_at = now() where id = any($1::uuid[])", [
      created,
    ]);
  });
});

const admin = { user: ADMIN_ID, aal: "aal2" as const };
const client = { user: CLIENT_A_ID, aal: "aal1" as const };

describe("AUTH-024: the revised inactivity schedule under real concurrency (requirement A)", () => {
  it(`A, B. a milestone against a client approval, both orders (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const milestoneFirst of [true, false]) {
        const { projectId, releaseId } = await readyProject(`AB ${i} ${milestoneFirst}`, false);
        const m = { ...admin, run: (c: Client) => milestone(c, releaseId, "reminder") };
        const a = { ...client, run: (c: Client) => approve(c, releaseId) };
        const { held, waited } = milestoneFirst ? await race(m, a) : await race(a, m);
        const [mr, ar] = milestoneFirst ? [held, waited] : [waited, held];
        expect(ar).toMatchObject({ ok: true });
        if (milestoneFirst) expect(mr).toMatchObject({ ok: true });
        else expect(mr).toEqual({ ok: false, error: "schedule_stopped" });
        expect(await evidence(projectId, releaseId)).toEqual({
          milestones: milestoneFirst ? 1 : 0,
          approvals: 1,
          revisions: 0,
          holds: 0,
          withdrawn: false,
        });
      }
    }
  }, 600_000);

  it(`C, D. a milestone against a revision request, both orders (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const milestoneFirst of [true, false]) {
        const { projectId, releaseId } = await readyProject(`CD ${i} ${milestoneFirst}`, false);
        const m = { ...admin, run: (c: Client) => milestone(c, releaseId, "reminder") };
        const r = { ...client, run: (c: Client) => revise(c, releaseId) };
        const { held, waited } = milestoneFirst ? await race(m, r) : await race(r, m);
        const [mr, rr] = milestoneFirst ? [held, waited] : [waited, held];
        expect(rr).toMatchObject({ ok: true });
        if (milestoneFirst) expect(mr).toMatchObject({ ok: true });
        else expect(mr).toEqual({ ok: false, error: "schedule_stopped" });
        expect(await evidence(projectId, releaseId)).toEqual({
          milestones: milestoneFirst ? 1 : 0,
          approvals: 0,
          revisions: 1,
          holds: 0,
          withdrawn: false,
        });
      }
    }
  }, 600_000);

  it(`E, F. a milestone against a withdrawal, both orders (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const milestoneFirst of [true, false]) {
        const { projectId, releaseId } = await readyProject(`EF ${i} ${milestoneFirst}`, false);
        const m = { ...admin, run: (c: Client) => milestone(c, releaseId, "reminder") };
        const w = { ...admin, run: (c: Client) => withdraw(c, releaseId) };
        const { held, waited } = milestoneFirst ? await race(m, w) : await race(w, m);
        const [mr, wr] = milestoneFirst ? [held, waited] : [waited, held];
        expect(wr).toMatchObject({ ok: true });
        if (milestoneFirst) expect(mr).toMatchObject({ ok: true });
        else expect(mr).toEqual({ ok: false, error: "not_current_release" });
        expect(await evidence(projectId, releaseId)).toEqual({
          milestones: milestoneFirst ? 1 : 0,
          approvals: 0,
          revisions: 0,
          holds: 0,
          withdrawn: true,
        });
      }
    }
  }, 600_000);

  it(`G, H. the day-30 administrative suspension against a client approval, both orders (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i++) {
      for (const holdFirst of [true, false]) {
        const { projectId, releaseId } = await readyProject(`GH ${i} ${holdFirst}`, true);
        const s = { ...admin, run: (c: Client) => suspend(c, projectId) };
        const a = { ...client, run: (c: Client) => approve(c, releaseId) };
        const { held, waited } = holdFirst ? await race(s, a) : await race(a, s);
        const [sr, ar] = holdFirst ? [held, waited] : [waited, held];
        expect(ar).toMatchObject({ ok: true });
        if (holdFirst) expect(sr).toMatchObject({ ok: true });
        else expect(sr).toEqual({ ok: false, error: "release_approved" });
        expect(await evidence(projectId, releaseId)).toEqual({
          milestones: 1,
          approvals: 1,
          revisions: 0,
          holds: holdFirst ? 1 : 0,
          withdrawn: false,
        });
      }
    }
  }, 600_000);
});
