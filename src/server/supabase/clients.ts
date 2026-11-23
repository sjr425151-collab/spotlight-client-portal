import "server-only";

import { createServerClient } from "@supabase/ssr";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";

import { AUTH_COOKIE_OPTIONS } from "@/config/auth-cookies";
import { env } from "@/config/env";
import { requestMeta } from "@/server/request";

/**
 * Spec 03 §5, §10. Publishable-key clients, server-only: the user client (with the
 * user's cookies, RLS always applies) and a sessionless client for sending codes.
 * The secret-key admin client lives in ./admin.ts (spec 03 §9.1 rule 6).
 */
export async function createUserClient(): Promise<SupabaseClient> {
  const cookieStore = await cookies();
  const meta = await requestMeta();
  return createServerClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookieOptions: AUTH_COOKIE_OPTIONS,
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet)
              cookieStore.set(name, value, options);
          } catch {
            // Called from a Server Component: the proxy refreshes cookies instead.
          }
        },
      },
      global: { headers: { "x-request-id": meta.requestId, "x-client-ip": meta.ip } },
    },
  );
}

/** A sessionless client with the publishable key, used to send sign-in codes. */
export async function createAnonymousClient(): Promise<SupabaseClient> {
  const meta = await requestMeta();
  return createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    // Supabase rate-limits by the end user's IP when forwarding is enabled (03A F-09).
    global: { headers: { "Sb-Forwarded-For": meta.ip, "x-request-id": meta.requestId } },
  });
}
