import type { NextConfig } from "next";

import { staticSecurityHeaders } from "./src/config/security-headers";

const nextConfig: NextConfig = {
  // A separate output directory lets CI serve a production-mode build alongside the test
  // build, to verify production-only behavior (tests/e2e/production-gating.spec.ts).
  distDir: process.env.NEXT_DIST_DIR || ".next",
  // Do not advertise the framework in response headers.
  poweredByHeader: false,
  reactStrictMode: true,
  // Typed routes catch broken internal links at compile time.
  typedRoutes: true,
  headers() {
    // The nonce-based Content-Security-Policy is set per request in src/proxy.ts.
    return Promise.resolve([{ source: "/:path*", headers: staticSecurityHeaders() }]);
  },
};

export default nextConfig;
