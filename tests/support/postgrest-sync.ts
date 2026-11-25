import { withDb } from "./db";
import { probePostgrest, type ProbeOutcome } from "./postgrest-ready";

/**
 * Deterministic PostgREST schema-cache synchronization around authorized local test DDL
 * (AUTH-008 I-1 item 3; F2, CURRENT-STATE §7). Local stack only, synthetic data only.
 *
 * Supabase installs the `pgrst_ddl_watch` event trigger, which sends `NOTIFY pgrst, 'reload
 * schema'` for every committed `ALTER TABLE`, `CREATE FUNCTION`, `ALTER TYPE` (and similar)
 * command, including a test's `alter table ... disable/enable trigger`. PostgREST (v16.5 in
 * the local stack) answers each message by opening new connections, re-reading its
 * configuration and schema cache, and then releasing every pool connection it held.
 *
 * The synchronization point is therefore observable in the database and does not depend on
 * a sleep: before the DDL, a request through PostgREST leaves at least one pooled backend
 * (`application_name` "PostgREST ..."); after the DDL commits, the reload is complete once
 * every one of those backends has been released. A final request through PostgREST must then
 * succeed. One overall deadline bounds every step (AUTH-008 Amendment 1); nothing is retried.
 */

/** Overall deadline for one synchronization (priming probe, reload wait, final probe). */
const DEADLINE_MS = 15_000;
/** Upper bound for one PostgREST request or database poll (further bounded by the deadline). */
const REQUEST_TIMEOUT_MS = 5_000;

const POOLED_BACKENDS = `select pid from pg_stat_activity
  where application_name like 'PostgREST%' and backend_type = 'client backend'
    and query not like 'LISTEN%'`;

async function pooledBackends(timeoutMs: number): Promise<number[]> {
  return withDb(async (db) => {
    // Bounded on the server: the poll fails instead of stalling past the deadline.
    await db.query(`set statement_timeout = ${Math.max(1, Math.floor(timeoutMs))}`);
    const result = await db.query(POOLED_BACKENDS);
    return result.rows.map((r: { pid: number }) => r.pid);
  });
}

export type SchemaCacheSync = {
  /** Milliseconds from the DDL's completion to the end of the PostgREST reload. */
  reloadMs: number;
};

const describe = (o: ProbeOutcome) =>
  JSON.stringify({
    kind: o.kind,
    status: o.status,
    code: o.code,
    detail: o.detail,
    ms: o.durationMs,
  });

/**
 * Runs `ddl` (which must commit DDL that the `pgrst_ddl_watch` trigger reports) and returns
 * only after PostgREST has finished the schema-cache reload that the DDL caused. Every step
 * outside `ddl` shares one overall deadline: each PostgREST request and database poll is
 * bounded by the smaller of the remaining deadline and an individual timeout (requests are
 * aborted when they stall), and the helper throws with diagnostics when the deadline passes.
 * Nothing is retried: a failed probe fails the calling test.
 */
export async function withSchemaCacheSync<T>(
  ddl: () => Promise<T>,
): Promise<{ result: T; sync: SchemaCacheSync }> {
  const started = Date.now();
  const remaining = () => DEADLINE_MS - (Date.now() - started);
  const bound = () => {
    const left = remaining();
    if (left <= 0) {
      throw new Error(
        `Schema-cache sync: the ${DEADLINE_MS} ms deadline passed (${Date.now() - started} ms elapsed)`,
      );
    }
    return Math.min(left, REQUEST_TIMEOUT_MS);
  };

  const primed = await probePostgrest({ timeoutMs: bound() });
  if (!primed.ok) {
    throw new Error(
      `Schema-cache sync: PostgREST probe failed before the DDL: ${describe(primed)}`,
    );
  }
  const before = await pooledBackends(bound());
  if (before.length === 0) {
    throw new Error("Schema-cache sync: no pooled PostgREST backend exists after the probe");
  }
  const result = await ddl();
  const committed = Date.now();
  let pooled = before;
  while (pooled.length > 0) {
    if (remaining() <= 0) {
      throw new Error(
        `Schema-cache sync: PostgREST did not complete a reload within the ${DEADLINE_MS} ms ` +
          `deadline (${Date.now() - committed} ms after the DDL; backends still pooled from ` +
          `before the DDL: ${pooled.join(", ")}). Did the DDL commit, and does it fire ` +
          "pgrst_ddl_watch?",
      );
    }
    await new Promise((resolve) => setTimeout(resolve, Math.min(10, Math.max(remaining(), 0))));
    const now = new Set(await pooledBackends(bound()));
    pooled = pooled.filter((pid) => now.has(pid));
  }
  const reloadMs = Date.now() - committed;
  const after = await probePostgrest({ timeoutMs: bound() });
  if (!after.ok) {
    throw new Error(
      `Schema-cache sync: PostgREST probe failed after the reload: ${describe(after)}`,
    );
  }
  // Diagnostic evidence for F2 (timing of every synchronized reload).
  console.warn(`[schema-cache-sync] PostgREST reload completed ${reloadMs} ms after the DDL`);
  return { result, sync: { reloadMs } };
}
