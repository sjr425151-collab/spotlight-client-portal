/**
 * Raster image safety (WP-C; spec 05 §5.3 rule 5). Pure TypeScript, no dependencies.
 *
 * - Dimension and pixel limits are read from the file headers before anything decodes the
 *   image (decompression-bomb protection).
 * - Metadata is stripped from the served copy: JPEG APP1-APP15 and COM segments (EXIF,
 *   including GPS location, XMP, IPTC), PNG ancillary text and EXIF chunks, and WEBP EXIF
 *   and XMP chunks. The original stays in quarantine.
 * Limits are [PROPOSED] values recorded in OI-73: 12,000 pixels per side and 100 megapixels.
 * HEIC conversion needs an image codec, which is not an approved dependency (OI-73); HEIC
 * files therefore stay held in processing and are never served.
 */

export const MAX_IMAGE_SIDE = 12_000;
export const MAX_IMAGE_PIXELS = 100_000_000;

export interface Dimensions {
  readonly width: number;
  readonly height: number;
}

const u16be = (b: Uint8Array, o: number) => ((b[o] ?? 0) << 8) | (b[o + 1] ?? 0);
const u32be = (b: Uint8Array, o: number) =>
  (((b[o] ?? 0) << 24) >>> 0) + ((b[o + 1] ?? 0) << 16) + ((b[o + 2] ?? 0) << 8) + (b[o + 3] ?? 0);
const u24le = (b: Uint8Array, o: number) =>
  (b[o] ?? 0) | ((b[o + 1] ?? 0) << 8) | ((b[o + 2] ?? 0) << 16);
const u14le = (b: Uint8Array, o: number) => ((b[o] ?? 0) | ((b[o + 1] ?? 0) << 8)) & 0x3fff;

function jpegDimensions(b: Uint8Array): Dimensions | null {
  let o = 2;
  while (o + 9 < b.length) {
    if (b[o] !== 0xff) return null;
    const marker = b[o + 1] ?? 0;
    if (marker === 0xd8 || (marker >= 0xd0 && marker <= 0xd7) || marker === 0x01) {
      o += 2;
      continue;
    }
    const length = u16be(b, o + 2);
    // SOF0-SOF15 except DHT (C4), JPG (C8), DAC (CC).
    if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
      return { height: u16be(b, o + 5), width: u16be(b, o + 7) };
    }
    if (length < 2) return null;
    o += 2 + length;
  }
  return null;
}

function webpDimensions(b: Uint8Array): Dimensions | null {
  const chunk = String.fromCharCode(...b.subarray(12, 16));
  if (chunk === "VP8X") return { width: u24le(b, 24) + 1, height: u24le(b, 27) + 1 };
  if (chunk === "VP8 ") return { width: u14le(b, 26), height: u14le(b, 28) };
  if (chunk === "VP8L") {
    const bits = (b[21] ?? 0) | ((b[22] ?? 0) << 8) | ((b[23] ?? 0) << 16) | ((b[24] ?? 0) << 24);
    return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
  }
  return null;
}

export function imageDimensions(mime: string, bytes: Uint8Array): Dimensions | null {
  if (mime === "image/png") {
    if (bytes.length < 24 || String.fromCharCode(...bytes.subarray(12, 16)) !== "IHDR") return null;
    return { width: u32be(bytes, 16), height: u32be(bytes, 20) };
  }
  if (mime === "image/jpeg") return jpegDimensions(bytes);
  if (mime === "image/webp") return webpDimensions(bytes);
  return null;
}

export function withinPixelLimits(d: Dimensions | null): boolean {
  return (
    d !== null &&
    d.width > 0 &&
    d.height > 0 &&
    d.width <= MAX_IMAGE_SIDE &&
    d.height <= MAX_IMAGE_SIDE &&
    d.width * d.height <= MAX_IMAGE_PIXELS
  );
}

/** JPEG: drops APP1-APP15 and COM; keeps APP0 (JFIF) and every image segment. */
function stripJpeg(b: Uint8Array): Uint8Array | null {
  const parts: Uint8Array[] = [b.subarray(0, 2)];
  let o = 2;
  while (o + 4 <= b.length) {
    if (b[o] !== 0xff) return null;
    const marker = b[o + 1] ?? 0;
    if (marker === 0xda) {
      parts.push(b.subarray(o)); // start of scan: the rest is entropy-coded image data
      break;
    }
    const length = u16be(b, o + 2);
    if (length < 2 || o + 2 + length > b.length) return null;
    const drop = (marker >= 0xe1 && marker <= 0xef) || marker === 0xfe;
    if (!drop) parts.push(b.subarray(o, o + 2 + length));
    o += 2 + length;
  }
  return concat(parts);
}

const PNG_DROPPED_CHUNKS = new Set(["eXIf", "tEXt", "zTXt", "iTXt", "tIME"]);

/** PNG: drops EXIF, text, and time chunks; the CRCs of kept chunks are unchanged. */
function stripPng(b: Uint8Array): Uint8Array | null {
  const parts: Uint8Array[] = [b.subarray(0, 8)];
  let o = 8;
  while (o + 12 <= b.length) {
    const length = u32be(b, o);
    const type = String.fromCharCode(...b.subarray(o + 4, o + 8));
    const end = o + 12 + length;
    if (end > b.length) return null;
    if (!PNG_DROPPED_CHUNKS.has(type)) parts.push(b.subarray(o, end));
    o = end;
    if (type === "IEND") break;
  }
  return concat(parts);
}

const u32le = (b: Uint8Array, o: number) =>
  ((b[o] ?? 0) | ((b[o + 1] ?? 0) << 8) | ((b[o + 2] ?? 0) << 16) | ((b[o + 3] ?? 0) << 24)) >>> 0;

/** WEBP: drops the EXIF and XMP chunks, clears their VP8X flags, and fixes the RIFF size. */
function stripWebp(b: Uint8Array): Uint8Array | null {
  const parts: Uint8Array[] = [];
  let o = 12;
  while (o + 8 <= b.length) {
    const type = String.fromCharCode(...b.subarray(o, o + 4));
    const size = u32le(b, o + 4);
    const end = o + 8 + size + (size % 2);
    if (o + 8 + size > b.length) return null;
    if (type !== "EXIF" && type !== "XMP ") {
      const chunk = b.slice(o, Math.min(end, b.length));
      if (type === "VP8X" && chunk.length > 8) chunk[8] = (chunk[8] ?? 0) & ~0x0c;
      parts.push(chunk);
    }
    o = end;
  }
  const body = concat(parts);
  const out = new Uint8Array(12 + body.length);
  out.set(b.subarray(0, 12), 0);
  const riffSize = 4 + body.length;
  out[4] = riffSize & 0xff;
  out[5] = (riffSize >>> 8) & 0xff;
  out[6] = (riffSize >>> 16) & 0xff;
  out[7] = (riffSize >>> 24) & 0xff;
  out.set(body, 12);
  return out;
}

function concat(parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

export type ImageProcessing =
  | { readonly ok: true; readonly bytes: Uint8Array; readonly dimensions: Dimensions }
  | { readonly ok: false; readonly code: "image_too_large" | "processing_failed" };

/** Validates limits and returns the copy to serve (metadata removed where supported). */
export function processRasterImage(mime: string, bytes: Uint8Array): ImageProcessing {
  const dimensions = imageDimensions(mime, bytes);
  if (!dimensions) return { ok: false, code: "processing_failed" };
  if (!withinPixelLimits(dimensions)) return { ok: false, code: "image_too_large" };
  const stripped =
    mime === "image/jpeg"
      ? stripJpeg(bytes)
      : mime === "image/png"
        ? stripPng(bytes)
        : mime === "image/webp"
          ? stripWebp(bytes)
          : null;
  if (!stripped) return { ok: false, code: "processing_failed" };
  return { ok: true, bytes: stripped, dimensions };
}
