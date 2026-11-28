import { readFileSync } from "node:fs";
import { join } from "node:path";

import { Client } from "pg";
import { describe, expect, it } from "vitest";

/**
 * AUTH-026 (OI-131), PR 2: the staff operational queue against the LOCAL stack.
 *
 * 1. Equivalence (acceptance 1): the queue's output equals the previous definition's output
 *    exactly, item for item and in order. Both are evaluated in one transaction: the previous
 *    definition (as last created by 20261128130000) is loaded as a pg_temp function from the
 *    migration file itself, so this test cannot drift from what it replaced. It runs over the
 *    database as the earlier suites leave it, plus WP-B's synthetic matrix where available.
 *    Everything is rolled back.
 * 2. Evaluation counts (acceptance 2): one queue call evaluates WP-B's set-based helper once
 *    and the per-project financial functions zero times, read from pg_stat_xact_user_functions.
 *    `track_functions` can be set only by the local stack's superuser, so this connection is
 *    `supabase_admin`, on 127.0.0.1 only, inside a rolled-back transaction (recorded by Main).
 */

const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const DB_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const host = new URL(DB_URL).hostname;
if (!["127.0.0.1", "localhost"].includes(host)) throw new Error("local only");
const SUPERUSER_URL = `postgresql://supabase_admin:postgres@${host}:${new URL(DB_URL).port || "54322"}/postgres`;

/** The previous queue definition, renamed into pg_temp. */
function previousQueue(): string {
  const text = readFileSync(
    join(process.cwd(), "supabase/migrations/20261128130000_wpc_pwp5b_inactivity.sql"),
    "utf8",
  );
  const start = text.indexOf("create or replace function private.operational_queue()");
  const end = text.indexOf("$$;", start) + 3;
  if (start < 0 || end < 3) throw new Error("previous queue definition not found");
  return text
    .slice(start, end)
    .replace(
      "create or replace function private.operational_queue()",
      "create function pg_temp.operational_queue_previous()",
    );
}

async function asStaff(c: Client) {
  const sid = (
    await c.query(
      `insert into auth.sessions (id, user_id, created_at, updated_at, aal)
       values (gen_random_uuid(), $1, now(), now(), 'aal2') returning id::text`,
      [ADMIN_ID],
    )
  ).rows[0].id as string;
  await c.query(
    `select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated',
       'aal', 'aal2', 'session_id', $2::text)::text, true)`,
    [ADMIN_ID, sid],
  );
}

async function connect(url: string) {
  const c = new Client({ connectionString: url });
  await c.connect();
  await c.query("set lock_timeout = '15s'; set statement_timeout = '120s'");
  return c;
}

describe("AUTH-026: the staff operational queue (OI-131)", () => {
  it("equals the previous definition item for item and in order, in one transaction", async () => {
    const c = await connect(DB_URL);
    try {
      await c.query("begin");
      await c.query(previousQueue());
      await asStaff(c);
      const { rows } = await c.query(
        `with prev as (select row_number() over () as n, q from pg_temp.operational_queue_previous() q),
              curr as (select row_number() over () as n, q from private.operational_queue() q)
         select (select count(*)::int from prev) as previous,
                (select count(*)::int from curr) as current,
                (select count(*)::int from prev full join curr using (n) where prev.q is distinct from curr.q) as differing,
                (select string_agg(q::text, '|' order by n) from prev)
                  = (select string_agg(q::text, '|' order by n) from curr) as identical`,
      );
      expect(rows[0].previous).toBeGreaterThan(0);
      expect(rows[0]).toEqual({
        previous: rows[0].previous,
        current: rows[0].previous,
        differing: 0,
        identical: true,
      });
    } finally {
      await c.query("rollback").catch(() => undefined);
      await c.end();
    }
  }, 300_000);

  it("evaluates the set-based helper once and no per-project financial function", async () => {
    const c = await connect(SUPERUSER_URL);
    try {
      await c.query("begin");
      await c.query("set local track_functions = 'all'");
      await asStaff(c);
      await c.query("set local role authenticated");
      const items = (await c.query("select count(*)::int as n from public.operational_queue()"))
        .rows[0].n as number;
      await c.query("reset role");
      const { rows } = await c.query(
        `select f.funcname::text as name, f.calls::int as calls from pg_stat_xact_user_functions f
          where f.schemaname = 'private'
            and f.funcname in ('financial_evaluation_for_projects', 'project_financial_status',
                               'project_financial_anomalies', 'gate_anomalies', 'operational_queue')`,
      );
      const calls = Object.fromEntries(rows.map((r) => [r.name as string, r.calls as number]));
      expect(items).toBeGreaterThan(0);
      expect(calls.operational_queue).toBe(1);
      expect(calls.financial_evaluation_for_projects).toBe(1);
      expect(calls.project_financial_anomalies ?? 0).toBe(0);
      expect(calls.project_financial_status ?? 0).toBe(0);
      expect(calls.gate_anomalies ?? 0).toBe(0);
    } finally {
      await c.query("rollback").catch(() => undefined);
      await c.end();
    }
  }, 300_000);
});
