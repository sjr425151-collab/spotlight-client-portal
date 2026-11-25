import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";

import { consumeRateLimit, LIMITS } from "@/server/auth/rate-limit";
import { emailDomain, recordSecurityEvent } from "@/server/auth/security-events";
import { emailSchema } from "@/server/services/sign-in";
import { createAdminClient } from "@/server/supabase/admin";

/**
 * Two-layer invitations (spec 03 §6.1): the application invitation (hashed 256-bit token,
 * 7 days, single use) authorizes access; Supabase Auth only proves control of the email.
 */

export const uuidSchema = z.uuid();
export const tokenSchema = z.string().regex(/^[A-Za-z0-9_-]{43}$/);

export const createInvitationSchema = z.object({
  kind: z.enum(["client", "staff"]),
  email: emailSchema,
  fullName: z.string().trim().min(1).max(200),
  projectId: uuidSchema.optional(),
  // "fulfillment" is passed through so the database rejects and audits it (OI-03, T-ROLE-05).
  // "sales": the Sales Representative role (03 §4.1), Owner-only with fresh MFA like any staff role.
  role: z.enum(["owner", "admin", "sales", "fulfillment"]).optional(),
});
export type CreateInvitationInput = z.infer<typeof createInvitationSchema>;

export type CreateInvitationResult =
  { ok: true; invitationId: string; emailSent: boolean } | { ok: false; error: string };

export function invitationLink(siteUrl: string, invitationId: string, token: string): string {
  const url = new URL("/invite/accept", siteUrl);
  url.searchParams.set("id", invitationId);
  url.searchParams.set("t", token);
  return url.toString();
}

/**
 * Creates the application invitation as the signed-in staff member (RLS and the definer
 * function authorize it), then asks Supabase Auth to email the code and link. Existing
 * confirmed users cannot be emailed by Supabase (03A S-06); they accept in the portal.
 */
export async function createInvitation(
  deps: { user: SupabaseClient; siteUrl: string },
  input: CreateInvitationInput,
): Promise<CreateInvitationResult> {
  const { data, error } = await deps.user.rpc("create_invitation", {
    p_kind: input.kind,
    p_email: input.email,
    p_full_name: input.fullName,
    p_project_id: input.kind === "client" ? (input.projectId ?? null) : null,
    p_intended_role: input.kind === "staff" ? (input.role ?? null) : null,
  });
  const result = data as {
    ok: boolean;
    error?: string;
    invitation_id?: string;
    token?: string;
  } | null;
  if (error || !result) return { ok: false, error: "unavailable" };
  if (!result.ok || !result.invitation_id || !result.token) {
    return { ok: false, error: result.error ?? "unavailable" };
  }

  // Secret-key use, after the database authorized and audited the invitation (§9.1 rule 6).
  const emailSent = await sendInvitationEmail(
    await createAdminClient(),
    input.email,
    invitationLink(deps.siteUrl, result.invitation_id, result.token),
  );
  return { ok: true, invitationId: result.invitation_id, emailSent };
}

async function sendInvitationEmail(admin: SupabaseClient, email: string, redirectTo: string) {
  // The before-user-created hook admits this email only because a pending invitation exists.
  const { error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
  if (error) {
    await recordSecurityEvent("auth.invite_email_not_sent", {
      email_domain: emailDomain(email),
      reason: error.code ?? "error",
    });
    return false;
  }
  return true;
}

/**
 * Service-role pre-check of an invitation link. The database counts failed attempts per
 * invitation (lock after 10); the app also limits attempts per IP (spec 03 §17).
 */
export async function checkInvitationLink(
  invitationId: string,
  token: string,
  ip: string,
): Promise<{ ok: true; email: string } | { ok: false }> {
  if (!uuidSchema.safeParse(invitationId).success || !tokenSchema.safeParse(token).success) {
    return { ok: false };
  }
  const allowed = await consumeRateLimit(
    `invite-link:ip:${ip}`,
    LIMITS.invitationLinkPerIp.limit,
    LIMITS.invitationLinkPerIp.windowSeconds,
  );
  if (!allowed) {
    await recordSecurityEvent("auth.invitation_link_rate_limited", {});
    return { ok: false };
  }
  const admin = await createAdminClient();
  const { data, error } = await admin.rpc("check_invitation_link", {
    p_invitation_id: invitationId,
    p_token: token,
  });
  const result = data as { ok: boolean; email?: string } | null;
  if (error || !result?.ok || !result.email) return { ok: false };
  return { ok: true, email: result.email };
}

/**
 * "Send me a new code" from a valid invitation link (03A S-02). While the invitee is
 * unconfirmed, Supabase only emails them through a re-invite; once confirmed, the
 * standard sign-in code is used.
 */
export async function resendInvitationCode(
  deps: { anon: SupabaseClient; ip: string; siteUrl: string },
  invitationId: string,
  token: string,
): Promise<void> {
  const link = await checkInvitationLink(invitationId, token, deps.ip);
  if (!link.ok) return;
  const [emailOk, ipOk] = await Promise.all([
    consumeRateLimit(
      `otp:email:${link.email}`,
      LIMITS.otpPerEmail.limit,
      LIMITS.otpPerEmail.windowSeconds,
    ),
    consumeRateLimit(`otp:ip:${deps.ip}`, LIMITS.otpPerIp.limit, LIMITS.otpPerIp.windowSeconds),
  ]);
  if (!emailOk || !ipOk) {
    await recordSecurityEvent("auth.otp_rate_limited", { email_domain: emailDomain(link.email) });
    return;
  }
  const admin = await createAdminClient();
  const { error } = await admin.auth.admin.inviteUserByEmail(link.email, {
    redirectTo: invitationLink(deps.siteUrl, invitationId, token),
  });
  if (error?.code === "email_exists") {
    await deps.anon.auth.signInWithOtp({ email: link.email, options: { shouldCreateUser: false } });
  }
  await recordSecurityEvent("auth.otp_requested", {
    email_domain: emailDomain(link.email),
    outcome: error && error.code !== "email_exists" ? (error.code ?? "error") : "sent",
    via: "invitation",
  });
}

/**
 * The pending invitation to resend, as read SERVER-SIDE by the caller's own authorized path
 * (staff: the invitations table through RLS; Sales: sales_project_progress, which checks the
 * active assignment). Never taken from form input.
 */
export interface PendingInvitation {
  id: string;
  kind: "client" | "staff";
  email: string;
  fullName: string;
  projectId: string | null;
  role?: "owner" | "admin" | "sales";
}

export type ResendResult =
  | { ok: true; invitationId: string; emailSent: boolean }
  | { ok: false; error: string; revoked: boolean };

/**
 * Resend is revoke followed by reissue (03 §4.1, §6.1; OI-84(d)), for every role. Revocation
 * comes first, so at most one usable invitation exists per address; the old link and token
 * stop working at once. If the reissue then fails (for example on the rate limit), the old
 * invitation stays revoked and the caller sees the failure. Both steps are database calls
 * that authorize, rate-limit, and audit on their own; there is no resend database object.
 */
export async function resendInvitation(
  deps: { user: SupabaseClient; siteUrl: string },
  invitation: PendingInvitation,
): Promise<ResendResult> {
  if (!uuidSchema.safeParse(invitation.id).success) {
    return { ok: false, error: "invalid_input", revoked: false };
  }
  const { data, error } = await deps.user.rpc("revoke_invitation", {
    p_invitation_id: invitation.id,
  });
  const revoked = data as { ok: boolean; error?: string } | null;
  if (error || !revoked) return { ok: false, error: "unavailable", revoked: false };
  if (!revoked.ok) return { ok: false, error: revoked.error ?? "unavailable", revoked: false };

  const input = createInvitationSchema.safeParse({
    kind: invitation.kind,
    email: invitation.email,
    fullName: invitation.fullName,
    projectId: invitation.projectId ?? undefined,
    role: invitation.role,
  });
  if (!input.success) return { ok: false, error: "invalid_input", revoked: true };
  const created = await createInvitation(deps, input.data);
  return created.ok ? created : { ok: false, error: created.error, revoked: true };
}

export type AcceptResult =
  { ok: true; kind: "client" | "staff"; projectId: string | null } | { ok: false };

/** Accepts as the signed-in user. A null token is the in-portal, email-bound path. */
export async function acceptInvitation(
  user: SupabaseClient,
  invitationId: string,
  token: string | null,
): Promise<AcceptResult> {
  if (!uuidSchema.safeParse(invitationId).success) return { ok: false };
  if (token !== null && !tokenSchema.safeParse(token).success) return { ok: false };
  const { data, error } = await user.rpc("accept_invitation", {
    p_invitation_id: invitationId,
    p_token: token,
  });
  const result = data as {
    ok: boolean;
    kind?: "client" | "staff";
    project_id?: string | null;
  } | null;
  if (error || !result?.ok || !result.kind) return { ok: false };
  return { ok: true, kind: result.kind, projectId: result.project_id ?? null };
}
