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
