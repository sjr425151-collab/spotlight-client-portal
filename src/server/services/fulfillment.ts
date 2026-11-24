import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { env } from "@/config/env";
import { UPLOAD_CATEGORIES, sanitizeFileName, type UploadCategory } from "@/domain/uploads";
import { observeLiveSite } from "@/server/publication/verifier";
import {
  runUploadPipeline,
  scanStoredUpload,
  type PipelineOutcome,
} from "@/server/uploads/pipeline";
import { scannerFor } from "@/server/uploads/scanner";
import { createAdminClient } from "@/server/supabase/admin";

/**
 * WP-C services (05, 06). Each call goes through the user-scoped client, so the database
 * definer function re-authorizes the caller (03 §10). The secret-key client is used only
 * for the upload pipeline and the live verifier, after the database has authorized the
 * caller, and only for the service-role functions that record server observations.
 */

export type Result = { ok: true; data: Record<string, unknown> } | { ok: false; error: string };

/** Calls a WP-C RPC with the user's own client. Unknown failures read as "unavailable". */
export async function callRpc(
  user: SupabaseClient,
  fn: string,
  args: Record<string, unknown>,
): Promise<Result> {
  const { data, error } = await user.rpc(fn, args);
  const result = data as ({ ok?: boolean; error?: string } & Record<string, unknown>) | null;
  if (error || !result) return { ok: false, error: "unavailable" };
  return result.ok
    ? { ok: true, data: result }
    : { ok: false, error: result.error ?? "unavailable" };
}

export function isUploadCategory(value: string): value is UploadCategory {
  return (UPLOAD_CATEGORIES as readonly string[]).includes(value);
}

/**
 * Accepts one file: the database reserves quota and authorizes the caller first, then the
 * server pipeline quarantines, validates, scans, and (only if clean) releases it.
 */
export async function acceptUpload(
  user: SupabaseClient,
  projectId: string,
  category: UploadCategory,
  file: File,
  replacesAssetId: string | null,
): Promise<{ ok: true; outcome: PipelineOutcome } | { ok: false; error: string }> {
  const requested = await callRpc(user, "request_upload", {
    p_project_id: projectId,
    p_category: category,
    p_mime: file.type || "application/octet-stream",
    p_bytes: file.size,
    p_original_name: sanitizeFileName(file.name),
    p_replaces_asset_id: replacesAssetId,
  });
  if (!requested.ok) return requested;
  const bytes = new Uint8Array(await file.arrayBuffer());
  const outcome = await runUploadPipeline(
    await createAdminClient(),
    {
      uploadId: String(requested.data.upload_id),
      projectId,
      category,
      declaredMime: file.type,
      quarantinePath: String(requested.data.quarantine_path),
    },
    bytes,
    scannerFor(env.APP_ENV),
  );
  return { ok: true, outcome };
}

/**
 * Live verification (06 §9). The caller's staff role and the deployment are re-checked by
 * the database, which compares the served build with the authorized release.
 */
export async function verifyLiveDeployment(
  user: SupabaseClient,
  deploymentId: string,
  verifiedStaffUserId: string,
): Promise<Result> {
  const { data: deployment } = await user
    .from("publication_deployments")
    .select("id, production_url, outcome")
    .eq("id", deploymentId)
    .maybeSingle();
  if (!deployment || deployment.outcome !== "succeeded" || !deployment.production_url) {
    return { ok: false, error: "not_found" };
  }
  const observed = await observeLiveSite(deployment.production_url);
  return callRpc(await createAdminClient(), "record_live_verification", {
    p_deployment_id: deploymentId,
    p_requested_by: verifiedStaffUserId,
    p_served_build_id: observed.servedBuildId,
    p_http_ok: observed.httpOk,
    p_tls_ok: observed.tlsOk,
    p_key_pages_ok: observed.keyPagesOk,
    p_forms_ok: observed.formsOk,
  });
}

/**
 * Retries the scan of a quarantined upload (05 §5.4 item 8). The staff caller is
 * authorized by reading the upload through RLS; the database refuses the new attempt while
 * backing off or after the last allowed attempt.
 */
export async function retryUploadScan(user: SupabaseClient, uploadId: string): Promise<Result> {
  const { data: upload } = await user
    .from("asset_uploads")
    .select("id, project_id, category, declared_mime, quarantine_path, status")
    .eq("id", uploadId)
    .maybeSingle();
  if (!upload || upload.status !== "quarantined" || !isUploadCategory(String(upload.category))) {
    return { ok: false, error: "not_found" };
  }
  const outcome = await scanStoredUpload(
    await createAdminClient(),
    {
      uploadId: upload.id,
      projectId: upload.project_id,
      category: upload.category,
      declaredMime: upload.declared_mime,
      quarantinePath: upload.quarantine_path,
    },
    scannerFor(env.APP_ENV),
  );
  return { ok: true, data: { outcome } };
}
