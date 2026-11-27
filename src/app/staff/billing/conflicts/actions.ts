"use server";

import { redirect } from "next/navigation";

import { requireOwner } from "@/server/auth/guards";
import {
  applyFinancialConflictDecision,
  conflictDeadlineFrom,
  readFinancialConflictAttemptStatus,
  recordFinancialConflictDecision,
} from "@/server/services/billing";
import { createUserClient } from "@/server/supabase/clients";

/**
 * OI-93 conflict decisions (AUTH-010). Owner only, with fresh MFA; the database re-authorizes
 * the Owner, aal2, fresh MFA, the live session and the reason, and owns every rule. Nothing here
 * contacts Stripe: an application works on recorded events and the ledger.
 */

const PATH = "/staff/billing/conflicts";
const text = (formData: FormData, key: string) => String(formData.get(key) ?? "").trim();

function back(params: Record<string, string>): never {
  redirect(`${PATH}?${new URLSearchParams(params).toString()}` as never);
}

export async function recordConflictDecisionAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: PATH });
  const result = await recordFinancialConflictDecision(await createUserClient(), {
    webhookEventId: text(formData, "webhookEventId"),
    projectId: text(formData, "projectId"),
    evidence: text(formData, "evidence"),
    reason: text(formData, "reason"),
  });
  back(result.ok ? { notice: "conflict_decision_recorded" } : { error: result.error });
}

// Every server action starts with its guard (03 §10). The 45-second deadline (AUTH-010) starts
// immediately after it, before the action's own checks and the database call.
export async function applyConflictDecisionAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: PATH });
  const deadline = conflictDeadlineFrom();
  const decisionId = text(formData, "decisionId");
  const attemptRequestId = text(formData, "attemptRequestId");
  const result = await applyFinancialConflictDecision(
    await createUserClient(),
    { decisionId, attemptRequestId, reason: text(formData, "reason") },
    deadline,
  );
  if (result.ok) {
    const { outcome, terminal_reason } = result.attempt;
    if (outcome === "posted" || outcome === "represented") back({ notice: `conflict_${outcome}` });
    back({ error: terminal_reason === "exhausted" ? "conflict_exhausted" : `conflict_${outcome}` });
  }
  if (result.error === "outcome_unknown") {
    // Never treated as "nothing happened": the page offers only a status read or a resubmission
    // of this same request until the outcome is known.
    back({ error: "outcome_unknown", pending: attemptRequestId, decision: decisionId });
  }
  back({ error: result.error });
}

export async function conflictAttemptStatusAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: PATH });
  const attemptRequestId = text(formData, "attemptRequestId");
  const status = await readFinancialConflictAttemptStatus(
    await createUserClient(),
    attemptRequestId,
  );
  if (!status.ok) back({ error: status.error });
  if (status.status === "recorded") back({ notice: "attempt_status_recorded" });
  back({
    notice: `attempt_status_${status.status}`,
    pending: attemptRequestId,
    decision: text(formData, "decisionId"),
  });
}
