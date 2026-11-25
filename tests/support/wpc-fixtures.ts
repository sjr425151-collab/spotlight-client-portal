import { randomBytes } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";

import {
  acceptAgreement,
  handleStripeWebhook,
  issueOrderSummary,
  runPaymentMethodLookups,
  startInitialCheckout,
} from "@/server/services/billing";
import { MockStripeGateway } from "@/server/stripe/mock-gateway";

import { withDb } from "./db";
import { adminClient } from "./local-supabase";
import { signedEvent, testWebhookSecret } from "./stripe-events";

/**
 * Shared WP-C integration fixtures (local stack, synthetic data only).
 *
 * AUTH-008 I-1 item 1 (F2, CURRENT-STATE §7): a paid project is created from real WP-B
 * records on a fresh, isolated project, through the same path as
 * tests/integration/wpb-billing.test.ts: business, project, membership, Owner-issued order
 * summary, the client's own acceptance, the mocked Checkout gateway (no network request), a
 * synthetic signed `checkout.session.completed` webhook (OI-63), and the payment-method
 * lookup. No financial function is replaced: the deposit and the payment authorization are
 * whatever the real `private.project_financial_status` derives from those records.
 *
 * A test file that uses `createPaidProject` mocks `@/server/supabase/admin` exactly as
 * wpb-billing.test.ts does, because the billing service module imports it.
 *
 * The seeded projects are never changed here: PROJECT_A stays unpaid (tests/e2e/wpc.spec.ts
 * T-LC-01) and PROJECT_B stays `intake_locked`.
 */

export const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
export const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
export const BUCKET = "project-assets";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const URLS = { successUrl: "http://localhost:3000/ok", cancelUrl: "http://localhost:3000/cancel" };

/**
 * A minimal PNG with a unique tEXt chunk per call. Unique bytes matter: a malicious verdict
 * blocks those exact bytes in every upload, permanently (05 §5.5 rule 3), and that evidence
 * persists across runs on a local database. The served copy strips tEXt chunks.
 */
let pngCount = 0;
const RUN = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
const u32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const chunk = (type: string, data: number[]) => [
  ...u32(data.length),
  ...[...type].map((ch) => ch.charCodeAt(0)),
  ...data,
  0,
  0,
  0,
  0, // CRC (not checked by the pipeline's header parser)
];
export const png = () => {
  const tag = [...`run-${RUN}-${pngCount++}`].map((ch) => ch.charCodeAt(0));
  return new Uint8Array([
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ...chunk("IHDR", [...u32(4), ...u32(4), 8, 6, 0, 0, 0]),
    ...chunk("tEXt", tag),
    ...chunk("IEND", []),
  ]);
};

export type FreshProject = { projectId: string; businessId: string; legalName: string };

/** A fresh synthetic business and project with one client member, created as the Owner. */
export async function createProject(label: string, memberUserId: string): Promise<FreshProject> {
  const legalName = `Synthetic ${label} ${RUN} LLC`;
  return withDb(async (db) => {
    await db.query("begin");
    try {
      await db.query("select set_config('request.jwt.claims', $1, true)", [
        JSON.stringify({ sub: OWNER_ID, role: "authenticated", aal: "aal2" }),
      ]);
      const business = await db.query(
        "insert into public.client_businesses (legal_name, display_name) values ($1, $1) returning id",
        [legalName],
      );
      const businessId = business.rows[0].id as string;
      const project = await db.query(
        "insert into public.projects (client_business_id, name) values ($1, $2) returning id",
        [businessId, `${label} ${RUN}`],
      );
      const projectId = project.rows[0].id as string;
      await db.query(
        "insert into public.project_memberships (project_id, user_id) values ($1, $2)",
        [projectId, memberUserId],
      );
      await db.query("commit");
      return { projectId, businessId, legalName };
    } catch (error) {
      await db.query("rollback");
      throw error;
    }
  });
}

type Financial = { deposit_verified: boolean; ready: boolean; intake_unlocked: boolean };

const financialOf = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select f.deposit_verified, f.payment_authorization_ready as ready,
              private.wpc_intake_unlocked($1) as intake_unlocked
         from private.project_financial_status($1) f`,
      [projectId],
    );
    return rows[0] as Financial;
  });

function expectOk<T extends { ok: boolean }>(step: string, result: T): T {
  if (!result.ok) throw new Error(`createPaidProject: ${step} failed: ${JSON.stringify(result)}`);
  return result;
}

/**
 * A fresh project whose deposit is verified and whose payment authorization is ready,
 * from real WP-B records only. `owner` is an Owner session at aal2; `client` is the signed-in
 * session of `clientUserId`, who becomes the project's only client member and the signer.
 */
export async function createPaidProject(input: {
  label: string;
  owner: SupabaseClient;
  client: SupabaseClient;
  clientUserId: string;
}): Promise<FreshProject> {
  const { owner, client } = input;
  const server = adminClient();
  const gateway = new MockStripeGateway();
  const secret = testWebhookSecret(input.label);
  const fresh = await createProject(input.label, input.clientUserId);
  const { projectId, businessId, legalName } = fresh;

  expectOk(
    "issueOrderSummary",
    await issueOrderSummary(owner, { projectId, packageKey: "advanced", scopeItems: ["Website"] }),
  );
  const summary = await client
    .from("order_summaries")
    .select("id")
    .eq("project_id", projectId)
    .single();
  if (summary.error) throw new Error(`createPaidProject: order summary: ${summary.error.message}`);
  expectOk(
    "acceptAgreement",
    await acceptAgreement(client, {
      orderSummaryId: summary.data.id,
      accepted: true,
      authorityConfirmed: true,
      signerFullLegalName: "Alex Client",
      businessLegalName: legalName,
      signerTitle: "Owner",
      checkboxUncheckedByDefault: true,
    }),
  );
  expectOk(
    "startInitialCheckout",
    await startInitialCheckout(client, server, gateway, projectId, URLS),
  );

  const checkout = await client
    .from("checkout_sessions")
    .select("id, stripe_checkout_session_id, order_summary_id, acceptance_id")
    .eq("project_id", projectId)
    .single();
  if (checkout.error) throw new Error(`createPaidProject: checkout: ${checkout.error.message}`);
  const customer = await owner
    .from("stripe_customers")
    .select("stripe_customer_id")
    .eq("client_business_id", businessId)
    .single();
  if (customer.error) throw new Error(`createPaidProject: customer: ${customer.error.message}`);

  const tag = randomBytes(6).toString("hex");
  const completed = signedEvent(secret, "checkout.session.completed", {
    id: checkout.data.stripe_checkout_session_id,
    object: "checkout.session",
    mode: "subscription",
    currency: "usd",
    amount_total: 59800,
    payment_status: "paid",
    customer: customer.data.stripe_customer_id,
    subscription: `sub_${tag}`,
    invoice: `in_${tag}`,
    total_details: { amount_discount: 0, amount_tax: 0 },
    metadata: {
      project_id: projectId,
      order_summary_id: checkout.data.order_summary_id,
      acceptance_id: checkout.data.acceptance_id,
      checkout_record_id: checkout.data.id,
    },
  });
  const delivered = await handleStripeWebhook({
    rawBody: completed.rawBody,
    signatureHeader: completed.header,
    secret,
    admin: server,
  });
  if (delivered.status !== 200 || delivered.body.duplicate !== false) {
    throw new Error(`createPaidProject: webhook: ${JSON.stringify(delivered)}`);
  }

  const lookups = expectOk(
    "runPaymentMethodLookups",
    await runPaymentMethodLookups(server, gateway),
  );
  const financial = await financialOf(projectId);
  if (!financial.deposit_verified || !financial.ready || !financial.intake_unlocked) {
    throw new Error(
      `createPaidProject: project not paid after the WP-B flow: ${JSON.stringify({
        financial,
        lookups,
      })}`,
    );
  }
  return fresh;
}

/** Frees a project's quota from abandoned reservations. */
export async function freeQuota(projectId: string) {
  await withDb((db) =>
    db.query(
      `update public.asset_uploads set status = 'failed_upload'
        where project_id = $1 and status = 'uploading'`,
      [projectId],
    ),
  );
}
