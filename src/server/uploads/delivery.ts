import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Server-mediated delivery of released assets (05 §4; PR #19 review H1).
 *
 * No user JWT can read, list, or sign a released object (storage policy
 * `project_assets_released_server_read_only`), so the browser never receives a storage URL.
 * For every request:
 *   1. the database authorizes the caller with their own session and audits the access
 *      (`record_asset_access`: project access, live session, staff at aal2, and the upload
 *      currently `available`);
 *   2. only then does the server read the object with the secret key;
 *   3. availability is checked again after the read, so a revocation that committed while the
 *      object was being read is honoured and nothing is served;
 *   4. the response is private and never stored by a shared cache.
 * Limitation: a response already being transferred when a revocation commits is not
 * recalled; every request after the commit is refused.
 */

const BUCKET = "project-assets";

/** Headers for a private asset response: never cached by a shared cache, never rendered inline. */
export function assetResponseHeaders(mime: string, name: string): Record<string, string> {
  const safeName = name.replace(/[^\w.-]+/g, "_").slice(0, 200) || "download";
  return {
    "Content-Type": mime,
    "Content-Disposition": `attachment; filename="${safeName}"`,
    "X-Content-Type-Options": "nosniff",
    "Content-Security-Policy": "default-src 'none'; sandbox",
    "Cache-Control": "private, no-store, max-age=0",
    Pragma: "no-cache",
    Vary: "Cookie",
    "Referrer-Policy": "no-referrer",
  };
}

export type Delivery =
  | { ok: true; body: Blob; headers: Record<string, string> }
  | { ok: false; error: "not_found" | "not_available" | "unavailable" };

export async function deliverAsset(
  user: SupabaseClient,
  admin: SupabaseClient,
  projectId: string,
  uploadId: string,
): Promise<Delivery> {
  const { data, error } = await user.rpc("record_asset_access", { p_upload_id: uploadId });
  const access = data as {
    ok?: boolean;
    error?: string;
    released_path?: string;
    mime?: string;
    name?: string;
  } | null;
  if (error || !access?.ok) {
    return { ok: false, error: access?.error === "not_available" ? "not_available" : "not_found" };
  }
  const path = String(access.released_path ?? "");
  if (path !== `${projectId}/assets/${uploadId}`) return { ok: false, error: "not_found" };

  const read = await admin.storage.from(BUCKET).download(path);
  if (read.error || !read.data) return { ok: false, error: "unavailable" };

  // Re-check after the read (step 3), with the caller's own session.
  const { data: current } = await user
    .from("asset_uploads")
    .select("status")
    .eq("id", uploadId)
    .maybeSingle();
  if (current?.status !== "available") return { ok: false, error: "not_available" };

  return {
    ok: true,
    body: read.data,
    headers: assetResponseHeaders(String(access.mime), String(access.name ?? "")),
  };
}
