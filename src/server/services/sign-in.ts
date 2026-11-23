import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";

import { consumeRateLimit, LIMITS } from "@/server/auth/rate-limit";
import { emailDomain, recordSecurityEvent } from "@/server/auth/security-events";

/**
 * Invitation-only email OTP sign-in (spec 03 §6.2). Responses never reveal whether an
 * account exists (TM-03): every request gets the same generic answer.
 */
export const emailSchema = z.string().trim().toLowerCase().pipe(z.email().max(254));

export const codeSchema = z
  .string()
  .trim()
  .regex(/^\d{6}$/);

export interface SignInDeps {
  anon: SupabaseClient;
  ip: string;
}

/** Sends a sign-in code to an existing, confirmed user. Always resolves without detail. */
export async function requestSignInCode(deps: SignInDeps, rawEmail: string): Promise<void> {
  const parsed = emailSchema.safeParse(rawEmail);
  if (!parsed.success) return;
  const email = parsed.data;

  const [emailOk, ipOk] = await Promise.all([
    consumeRateLimit(
      `otp:email:${email}`,
      LIMITS.otpPerEmail.limit,
      LIMITS.otpPerEmail.windowSeconds,
    ),
    consumeRateLimit(`otp:ip:${deps.ip}`, LIMITS.otpPerIp.limit, LIMITS.otpPerIp.windowSeconds),
  ]);
  if (!emailOk || !ipOk) {
    await recordSecurityEvent("auth.otp_rate_limited", { email_domain: emailDomain(email) });
    return;
  }

  // shouldCreateUser:false plus disabled sign-up: unknown emails get no code (03A U-03).
  const { error } = await deps.anon.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });
  await recordSecurityEvent("auth.otp_requested", {
    email_domain: emailDomain(email),
    outcome: error ? (error.code ?? "error") : "sent",
  });
}

export type VerifyOutcome = { ok: true } | { ok: false; reason: "invalid" | "rate_limited" };

/** Verifies a six-digit code on the user client, which then holds the new session. */
export async function verifySignInCode(
  user: SupabaseClient,
  rawEmail: string,
  rawCode: string,
  ip: string,
): Promise<VerifyOutcome> {
  const email = emailSchema.safeParse(rawEmail);
  const code = codeSchema.safeParse(rawCode);
  if (!email.success || !code.success) return { ok: false, reason: "invalid" };

  const [emailOk, ipOk] = await Promise.all([
    consumeRateLimit(
      `verify:email:${email.data}`,
      LIMITS.verifyPerEmail.limit,
      LIMITS.verifyPerEmail.windowSeconds,
    ),
    consumeRateLimit(`verify:ip:${ip}`, LIMITS.verifyPerIp.limit, LIMITS.verifyPerIp.windowSeconds),
  ]);
  if (!emailOk || !ipOk) {
    await recordSecurityEvent("auth.verify_rate_limited", {
      email_domain: emailDomain(email.data),
    });
    return { ok: false, reason: "rate_limited" };
  }

  const { data, error } = await user.auth.verifyOtp({
    email: email.data,
    token: code.data,
    type: "email",
  });
  if (error || !data.session) {
    await recordSecurityEvent("auth.sign_in_failed", {
      email_domain: emailDomain(email.data),
      reason: error?.code ?? "no_session",
    });
    return { ok: false, reason: "invalid" };
  }
  await recordSecurityEvent("auth.sign_in_succeeded", { method: "email_otp" }, user);
  return { ok: true };
}
