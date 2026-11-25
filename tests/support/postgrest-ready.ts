import { existsSync } from "node:fs";

/**
 * PostgREST readiness for the LOCAL Supabase stack (AUTH-008 I-1; F2, CURRENT-STATE §7).
 *
 * F2 cause (reproduced, CURRENT-STATE §14): `supabase db reset` restarts Postgres while
 * PostgREST's pool still holds connections opened by earlier traffic. When PostgREST's
 * listener reconnects, its configuration and schema-cache queries run on those dead pooled
 * connections and fail, so PostgREST enters its reconnect backoff (1 s, 2 s, 4 s, ...) and
 * answers every request with `503 PGRST001 "no connection to the server"` until it has
 * reconnected and reloaded. A suite started within those seconds of a reset fails on its
 * first PostgREST requests.
 *
 * `waitForPostgrestReady` is a readiness gate, not a retry of a test operation: it runs once
 * per test file, before any test, and returns only after PostgREST has answered a read-only
 * request successfully three times in a row. Any wait is reported with the statuses seen,
 * and the gate fails the run (with diagnostics) if PostgREST is not ready within 60 s.
 */

if (!process.env.SUPABASE_SECRET_KEY && existsSync(".env.local")) {
  process.loadEnvFile(".env.local");
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321";
const SECRET_KEY = process.env.SUPABASE_SECRET_KEY ?? "";
const READY_TIMEOUT_MS = 60_000;
const CONSECUTIVE_OK = 3;

if (!["127.0.0.1", "localhost"].includes(new URL(SUPABASE_URL).hostname)) {
  throw new Error("PostgREST readiness checks may only run against a local Supabase stack");
}

/** A read-only request through PostgREST that returns no rows (the local stack's secret key). */
export async function probePostgrest(): Promise<{ status: number; body: string }> {
  try {
    const response = await fetch(`${SUPABASE_URL}/rest/v1/projects?select=id&limit=0`, {
      headers: { apikey: SECRET_KEY, Authorization: `Bearer ${SECRET_KEY}` },
    });
    return { status: response.status, body: (await response.text()).slice(0, 300) };
  } catch (error) {
    return { status: 0, body: String((error as Error).cause ?? error) };
  }
}

export type PostgrestReadiness = { waitedMs: number; failures: Record<string, number> };

export async function waitForPostgrestReady(): Promise<PostgrestReadiness> {
  const started = Date.now();
  const failures: Record<string, number> = {};
  let consecutive = 0;
  while (consecutive < CONSECUTIVE_OK) {
    const { status, body } = await probePostgrest();
    if (status === 200) {
      consecutive++;
      continue;
    }
    consecutive = 0;
    const key = `${status} ${body.match(/PGRST\d{3}/)?.[0] ?? body.slice(0, 80)}`;
    failures[key] = (failures[key] ?? 0) + 1;
    if (Date.now() - started > READY_TIMEOUT_MS) {
      throw new Error(
        `PostgREST was not ready within ${READY_TIMEOUT_MS} ms: ${JSON.stringify(failures)}`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  const readiness = { waitedMs: Date.now() - started, failures };
  if (Object.keys(failures).length > 0) {
    // Diagnostic evidence for F2: the gate had to wait for PostgREST to reconnect.
    console.warn(`[postgrest-ready] waited ${readiness.waitedMs} ms: ${JSON.stringify(failures)}`);
  }
  return readiness;
}
