import "server-only";

import { createHash } from "node:crypto";

import type {
  CheckoutSessionObject,
  CreatedObject,
  GatewayResult,
  InvoiceObject,
  PaymentMethodLookup,
  ReconciliationTotals,
  StripeGateway,
  StripeParams,
  StripePriceObject,
} from "./gateway";

/**
 * A deterministic, in-memory Stripe stand-in for development and CI (AUTH-001: "Stripe calls
 * only through a mocked client"). It makes no network request and holds no credential.
 *
 * It models the provider behaviors the WP-B design depends on, as documented in 04 §6.2:
 * the same idempotency key with the same parameters returns the saved result; the same key
 * with different parameters is an error. Prices come from the verified test catalog
 * (04 §6.5). Tests can inject failures, ambiguity, live-mode responses and price drift.
 *
 * A behavior proven only against this mock is NOT verified against Stripe (04 §11): the
 * matching test-mode verification is DEP-06 / DEP-15 under AUTH-002.
 */

const TEST_CATALOG: Record<string, { amount: number; type: "one_time" | "recurring" }> = {
  price_1Uf5HxK5j4r4WkVPkRUJ4gnZ: { amount: 16000, type: "one_time" },
  price_1Uf5HyK5j4r4WkVPfrkvOv7h: { amount: 64000, type: "one_time" },
  price_1Uf5HyK5j4r4WkVPOtk24lGw: { amount: 29900, type: "one_time" },
  price_1Uf5HzK5j4r4WkVPRH6Wkz6D: { amount: 119600, type: "one_time" },
  price_1Uf5HzK5j4r4WkVP35jgGOiy: { amount: 49900, type: "one_time" },
  price_1Uf5I0K5j4r4WkVPZLs7eS9w: { amount: 199600, type: "one_time" },
  price_1Uf5I0K5j4r4WkVPW6smdGo2: { amount: 69900, type: "one_time" },
  price_1Uf5I1K5j4r4WkVPB0lY2MgL: { amount: 279600, type: "one_time" },
  price_1Uf5I1K5j4r4WkVPyCBIiYGP: { amount: 99900, type: "one_time" },
  price_1Uf5I1K5j4r4WkVPDvIUmRD9: { amount: 399600, type: "one_time" },
  price_1Uf5I2K5j4r4WkVPJodSnaBe: { amount: 9900, type: "recurring" },
};

export type MockFault = "failed" | "ambiguous" | "livemode" | null;

export interface MockCall {
  method: string;
  idempotencyKey: string | null;
  params: StripeParams | string;
}

function suffix(key: string): string {
  return createHash("sha256").update(key).digest("hex").slice(0, 16);
}

export class MockStripeGateway implements StripeGateway {
  readonly kind = "mock" as const;
  readonly calls: MockCall[] = [];
  /** The next create returns this fault once, then behaves normally. */
  nextFault: MockFault = null;
  /** Overrides a catalog price amount, to simulate drift (T-PAY-12). */
  readonly priceOverrides = new Map<string, number>();
  readonly totals = new Map<string, ReconciliationTotals>();
  /**
   * The card each Checkout Session or SetupIntent saved. A session the mock created defaults
   * to an attached card on its Customer; tests override this to model a card that was not
   * saved, a different Customer, or a detached card (T-PAY-18, T-PAY-21).
   */
  readonly paymentMethods = new Map<string, PaymentMethodLookup>();
  /** Invoices the mock finalized, with whether automatic collection is still on. */
  readonly invoices = new Map<string, { autoAdvance: boolean; defaultPaymentMethod: unknown }>();
  private readonly saved = new Map<string, { params: string; result: GatewayResult<unknown> }>();

  async retrievePrice(priceId: string): Promise<GatewayResult<StripePriceObject>> {
    this.calls.push({ method: "prices.retrieve", idempotencyKey: null, params: priceId });
    const entry = TEST_CATALOG[priceId];
    if (!entry) return { kind: "failed", httpStatus: 404, code: "resource_missing" };
    return {
      kind: "ok",
      httpStatus: 200,
      object: {
        id: priceId,
        livemode: false,
        active: true,
        currency: "usd",
        unit_amount: this.priceOverrides.get(priceId) ?? entry.amount,
        type: entry.type,
      },
    };
  }

  createCustomer(params: StripeParams, key: string): Promise<GatewayResult<CreatedObject>> {
    return this.create("customers.create", params, key, () => ({
      id: `cus_mock${suffix(key)}`,
      livemode: false,
    }));
  }

  createCheckoutSession(
    params: StripeParams,
    key: string,
  ): Promise<GatewayResult<CheckoutSessionObject>> {
    return this.create("checkout.sessions.create", params, key, () => this.session(params, key));
  }

  createRecoverySession(
    params: StripeParams,
    key: string,
  ): Promise<GatewayResult<CheckoutSessionObject>> {
    if (params.mode !== "setup") {
      return Promise.resolve({ kind: "failed", httpStatus: 400, code: "parameter_invalid" });
    }
    return this.create("checkout.sessions.create[setup]", params, key, () =>
      this.session(params, key),
    );
  }

  /** A SetupIntent completed by a recovery session saves a card on that session's Customer. */
  completeSetupIntent(setupIntentId: string, sessionId: string, paymentMethodId?: string): void {
    const session = this.paymentMethods.get(sessionId);
    this.paymentMethods.set(setupIntentId, {
      payment_method: paymentMethodId ?? `pm_mock${suffix(setupIntentId)}`,
      customer: session?.customer ?? null,
      attached: true,
      livemode: false,
    });
  }

  disableAutomaticCollection(
    invoiceId: string,
    params: StripeParams,
    key: string,
  ): Promise<GatewayResult<CreatedObject>> {
    return this.create("invoices.update", { invoice: invoiceId, ...params }, key, () => {
      const invoice = this.invoices.get(invoiceId);
      if (invoice) invoice.autoAdvance = false;
      return { id: invoiceId, livemode: false };
    });
  }

  async retrieveCheckoutPaymentMethod(
    sessionId: string,
  ): Promise<GatewayResult<PaymentMethodLookup>> {
    return this.lookup("checkout.sessions.retrieve", sessionId);
  }

  async retrieveSetupIntentPaymentMethod(
    setupIntentId: string,
  ): Promise<GatewayResult<PaymentMethodLookup>> {
    return this.lookup("setup_intents.retrieve", setupIntentId);
  }

  private lookup(method: string, id: string): GatewayResult<PaymentMethodLookup> {
    this.calls.push({ method, idempotencyKey: null, params: id });
    const found = this.paymentMethods.get(id);
    return found
      ? { kind: "ok", httpStatus: 200, object: { ...found } }
      : { kind: "failed", httpStatus: 404, code: "resource_missing" };
  }

  private session(params: StripeParams, key: string): CheckoutSessionObject {
    const id = `cs_test_mock${suffix(key)}`;
    // Card only (OI-74): anything else would not yield a reusable card.
    const cardOnly =
      JSON.stringify(params.allowed_payment_method_types ?? params.payment_method_types) ===
      '["card"]';
    this.paymentMethods.set(id, {
      payment_method: cardOnly ? `pm_mock${suffix(id)}` : null,
      customer: typeof params.customer === "string" ? params.customer : null,
      attached: cardOnly,
      livemode: false,
    });
    return {
      id,
      livemode: false,
      url: `https://checkout.stripe.com/c/pay/${id}`,
      expires_at: Math.floor(Date.now() / 1000) + 86_400,
    };
  }

  createFinalBalanceInvoice(
    params: StripeParams,
    key: string,
  ): Promise<GatewayResult<InvoiceObject>> {
    return this.create("invoices.create_finalize_send", params, key, () => {
      const id = `in_mock${suffix(key)}`;
      const lines = (params.lines as Array<{ price: string }> | undefined) ?? [];
      const amount = lines.reduce((sum, line) => sum + (TEST_CATALOG[line.price]?.amount ?? 0), 0);
      this.invoices.set(id, {
        autoAdvance: params.auto_advance === true,
        defaultPaymentMethod: params.default_payment_method ?? null,
      });
      return {
        id,
        livemode: false,
        amount_due: amount,
        hosted_invoice_url: `https://invoice.stripe.com/i/acct_mock/${id}`,
      };
    });
  }

  async reconciliationTotals(input: {
    projectId: string;
    customerId: string;
  }): Promise<GatewayResult<ReconciliationTotals>> {
    this.calls.push({
      method: "reconciliation.totals",
      idempotencyKey: null,
      params: input.projectId,
    });
    const totals = this.totals.get(input.projectId);
    return totals
      ? { kind: "ok", httpStatus: 200, object: totals }
      : { kind: "failed", httpStatus: 404, code: "no_totals" };
  }

  private async create<T extends CreatedObject>(
    method: string,
    params: StripeParams,
    key: string,
    build: () => T,
  ): Promise<GatewayResult<T>> {
    this.calls.push({ method, idempotencyKey: key, params });
    const serialized = JSON.stringify(params);
    const saved = this.saved.get(key);
    if (saved) {
      if (saved.params !== serialized) {
        return { kind: "failed", httpStatus: 400, code: "idempotency_key_in_use" };
      }
      return saved.result as GatewayResult<T>;
    }
    const fault = this.nextFault;
    this.nextFault = null;
    let result: GatewayResult<T>;
    if (fault === "ambiguous") {
      return { kind: "ambiguous", reason: "network_timeout" };
    } else if (fault === "failed") {
      result = { kind: "failed", httpStatus: 400, code: "parameter_invalid" };
    } else {
      const object = build();
      result = {
        kind: "ok",
        httpStatus: 200,
        object: fault === "livemode" ? { ...object, livemode: true } : object,
      };
    }
    this.saved.set(key, { params: serialized, result });
    return result;
  }
}
