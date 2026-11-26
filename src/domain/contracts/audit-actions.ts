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
  // WP-B implementation (03 §11 minimum catalog; 04). Additive.
  b("agreement_version.created", "agreement", "04 §2"),
  b("agreement_version.approved", "agreement", "04 §2"),
  b("agreement.hash_mismatch", "agreement", "04 §3"),
  b("agreement.reacceptance_required", "agreement", "03 §11"),
  b("order_summary.issued", "agreement", "03 §11"),
  b("order_summary.superseded", "agreement", "03 §11"),
  b("order_summary.catalog_mismatch", "agreement", "04 §7"),
  b("checkout.session_requested", "payment", "04 §17"),
  b("checkout.session_completed", "payment", "04 §11"),
  b("checkout.price_verification_failed", "payment", "04 §7"),
  b("payment.deposit_verified", "payment", "04 §11"),
  b("outbound.request_failed", "payment", "04 §6.4"),
  b("outbound.request_ambiguous", "payment", "04 §6.4"),
  b("outbound.request_reconciled", "payment", "04 §6.4"),
  b("outbound.request_retried", "payment", "04 §10"),
  b("outbound.livemode_mismatch", "payment", "04 §6.3"),
  b("outbound.claim_token_rejected", "payment", "04 §6.4"),
  b("webhook.received", "payment", "03 §11"),
  b("webhook.processed", "payment", "03 §11"),
  b("webhook.rejected", "payment", "03 §11"),
  b("webhook.quarantined", "payment", "04 §11"),
  b("webhook.processing_failed", "payment", "04 §17"),
  b("quarantine.resolved", "payment", "04 §11"),
  b("ledger.entry_posted", "payment", "03 §11"),
  b("refund.recorded", "payment", "04 §15.2"),
  b("refund.decision_recorded", "payment", "04 §15.2"),
  b("refund.decision_denied", "payment", "04 §15.2"),
  b("dispute.opened", "payment", "04 §15.4"),
  b("dispute.updated", "payment", "04 §15.4"),
  b("dispute.closed", "payment", "04 §15.4"),
  b("hold.placed", "payment", "04 §14"),
  b("hold.cleared", "payment", "04 §14"),
  b("hold.exception_authorized", "payment", "04 §14"),
  b("hold.placement_denied", "payment", "03 §4"),
  b("hold.clear_denied", "payment", "03 §4"),
  b("release_approval.rejected", "payment", "04 §10"),
  b("release_approval.duplicate", "payment", "04 §10"),
  b("reconciliation.mismatch", "payment", "04 §13"),
  b("reconciliation.completed", "payment", "04 §13"),
  b("reconciliation.mismatch_resolved", "payment", "04 §13"),
  b("maintenance.payment_failed", "subscription", "04 §9.1"),
  b("maintenance.payment_recovered", "subscription", "04 §9.1"),
  b("subscription.status_mirrored", "subscription", "04 §11"),
  b("billing_hold.review_decided", "subscription", "04 §9.1.1"),
  b("billing_hold.review_denied", "subscription", "04 §9.1.1"),
  b("termination.review_opened", "subscription", "04 §9.1.1"),
  b("termination.authorized", "subscription", "03 §11"),
  b("termination.authorization_denied", "subscription", "04 §9.1.1"),
  b("termination.effective", "subscription", "03 §11"),
  b("termination.withdrawn", "subscription", "03 §11"),
  b("stripe.cancellation_exception", "subscription", "03 §11"),
  b("stripe.cancellation_exception_resolved", "subscription", "04 §9.1.1"),
  b("cancellation.maintenance_cessation_rejected", "subscription", "04 §15.1"),
  b("cancellation.deactivation_rejected", "subscription", "04 §15.1"),
  // WP-B, OI-74, OI-81, OI-82, 04 §13 (additive).
  b("order_summary.price_change_rejected", "agreement", "04 §4"),
  b("payment_authorization.established", "payment", "04 §8.1"),
  b("payment_authorization.unavailable", "payment", "04 §8.1"),
  b("payment_authorization.unavailable_at_deposit", "payment", "04 §8.1"),
  b("payment_authorization.revoked", "payment", "04 §8.1"),
  b("payment_authorization.revocation_denied", "payment", "04 §8.1"),
  b("payment_authorization.revocation_reviewed", "payment", "04 §8.1"),
  b("payment_method.recovery_session_created", "payment", "04 §8.1"),
  b("payment_method.replaced", "payment", "04 §8.1"),
  b("payment_method.recovery_failed", "payment", "04 §8.1"),
  b("payment_method.recovery_attempt_failed", "payment", "04 §8.1"),
  b("payment_method.recovery_rejected", "payment", "04 §8.1"),
  b("payment_method.lookup_rejected", "payment", "04 §8.1"),
  b("balance.automatic_collection_halted", "payment", "04 §10"),
  b("balance.automatic_collection_superseded", "payment", "04 §10"),
  b("balance.automatic_collection_disabled", "payment", "04 §10"),
  b("balance.charged_after_halt", "payment", "04 §10"),
  b("reversal.holding_posted", "payment", "04 §15.2.1"),
  b("reversal.reconciled", "payment", "04 §15.2.1"),
  b("reversal.reconciliation_denied", "payment", "04 §15.2.1"),
  b("billing_job.started", "payment", "04 §13"),
  b("billing_job.completed", "payment", "04 §13"),
  b("billing_job.skipped", "payment", "04 §13"),
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

// --- WP-S: Sales Representative actions (03 §4.1; OI-77, OI-78, OI-84; AUTH-005) ---
// A separate list, so the WP-B / WP-C ownership rule above is unchanged. All general
// (non-financial). Invitation and order-summary events keep their existing names; the actor's
// role ("sales") is recorded on every row by private.record_audit_event.
export interface WpSAuditAction {
  readonly action: string;
  readonly category: "general";
  readonly owner: "WP-S";
  readonly spec: string;
}
const s = (action: string, spec: string): WpSAuditAction => ({
  action,
  category: "general",
  owner: "WP-S",
  spec,
});
export const WP_S_AUDIT_ACTIONS: readonly WpSAuditAction[] = [
  s("sales.customer_created", "03 §4.1"),
  s("sales_assignment.created", "03 §4.1"),
  s("sales_assignment.ended", "03 §4.1"),
  s("sales_assignment.reassigned", "03 §4.1"),
  s("sales.rate_limited", "03 §4.1"),
  // Reason kind only: scope_input, notes_input, after_acceptance, missing_scope_definition (OI-84).
  s("sales.order_summary_rejected", "03 §4.1"),
  // Rejected and audited attempts required by 03 §4.1 (assignment manipulation, T-SALES-16;
  // client-role separation, T-SALES-24).
  s("sales_assignment.change_rejected", "03 §4.1"),
  s("invitation.create_rejected", "03 §4.1"),
  s("staff_role.sales_assignment_rejected", "03 §4.1"),
];

/** The reason kinds `sales.order_summary_rejected` may carry (OI-84(b), (c)). */
export const SALES_ORDER_REJECTION_REASONS = [
  "scope_input",
  "notes_input",
  "after_acceptance",
  "missing_scope_definition",
] as const;
