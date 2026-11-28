import { randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/**
 * AUTH-022 (PWP-2; 04 §4A v0.11.0, OD-3): real-connection concurrency for v2 acceptance, against the
 * LOCAL stack with parallel database connections and the real functions (none is replaced).
 *
 *   T-CON-07 (the acceptance side): acceptance against bundle withdrawal, in both commit orders. The
 *            first committed outcome wins: a withdrawal committed first prevents the acceptance; an
 *            acceptance committed first stays valid while the withdrawal waits and then succeeds.
 *   Requirement A: acceptance against a replacement issuance, and against the sealing of a newer
 *            bundle, in both orders: each waits on the documented lock and completes, with no lock
 *            cycle. A deadlock (40P01), a lock timeout or any unexpected refusal fails the test.
 *
 * Every wait is observed in pg_locks (an ungranted lock). Each repetition gets a fresh fixture
 * bundle built by the seed constructors and its own project, because withdrawal is irreversible.
 * The suite ends by sealing a clean, newest fixture bundle, so later suites resolve an eligible one.
 * Synthetic and fixture data only; local and CI only.
 */

const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
// `signature` is used by no other integration or e2e test except the AUTH-021 race suite, which
// runs earlier; this suite leaves a newest, eligible fixture bundle behind.
const PKG = "signature";
const REPETITIONS = 5;
const FACTOR = "it-pwp2";
const marker = randomUUID().slice(0, 8);

let admin: Client;
let a: Client;
let b: Client;
const sessions: Record<string, string> = {};
let counter = 0;

async function q<T = Record<string, unknown>>(c: Client, sql: string, params: unknown[] = []) {
  return (await c.query(sql, params)).rows[0] as T;
}
async function as(c: Client, uid: string, aal: "aal1" | "aal2", fresh = false): Promise<void> {
  const claims = {
    sub: uid,
    role: "authenticated",
    aal,
    session_id: sessions[uid],
    amr: fresh ? [{ method: "totp", timestamp: Math.floor(Date.now() / 1000) }] : [],
  };
  await c.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)]);
  await c.query("set local role authenticated");
}
async function pidOf(c: Client): Promise<number> {
  return Number((await c.query("select pg_backend_pid() p")).rows[0].p);
}
async function waiting(pid: number): Promise<boolean> {
  for (let i = 0; i < 100; i += 1) {
    const r = await admin.query(
      "select exists (select 1 from pg_locks where pid = $1 and not granted) w",
      [pid],
    );
    if (r.rows[0].w) return true;
    await new Promise((res) => setTimeout(res, 50));
  }
  return false;
}
/** A newer fixture bundle for PKG, through the seed constructors only (the OD-9 labels apply). */
async function freshBundle(c: Client = admin): Promise<string> {
  counter += 1;
  const tag = `IT pwp2 ${marker} ${counter}`;
  await c.query(
    "select private.construct_contract_instrument('shared_terms', null, $1, $2, array['FX-S1'], true)",
    [
      `TEST FIXTURE shared terms (${tag})`,
      `TEST FIXTURE — NOT A CONTRACT INSTRUMENT (shared terms, ${tag})`,
    ],
  );
  const r = await q<{ v: { bundle_id: string } }>(
    c,
    `select private.construct_contract_bundle($1, $2,
       (select id from public.agreement_versions where version_label = 'test-fixture-1'),
       (select id from private.contract_instrument_versions where kind = 'package_specification'
          and package_key = $1 and is_test_fixture and instrument_version = 1),
       (select id from private.contract_instrument_versions where kind = 'maintenance_specification'
          and is_test_fixture and instrument_version = 1),
       (select id from private.contract_instrument_versions where kind = 'shared_terms'
          order by instrument_version desc limit 1),
       1, '["FX-P1", "FX-P2", "FX-P3"]'::jsonb, true) v`,
    [PKG, `TEST FIXTURE — NOT A CONTRACT BUNDLE (${tag})`],
  );
  return r.v.bundle_id;
}
/** A fresh project of client A, and an Admin-issued v2 order summary on it. */
async function presentedSummary(): Promise<{
  projectId: string;
  summaryId: string;
  legal: string;
}> {
  const legal = `PWP2 Race ${marker} ${counter} LLC`;
  // Setup rows carry an authenticated creator (the Owner), as the WP-C fixtures do.
  await admin.query("begin");
  await admin.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: OWNER_ID, role: "authenticated" }),
  ]);
  const biz = await q<{ id: string }>(
    admin,
    "insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id",
    [legal],
  );
  const prj = await q<{ id: string }>(
    admin,
    "insert into public.projects (client_business_id, name) values ($1, $2) returning id",
    [biz.id, `PWP2 race ${counter}`],
  );
  await admin.query(
    "insert into public.project_memberships (project_id, user_id) values ($1, $2)",
    [prj.id, CLIENT_A_ID],
  );
  await admin.query("commit");
  await a.query("begin");
  await as(a, ADMIN_ID, "aal2");
  const r = await q<{ v: { ok: boolean; order_summary_id: string } }>(
    a,
    "select public.issue_order_summary($1, $2) v",
    [prj.id, PKG],
  );
  await a.query("commit");
  expect(r.v.ok, JSON.stringify(r.v)).toBe(true);
  return { projectId: prj.id, summaryId: r.v.order_summary_id, legal };
}
const ACCEPT =
  "select public.accept_agreement($1, true, true, 'Client Signer', $2, 'Owner', true) v";
const WITHDRAW =
  "select public.withdraw_contract_bundle($1, 'IT race withdrawal', 'IT-PWP2-RACE') v";
const bundleOf = async (summaryId: string) =>
  (
    await q<{ id: string }>(
      admin,
      "select contract_bundle_id id from public.order_summaries where id = $1",
      [summaryId],
    )
  ).id;
const acceptances = async (summaryId: string) =>
  Number(
    (
      await q<{ n: number }>(
        admin,
        "select count(*)::int n from public.agreement_acceptances where order_summary_id = $1",
        [summaryId],
      )
    ).n,
  );

beforeAll(async () => {
  admin = new Client({ connectionString: DB_URL });
  a = new Client({ connectionString: DB_URL });
  b = new Client({ connectionString: DB_URL });
  await Promise.all([admin.connect(), a.connect(), b.connect()]);
  for (const c of [a, b]) await c.query("set lock_timeout = '15s'; set statement_timeout = '20s'");
  expect((await q<{ e: string }>(admin, "select private.app_environment() e")).e).toBe(
    "development",
  );
  for (const [uid, aal] of [
    [OWNER_ID, "aal2"],
    [ADMIN_ID, "aal2"],
    [CLIENT_A_ID, "aal1"],
  ] as const) {
    sessions[uid] = randomUUID();
    await admin.query(
      "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), $3)",
      [sessions[uid], uid, aal],
    );
    if (aal === "aal2") {
      await admin.query(
        `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
         select gen_random_uuid(), $1, $2, 'totp', 'verified', now(), now()
         where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
        [uid, FACTOR],
      );
    }
  }
});

afterAll(async () => {
  for (const c of [a, b]) await c.query("rollback").catch(() => undefined);
  // Leave a newest, eligible fixture bundle for PKG behind.
  await freshBundle();
  // OI-130: remove the secret-less verified factors this file inserted, so a later OTP sign-in works.
  await admin.query("delete from auth.mfa_factors where friendly_name = $1", [FACTOR]);
  await Promise.all([admin.end(), a.end(), b.end()]);
});

describe("AUTH-022: v2 acceptance under real concurrency (T-CON-07, requirement A)", () => {
  it(`T-CON-07: withdrawal first; the acceptance waits, then is refused (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      await freshBundle();
      const s = await presentedSummary();
      await a.query("begin");
      await as(a, OWNER_ID, "aal2", true);
      const w = await q<{ v: { ok: boolean } }>(a, WITHDRAW, [await bundleOf(s.summaryId)]);
      expect(w.v.ok, JSON.stringify(w.v)).toBe(true);
      await b.query("begin");
      await as(b, CLIENT_A_ID, "aal1");
      const bPid = await pidOf(b);
      const pending = b.query(ACCEPT, [s.summaryId, s.legal]);
      expect(await waiting(bPid)).toBe(true);
      await a.query("commit");
      const r = (await pending).rows[0].v as Record<string, unknown>;
      await b.query("commit");
      expect(r.error, JSON.stringify(r)).toBe("bundle_withdrawn");
      expect(await acceptances(s.summaryId)).toBe(0);
    }
  }, 300_000);

  it(`T-CON-07: acceptance first; the withdrawal waits, then succeeds; the acceptance stays valid (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      await freshBundle();
      const s = await presentedSummary();
      await b.query("begin");
      await as(b, CLIENT_A_ID, "aal1");
      const r = await q<{ v: { ok: boolean; acceptance_id: string } }>(b, ACCEPT, [
        s.summaryId,
        s.legal,
      ]);
      expect(r.v.ok, JSON.stringify(r.v)).toBe(true);
      await a.query("begin");
      await as(a, OWNER_ID, "aal2", true);
      const aPid = await pidOf(a);
      const pending = a.query(WITHDRAW, [await bundleOf(s.summaryId)]);
      expect(await waiting(aPid)).toBe(true);
      await b.query("commit");
      const w = (await pending).rows[0].v as Record<string, unknown>;
      await a.query("commit");
      expect(w.ok, JSON.stringify(w)).toBe(true);
      expect(await acceptances(s.summaryId)).toBe(1);
      await b.query("begin");
      await as(b, CLIENT_A_ID, "aal1");
      const replay = await q<{ v: { acceptance_id: string; existing: boolean } }>(b, ACCEPT, [
        s.summaryId,
        s.legal,
      ]);
      await b.query("commit");
      expect(replay.v).toMatchObject({ acceptance_id: r.v.acceptance_id, existing: true });
    }
  }, 300_000);

  it(`requirement A: acceptance against a replacement issuance, both orders, no lock cycle (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      for (const issuanceFirst of [true, false]) {
        // The previous scenario's last withdrawal left the newest bundle withdrawn (R-05: no fallback).
        await freshBundle();
        const s = await presentedSummary();
        const issue =
          "select public.issue_order_summary($1, $2, '[]'::jsonb, null, 'IT replacement') v";
        if (issuanceFirst) {
          await a.query("begin");
          await as(a, ADMIN_ID, "aal2");
          const n = await q<{ v: { ok: boolean } }>(a, issue, [s.projectId, PKG]);
          expect(n.v.ok, JSON.stringify(n.v)).toBe(true);
          await b.query("begin");
          await as(b, CLIENT_A_ID, "aal1");
          const bPid = await pidOf(b);
          const pending = b.query(ACCEPT, [s.summaryId, s.legal]);
          expect(await waiting(bPid)).toBe(true);
          await a.query("commit");
          const r = (await pending).rows[0].v as Record<string, unknown>;
          await b.query("commit");
          expect(r.error, JSON.stringify(r)).toBe("order_summary_superseded");
          expect(await acceptances(s.summaryId)).toBe(0);
        } else {
          await b.query("begin");
          await as(b, CLIENT_A_ID, "aal1");
          const r = await q<{ v: { ok: boolean } }>(b, ACCEPT, [s.summaryId, s.legal]);
          expect(r.v.ok, JSON.stringify(r.v)).toBe(true);
          await a.query("begin");
          await as(a, ADMIN_ID, "aal2");
          const aPid = await pidOf(a);
          const pending = a.query(issue, [s.projectId, PKG]);
          expect(await waiting(aPid)).toBe(true);
          await b.query("commit");
          const n = (await pending).rows[0].v as Record<string, unknown>;
          await a.query("commit");
          expect(n.ok, JSON.stringify(n)).toBe(true);
          expect(await acceptances(s.summaryId)).toBe(1);
        }
      }
    }
  }, 300_000);

  it(`requirement A: acceptance against the sealing of a newer bundle, both orders; the presented summary stays acceptable (${REPETITIONS}x)`, async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      for (const sealFirst of [true, false]) {
        await freshBundle();
        const s = await presentedSummary();
        if (sealFirst) {
          await a.query("begin");
          await freshBundle(a);
          await b.query("begin");
          await as(b, CLIENT_A_ID, "aal1");
          const bPid = await pidOf(b);
          const pending = b.query(ACCEPT, [s.summaryId, s.legal]);
          expect(await waiting(bPid)).toBe(true);
          await a.query("commit");
          const r = (await pending).rows[0].v as Record<string, unknown>;
          await b.query("commit");
          expect(r.ok, JSON.stringify(r)).toBe(true);
        } else {
          await b.query("begin");
          await as(b, CLIENT_A_ID, "aal1");
          const r = await q<{ v: { ok: boolean } }>(b, ACCEPT, [s.summaryId, s.legal]);
          expect(r.v.ok, JSON.stringify(r.v)).toBe(true);
          await a.query("begin");
          const aPid = await pidOf(a);
          const pending = freshBundle(a);
          expect(await waiting(aPid)).toBe(true);
          await b.query("commit");
          await pending;
          await a.query("commit");
        }
        expect(await acceptances(s.summaryId)).toBe(1);
      }
    }
  }, 300_000);
});
