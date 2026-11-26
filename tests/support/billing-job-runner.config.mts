import { fileURLToPath } from "node:url";

import { defineConfig } from "vitest/config";

/**
 * Vitest configuration for the billing-job runner subprocess only (AUTH-008 I-2, seam (a);
 * see billing-job-runner.ts). It runs exactly one file, against the LOCAL Supabase stack.
 */
export default defineConfig({
  root: fileURLToPath(new URL("../..", import.meta.url)),
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("../../src", import.meta.url)),
      // Server modules are exercised directly, outside Next.js (as in the integration config).
      "server-only": fileURLToPath(new URL("./empty.ts", import.meta.url)),
    },
  },
  test: {
    include: ["tests/support/billing-job-runner.job.ts"],
    environment: "node",
    fileParallelism: false,
    testTimeout: 90_000,
    hookTimeout: 60_000,
  },
});
