import "server-only";

import { createAdminClient } from "@/server/supabase/admin";

/**
 * Server-side fixed-window rate limits (spec 03 §17). Fails closed: if the limiter is
 * unavailable, the request is treated as limited.
 */
export async function consumeRateLimit(bucket: string, limit: number, windowSeconds: number) {
  const admin = await createAdminClient();
  const { data, error } = await admin.rpc("consume_rate_limit", {
    p_bucket: bucket,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  return !error && data === true;
}

/**
 * Spec 03 §17 values: OTP requests per email 5/h and per IP 20/h. The spec requires a
 * per-IP limit for code verification and invitation attempts without giving a number;
 * the values marked "implementation value" are flagged for Owner confirmation (03A S-08).
 */
export const LIMITS = {
  otpPerEmail: { limit: 5, windowSeconds: 3600 },
  otpPerIp: { limit: 20, windowSeconds: 3600 },
  verifyPerEmail: { limit: 10, windowSeconds: 3600 }, // implementation value
  verifyPerIp: { limit: 30, windowSeconds: 3600 }, // implementation value
  invitationLinkPerIp: { limit: 30, windowSeconds: 3600 }, // implementation value
} as const;
