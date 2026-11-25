"use server";

import { redirect } from "next/navigation";

import { homeFor, requireUser, safeReturnPath } from "@/server/auth/guards";
import { startEnrollment, verifiedTotpFactor, verifyTotp } from "@/server/services/mfa";
import { createUserClient } from "@/server/supabase/clients";

export interface EnrollState {
  factorId?: string;
  qrCode?: string;
  secret?: string;
  error?: string;
}

/** Staff and Sales Representatives only (03 §4.1, §7): begins TOTP enrollment. */
export async function startEnrollmentAction(_prev: EnrollState): Promise<EnrollState> {
  const ctx = await requireUser();
  if (!ctx.staffRole && !ctx.sales) redirect("/portal");
  const enrollment = await startEnrollment(await createUserClient());
  if (!enrollment) return { error: "unavailable" };
  return enrollment;
}

export async function completeEnrollmentAction(
  prev: EnrollState,
  formData: FormData,
): Promise<EnrollState> {
  const ctx = await requireUser();
  if (!ctx.staffRole && !ctx.sales) redirect("/portal");
  const factorId = String(formData.get("factorId") ?? "");
  const user = await createUserClient();
  const ok = await verifyTotp(user, factorId, String(formData.get("code") ?? ""), "enroll");
  if (!ok) return { ...prev, error: "invalid_mfa_code" };
  redirect(`${safeReturnPath(String(formData.get("next") ?? ""), homeFor(ctx))}`);
}

/** Verifies the authenticator code: upgrades to aal2, or refreshes MFA for high-risk actions. */
export async function verifyMfaAction(formData: FormData) {
  const ctx = await requireUser();
  if (!ctx.staffRole && !ctx.sales) redirect("/portal");
  const next = safeReturnPath(String(formData.get("next") ?? ""), homeFor(ctx));
  const user = await createUserClient();
  const factor = await verifiedTotpFactor(user);
  if (!factor) redirect("/mfa");
  const ok = await verifyTotp(user, factor.id, String(formData.get("code") ?? ""), "verify");
  if (!ok) {
    redirect(
      `/mfa?error=invalid_mfa_code&next=${encodeURIComponent(next)}${formData.get("reauth") ? "&reauth=1" : ""}`,
    );
  }
  redirect(next as never);
}
