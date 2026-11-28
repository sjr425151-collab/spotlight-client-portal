"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { env } from "@/config/env";
import { requireClient } from "@/server/auth/guards";
import {
  acceptAgreement,
  beginPaymentMethodRecoveryAsCaller,
  revokePaymentAuthorization,
  startInitialCheckoutAsCaller,
} from "@/server/services/billing";
import { getStripeGateway, StripeGatewayUnavailableError } from "@/server/stripe";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Client billing actions (spec 04 §3, §8, §15.1.1; 03 §4). Each starts with a guard; the
 * database re-authorizes membership, rejects staff, and enforces every precondition.
 */

const projectIdSchema = z.uuid();

function billingPath(projectId: string, query: string): never {
  const safe = projectIdSchema.safeParse(projectId).success ? projectId : null;
  redirect((safe ? `/portal/projects/${safe}/billing?${query}` : "/portal") as never);
}

export async function acceptAgreementAction(formData: FormData) {
  await requireClient();
  const projectId = String(formData.get("projectId") ?? "");
  const result = await acceptAgreement(await createUserClient(), {
    orderSummaryId: String(formData.get("orderSummaryId") ?? ""),
    // An unchecked checkbox is absent from the form, so it can never read as true.
    accepted: formData.get("accepted") === "true",
    authorityConfirmed: formData.get("authorityConfirmed") === "true",
    signerFullLegalName: String(formData.get("signerFullLegalName") ?? ""),
    businessLegalName: String(formData.get("businessLegalName") ?? ""),
    signerTitle: String(formData.get("signerTitle") ?? ""),
    checkboxUncheckedByDefault: formData.get("checkboxDefault") === "unchecked",
  });
  billingPath(projectId, result.ok ? "notice=agreement_accepted" : `error=${result.error}`);
}

export async function startCheckoutAction(formData: FormData) {
  await requireClient();
  const projectId = String(formData.get("projectId") ?? "");
  if (!projectIdSchema.safeParse(projectId).success) redirect("/portal");
  let gateway;
  try {
    gateway = await getStripeGateway();
  } catch (error) {
    if (error instanceof StripeGatewayUnavailableError)
      billingPath(projectId, "error=payments_unavailable");
    throw error;
  }
  const base = `${env.NEXT_PUBLIC_SITE_URL}/portal/projects/${projectId}/billing`;
  const result = await startInitialCheckoutAsCaller(await createUserClient(), gateway, projectId, {
    successUrl: `${base}?checkout=returned`,
    cancelUrl: `${base}?checkout=cancelled`,
  });
  if (!result.ok) billingPath(projectId, `error=${result.error}`);
  redirect(result.url as never);
}

export async function requestCancellationAction(formData: FormData) {
  await requireClient();
  const projectId = String(formData.get("projectId") ?? "");
  const { data } = await (
    await createUserClient()
  ).rpc("submit_cancellation_request", {
    p_project_id: projectIdSchema.safeParse(projectId).success ? projectId : null,
  });
  const ok = (data as { ok?: boolean } | null)?.ok === true;
  billingPath(projectId, ok ? "notice=cancellation_received" : "error=unavailable");
}

/** OI-74: save a replacement card on a Stripe-hosted setup page. It never charges. */
export async function beginRecoveryAction(formData: FormData) {
  await requireClient();
  const projectId = String(formData.get("projectId") ?? "");
  if (!projectIdSchema.safeParse(projectId).success) redirect("/portal");
  let gateway;
  try {
    gateway = await getStripeGateway();
  } catch (error) {
    if (error instanceof StripeGatewayUnavailableError)
      billingPath(projectId, "error=payments_unavailable");
    throw error;
  }
  const base = `${env.NEXT_PUBLIC_SITE_URL}/portal/projects/${projectId}/billing`;
  const result = await beginPaymentMethodRecoveryAsCaller(
    await createUserClient(),
    gateway,
    projectId,
    { successUrl: `${base}?notice=card_saved`, cancelUrl: `${base}?recovery=cancelled` },
  );
  if (!result.ok) billingPath(projectId, `error=${result.error}`);
  redirect(result.url as never);
}

/** OI-74: the acceptance signer turns off automatic final payment (fresh sign-in code). */
export async function revokeAuthorizationAction(formData: FormData) {
  await requireClient();
  const projectId = String(formData.get("projectId") ?? "");
  const result = await revokePaymentAuthorization(await createUserClient(), {
    projectId,
    reason: String(formData.get("reason") ?? ""),
  });
  // Clients have no authenticator; their fresh reauthentication is a new sign-in code.
  const error =
    !result.ok && result.error === "reauthentication_required"
      ? "client_reauthentication_required"
      : result.ok
        ? null
        : result.error;
  billingPath(projectId, error ? `error=${error}` : "notice=authorization_revoked");
}
