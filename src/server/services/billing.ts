import "server-only";

import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";

import type { GatewayResult, StripeGateway, StripeParams } from "@/server/stripe/gateway";
import { createAdminClient } from "@/server/supabase/admin";
import { verifyStripeSignature } from "@/server/stripe/webhook-signature";

/**
 * WP-B billing services (spec 04 §3, §8, §10-§13, §17). Authorization lives in the database
 * functions; these services orchestrate. Two clients are used:
 * - the user client (RLS and the definer functions authorize the caller), and
 * - the admin client, only for server-only steps (recording Stripe results, ingesting
 *   webhooks, jobs) and only after the caller was authorized (03 §9.1 rule 6).
 * The gateway is the mocked client under AUTH-001; no Stripe request is made.
 */

export type ServiceResult<T = Record<string, unknown>> =
  ({ ok: true } & T) | { ok: false; error: string };

const uuid = z.uuid();

export const acceptAgreementSchema = z.object({
  orderSummaryId: uuid,
  // Explicit true only (T-AGR-01, T-AGR-06): an absent checkbox is false.
  accepted: z.literal(true),
  authorityConfirmed: z.literal(true),
  signerFullLegalName: z.string().trim().min(1).max(200),
  businessLegalName: z.string().trim().min(1).max(200),
  signerTitle: z.string().trim().min(1).max(200),
  // The form renders both checkboxes unchecked and reports that state (04 §3).
  checkboxUncheckedByDefault: z.literal(true),
});
export type AcceptAgreementInput = z.infer<typeof acceptAgreementSchema>;

function rpcResult(data: unknown, error: { message?: string } | null): ServiceResult {
  if (error || !data || typeof data !== "object") return { ok: false, error: "unavailable" };
  const row = data as { ok?: boolean; error?: string } & Record<string, unknown>;
  return row.ok
    ? (row as { ok: true } & Record<string, unknown>)
    : { ok: false, error: row.error ?? "unavailable" };
}

export async function acceptAgreement(db: SupabaseClient, input: unknown): Promise<ServiceResult> {
  const parsed = acceptAgreementSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "explicit_acceptance_required" };
  const v = parsed.data;
  const { data, error } = await db.rpc("accept_agreement", {
    p_order_summary_id: v.orderSummaryId,
    p_accepted: v.accepted,
    p_authority_confirmed: v.authorityConfirmed,
    p_signer_full_legal_name: v.signerFullLegalName,
    p_business_legal_name: v.businessLegalName,
    p_signer_title: v.signerTitle,
    p_checkbox_unchecked_by_default: v.checkboxUncheckedByDefault,
  });
  return rpcResult(data, error);
}

export const issueOrderSummarySchema = z.object({
  projectId: uuid,
  packageKey: z.enum(["essential", "professional", "advanced", "signature", "prestige"]),
  scopeItems: z.array(z.string().trim().min(1).max(300)).max(50),
  projectNotes: z.string().trim().max(2000).optional(),
  changeReason: z.string().trim().max(1000).optional(),
});

export async function issueOrderSummary(
  db: SupabaseClient,
  input: unknown,
): Promise<ServiceResult> {
  const parsed = issueOrderSummarySchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "invalid_input" };
  const v = parsed.data;
  const { data, error } = await db.rpc("issue_order_summary", {
    p_project_id: v.projectId,
    p_package_key: v.packageKey,
    p_scope_items: v.scopeItems,
    p_project_notes: v.projectNotes || null,
    p_change_reason: v.changeReason || null,
  });
  return rpcResult(data, error);
}

// ---------------------------------------------------------------------------
// Outbound execution (04 §17 #2; §6.3-§6.4 rules for every create)
// ---------------------------------------------------------------------------

interface ExecutionRow {
  ok: true;
  id: string;
  purpose:
    | "customer_create"
    | "checkout_session_create"
    | "final_balance_invoice_create"
    | "recovery_session_create"
    | "final_balance_invoice_disable_auto";
  idempotency_key: string;
  params: StripeParams;
  customer: string | null;
  expected_livemode: boolean;
}

export interface ReturnUrls {
  successUrl: string;
  cancelUrl: string;
}

/**
 * AUTH-009: the provider request may start only within this bound, measured on the
 * executor's monotonic clock from the start of its `confirm_outbound_dispatch` call. That
 * start precedes the database's `dispatch_confirmed_at`, so the bound is never later than
 * 30 seconds after it; a delayed confirmation response grants no fresh window.
 */
export const SEND_DEADLINE_MS = 30_000;

/** A monotonic clock in milliseconds (a fake one in tests). */
export interface DispatchClock {
  now(): number;
}
const monotonicClock: DispatchClock = { now: () => performance.now() };

/**
 * Records a result with the claim token (A1). The token is held in memory only and never
 * logged or returned. One identical resubmission is made only when the response was lost
 * (a transport error, no result): the database returns the stored outcome, applies nothing
 * again, and never authorizes another provider request.
 */
async function record(
  admin: SupabaseClient,
  requestId: string,
  claimToken: string,
  outcome: "succeeded" | "failed" | "ambiguous",
  fields: {
    objectId?: string;
    livemode?: boolean | undefined;
    httpStatus?: number;
    code?: string;
    details?: object;
  },
): Promise<ServiceResult> {
  const args = {
    p_request_id: requestId,
    p_claim_token: claimToken,
    p_outcome: outcome,
    p_stripe_object_id: fields.objectId ?? null,
    p_livemode: fields.livemode ?? null,
    p_http_status: fields.httpStatus ?? null,
    p_error_code: fields.code ?? null,
    p_details: fields.details ?? {},
  };
  let { data, error } = await admin.rpc("record_outbound_result", args);
  if (error && !data) ({ data, error } = await admin.rpc("record_outbound_result", args));
  return rpcResult(data, error);
}

type Confirmation =
  | { kind: "confirmed" }
  | { kind: "superseded"; nextRequestId: string }
  | { kind: "refused"; error: string };

/**
 * A3: the set-once dispatch confirmation, immediately before the provider request. Anything
 * but an explicit confirmation fails closed: nothing is sent.
 */
async function confirmDispatch(
  admin: SupabaseClient,
  requestId: string,
  claimToken: string,
): Promise<Confirmation> {
  const { data, error } = await admin.rpc("confirm_outbound_dispatch", {
    p_request_id: requestId,
    p_claim_token: claimToken,
  });
  const row = data as {
    ok?: boolean;
    confirmed?: boolean;
    error?: string;
    next_request_id?: unknown;
  };
  if (!error && row?.ok === true && row.confirmed === true) return { kind: "confirmed" };
  if (
    !error &&
    row?.error === "superseded" &&
    typeof row.next_request_id === "string" &&
    row.next_request_id !== requestId
  ) {
    return { kind: "superseded", nextRequestId: row.next_request_id };
  }
  const result = rpcResult(data, error);
  return { kind: "refused", error: result.ok ? "not_confirmed" : result.error };
}

/** Line prices the request will charge, with the total the snapshot expects. */
function expectedCharge(row: ExecutionRow): { prices: string[]; total: number } | null {
  const p = row.params;
  if (row.purpose === "checkout_session_create") {
    const items = (p.line_items as Array<{ price: string }> | undefined) ?? [];
    return { prices: items.map((i) => i.price), total: Number(p.expected_amount_total) };
  }
  if (row.purpose === "final_balance_invoice_create") {
    const lines = (p.lines as Array<{ price: string }> | undefined) ?? [];
    return { prices: lines.map((l) => l.price), total: Number(p.expected_amount_due) };
  }
  return null;
}

/**
 * 04 §7 / T-PAY-12: the configured Stripe price amounts must equal the snapshot; and every
 * response must carry `livemode` exactly false outside production (04 §6.3, fail closed).
 */
async function verifyPrices(gateway: StripeGateway, row: ExecutionRow): Promise<string | null> {
  const charge = expectedCharge(row);
  if (!charge) return null;
  if (!Number.isSafeInteger(charge.total) || charge.prices.length === 0)
    return "price_verification_failed";
  let sum = 0;
  for (const priceId of charge.prices) {
    const result = await gateway.retrievePrice(priceId);
    if (result.kind !== "ok") return "price_verification_failed";
    const price = result.object;
    if (price.livemode !== row.expected_livemode) return "livemode_mismatch";
    if (!price.active || price.currency !== "usd" || !Number.isSafeInteger(price.unit_amount)) {
      return "price_verification_failed";
    }
    sum += price.unit_amount as number;
  }
  return sum === charge.total ? null : "price_verification_failed";
}

/**
 * The parameters sent are exactly the database's, plus the resolved Customer and the return
 * URLs. Nothing the database set (card-only payment methods, `auto_advance`,
 * `default_payment_method`, the line, metadata) is changed here (OI-74).
 */
function stripeParams(row: ExecutionRow, urls?: ReturnUrls): StripeParams {
  const { expected_amount_total: _t, expected_amount_due: _d, ...params } = row.params;
  void _t;
  void _d;
  if (row.purpose === "customer_create") return params;
  if (row.purpose === "final_balance_invoice_disable_auto") {
    const { invoice: _invoice, ...update } = params;
    void _invoice;
    return update;
  }
  const withCustomer: StripeParams = { ...params, customer: row.customer };
  if (row.purpose === "checkout_session_create" || row.purpose === "recovery_session_create") {
    if (!urls) throw new Error("Checkout requires return URLs");
    return { ...withCustomer, success_url: urls.successUrl, cancel_url: urls.cancelUrl };
  }
  return withCustomer;
}

/** OI-74: every Checkout the portal opens offers cards only. */
function cardOnly(row: ExecutionRow): boolean {
  if (row.purpose !== "checkout_session_create" && row.purpose !== "recovery_session_create")
    return true;
  const types = row.params.allowed_payment_method_types;
  return Array.isArray(types) && types.length === 1 && types[0] === "card";
}

async function call(
  gateway: StripeGateway,
  row: ExecutionRow,
  params: StripeParams,
): Promise<GatewayResult<{ id: string; livemode: boolean } & Record<string, unknown>>> {
  switch (row.purpose) {
    case "customer_create":
      return gateway.createCustomer(params, row.idempotency_key) as never;
    case "checkout_session_create":
      return gateway.createCheckoutSession(params, row.idempotency_key) as never;
    case "final_balance_invoice_create":
      return gateway.createFinalBalanceInvoice(params, row.idempotency_key) as never;
    case "recovery_session_create":
      return gateway.createRecoverySession(params, row.idempotency_key) as never;
    case "final_balance_invoice_disable_auto":
      return gateway.disableAutomaticCollection(
        String(row.params.invoice),
        params,
        row.idempotency_key,
      ) as never;
  }
}

/**
 * Executes one pending outbound request exactly once. No automatic retry: an ambiguous
 * outcome is recorded and blocks the record until the Owner reconciles it (04 §6.4).
 *
 * An automatic final-balance create that no longer qualifies when it is claimed (the
 * authorization was revoked, the card detached or replaced) is never sent: the database
 * marks it failed and queues a hosted-only attempt on the same invoice record, which runs
 * here instead (OI-74, T-PAY-21). The same replacement happens at confirmation when the
 * authorization changed after the claim.
 *
 * AUTH-009: the claim returns a one-time token (kept in memory only); the request is
 * confirmed immediately before the provider request, which starts only within
 * SEND_DEADLINE_MS of the start of the confirmation call. A definitive `failed` is recorded
 * only when the executor knows no provider request started; once one may have started, an
 * unknown outcome is `ambiguous`. No automatic redispatch, and no gateway or SDK retries.
 */
export async function executeOutboundRequest(
  admin: SupabaseClient,
  gateway: StripeGateway,
  requestId: string,
  urls?: ReturnUrls,
  clock: DispatchClock = monotonicClock,
): Promise<ServiceResult<{ status: string }>> {
  const { data, error } = await admin.rpc("outbound_request_for_execution", {
    p_request_id: requestId,
  });
  const superseded = data as { error?: string; next_request_id?: unknown } | null;
  if (
    !error &&
    superseded?.error === "superseded" &&
    typeof superseded.next_request_id === "string" &&
    superseded.next_request_id !== requestId
  ) {
    return executeOutboundRequest(admin, gateway, superseded.next_request_id, urls, clock);
  }
  const loaded = rpcResult(data, error);
  if (!loaded.ok) return loaded;
  const { claim_token: claimToken, ...claimed } = loaded as Record<string, unknown>;
  if (typeof claimToken !== "string") return { ok: false, error: "claim_token_missing" };
  const row = claimed as unknown as ExecutionRow;
  if (row.expected_livemode && gateway.kind === "mock")
    return { ok: false, error: "mode_mismatch" };

  // Nothing is sent, and the executor knows it: confirm (fail closed), then record a
  // definitive failure. An unconfirmed result would be recorded ambiguous instead.
  const failWithoutSend = async (
    httpStatus: number,
    code: string,
  ): Promise<ServiceResult<{ status: string }>> => {
    const confirmation = await confirmDispatch(admin, requestId, claimToken);
    if (confirmation.kind === "superseded")
      return executeOutboundRequest(admin, gateway, confirmation.nextRequestId, urls, clock);
    if (confirmation.kind === "refused") return { ok: false, error: confirmation.error };
    const recorded = await record(admin, requestId, claimToken, "failed", { httpStatus, code });
    return recorded.ok ? { ok: false, error: code } : recorded;
  };

  if (!cardOnly(row)) return failWithoutSend(409, "payment_method_types_invalid");

  const priceProblem = await verifyPrices(gateway, row);
  // Nothing was created at Stripe, so the request is definitively failed (not ambiguous).
  if (priceProblem) return failWithoutSend(409, priceProblem);

  const params = stripeParams(row, urls);
  const confirmationStarted = clock.now();
  const confirmation = await confirmDispatch(admin, requestId, claimToken);
  if (confirmation.kind === "superseded")
    return executeOutboundRequest(admin, gateway, confirmation.nextRequestId, urls, clock);
  if (confirmation.kind === "refused") return { ok: false, error: confirmation.error };
  if (clock.now() - confirmationStarted > SEND_DEADLINE_MS) {
    // The deadline passed before any provider request started: safe to record as failed.
    const recorded = await record(admin, requestId, claimToken, "failed", {
      code: "dispatch_not_initiated",
    });
    return recorded.ok ? { ok: false, error: "dispatch_not_initiated" } : recorded;
  }

  // From here a provider request may have started: an unknown outcome is never `failed`.
  const result = await call(gateway, row, params);
  if (result.kind === "ok") {
    const { id, livemode, ...rest } = result.object;
    const details: Record<string, unknown> = {};
    for (const key of ["url", "expires_at", "hosted_invoice_url"])
      if (key in rest) details[key] = rest[key];
    const recorded = await record(admin, requestId, claimToken, "succeeded", {
      objectId: id,
      // Strictly boolean; anything else is passed as null and the database aborts.
      livemode: typeof livemode === "boolean" ? livemode : undefined,
      httpStatus: result.httpStatus,
      details,
    });
    if (!recorded.ok) return recorded;
    // A late or unconfirmed success is recorded ambiguous and awaits Owner reconciliation.
    return recorded.status === "succeeded"
      ? { ok: true, status: "succeeded" }
      : { ok: false, error: "reconciliation_required" };
  }
  if (result.kind === "failed") {
    await record(admin, requestId, claimToken, "failed", {
      httpStatus: result.httpStatus,
      code: result.code,
    });
    return { ok: false, error: "stripe_rejected" };
  }
  await record(admin, requestId, claimToken, "ambiguous", { code: result.reason });
  return { ok: false, error: "reconciliation_required" };
}

/**
 * 04 §8: start (or resume) the client's initial Checkout. The database authorizes the client,
 * enforces a current acceptance, verifies the catalog and returns the same session for a
 * double click (T-ARC-05). Returns the Stripe-hosted URL to redirect to.
 */
export async function startInitialCheckout(
  db: SupabaseClient,
  admin: SupabaseClient,
  gateway: StripeGateway,
  projectId: string,
  urls: ReturnUrls,
): Promise<ServiceResult<{ url: string }>> {
  if (!uuid.safeParse(projectId).success) return { ok: false, error: "not_found" };
  const { data, error } = await db.rpc("begin_initial_checkout", { p_project_id: projectId });
  const begun = rpcResult(data, error);
  if (!begun.ok) return begun;
  const existingUrl = begun.checkout_url;
  if (begun.status === "open" && typeof existingUrl === "string")
    return { ok: true, url: existingUrl };

  for (const requestId of (begun.requests as string[] | undefined) ?? []) {
    const executed = await executeOutboundRequest(admin, gateway, requestId, urls);
    // Another request (a double click) holds the claim and is sending it; wait for its result.
    if (!executed.ok && executed.error !== "already_claimed" && executed.error !== "not_pending") {
      return executed;
    }
  }
  for (let attempt = 0; attempt < 20; attempt++) {
    const status = rpcResult(...(await statusOf(db, projectId)));
    const url = status.ok ? status.checkout_url : null;
    if (typeof url === "string") return { ok: true, url };
    if (status.ok && status.checkout_status !== "creating") break;
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  return { ok: false, error: "checkout_unavailable" };
}

async function statusOf(
  db: SupabaseClient,
  projectId: string,
): Promise<[unknown, { message?: string } | null]> {
  const { data, error } = await db.rpc("project_billing_status", { p_project_id: projectId });
  return [data, error];
}

export interface BillingStatus {
  agreementState: string;
  orderSummaryId: string | null;
  depositState: string;
  finalBalanceState: string;
  depositCents: number | null;
  maintenanceMonthlyCents: number | null;
  balanceCents: number | null;
  checkoutStatus: string | null;
  checkoutUrl: string | null;
  finalInvoiceAmountCents: number | null;
  finalInvoiceUrl: string | null;
  billingHoldActive: boolean;
  /** OI-74: none | active | payment_method_unavailable | revoked. */
  paymentAuthorizationState: string;
  /** Only the person who signed the acceptance may revoke (04 §8.1). */
  isAuthorizationSigner: boolean;
  recoveryUrl: string | null;
  finalCollectionMode: string | null;
}

/** The caller's own billing status (client member or Owner). Admin receives not_found. */
export async function getBillingStatus(
  db: SupabaseClient,
  projectId: string,
): Promise<BillingStatus | null> {
  if (!uuid.safeParse(projectId).success) return null;
  const result = rpcResult(...(await statusOf(db, projectId)));
  if (!result.ok) return null;
  const r = result as Record<string, unknown>;
  const num = (v: unknown) => (typeof v === "number" ? v : null);
  const str = (v: unknown) => (typeof v === "string" ? v : null);
  return {
    agreementState: String(r.agreement_state),
    orderSummaryId: str(r.order_summary_id),
    depositState: String(r.deposit_state),
    finalBalanceState: String(r.final_balance_state),
    depositCents: num(r.deposit_cents),
    maintenanceMonthlyCents: num(r.maintenance_monthly_cents),
    balanceCents: num(r.balance_cents),
    checkoutStatus: str(r.checkout_status),
    checkoutUrl: str(r.checkout_url),
    finalInvoiceAmountCents: num(r.final_invoice_amount_cents),
    finalInvoiceUrl: str(r.final_invoice_url),
    billingHoldActive: r.billing_hold_active === true,
    paymentAuthorizationState: String(r.payment_authorization_state ?? "none"),
    isAuthorizationSigner: r.is_authorization_signer === true,
    recoveryUrl: str(r.recovery_url),
    finalCollectionMode: str(r.final_collection_mode),
  };
}

// ---------------------------------------------------------------------------
// Payment authorization: recovery and revocation (04 §8.1, OI-74)
// ---------------------------------------------------------------------------

/**
 * Setup-mode recovery: the client saves a replacement card on a Stripe-hosted page. It never
 * charges, and never writes the subscription's payment method. The database authorizes the
 * client and reuses an open session for a double click.
 */
export async function beginPaymentMethodRecovery(
  db: SupabaseClient,
  admin: SupabaseClient,
  gateway: StripeGateway,
  projectId: string,
  urls: ReturnUrls,
): Promise<ServiceResult<{ url: string }>> {
  if (!uuid.safeParse(projectId).success) return { ok: false, error: "not_found" };
  const { data, error } = await db.rpc("begin_payment_method_recovery", {
    p_project_id: projectId,
  });
  const begun = rpcResult(data, error);
  if (!begun.ok) return begun;
  if (begun.status === "open" && typeof begun.checkout_url === "string")
    return { ok: true, url: begun.checkout_url };
  for (const requestId of (begun.requests as string[] | undefined) ?? []) {
    const executed = await executeOutboundRequest(admin, gateway, requestId, urls);
    if (!executed.ok && executed.error !== "already_claimed" && executed.error !== "not_pending") {
      return executed;
    }
  }
  for (let attempt = 0; attempt < 20; attempt++) {
    const status = await getBillingStatus(db, projectId);
    if (status?.recoveryUrl) return { ok: true, url: status.recoveryUrl };
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  return { ok: false, error: "recovery_unavailable" };
}

export const revokeAuthorizationSchema = z.object({
  projectId: uuid,
  reason: z.string().trim().min(1).max(1000),
});

/**
 * The acceptance signer revokes the final-payment authorization (requires a fresh sign-in
 * code; the database checks it). Automatic collection stops; the balance stays payable on
 * the hosted invoice page.
 */
export async function revokePaymentAuthorization(
  db: SupabaseClient,
  input: unknown,
): Promise<ServiceResult> {
  const parsed = revokeAuthorizationSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "reason_required" };
  const { data, error } = await db.rpc("revoke_payment_authorization", {
    p_project_id: parsed.data.projectId,
    p_reason: parsed.data.reason,
  });
  return rpcResult(data, error);
}

// ---------------------------------------------------------------------------
// Webhooks (04 §11, §17 #4)
// ---------------------------------------------------------------------------

export interface WebhookResponse {
  status: number;
  body: { received: boolean; duplicate?: boolean; error?: string };
}

/**
 * Verifies the signature on the raw body, then stores the event durably, and only then
 * acknowledges (T-ARC-01). A storage failure returns 500 so Stripe retries; the duplicate is
 * absorbed by the unique event ID (T-PAY-05). Processing runs after the durable insert; a
 * processing failure leaves the stored event retryable and still returns 200 (T-ARC-02).
 */
export async function handleStripeWebhook(input: {
  rawBody: string;
  signatureHeader: string | null;
  secret: string;
  admin: SupabaseClient;
  nowSeconds?: number;
}): Promise<WebhookResponse> {
  const signature = verifyStripeSignature(
    input.rawBody,
    input.signatureHeader,
    input.secret,
    input.nowSeconds,
  );
  if (!signature.ok) return { status: 400, body: { received: false, error: "invalid_signature" } };

  let event: unknown;
  try {
    event = JSON.parse(input.rawBody);
  } catch {
    return { status: 400, body: { received: false, error: "malformed_event" } };
  }
  const rawSha = createHash("sha256").update(input.rawBody, "utf8").digest("hex");
  const { data, error } = await input.admin.rpc("ingest_stripe_event", {
    p_event: event,
    p_raw_body_sha256: rawSha,
  });
  if (error || !data) return { status: 500, body: { received: false, error: "storage_failed" } };
  const ingest = data as {
    ok: boolean;
    error?: string;
    webhook_event_id?: number;
    duplicate?: boolean;
  };
  if (!ingest.ok)
    return { status: 400, body: { received: false, error: ingest.error ?? "rejected" } };

  if (!ingest.duplicate && ingest.webhook_event_id) {
    // Errors here are recorded on the stored event and retried by the billing job.
    await input.admin.rpc("process_stripe_event", { p_webhook_event_id: ingest.webhook_event_id });
  }
  return { status: 200, body: { received: true, duplicate: ingest.duplicate === true } };
}

// ---------------------------------------------------------------------------
// Scheduled work (server only)
// ---------------------------------------------------------------------------

/** The database-only billing jobs (04 §13), each its own idempotent, single-flight entry point. */
export const DATABASE_BILLING_JOBS = [
  "webhook_backfill",
  "release_approvals",
  "maintenance_recovery",
  "service_terminations",
  "outbound_requests",
] as const;
export type DatabaseBillingJob = (typeof DATABASE_BILLING_JOBS)[number];

export async function runBillingJob(
  admin: SupabaseClient,
  job: DatabaseBillingJob,
): Promise<ServiceResult<{ skipped: boolean; result: unknown }>> {
  const { data, error } = await admin.rpc("run_billing_job", { p_job: job });
  const run = rpcResult(data, error);
  if (!run.ok) return run;
  return { ok: true, skipped: run.skipped === true, result: run.result ?? null };
}

interface LookupsDue {
  initial: Array<{ record_id: string; stripe_checkout_session_id: string }>;
  recovery: Array<{ record_id: string; stripe_setup_intent_id: string }>;
}

/**
 * 04 §8.1: records the card each verified initial Checkout or completed recovery saved.
 * Single-flight through `begin_billing_job`; a lookup Stripe cannot answer is left for the
 * next run (it is idempotent per record).
 */
export async function runPaymentMethodLookups(
  admin: SupabaseClient,
  gateway: StripeGateway,
): Promise<ServiceResult<{ skipped: boolean; recorded: number }>> {
  const { data: runId, error } = await admin.rpc("begin_billing_job", {
    p_job: "payment_method_lookups",
  });
  if (error) return { ok: false, error: "unavailable" };
  if (typeof runId !== "string") return { ok: true, skipped: true, recorded: 0 };
  let recorded = 0;
  let failed = 0;
  try {
    const { data } = await admin.rpc("payment_method_lookups_due");
    const due = (data ?? { initial: [], recovery: [] }) as LookupsDue;
    const work = [
      ...due.initial.map((d) => ({
        kind: "initial" as const,
        id: d.record_id,
        lookup: () => gateway.retrieveCheckoutPaymentMethod(d.stripe_checkout_session_id),
      })),
      ...due.recovery.map((d) => ({
        kind: "recovery" as const,
        id: d.record_id,
        lookup: () => gateway.retrieveSetupIntentPaymentMethod(d.stripe_setup_intent_id),
      })),
    ];
    for (const item of work) {
      const found = await item.lookup();
      if (found.kind !== "ok") {
        failed += 1;
        continue;
      }
      const { data: result } = await admin.rpc("record_payment_method_lookup", {
        p_kind: item.kind,
        p_record_id: item.id,
        p_payment_method_id: found.object.payment_method,
        p_customer_id: found.object.customer,
        // Strictly boolean; anything else is passed as null and the database rejects it.
        p_livemode: typeof found.object.livemode === "boolean" ? found.object.livemode : null,
        p_attached: found.object.attached === true,
      });
      if ((result as { ok?: boolean } | null)?.ok) recorded += 1;
      else failed += 1;
    }
  } finally {
    await admin.rpc("finish_billing_job", {
      p_run_id: runId,
      p_result: { recorded, failed },
    });
  }
  return { ok: true, skipped: false, recorded };
}

/** Pending final-balance creates and automatic-collection stops, sent through the executor. */
async function executePendingFinalBalanceRequests(
  admin: SupabaseClient,
  gateway: StripeGateway,
): Promise<number> {
  const { data: pending } = await admin
    .from("outbound_stripe_requests")
    .select("id")
    .in("purpose", ["final_balance_invoice_create", "final_balance_invoice_disable_auto"])
    .eq("status", "pending")
    .is("claimed_at", null)
    .order("created_at");
  let executed = 0;
  for (const row of pending ?? []) {
    const result = await executeOutboundRequest(admin, gateway, row.id as string);
    if (result.ok) executed += 1;
  }
  return executed;
}

/**
 * One pass of the billing jobs (04 §13), invoked directly in tests (T-ARC-09); the hosted
 * scheduler binding is WP-D's (DEP-17). Order: retry stored webhooks, record saved cards,
 * consume release approvals, then holds and terminations, stale-request marking, and the
 * Stripe sends the database queued.
 */
export async function runBillingJobs(
  admin: SupabaseClient,
  gateway: StripeGateway,
): Promise<ServiceResult<{ jobs: Record<string, unknown>; requestsExecuted: number }>> {
  const jobs: Record<string, unknown> = {};
  for (const job of ["webhook_backfill"] as const) jobs[job] = await runBillingJob(admin, job);
  jobs.payment_method_lookups = await runPaymentMethodLookups(admin, gateway);
  for (const job of DATABASE_BILLING_JOBS.filter((j) => j !== "webhook_backfill")) {
    jobs[job] = await runBillingJob(admin, job);
  }
  const requestsExecuted = await executePendingFinalBalanceRequests(admin, gateway);
  return { ok: true, jobs, requestsExecuted };
}

/** 04 §13: compares Stripe totals with the ledger; mismatches are quarantined, never fixed. */
export async function runReconciliation(
  admin: SupabaseClient,
  gateway: StripeGateway,
  runKey?: string,
): Promise<ServiceResult<{ projectsChecked: number; mismatches: number; skipped?: boolean }>> {
  // One run per local day by default (04 §13); a rerun with the same key does nothing.
  const { data: runId, error } = await admin.rpc("start_reconciliation_run", {
    p_source: "mocked_gateway",
    p_run_key: runKey ?? null,
  });
  if (error) return { ok: false, error: "unavailable" };
  if (typeof runId !== "string")
    return { ok: true, projectsChecked: 0, mismatches: 0, skipped: true };
  const { data: projects } = await admin
    .from("projects")
    .select(
      "id, client_business_id, client_businesses!inner(stripe_customers!inner(stripe_customer_id))",
    );
  let mismatches = 0;
  for (const project of (projects ?? []) as Array<{ id: string; client_businesses: unknown }>) {
    const business = Array.isArray(project.client_businesses)
      ? project.client_businesses[0]
      : project.client_businesses;
    const customers = (business as { stripe_customers?: unknown } | undefined)?.stripe_customers;
    const customer = Array.isArray(customers) ? customers[0] : customers;
    const customerId = (customer as { stripe_customer_id?: string } | undefined)
      ?.stripe_customer_id;
    if (!customerId) continue;
    const totals = await gateway.reconciliationTotals({ projectId: project.id, customerId });
    if (totals.kind !== "ok") continue;
    const { data: count } = await admin.rpc("record_project_reconciliation", {
      p_run_id: runId,
      p_project_id: project.id,
      p_stripe: totals.object,
    });
    mismatches += typeof count === "number" ? count : 0;
  }
  const { data: done } = await admin.rpc("complete_reconciliation_run", { p_run_id: runId });
  const summary = (done ?? {}) as { projects_checked?: number };
  return { ok: true, projectsChecked: summary.projects_checked ?? 0, mismatches };
}

// ---------------------------------------------------------------------------
// Entry points for routes and actions (the admin client never leaves src/server)
// ---------------------------------------------------------------------------

/** Webhook route entry point: the admin client is created only after configuration checks. */
export async function receiveStripeWebhook(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
  gateway: StripeGateway | null = null,
): Promise<WebhookResponse> {
  const admin = await createAdminClient();
  const response = await handleStripeWebhook({ rawBody, signatureHeader, secret, admin });
  // A verified deposit or completed recovery needs its saved card recorded before the
  // authorization is ready (04 §8.1). Best effort after the acknowledgement is decided: the
  // billing job repeats any lookup that does not complete here.
  if (gateway && response.status === 200 && !response.body.duplicate) {
    await runPaymentMethodLookups(admin, gateway).catch(() => undefined);
  }
  return response;
}

/** Client action entry point. The user client authorizes; the admin client records results. */
export async function startInitialCheckoutAsCaller(
  db: SupabaseClient,
  gateway: StripeGateway,
  projectId: string,
  urls: ReturnUrls,
): Promise<ServiceResult<{ url: string }>> {
  return startInitialCheckout(db, await createAdminClient(), gateway, projectId, urls);
}

/** Client action entry point for setup-mode recovery. */
export async function beginPaymentMethodRecoveryAsCaller(
  db: SupabaseClient,
  gateway: StripeGateway,
  projectId: string,
  urls: ReturnUrls,
): Promise<ServiceResult<{ url: string }>> {
  return beginPaymentMethodRecovery(db, await createAdminClient(), gateway, projectId, urls);
}
