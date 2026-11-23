/**
 * Supabase auth cookie hardening (spec 03 §6.2, TM-15). The browser never needs the
 * tokens: every Supabase call is server-side, so cookies are HttpOnly.
 */
export const AUTH_COOKIE_OPTIONS = {
  httpOnly: true,
  sameSite: "lax",
  secure: process.env.NODE_ENV === "production" && process.env.APP_ENV !== "test",
  path: "/",
} as const;
