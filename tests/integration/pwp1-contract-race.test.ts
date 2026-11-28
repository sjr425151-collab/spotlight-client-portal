import { createHash, randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/**
 * AUTH-021 (PWP-1; 04 §4A v0.11.0, OD-3 and OD-4): real-connection concurrency for contract
 * instruments and bundles, against the LOCAL stack with parallel database connections and the
 * real functions (no function is replaced).
 *
 *   T-CON-02: two sessions creating an instrument version, and two sessions sealing a bundle, for
 *             one package yield consecutive versions with no duplicate or gap.
 *   Sealing against withdrawal, activation against withdrawal and resolution against withdrawal,
 *   in both commit orders (the withdrawal side of T-CON-07): the first committed outcome wins.
 *
 * Every wait is observed in pg_locks (an ungranted advisory lock). A deadlock (40P01), a lock
 * timeout or any unexpected refusal fails the test. Content is synthetic and non-legal (D11),
 * local and CI only. The records are append-only, so this suite uses the `signature` package,
 * which no other integration or e2e test uses; run it on a freshly reset local database.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const PKG = "signature";
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
const ids: Record<string, string> = {};
let scopeVersion = 0;

const len = (s: string) => Buffer.byteLength(s, "utf8");
const sha = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");
function instrumentSha(
  kind: string,
  pkg: string | null,
  v: number,
  t: string,
  body: string,
  p: string[],
) {
  return sha(
    "spotlight.contract_instrument.v1" +
      `|kind${len(kind)}:${kind}|pkg${pkg === null ? "-" : `${len(pkg)}:${pkg}`}|v${v}` +
      `|t${len(t)}:${t}|b${len(body)}:${body}|n${p.length}` +
      p.map((x) => `|p${len(x)}:${x}`).join(""),
  );
}
function scopeSha(pkg: string, v: number, items: string[]) {
  return sha(
    `spotlight.package_scope.v1|k${len(pkg)}:${pkg}|v${v}|n${items.length}` +
      items.map((t, i) => `|p${i + 1}:${len(t)}:${t}`).join(""),
  );
}

function claims(): string {
  return JSON.stringify({
    sub: OWNER_ID,
    role: "authenticated",
    aal: "aal2",
    session_id: ownerSession,
    amr: [{ method: "totp", timestamp: Math.floor(Date.now() / 1000) }],
  });
}
async function asOwner(c: Client): Promise<void> {
  await c.query("select set_config('request.jwt.claims', $1, true)", [claims()]);
  await c.query("set local role authenticated");
}
async function asSales(c: Client): Promise<void> {
  const claimsSales = JSON.stringify({
    sub: SALES_ID,
    role: "authenticated",
    aal: "aal2",
    session_id: salesSession,
    amr: [{ method: "totp", timestamp: Math.floor(Date.now() / 1000) }],
  });
  await c.query("select set_config('request.jwt.claims', $1, true)", [claimsSales]);
  await c.query("set local role authenticated");
}
async function ownerCall(
  c: Client,
  sql: string,
  params: unknown[],
): Promise<Record<string, unknown>> {
  await asOwner(c);
  return (await c.query(sql, params)).rows[0].v as Record<string, unknown>;
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
async function one<T = unknown>(sql: string, params: unknown[] = []): Promise<T> {
  return (await admin.query(sql, params)).rows[0] as T;
}
async function pidOf(c: Client): Promise<number> {
  return Number((await c.query("select pg_backend_pid() p")).rows[0].p);
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

async function nextInstrumentVersion(kind: string, pkg: string | null): Promise<number> {
  const r = await one<{ n: number }>(
    `select coalesce(max(instrument_version), 0) + 1 as n from private.contract_instrument_versions
      where kind = $1 and package_key is not distinct from $2`,
    [kind, pkg],
  );
  return Number(r.n);
}
async function loadInstrument(
  kind: string,
  pkg: string | null,
  provisions: string[],
): Promise<string> {
  const v = await nextInstrumentVersion(kind, pkg);
  const title = `IT SYNTHETIC ${kind} ${marker}`;
  const body = `IT SYNTHETIC ${kind} BODY ${marker} v${v}`;
  const r = await owner(
    "select public.create_contract_instrument_version($1, $2, $3, $4, $5, $6, $7) v",
    [kind, pkg, v, title, body, provisions, instrumentSha(kind, pkg, v, title, body, provisions)],
  );
  expect(r.ok, JSON.stringify(r)).toBe(true);
  return r.instrument_id as string;
}

const SEAL_SQL = "select public.seal_contract_bundle($1, $2, $3, $4, $5, $6, $7, $8) v";
const sealParams = (title: string) => [
  PKG,
  title,
  ids.agreement,
  ids.package,
  ids.maintenance,
  ids.shared,
  scopeVersion,
  JSON.stringify(["IT-P1", "IT-P2"]),
];
async function sealFresh(activate: boolean): Promise<{ id: string; sha: string }> {
  const s = await owner(
    SEAL_SQL,
    sealParams(`IT SYNTHETIC BUNDLE ${marker} ${randomUUID().slice(0, 8)}`),
  );
  expect(s.ok, JSON.stringify(s)).toBe(true);
  const id = s.bundle_id as string;
  const bundleSha = s.bundle_sha256 as string;
  if (activate) {
    const ap = await owner("select public.record_contract_bundle_approval($1, $2, $3, $4) v", [
      id,
      bundleSha,
      `IT-LEGAL-${marker}`,
      "e".repeat(64),
    ]);
    expect(ap.ok, JSON.stringify(ap)).toBe(true);
    const ac = await owner("select public.activate_contract_bundle($1) v", [id]);
    expect(ac.ok, JSON.stringify(ac)).toBe(true);
  }
  return { id, sha: bundleSha };
}
const resolvedId = async (c: Client) =>
  ((await c.query("select bundle_id from private.current_contract_bundle($1)", [PKG])).rows[0]
    ?.bundle_id ?? null) as string | null;

beforeAll(async () => {
  admin = new Client({ connectionString: DB_URL });
  a = new Client({ connectionString: DB_URL });
  b = new Client({ connectionString: DB_URL });
  await Promise.all([admin.connect(), a.connect(), b.connect()]);
  for (const c of [a, b]) await c.query("set lock_timeout = '15s'; set statement_timeout = '20s'");
  expect((await one<{ e: string }>("select private.app_environment() e")).e).toBe("development");
  ownerSession = randomUUID();
  await admin.query(
    "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), 'aal2')",
    [ownerSession, OWNER_ID],
  );
  await admin.query(
    `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
     select gen_random_uuid(), $1, 'it-pwp1', 'totp', 'verified', now(), now()
     where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
    [OWNER_ID],
  );
  salesSession = randomUUID();
  await admin.query(
    "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), 'aal2')",
    [salesSession, SALES_ID],
  );
  await admin.query(
    `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
     select gen_random_uuid(), $1, 'it-pwp1', 'totp', 'verified', now(), now()
     where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
    [SALES_ID],
  );
  await admin.query("begin");
  await asSales(admin);
  projectId = (
    await admin.query(
      "select public.sales_create_customer_project($1, $2, $3) ->> 'project_id' as id",
      [`PWP1 Race ${marker} LLC`, `PWP1 Race ${marker}`, "Race site"],
    )
  ).rows[0].id as string;
  await admin.query("commit");
  // A synthetic approved agreement holding only a heading and the approved 04 §3.1 clause. It is
  // dated before the seeded fixture agreement (2026-11-24) so that issuance, which takes the
  // usable agreement with the latest effective date, keeps using the fixture in later suites.
  const text = (
    await one<{ t: string }>(
      "select 'IT SYNTHETIC AGREEMENT " +
        marker +
        "' || E'\\n\\n' || private.final_payment_clause() t",
    )
  ).t;
  const ag = await owner(
    "select public.create_agreement_version($1, $2, date '2026-11-01', $3) v",
    [`it-pwp1-${marker}`, text, "IT-AGR"],
  );
  ids.agreement = ag.agreement_version_id as string;
  expect((await owner("select public.approve_agreement_version($1) v", [ids.agreement])).ok).toBe(
    true,
  );
  ids.package = await loadInstrument("package_specification", PKG, ["IT-P1", "IT-P2"]);
  ids.maintenance = await loadInstrument("maintenance_specification", null, ["IT-M1"]);
  ids.shared = await loadInstrument("shared_terms", null, ["IT-S1"]);
  // A synthetic AUTH-018 scope version, approved and loaded.
  scopeVersion = Number(
    (
      await one<{ n: number }>(
        `select coalesce(max(v), 0) + 1 as n from (
         select max(scope_version) v from private.billing_package_scope where package_key = $1
         union all select max(scope_version) from private.billing_package_scope_versions where package_key = $1) x`,
        [PKG],
      )
    ).n,
  );
  const items = [`IT SYNTHETIC SCOPE ${marker} A`, `IT SYNTHETIC SCOPE ${marker} B`];
  expect(
    (
      await owner("select public.record_package_scope_approval($1, $2, $3, $4, $5) v", [
        PKG,
        scopeVersion,
        scopeSha(PKG, scopeVersion, items),
        `IT-SCOPE-${marker}`,
        "e".repeat(64),
      ])
    ).ok,
  ).toBe(true);
  expect(
    (
      await owner("select public.load_package_scope_version($1, $2, $3) v", [
        PKG,
        scopeVersion,
        items,
      ])
    ).ok,
  ).toBe(true);
});

afterAll(async () => {
  await Promise.all([admin?.end(), a?.end(), b?.end()]);
});

// AUTH-025 (OI-130): remove the MFA factors this file creates, and only those, whatever the outcome.
afterAll(async () => {
  const c = new Client({ connectionString: DB_URL });
  await c.connect();
  try {
    await c.query("delete from auth.mfa_factors where friendly_name = 'it-pwp1'");
  } finally {
    await c.end();
  }
});

/**
 * N-3: per-scenario failure cleanup. Both connections are rolled back concurrently whether the
 * scenario passed or failed, so one failed check cannot leave a transaction (and its advisory
 * locks) open into later scenarios. A rollback queued behind a waiting query runs once the other
 * connection's rollback releases the lock it waits on. Only cleanup errors are swallowed; the
 * original failure still propagates.
 */
function scenario(fn: () => Promise<void>): () => Promise<void> {
  return async () => {
    try {
      await fn();
    } finally {
      await Promise.allSettled([a.query("rollback"), b.query("rollback")]);
    }
  };
}

describe("AUTH-021 serialization (local stack, parallel connections)", () => {
  it(
    "T-CON-02: two sessions creating instrument versions yield consecutive versions",
    scenario(async () => {
      for (let i = 0; i < REPETITIONS; i += 1) {
        const before = await nextInstrumentVersion("shared_terms", null);
        await a.query("begin");
        await b.query("begin");
        await a.query(
          "select private.construct_contract_instrument('shared_terms', null, $1, $2, array['IT-S1'], false)",
          [`IT SYNTHETIC race ${marker}`, `IT SYNTHETIC race A ${marker} ${i}`],
        );
        const bPid = await pidOf(b);
        const pending = b.query(
          "select private.construct_contract_instrument('shared_terms', null, $1, $2, array['IT-S1'], false) r",
          [`IT SYNTHETIC race ${marker}`, `IT SYNTHETIC race B ${marker} ${i}`],
        );
        expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
        await a.query("commit");
        await pending;
        await b.query("commit");
        const v = await one<{ s: string }>(
          `select string_agg(instrument_version::text, ',' order by instrument_version) s
           from private.contract_instrument_versions where kind = 'shared_terms' and instrument_version >= $1`,
          [before],
        );
        expect(v.s).toBe(`${before},${before + 1}`);
      }
    }),
  );

  it(
    "T-CON-02: two sessions sealing bundles for one package yield consecutive versions",
    scenario(async () => {
      for (let i = 0; i < REPETITIONS; i += 1) {
        const before = Number(
          (
            await one<{ n: number }>(
              "select coalesce(max(bundle_version), 0) + 1 n from private.contract_bundles where package_key = $1",
              [PKG],
            )
          ).n,
        );
        await a.query("begin");
        await b.query("begin");
        const first = await ownerCall(
          a,
          SEAL_SQL,
          sealParams(`IT SYNTHETIC BUNDLE ${marker} A${i}`),
        );
        expect(first.ok, JSON.stringify(first)).toBe(true);
        const bPid = await pidOf(b);
        const pending = ownerCall(b, SEAL_SQL, sealParams(`IT SYNTHETIC BUNDLE ${marker} B${i}`));
        expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
        await a.query("commit");
        const second = await pending;
        await b.query("commit");
        expect(second.ok, JSON.stringify(second)).toBe(true);
        expect([first.bundle_version, second.bundle_version]).toEqual([before, before + 1]);
      }
    }),
  );

  it(
    "sealing against withdrawal, both orders: each waits for the other; the outcomes are consistent",
    scenario(async () => {
      for (let i = 0; i < REPETITIONS; i += 1) {
        // Withdrawal first; the seal waits, then seals the next version.
        const w1 = await sealFresh(true);
        await a.query("begin");
        const wd = await ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          w1.id,
          "IT race",
          "IT-WD",
        ]);
        expect(wd.ok, JSON.stringify(wd)).toBe(true);
        await b.query("begin");
        const bPid = await pidOf(b);
        const pendingSeal = ownerCall(
          b,
          SEAL_SQL,
          sealParams(`IT SYNTHETIC BUNDLE ${marker} S${i}`),
        );
        expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
        await a.query("commit");
        const sealed = await pendingSeal;
        await b.query("commit");
        expect(sealed.ok, JSON.stringify(sealed)).toBe(true);
        // Seal first; the withdrawal of the previous bundle waits, then succeeds.
        const w2 = await sealFresh(true);
        await b.query("begin");
        const s2 = await ownerCall(b, SEAL_SQL, sealParams(`IT SYNTHETIC BUNDLE ${marker} T${i}`));
        expect(s2.ok, JSON.stringify(s2)).toBe(true);
        await a.query("begin");
        const aPid = await pidOf(a);
        const pendingWd = ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          w2.id,
          "IT race",
          "IT-WD",
        ]);
        expect(await waitsOnAdvisoryLock(aPid)).toBe(true);
        await b.query("commit");
        const wd2 = await pendingWd;
        await a.query("commit");
        expect(wd2.ok, JSON.stringify(wd2)).toBe(true);
      }
    }),
  );

  it(
    "activation against withdrawal, both orders: no reactivation after a committed withdrawal",
    scenario(async () => {
      for (let i = 0; i < REPETITIONS; i += 1) {
        // Withdrawal first: the waiting activation is refused as withdrawn.
        const x = await sealFresh(false);
        expect(
          (
            await owner("select public.record_contract_bundle_approval($1, $2, $3, $4) v", [
              x.id,
              x.sha,
              `IT-LEGAL-${marker}`,
              "e".repeat(64),
            ])
          ).ok,
        ).toBe(true);
        await a.query("begin");
        await ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          x.id,
          "IT race",
          "IT-WD",
        ]);
        await b.query("begin");
        const bPid = await pidOf(b);
        const pending = ownerCall(b, "select public.activate_contract_bundle($1) v", [x.id]);
        expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
        await a.query("commit");
        const act = await pending;
        await b.query("commit");
        expect(act.error).toBe("withdrawn");
        // Activation first: the withdrawal waits, then succeeds; the bundle ends withdrawn.
        const y = await sealFresh(false);
        expect(
          (
            await owner("select public.record_contract_bundle_approval($1, $2, $3, $4) v", [
              y.id,
              y.sha,
              `IT-LEGAL-${marker}`,
              "e".repeat(64),
            ])
          ).ok,
        ).toBe(true);
        await b.query("begin");
        expect(
          (await ownerCall(b, "select public.activate_contract_bundle($1) v", [y.id])).ok,
        ).toBe(true);
        await a.query("begin");
        const aPid = await pidOf(a);
        const pendingWd = ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          y.id,
          "IT race",
          "IT-WD",
        ]);
        expect(await waitsOnAdvisoryLock(aPid)).toBe(true);
        await b.query("commit");
        expect((await pendingWd).ok).toBe(true);
        await a.query("commit");
        const events = await one<{ e: string }>(
          "select string_agg(event, ',' order by event) e from private.contract_bundle_eligibility where bundle_id = $1",
          [y.id],
        );
        expect(events.e).toBe("activated,withdrawn");
        expect(await resolvedId(admin)).toBeNull();
      }
    }),
  );

  it(
    "resolution against withdrawal, both orders: a committed withdrawal is seen after the wait",
    scenario(async () => {
      for (let i = 0; i < REPETITIONS; i += 1) {
        // Withdrawal first: the waiting resolver then sees the withdrawal and returns nothing.
        const x = await sealFresh(true);
        expect(await resolvedId(admin)).toBe(x.id);
        await a.query("begin");
        await ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          x.id,
          "IT race",
          "IT-WD",
        ]);
        await b.query("begin");
        const bPid = await pidOf(b);
        const pending = resolvedId(b);
        expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
        await a.query("commit");
        expect(await pending).toBeNull();
        await b.query("commit");
        // Resolution first (shared lock held to commit): the withdrawal waits for it.
        const y = await sealFresh(true);
        await b.query("begin");
        expect(await resolvedId(b)).toBe(y.id);
        await a.query("begin");
        const aPid = await pidOf(a);
        const pendingWd = ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          y.id,
          "IT race",
          "IT-WD",
        ]);
        expect(await waitsOnAdvisoryLock(aPid)).toBe(true);
        await b.query("commit");
        expect((await pendingWd).ok).toBe(true);
        await a.query("commit");
        expect(await resolvedId(admin)).toBeNull();
      }
    }),
  );

  it(
    "requirement A: issuance against bundle governance, both orders: it waits, with no lock cycle",
    scenario(async () => {
      // The setup loads the synthetic scope version but never activates it, so issuance has no active
      // scope definition in either order: anything other than scope_definition_missing fails.
      const issue =
        "select public.issue_order_summary($1, $2, '[]'::jsonb, null, 'Synthetic race order') v";
      for (let i = 0; i < REPETITIONS; i += 1) {
        // Governance first (per-package lock exclusive); issuance holds the project row and waits on it.
        const x = await sealFresh(true);
        await a.query("begin");
        await ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          x.id,
          "IT race",
          "IT-WD",
        ]);
        await b.query("begin");
        await asSales(b);
        const bPid = await pidOf(b);
        const pending = b.query(issue, [projectId, PKG]);
        expect(await waitsOnAdvisoryLock(bPid)).toBe(true);
        await a.query("commit");
        const r1 = (await pending).rows[0].v as Record<string, unknown>;
        await b.query("rollback");
        expect(r1.error).toBe("scope_definition_missing");
        // Issuance first (shared lock held to commit); governance waits for it.
        const y = await sealFresh(true);
        await b.query("begin");
        await asSales(b);
        const r2 = (await b.query(issue, [projectId, PKG])).rows[0].v as Record<string, unknown>;
        expect(r2.error).toBe("scope_definition_missing");
        await a.query("begin");
        const aPid = await pidOf(a);
        const pendingWd = ownerCall(a, "select public.withdraw_contract_bundle($1, $2, $3) v", [
          y.id,
          "IT race",
          "IT-WD",
        ]);
        expect(await waitsOnAdvisoryLock(aPid)).toBe(true);
        await b.query("rollback");
        expect((await pendingWd).ok).toBe(true);
        await a.query("commit");
      }
    }),
  );
});
