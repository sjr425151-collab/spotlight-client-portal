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
];

const baseSchema = z.object({
  APP_ENV: z.enum(APP_ENVIRONMENTS),
  NEXT_PUBLIC_SITE_URL: z.url({ protocol: /^https?$/ }),
  STRIPE_SECRET_KEY: z.string().min(1).optional(),
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
