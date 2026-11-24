import "server-only";

import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Stripe webhook signature verification on the RAW request body (spec 04 §11 rule 1, §17 #4).
 *
 * Scheme [VERIFY-PROVIDER, DEP-15]: the `Stripe-Signature` header carries `t=<unix seconds>`
 * and one or more `v1=<hex HMAC-SHA256>` entries, where the HMAC is computed with the
 * endpoint's signing secret over `${t}.${rawBody}`. Any matching `v1` passes; other schemes
 * are ignored. Timestamps outside the tolerance are rejected (replay protection on top of
 * the durable `stripe_event_id` deduplication). Comparisons are constant-time.
 *
 * In CI the secret is a test-only value generated for the run (OI-63). Verification against
 * real Stripe-signed events is DEP-15 under AUTH-002 and has NOT been performed.
 */

export const SIGNATURE_TOLERANCE_SECONDS = 300;
const MAX_HEADER_LENGTH = 4096;

export type SignatureFailure =
  "missing_header" | "malformed_header" | "timestamp_out_of_tolerance" | "no_matching_signature";

export type SignatureResult =
  { ok: true; timestamp: number } | { ok: false; reason: SignatureFailure };

export function computeSignature(secret: string, timestamp: number, rawBody: string): string {
  return createHmac("sha256", secret).update(`${timestamp}.${rawBody}`, "utf8").digest("hex");
}

export function verifyStripeSignature(
  rawBody: string,
  header: string | null,
  secret: string,
  nowSeconds: number = Math.floor(Date.now() / 1000),
  toleranceSeconds: number = SIGNATURE_TOLERANCE_SECONDS,
): SignatureResult {
  if (!secret) throw new Error("A webhook signing secret is required");
  if (!header) return { ok: false, reason: "missing_header" };
  if (header.length > MAX_HEADER_LENGTH) return { ok: false, reason: "malformed_header" };

  let timestamp: number | null = null;
  const candidates: string[] = [];
  for (const part of header.split(",")) {
    const index = part.indexOf("=");
    if (index <= 0) continue;
    const key = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    if (key === "t" && /^\d{1,12}$/.test(value)) timestamp = Number(value);
    if (key === "v1" && /^[0-9a-f]{64}$/.test(value)) candidates.push(value);
  }
  if (timestamp === null || candidates.length === 0)
    return { ok: false, reason: "malformed_header" };
  if (Math.abs(nowSeconds - timestamp) > toleranceSeconds) {
    return { ok: false, reason: "timestamp_out_of_tolerance" };
  }

  const expected = Buffer.from(computeSignature(secret, timestamp, rawBody), "hex");
  const matched = candidates.some((candidate) => {
    const provided = Buffer.from(candidate, "hex");
    return provided.length === expected.length && timingSafeEqual(provided, expected);
  });
  return matched ? { ok: true, timestamp } : { ok: false, reason: "no_matching_signature" };
}
