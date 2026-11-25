import { existsSync } from "node:fs";

import { withDb } from "./db";

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
 * succeed. Every wait is bounded and fails with diagnostics; nothing is retried silently.
 */

if (!process.env.SUPABASE_SECRET_KEY && existsSync(".env.local")) {
  process.loadEnvFile(".env.local");
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321";
const SECRET_KEY = process.env.SUPABASE_SECRET_KEY ?? "";
const TIMEOUT_MS = 15_000;

if (!["127.0.0.1", "localhost"].includes(new URL(SUPABASE_URL).hostname)) {
  throw new Error("Schema-cache synchronization may only run against a local Supabase stack");
}

const POOLED_BACKENDS = `select pid from pg_stat_activity
  where application_name like 'PostgREST%' and backend_type = 'client backend'
    and query not like 'LISTEN%'`;

/** A read-only request through PostgREST that returns no rows (the local stack's secret key). */
async function probe(): Promise<{ status: number; body: string }> {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/projects?select=id&limit=0`, {
    headers: { apikey: SECRET_KEY, Authorization: `Bearer ${SECRET_KEY}` },
  });
  return { status: response.status, body: (await response.text()).slice(0, 300) };
}

async function pooledBackends(): Promise<number[]> {
  return withDb(async (db) => (await db.query(POOLED_BACKENDS)).rows.map((r) => r.pid as number));
}

export type SchemaCacheSync = {
  /** Milliseconds from the DDL's completion to the end of the PostgREST reload. */
  reloadMs: number;
};

/**
 * Runs `ddl` (which must commit DDL that the `pgrst_ddl_watch` trigger reports) and returns
 * only after PostgREST has finished the schema-cache reload that the DDL caused.
 */
export async function withSchemaCacheSync<T>(
  ddl: () => Promise<T>,
): Promise<{ result: T; sync: SchemaCacheSync }> {
  const primed = await probe();
  if (primed.status !== 200) {
    throw new Error(`PostgREST probe failed before the DDL: ${primed.status} ${primed.body}`);
  }
  const before = await pooledBackends();
  if (before.length === 0) {
    throw new Error("Schema-cache sync: no pooled PostgREST backend exists after the probe");
  }
  const result = await ddl();
  const committed = Date.now();
  let remaining = before;
  while (remaining.length > 0) {
    if (Date.now() - committed > TIMEOUT_MS) {
      throw new Error(
        `Schema-cache sync: PostgREST did not complete a reload within ${TIMEOUT_MS} ms ` +
          `(backends still pooled from before the DDL: ${remaining.join(", ")}). ` +
          "Did the DDL commit, and does it fire pgrst_ddl_watch?",
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
    const now = new Set(await pooledBackends());
    remaining = remaining.filter((pid) => now.has(pid));
  }
  const reloadMs = Date.now() - committed;
  const after = await probe();
  if (after.status !== 200) {
    throw new Error(`PostgREST probe failed after the reload: ${after.status} ${after.body}`);
  }
  // Diagnostic evidence for F2 (timing of every synchronized reload).
  console.warn(`[schema-cache-sync] PostgREST reload completed ${reloadMs} ms after the DDL`);
  return { result, sync: { reloadMs } };
}
