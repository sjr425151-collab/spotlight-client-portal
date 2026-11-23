/**
 * Security headers (spec 03 §2 TM-10, §14; T-SEC-02, T-SEC-03).
 *
 * The Content-Security-Policy is nonce-based and set per request by `src/proxy.ts`
 * (resolves DEP-13). Next.js applies the nonce to its own scripts automatically
 * (03A F-30). The browser never talks to Supabase directly (all Supabase calls are
 * server-side), so `connect-src` stays `'self'`.
 */

export interface CspOptions {
  /** `next dev` needs eval for fast refresh and a websocket for HMR (03A F-30). */
  isDevelopment: boolean;
  /** Per-request nonce: at least 128 random bits, base64. */
  nonce: string;
}

export interface Header {
  key: string;
  value: string;
}

export function contentSecurityPolicy({ isDevelopment, nonce }: CspOptions): string {
  if (!/^[A-Za-z0-9+/=]{22,}$/.test(nonce)) {
    throw new Error("CSP nonce must be at least 128 bits of base64");
  }
  const directives: Record<string, string[]> = {
    "default-src": ["'self'"],
    "script-src": [
      "'self'",
      `'nonce-${nonce}'`,
      "'strict-dynamic'",
      ...(isDevelopment ? ["'unsafe-eval'"] : []),
    ],
    "style-src": ["'self'", `'nonce-${nonce}'`],
    "img-src": ["'self'", "data:", "blob:"],
    "font-src": ["'self'"],
    "connect-src": ["'self'", ...(isDevelopment ? ["ws:"] : [])],
    "object-src": ["'none'"],
    "base-uri": ["'self'"],
    "form-action": ["'self'"],
    "frame-ancestors": ["'none'"],
  };

  return Object.entries(directives)
    .map(([directive, sources]) => `${directive} ${sources.join(" ")}`)
    .join("; ");
}

/** Static headers applied to every response (next.config.ts). CSP is added by the proxy. */
export function staticSecurityHeaders(): Header[] {
  return [
    { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
    { key: "X-Content-Type-Options", value: "nosniff" },
    { key: "X-Frame-Options", value: "DENY" },
    { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
    {
      key: "Permissions-Policy",
      value: "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()",
    },
    { key: "Cross-Origin-Opener-Policy", value: "same-origin" },
  ];
}

export function generateNonce(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
