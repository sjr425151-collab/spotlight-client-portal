import { createHash } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";
import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import { withDb } from "../support/db";
import { adminClient, signInWithCode, upgradeToAal2 } from "../support/local-supabase";

vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

import {
  acceptAgreement,
  getBillingStatus,
  handleStripeWebhook,
  issueOrderSummary,
  revokePaymentAuthorization,
  runBillingJob,
  runBillingJobs,
  runPaymentMethodLookups,
  runReconciliation,
  startInitialCheckout,
} from "@/server/services/billing";
import { MockStripeGateway } from "@/server/stripe/mock-gateway";
import { computeSignature } from "@/server/stripe/webhook-signature";

/**
 * WP-B integration tests against the LOCAL Supabase stack: real Auth sessions (Mailpit codes,
 * TOTP), real PostgREST and RLS, the mocked Stripe gateway (no network request), and
 * synthetic Stripe-format events signed with a test-only secret generated for this run
 * (OI-63). Nothing here is verified against Stripe; that is DEP-15 under AUTH-002.
 */

const OWNER = "owner@example.test";
const ADMIN = "admin@example.test";
const CLIENT_A = "client.a@example.test";
const CLIENT_B = "client.b@example.test";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const RUN = Date.now().toString(36);
const SECRET = `whsec_${createHash("sha256").update(`ci-${RUN}`).digest("hex").slice(0, 32)}`;
const URLS = { successUrl: "http://localhost:3000/ok", cancelUrl: "http://localhost:3000/cancel" };

// Same synthetic-staff cleanup as the Phase 2 suite, so each run enrolls fresh TOTP factors.
const STAFF_FACTORS_CLEANUP = `delete from auth.mfa_factors where user_id in (
  '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002')`;
const totpSecrets = new Map<string, string>();
let owner: SupabaseClient;
let admin: SupabaseClient;
let clientA: SupabaseClient;
let clientB: SupabaseClient;
let projectId: string;
let businessId: string;
const gateway = new MockStripeGateway();
const server = adminClient();

function signedEvent(
  type: string,
  object: Record<string, unknown>,
  id = `evt_${RUN}${Math.random().toString(36).slice(2, 10)}`,
) {
  const now = Math.floor(Date.now() / 1000);
  const rawBody = JSON.stringify({
    id,
    object: "event",
    type,
    api_version: "2026-09-30.endive",
    livemode: false,
    created: now,
    data: { object },
  });
  return { id, rawBody, header: `t=${now},v1=${computeSignature(SECRET, now, rawBody)}` };
}
const deliver = (e: { rawBody: string; header: string }) =>
  handleStripeWebhook({
    rawBody: e.rawBody,
    signatureHeader: e.header,
    secret: SECRET,
    admin: server,
  });

/**
 * The local Auth enforces a minimum interval between codes sent to one address. The
 * support helper spaces sends within a file only, so a suite that runs right after
 * another one may hit the interval for its first send; only that error is retried.
 */
async function signIn(email: string): Promise<SupabaseClient> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await signInWithCode(email);
    } catch (error) {
      if (attempt >= 3 || !String(error).includes("over_email_send_rate_limit")) throw error;
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }
}

async function asService<T>(db: Client, sql: string, params: unknown[] = []): Promise<T> {
  await db.query("begin");
  await db.query(`select set_config('request.jwt.claims', '{"role":"service_role"}', true)`);
  await db.query("set local role service_role");
  const result = await db.query(sql, params);
  await db.query("commit");
  return result.rows as T;
}

beforeAll(async () => {
  // A fresh project per run: WP-B records are append-only and cannot be cleaned up.
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(STAFF_FACTORS_CLEANUP);
    await db.query("begin");
    await db.query(
      `select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}', true)`,
    );
    const business = await db.query(
      "insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id",
      [`Synthetic WPB ${RUN} LLC`],
    );
    businessId = business.rows[0].id;
    const project = await db.query(
      "insert into public.projects (client_business_id, name) values ($1, $2) returning id",
      [businessId, `WP-B ${RUN}`],
    );
    projectId = project.rows[0].id;
    await db.query("insert into public.project_memberships (project_id, user_id) values ($1, $2)", [
      projectId,
      CLIENT_A_ID,
    ]);
    await db.query("commit");
  });
  owner = await signIn(OWNER);
  await upgradeToAal2(owner, totpSecrets);
  admin = await signIn(ADMIN);
  await upgradeToAal2(admin, totpSecrets);
  clientA = await signIn(CLIENT_A);
  clientB = await signIn(CLIENT_B);
});

afterAll(async () => {
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(STAFF_FACTORS_CLEANUP);
  });
});

describe("WP-B agreement and initial Checkout through the API", () => {
  it("the Owner issues the order summary; a client cannot", async () => {
    expect(
      await issueOrderSummary(clientA, { projectId, packageKey: "advanced", scopeItems: [] }),
    ).toEqual({
      ok: false,
      error: "forbidden",
    });
    const issued = await issueOrderSummary(owner, {
      projectId,
      packageKey: "advanced",
      scopeItems: ["Website"],
    });
    expect(issued.ok).toBe(true);
  });

  it("T-AGR-05: staff cannot accept on the client's behalf; T-AGR-01: no implicit acceptance", async () => {
    const { data: summary } = await clientA
      .from("order_summaries")
      .select("id")
      .eq("project_id", projectId)
      .single();
    const input = {
      orderSummaryId: summary!.id,
      accepted: true,
      authorityConfirmed: true,
      signerFullLegalName: "Alex Client",
      businessLegalName: `Synthetic WPB ${RUN} LLC`,
      signerTitle: "Owner",
      checkboxUncheckedByDefault: true,
    };
    expect((await acceptAgreement(owner, input)).ok).toBe(false);
    expect(await acceptAgreement(clientA, { ...input, accepted: false })).toEqual({
      ok: false,
      error: "explicit_acceptance_required",
    });
    expect(await acceptAgreement(clientA, { ...input, authorityConfirmed: undefined })).toEqual({
      ok: false,
      error: "explicit_acceptance_required",
    });
    expect((await acceptAgreement(clientA, input)).ok).toBe(true);
  });

  it("T-PAY-11: another project's client cannot start this Checkout", async () => {
    expect(await startInitialCheckout(clientB, server, gateway, projectId, URLS)).toEqual({
      ok: false,
      error: "not_found",
    });
  });

  it("T-ARC-05: concurrent requests produce one Stripe Customer and one Checkout Session (T-BIL-20 parameters)", async () => {
    const results = await Promise.all([
      startInitialCheckout(clientA, server, gateway, projectId, URLS),
      startInitialCheckout(clientA, server, gateway, projectId, URLS),
      startInitialCheckout(clientA, server, gateway, projectId, URLS),
    ]);
    const urls = new Set(results.filter((r) => r.ok).map((r) => (r as { url: string }).url));
    expect(urls.size).toBe(1);
    expect([...urls][0]).toMatch(/^https:\/\/checkout\.stripe\.com\//);
    const creates = gateway.calls.filter((c) => c.method === "checkout.sessions.create");
    expect(creates).toHaveLength(1);
    expect(
      gateway.calls.filter(
        (c) => c.method === "customers.create" && c.idempotencyKey?.includes(businessId),
      ),
    ).toHaveLength(1);
    const params = creates[0]!.params as Record<string, unknown>;
    expect(params.line_items).toEqual([
      { price: "price_1Uf5HzK5j4r4WkVP35jgGOiy", quantity: 1 },
      { price: "price_1Uf5I2K5j4r4WkVPJodSnaBe", quantity: 1 },
    ]);
    expect(params.discounts).toEqual([]);
    expect(params.allow_promotion_codes).toBe(false);
    // OI-74: card only, and the card is always collected for the final balance.
    expect(params.allowed_payment_method_types).toEqual(["card"]);
    expect(params.payment_method_collection).toBe("always");
    expect(params).not.toHaveProperty("expected_amount_total");
  });

  it("T-PAY-04: returning from Checkout without a webhook leaves the deposit pending", async () => {
    expect((await getBillingStatus(clientA, projectId))?.depositState).toBe("pending");
  });
});

describe("WP-B webhooks through the service (T-PAY-03, T-PAY-05, T-ARC-01)", () => {
  let session: {
    id: string;
    customer: string;
    checkoutRecordId: string;
    orderSummaryId: string;
    acceptanceId: string;
  };

  beforeAll(async () => {
    const { data: cs } = await clientA
      .from("checkout_sessions")
      .select("id, stripe_checkout_session_id, order_summary_id, acceptance_id")
      .eq("project_id", projectId)
      .single();
    const { data: customer } = await owner
      .from("stripe_customers")
      .select("stripe_customer_id")
      .eq("client_business_id", businessId)
      .single();
    session = {
      id: cs!.stripe_checkout_session_id!,
      customer: customer!.stripe_customer_id,
      checkoutRecordId: cs!.id,
      orderSummaryId: cs!.order_summary_id,
      acceptanceId: cs!.acceptance_id,
    };
  });

  const completed = () => ({
    id: session.id,
    object: "checkout.session",
    mode: "subscription",
    currency: "usd",
    amount_total: 59800,
    payment_status: "paid",
    customer: session.customer,
    subscription: `sub_${RUN}00001`,
    invoice: `in_${RUN}00001`,
    total_details: { amount_discount: 0, amount_tax: 0 },
    metadata: {
      project_id: projectId,
      order_summary_id: session.orderSummaryId,
      acceptance_id: session.acceptanceId,
      checkout_record_id: session.checkoutRecordId,
    },
  });

  it("T-PAY-03: an invalid signature is rejected and stores nothing", async () => {
    const e = signedEvent("checkout.session.completed", completed());
    const result = await handleStripeWebhook({
      rawBody: e.rawBody,
      signatureHeader: e.header.replace(/v1=[0-9a-f]{64}/, `v1=${"0".repeat(64)}`),
      secret: SECRET,
      admin: server,
    });
    expect(result.status).toBe(400);
    const { data } = await owner.from("webhook_events").select("id").eq("stripe_event_id", e.id);
    expect(data).toEqual([]);
  });

  it("T-PAY-05: concurrent replays of one event post the ledger exactly once", async () => {
    const e = signedEvent("checkout.session.completed", completed());
    const results = await Promise.all(Array.from({ length: 6 }, () => deliver(e)));
    expect(results.every((r) => r.status === 200)).toBe(true);
    expect(results.filter((r) => r.body.duplicate === false)).toHaveLength(1);
    const { data: ledger } = await owner
      .from("ledger_entries")
      .select("entry_type, amount_cents")
      .eq("project_id", projectId)
      .order("id");
    expect(ledger).toEqual([
      { entry_type: "deposit_charge", amount_cents: 49900 },
      { entry_type: "maintenance_charge", amount_cents: 9900 },
    ]);
    expect((await getBillingStatus(clientA, projectId))?.agreementState).toBe("effective");
  });

  it("T-PAY-13: the authorization is not ready until the saved card is recorded; then intake can unlock", async () => {
    const financial = async () =>
      withDb(async (db) => {
        const r = await db.query(
          "select (private.project_financial_status($1)).payment_authorization_ready as ready, (private.project_financial_status($1)).deposit_verified as deposit",
          [projectId],
        );
        return r.rows[0] as { ready: boolean; deposit: boolean };
      });
    expect(await financial()).toEqual({ ready: false, deposit: true });
    expect((await getBillingStatus(clientA, projectId))?.paymentAuthorizationState).toBe("none");
    const first = await runPaymentMethodLookups(server, gateway);
    expect(first).toEqual({ ok: true, skipped: false, recorded: 1 });
    // Idempotent per record: a rerun has nothing left to look up.
    expect(await runPaymentMethodLookups(server, gateway)).toEqual({
      ok: true,
      skipped: false,
      recorded: 0,
    });
    expect(await financial()).toEqual({ ready: true, deposit: true });
    const status = await getBillingStatus(clientA, projectId);
    expect(status?.paymentAuthorizationState).toBe("active");
    expect(status?.isAuthorizationSigner).toBe(true);
    const { data: auth } = await owner
      .from("payment_authorizations")
      .select("stripe_payment_method_id, authorized_balance_cents, status")
      .eq("project_id", projectId)
      .single();
    expect(auth).toEqual({
      stripe_payment_method_id: gateway.paymentMethods.get(session.id)!.payment_method,
      authorized_balance_cents: 199600,
      status: "active",
    });
    // OI-74: clients and Admin read no authorization rows.
    for (const caller of [clientA, admin]) {
      const { data } = await caller
        .from("payment_authorizations")
        .select("id")
        .eq("project_id", projectId);
      expect(data).toEqual([]);
    }
  });

  it("OI-72 (server layer): Admin gets derived states only, no ledger rows and no amounts", async () => {
    const { data: states } = await admin.rpc("operational_payment_states", {
      p_project_ids: [projectId],
    });
    expect(Object.keys((states as object[])[0]!).sort()).toEqual([
      "billing_operational_hold",
      "deposit_requirement_satisfied",
      "final_balance_requirement_satisfied",
      "owner_intervention_required",
      "payment_recovery_required",
      "project_id",
      "publication_financially_eligible",
    ]);
    expect((states as Array<Record<string, boolean>>)[0]!.deposit_requirement_satisfied).toBe(true);
    const { data: ledger } = await admin
      .from("ledger_entries")
      .select("id")
      .eq("project_id", projectId);
    expect(ledger).toEqual([]);
    expect(await getBillingStatus(admin, projectId)).toBeNull();
    const { error } = await clientA.rpc("operational_payment_states", {
      p_project_ids: [projectId],
    });
    expect(error).not.toBeNull();
  });
});

describe("WP-B final-balance obligation under real concurrency (04 §10, OI-73, OI-74)", () => {
  it("two release.approved events consumed by two concurrent job runs create one obligation and one automatic invoice", async () => {
    await withDb(async (db) => {
      for (const n of [1, 2]) {
        await db.query(
          `select private.emit_domain_event('release.approved', $1, 'preview_release', gen_random_uuid()::text,
             jsonb_build_object('approval_id', gen_random_uuid()), $2)`,
          [projectId, `release.approved:${RUN}:${n}`],
        );
      }
    });
    const url =
      process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    const a = new Client({ connectionString: url });
    const b = new Client({ connectionString: url });
    await Promise.all([a.connect(), b.connect()]);
    try {
      // The job entry point is single-flight: a concurrent run is skipped, never doubled.
      await Promise.all([
        asService(a, "select public.run_billing_job('release_approvals')"),
        asService(b, "select public.run_billing_job('release_approvals')"),
      ]);
      // Whichever run was skipped, a follow-up run consumes anything left (idempotently).
      await asService(a, "select public.run_billing_job('release_approvals')");
    } finally {
      await Promise.all([a.end(), b.end()]);
    }
    const { data: invoices } = await owner
      .from("final_balance_invoices")
      .select("id, amount_cents, status, collection_mode, default_payment_method_id")
      .eq("project_id", projectId);
    expect(invoices).toHaveLength(1);
    expect(invoices![0]!.amount_cents).toBe(199600);
    expect(invoices![0]!.collection_mode).toBe("automatic");

    const before = gateway.calls.filter((c) => c.method === "invoices.create_finalize_send").length;
    await Promise.all([runBillingJobs(server, gateway), runBillingJobs(server, gateway)]);
    const created =
      gateway.calls.filter((c) => c.method === "invoices.create_finalize_send").length - before;
    expect(created).toBe(1);
    const sent = gateway.calls.filter((c) => c.method === "invoices.create_finalize_send").at(-1)!
      .params as Record<string, unknown>;
    expect(sent.collection_method).toBe("charge_automatically");
    expect(sent.auto_advance).toBe(true);
    expect(sent.default_payment_method).toBe(invoices![0]!.default_payment_method_id);
    expect(sent).not.toHaveProperty("expected_amount_due");
    const status = await getBillingStatus(clientA, projectId);
    expect(status?.finalCollectionMode).toBe("automatic");
    expect(status?.finalBalanceState).toBe("pending");
    expect(status?.finalInvoiceUrl).toMatch(/^https:\/\/invoice\.stripe\.com\//);
  });

  it("the balance is verified only by the signed invoice.paid webhook", async () => {
    const { data: fbi } = await owner
      .from("final_balance_invoices")
      .select(
        "id, stripe_invoice_id, stripe_customer_id, order_summary_id, default_payment_method_id",
      )
      .eq("project_id", projectId)
      .single();
    const e = signedEvent("invoice.paid", {
      id: fbi!.stripe_invoice_id,
      object: "invoice",
      billing_reason: "manual",
      currency: "usd",
      amount_paid: 199600,
      customer: fbi!.stripe_customer_id,
      default_payment_method: fbi!.default_payment_method_id,
      payment_intent: `pi_${RUN}fb0001`,
      metadata: {
        project_id: projectId,
        order_summary_id: fbi!.order_summary_id,
        final_balance_invoice_id: fbi!.id,
      },
      lines: {
        data: [
          { quantity: 1, pricing: { price_details: { price: "price_1Uf5I0K5j4r4WkVPZLs7eS9w" } } },
        ],
      },
    });
    expect((await deliver(e)).status).toBe(200);
    expect((await getBillingStatus(clientA, projectId))?.finalBalanceState).toBe("verified");
  });

  it("T-ARC-07: reconciliation with mismatched Stripe totals alerts and changes nothing", async () => {
    gateway.totals.set(projectId, { charges_cents: 1, refunds_cents: 0, open_disputes: 0 });
    const runKey = `it-${RUN}`;
    const result = await runReconciliation(server, gateway, runKey);
    expect(result.ok).toBe(true);
    // T-ARC-09: the same run key is a no-op (one daily run).
    expect(await runReconciliation(server, gateway, runKey)).toEqual({
      ok: true,
      projectsChecked: 0,
      mismatches: 0,
      skipped: true,
    });
    const { data: mismatches } = await owner
      .from("reconciliation_mismatches")
      .select("kind")
      .eq("project_id", projectId);
    expect(mismatches).toEqual([{ kind: "charges_total" }]);
    expect((await getBillingStatus(clientA, projectId))?.finalBalanceState).toBe("verified");
  });
});

describe("WP-B billing job entry points (04 §13, T-ARC-09)", () => {
  it("a run while another connection holds the job is skipped and audited; a rerun is idempotent", async () => {
    const url =
      process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    const holder = new Client({ connectionString: url });
    await holder.connect();
    try {
      await holder.query("begin");
      await holder.query(
        "select pg_advisory_xact_lock(hashtextextended('wpb:job:release_approvals', 0))",
      );
      expect(await runBillingJob(server, "release_approvals")).toEqual({
        ok: true,
        skipped: true,
        result: null,
      });
      await holder.query("rollback");
    } finally {
      await holder.end();
    }
    const first = await runBillingJob(server, "release_approvals");
    const second = await runBillingJob(server, "release_approvals");
    expect(first).toMatchObject({ ok: true, skipped: false });
    expect(second).toEqual({ ok: true, skipped: false, result: { consumed: 0 } });
    const { data: audit } = await owner
      .from("audit_events")
      .select("action")
      .in("action", ["billing_job.skipped", "billing_job.completed"])
      .eq("target_id", "release_approvals");
    expect(new Set((audit ?? []).map((a) => a.action))).toEqual(
      new Set(["billing_job.skipped", "billing_job.completed"]),
    );
  });
});

describe("WP-B payment authorization revocation through the API (04 §8.1, OI-74)", () => {
  it("only the acceptance signer may revoke; staff and other clients cannot", async () => {
    expect(await revokePaymentAuthorization(clientB, { projectId, reason: "x" })).toEqual({
      ok: false,
      error: "not_found",
    });
    expect(await revokePaymentAuthorization(admin, { projectId, reason: "x" })).toEqual({
      ok: false,
      error: "not_found",
    });
    expect(await revokePaymentAuthorization(clientA, { projectId, reason: " " })).toEqual({
      ok: false,
      error: "reason_required",
    });
  });

  it("the signer revokes with a recent sign-in code; the Owner sees a review item", async () => {
    const result = await revokePaymentAuthorization(clientA, {
      projectId,
      reason: "Synthetic revocation",
    });
    expect(result).toMatchObject({ ok: true });
    expect((await getBillingStatus(clientA, projectId))?.paymentAuthorizationState).toBe("revoked");
    const { data: auth } = await owner
      .from("payment_authorizations")
      .select("status, revocation_source")
      .eq("project_id", projectId)
      .single();
    expect(auth).toEqual({ status: "revoked", revocation_source: "client" });
    const { data: states } = await owner.rpc("operational_payment_states", {
      p_project_ids: [projectId],
    });
    expect((states as Array<Record<string, boolean>>)[0]!.owner_intervention_required).toBe(true);
  });
});
