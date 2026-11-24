"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { requireOwner, requireStaff } from "@/server/auth/guards";
import { issueOrderSummary } from "@/server/services/billing";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Staff billing actions (spec 04 §4, §14; 03 §4; OI-72). Each starts with a guard, and the
 * database re-authorizes the role, aal2, the live session, and fresh MFA where required.
 */

const uuid = z.uuid();
const text = (formData: FormData, key: string) => String(formData.get(key) ?? "").trim();

function back(
  projectId: string,
  result: { ok?: boolean; error?: string } | null,
  okCode: string,
): never {
  const path = uuid.safeParse(projectId).success ? `/staff/projects/${projectId}` : "/staff";
  const query = result?.ok ? `notice=${okCode}` : `error=${result?.error ?? "unavailable"}`;
  redirect(`${path}?${query}` as never);
}

export async function issueOrderSummaryAction(formData: FormData) {
  await requireStaff();
  const projectId = text(formData, "projectId");
  const result = await issueOrderSummary(await createUserClient(), {
    projectId,
    packageKey: text(formData, "packageKey"),
    scopeItems: text(formData, "scopeItems")
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean),
    projectNotes: text(formData, "projectNotes") || undefined,
    changeReason: text(formData, "changeReason") || undefined,
  });
  back(projectId, result, "order_summary_issued");
}

export async function placeBillingHoldAction(formData: FormData) {
  await requireOwner();
  const projectId = text(formData, "projectId");
  const { data } = await (
    await createUserClient()
  ).rpc("place_billing_hold", {
    p_project_id: uuid.safeParse(projectId).success ? projectId : null,
    p_hold_type:
      text(formData, "holdType") === "dispute_risk_hold"
        ? "dispute_risk_hold"
        : "owner_manual_hold",
    p_reason: text(formData, "reason").slice(0, 1000),
  });
  back(projectId, data as { ok?: boolean; error?: string } | null, "hold_placed");
}

export async function clearBillingHoldAction(formData: FormData) {
  await requireOwner();
  const projectId = text(formData, "projectId");
  // A system hold exception needs fresh reauthentication (OI-26); the database checks too.
  if (text(formData, "holdType") === "maintenance_payment_hold") {
    await requireOwner({
      fresh: true,
      returnTo: uuid.safeParse(projectId).success ? `/staff/projects/${projectId}` : "/staff",
    });
  }
  const holdId = text(formData, "holdId");
  const { data } = await (
    await createUserClient()
  ).rpc("clear_billing_hold", {
    p_hold_id: uuid.safeParse(holdId).success ? holdId : null,
    p_reason: text(formData, "reason").slice(0, 1000),
  });
  back(projectId, data as { ok?: boolean; error?: string } | null, "hold_cleared");
}

/** OI-74: the Owner records a revocation received outside the portal (fresh MFA, reason). */
export async function recordAuthorizationRevocationAction(formData: FormData) {
  await requireOwner();
  const projectId = text(formData, "projectId");
  // Fresh reauthentication (03 §7); the database checks it again.
  await requireOwner({
    fresh: true,
    returnTo: uuid.safeParse(projectId).success ? `/staff/projects/${projectId}` : "/staff",
  });
  const { data } = await (
    await createUserClient()
  ).rpc("record_payment_authorization_revocation", {
    p_project_id: uuid.safeParse(projectId).success ? projectId : null,
    p_reason: text(formData, "reason").slice(0, 1000),
  });
  back(projectId, data as { ok?: boolean; error?: string } | null, "authorization_revoked_staff");
}

/** OI-74: the Owner reviews a revocation (fresh MFA, note). */
export async function reviewAuthorizationRevocationAction(formData: FormData) {
  await requireOwner();
  const projectId = text(formData, "projectId");
  // Fresh reauthentication (03 §7); the database checks it again.
  await requireOwner({
    fresh: true,
    returnTo: uuid.safeParse(projectId).success ? `/staff/projects/${projectId}` : "/staff",
  });
  const { data } = await (
    await createUserClient()
  ).rpc("review_authorization_revocation", {
    p_project_id: uuid.safeParse(projectId).success ? projectId : null,
    p_note: text(formData, "note").slice(0, 1000),
  });
  back(projectId, data as { ok?: boolean; error?: string } | null, "revocation_reviewed");
}
