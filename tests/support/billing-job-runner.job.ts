import { writeFileSync } from "node:fs";

import { expect, it, vi } from "vitest";

import { assertRunnerAllowed, RUNNER_MARKER } from "./billing-job-runner";

/**
 * The subprocess side of the billing-job runner (AUTH-008 I-2, seam (a)); run only through
 * `billing-job-runner.config.mts` by `runBillingJobsOnce()`. One pass of the existing
 * `runBillingJobs` service against the local stack with the in-memory mocked gateway.
 */
vi.mock("@/server/supabase/admin", async () => {
  const support = await import("./local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

it(`${RUNNER_MARKER}: one pass of runBillingJobs`, async () => {
  assertRunnerAllowed(process.env);
  const output = process.env.WPI_BILLING_JOB_RUNNER_OUTPUT;
  expect(output, "WPI_BILLING_JOB_RUNNER_OUTPUT").toBeTruthy();
  const { adminClient } = await import("./local-supabase");
  const { runBillingJobs } = await import("@/server/services/billing");
  const { MockStripeGateway } = await import("@/server/stripe/mock-gateway");
  const gateway = new MockStripeGateway();
  const result = await runBillingJobs(adminClient(), gateway);
  writeFileSync(
    output!,
    JSON.stringify({
      ok: result.ok,
      jobs: result.ok ? result.jobs : {},
      requestsExecuted: result.ok ? result.requestsExecuted : 0,
      gatewayCalls: gateway.calls.map((c) => c.method),
    }),
  );
  expect(result.ok).toBe(true);
});
