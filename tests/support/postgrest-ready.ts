import { existsSync } from "node:fs";

/**
 * PostgREST readiness for the LOCAL Supabase stack (AUTH-008 I-1 and Amendment 1; F2,
 * CURRENT-STATE §7, §14).
 *
 * F2 cause (reproduced, CURRENT-STATE §14): `supabase db reset` restarts Postgres while
 * PostgREST's pool still holds connections opened by earlier traffic. When PostgREST's
 * listener reconnects, its configuration and schema-cache queries run on those dead pooled
 * connections and fail, so PostgREST enters its reconnect backoff (1 s, 2 s, 4 s, ...) and
 * answers every request with `503 PGRST001 "no connection to the server"` until it has
 * reconnected and reloaded. A suite started within those seconds of a reset fails on its
 * first PostgREST requests.
 *
 * `waitForPostgrestReady` is a readiness gate, not a retry of a test operation (Owner
 * decision WPI-P1, AUTH-008 Amendment 1): it runs once per test file, before any test, and
 * returns only after PostgREST has answered a read-only request successfully three times in
 * a row. The gate has a real overall deadline: every request is bounded by the smaller of
 * the remaining deadline and an individual request timeout, and is aborted (`AbortSignal`)
 * when it stalls. Every failed attempt (HTTP status and PGRST code, timeout, or network
 * error) is recorded with its elapsed time. At the deadline the gate throws with those
 * diagnostics (fail closed); it never lets a test run before readiness. It is never used
 * around a test, a financial operation, or an application RPC.
 */

if (!process.env.SUPABASE_SECRET_KEY && existsSync(".env.local")) {
  process.loadEnvFile(".env.local");
}

const DEFAULT_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321";
const DEFAULT_KEY = process.env.SUPABASE_SECRET_KEY ?? "";

export const READY_DEFAULTS = {
  /** Overall deadline for the whole gate. */
  deadlineMs: 60_000,
  /** Upper bound for one request (further bounded by the remaining deadline). */
  requestTimeoutMs: 5_000,
  /** Pause after a failed attempt (bounded by the remaining deadline). */
  intervalMs: 100,
  /** Consecutive successful requests required. */
  consecutive: 3,
} as const;

function assertLocal(baseUrl: string) {
  if (!["127.0.0.1", "localhost"].includes(new URL(baseUrl).hostname)) {
    throw new Error("PostgREST readiness checks may only run against a local Supabase stack");
  }
}
assertLocal(DEFAULT_URL);

export type ProbeOutcome = {
  ok: boolean;
  /** `ok`, `http` (non-200 status), `timeout` (aborted when stalled), or `network`. */
  kind: "ok" | "http" | "timeout" | "network";
  status: number | null;
  /** The PostgREST error code in the response body, if any (for example PGRST001). */
  code: string | null;
  detail: string;
  durationMs: number;
};

export type ProbeOptions = {
  baseUrl?: string | undefined;
  key?: string | undefined;
  timeoutMs?: number | undefined;
};

/**
 * One read-only request through PostgREST that returns no rows (the local stack's secret
 * key), bounded by `timeoutMs`: the request, including reading the body, is aborted when it
 * stalls. Never throws; the outcome says what happened.
 */
export async function probePostgrest(options: ProbeOptions = {}): Promise<ProbeOutcome> {
  const baseUrl = options.baseUrl ?? DEFAULT_URL;
  const key = options.key ?? DEFAULT_KEY;
  const timeoutMs = Math.max(1, Math.floor(options.timeoutMs ?? READY_DEFAULTS.requestTimeoutMs));
  assertLocal(baseUrl);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const started = Date.now();
  try {
    const response = await fetch(`${baseUrl}/rest/v1/projects?select=id&limit=0`, {
      headers: { apikey: key, Authorization: `Bearer ${key}` },
      signal: controller.signal,
    });
    const body = (await response.text()).slice(0, 300);
    const durationMs = Date.now() - started;
    if (response.status === 200) {
      return { ok: true, kind: "ok", status: 200, code: null, detail: "", durationMs };
    }
    return {
      ok: false,
      kind: "http",
      status: response.status,
      code: body.match(/PGRST\d{3}/)?.[0] ?? null,
      detail: body.slice(0, 120),
      durationMs,
    };
  } catch (error) {
    const durationMs = Date.now() - started;
    if (controller.signal.aborted) {
      return {
        ok: false,
        kind: "timeout",
        status: null,
        code: null,
        detail: `aborted after ${timeoutMs} ms`,
        durationMs,
      };
    }
    const cause = (error as Error & { cause?: { code?: string; message?: string } }).cause;
    return {
      ok: false,
      kind: "network",
      status: null,
      code: null,
      detail: String(cause?.code ?? cause?.message ?? (error as Error).message),
      durationMs,
    };
  } finally {
    clearTimeout(timer);
  }
}

export type ReadinessFailure = {
  attempt: number;
  /** Milliseconds since the gate started when the attempt ended. */
  atMs: number;
  kind: ProbeOutcome["kind"];
  status: number | null;
  code: string | null;
  detail: string;
  durationMs: number;
};

export type PostgrestReadiness = {
  waitedMs: number;
  attempts: number;
  /** Failure counts by kind, status, and code, for example `{"http 503 PGRST001": 2}`. */
  failureCounts: Record<string, number>;
  /** Every failed attempt, in order (the last 50 are kept). */
  failures: ReadinessFailure[];
};

export type ReadyOptions = ProbeOptions & {
  deadlineMs?: number;
  requestTimeoutMs?: number;
  intervalMs?: number;
  consecutive?: number;
};

const failureKey = (f: { kind: string; status: number | null; code: string | null }) =>
  [f.kind, f.status ?? "", f.code ?? ""].filter((part) => part !== "").join(" ");

export class PostgrestNotReadyError extends Error {
  constructor(
    message: string,
    readonly readiness: PostgrestReadiness,
  ) {
    super(message);
    this.name = "PostgrestNotReadyError";
  }
}

export async function waitForPostgrestReady(
  options: ReadyOptions = {},
): Promise<PostgrestReadiness> {
  const deadlineMs = options.deadlineMs ?? READY_DEFAULTS.deadlineMs;
  const requestTimeoutMs = options.requestTimeoutMs ?? READY_DEFAULTS.requestTimeoutMs;
  const intervalMs = options.intervalMs ?? READY_DEFAULTS.intervalMs;
  const required = options.consecutive ?? READY_DEFAULTS.consecutive;
  const started = Date.now();
  const elapsed = () => Date.now() - started;
  const readiness: PostgrestReadiness = {
    waitedMs: 0,
    attempts: 0,
    failureCounts: {},
    failures: [],
  };
  const expire = (): never => {
    readiness.waitedMs = elapsed();
    throw new PostgrestNotReadyError(
      `PostgREST was not ready within the ${deadlineMs} ms deadline ` +
        `(${readiness.attempts} attempts, ${readiness.waitedMs} ms elapsed, ` +
        `${required} consecutive successes required): ` +
        `failures ${JSON.stringify(readiness.failureCounts)}; ` +
        `last failures ${JSON.stringify(readiness.failures.slice(-5))}`,
      readiness,
    );
  };

  let consecutive = 0;
  while (consecutive < required) {
    const remaining = deadlineMs - elapsed();
    if (remaining <= 0) expire();
    readiness.attempts++;
    const outcome = await probePostgrest({
      baseUrl: options.baseUrl,
      key: options.key,
      timeoutMs: Math.min(remaining, requestTimeoutMs),
    });
    if (outcome.ok) {
      consecutive++;
      continue;
    }
    consecutive = 0;
    const failure: ReadinessFailure = {
      attempt: readiness.attempts,
      atMs: elapsed(),
      kind: outcome.kind,
      status: outcome.status,
      code: outcome.code,
      detail: outcome.detail,
      durationMs: outcome.durationMs,
    };
    const key = failureKey(failure);
    readiness.failureCounts[key] = (readiness.failureCounts[key] ?? 0) + 1;
    readiness.failures.push(failure);
    if (readiness.failures.length > 50) readiness.failures.shift();
    const pause = Math.min(intervalMs, deadlineMs - elapsed());
    if (pause <= 0) expire();
    await new Promise((resolve) => setTimeout(resolve, pause));
  }
  readiness.waitedMs = elapsed();
  if (readiness.failures.length > 0) {
    // Diagnostic evidence for F2: the gate had to wait for PostgREST to reconnect.
    console.warn(
      `[postgrest-ready] waited ${readiness.waitedMs} ms (${readiness.attempts} attempts): ` +
        JSON.stringify(readiness.failureCounts),
    );
  }
  return readiness;
}
