import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type * as EnvironmentConsistency from "@/server/environment-consistency";

vi.mock("server-only", () => ({}));

/**
 * OI-115 / OI-119 (AUTH-016): no test seam activates when APP_ENV and the database disagree,
 * and none activates at all in preview, staging or production.
 * - Point 2: `getStripeGateway()` awaits the environment check before the mock exists, so a
 *   failed check prevents gateway acquisition; the billing actions and the webhook route then
 *   never reach a gateway, an outbound claim or a dispatch confirmation.
 * - Point 1: in preview, staging and production the scanner and live verifier select no stub,
 *   and the environment schema refuses the mocked gateway.
 */

const state = vi.hoisted(() => ({
  appEnv: "test",
  gateway: "mock" as "mock" | "disabled",
  check: vi.fn<() => Promise<void>>(),
  mockConstructed: 0,
}));

vi.mock("@/config/env", () => ({
  get env() {
    return {
      APP_ENV: state.appEnv,
      STRIPE_GATEWAY: state.gateway,
      NEXT_PUBLIC_SITE_URL: "http://localhost:3000",
      STRIPE_WEBHOOK_SECRET: "whsec_test_placeholder",
    };
  },
}));

vi.mock("@/server/environment-consistency", async (importOriginal) => {
  const real = await importOriginal<typeof EnvironmentConsistency>();
  return { ...real, assertEnvironmentConsistent: () => state.check() };
});

vi.mock("@/server/stripe/mock-gateway", () => ({
  MockStripeGateway: class {
    readonly kind = "mock";
    readonly calls: unknown[] = [];
    constructor() {
      state.mockConstructed += 1;
    }
  },
}));

const billing = vi.hoisted(() => ({
  startInitialCheckoutAsCaller: vi.fn(),
  beginPaymentMethodRecoveryAsCaller: vi.fn(),
  receiveStripeWebhook: vi.fn(async () => ({ status: 200, body: { received: true } })),
}));
vi.mock("@/server/services/billing", () => ({
  acceptAgreement: vi.fn(),
  revokePaymentAuthorization: vi.fn(),
  ...billing,
}));
vi.mock("@/server/auth/guards", () => ({ requireClient: vi.fn(async () => ({})) }));
vi.mock("@/server/supabase/clients", () => ({ createUserClient: vi.fn(async () => ({})) }));
vi.mock("next/navigation", () => ({
  redirect: vi.fn((to: string) => {
    throw new Error(`redirect:${to}`);
  }),
}));

import { EnvironmentInconsistentError } from "@/server/environment-consistency";

const holder = globalThis as typeof globalThis & { __spotlightMockStripeGateway?: unknown };
const PROJECT = "00000000-0000-4000-8000-000000000123";
const form = () => {
  const data = new FormData();
  data.set("projectId", PROJECT);
  return data;
};
const refuse = () => Promise.reject(new EnvironmentInconsistentError("APP_ENV=test; c1=null"));

beforeEach(() => {
  state.appEnv = "test";
  state.gateway = "mock";
  state.mockConstructed = 0;
  state.check.mockReset();
  delete holder.__spotlightMockStripeGateway;
  vi.clearAllMocks();
});
afterEach(() => {
  delete holder.__spotlightMockStripeGateway;
});

describe("getStripeGateway (point 2)", () => {
  it("a failed environment check rejects before the mock gateway exists", async () => {
    state.check.mockImplementation(refuse);
    const { getStripeGateway } = await import("@/server/stripe");
    await expect(getStripeGateway()).rejects.toBeInstanceOf(EnvironmentInconsistentError);
    expect(state.check).toHaveBeenCalledTimes(1);
    expect(state.mockConstructed).toBe(0);
    expect(holder.__spotlightMockStripeGateway).toBeUndefined();
  });

  it("an agreeing classification returns the one mock gateway", async () => {
    state.check.mockResolvedValue(undefined);
    const { getStripeGateway } = await import("@/server/stripe");
    const first = await getStripeGateway();
    expect(first.kind).toBe("mock");
    expect(await getStripeGateway()).toBe(first);
    expect(state.mockConstructed).toBe(1);
    expect(state.check).toHaveBeenCalledTimes(2);
  });

  it("with no gateway configured it fails closed as before, without reading the classification", async () => {
    state.gateway = "disabled";
    const { getStripeGateway, StripeGatewayUnavailableError } = await import("@/server/stripe");
    await expect(getStripeGateway()).rejects.toBeInstanceOf(StripeGatewayUnavailableError);
    expect(state.check).not.toHaveBeenCalled();
    expect(state.mockConstructed).toBe(0);
  });
});

describe("billing actions and webhook route with a failed check (point 2)", () => {
  it("startCheckoutAction stops before any checkout, claim or dispatch", async () => {
    state.check.mockImplementation(refuse);
    const { startCheckoutAction } =
      await import("@/app/portal/projects/[projectId]/billing/actions");
    await expect(startCheckoutAction(form())).rejects.toBeInstanceOf(EnvironmentInconsistentError);
    expect(billing.startInitialCheckoutAsCaller).not.toHaveBeenCalled();
    expect(state.mockConstructed).toBe(0);
  });

  it("beginRecoveryAction stops before any recovery session, claim or dispatch", async () => {
    state.check.mockImplementation(refuse);
    const { beginRecoveryAction } =
      await import("@/app/portal/projects/[projectId]/billing/actions");
    await expect(beginRecoveryAction(form())).rejects.toBeInstanceOf(EnvironmentInconsistentError);
    expect(billing.beginPaymentMethodRecoveryAsCaller).not.toHaveBeenCalled();
    expect(state.mockConstructed).toBe(0);
  });

  it("the webhook route still verifies and stores the event, but with no gateway", async () => {
    state.check.mockImplementation(refuse);
    const { POST } = await import("@/app/api/stripe/webhook/route");
    const response = await POST(
      new Request("http://localhost/api/stripe/webhook", {
        method: "POST",
        body: "{}",
        headers: { "stripe-signature": "t=1,v1=placeholder" },
      }),
    );
    expect(response.status).toBe(200);
    expect(billing.receiveStripeWebhook).toHaveBeenCalledTimes(1);
    expect(billing.receiveStripeWebhook.mock.calls[0]).toEqual([
      "{}",
      "t=1,v1=placeholder",
      "whsec_test_placeholder",
      null,
    ]);
    expect(state.mockConstructed).toBe(0);
  });

  it("with an agreeing classification the action passes the mock gateway on unchanged", async () => {
    state.check.mockResolvedValue(undefined);
    billing.startInitialCheckoutAsCaller.mockResolvedValue({
      ok: true,
      url: "https://checkout.test/x",
    });
    const { startCheckoutAction } =
      await import("@/app/portal/projects/[projectId]/billing/actions");
    await expect(startCheckoutAction(form())).rejects.toThrow("redirect:https://checkout.test/x");
    expect(billing.startInitialCheckoutAsCaller).toHaveBeenCalledTimes(1);
    expect(
      (billing.startInitialCheckoutAsCaller.mock.calls[0] as unknown[])[1] as { kind: string },
    ).toMatchObject({ kind: "mock" });
  });
});

describe("no seam activates in preview, staging or production (point 1)", () => {
  const base = {
    NEXT_PUBLIC_SITE_URL: "https://portal.example.com",
    NEXT_PUBLIC_SUPABASE_URL: "https://abcdefghijklmnopqrst.supabase.co",
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_placeholder",
    SUPABASE_SECRET_KEY: "sb_secret_placeholder",
  };
  for (const appEnv of ["preview", "staging", "production"]) {
    it(`${appEnv}: no mock scanner, no stub verifier, and the mock gateway is refused`, async () => {
      const { scannerFor } = await import("@/server/uploads/scanner");
      const { verifierFor, observeLiveSite } = await import("@/server/publication/verifier");
      const { parseServerEnv } = await import("@/config/env-schema");
      expect(scannerFor(appEnv)).toBeNull();
      // The real verifier fetches; the stub would answer a reserved .test host successfully.
      const fetchSpy = vi.spyOn(globalThis, "fetch").mockRejectedValue(new TypeError("no network"));
      const observed = await verifierFor(appEnv)(
        "https://" + "a".repeat(40) + ".live.example.test/",
      );
      expect(observed).toEqual(
        await observeLiveSite("https://unreachable.example.test/", async () => {
          throw new TypeError("no network");
        }),
      );
      expect(fetchSpy).toHaveBeenCalled();
      const source =
        appEnv === "preview"
          ? { ...base, NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321" }
          : base;
      expect(() =>
        parseServerEnv({ ...source, APP_ENV: appEnv, STRIPE_GATEWAY: "mock" }),
      ).toThrow();
      expect(() => parseServerEnv({ ...source, APP_ENV: appEnv })).not.toThrow();
    });
  }
});
