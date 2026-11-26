import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { assertRunnerAllowed, RUNNER_MARKER } from "../support/billing-job-runner";

/**
 * AUTH-008 I-2 seam (a): the billing-job runner runs only on an affirmative `development` or
 * `test` classification, only against the local stack and never with a Stripe credential;
 * and no application route, action or module can reach it.
 */
const LOCAL = {
  NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
  SUPABASE_DB_URL: "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
};

describe("assertRunnerAllowed", () => {
  it.each(["development", "test"])("allows APP_ENV=%s against the local stack", (appEnv) => {
    expect(() => assertRunnerAllowed({ ...LOCAL, APP_ENV: appEnv })).not.toThrow();
  });

  it.each([
    undefined,
    "",
    "production",
    "staging",
    "preview",
    "unknown",
    "Test",
    "DEVELOPMENT",
    " test",
  ])("refuses APP_ENV=%j (fail closed)", (appEnv) => {
    expect(() => assertRunnerAllowed({ ...LOCAL, APP_ENV: appEnv })).toThrow(
      new RegExp(`${RUNNER_MARKER}: refused for APP_ENV=`),
    );
  });

  it.each([
    ["NEXT_PUBLIC_SUPABASE_URL", "https://abcdefgh.supabase.co"],
    ["SUPABASE_DB_URL", "postgresql://postgres:x@db.abcdefgh.supabase.co:5432/postgres"],
    ["SUPABASE_DB_URL", "not a url"],
  ])("refuses a non-local %s", (name, value) => {
    expect(() => assertRunnerAllowed({ ...LOCAL, APP_ENV: "test", [name]: value })).toThrow(
      new RegExp(RUNNER_MARKER),
    );
  });

  it("refuses when a Stripe credential is present", () => {
    expect(() =>
      assertRunnerAllowed({ ...LOCAL, APP_ENV: "test", STRIPE_SECRET_KEY: "sk_test_x" }),
    ).toThrow(/Stripe credential/);
  });
});

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? files(path) : [path];
  });
}

describe("static isolation: no application code reaches the runner", () => {
  const sources = files("src").filter((f) => /\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f));

  it("scans the application source", () => {
    expect(sources.length).toBeGreaterThan(50);
  });

  it("no route, action or module under src/ imports the runner or any test support module", () => {
    const offenders = sources.filter((file) => {
      const text = readFileSync(file, "utf8");
      return (
        /billing-job-runner/.test(text) ||
        /from\s+["'][^"']*tests\/support/.test(text) ||
        /import\(\s*["'][^"']*tests\/support/.test(text)
      );
    });
    expect(offenders).toEqual([]);
  });

  it("the runner's job file is outside the unit and integration suites", () => {
    const unit = readFileSync("vitest.config.mts", "utf8");
    const integration = readFileSync("vitest.integration.config.mts", "utf8");
    expect(unit).toContain('include: ["tests/unit/**/*.test.{ts,tsx}"]');
    expect(integration).toContain('include: ["tests/integration/**/*.test.ts"]');
    const runner = readFileSync("tests/support/billing-job-runner.config.mts", "utf8");
    expect(runner).toContain('include: ["tests/support/billing-job-runner.job.ts"]');
  });

  it("the runner uses only the in-memory mocked gateway", () => {
    const job = readFileSync("tests/support/billing-job-runner.job.ts", "utf8");
    expect(job).toContain("new MockStripeGateway()");
    expect(job).not.toMatch(/@\/server\/stripe["']|getStripeGateway|stripe\/index/);
  });
});
