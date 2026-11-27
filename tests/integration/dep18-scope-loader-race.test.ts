import { createHash, randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/**
 * AUTH-018 (DEP-18 R1 interim scope loading and activation; 04 §4A): serialization of concurrent
 * loading, activation, withdrawal and Sales issuance, against the LOCAL stack with real parallel
 * database connections and the real functions (no function is replaced).
 *
 * Every governance function takes the per-package eligibility lock exclusively; the resolver
 * (called by issue_order_summary) takes it shared and holds it until commit, and is volatile, so:
 *   - a withdrawal or load committed while issuance waited is seen (issuance fails closed);
 *   - an issuance committed first stays valid, and the withdrawal waits for it;
 *   - concurrent identical activations or loads produce one record and one event;
 *   - an activation never succeeds after a withdrawal committed first.
 * Each ordering repeats; a deadlock (40P01) or any other database error fails the test.
 *
 * Items are synthetic, non-legal test strings (D11), local and CI only. The records are
 * append-only, so this suite uses the `prestige` package, which no other integration or e2e test
 * uses; run it on a freshly reset local database.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const PKG = "prestige";
const REPETITIONS = 5;
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");

let admin: Client;
let a: Client;
let b: Client;
let ownerSession: string;
let salesSession: string;
let projectId: string;
const marker = randomUUID().slice(0, 8);

function canonicalSha(key: string, version: number, items: string[]): string {
  const len = (s: string) => Buffer.byteLength(s, "utf8");
  const body = items.map((t, i) => `|p${i + 1}:${len(t)}:${t}`).join("");
  const text = `spotlight.package_scope.v1|k${len(key)}:${key}|v${version}|n${items.length}${body}`;
  return createHash("sha256").update(text, "utf8").digest("hex");
}

function claims(uid: string, sid: string): string {
  const now = Math.floor(Date.now() / 1000);
  return JSON.stringify({
    sub: uid,
    role: "authenticated",
    aal: "aal2",
    session_id: sid,
    amr: [{ method: "totp", timestamp: now }],
  });
}

async function as(c: Client, uid: string, sid: string): Promise<void> {
  await c.query("select set_config('request.jwt.claims', $1, true)", [claims(uid, sid)]);
  await c.query("set local role authenticated");
}

async function newSession(uid: string): Promise<string> {
  const sid = randomUUID();
  await admin.query(
    "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), 'aal2')",
    [sid, uid],
  );
  await admin.query(
    `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
     select gen_random_uuid(), $1, 'it-dep18', 'totp', 'verified', now(), now()
     where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
    [uid],
  );
  return sid;
}

async function ownerCall(
  c: Client,
  sql: string,
  params: unknown[],
): Promise<Record<string, unknown>> {
  await as(c, OWNER_ID, ownerSession);
  const r = await c.query(sql, params);
  return r.rows[0].v as Record<string, unknown>;
}

async function owner(sql: string, params: unknown[]): Promise<Record<string, unknown>> {
  await admin.query("begin");
  try {
    const v = await ownerCall(admin, sql, params);
    await admin.query("commit");
    return v;
  } catch (e) {
    await admin.query("rollback");
    throw e;
  }
}

async function nextVersion(): Promise<number> {
  const r = await admin.query(
    `select coalesce(max(v), 0) + 1 as n from (
       select max(scope_version) v from private.billing_package_scope where package_key = $1
       union all select max(scope_version) from private.billing_package_scope_versions where package_key = $1) x`,
    [PKG],
  );
  return Number(r.rows[0].n);
}

/** Approve and load the next version; optionally activate it. Returns the version. */
async function prepareVersion(activate: boolean): Promise<number> {
  const v = await nextVersion();
  const items = [
    `IT SYNTHETIC SCOPE ITEM ${marker} V${v}-A`,
    `IT SYNTHETIC SCOPE ITEM ${marker} V${v}-B`,
  ];
  const approved = await owner(
    "select public.record_package_scope_approval($1, $2, $3, $4, $5) v",
    [PKG, v, canonicalSha(PKG, v, items), `IT-DEP18-${marker}-${v}`, "e".repeat(64)],
  );
  expect(approved.ok, JSON.stringify(approved)).toBe(true);
  const loaded = await owner("select public.load_package_scope_version($1, $2, $3) v", [
    PKG,
    v,
    items,
  ]);
  expect(loaded.ok, JSON.stringify(loaded)).toBe(true);
  if (activate) {
    const act = await owner("select public.activate_package_scope_version($1, $2) v", [PKG, v]);
    expect(act.ok, JSON.stringify(act)).toBe(true);
  }
  return v;
}

async function waitsOnAdvisoryLock(pid: number): Promise<boolean> {
  for (let i = 0; i < 100; i += 1) {
    const r = await admin.query(
      "select exists (select 1 from pg_locks where pid = $1 and locktype = 'advisory' and not granted) w",
      [pid],
    );
    if (r.rows[0].w) return true;
    await new Promise((res) => setTimeout(res, 50));
  }
  return false;
}

async function pidOf(c: Client): Promise<number> {
  return Number((await c.query("select pg_backend_pid() p")).rows[0].p);
}

const ISSUE_SQL =
  "select public.issue_order_summary($1, $2, '[]'::jsonb, null, 'Synthetic race order') v";

beforeAll(async () => {
  admin = new Client({ connectionString: DB_URL });
  a = new Client({ connectionString: DB_URL });
  b = new Client({ connectionString: DB_URL });
  await Promise.all([admin.connect(), a.connect(), b.connect()]);
  for (const c of [a, b]) await c.query("set lock_timeout = '15s'; set statement_timeout = '20s'");
  const env = await admin.query("select private.app_environment() e");
  expect(env.rows[0].e).toBe("development");
  ownerSession = await newSession(OWNER_ID);
  salesSession = await newSession(SALES_ID);
  await admin.query("begin");
  await as(admin, SALES_ID, salesSession);
  const p = await admin.query(
    "select public.sales_create_customer_project($1, $2, $3) ->> 'project_id' as id",
    [`DEP18 Race ${marker} LLC`, `DEP18 Race ${marker}`, "Race site"],
  );
  await admin.query("commit");
  projectId = p.rows[0].id as string;
  expect(projectId).toBeTruthy();
});

afterAll(async () => {
  await Promise.all([admin?.end(), a?.end(), b?.end()]);
});

describe("AUTH-018 serialization (local stack, parallel connections)", () => {
  it("withdrawal first: issuance waits, then sees the withdrawal and fails closed", async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      const v = await prepareVersion(true);
      await a.query("begin");
      const w = await ownerCall(a, "select public.withdraw_package_scope_version($1, $2) v", [
        PKG,
        v,
      ]);
      expect(w.ok).toBe(true);
      await b.query("begin");
      await as(b, SALES_ID, salesSession);
      const bPid = await pidOf(b);
      const pending = b.query(ISSUE_SQL, [projectId, PKG]);
      expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
      await a.query("commit");
      const issued = (await pending).rows[0].v as Record<string, unknown>;
      await b.query("rollback");
      expect(issued.error, JSON.stringify(issued)).toBe("scope_definition_missing");
    }
  });

  it("issuance first: the withdrawal waits for it; the committed issuance stays valid", async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      const v = await prepareVersion(true);
      await b.query("begin");
      await as(b, SALES_ID, salesSession);
      const issued = (await b.query(ISSUE_SQL, [projectId, PKG])).rows[0].v as Record<
        string,
        unknown
      >;
      expect(issued.ok, JSON.stringify(issued)).toBe(true);
      await a.query("begin");
      const aPid = await pidOf(a);
      const pending = ownerCall(a, "select public.withdraw_package_scope_version($1, $2) v", [
        PKG,
        v,
      ]);
      expect(await waitsOnAdvisoryLock(aPid)).toBe(true);
      await b.query("commit");
      const w = await pending;
      await a.query("commit");
      expect(w.ok).toBe(true);
      const os = await admin.query("select scope_items from public.order_summaries where id = $1", [
        issued.order_summary_id,
      ]);
      expect(os.rows[0].scope_items).toHaveLength(2);
      await b.query("begin");
      await as(b, SALES_ID, salesSession);
      const after = (await b.query(ISSUE_SQL, [projectId, PKG])).rows[0].v as Record<
        string,
        unknown
      >;
      await b.query("rollback");
      expect(after.error).toBe("scope_definition_missing");
    }
  });

  it("a load committed while issuance waited suspends issuance (newest version inactive)", async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      await prepareVersion(true);
      const v = await nextVersion();
      const items = [`IT SYNTHETIC SCOPE ITEM ${marker} L${v}`];
      await owner("select public.record_package_scope_approval($1, $2, $3, $4, $5) v", [
        PKG,
        v,
        canonicalSha(PKG, v, items),
        `IT-DEP18-${marker}-L${v}`,
        "e".repeat(64),
      ]);
      await a.query("begin");
      const l = await ownerCall(a, "select public.load_package_scope_version($1, $2, $3) v", [
        PKG,
        v,
        items,
      ]);
      expect(l.ok).toBe(true);
      await b.query("begin");
      await as(b, SALES_ID, salesSession);
      const bPid = await pidOf(b);
      const pending = b.query(ISSUE_SQL, [projectId, PKG]);
      expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
      await a.query("commit");
      const issued = (await pending).rows[0].v as Record<string, unknown>;
      await b.query("rollback");
      expect(issued.error).toBe("scope_definition_missing");
    }
  });

  it("withdrawal first: a concurrent activation waits and is refused; no reactivation", async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      const v = await prepareVersion(false);
      await a.query("begin");
      await ownerCall(a, "select public.withdraw_package_scope_version($1, $2) v", [PKG, v]);
      await b.query("begin");
      const bPid = await pidOf(b);
      const pending = ownerCall(b, "select public.activate_package_scope_version($1, $2) v", [
        PKG,
        v,
      ]);
      expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
      await a.query("commit");
      const act = await pending;
      await b.query("commit");
      expect(act.error).toBe("withdrawn");
      const rows = await admin.query(
        "select string_agg(event, ',' order by event) e from private.billing_package_scope_eligibility where package_key = $1 and scope_version = $2",
        [PKG, v],
      );
      expect(rows.rows[0].e).toBe("withdrawn");
    }
  });

  it("concurrent identical activations and loads produce one record and one event", async () => {
    for (let i = 0; i < REPETITIONS; i += 1) {
      const v = await prepareVersion(false);
      await a.query("begin");
      await b.query("begin");
      const x = await ownerCall(a, "select public.activate_package_scope_version($1, $2) v", [
        PKG,
        v,
      ]);
      const bActPid = await pidOf(b);
      const pendingY = ownerCall(b, "select public.activate_package_scope_version($1, $2) v", [
        PKG,
        v,
      ]);
      expect(await waitsOnAdvisoryLock(bActPid)).toBe(true);
      await a.query("commit");
      const y = await pendingY;
      await b.query("commit");
      expect([x.replayed, y.replayed].sort()).toEqual([false, true]);
      const n = await admin.query(
        `select (select count(*) from private.billing_package_scope_eligibility where package_key = $1 and scope_version = $2)::int e,
                (select count(*) from public.audit_events where action = 'package_scope.activated' and target_id = $1 || ':' || $2)::int a`,
        [PKG, v],
      );
      expect(n.rows[0]).toEqual({ e: 1, a: 1 });

      const w = await nextVersion();
      const items = [`IT SYNTHETIC SCOPE ITEM ${marker} D${w}`];
      await owner("select public.record_package_scope_approval($1, $2, $3, $4, $5) v", [
        PKG,
        w,
        canonicalSha(PKG, w, items),
        `IT-DEP18-${marker}-D${w}`,
        "e".repeat(64),
      ]);
      await a.query("begin");
      await b.query("begin");
      const first = await ownerCall(a, "select public.load_package_scope_version($1, $2, $3) v", [
        PKG,
        w,
        items,
      ]);
      const bPid = await pidOf(b);
      const second = ownerCall(b, "select public.load_package_scope_version($1, $2, $3) v", [
        PKG,
        w,
        items,
      ]);
      expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
      await a.query("commit");
      const s = await second;
      await b.query("commit");
      expect(first.replayed).toBe(false);
      expect(s.replayed).toBe(true);
      const m = await admin.query(
        `select (select count(*) from private.billing_package_scope_versions where package_key = $1 and scope_version = $2)::int h,
                (select count(*) from public.audit_events where action = 'package_scope.loaded' and target_id = $1 || ':' || $2)::int a`,
        [PKG, w],
      );
      expect(m.rows[0]).toEqual({ h: 1, a: 1 });
    }
  });
});
