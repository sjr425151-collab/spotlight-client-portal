import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Calls a PostgREST RPC and returns its `data`. A PostgREST `error` (a transport, schema
 * cache, permission, or SQL error) is never silently read as an empty result: it fails the
 * calling test with the function name and the complete error (F2, CURRENT-STATE §7).
 */
export async function callRpc<T = unknown>(
  client: SupabaseClient,
  fn: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error, status } = await client.rpc(fn, args);
  if (error) {
    throw new Error(
      `rpc ${fn} failed (HTTP ${status}): ${JSON.stringify({
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      })}`,
    );
  }
  return data as T;
}

type PostgrestResult = {
  data: unknown;
  error: { code?: string; message: string; details?: string; hint?: string } | null;
  status: number;
};

/**
 * Awaits a non-RPC PostgREST read (a `select` query) and returns its `data`. As with
 * `callRpc`, a PostgREST `error` fails the calling test with the read's label and the
 * complete error instead of being read as missing data (AUTH-008 I-2, WP-C O-1). A read that
 * returns no data at all also fails: every caller expects rows.
 */
export async function selectOk<Q extends PromiseLike<PostgrestResult>>(
  label: string,
  query: Q,
): Promise<NonNullable<Awaited<Q>["data"]>> {
  const { data, error, status } = await query;
  if (data === null && !error) throw new Error(`select ${label} returned no data (HTTP ${status})`);
  if (error) {
    throw new Error(
      `select ${label} failed (HTTP ${status}): ${JSON.stringify({
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      })}`,
    );
  }
  return data as NonNullable<Awaited<Q>["data"]>;
}
