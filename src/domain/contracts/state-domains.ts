/**
 * State-domain contract (WP-0; spec 05 §2, 01 §7, R1 acceptance item 9).
 *
 * Each list mirrors a Postgres enum created by
 * `supabase/migrations/20261124120000_wp0_shared_contracts.sql`, in the same order.
 * `tests/unit/contracts.test.ts` fails if the two ever diverge.
 *
 * The domains are tracked separately: no dimension is derived from another, and gates are
 * computed from records, never from an editable status (05 §2; 06 §2).
 */

/** The six separately tracked state domains (01 §7). */
export const STATE_DOMAINS = [
  "agreement",
  "payment",
  "subscription",
  "fulfillment",
  "approval",
  "deployment",
] as const;
export type StateDomain = (typeof STATE_DOMAINS)[number];

/** Domains whose records Admin may not read (03 §4 "non-financial" rule). */
export const FINANCIAL_DOMAINS = [
  "payment",
  "subscription",
] as const satisfies readonly StateDomain[];

export function isFinancialDomain(domain: StateDomain): boolean {
  return (FINANCIAL_DOMAINS as readonly StateDomain[]).includes(domain);
}

/** Agreement (04 §1). Domain: agreement. */
export const AGREEMENT_STATES = [
  "not_presented",
  "presented",
  "accepted_pending_payment",
  "effective",
  "superseded",
  "reacceptance_required",
  "expired",
] as const;
export type AgreementState = (typeof AGREEMENT_STATES)[number];

/** Deposit. Changes only through verified webhook processing (04 §11). Domain: payment. */
export const DEPOSIT_STATES = [
  "not_started",
  "pending",
  "verified",
  "failed",
  "refunded",
  "disputed",
] as const;
export type DepositState = (typeof DEPOSIT_STATES)[number];

/** Final balance. Changes only through verified webhook processing. Domain: payment. */
export const FINAL_BALANCE_STATES = [
  "not_due",
  "due",
  "pending",
  "verified",
  "failed",
  "refunded",
  "disputed",
  "settled_by_adjustment",
] as const;
export type FinalBalanceState = (typeof FINAL_BALANCE_STATES)[number];

/**
 * Mirror of the Stripe subscription status (04 §11), verified against Stripe's OpenAPI
 * specification 2026-09-30.endive. Domain: subscription.
 */
export const SUBSCRIPTION_STATUSES = [
  "incomplete",
  "incomplete_expired",
  "trialing",
  "active",
  "past_due",
  "canceled",
  "unpaid",
  "paused",
] as const;
export type SubscriptionStatus = (typeof SUBSCRIPTION_STATUSES)[number];

/** Owner-authorized service termination, independent of the Stripe status (04 §9.1.1). */
export const SERVICE_TERMINATION_STATES = [
  "none",
  "under_owner_review",
  "termination_authorized",
  "effective",
  "maintenance_ceased",
  "offboarded",
  "transferred",
  "withdrawn",
] as const;
export type ServiceTerminationState = (typeof SERVICE_TERMINATION_STATES)[number];

/** Intake. Domain: fulfillment. */
export const INTAKE_STATES = [
  "locked",
  "open",
  "submitted",
  "accepted_by_staff",
  "changes_requested",
] as const;
export type IntakeState = (typeof INTAKE_STATES)[number];

/** Development milestones: informational only, never a gate (05 §2). Domain: fulfillment. */
export const DEVELOPMENT_STATES = [
  "not_started",
  "in_progress",
  "ready_for_preview",
  "paused",
] as const;
export type DevelopmentState = (typeof DEVELOPMENT_STATES)[number];

/** Per preview release (05 §6-§7). Domain: approval. */
export const RELEASE_APPROVAL_STATES = ["released", "approved", "superseded", "withdrawn"] as const;
export type ReleaseApprovalState = (typeof RELEASE_APPROVAL_STATES)[number];

/** Publication eligibility and deployment (06). Domain: deployment. */
export const PUBLICATION_STATES = [
  "not_eligible",
  "eligible",
  "authorized",
  "deploying",
  "live_unverified",
  "live_verified",
  "failed",
  "rolled_back",
] as const;
export type PublicationState = (typeof PUBLICATION_STATES)[number];

/**
 * Hold types (04 §14). OI-71 item 3 (decided): `maintenance_payment_hold`, `dispute_risk_hold`
 * and `owner_manual_hold` are WP-B records reported in `active_billing_holds`;
 * `approval_nonresponsive_hold` is a WP-C hold reported in `active_fulfillment_holds`.
 */
export const HOLD_TYPES = [
  "maintenance_payment_hold",
  "approval_nonresponsive_hold",
  "dispute_risk_hold",
  "owner_manual_hold",
] as const;
export type HoldType = (typeof HOLD_TYPES)[number];

/** Which domain each state dimension belongs to. */
export const DIMENSION_DOMAIN = {
  agreement_state: "agreement",
  deposit_state: "payment",
  final_balance_state: "payment",
  subscription_status: "subscription",
  service_termination_state: "subscription",
  intake_state: "fulfillment",
  development_state: "fulfillment",
  release_approval_state: "approval",
  publication_state: "deployment",
} as const satisfies Record<string, StateDomain>;
