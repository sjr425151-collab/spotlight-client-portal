"use server";

import { redirect } from "next/navigation";

import { env } from "@/config/env";
import { requireSales } from "@/server/auth/guards";
import { uuidSchema } from "@/server/services/invitations";
import {
  createCustomerProject,
  inviteClient,
  issueSalesOrderSummary,
  resendClientInvitation,
  revokeClientInvitation,
} from "@/server/services/sales";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Sales Representative server actions (03 §4.1). Each starts with the Sales guard; every
 * database call re-checks the role, aal2, the live session, and the active assignment, so
 * the guard is never the only control (OI-78). The forms carry no amount, price, scope item,
 * or note: the order summary takes only the package key and a change reason (OI-84(b)).
 */

const text = (formData: FormData, key: string) => String(formData.get(key) ?? "");

function done(path: string, result: { ok: boolean; error?: string }, okCode: string): never {
  const query = result.ok ? `notice=${okCode}` : `error=${result.error ?? "unavailable"}`;
  redirect(`${path}?${query}` as never);
}

function projectPath(projectId: string) {
  return uuidSchema.safeParse(projectId).success ? `/sales/projects/${projectId}` : "/sales";
}

export async function createCustomerAction(formData: FormData) {
  await requireSales();
  const result = await createCustomerProject(await createUserClient(), {
    legalName: text(formData, "legalName"),
    displayName: text(formData, "displayName") || undefined,
    projectName: text(formData, "projectName"),
  });
  if (!result.ok) done("/sales", result, "customer_created");
  done(
    projectPath(result.project_id),
    { ok: true },
    result.existing ? "customer_exists" : "customer_created",
  );
}

export async function issueOrderSummaryAction(formData: FormData) {
  await requireSales({ returnTo: projectPath(text(formData, "projectId")) });
  const projectId = text(formData, "projectId");
  done(
    projectPath(projectId),
    await issueSalesOrderSummary(await createUserClient(), {
      projectId,
      packageKey: text(formData, "packageKey"),
      changeReason: text(formData, "changeReason") || undefined,
    }),
    "order_summary_issued",
  );
}

export async function inviteClientAction(formData: FormData) {
  await requireSales({ returnTo: projectPath(text(formData, "projectId")) });
  const projectId = text(formData, "projectId");
  const result = await inviteClient(
    { user: await createUserClient(), siteUrl: env.NEXT_PUBLIC_SITE_URL },
    { projectId, email: text(formData, "email"), fullName: text(formData, "fullName") },
  );
  done(
    projectPath(projectId),
    result,
    result.ok && !result.emailSent ? "invite_existing_user" : "invite_sent",
  );
}

export async function resendInvitationAction(formData: FormData) {
  await requireSales({ returnTo: projectPath(text(formData, "projectId")) });
  const projectId = text(formData, "projectId");
  done(
    projectPath(projectId),
    await resendClientInvitation(
      { user: await createUserClient(), siteUrl: env.NEXT_PUBLIC_SITE_URL },
      projectId,
      text(formData, "id"),
    ),
    "invitation_resent",
  );
}

export async function revokeInvitationAction(formData: FormData) {
  await requireSales({ returnTo: projectPath(text(formData, "projectId")) });
  const projectId = text(formData, "projectId");
  done(
    projectPath(projectId),
    await revokeClientInvitation(await createUserClient(), text(formData, "id")),
    "invitation_revoked",
  );
}
