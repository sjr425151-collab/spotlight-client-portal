import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { cache } from "react";

import { createUserClient } from "@/server/supabase/clients";

export type StaffRole = "owner" | "admin";

/**
 * The caller's authorization context (spec 03 §10). Identity comes from verified JWT
 * claims (getClaims, never getSession: T-AUTH-13). Role, status, session liveness and MFA
 * freshness come from the database on every request, so revocation is immediate (§6.3).
 */
export interface AuthContext {
  userId: string;
  email: string | null;
  active: boolean;
  staffRole: StaffRole | null;
  aal: "aal1" | "aal2";
  mfaFresh: boolean;
  sessionActive: boolean;
}

interface AuthContextRow {
  user_id: string | null;
  email: string | null;
  active: boolean;
  staff_role: string | null;
  aal: string;
  mfa_fresh: boolean;
  session_active: boolean;
}

export async function loadAuthContext(client: SupabaseClient): Promise<AuthContext | null> {
  const { data: claims, error: claimsError } = await client.auth.getClaims();
  if (claimsError || !claims?.claims?.sub) return null;

  const { data, error } = await client.rpc("auth_context");
  const row = data as AuthContextRow | null;
  if (error || !row?.user_id || row.user_id !== claims.claims.sub) return null;

  return {
    userId: row.user_id,
    email: row.email,
    active: row.active,
    staffRole: row.staff_role === "owner" || row.staff_role === "admin" ? row.staff_role : null,
    aal: row.aal === "aal2" ? "aal2" : "aal1",
    mfaFresh: row.mfa_fresh,
    sessionActive: row.session_active,
  };
}

/** Per-request memoized context for server components and server actions. */
export const getAuthContext = cache(async (): Promise<AuthContext | null> => {
  return loadAuthContext(await createUserClient());
});
