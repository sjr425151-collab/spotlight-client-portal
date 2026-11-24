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
 * and subscription domains are financial, everything else is general. Pending Owner
 * confirmation in OI-71.
 */
import type { OwnerPackage } from "./domain-events";
import type { StateDomain } from "./state-domains";

export const AUDIT_ACTION_PATTERN = /^[a-z][a-z_]*\.[a-z][a-z_]*$/;
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
];

export function auditAction(name: string): AuditAction {
  const found = AUDIT_ACTIONS.find((a) => a.action === name);
  if (!found) throw new Error(`Unregistered audit action: ${name}`);
  return found;
}
