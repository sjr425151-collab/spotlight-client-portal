import type { SupabaseClient } from "@supabase/supabase-js";
import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));
vi.mock("@/server/supabase/admin", () => ({ createAdminClient: vi.fn() }));

import {
  executeOutboundRequest,
  handleStripeWebhook,
  runPaymentMethodLookups,
} from "@/server/services/billing";
import { MockStripeGateway } from "@/server/stripe/mock-gateway";
import { computeSignature } from "@/server/stripe/webhook-signature";

/**
 * WP-B service behavior with a recording fake database client and the mocked gateway
 * (no Stripe request, no database). The database-side guarantees are proven by pgTAP
 * 100-120 and the integration tests; these prove the server-side steps around them.
 */

type Call = { fn: string; args: Record<string, unknown> };

function fakeDb(responses: Record<string, unknown | ((args: Record<string, unknown>) => unknown)>) {
  const calls: Call[] = [];
  const client = {
    rpc: async (fn: string, args: Record<string, unknown> = {}) => {
      calls.push({ fn, args });
      const raw = responses[fn];
      // An array answers successive calls in order (the last answer repeats).
      const response = Array.isArray(raw)
        ? raw[Math.min(calls.filter((c) => c.fn === fn).length - 1, raw.length - 1)]
        : raw;
      if (response instanceof Error) return { data: null, error: { message: response.message } };
      return { data: typeof response === "function" ? response(args) : response, error: null };
    },
  } as unknown as SupabaseClient;
  return { client, calls };
}

const secret = `whsec_${crypto.randomUUID().replace(/-/g, "")}`;
const now = Math.floor(Date.now() / 1000);
const event = JSON.stringify({
  id: "evt_unit0000001",
  object: "event",
  type: "invoice.paid",
  livemode: false,
  created: now,
  data: { object: { id: "in_x" } },
});
const signed = (body: string) => `t=${now},v1=${computeSignature(secret, now, body)}`;

describe("handleStripeWebhook (04 §11, §17 #4)", () => {
  it("T-PAY-03: an invalid signature is rejected with 400 before any database call", async () => {
    const db = fakeDb({});
    const result = await handleStripeWebhook({
      rawBody: event,
      signatureHeader: `t=${now},v1=${"0".repeat(64)}`,
      secret,
      admin: db.client,
    });
    expect(result.status).toBe(400);
    expect(db.calls).toEqual([]);
  });

  it("T-ARC-01: acknowledges only after the durable insert, then processes", async () => {
    const db = fakeDb({
      ingest_stripe_event: { ok: true, webhook_event_id: 7, duplicate: false },
      process_stripe_event: { ok: true },
    });
    const result = await handleStripeWebhook({
      rawBody: event,
      signatureHeader: signed(event),
      secret,
      admin: db.client,
    });
    expect(result).toEqual({ status: 200, body: { received: true, duplicate: false } });
    expect(db.calls.map((c) => c.fn)).toEqual(["ingest_stripe_event", "process_stripe_event"]);
    expect(db.calls[0]!.args.p_raw_body_sha256).toMatch(/^[0-9a-f]{64}$/);
  });

  it("T-ARC-01: a storage failure returns 500 so Stripe retries", async () => {
    const db = fakeDb({ ingest_stripe_event: new Error("connection refused") });
    const result = await handleStripeWebhook({
      rawBody: event,
      signatureHeader: signed(event),
      secret,
      admin: db.client,
    });
    expect(result.status).toBe(500);
    expect(db.calls.map((c) => c.fn)).toEqual(["ingest_stripe_event"]);
  });

  it("T-PAY-05: a duplicate is acknowledged without reprocessing", async () => {
    const db = fakeDb({ ingest_stripe_event: { ok: true, webhook_event_id: 7, duplicate: true } });
    const result = await handleStripeWebhook({
      rawBody: event,
      signatureHeader: signed(event),
      secret,
      admin: db.client,
    });
    expect(result.body.duplicate).toBe(true);
    expect(db.calls.map((c) => c.fn)).toEqual(["ingest_stripe_event"]);
  });

  it("T-PAY-08: a database livemode rejection is a 400", async () => {
    const db = fakeDb({ ingest_stripe_event: { ok: false, error: "livemode_mismatch" } });
    const result = await handleStripeWebhook({
      rawBody: event,
      signatureHeader: signed(event),
      secret,
      admin: db.client,
    });
    expect(result).toEqual({ status: 400, body: { received: false, error: "livemode_mismatch" } });
  });

  it("T-ARC-02: a processing error after storage still acknowledges (the stored event is retried)", async () => {
    const db = fakeDb({
      ingest_stripe_event: { ok: true, webhook_event_id: 9, duplicate: false },
      process_stripe_event: new Error("boom"),
    });
    const result = await handleStripeWebhook({
      rawBody: event,
      signatureHeader: signed(event),
      secret,
      admin: db.client,
    });
    expect(result.status).toBe(200);
  });
});

const checkoutRow = {
  ok: true,
  id: "11111111-1111-4111-8111-111111111111",
  purpose: "checkout_session_create",
  idempotency_key: "wpb-checkout-22222222-2222-4222-8222-222222222222-c1-a1",
  customer: "cus_TestA000001",
  expected_livemode: false,
  params: {
    mode: "subscription",
    allowed_payment_method_types: ["card"],
    payment_method_collection: "always",
    line_items: [
      { price: "price_1Uf5HyK5j4r4WkVPOtk24lGw", quantity: 1 },
      { price: "price_1Uf5I2K5j4r4WkVPJodSnaBe", quantity: 1 },
    ],
    discounts: [],
    allow_promotion_codes: false,
    automatic_tax: { enabled: false },
    expected_amount_total: 39800,
    metadata: { project_id: "p" },
  },
};
const urls = { successUrl: "http://localhost:3000/ok", cancelUrl: "http://localhost:3000/cancel" };

describe("executeOutboundRequest (04 §6.3-§6.4, §7, §17 #2)", () => {
  it("sends the database-built parameters with the derived key, and records the result", async () => {
    const gateway = new MockStripeGateway();
    const db = fakeDb({
      outbound_request_for_execution: checkoutRow,
      record_outbound_result: { ok: true, status: "succeeded" },
    });
    expect((await executeOutboundRequest(db.client, gateway, checkoutRow.id, urls)).ok).toBe(true);
    const create = gateway.calls.find((c) => c.method === "checkout.sessions.create")!;
    expect(create.idempotencyKey).toBe(checkoutRow.idempotency_key);
    expect(create.params).toEqual({
      mode: "subscription",
      allowed_payment_method_types: ["card"],
      payment_method_collection: "always",
      line_items: checkoutRow.params.line_items,
      discounts: [],
      allow_promotion_codes: false,
      automatic_tax: { enabled: false },
      metadata: { project_id: "p" },
      customer: "cus_TestA000001",
      success_url: urls.successUrl,
      cancel_url: urls.cancelUrl,
    });
    const recorded = db.calls.find((c) => c.fn === "record_outbound_result")!.args;
    expect(recorded.p_outcome).toBe("succeeded");
    expect(recorded.p_livemode).toBe(false);
    expect(String(recorded.p_stripe_object_id)).toMatch(/^cs_test_/);
  });

  it("T-PAY-12: a Stripe price that drifted from the snapshot blocks the create", async () => {
    const gateway = new MockStripeGateway();
    gateway.priceOverrides.set("price_1Uf5HyK5j4r4WkVPOtk24lGw", 29901);
    const db = fakeDb({
      outbound_request_for_execution: checkoutRow,
      record_outbound_result: { ok: true },
    });
    expect(await executeOutboundRequest(db.client, gateway, checkoutRow.id, urls)).toEqual({
      ok: false,
      error: "price_verification_failed",
    });
    expect(gateway.calls.some((c) => c.method === "checkout.sessions.create")).toBe(false);
    expect(db.calls.find((c) => c.fn === "record_outbound_result")!.args).toMatchObject({
      p_outcome: "failed",
      p_error_code: "price_verification_failed",
    });
  });

  it("04 §6.4: an ambiguous outcome is recorded once and never retried automatically", async () => {
    const gateway = new MockStripeGateway();
    gateway.nextFault = "ambiguous";
    const db = fakeDb({
      outbound_request_for_execution: checkoutRow,
      record_outbound_result: { ok: true },
    });
    expect(await executeOutboundRequest(db.client, gateway, checkoutRow.id, urls)).toEqual({
      ok: false,
      error: "reconciliation_required",
    });
    expect(gateway.calls.filter((c) => c.method === "checkout.sessions.create")).toHaveLength(1);
    expect(db.calls.find((c) => c.fn === "record_outbound_result")!.args.p_outcome).toBe(
      "ambiguous",
    );
  });

  it("04 §6.3: a live-mode response is passed through so the database aborts it", async () => {
    const gateway = new MockStripeGateway();
    gateway.nextFault = "livemode";
    const db = fakeDb({
      outbound_request_for_execution: checkoutRow,
      record_outbound_result: { ok: false, error: "livemode_mismatch" },
    });
    expect(await executeOutboundRequest(db.client, gateway, checkoutRow.id, urls)).toEqual({
      ok: false,
      error: "livemode_mismatch",
    });
    expect(db.calls.find((c) => c.fn === "record_outbound_result")!.args.p_livemode).toBe(true);
  });

  it("the mock enforces idempotency: same key and parameters return the saved object; different parameters fail", async () => {
    const gateway = new MockStripeGateway();
    const first = await gateway.createCustomer({ name: "A" }, "wpb-customer-k-a1");
    const again = await gateway.createCustomer({ name: "A" }, "wpb-customer-k-a1");
    const changed = await gateway.createCustomer({ name: "B" }, "wpb-customer-k-a1");
    expect(again).toEqual(first);
    expect(changed).toEqual({ kind: "failed", httpStatus: 400, code: "idempotency_key_in_use" });
  });

  it("refuses to use the mock where the database expects live mode", async () => {
    const db = fakeDb({
      outbound_request_for_execution: { ...checkoutRow, expected_livemode: true },
    });
    expect(
      await executeOutboundRequest(db.client, new MockStripeGateway(), checkoutRow.id, urls),
    ).toEqual({ ok: false, error: "mode_mismatch" });
  });
});

const finalRow = (auto: boolean) => ({
  ok: true,
  id: auto ? "33333333-3333-4333-8333-333333333333" : "44444444-4444-4444-8444-444444444444",
  purpose: "final_balance_invoice_create",
  idempotency_key: `wpb-final-balance-os-ap-a${auto ? 1 : 2}`,
  customer: "cus_TestA000001",
  expected_livemode: false,
  params: {
    collection_method: "charge_automatically",
    auto_advance: auto,
    ...(auto ? { default_payment_method: "pm_TestCard0001" } : {}),
    lines: [{ price: "price_1Uf5HzK5j4r4WkVPRH6Wkz6D", quantity: 1 }],
    discounts: [],
    automatic_tax: { enabled: false },
    expected_amount_due: 119600,
    metadata: { project_id: "p", payment_consent_id: "a" },
  },
});

describe("OI-74 executor behavior (04 §8.1, §10)", () => {
  it("refuses a Checkout that is not card-only before anything is sent", async () => {
    const gateway = new MockStripeGateway();
    const db = fakeDb({
      outbound_request_for_execution: {
        ...checkoutRow,
        params: {
          ...checkoutRow.params,
          allowed_payment_method_types: ["card", "us_bank_account"],
        },
      },
      record_outbound_result: { ok: true },
    });
    expect(await executeOutboundRequest(db.client, gateway, checkoutRow.id, urls)).toEqual({
      ok: false,
      error: "payment_method_types_invalid",
    });
    expect(gateway.calls).toEqual([]);
    expect(db.calls.find((c) => c.fn === "record_outbound_result")!.args).toMatchObject({
      p_outcome: "failed",
      p_error_code: "payment_method_types_invalid",
    });
  });

  it("T-PAY-19: an automatic create sends the authorized card and auto_advance unchanged", async () => {
    const gateway = new MockStripeGateway();
    const row = finalRow(true);
    const db = fakeDb({
      outbound_request_for_execution: row,
      record_outbound_result: { ok: true, status: "succeeded" },
    });
    expect((await executeOutboundRequest(db.client, gateway, row.id)).ok).toBe(true);
    const sent = gateway.calls.find((c) => c.method === "invoices.create_finalize_send")!;
    expect(sent.params).toEqual({
      collection_method: "charge_automatically",
      auto_advance: true,
      default_payment_method: "pm_TestCard0001",
      lines: row.params.lines,
      discounts: [],
      automatic_tax: { enabled: false },
      metadata: { project_id: "p", payment_consent_id: "a" },
      customer: "cus_TestA000001",
    });
  });

  it("T-PAY-21: a superseded automatic create is never sent; the hosted-only attempt runs instead", async () => {
    const gateway = new MockStripeGateway();
    const hosted = finalRow(false);
    const db = fakeDb({
      outbound_request_for_execution: [
        { ok: false, error: "superseded", next_request_id: hosted.id },
        hosted,
      ],
      record_outbound_result: { ok: true, status: "succeeded" },
    });
    expect((await executeOutboundRequest(db.client, gateway, finalRow(true).id)).ok).toBe(true);
    expect(
      db.calls.filter((c) => c.fn === "outbound_request_for_execution").map((c) => c.args),
    ).toEqual([{ p_request_id: finalRow(true).id }, { p_request_id: hosted.id }]);
    const sent = gateway.calls.filter((c) => c.method === "invoices.create_finalize_send");
    expect(sent).toHaveLength(1);
    expect(sent[0]!.idempotencyKey).toBe(hosted.idempotency_key);
    expect(sent[0]!.params).toMatchObject({ auto_advance: false });
    expect(sent[0]!.params).not.toHaveProperty("default_payment_method");
  });

  it("stops automatic collection on an existing invoice with auto_advance false only", async () => {
    const gateway = new MockStripeGateway();
    const db = fakeDb({
      outbound_request_for_execution: {
        ok: true,
        id: "55555555-5555-4555-8555-555555555555",
        purpose: "final_balance_invoice_disable_auto",
        idempotency_key: "wpb-final-balance-stop-f-a1",
        customer: null,
        expected_livemode: false,
        params: { invoice: "in_TestInvoice01", auto_advance: false },
      },
      record_outbound_result: { ok: true, status: "succeeded" },
    });
    expect((await executeOutboundRequest(db.client, gateway, "x")).ok).toBe(true);
    expect(gateway.calls).toEqual([
      {
        method: "invoices.update",
        idempotencyKey: "wpb-final-balance-stop-f-a1",
        params: { invoice: "in_TestInvoice01", auto_advance: false },
      },
    ]);
  });

  it("recovery opens a setup-mode, card-only session on the client's Customer", async () => {
    const gateway = new MockStripeGateway();
    const db = fakeDb({
      outbound_request_for_execution: {
        ok: true,
        id: "66666666-6666-4666-8666-666666666666",
        purpose: "recovery_session_create",
        idempotency_key: "wpb-recovery-r-a1",
        customer: "cus_TestA000001",
        expected_livemode: false,
        params: { mode: "setup", allowed_payment_method_types: ["card"], metadata: { p: 1 } },
      },
      record_outbound_result: { ok: true, status: "succeeded" },
    });
    expect((await executeOutboundRequest(db.client, gateway, "x", urls)).ok).toBe(true);
    expect(gateway.calls.map((c) => c.method)).toEqual(["checkout.sessions.create[setup]"]);
    expect(gateway.calls[0]!.params).toEqual({
      mode: "setup",
      allowed_payment_method_types: ["card"],
      metadata: { p: 1 },
      customer: "cus_TestA000001",
      success_url: urls.successUrl,
      cancel_url: urls.cancelUrl,
    });
  });
});

describe("runPaymentMethodLookups (04 §8.1, 04 §13 single-flight)", () => {
  it("does nothing when another run holds the job", async () => {
    const gateway = new MockStripeGateway();
    const db = fakeDb({ begin_billing_job: null });
    expect(await runPaymentMethodLookups(db.client, gateway)).toEqual({
      ok: true,
      skipped: true,
      recorded: 0,
    });
    expect(gateway.calls).toEqual([]);
    expect(db.calls.map((c) => c.fn)).toEqual(["begin_billing_job"]);
  });

  it("records what Stripe reports for each due record, then finishes the run", async () => {
    const gateway = new MockStripeGateway();
    gateway.paymentMethods.set("cs_test_lookup01", {
      payment_method: "pm_TestCard0001",
      customer: "cus_TestA000001",
      attached: true,
      livemode: false,
    });
    const db = fakeDb({
      begin_billing_job: "77777777-7777-4777-8777-777777777777",
      payment_method_lookups_due: {
        ok: true,
        initial: [{ record_id: "r1", stripe_checkout_session_id: "cs_test_lookup01" }],
        recovery: [{ record_id: "r2", stripe_setup_intent_id: "seti_unknown01" }],
      },
      record_payment_method_lookup: { ok: true, established: true },
      finish_billing_job: { ok: true },
    });
    expect(await runPaymentMethodLookups(db.client, gateway)).toEqual({
      ok: true,
      skipped: false,
      recorded: 1,
    });
    expect(db.calls.find((c) => c.fn === "record_payment_method_lookup")!.args).toEqual({
      p_kind: "initial",
      p_record_id: "r1",
      p_payment_method_id: "pm_TestCard0001",
      p_customer_id: "cus_TestA000001",
      p_livemode: false,
      p_attached: true,
    });
    // The unknown SetupIntent is left for the next run, not recorded as anything.
    expect(db.calls.filter((c) => c.fn === "record_payment_method_lookup")).toHaveLength(1);
    expect(db.calls.at(-1)).toEqual({
      fn: "finish_billing_job",
      args: {
        p_run_id: "77777777-7777-4777-8777-777777777777",
        p_result: { recorded: 1, failed: 1 },
      },
    });
  });
});
