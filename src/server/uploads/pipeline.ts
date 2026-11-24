import "server-only";

import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";

import { processRasterImage } from "@/domain/image-safety";
import { sanitizeSvg } from "@/domain/svg-sanitize";
import { validateContent, type UploadCategory } from "@/domain/uploads";

import type { MalwareScanner } from "./scanner";

/**
 * Upload pipeline (WP-C; spec 05 §5.3). Runs on the server after the database has
 * reserved quota and authorized the uploader (`request_upload`). Every step is recorded by
 * a service-role-only database function, which re-checks the state machine:
 *
 *   uploading -> quarantined -> scanning -> processing -> available, or rejected
 *
 * Bytes are written only to the project's quarantine path. The served copy (sanitized or
 * metadata-stripped) is written to the released path only after the database has recorded
 * a clean scan of the exact stored bytes; if the database then refuses the release, the
 * copy is removed. Nothing here touches payment state.
 */

const BUCKET = "project-assets";

export interface PipelineUpload {
  readonly uploadId: string;
  readonly projectId: string;
  readonly category: UploadCategory;
  readonly declaredMime: string;
  readonly quarantinePath: string;
}

export type PipelineOutcome = "available" | "rejected" | "quarantined" | "held" | "failed_upload";

type Rpc = { ok?: boolean; status?: string; error?: string; held?: string };

async function rpc(admin: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<Rpc> {
  const { data, error } = await admin.rpc(fn, args);
  if (error || !data) return { ok: false, error: "unavailable" };
  return data as Rpc;
}

const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

/** The copy that may be served, or a rejection code. Videos and documents pass unchanged. */
export function servedCopy(
  mime: string,
  bytes: Uint8Array,
): { ok: true; bytes: Uint8Array } | { ok: false; code: string; hold?: boolean } {
  if (mime === "image/svg+xml") {
    const result = sanitizeSvg(new TextDecoder("utf-8").decode(bytes));
    return result.ok
      ? { ok: true, bytes: new TextEncoder().encode(result.svg) }
      : { ok: false, code: result.code };
  }
  if (mime === "image/heic") return { ok: false, code: "heic_conversion_unavailable", hold: true };
  if (mime === "image/png" || mime === "image/jpeg" || mime === "image/webp") {
    const result = processRasterImage(mime, bytes);
    return result.ok ? { ok: true, bytes: result.bytes } : { ok: false, code: result.code };
  }
  return { ok: true, bytes };
}

export async function runUploadPipeline(
  admin: SupabaseClient,
  upload: PipelineUpload,
  bytes: Uint8Array,
  scanner: MalwareScanner | null,
): Promise<PipelineOutcome> {
  // 1. Store in quarantine (served as opaque bytes, never as active content).
  const stored = await admin.storage.from(BUCKET).upload(upload.quarantinePath, bytes, {
    contentType: "application/octet-stream",
    upsert: false,
  });
  if (stored.error) {
    await rpc(admin, "fail_upload", { p_upload_id: upload.uploadId, p_code: "storage_error" });
    return "failed_upload";
  }
  const hash = sha256(bytes);
  const completed = await rpc(admin, "complete_upload", {
    p_upload_id: upload.uploadId,
    p_size_bytes: bytes.length,
    p_sha256: hash,
  });
  if (completed.status !== "quarantined") return "failed_upload";

  // 2. Content validation (magic bytes, polyglots, executables).
  const content = validateContent(upload.category, upload.declaredMime, bytes);
  const checked = await rpc(admin, "record_content_check", {
    p_upload_id: upload.uploadId,
    p_passed: content.ok,
    p_detected_mime: content.ok ? content.detectedMime : null,
    p_code: content.ok ? null : content.code,
  });
  if (!content.ok || checked.status === "rejected") return "rejected";
  if (checked.status !== "scanning") return "quarantined";

  // 3. Malware scan. Without a scanner (DEP-07) the file stays in quarantine.
  if (!scanner) {
    await rpc(admin, "record_scan_result", {
      p_upload_id: upload.uploadId,
      p_scanner: "unavailable",
      p_engine_version: "none",
      p_verdict: "error",
      p_scanned_sha256: hash,
    });
    return "quarantined";
  }
  let verdict;
  try {
    verdict = await scanner.scan(bytes);
  } catch {
    verdict = { verdict: "error" as const, engineVersion: "unknown" };
  }
  const scanned = await rpc(admin, "record_scan_result", {
    p_upload_id: upload.uploadId,
    p_scanner: scanner.id,
    p_engine_version: verdict.engineVersion,
    p_verdict: verdict.verdict,
    p_scanned_sha256: hash,
    p_signature: verdict.signature ?? null,
  });
  if (scanned.status === "rejected") return "rejected";
  if (scanned.status !== "processing") return "quarantined";

  // 4. Processing: the served copy only.
  const copy = servedCopy(content.detectedMime, bytes);
  if (!copy.ok) {
    await rpc(admin, "record_processing_outcome", {
      p_upload_id: upload.uploadId,
      p_outcome: copy.hold ? "held" : "rejected",
      p_note: copy.code,
    });
    return copy.hold ? "held" : "rejected";
  }

  // 5. Release: write the served copy, then let the database confirm the clean scan.
  const releasedPath = `${upload.projectId}/assets/${upload.uploadId}`;
  const written = await admin.storage
    .from(BUCKET)
    .upload(releasedPath, copy.bytes, { contentType: content.detectedMime, upsert: false });
  if (written.error) return "held";
  const released = await rpc(admin, "release_upload", {
    p_upload_id: upload.uploadId,
    p_released_sha256: sha256(copy.bytes),
    p_released_bytes: copy.bytes.length,
  });
  if (released.status !== "available") {
    await admin.storage.from(BUCKET).remove([releasedPath]);
    return "quarantined";
  }
  return "available";
}
