import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

import { contentSecurityPolicy, generateNonce } from "@/config/security-headers";
import { AUTH_COOKIE_OPTIONS } from "@/config/auth-cookies";

/**
 * Next.js 16 proxy (03A F-31): per-request nonce CSP (spec 03 §14, DEP-13) and Supabase
 * session refresh with getClaims() (03A F-19). Every HTML response is dynamic because
 * nonces require it (03A F-30). Authenticated responses are never cached (TM-15).
 */
const PRIVATE_PREFIXES = ["/portal", "/staff", "/mfa", "/invite", "/sign-in"];

export async function proxy(request: NextRequest) {
  const nonce = generateNonce();
  const csp = contentSecurityPolicy({
    isDevelopment: process.env.NODE_ENV === "development",
    nonce,
  });
  const requestId = crypto.randomUUID();

  // 1. Refresh the Supabase session (only when an auth cookie is present).
  const refreshed: Array<{ name: string; value: string; options: object }> = [];
  const refreshHeaders: Record<string, string> = {};
  const hasAuthCookie = request.cookies.getAll().some((cookie) => cookie.name.startsWith("sb-"));
  if (hasAuthCookie) {
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
      process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "",
      {
        cookieOptions: AUTH_COOKIE_OPTIONS,
        cookies: {
          getAll: () => request.cookies.getAll(),
          setAll(cookiesToSet, headers) {
            for (const { name, value, options } of cookiesToSet) {
              request.cookies.set(name, value);
              refreshed.push({ name, value, options });
            }
            Object.assign(refreshHeaders, headers ?? {});
          },
        },
      },
    );
    await supabase.auth.getClaims();
  }

  // 2. Forward the nonce (and refreshed cookies) to the rendering request.
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("content-security-policy", csp);
  requestHeaders.set("x-request-id", requestId);
  const response = NextResponse.next({ request: { headers: requestHeaders } });

  for (const { name, value, options } of refreshed) response.cookies.set(name, value, options);
  for (const [key, value] of Object.entries(refreshHeaders)) response.headers.set(key, value);

  response.headers.set("Content-Security-Policy", csp);
  response.headers.set("x-request-id", requestId);
  const isPrivate = PRIVATE_PREFIXES.some((prefix) => request.nextUrl.pathname.startsWith(prefix));
  if (isPrivate || hasAuthCookie) {
    response.headers.set("Cache-Control", "private, no-store");
  }
  return response;
}

export const config = {
  matcher: [
    {
      source: "/((?!_next/static|_next/image|brand/|robots.txt).*)",
      missing: [
        { type: "header", key: "next-router-prefetch" },
        { type: "header", key: "purpose", value: "prefetch" },
      ],
    },
  ],
};
