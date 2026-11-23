import { describe, expect, it } from "vitest";

import {
  APP_ENVIRONMENTS,
  EnvValidationError,
  isDesignSystemEnabled,
  parseServerEnv,
} from "@/config/env-schema";

// Placeholder key shapes only: not real keys, and no Supabase stack is contacted.
const valid = {
  APP_ENV: "test",
  NEXT_PUBLIC_SITE_URL: "http://localhost:3000",
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_placeholder",
  SUPABASE_SECRET_KEY: "sb_secret_placeholder",
};

function issuesFor(source: Record<string, string | undefined>): readonly string[] {
  try {
    parseServerEnv(source);
  } catch (error) {
    if (error instanceof EnvValidationError) return error.issues;
    throw error;
  }
  return [];
}

describe("parseServerEnv", () => {
  it("accepts a minimal valid configuration", () => {
    expect(parseServerEnv(valid)).toEqual(valid);
  });

  it("fails closed when required variables are missing", () => {
    const issues = issuesFor({});
    expect(issues.some((issue) => issue.startsWith("APP_ENV"))).toBe(true);
    expect(issues.some((issue) => issue.startsWith("NEXT_PUBLIC_SITE_URL"))).toBe(true);
    expect(issues.some((issue) => issue.startsWith("SUPABASE_SECRET_KEY"))).toBe(true);
  });

  it("requires Supabase keys of the right kind (spec 03 §15)", () => {
    expect(
      issuesFor({ ...valid, NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_secret_x" }),
    ).not.toHaveLength(0);
    expect(issuesFor({ ...valid, SUPABASE_SECRET_KEY: "sb_publishable_x" })).not.toHaveLength(0);
  });

  it.each(["development", "test", "preview"])(
    "rejects a hosted Supabase project in %s (local stack only)",
    (appEnv) => {
      const issues = issuesFor({
        ...valid,
        APP_ENV: appEnv,
        NEXT_PUBLIC_SUPABASE_URL: "https://abcdefghijklmnop.supabase.co",
      });
      expect(issues).toContain(
        "NEXT_PUBLIC_SUPABASE_URL: only a local Supabase stack is allowed outside staging and production",
      );
    },
  );

  it("rejects unknown environments and non-http URLs", () => {
    expect(issuesFor({ ...valid, APP_ENV: "prod" })).not.toHaveLength(0);
    expect(issuesFor({ ...valid, NEXT_PUBLIC_SITE_URL: "javascript:alert(1)" })).not.toHaveLength(
      0,
    );
  });

  it.each(["development", "test", "preview", "staging"])(
    "rejects a live Stripe key in %s (spec 02 §4)",
    (appEnv) => {
      const issues = issuesFor({ ...valid, APP_ENV: appEnv, STRIPE_SECRET_KEY: "sk_live_x" });
      expect(issues).toContain(
        "STRIPE_SECRET_KEY: a live-mode Stripe key is not allowed outside production",
      );
    },
  );

  it("allows a test-mode Stripe key outside production", () => {
    expect(issuesFor({ ...valid, STRIPE_SECRET_KEY: "sk_test_x" })).toHaveLength(0);
  });

  it.each([
    ["sk_test_abc123"],
    ["rk_live_abc123"],
    ["whsec_abc123"],
    ["re_abcdefghijklmnopqrstuvwxyz"],
    ["sb_secret_abc123"],
  ])("rejects secret-like values in NEXT_PUBLIC_ variables (%s)", (value) => {
    const issues = issuesFor({ ...valid, NEXT_PUBLIC_LEAK: value });
    expect(issues).toContain(
      "NEXT_PUBLIC_LEAK: browser-exposed variables must not contain secret values",
    );
  });

  it("never echoes variable values in error messages", () => {
    const secret = "sk_live_DO_NOT_PRINT";
    try {
      parseServerEnv({ ...valid, STRIPE_SECRET_KEY: secret, NEXT_PUBLIC_LEAK: secret });
      expect.unreachable("expected validation to fail");
    } catch (error) {
      expect(String((error as Error).message)).not.toContain(secret);
    }
  });
});

describe("isDesignSystemEnabled", () => {
  it("is disabled in production", () => {
    expect(isDesignSystemEnabled("production")).toBe(false);
  });

  it.each(APP_ENVIRONMENTS.filter((appEnv) => appEnv !== "production"))(
    "remains available in non-production environment %s",
    (appEnv) => {
      expect(isDesignSystemEnabled(appEnv)).toBe(true);
    },
  );
});
