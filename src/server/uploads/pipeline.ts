import "server-only";

import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";

import { processRasterImage } from "@/domain/image-safety";
import { sanitizeSvg } from "@/domain/svg-sanitize";
import { validateContent, type UploadCategory } from "@/domain/uploads";

import type { MalwareScanner, ScanVerdict } from "./scanner";

/**
 * Upload pipeline (WP-C; spec 05 §5.3, §5.5). Runs on the server after the database has
 * reserved quota and authorized the uploader (`request_upload`). Every step is recorded by
 * a service-role-only database function, which re-checks the state machine:
 *
 *   uploading -> quarantined -> scanning -> processing -> available, or rejected
 *
 * Exact bytes (05 §5.5 rule 5): every hash the database sees is computed here from the
 * object as stored, never from the request body: the quarantine object is read back after
 * upload, read again before processing (and its hash confirmed), and the released object is
 * read back before release. Each scan attempt is named in its result (rule 2); the database
 * decides authority. A malicious verdict for a released file revokes it (rule 3); the
 * released object is then unreadable through the storage policy and deleted here.
 * Nothing here touches payment state.
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

type Rpc = {
  ok?: boolean;
  status?: string;
  error?: string;
  held?: string;
  attempt_id?: string;
  revoked?: boolean;
  released_path?: string;
};

async function rpc(admin: SupabaseClient, fn: string, args: Record<string, unknown>): Promise<Rpc> {
  const { data, error } = await admin.rpc(fn, args);
  if (error || !data) return { ok: false, error: "unavailable" };
  return data as Rpc;
}

export const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

/** Reads a stored object back. Null if it cannot be read. */
async function readStored(admin: SupabaseClient, path: string): Promise<Uint8Array | null> {
  const { data, error } = await admin.storage.from(BUCKET).download(path);
  if (error || !data) return null;
  return new Uint8Array(await data.arrayBuffer());
}

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

/**
 * Records a scan verdict for an attempt. If it revoked a released file, deletes the
 * released object as well (the storage policy already makes it unreadable).
 */
export async function recordScanVerdict(
  admin: SupabaseClient,
  uploadId: string,
  attemptId: string | null,
  scannerId: string,
  verdict: ScanVerdict,
  scannedSha256: string,
): Promise<Rpc> {
  const result = await rpc(admin, "record_scan_result", {
    p_upload_id: uploadId,
    p_attempt_id: attemptId,
    p_scanner: scannerId,
    p_engine_version: verdict.engineVersion,
    p_verdict: verdict.verdict,
    p_scanned_sha256: scannedSha256,
    p_signature: verdict.signature ?? null,
  });
  if (result.revoked && result.released_path) {
    await admin.storage.from(BUCKET).remove([result.released_path]);
  }
  return result;
}

/**
 * Validates, scans, processes, and releases a completed upload from its stored quarantine
 * object. Also the retry path after a failed attempt (05 §5.4 item 8): the database refuses
 * a new attempt while backing off or once the attempts are exhausted.
 */
export async function scanStoredUpload(
  admin: SupabaseClient,
  upload: PipelineUpload,
  scanner: MalwareScanner | null,
): Promise<PipelineOutcome> {
  const stored = await readStored(admin, upload.quarantinePath);
  if (!stored) return "quarantined";
  const storedHash = sha256(stored);

  // Content validation (magic bytes, polyglots, executables); a pass opens a scan attempt.
  const content = validateContent(upload.category, upload.declaredMime, stored);
  const checked = await rpc(admin, "record_content_check", {
    p_upload_id: upload.uploadId,
    p_passed: content.ok,
    p_detected_mime: content.ok ? content.detectedMime : null,
    p_code: content.ok ? null : content.code,
  });
  if (!content.ok || checked.status === "rejected") return "rejected";
  if (checked.status !== "scanning" || !checked.attempt_id) return "quarantined";
  const attemptId = checked.attempt_id;

  // Malware scan. Without a scanner (DEP-07) the attempt fails and the file stays quarantined.
  let verdict: ScanVerdict;
  if (!scanner) {
    verdict = { verdict: "error", engineVersion: "none" };
  } else {
    try {
      verdict = await scanner.scan(stored);
    } catch {
      verdict = { verdict: "error", engineVersion: "unknown" };
    }
  }
  const scanned = await recordScanVerdict(
    admin,
    upload.uploadId,
    attemptId,
    scanner?.id ?? "unavailable",
    verdict,
    storedHash,
  );
  if (scanned.status === "rejected") return "rejected";
  if (scanned.status !== "processing") return "quarantined";

  // Processing re-reads the stored object and confirms its hash before deriving (rule 5).
  const reread = await readStored(admin, upload.quarantinePath);
  if (!reread) return "held";
  const confirmed = await rpc(admin, "confirm_source_hash", {
    p_upload_id: upload.uploadId,
    p_sha256: sha256(reread),
  });
  if (confirmed.status === "rejected") return "rejected";
  if (!confirmed.ok) return "held";
  const copy = servedCopy(content.detectedMime, reread);
  if (!copy.ok) {
    await rpc(admin, "record_processing_outcome", {
      p_upload_id: upload.uploadId,
      p_outcome: copy.hold ? "held" : "rejected",
      p_note: copy.code,
    });
    return copy.hold ? "held" : "rejected";
  }

  // Release: write the served copy, read it back for its hash, then let the database decide.
  const releasedPath = `${upload.projectId}/assets/${upload.uploadId}`;
  const written = await admin.storage
    .from(BUCKET)
    .upload(releasedPath, copy.bytes, { contentType: content.detectedMime, upsert: false });
  if (written.error) return "held";
  const releasedBytes = await readStored(admin, releasedPath);
  const released = releasedBytes
    ? await rpc(admin, "release_upload", {
        p_upload_id: upload.uploadId,
        p_released_sha256: sha256(releasedBytes),
        p_released_bytes: releasedBytes.length,
      })
    : ({ ok: false } as Rpc);
  if (released.status !== "available") {
    await admin.storage.from(BUCKET).remove([releasedPath]);
    return released.error === "malware_detected" ? "rejected" : "quarantined";
  }
  return "available";
}

export async function runUploadPipeline(
  admin: SupabaseClient,
  upload: PipelineUpload,
  bytes: Uint8Array,
  scanner: MalwareScanner | null,
): Promise<PipelineOutcome> {
  // Store in quarantine (served as opaque bytes, never as active content).
  const stored = await admin.storage.from(BUCKET).upload(upload.quarantinePath, bytes, {
    contentType: "application/octet-stream",
    upsert: false,
  });
  if (stored.error) {
    await rpc(admin, "fail_upload", { p_upload_id: upload.uploadId, p_code: "storage_error" });
    return "failed_upload";
  }
  // Size and hash of the object as stored, read back (rule 5).
  const readBack = await readStored(admin, upload.quarantinePath);
  if (!readBack) {
    await rpc(admin, "fail_upload", { p_upload_id: upload.uploadId, p_code: "storage_error" });
    return "failed_upload";
  }
  const completed = await rpc(admin, "complete_upload", {
    p_upload_id: upload.uploadId,
    p_size_bytes: readBack.length,
    p_sha256: sha256(readBack),
  });
  if (completed.status !== "quarantined") return "failed_upload";
  return scanStoredUpload(admin, upload, scanner);
}
