import { describe, expect, it } from "vitest";

import {
  contentSecurityPolicy,
  generateNonce,
  staticSecurityHeaders,
} from "@/config/security-headers";

const nonce = generateNonce();

describe("staticSecurityHeaders", () => {
  const headers = new Map(staticSecurityHeaders().map(({ key, value }) => [key, value]));

  it.each([
    "Strict-Transport-Security",
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Referrer-Policy",
    "Permissions-Policy",
    "Cross-Origin-Opener-Policy",
  ])("includes %s", (name) => {
    expect(headers.get(name)).toBeTruthy();
  });

  it("does not set a static CSP (the proxy sets a per-request nonce CSP)", () => {
    expect(headers.has("Content-Security-Policy")).toBe(false);
    expect(headers.get("X-Frame-Options")).toBe("DENY");
  });
});

describe("contentSecurityPolicy (DEP-13, T-SEC-03)", () => {
  const csp = contentSecurityPolicy({ isDevelopment: false, nonce });

  it("uses the nonce with strict-dynamic and no unsafe-inline", () => {
    expect(csp).toContain(`script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`);
    expect(csp).toContain(`style-src 'self' 'nonce-${nonce}'`);
    expect(csp).not.toContain("unsafe-inline");
  });

  it("forbids framing and plugins, and keeps connections same-origin", () => {
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
    expect(csp).toContain("connect-src 'self';");
    expect(csp).toContain("form-action 'self'");
  });

  it("only allows eval and websockets in development", () => {
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).not.toContain("ws:");
    expect(contentSecurityPolicy({ isDevelopment: true, nonce })).toContain("'unsafe-eval'");
  });

  it("rejects weak or malformed nonces", () => {
    expect(() => contentSecurityPolicy({ isDevelopment: false, nonce: "short" })).toThrow();
    expect(() =>
      contentSecurityPolicy({ isDevelopment: false, nonce: "' 'unsafe-inline' 'x" }),
    ).toThrow();
  });

  it("generates a fresh 128-bit nonce each time", () => {
    const nonces = new Set(Array.from({ length: 50 }, generateNonce));
    expect(nonces.size).toBe(50);
    expect(atob(nonce)).toHaveLength(16);
  });
});
