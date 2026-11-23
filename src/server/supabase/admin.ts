import "server-only";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { env } from "@/config/env";
import { requestMeta } from "@/server/request";

/**
 * The only use of the Supabase secret key (spec 03 §9.1 rule 6). It bypasses RLS, so
 * every caller authorizes first (§10) and the action is audited. Used for invitation
 * provisioning, invitation-link checks, rate limits, security events, Auth bans, and
 * MFA factor reset. Never import it into client components (ESLint boundary).
 */
export async function createAdminClient(): Promise<SupabaseClient> {
  const meta = await requestMeta();
  return createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { "x-request-id": meta.requestId, "x-client-ip": meta.ip } },
  });
}
