"use server";

import { redirect } from "next/navigation";

import { intakeFromForm } from "@/domain/intake";
import { requireOwner, requireStaff } from "@/server/auth/guards";
import { uuidSchema } from "@/server/services/invitations";
import {
  callRpc,
  retryUploadScan,
  verifyLiveDeployment,
  type Result,
} from "@/server/services/fulfillment";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Staff fulfillment and publication actions (05, 06; 03 §4). Each starts with a guard and
 * the database re-authorizes the role inside the definer function. Owner-only actions with
 * fresh reauthentication (publication authorization, performance exceptions, deployment
 * targets) are checked both here (`requireOwner({ fresh: true })`) and in the database
 * (`private.mfa_is_fresh`). No action can pass, skip, or override a gate (06 §2).
 */

const text = (formData: FormData, key: string) => String(formData.get(key) ?? "");
const flag = (formData: FormData, key: string) => formData.get(key) === "on";
const projectPath = (formData: FormData) => {
  const id = text(formData, "projectId");
  return uuidSchema.safeParse(id).success ? `/staff/projects/${id}` : "/staff";
};

function done(formData: FormData, result: Result, okCode = "saved"): never {
  redirect(
    `${projectPath(formData)}?${result.ok ? `notice=${okCode}` : `error=${result.error}`}` as never,
  );
}

const call = async (fn: string, args: Record<string, unknown>) =>
  callRpc(await createUserClient(), fn, args);

export async function reviewIntakeAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("review_intake", {
      p_submission_id: text(formData, "submissionId"),
      p_decision: text(formData, "decision"),
      p_note: text(formData, "note").slice(0, 2000) || null,
    }),
  );
}

export async function correctIntakeAction(formData: FormData) {
  await requireStaff();
  let content;
  try {
    content = intakeFromForm((k) =>
      typeof formData.get(k) === "string" ? String(formData.get(k)) : null,
    );
  } catch {
    done(formData, { ok: false, error: "invalid_input" });
  }
  done(
    formData,
    await call("correct_intake", {
      p_project_id: text(formData, "projectId"),
      p_content: content,
      p_reason: text(formData, "reason").slice(0, 1000),
    }),
  );
}

export async function decideUploadExceptionAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("decide_upload_exception", {
      p_exception_id: text(formData, "exceptionId"),
      p_approve: text(formData, "decision") === "approve",
      p_reason: text(formData, "reason").slice(0, 1000),
    }),
  );
}

export async function recordPreviewDraftAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("record_preview_draft", {
      p_project_id: text(formData, "projectId"),
      p_commit_sha: text(formData, "commitSha").trim(),
      p_note: text(formData, "note").slice(0, 1000) || null,
    }),
  );
}

export async function releasePreviewAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("release_preview", {
      p_project_id: text(formData, "projectId"),
      p_commit_sha: text(formData, "commitSha").trim(),
      p_deployment_id: text(formData, "deploymentId").trim(),
      p_preview_url: text(formData, "previewUrl").trim(),
      p_asset_upload_ids: formData
        .getAll("assetIds")
        .map(String)
        .filter((id) => uuidSchema.safeParse(id).success),
      p_release_note: text(formData, "note").slice(0, 2000) || null,
    }),
    "preview_released",
  );
}

export async function withdrawPreviewAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("withdraw_preview", {
      p_release_id: text(formData, "releaseId"),
      p_reason: text(formData, "reason").slice(0, 1000),
    }),
  );
}

export async function classifyRevisionAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("classify_revision_request", {
      p_revision_request_id: text(formData, "revisionRequestId"),
      p_scope: text(formData, "scope"),
      p_note: text(formData, "note").slice(0, 1000) || null,
    }),
  );
}

export async function recordOutreachAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("record_outreach", {
      p_release_id: text(formData, "releaseId"),
      p_kind: text(formData, "kind"),
      p_channel: text(formData, "channel"),
      p_occurred_on: text(formData, "occurredOn") || null,
      p_summary: text(formData, "summary").slice(0, 2000),
    }),
  );
}

export async function placeApprovalHoldAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("place_approval_hold", {
      p_project_id: text(formData, "projectId"),
      p_reason: text(formData, "reason").slice(0, 1000),
    }),
  );
}

export async function clearApprovalHoldAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("clear_approval_hold", {
      p_hold_id: text(formData, "holdId"),
      p_reason: text(formData, "reason").slice(0, 1000),
    }),
  );
}

export async function recordHoldResumptionAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("record_hold_resumption", {
      p_hold_id: text(formData, "holdId"),
      p_decision: text(formData, "decision"),
      p_note: text(formData, "note").slice(0, 1000) || null,
    }),
  );
}

const QA_AREAS = [
  "functional",
  "responsive",
  "branding_content",
  "performance",
  "accessibility",
  "security",
  "domain_operational",
  "monitoring_rollback",
] as const;
const SECURITY_KEYS = [
  "https_hsts",
  "security_headers",
  "no_exposed_secrets",
  "dependency_scan",
  "form_abuse_protection",
  "no_debug_endpoints",
  "admin_surfaces_protected",
] as const;
const result = (formData: FormData, key: string) => {
  const value = text(formData, key);
  return value === "pass" || value === "not_applicable" ? value : "fail";
};

export async function recordQaAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("record_qa_result", {
      p_release_id: text(formData, "releaseId"),
      p_checklist_version: "r1-v1",
      p_items: QA_AREAS.map((area) => ({
        key: area,
        area,
        result: result(formData, `qa_${area}`),
        ...(text(formData, `ev_${area}`)
          ? { evidence: text(formData, `ev_${area}`).slice(0, 500) }
          : {}),
      })),
    }),
  );
}

export async function recordSecurityAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("record_security_result", {
      p_release_id: text(formData, "releaseId"),
      p_checklist_version: "r1-v1",
      p_items: SECURITY_KEYS.map((key) => ({
        key,
        severity: key === "dependency_scan" ? "high" : "critical",
        result: result(formData, `sec_${key}`),
      })),
    }),
  );
}

export async function approvePerformanceExceptionAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: projectPath(formData) });
  let measured: unknown = null;
  try {
    measured = JSON.parse(text(formData, "measuredValues"));
  } catch {
    done(formData, { ok: false, error: "invalid_input" });
  }
  done(
    formData,
    await call("approve_performance_exception", {
      p_release_id: text(formData, "releaseId"),
      p_measured_values: measured,
      p_reason: text(formData, "reason").slice(0, 1000),
    }),
  );
}

export async function recordDomainCheckAction(formData: FormData) {
  await requireStaff();
  const spotlight = flag(formData, "spotlightRegistered");
  done(
    formData,
    await call("record_domain_check", {
      p_project_id: text(formData, "projectId"),
      p_domain: text(formData, "domain"),
      p_dns_ok: flag(formData, "dnsOk"),
      p_tls_ok: flag(formData, "tlsOk"),
      p_redirect_ok: flag(formData, "redirectOk"),
      p_registrant_ok:
        text(formData, "registrant") === "na" ? null : flag(formData, "registrantOk"),
      p_charges_disclosed: flag(formData, "chargesDisclosed"),
      p_spotlight_registered: spotlight,
      p_registration_date: spotlight ? text(formData, "registrationDate") || null : null,
      p_registrar_expiry: spotlight ? text(formData, "registrarExpiry") || null : null,
      p_notes: text(formData, "notes").slice(0, 1000) || null,
    }),
  );
}

export async function registerSiteTargetAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: projectPath(formData) });
  done(
    formData,
    await call("register_client_site_target", {
      p_project_id: text(formData, "projectId"),
      p_target_ref: text(formData, "targetRef").trim(),
    }),
  );
}

export async function authorizePublicationAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: projectPath(formData) });
  if (text(formData, "confirm") !== "yes")
    done(formData, { ok: false, error: "confirmation_required" });
  done(
    formData,
    await call("authorize_publication", {
      p_project_id: text(formData, "projectId"),
      p_release_id: text(formData, "releaseId"),
    }),
    "publication_authorized",
  );
}

export async function startDeploymentAction(formData: FormData) {
  await requireStaff();
  done(
    formData,
    await call("start_deployment", {
      p_authorization_id: text(formData, "authorizationId"),
    }),
    "deployment_started",
  );
}

export async function recordDeploymentAction(formData: FormData) {
  await requireStaff();
  const succeeded = text(formData, "outcome") === "succeeded";
  done(
    formData,
    await call("record_deployment_result", {
      p_deployment_id: text(formData, "deploymentId"),
      p_succeeded: succeeded,
      p_provider_deployment_id: succeeded ? text(formData, "providerDeploymentId").trim() : null,
      p_production_url: succeeded ? text(formData, "productionUrl").trim() : null,
      p_failure_reason: succeeded ? null : text(formData, "failureReason").slice(0, 1000),
    }),
  );
}

export async function verifyLiveAction(formData: FormData) {
  const ctx = await requireStaff();
  done(
    formData,
    await verifyLiveDeployment(
      await createUserClient(),
      text(formData, "deploymentId"),
      ctx.userId,
    ),
    "verification_recorded",
  );
}

export async function resolveIncidentAction(formData: FormData) {
  await requireOwner();
  done(
    formData,
    await call("resolve_incident", {
      p_incident_id: text(formData, "incidentId"),
      p_resolution: text(formData, "resolution").slice(0, 2000),
    }),
  );
}

export async function retryScanAction(formData: FormData) {
  await requireStaff();
  const result = await retryUploadScan(await createUserClient(), text(formData, "uploadId"));
  done(formData, result, result.ok ? `upload_${String(result.data.outcome)}` : "saved");
}
