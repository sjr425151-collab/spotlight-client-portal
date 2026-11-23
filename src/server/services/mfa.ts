import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { recordSecurityEvent, verifiedActorId } from "@/server/auth/security-events";
import { codeSchema } from "@/server/services/sign-in";

/** TOTP MFA (spec 03 §7). All calls run on the server with the user's own session. */

export async function verifiedTotpFactor(user: SupabaseClient) {
  const { data } = await user.auth.mfa.listFactors();
  return data?.totp.find((factor) => factor.status === "verified") ?? null;
}

export interface Enrollment {
  factorId: string;
  qrCode: string;
  secret: string;
}

export async function startEnrollment(user: SupabaseClient): Promise<Enrollment | null> {
  if (await verifiedTotpFactor(user)) return null;
  // Remove abandoned, unverified factors so the user can start again.
  const { data } = await user.auth.mfa.listFactors();
  for (const factor of data?.all ?? []) {
    if (factor.status !== "verified") await user.auth.mfa.unenroll({ factorId: factor.id });
  }
  const { data: enrolled, error } = await user.auth.mfa.enroll({
    factorType: "totp",
    friendlyName: `Authenticator ${new Date().toISOString().slice(0, 10)}`,
  });
  if (error || !enrolled) return null;
  return { factorId: enrolled.id, qrCode: enrolled.totp.qr_code, secret: enrolled.totp.secret };
}

/** Challenges and verifies a factor; on success the session is upgraded to aal2. */
export async function verifyTotp(
  user: SupabaseClient,
  factorId: string,
  rawCode: string,
  kind: "enroll" | "verify",
): Promise<boolean> {
  const code = codeSchema.safeParse(rawCode);
  if (!code.success) return false;
  const { error } = await user.auth.mfa.challengeAndVerify({ factorId, code: code.data });
  await recordSecurityEvent(
    error ? "mfa.verify_failed" : kind === "enroll" ? "mfa.enrolled" : "mfa.verified",
    { reason: error?.code ?? null },
    await verifiedActorId(user),
  );
  return !error;
}
