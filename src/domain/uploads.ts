/**
 * Upload rules and content validation (WP-C; spec 05 §5). Pure TypeScript.
 *
 * The per-category limits mirror `private.upload_max_bytes` in
 * `supabase/migrations/20261124140000_wpc_intake_uploads.sql`; `tests/unit/wpc-uploads.test.ts`
 * checks that they agree. Sizes use decimal megabytes (1 MB = 1,000,000 bytes), the stricter
 * reading, approved in OI-79 item 1 (05 §5.4). The database is the authority; this module rejects early and validates
 * the actual bytes, which the database never sees.
 */

export const UPLOAD_CATEGORIES = [
  "logo",
  "photo",
  "brand_guidelines",
  "business_document",
  "video",
  "other",
] as const;
export type UploadCategory = (typeof UPLOAD_CATEGORIES)[number];

export const UPLOAD_STATUSES = [
  "uploading",
  "failed_upload",
  "quarantined",
  "scanning",
  "processing",
  "available",
  "rejected",
] as const;
export type UploadStatus = (typeof UPLOAD_STATUSES)[number];

const MB = 1_000_000;
export const DOCX_MIME = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

/** 05 §5.2. `other` has no fixed rule: it needs an approved exception naming the type. */
export const CATEGORY_RULES: Record<
  Exclude<UploadCategory, "other">,
  { readonly mimes: readonly string[]; readonly maxBytes: number; readonly label: string }
> = {
  logo: {
    mimes: ["image/png", "image/jpeg", "image/webp", "image/svg+xml"],
    maxBytes: 15 * MB,
    label: "Logo",
  },
  photo: {
    mimes: ["image/jpeg", "image/png", "image/webp", "image/heic"],
    maxBytes: 25 * MB,
    label: "Photo",
  },
  brand_guidelines: { mimes: ["application/pdf"], maxBytes: 25 * MB, label: "Brand guidelines" },
  business_document: {
    mimes: ["application/pdf", DOCX_MIME],
    maxBytes: 20 * MB,
    label: "Business document",
  },
  video: { mimes: ["video/mp4", "video/quicktime"], maxBytes: 250 * MB, label: "Video" },
};

/** 05 §5.1. */
export const QUOTA_FILES = 100;
export const QUOTA_BYTES = 2_000 * MB;
/** Absolute ceiling for any upload, including approved exceptions. */
export const MAX_UPLOAD_BYTES = 250 * MB;

export function maxBytesFor(category: UploadCategory, mime: string): number | null {
  if (category === "other") return null;
  const rule = CATEGORY_RULES[category];
  return rule.mimes.includes(mime) ? rule.maxBytes : null;
}

/** File names are stored for display only and never used as storage paths. */
export function sanitizeFileName(name: string): string {
  const cleaned = name
    .normalize("NFC")
    .replace(/[\\/\p{Cc}]/gu, "_")
    .trim();
  return cleaned.slice(0, 200) || "upload";
}

// ---------------------------------------------------------------------------
// Content validation (05 §5.3 rule 1): actual bytes, not the extension or declared MIME.
// ---------------------------------------------------------------------------

export type ContentCheck =
  | { readonly ok: true; readonly detectedMime: string }
  | { readonly ok: false; readonly code: ContentRejection };

export type ContentRejection =
  "empty_file" | "type_mismatch" | "unrecognized_type" | "polyglot" | "executable" | "svg_invalid";

const startsWith = (bytes: Uint8Array, signature: readonly number[], offset = 0) =>
  bytes.length >= offset + signature.length && signature.every((b, i) => bytes[offset + i] === b);

const ascii = (bytes: Uint8Array, start: number, length: number) =>
  String.fromCharCode(...bytes.subarray(start, start + length));

/** Identifies a file from its leading bytes. Returns null when unknown. */
export function sniffMime(bytes: Uint8Array): string | null {
  if (startsWith(bytes, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "image/png";
  if (startsWith(bytes, [0xff, 0xd8, 0xff])) return "image/jpeg";
  if (ascii(bytes, 0, 4) === "RIFF" && ascii(bytes, 8, 4) === "WEBP") return "image/webp";
  if (ascii(bytes, 0, 5) === "%PDF-") return "application/pdf";
  if (startsWith(bytes, [0x50, 0x4b, 0x03, 0x04])) return "application/zip";
  if (ascii(bytes, 4, 4) === "ftyp") {
    const brand = ascii(bytes, 8, 4);
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) return "image/heic";
    if (brand === "qt  ") return "video/quicktime";
    return "video/mp4";
  }
  const head = new TextDecoder("utf-8", { fatal: false })
    .decode(bytes.subarray(0, 1024))
    .replace(/^﻿/, "")
    .trimStart();
  if (/^(<\?xml[^>]*>\s*)?(<!--[\s\S]*?-->\s*)*(<!DOCTYPE svg[^>]*>\s*)?<svg[\s>]/i.test(head)) {
    return "image/svg+xml";
  }
  return null;
}

/** Executable formats that are never accepted, whatever the declared type (T-UP-02). */
function isExecutable(bytes: Uint8Array): boolean {
  return (
    startsWith(bytes, [0x4d, 0x5a]) || // PE / DOS (MZ)
    startsWith(bytes, [0x7f, 0x45, 0x4c, 0x46]) || // ELF
    startsWith(bytes, [0xcf, 0xfa, 0xed, 0xfe]) || // Mach-O 64
    startsWith(bytes, [0xce, 0xfa, 0xed, 0xfe]) || // Mach-O 32
    startsWith(bytes, [0xca, 0xfe, 0xba, 0xbe]) || // Mach-O fat / Java class
    ascii(bytes, 0, 2) === "#!" // scripts
  );
}

const ACTIVE_MARKERS = [/<script/i, /<\?php/i, /<html/i, /<iframe/i, /javascript:/i];

function containsSequence(bytes: Uint8Array, sequence: readonly number[], from = 0): boolean {
  outer: for (let i = from; i <= bytes.length - sequence.length; i++) {
    for (let j = 0; j < sequence.length; j++) if (bytes[i + j] !== sequence[j]) continue outer;
    return true;
  }
  return false;
}

/**
 * Polyglot heuristics for binary images: an embedded archive or PDF, or active markup, in
 * a file that claims to be a raster image (T-UP-02).
 */
function looksPolyglot(bytes: Uint8Array, mime: string): boolean {
  if (!mime.startsWith("image/") || mime === "image/svg+xml") return false;
  if (containsSequence(bytes, [0x50, 0x4b, 0x03, 0x04], 4)) return true; // ZIP local header
  if (containsSequence(bytes, [0x25, 0x50, 0x44, 0x46, 0x2d], 4)) return true; // %PDF-
  const text = new TextDecoder("latin1").decode(bytes);
  return ACTIVE_MARKERS.some((marker) => marker.test(text));
}

/** DOCX is a ZIP whose first entry set includes `word/document.xml` and `[Content_Types].xml`. */
function isDocx(bytes: Uint8Array): boolean {
  const text = new TextDecoder("latin1").decode(bytes.subarray(0, Math.min(bytes.length, 65536)));
  return text.includes("[Content_Types].xml") && text.includes("word/");
}

export function validateContent(
  category: UploadCategory,
  declaredMime: string,
  bytes: Uint8Array,
): ContentCheck {
  if (bytes.length === 0) return { ok: false, code: "empty_file" };
  if (isExecutable(bytes)) return { ok: false, code: "executable" };
  const sniffed = sniffMime(bytes);
  if (category === "other") {
    // Approved exception types are not content-typed here; they are still scanned.
    return { ok: true, detectedMime: sniffed ?? "application/octet-stream" };
  }
  if (!sniffed) return { ok: false, code: "unrecognized_type" };
  const detected = sniffed === "application/zip" && isDocx(bytes) ? DOCX_MIME : sniffed;
  if (detected !== declaredMime) return { ok: false, code: "type_mismatch" };
  if (looksPolyglot(bytes, detected)) return { ok: false, code: "polyglot" };
  return { ok: true, detectedMime: detected };
}

/** EICAR anti-malware test string (public test file), used by the mocked scanner. */
export const EICAR_SIGNATURE =
  "X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";

/** User-facing guidance for a rejected upload (OI-31: actionable re-upload guidance). */
export const REJECTION_GUIDANCE: Record<string, string> = {
  malware_detected:
    "This file failed the security scan and was blocked. Upload a clean copy from the original source.",
  type_mismatch:
    "The file's contents do not match its type. Export it again in one of the allowed formats and re-upload.",
  unrecognized_type: "We could not recognize this file type. Use one of the allowed formats.",
  polyglot:
    "This file contains embedded content that is not allowed. Export a plain copy and re-upload.",
  executable: "Programs and scripts cannot be uploaded.",
  empty_file: "The file was empty. Choose the file again and re-upload.",
  svg_invalid: "This SVG could not be read safely. Export it again, or upload a PNG instead.",
  image_too_large: "The image dimensions are too large. Resize it below 12,000 pixels per side.",
  processing_failed: "We could not process this file. Try exporting it again, or contact us.",
  content_invalid: "This file could not be validated. Export it again and re-upload.",
};
