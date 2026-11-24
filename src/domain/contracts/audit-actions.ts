/**
 * Audit action names shared by WP-B and WP-C (WP-0; spec 01 §7, 03 §11).
 *
 * Every name here is quoted from an approved specification. Packages add the names they
 * need in their own section, citing the spec. Audit rows are still written only through
 * `private.record_audit_event` or the audit row triggers (03 §11); this list fixes the
 * names and the `category` argument so both packages use them consistently.
 *
 * Category: `financial` rows are hidden from Admin by the existing `audit_events` policy
 * (03 §4). The rule used here is the same as for domain events: actions in the payment
 * and subscription domains are financial, everything else is general (confirmed in OI-71
 * item 4).
 */
import type { OwnerPackage } from "./domain-events";
import type { StateDomain } from "./state-domains";

/**
 * Digits are allowed after the first letter of each segment (additive, WP-C): 05 §7.1 names
 * `approval.reminder_1_sent` and `approval.reminder_2_sent`. Every earlier name still matches.
 */
export const AUDIT_ACTION_PATTERN = /^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$/;
/** `audit_events_action_bounded` (Phase 2 migration). */
export const AUDIT_ACTION_MAX_LENGTH = 100;

export type AuditCategory = "general" | "financial";

export interface AuditAction {
  readonly action: string;
  readonly domain: StateDomain;
  readonly category: AuditCategory;
  readonly owner: OwnerPackage;
  readonly spec: string;
}

const b = (action: string, domain: StateDomain, spec: string): AuditAction => ({
  action,
  domain,
  category: domain === "payment" || domain === "subscription" ? "financial" : "general",
  owner: "WP-B",
  spec,
});
const c = (action: string, domain: StateDomain, spec: string): AuditAction => ({
  action,
  domain,
  category: domain === "payment" || domain === "subscription" ? "financial" : "general",
  owner: "WP-C",
  spec,
});

export const AUDIT_ACTIONS: readonly AuditAction[] = [
  // --- WP-B: agreements, payments, subscription ---
  b("agreement.accepted", "agreement", "04 §3"),
  b("agreement.effective", "agreement", "04 §1"),
  b("checkout.session_created", "payment", "04 §8"),
  b("balance.collection_authorized", "payment", "04 §10"),
  b("balance.charge_attempted", "payment", "04 §10"),
  b("balance.charge_succeeded", "payment", "04 §10"),
  b("balance.charge_failed", "payment", "04 §10"),
  b("balance.action_required", "payment", "04 §10"),
  b("cancellation.requested", "subscription", "04 §15.1.1"),
  b("cancellation.confirmed", "subscription", "04 §15.1.1"),
  b("cancellation.effective", "subscription", "04 §15.1.1"),
  b("cancellation.milestones_notified", "subscription", "04 §15.1.1"),
  b("cancellation.notice_sent", "subscription", "04 §15.1.1"),
  b("cancellation.maintenance_ceased", "subscription", "04 §15.1.1"),
  b("cancellation.services_deactivated", "subscription", "04 §15.1.1"),
  b("cancellation.transferred", "subscription", "04 §15.1.1"),
  // --- WP-C: intake, approvals, publication ---
  c("intake.submitted", "fulfillment", "05 §3"),
  c("intake.changes_requested", "fulfillment", "05 §3"),
  c("intake.accepted", "fulfillment", "05 §3"),
  c("intake.edited_by_staff", "fulfillment", "05 §3"),
  c("preview.released", "approval", "05 §7"),
  c("preview.approved", "approval", "05 §7"),
  c("preview.superseded", "approval", "05 §7"),
  c("preview.withdrawn", "approval", "05 §7"),
  c("approval_hold.placed", "approval", "05 §7.1"),
  c("approval_hold.client_response", "approval", "05 §7.1"),
  c("approval_hold.cleared", "approval", "05 §7.1"),
  c("approval_hold.resumption_decided", "approval", "05 §7.1"),
  c("publication.authorized", "deployment", "06 §3"),
  c("publication.authorization_rejected", "deployment", "06 §3"),
  c("deployment.started", "deployment", "06 §8"),
  c("deployment.succeeded", "deployment", "06 §8"),
  c("deployment.failed", "deployment", "06 §8"),
  // --- WP-C additions (05 §3-§7.2, 06 §2-§9). Same rule: all general (non-financial). ---
  c("upload.requested", "fulfillment", "05 §4"),
  c("upload.completed", "fulfillment", "05 §5"),
  c("upload.failed", "fulfillment", "05 §5"),
  c("upload.scan_recorded", "fulfillment", "05 §5"),
  c("upload.rejected", "fulfillment", "05 §5"),
  c("upload.released", "fulfillment", "05 §5"),
  c("upload.purged", "fulfillment", "05 §5"),
  c("upload.accessed", "fulfillment", "05 §4"),
  c("upload.exception_requested", "fulfillment", "05 §5"),
  c("upload.exception_decided", "fulfillment", "05 §5"),
  c("upload.access_revoked", "fulfillment", "05 §5.5"),
  // PR #19 review corrections (H1, M2): durable deletion of revoked objects and refused
  // requests, under 05 §4 ("upload and access history are audited") and 05 §5.5 rule 3.
  c("upload.refused", "fulfillment", "05 §4"),
  c("upload.object_deleted", "fulfillment", "05 §5.5"),
  c("upload.object_deletion_failed", "fulfillment", "05 §5.5"),
  c("upload.object_deletion_retried", "fulfillment", "05 §5.5"),
  c("preview.draft_recorded", "approval", "05 §6"),
  c("preview.revision_requested", "approval", "05 §8"),
  c("preview.revision_classified", "approval", "05 §8"),
  c("approval.reminder_1_sent", "approval", "05 §7.1"),
  c("approval.reminder_2_sent", "approval", "05 §7.1"),
  c("approval.admin_notified", "approval", "05 §7.1"),
  c("approval.personal_followup_recorded", "approval", "05 §7.1"),
  c("approval_hold.clear_rejected", "approval", "05 §7.2"),
  c("qa.recorded", "deployment", "06 §6"),
  c("qa.performance_exception_approved", "deployment", "06 §2"),
  c("security_check.recorded", "deployment", "06 §7"),
  c("domain.readiness_recorded", "deployment", "06 §5"),
  c("client_site.target_registered", "deployment", "06 §4"),
  c("publication.authorization_invalidated", "deployment", "06 §3"),
  c("deployment.start_rejected", "deployment", "06 §8"),
  c("deployment.verification_recorded", "deployment", "06 §9"),
  c("incident.opened", "deployment", "06 §8"),
  c("incident.resolved", "deployment", "06 §8"),
];

export function auditAction(name: string): AuditAction {
  const found = AUDIT_ACTIONS.find((a) => a.action === name);
  if (!found) throw new Error(`Unregistered audit action: ${name}`);
  return found;
}
