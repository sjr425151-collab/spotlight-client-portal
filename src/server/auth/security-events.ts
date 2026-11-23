import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

import { createAdminClient } from "@/server/supabase/admin";

/**
 * Security audit events (spec 03 §11). Summaries carry no OTPs, tokens or full emails:
 * only the email domain and outcome codes (CLAUDE.md §4).
 */
export async function recordSecurityEvent(
  action: `${"auth" | "mfa" | "session"}.${string}`,
  summary: Record<string, string | number | boolean | null> = {},
  client?: SupabaseClient,
) {
  const db = client ?? (await createAdminClient());
  const { error } = await db.rpc("record_security_event", { p_action: action, p_summary: summary });
  if (error) console.error("security event not recorded", action);
}

export function emailDomain(email: string): string {
  return email.split("@")[1]?.toLowerCase() ?? "";
}
