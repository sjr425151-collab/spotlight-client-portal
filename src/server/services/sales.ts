import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { z } from "zod";

import { isPackageKey } from "@/domain/billing/pricing";
import {
  createInvitation,
  createInvitationSchema,
  resendInvitation,
  uuidSchema,
  type CreateInvitationResult,
  type ResendResult,
} from "@/server/services/invitations";

/**
 * Sales Representative services (03 §4.1; OI-77, OI-78, OI-83, OI-84). Every call goes
 * through a SECURITY DEFINER function that checks the Sales role, aal2, the live session, and
 * the active assignment at the time of the call. These services only validate shape and
 * orchestrate; they never decide access, and never pass amounts, scope items, or notes.
 */

type Fail = { ok: false; error: string };

function unwrap<T extends object>(data: unknown, error: unknown): ({ ok: true } & T) | Fail {
  if (error || !data || typeof data !== "object") return { ok: false, error: "unavailable" };
  const row = data as { ok?: boolean; error?: string };
  return row.ok ? (data as { ok: true } & T) : { ok: false, error: row.error ?? "unavailable" };
}

export const createCustomerSchema = z.object({
  legalName: z.string().trim().min(1).max(200),
  displayName: z.string().trim().max(200).optional(),
  projectName: z.string().trim().min(1).max(200),
});

export interface SalesCustomer {
  project_id: string;
  project_name: string;
  client_business_id: string;
  business_legal_name: string;
  business_display_name: string;
  assigned_at: string;
}

export interface SalesPendingInvitation {
  id: string;
  email: string;
  full_name: string;
  status: "pending" | "expired";
  sent_at: string;
  expires_at: string;
}

export interface SalesProgress {
  project: { id: string; name: string; created_at: string };
  business: { legal_name: string; display_name: string };
  order_summary: {
    id: string;
    revision: number;
    status: "presented" | "superseded";
    package_key: string;
    package_display_name: string | null;
    package_total_cents: number;
    deposit_cents: number;
    balance_cents: number;
    maintenance_monthly_cents: number;
    currency: string;
    scope_items: string[];
    issued_at: string;
  } | null;
  progress: {
    agreement_state: string | null;
    agreement_effective: boolean;
    deposit_requirement_satisfied: boolean;
    final_balance_requirement_satisfied: boolean;
    billing_operational_hold: boolean;
    intake_state: string | null;
    preview_approved: boolean;
    publication_eligible: boolean;
  };
  pending_invitations: SalesPendingInvitation[];
}

/** Customer, project, and self-assignment in one database transaction (OI-77 refinement 3). */
export async function createCustomerProject(user: SupabaseClient, input: unknown) {
  const parsed = createCustomerSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "invalid_input" } as Fail;
  const { data, error } = await user.rpc("sales_create_customer_project", {
    p_legal_name: parsed.data.legalName,
    p_display_name: parsed.data.displayName || null,
    p_project_name: parsed.data.projectName,
  });
  return unwrap<{ project_id: string; existing: boolean }>(data, error);
}

export async function listCustomers(user: SupabaseClient) {
  const { data, error } = await user.rpc("sales_list_customers");
  return unwrap<{ customers: SalesCustomer[] }>(data, error);
}

export async function projectProgress(user: SupabaseClient, projectId: string) {
  if (!uuidSchema.safeParse(projectId).success) return { ok: false, error: "not_found" } as Fail;
  const { data, error } = await user.rpc("sales_project_progress", { p_project_id: projectId });
  return unwrap<SalesProgress>(data, error);
}

export const salesOrderSchema = z.object({
  projectId: uuidSchema,
  packageKey: z.string().refine(isPackageKey),
  changeReason: z.string().trim().max(1000).optional(),
});

/**
 * OI-84(b): a Sales order summary takes the package key and an optional noncontractual
 * change reason only. Pricing and the standard scope are resolved by the database.
 */
export async function issueSalesOrderSummary(user: SupabaseClient, input: unknown) {
  const parsed = salesOrderSchema.safeParse(input);
  if (!parsed.success) return { ok: false, error: "invalid_input" } as Fail;
  const { data, error } = await user.rpc("issue_order_summary", {
    p_project_id: parsed.data.projectId,
    p_package_key: parsed.data.packageKey,
    p_change_reason: parsed.data.changeReason || null,
  });
  return unwrap<{ order_summary_id: string; revision: number }>(data, error);
}

export async function inviteClient(
  deps: { user: SupabaseClient; siteUrl: string },
  input: { projectId: string; email: string; fullName: string },
): Promise<CreateInvitationResult> {
  const parsed = createInvitationSchema.safeParse({ kind: "client", ...input });
  if (!parsed.success) return { ok: false, error: "invalid_input" };
  return createInvitation(deps, parsed.data);
}

export async function revokeClientInvitation(user: SupabaseClient, invitationId: string) {
  if (!uuidSchema.safeParse(invitationId).success) return { ok: false, error: "not_found" } as Fail;
  const { data, error } = await user.rpc("revoke_invitation", { p_invitation_id: invitationId });
  return unwrap<object>(data, error);
}

/**
 * Resend for a Sales Representative: the invitation is looked up in the assignment-checked
 * progress view (never from the form), then revoked and reissued (OI-84(d)).
 */
export async function resendClientInvitation(
  deps: { user: SupabaseClient; siteUrl: string },
  projectId: string,
  invitationId: string,
): Promise<ResendResult> {
  const progress = await projectProgress(deps.user, projectId);
  if (!progress.ok) return { ok: false, error: "not_found", revoked: false };
  const pending = progress.pending_invitations.find((i) => i.id === invitationId);
  if (!pending) return { ok: false, error: "not_found", revoked: false };
  return resendInvitation(deps, {
    id: pending.id,
    kind: "client",
    email: pending.email,
    fullName: pending.full_name,
    projectId,
  });
}
