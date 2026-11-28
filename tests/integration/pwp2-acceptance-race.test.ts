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
 *   OI-132 (option (a)): issuance against AUTH-018 scope withdrawal and scope activation, in both
 *            orders: the per-package lock serializes them; a withdrawn or inactive newest version
 *            refuses issuance (scope_definition_missing), with no fallback.
 *
 * Every wait is observed in pg_locks (an ungranted lock). Each repetition gets a fresh synthetic
 * bundle (Owner functions only; see the helpers) and its own project, because withdrawal is
 * irreversible. The suite ends by sealing a clean, newest bundle over the current scope version, so
 * later suites resolve an eligible one. Synthetic data only; local and CI only.
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
// OI-132 (a): issuance needs an eligible bundle AND the AUTH-018 scope gate at the bundle's pinned
// version. This suite therefore builds synthetic, non-fixture content through the Owner functions
// only (AUTH-018 scope loader; AUTH-021 instruments, sealing, approval and activation; an agreement
// holding only a synthetic heading and the approved 04 §3.1 clause, as in pwp1-contract-race).
const syn: Record<string, string> = {};
let scopeV = 0;
/** One Owner call on `c` (inside its transaction when one is open), refusing any non-ok result. */
async function ownerOn(
  c: Client,
  sql: string,
  params: unknown[],
): Promise<Record<string, unknown>> {
  await as(c, OWNER_ID, "aal2", true);
  const v = (await c.query(sql, params)).rows[0].v as Record<string, unknown>;
  if (v.ok !== true) throw new Error(`setup: ${sql}: ${JSON.stringify(v)}`);
  return v;
}
async function ownerTx(sql: string, params: unknown[]): Promise<Record<string, unknown>> {
  await admin.query("begin");
  try {
    const v = await ownerOn(admin, sql, params);
    await admin.query("commit");
    return v;
  } catch (e) {
    await admin.query("rollback");
    throw e;
  }
}
const scopeItems = (v: number) => [
  `IT PWP2 SCOPE ${marker} V${v}-A`,
  `IT PWP2 SCOPE ${marker} V${v}-B`,
];
/** Approve and load the next synthetic scope version of PKG; optionally activate it. */
async function newScope(activate: boolean): Promise<number> {
  const v = Number(
    (
      await q<{ n: number }>(
        admin,
        `select coalesce(max(v), 0) + 1 n from (
           select max(scope_version) v from private.billing_package_scope where package_key = $1
           union all select max(scope_version) from private.billing_package_scope_versions where package_key = $1) x`,
        [PKG],
      )
    ).n,
  );
  const items = scopeItems(v);
  const sha = (
    await q<{ s: string }>(
      admin,
      `select encode(extensions.digest(convert_to('spotlight.package_scope.v1|k' || octet_length($1::text) || ':'
         || $1 || '|v' || $2 || '|n' || cardinality($3::text[]) || (select string_agg('|p' || o || ':'
         || octet_length(t) || ':' || t, '' order by o) from unnest($3::text[]) with ordinality u (t, o)),
         'UTF8'), 'sha256'), 'hex') s`,
      [PKG, v, items],
    )
  ).s;
  await ownerTx("select public.record_package_scope_approval($1, $2, $3, $4, $5) v", [
    PKG,
    v,
    sha,
    `IT-PWP2-SCOPE-${marker}-${v}`,
    "e".repeat(64),
  ]);
  await ownerTx("select public.load_package_scope_version($1, $2, $3) v", [PKG, v, items]);
  if (activate) await ownerTx("select public.activate_package_scope_version($1, $2) v", [PKG, v]);
  return v;
}
async function synInstrument(kind: string, pkg: string | null): Promise<string> {
  const ver = Number(
    (
      await q<{ n: number }>(
        admin,
        `select coalesce(max(instrument_version), 0) + 1 n from private.contract_instrument_versions
          where kind = $1 and package_key is not distinct from $2`,
        [kind, pkg],
      )
    ).n,
  );
  const body = `IT PWP2 SYNTHETIC ${kind} ${marker}`;
  const sha = (
    await q<{ s: string }>(
      admin,
      "select private.contract_instrument_sha256($1, $2, $3, 'IT SYNTHETIC', $4, array['S1', 'S2']) s",
      [kind, pkg, ver, body],
    )
  ).s;
  const r = await ownerTx(
    "select public.create_contract_instrument_version($1, $2, $3, 'IT SYNTHETIC', $4, array['S1', 'S2'], $5) v",
    [kind, pkg, ver, body, sha],
  );
  return r.instrument_id as string;
}
/** Seal, approve and activate a bundle for PKG pinning scope version `v` (default: the current one). */
async function freshBundle(c: Client = admin, v: number = scopeV): Promise<string> {
  counter += 1;
  const own = c === admin;
  if (own) await admin.query("begin");
  try {
    const sealed = await ownerOn(
      c,
      "select public.seal_contract_bundle($1, $2, $3, $4, $5, $6, $7, $8) v",
      [
        PKG,
        `IT PWP2 SYNTHETIC BUNDLE ${marker} ${counter}`,
        syn.agreement,
        syn.package,
        syn.maintenance,
        syn.shared,
        v,
        JSON.stringify(["S1", "S2"]),
      ],
    );
    await ownerOn(c, "select public.record_contract_bundle_approval($1, $2, $3, $4) v", [
      sealed.bundle_id,
      sealed.bundle_sha256,
      `IT-PWP2-LEGAL-${marker}-${counter}`,
      "e".repeat(64),
    ]);
    await ownerOn(c, "select public.activate_contract_bundle($1) v", [sealed.bundle_id]);
    if (own) await admin.query("commit");
    return sealed.bundle_id as string;
  } catch (e) {
    if (own) await admin.query("rollback");
    throw e;
  }
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
  const text = (
    await q<{ t: string }>(
      admin,
      `select 'IT PWP2 SYNTHETIC AGREEMENT ${marker}' || E'\\n\\n' || private.final_payment_clause() t`,
    )
  ).t;
  const ag = await ownerTx(
    "select public.create_agreement_version($1, $2, date '2026-11-01', $3) v",
    [`it-pwp2-${marker}`, text, "IT-PWP2-AGR"],
  );
  syn.agreement = ag.agreement_version_id as string;
  await ownerTx("select public.approve_agreement_version($1) v", [syn.agreement]);
  syn.package = await synInstrument("package_specification", PKG);
  syn.maintenance = await synInstrument("maintenance_specification", null);
  syn.shared = await synInstrument("shared_terms", null);
  scopeV = await newScope(true);
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

  it(`OI-132 requirement A: issuance against scope withdrawal, both orders (${REPETITIONS}x)`, async () => {
    const replace = "select public.issue_order_summary($1, $2, '[]'::jsonb, null, 'IT race') v";
    for (let i = 0; i < REPETITIONS; i += 1) {
      for (const withdrawalFirst of [true, false]) {
        await freshBundle();
        const s = await presentedSummary();
        if (withdrawalFirst) {
          await a.query("begin");
          await ownerOn(a, "select public.withdraw_package_scope_version($1, $2) v", [PKG, scopeV]);
          await b.query("begin");
          await as(b, ADMIN_ID, "aal2");
          const bPid = await pidOf(b);
          const pending = b.query(replace, [s.projectId, PKG]);
          expect(await waiting(bPid)).toBe(true);
          await a.query("commit");
          const r = (await pending).rows[0].v as Record<string, unknown>;
          await b.query("commit");
          expect(r.error, JSON.stringify(r)).toBe("scope_definition_missing");
        } else {
          await b.query("begin");
          await as(b, ADMIN_ID, "aal2");
          const r = (await b.query(replace, [s.projectId, PKG])).rows[0].v as Record<
            string,
            unknown
          >;
          expect(r.ok, JSON.stringify(r)).toBe(true);
          await a.query("begin");
          const aPid = await pidOf(a);
          const pending = ownerOn(a, "select public.withdraw_package_scope_version($1, $2) v", [
            PKG,
            scopeV,
          ]);
          expect(await waiting(aPid)).toBe(true);
          await b.query("commit");
          await pending;
          await a.query("commit");
          const kept = await q<{ n: number }>(
            admin,
            "select count(*)::int n from public.order_summaries where id = $1 and status = 'presented'",
            [r.order_summary_id],
          );
          expect(kept.n).toBe(1);
        }
        // The withdrawn version never resolves again (no fallback to an older version).
        await b.query("begin");
        await as(b, ADMIN_ID, "aal2");
        const after = (await b.query(replace, [s.projectId, PKG])).rows[0].v as Record<
          string,
          unknown
        >;
        await b.query("rollback");
        expect(after.error, JSON.stringify(after)).toBe("scope_definition_missing");
        scopeV = await newScope(true);
      }
    }
  }, 600_000);

  it(`OI-132 requirement A: issuance against scope activation, both orders (${REPETITIONS}x)`, async () => {
    const replace = "select public.issue_order_summary($1, $2, '[]'::jsonb, null, 'IT race') v";
    for (let i = 0; i < REPETITIONS; i += 1) {
      for (const activationFirst of [true, false]) {
        await freshBundle();
        const s = await presentedSummary();
        // A newer loaded but inactive version, already pinned by an eligible bundle: issuance is
        // suspended until the version is activated (04 §4A rule 7).
        const v = await newScope(false);
        await freshBundle(admin, v);
        if (activationFirst) {
          await a.query("begin");
          await ownerOn(a, "select public.activate_package_scope_version($1, $2) v", [PKG, v]);
          await b.query("begin");
          await as(b, ADMIN_ID, "aal2");
          const bPid = await pidOf(b);
          const pending = b.query(replace, [s.projectId, PKG]);
          expect(await waiting(bPid)).toBe(true);
          await a.query("commit");
          const r = (await pending).rows[0].v as Record<string, unknown>;
          await b.query("commit");
          expect(r.ok, JSON.stringify(r)).toBe(true);
          const pinnedV = await q<{ v: number }>(
            admin,
            "select scope_version v from public.order_summaries where id = $1",
            [r.order_summary_id],
          );
          expect(Number(pinnedV.v)).toBe(v);
        } else {
          await b.query("begin");
          await as(b, ADMIN_ID, "aal2");
          const r = (await b.query(replace, [s.projectId, PKG])).rows[0].v as Record<
            string,
            unknown
          >;
          expect(r.error, JSON.stringify(r)).toBe("scope_definition_missing");
          await a.query("begin");
          const aPid = await pidOf(a);
          const pending = ownerOn(a, "select public.activate_package_scope_version($1, $2) v", [
            PKG,
            v,
          ]);
          expect(await waiting(aPid)).toBe(true);
          await b.query("commit");
          await pending;
          await a.query("commit");
        }
        scopeV = v;
      }
    }
  }, 600_000);
});
