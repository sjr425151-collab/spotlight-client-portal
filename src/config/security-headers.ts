/**
 * Security headers applied to every portal response (03 §2 TM-10, T-SEC-02).
 *
 * Phase 1 uses a static Content-Security-Policy. Next.js injects inline bootstrap
 * scripts, so `script-src` allows 'unsafe-inline' until a nonce-based policy is
 * introduced alongside request handling in Phase 2 (tracked in docs/DEVELOPMENT.md).
 */

export interface SecurityHeaderOptions {
  /** `next dev` needs eval for fast refresh and a websocket for HMR. */
  isDevelopment: boolean;
}

export interface Header {
  key: string;
  value: string;
}

export function contentSecurityPolicy({ isDevelopment }: SecurityHeaderOptions): string {
  const scriptSrc = ["'self'", "'unsafe-inline'", ...(isDevelopment ? ["'unsafe-eval'"] : [])];
  const connectSrc = ["'self'", ...(isDevelopment ? ["ws:"] : [])];

  const directives: Record<string, string[]> = {
    "default-src": ["'self'"],
    "script-src": scriptSrc,
    "style-src": ["'self'", "'unsafe-inline'"],
    "img-src": ["'self'", "data:", "blob:"],
    "font-src": ["'self'"],
    "connect-src": connectSrc,
    "object-src": ["'none'"],
    "base-uri": ["'self'"],
    "form-action": ["'self'"],
    "frame-ancestors": ["'none'"],
  };

  return Object.entries(directives)
    .map(([directive, sources]) => `${directive} ${sources.join(" ")}`)
    .join("; ");
}

export function securityHeaders(options: SecurityHeaderOptions): Header[] {
  return [
    { key: "Content-Security-Policy", value: contentSecurityPolicy(options) },
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
