import { Client, type QueryConfig } from "pg";

import { probePostgrest, type ProbeOutcome } from "./postgrest-ready";

/**
 * Deterministic PostgREST schema-cache synchronization around authorized local test DDL
 * (AUTH-008 I-1 item 3 and Amendment 1, including the Owner-approved W-1 correction; F2,
 * CURRENT-STATE §7). Local stack only, synthetic data only.
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
 * succeed. Nothing is retried: any failed step fails the calling test.
 *
 * Deadline (helper-owned operations only). One absolute budget covers every operation this
 * helper performs: the priming probe, each database connect, query, poll and close, the
 * pauses between polls, and the final probe. The remaining budget is recalculated before
 * every one of them, and each is bounded by the smaller of that remainder and a per-step
 * timeout, on the client side and independently of the server:
 *  - PostgREST requests are aborted with an `AbortSignal` (postgrest-ready.ts);
 *  - connection establishment uses pg's `connectionTimeoutMillis`;
 *  - waiting for a query response uses pg's client-side `query_timeout`;
 *  - closing races `client.end()` against the bound and destroys the socket if it is not
 *    closed in time.
 * `statement_timeout` is also set as defense in depth; it bounds only server-side statement
 * execution (it does not bound connecting, a stalled socket, or the close).
 *
 * The caller's `ddl()` is NOT bounded by this helper. It is the caller's own authorized
 * local test operation, and its duration is excluded from the helper's budget (the budget is
 * paused while it runs); a stalled `ddl()` is the caller's responsibility.
 *
 * pg internals (accepted by the Owner; verified against the pinned pg 8.16.3): after a
 * client-side query timeout pg leaves the connection open, and `client.end()` waits for the
 * socket's `end` event, so a timed-out query or an unfinished close is ended by destroying
 * `client.connection.stream` (the `net.Socket`). The access is guarded: if that interface is
 * absent the helper still fails closed with diagnostics.
 */

const DATABASE_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
/** Helper-owned budget for one synchronization. */
const DEADLINE_MS = 15_000;
/** Upper bound for one helper-owned step (further bounded by the remaining budget). */
const STEP_TIMEOUT_MS = 5_000;
const POLL_INTERVAL_MS = 10;

const POOLED_BACKENDS = `select pid from pg_stat_activity
  where application_name like 'PostgREST%' and backend_type = 'client backend'
    and query not like 'LISTEN%'`;

export type SyncStep =
  | "probe-before"
  | "connect"
  | "set-statement-timeout"
  | "query"
  | "close"
  | "poll-wait"
  | "reload-wait"
  | "probe-after";

/** A failed helper-owned step: which step, helper-owned elapsed time, its bound, the cause. */
export class SchemaCacheSyncError extends Error {
  constructor(
    readonly step: SyncStep,
    readonly elapsedMs: number,
    readonly boundMs: number | null,
    readonly detail: string,
  ) {
    super(
      `Schema-cache sync failed at ${step} after ${elapsedMs} ms of the helper's budget ` +
        `(bound ${boundMs ?? "none"} ms): ${detail}`,
    );
    this.name = "SchemaCacheSyncError";
  }
}

/** The helper-owned budget: one absolute deadline that can be paused while `ddl()` runs. */
export class SyncBudget {
  private spent = 0;
  private since: number | null = Date.now();

  constructor(
    readonly deadlineMs: number = DEADLINE_MS,
    readonly stepTimeoutMs: number = STEP_TIMEOUT_MS,
  ) {}

  elapsed(): number {
    return this.spent + (this.since === null ? 0 : Date.now() - this.since);
  }

  remaining(): number {
    return this.deadlineMs - this.elapsed();
  }

  pause() {
    if (this.since !== null) this.spent += Date.now() - this.since;
    this.since = null;
  }

  resume() {
    if (this.since === null) this.since = Date.now();
  }

  /** The bound for the next step; throws (fail closed) once the budget is exhausted. */
  bound(step: SyncStep): number {
    const left = this.remaining();
    if (left <= 0) {
      throw new SchemaCacheSyncError(
        step,
        this.elapsed(),
        0,
        `the ${this.deadlineMs} ms helper-owned deadline is exhausted`,
      );
    }
    return Math.max(1, Math.floor(Math.min(left, this.stepTimeoutMs)));
  }
}

const message = (error: unknown) =>
  error instanceof Error ? `${error.name}: ${error.message}` : String(error);

function assertLocalDatabase(url: string) {
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) {
    throw new Error("Tests may only connect to a local database");
  }
}

/** Destroys the client's socket (pg internal `connection.stream`), defensively. */
function destroySocket(client: Client): boolean {
  const stream = (client as unknown as { connection?: { stream?: { destroy?: () => void } } })
    .connection?.stream;
  if (typeof stream?.destroy !== "function") return false;
  stream.destroy();
  return true;
}

/** Ends the client within the budget; destroys the socket if that does not finish in time. */
async function boundedClose(client: Client, budget: SyncBudget, force: boolean) {
  if (force || budget.remaining() <= 0) {
    destroySocket(client);
    // Settle pg's own end bookkeeping without waiting on it.
    client.end().catch(() => {});
    return null;
  }
  const bound = budget.bound("close");
  let timer: NodeJS.Timeout | undefined;
  const ended = client.end().then(
    () => true,
    () => true,
  );
  const timedOut = new Promise<false>((resolve) => {
    timer = setTimeout(() => resolve(false), bound);
  });
  const closed = await Promise.race([ended, timedOut]);
  clearTimeout(timer);
  if (closed) return null;
  const destroyed = destroySocket(client);
  return new SchemaCacheSyncError(
    "close",
    budget.elapsed(),
    bound,
    `client.end() did not finish within the bound; socket ${destroyed ? "destroyed" : "could not be destroyed (pg connection.stream unavailable)"}`,
  );
}

/**
 * One poll of the PostgREST backends pooled in Postgres, through a client local to this
 * helper (W-1): connect, a server-side `statement_timeout`, the query, and the close are each
 * bounded by the remaining budget. Any failure destroys the connection and throws.
 */
export async function pollPooledBackends(
  budget: SyncBudget,
  databaseUrl: string = DATABASE_URL,
): Promise<number[]> {
  assertLocalDatabase(databaseUrl);
  const connectBound = budget.bound("connect");
  const client = new Client({
    connectionString: databaseUrl,
    connectionTimeoutMillis: connectBound,
  });
  // A socket error after connecting is reported through the failing step, never as an
  // unhandled 'error' event.
  client.on("error", () => {});
  let failure: SchemaCacheSyncError | null = null;
  let pids: number[] = [];
  let step: SyncStep = "connect";
  let bound = connectBound;
  try {
    await client.connect();
    step = "set-statement-timeout";
    bound = budget.bound(step);
    await client.query({
      text: `set statement_timeout = ${bound}`,
      query_timeout: bound,
    } as QueryConfig);
    step = "query";
    bound = budget.bound(step);
    const result = await client.query<{ pid: number }>({
      text: POOLED_BACKENDS,
      query_timeout: bound,
    } as QueryConfig);
    pids = result.rows.map((r) => r.pid);
  } catch (error) {
    failure =
      error instanceof SchemaCacheSyncError
        ? error
        : new SchemaCacheSyncError(step, budget.elapsed(), bound, message(error));
  }
  const closeFailure = await boundedClose(client, budget, failure !== null);
  if (failure) throw failure;
  if (closeFailure) throw closeFailure;
  return pids;
}

export type SchemaCacheSync = {
  /** Milliseconds from the DDL's completion to the end of the PostgREST reload. */
  reloadMs: number;
  /** Helper-owned milliseconds used (the caller's `ddl()` excluded). */
  helperMs: number;
};

export type SchemaCacheSyncOptions = {
  databaseUrl?: string | undefined;
  baseUrl?: string | undefined;
  key?: string | undefined;
  deadlineMs?: number | undefined;
  stepTimeoutMs?: number | undefined;
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
 * only after PostgREST has finished the schema-cache reload that the DDL caused. Every
 * helper-owned operation shares one absolute budget (see the file header); the caller's
 * `ddl()` is excluded from it and is not bounded by this helper.
 */
export async function withSchemaCacheSync<T>(
  ddl: () => Promise<T>,
  options: SchemaCacheSyncOptions = {},
): Promise<{ result: T; sync: SchemaCacheSync }> {
  const budget = new SyncBudget(options.deadlineMs, options.stepTimeoutMs);
  const databaseUrl = options.databaseUrl ?? DATABASE_URL;
  const probe = async (step: "probe-before" | "probe-after") => {
    const bound = budget.bound(step);
    const outcome = await probePostgrest({
      baseUrl: options.baseUrl,
      key: options.key,
      timeoutMs: bound,
    });
    if (!outcome.ok) {
      throw new SchemaCacheSyncError(step, budget.elapsed(), bound, describe(outcome));
    }
  };

  await probe("probe-before");
  const before = await pollPooledBackends(budget, databaseUrl);
  if (before.length === 0) {
    throw new SchemaCacheSyncError(
      "probe-before",
      budget.elapsed(),
      null,
      "no pooled PostgREST backend exists after the probe",
    );
  }

  // The caller-owned DDL runs outside the helper's budget.
  budget.pause();
  const result = await ddl();
  budget.resume();

  const committed = Date.now();
  let pooled = before;
  while (pooled.length > 0) {
    const pause = Math.min(POLL_INTERVAL_MS, budget.bound("poll-wait"));
    await new Promise((resolve) => setTimeout(resolve, pause));
    if (budget.remaining() <= 0) {
      throw new SchemaCacheSyncError(
        "reload-wait",
        budget.elapsed(),
        0,
        `PostgREST did not complete a reload (${Date.now() - committed} ms after the DDL; ` +
          `backends still pooled from before the DDL: ${pooled.join(", ")}). Did the DDL ` +
          "commit, and does it fire pgrst_ddl_watch?",
      );
    }
    const now = new Set(await pollPooledBackends(budget, databaseUrl));
    pooled = pooled.filter((pid) => now.has(pid));
  }
  const reloadMs = Date.now() - committed;
  await probe("probe-after");
  // Diagnostic evidence for F2 (timing of every synchronized reload).
  console.warn(`[schema-cache-sync] PostgREST reload completed ${reloadMs} ms after the DDL`);
  return { result, sync: { reloadMs, helperMs: budget.elapsed() } };
}
