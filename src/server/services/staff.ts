import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { recordSecurityEvent, verifiedActorId } from "@/server/auth/security-events";
import { createAdminClient } from "@/server/supabase/admin";

/**
 * Staff and user administration (spec 03 §4, §6.3). Authorization happens twice: in the
 * calling guard and again inside the definer function. The admin client is used only
 * after the database has accepted the change.
 */

type RpcResult = { ok: boolean; error?: string };

async function call(client: SupabaseClient, fn: string, args: Record<string, unknown>) {
  const { data, error } = await client.rpc(fn, args);
  const result = data as RpcResult | null;
  if (error || !result) return { ok: false, error: "unavailable" } as const;
  return result.ok
    ? ({ ok: true } as const)
    : ({ ok: false, error: result.error ?? "unavailable" } as const);
}

export function setStaffRole(
  user: SupabaseClient,
  userId: string,
  role: "owner" | "admin" | "fulfillment",
  reason: string,
) {
  return call(user, "set_staff_role", { p_user_id: userId, p_role: role, p_reason: reason });
}

export function revokeStaff(user: SupabaseClient, userId: string, reason: string) {
  return call(user, "revoke_staff", { p_user_id: userId, p_reason: reason });
}

export function revokeMembership(user: SupabaseClient, membershipId: string, reason: string) {
  return call(user, "revoke_membership", { p_membership_id: membershipId, p_reason: reason });
}

export function revokeInvitation(user: SupabaseClient, invitationId: string) {
  return call(user, "revoke_invitation", { p_invitation_id: invitationId });
}

/**
 * Deactivation is immediate (spec 03 §6.3): the profile status is checked live by every
 * policy, and the Auth ban stops session refresh (03A U-11).
 */
export async function setUserStatus(
  user: SupabaseClient,
  userId: string,
  status: "active" | "deactivated",
  reason: string,
) {
  const result = await call(user, "set_user_status", {
    p_user_id: userId,
    p_status: status,
    p_reason: reason,
  });
  if (!result.ok) return result;
  const admin = await createAdminClient();
  const { error } = await admin.auth.admin.updateUserById(userId, {
    ban_duration: status === "deactivated" ? "876000h" : "none",
  });
  if (error) {
    await recordSecurityEvent(
      "session.ban_update_failed",
      { target: userId, status },
      await verifiedActorId(user),
    );
    return { ok: false, error: "partial" } as const;
  }
  return result;
}

/**
 * Owner-only MFA reset (spec 03 §7). The caller's guard has already required the Owner
 * with fresh MFA; the database re-checks that before any factor is removed.
 */
export async function resetMfa(user: SupabaseClient, userId: string) {
  const { data } = await user.rpc("auth_context");
  const ctx = data as {
    user_id?: string;
    staff_role?: string;
    mfa_fresh?: boolean;
    session_active?: boolean;
  } | null;
  if (ctx?.staff_role !== "owner" || !ctx.mfa_fresh || !ctx.session_active) {
    return { ok: false, error: "forbidden" } as const;
  }
  const admin = await createAdminClient();
  const { data: factors, error } = await admin.auth.admin.mfa.listFactors({ userId });
  if (error) return { ok: false, error: "unavailable" } as const;
  for (const factor of factors.factors) {
    await admin.auth.admin.mfa.deleteFactor({ id: factor.id, userId });
  }
  // Actor: the Owner the database just verified (auth_context reads the verified JWT).
  await recordSecurityEvent(
    "mfa.reset",
    { target: userId, factors: factors.factors.length },
    ctx.user_id ?? null,
  );
  return { ok: true } as const;
}
