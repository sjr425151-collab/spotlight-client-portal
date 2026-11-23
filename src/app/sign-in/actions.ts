"use server";

import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { AUTH_COOKIE_OPTIONS } from "@/config/auth-cookies";
import { getAuthContext } from "@/server/auth/context";
import { recordSecurityEvent } from "@/server/auth/security-events";
import { requestMeta } from "@/server/request";
import { emailSchema, requestSignInCode, verifySignInCode } from "@/server/services/sign-in";
import { createAnonymousClient, createUserClient } from "@/server/supabase/clients";

const PENDING_EMAIL_COOKIE = "sp_signin_email";

// public-action: sign-in is the unauthenticated entry point (spec 03 §6.2).
export async function requestCodeAction(formData: FormData) {
  const email = emailSchema.safeParse(formData.get("email"));
  if (email.success) {
    const meta = await requestMeta();
    await requestSignInCode({ anon: await createAnonymousClient(), ip: meta.ip }, email.data);
    (await cookies()).set(PENDING_EMAIL_COOKIE, email.data, {
      httpOnly: true,
      sameSite: "lax",
      secure: AUTH_COOKIE_OPTIONS.secure,
      path: "/sign-in",
      maxAge: 600,
    });
  }
  // Same response whether or not the account exists (TM-03).
  redirect("/sign-in?step=code&notice=code_sent");
}

// public-action: completes sign-in with the emailed code.
export async function verifyCodeAction(formData: FormData) {
  const store = await cookies();
  const email = store.get(PENDING_EMAIL_COOKIE)?.value ?? "";
  const user = await createUserClient();
  const meta = await requestMeta();
  const outcome = await verifySignInCode(user, email, String(formData.get("code") ?? ""), meta.ip);
  if (!outcome.ok) {
    redirect(
      `/sign-in?step=code&error=${outcome.reason === "rate_limited" ? "rate_limited" : "invalid_code"}`,
    );
  }
  store.delete({ name: PENDING_EMAIL_COOKIE, path: "/sign-in" });
  redirect("/portal");
}

// public-action: ends the current session. Staff sign out of every device (spec 03 §6.3).
export async function signOutAction() {
  const ctx = await getAuthContext();
  const user = await createUserClient();
  if (ctx)
    await recordSecurityEvent(
      "session.signed_out",
      { scope: ctx.staffRole ? "global" : "local" },
      ctx.userId,
    );
  await user.auth.signOut({ scope: ctx?.staffRole ? "global" : "local" });
  redirect("/sign-in?notice=signed_out");
}
