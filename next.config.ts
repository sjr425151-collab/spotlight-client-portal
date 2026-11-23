import type { NextConfig } from "next";

import { securityHeaders } from "./src/config/security-headers";

const isDevelopment = process.env.NODE_ENV === "development";

const nextConfig: NextConfig = {
  // Do not advertise the framework in response headers.
  poweredByHeader: false,
  reactStrictMode: true,
  // Typed routes catch broken internal links at compile time.
  typedRoutes: true,
  headers() {
    return Promise.resolve([
      {
        source: "/:path*",
        headers: securityHeaders({ isDevelopment }),
      },
    ]);
  },
};

export default nextConfig;
