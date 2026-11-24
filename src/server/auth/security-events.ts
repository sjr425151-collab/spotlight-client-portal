import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { createAdminClient } from "@/server/supabase/admin";

/**
 * Security audit events (spec 03 §11). Recorded only by the server with the secret key:
 * the database refuses every other caller (Phase 2 remediation D1). The actor is the user
 * the server has verified (JWT claims via getClaims, or the Auth server's own response),
 * never a value taken from client input. Summaries carry no OTPs, tokens or full emails:
 * only the email domain and outcome codes (CLAUDE.md §3). The database rejects summaries
 * over 2048 bytes.
 */
export type SecurityAction = `${"auth" | "mfa" | "session"}.${string}`;

export async function recordSecurityEvent(
  action: SecurityAction,
  summary: Record<string, string | number | boolean | null> = {},
  actorUserId: string | null = null,
) {
  const admin = await createAdminClient();
  const { error } = await admin.rpc("record_security_event", {
    p_actor_user_id: actorUserId,
    p_action: action,
    p_summary: summary,
  });
  if (error) console.error("security event not recorded", action);
}

/** The verified user behind a user-scoped client (signature-checked JWT claims), or null. */
export async function verifiedActorId(user: SupabaseClient): Promise<string | null> {
  const { data, error } = await user.auth.getClaims();
  return !error && typeof data?.claims?.sub === "string" ? data.claims.sub : null;
}

export function emailDomain(email: string): string {
  return email.split("@")[1]?.toLowerCase() ?? "";
}
