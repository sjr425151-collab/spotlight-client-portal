import nextCoreWebVitals from "eslint-config-next/core-web-vitals";
import nextTypescript from "eslint-config-next/typescript";

/** @type {import("eslint").Linter.Config[]} */
const config = [
  {
    ignores: [
      ".next/**",
      ".next-production/**",
      "node_modules/**",
      "coverage/**",
      "playwright-report/**",
      "test-results/**",
      ".lighthouseci/**",
      "next-env.d.ts",
    ],
  },
  ...nextCoreWebVitals,
  ...nextTypescript,
  {
    rules: {
      // Never leave debug logging in committed code (CLAUDE.md §4: no secrets in logs).
      "no-console": ["error", { allow: ["warn", "error"] }],
      eqeqeq: ["error", "always"],
      "@typescript-eslint/consistent-type-imports": "error",
      "@typescript-eslint/no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },
  {
    // Architecture boundaries (docs/DEVELOPMENT.md): UI and domain code must not import
    // server-only adapters or configuration directly.
    files: ["src/components/**", "src/domain/**", "src/design/**"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["@/server/*", "@/config/env", "server-only"],
              message:
                "UI, design and domain modules must stay free of server-only code. Pass data in from a server component instead.",
            },
          ],
        },
      ],
    },
  },
  {
    // Spec 03 §9.1 rule 6 / §10: the secret-key admin client is importable only from
    // src/server/**, where each use follows an explicit authorization check.
    files: ["src/app/**", "src/lib/**", "src/config/**", "src/proxy.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["@/server/supabase/admin", "**/supabase/admin"],
              message:
                "The admin (secret-key) client is server-adapter only. Call a service in src/server/services instead.",
            },
          ],
        },
      ],
    },
  },
  {
    files: ["scripts/**/*.mjs"],
    rules: { "no-console": "off" },
  },
];

export default config;
