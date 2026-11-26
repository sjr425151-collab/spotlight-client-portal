import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

/**
 * Billing-job runner (AUTH-008 I-2, seam (a)): one pass of the existing `runBillingJobs`
 * service (04 §13), started by the R1 browser suite as a subprocess through the existing
 * Vitest tooling (`billing-job-runner.config.mts` runs `billing-job-runner.job.ts`). It is a
 * test harness: no application route, action or module imports it (static check in
 * tests/unit/wpi-billing-job-runner.test.ts), and it is not part of any build.
 *
 * It runs only on an affirmative `development` or `test` classification and only against the
 * local Supabase stack, with the in-memory mocked Stripe gateway: no credential and no
 * provider request. Any other classification, including a missing or unknown one, `preview`,
 * `staging` and `production`, is refused before anything runs.
 */

export const RUNNER_MARKER = "wpi-billing-job-runner";

const ALLOWED_ENVIRONMENTS = new Set(["development", "test"]);
const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost"]);

/** Throws unless the environment affirmatively allows the runner (fail closed). */
export function assertRunnerAllowed(environment: Record<string, string | undefined>): void {
  const appEnv = environment.APP_ENV;
  if (appEnv === undefined || !ALLOWED_ENVIRONMENTS.has(appEnv)) {
    throw new Error(
      `${RUNNER_MARKER}: refused for APP_ENV=${JSON.stringify(appEnv ?? null)}; ` +
        "only development and test may run billing jobs from the test harness",
    );
  }
  for (const name of ["NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_DB_URL"]) {
    const value = environment[name];
    if (value === undefined) continue;
    let host = "";
    try {
      host = new URL(value).hostname;
    } catch {
      throw new Error(`${RUNNER_MARKER}: ${name} is not a URL`);
    }
    if (!LOCAL_HOSTS.has(host)) {
      throw new Error(`${RUNNER_MARKER}: ${name} must point at the local Supabase stack`);
    }
  }
  if (environment.STRIPE_SECRET_KEY) {
    throw new Error(`${RUNNER_MARKER}: refused with a Stripe credential in the environment`);
  }
}

export type RunnerResult = {
  ok: boolean;
  jobs: Record<string, unknown>;
  requestsExecuted: number;
  gatewayCalls: string[];
};

/** Runs one pass of the billing jobs in a subprocess and returns its result. */
export function runBillingJobsOnce(): RunnerResult {
  if (!process.env.APP_ENV && existsSync(".env.local")) process.loadEnvFile(".env.local");
  assertRunnerAllowed(process.env);
  const dir = mkdtempSync(join(tmpdir(), `${RUNNER_MARKER}-`));
  const output = join(dir, "result.json");
  try {
    const run = spawnSync(
      "pnpm",
      ["exec", "vitest", "run", "--config", "tests/support/billing-job-runner.config.mts"],
      {
        encoding: "utf8",
        env: { ...process.env, WPI_BILLING_JOB_RUNNER_OUTPUT: output },
        timeout: 120_000,
      },
    );
    if (run.status !== 0 || !existsSync(output)) {
      throw new Error(
        `${RUNNER_MARKER}: the billing-job pass failed (exit ${run.status}, signal ${run.signal}):\n` +
          `${run.stdout}\n${run.stderr}`,
      );
    }
    return JSON.parse(readFileSync(output, "utf8")) as RunnerResult;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
