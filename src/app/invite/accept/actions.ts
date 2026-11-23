"use server";

import { redirect } from "next/navigation";

import { env } from "@/config/env";
import { getAuthContext } from "@/server/auth/context";
import { requestMeta } from "@/server/request";
import {
  acceptInvitation,
  checkInvitationLink,
  resendInvitationCode,
} from "@/server/services/invitations";
import { verifySignInCode } from "@/server/services/sign-in";
import { createAnonymousClient, createUserClient } from "@/server/supabase/clients";

function linkParams(formData: FormData) {
  return { id: String(formData.get("id") ?? ""), token: String(formData.get("t") ?? "") };
}

function backTo(id: string, token: string, query: string): never {
  const params = new URLSearchParams({ id, t: token });
  redirect(`/invite/accept?${params.toString()}&${query}`);
}

function destination(kind: "client" | "staff"): never {
  // Staff must enroll in MFA before anything else (spec 03 §7).
  redirect(
    kind === "staff" ? "/mfa?notice=invitation_accepted" : "/portal?notice=invitation_accepted",
  );
}

// public-action: the invitee proves control of the email with the code, then accepts.
// The link token is re-checked server-side; nothing from the form is trusted.
export async function verifyInvitationCodeAction(formData: FormData) {
  const { id, token } = linkParams(formData);
  const meta = await requestMeta();
  const link = await checkInvitationLink(id, token, meta.ip);
  if (!link.ok) redirect("/invite/accept?error=invalid_invitation");

  const user = await createUserClient();
  const verified = await verifySignInCode(
    user,
    link.email,
    String(formData.get("code") ?? ""),
    meta.ip,
  );
  if (!verified.ok)
    backTo(
      id,
      token,
      `error=${verified.reason === "rate_limited" ? "rate_limited" : "invalid_code"}`,
    );

  const accepted = await acceptInvitation(user, id, token);
  if (!accepted.ok) redirect("/invite/accept?error=invalid_invitation");
  destination(accepted.kind);
}

// public-action: sends a fresh code for a valid invitation link (03A S-02).
export async function resendInvitationCodeAction(formData: FormData) {
  const { id, token } = linkParams(formData);
  const meta = await requestMeta();
  await resendInvitationCode(
    {
      anon: await createAnonymousClient(),
      ip: meta.ip,
      siteUrl: env.NEXT_PUBLIC_SITE_URL,
    },
    id,
    token,
  );
  backTo(id, token, "notice=code_sent");
}

// public-action: an already signed-in user accepts the invitation from the link.
// accept_invitation binds it to the caller's verified email.
export async function acceptSignedInAction(formData: FormData) {
  const ctx = await getAuthContext();
  if (!ctx?.sessionActive) redirect("/sign-in");
  const { id, token } = linkParams(formData);
  const accepted = await acceptInvitation(await createUserClient(), id, token);
  if (!accepted.ok) redirect("/invite/accept?error=invalid_invitation");
  destination(accepted.kind);
}
