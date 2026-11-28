import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/**
 * AUTH-026 (OI-131), WP-B: the evaluation counts of private.financial_evaluation_for_projects,
 * asserted from pg_stat_xact_user_functions deltas, against the LOCAL stack.
 *
 * One helper call over every active project evaluates the financial status of each project once,
 * in a single set-based pass: the helper runs once, and the per-project functions
 * (project_financial_status, project_financial_anomalies, gate_anomalies) run zero times. The same
 * transaction also checks exact equivalence with private.project_financial_status (to_jsonb byte
 * for byte, with failure parity) for every project the earlier suites left in the database.
 *
 * Function counting needs `track_functions`, which only a superuser may set: the test uses the
 * local Supabase CLI `supabase_admin` connection (CLI default credentials; local and CI only, by
 * the hostname guard), inside one transaction that is rolled back. WP-C's queue-level counts
 * (AUTH-026 PR 2) use the same mechanism. Synthetic data only; nothing persists.
 */

const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
if (!["127.0.0.1", "localhost"].includes(new URL(DB_URL).hostname)) throw new Error("local only");
const ADMIN_URL = (() => {
  const u = new URL(DB_URL);
  u.username = "supabase_admin";
  u.password = "postgres";
  return u.toString();
})();

const COUNTED = [
  "financial_evaluation_for_projects",
  "project_financial_status",
  "project_financial_anomalies",
  "gate_anomalies",
];

let admin: Client;

beforeAll(async () => {
  admin = new Client({ connectionString: ADMIN_URL });
  await admin.connect();
});

afterAll(async () => {
  await admin?.end();
});

async function calls(): Promise<Record<string, number>> {
  const { rows } = await admin.query<{ funcname: string; calls: string }>(
    `select funcname, calls from pg_stat_xact_user_functions
      where schemaname = 'private' and funcname = any($1::text[])`,
    [COUNTED],
  );
  const out: Record<string, number> = Object.fromEntries(COUNTED.map((f) => [f, 0]));
  for (const r of rows) out[r.funcname] = Number(r.calls);
  return out;
}

describe("AUTH-026: financial evaluation counts (pg_stat_xact_user_functions)", () => {
  it("evaluates every active project in one set-based pass, with no per-project evaluation", async () => {
    await admin.query("begin");
    try {
      await admin.query("set local track_functions = 'all'");
      const { rows: active } = await admin.query<{ n: number }>(
        "select count(*)::int as n from public.projects where archived_at is null",
      );
      const n = active[0]?.n ?? 0;
      expect(n).toBeGreaterThan(0);
      const before = await calls();
      const { rows } = await admin.query<{ n: number; failed: number }>(
        `select count(*)::int as n, count(*) filter (where failed)::int as failed
           from private.financial_evaluation_for_projects(
                  (select array_agg(id) from public.projects where archived_at is null))`,
      );
      const after = await calls();
      const delta = Object.fromEntries(COUNTED.map((f) => [f, (after[f] ?? 0) - (before[f] ?? 0)]));
      expect(rows[0]).toEqual({ n, failed: 0 });
      expect(delta).toEqual({
        financial_evaluation_for_projects: 1,
        project_financial_status: 0,
        project_financial_anomalies: 0,
        gate_anomalies: 0,
      });
    } finally {
      await admin.query("rollback");
    }
  });

  it("equals private.project_financial_status exactly for every project the suites reached", async () => {
    await admin.query("begin");
    try {
      const { rows } = await admin.query<{ n: number; mismatches: number }>(
        `select count(*)::int as n,
                count(*) filter (where e.failed
                                    or to_jsonb(e.status) is distinct from
                                       to_jsonb(private.project_financial_status(e.project_id)))::int as mismatches
           from private.financial_evaluation_for_projects((select array_agg(id) from public.projects)) e`,
      );
      expect(rows[0]?.n ?? 0).toBeGreaterThan(0);
      expect(rows[0]?.mismatches).toBe(0);
    } finally {
      await admin.query("rollback");
    }
  });
});
