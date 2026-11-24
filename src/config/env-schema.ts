import { z } from "zod";

/**
 * Environment contract (02 §4, §9). Pure module: no `server-only` import, so the rules
 * can be unit tested. Application code reads configuration through `@/config/env`.
 *
 * Only variables that Phase 1 actually uses are required. Integration variables for
 * later phases are listed in `.env.example` and are validated here only where a
 * Phase 1 guardrail applies (a live Stripe key outside production).
 */

export const APP_ENVIRONMENTS = [
  "development",
  "test",
  "preview",
  "staging",
  "production",
] as const;
export type AppEnvironment = (typeof APP_ENVIRONMENTS)[number];

/** Value patterns that must never appear in a browser-exposed (NEXT_PUBLIC_) variable. */
const SECRET_VALUE_PATTERNS: readonly RegExp[] = [
  /\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]+/, // Stripe secret and restricted keys
  /\bwhsec_[A-Za-z0-9]+/, // Stripe webhook signing secrets
  /\bre_[A-Za-z0-9_]{20,}/, // Resend API keys
  /"role"\s*:\s*"service_role"/, // decoded Supabase service-role JWT payloads
  /\bsb_secret_[A-Za-z0-9_-]+/, // Supabase secret API keys (spec 03 §15)
];

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

const baseSchema = z.object({
  APP_ENV: z.enum(APP_ENVIRONMENTS),
  NEXT_PUBLIC_SITE_URL: z.url({ protocol: /^https?$/ }),
  STRIPE_SECRET_KEY: z.string().min(1).optional(),
  // Spec 03 §15. Server code only; the browser never talks to Supabase directly.
  NEXT_PUBLIC_SUPABASE_URL: z.url({ protocol: /^https?$/ }),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().regex(/^sb_publishable_[A-Za-z0-9_-]+$/, {
    message: "must be a Supabase publishable key (sb_publishable_...)",
  }),
  SUPABASE_SECRET_KEY: z.string().regex(/^sb_secret_[A-Za-z0-9_-]+$/, {
    message: "must be a Supabase secret key (sb_secret_...)",
  }),
  // WP-B (04 §11). Server-only signing secret of the webhook endpoint. CI generates a
  // test-only value per run (OI-63); a real test-mode secret exists only under AUTH-002.
  STRIPE_WEBHOOK_SECRET: z
    .string()
    .regex(/^whsec_[A-Za-z0-9]+$/, { message: "must be a webhook signing secret (whsec_...)" })
    .optional(),
  // WP-B: which Stripe gateway the server uses (absent means disabled). "mock" never makes a network request and is
  // allowed only in development and test. No real gateway exists until AUTH-002 is active.
  STRIPE_GATEWAY: z.enum(["disabled", "mock"]).optional(),
  // OI-69: whether the test-only agreement fixture may be presented (absent means disabled).
  // Rejected in production.
  AGREEMENT_TEST_FIXTURE: z.enum(["enabled", "disabled"]).optional(),
});

export type ServerEnv = z.infer<typeof baseSchema>;

export class EnvValidationError extends Error {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    // Messages name variables and rules only; they never echo values.
    super(`Invalid environment configuration:\n- ${issues.join("\n- ")}`);
    this.name = "EnvValidationError";
    this.issues = issues;
  }
}

export function parseServerEnv(source: Record<string, string | undefined>): ServerEnv {
  const issues: string[] = [];

  const parsed = baseSchema.safeParse(source);
  if (!parsed.success) {
    for (const issue of parsed.error.issues) {
      issues.push(`${issue.path.join(".") || "(root)"}: ${issue.message}`);
    }
  }

  // 02 §4 rule 2: non-production environments may never hold live Stripe keys.
  const appEnv = parsed.success ? parsed.data.APP_ENV : source.APP_ENV;
  const stripeKey = source.STRIPE_SECRET_KEY;
  if (stripeKey && /^(?:sk|rk)_live_/.test(stripeKey) && appEnv !== "production") {
    issues.push("STRIPE_SECRET_KEY: a live-mode Stripe key is not allowed outside production");
  }

  // OI-69 (T-AGR-08): the environment schema rejects the test-only fixture in production.
  if (source.AGREEMENT_TEST_FIXTURE === "enabled" && appEnv === "production") {
    issues.push(
      "AGREEMENT_TEST_FIXTURE: the test-only agreement fixture is not allowed in production",
    );
  }
  // CLAUDE.md §4: the mocked gateway is a development and CI tool only.
  if (source.STRIPE_GATEWAY === "mock" && appEnv !== "development" && appEnv !== "test") {
    issues.push(
      "STRIPE_GATEWAY: the mocked Stripe gateway is allowed only in development and test",
    );
  }

  // Spec 03 §15: only staging and production may point at a non-local Supabase project.
  const supabaseUrl = source.NEXT_PUBLIC_SUPABASE_URL;
  if (supabaseUrl && appEnv !== "staging" && appEnv !== "production") {
    try {
      if (!LOCAL_HOSTS.has(new URL(supabaseUrl).hostname)) {
        issues.push(
          "NEXT_PUBLIC_SUPABASE_URL: only a local Supabase stack is allowed outside staging and production",
        );
      }
    } catch {
      // Reported by the schema above.
    }
  }

  // 02 §9 rule 3: secrets must never be exposed to client bundles.
  for (const [name, value] of Object.entries(source)) {
    if (name.startsWith("NEXT_PUBLIC_") && value) {
      if (SECRET_VALUE_PATTERNS.some((pattern) => pattern.test(value))) {
        issues.push(`${name}: browser-exposed variables must not contain secret values`);
      }
    }
  }

  if (issues.length > 0 || !parsed.success) {
    throw new EnvValidationError(issues);
  }

  return parsed.data;
}

/** The internal design-system reference page is never served in production. */
export function isDesignSystemEnabled(appEnv: AppEnvironment): boolean {
  return appEnv !== "production";
}
