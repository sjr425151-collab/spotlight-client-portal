import { describe, expect, it } from "vitest";

import { contentSecurityPolicy, securityHeaders } from "@/config/security-headers";

describe("securityHeaders", () => {
  const headers = new Map(
    securityHeaders({ isDevelopment: false }).map(({ key, value }) => [key, value]),
  );

  it.each([
    "Content-Security-Policy",
    "Strict-Transport-Security",
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Referrer-Policy",
    "Permissions-Policy",
  ])("includes %s", (name) => {
    expect(headers.get(name)).toBeTruthy();
  });

  it("forbids framing and plugins", () => {
    const csp = headers.get("Content-Security-Policy") ?? "";
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("object-src 'none'");
    expect(headers.get("X-Frame-Options")).toBe("DENY");
  });

  it("only allows eval and websockets in development", () => {
    expect(contentSecurityPolicy({ isDevelopment: false })).not.toContain("unsafe-eval");
    expect(contentSecurityPolicy({ isDevelopment: false })).not.toContain("ws:");
    expect(contentSecurityPolicy({ isDevelopment: true })).toContain("'unsafe-eval'");
  });
});
