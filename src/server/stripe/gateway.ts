import "server-only";

/**
 * The Stripe gateway contract (spec 04 §6.3-§6.4, §8, §10, §17). Every create is made only
 * after its `outbound_stripe_requests` row exists, with that row's idempotency key, and its
 * result is recorded through `public.record_outbound_result`. No implementation here talks
 * to Stripe: under AUTH-001 only the mocked gateway exists. A real test-mode gateway is
 * AUTH-002 work and must keep this contract, including the fail-closed `livemode` rule.
 *
 * Result classification (04 §6.4): `ok` only for a successful response carrying the expected
 * object; `failed` for a definitive rejection (4xx) where Stripe created nothing; `ambiguous`
 * for a network error, timeout, 5xx, or any uncertain outcome. Ambiguous creates are never
 * retried automatically; they are reconciled first.
 *
 * AUTH-009 (OI-91): the executor calls a gateway method only after the claim (which returns a
 * one-time claim token) and a successful `confirm_outbound_dispatch`, and only within 30
 * seconds of starting that confirmation call. A real gateway must bound each provider request
 * at 30 seconds and make no SDK or transport retries (for example `maxNetworkRetries: 0`):
 * once a request may have started, a timeout or cancellation is `ambiguous`, never `failed`.
 * The claim token never reaches the gateway, a log or an error message.
 */

export type GatewayResult<T> =
  | { kind: "ok"; httpStatus: number; object: T }
  | { kind: "failed"; httpStatus: number; code: string }
  | { kind: "ambiguous"; reason: string };

export interface StripePriceObject {
  id: string;
  livemode: boolean;
  active: boolean;
  currency: string;
  unit_amount: number | null;
  type: "one_time" | "recurring";
}

export interface CreatedObject {
  id: string;
  livemode: boolean;
}

export interface CheckoutSessionObject extends CreatedObject {
  url: string;
  expires_at: number;
}

export interface InvoiceObject extends CreatedObject {
  hosted_invoice_url: string;
  amount_due: number;
}

/**
 * The card a completed Checkout Session or SetupIntent saved (04 §8.1, OI-74). `attached`
 * means the payment method is attached to `customer` and reusable off-session. Which Stripe
 * fields carry this, and whether a subscription-mode Checkout attaches the card, is
 * [VERIFY-PROVIDER] under AUTH-002 (DEP-06); the mock models the documented behavior.
 */
export interface PaymentMethodLookup {
  payment_method: string | null;
  customer: string | null;
  attached: boolean;
  livemode: boolean;
}

/** Parameters exactly as the database built them (never from client input). */
export type StripeParams = Record<string, unknown>;

/**
 * A refund or dispute object Stripe holds for the project's Customer, with the charge it
 * belongs to. B1: the daily reconciliation attributes any object WP-B never recorded through
 * this charge and blocks the matching gate until the Owner reviews it.
 */
export interface ReconciliationObject {
  id: string;
  amount: number;
  status: string;
  charge?: string | null;
  payment_intent?: string | null;
  invoice?: string | null;
}

/** Per-project totals and objects used by the daily reconciliation (04 §13). */
export interface ReconciliationTotals {
  charges_cents: number;
  refunds_cents: number;
  open_disputes: number;
  refunds?: ReconciliationObject[];
  disputes?: ReconciliationObject[];
}

export interface StripeGateway {
  /** "mock" never makes a network request. */
  readonly kind: "mock";
  retrievePrice(priceId: string): Promise<GatewayResult<StripePriceObject>>;
  createCustomer(
    params: StripeParams,
    idempotencyKey: string,
  ): Promise<GatewayResult<CreatedObject>>;
  createCheckoutSession(
    params: StripeParams,
    idempotencyKey: string,
  ): Promise<GatewayResult<CheckoutSessionObject>>;
  /**
   * Creates and finalizes the single final-balance invoice (04 §10, OI-74). With
   * `auto_advance: true` and `default_payment_method` set, Stripe attempts the authorized card
   * automatically; otherwise it is paid only on its hosted page.
   */
  createFinalBalanceInvoice(
    params: StripeParams,
    idempotencyKey: string,
  ): Promise<GatewayResult<InvoiceObject>>;
  /** Setup-mode Checkout for a replacement card (04 §8.1). It never charges. */
  createRecoverySession(
    params: StripeParams,
    idempotencyKey: string,
  ): Promise<GatewayResult<CheckoutSessionObject>>;
  /**
   * Turns off automatic collection on an existing invoice (`auto_advance: false`) after a
   * revocation or detachment raced the automatic create. Whether this stops an attempt
   * already scheduled is [VERIFY-PROVIDER] (DEP-06).
   */
  disableAutomaticCollection(
    invoiceId: string,
    params: StripeParams,
    idempotencyKey: string,
  ): Promise<GatewayResult<CreatedObject>>;
  retrieveCheckoutPaymentMethod(sessionId: string): Promise<GatewayResult<PaymentMethodLookup>>;
  retrieveSetupIntentPaymentMethod(
    setupIntentId: string,
  ): Promise<GatewayResult<PaymentMethodLookup>>;
  reconciliationTotals(input: {
    projectId: string;
    customerId: string;
  }): Promise<GatewayResult<ReconciliationTotals>>;
}

export class StripeGatewayUnavailableError extends Error {
  constructor() {
    super(
      "No Stripe gateway is configured. Real Stripe access requires an active AUTH-002 authorization.",
    );
    this.name = "StripeGatewayUnavailableError";
  }
}
