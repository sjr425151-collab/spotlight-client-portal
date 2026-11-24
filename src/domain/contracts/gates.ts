/**
 * Gate-interface contract (WP-0; spec 01 §7, 06 §2).
 *
 * The single gate evaluator (06 §2, owned by WP-C and reviewed by WP-B) reads only:
 * - `private.project_financial_status(project_id)`, owned by WP-B
 * - `private.project_fulfillment_status(project_id)`, owned by WP-C
 *
 * The attribute lists below mirror the Postgres composite types in the WP-0 migration, in
 * order; `tests/unit/contracts.test.ts` checks them. Until an owning package implements its
 * function, it returns `implemented: false` and no satisfied input, so no gate can pass.
 *
 * OI-71 (decided): G1 derives from the financial interface (WP-B added `agreement_state` and
 * `agreement_effective`, contract version 2; OI-74 added `payment_authorization_ready` and
 * `payment_authorization_state`, contract version 3), G6 from the fulfillment interface (WP-C added `domain_ready`,
 * `domain_check_id`, `domain_checked_at`, contract version 2), and G8 is the fail-closed
 * union of both hold lists in the single evaluator. Extending a status type is additive.
 */
import type {
  AgreementState,
  DepositState,
  FinalBalanceState,
  HoldType,
  IntakeState,
} from "./state-domains";

export const FINANCIAL_STATUS_ATTRIBUTES = [
  "project_id",
  "contract_version",
  "implemented",
  "deposit_state",
  "deposit_verified",
  "final_balance_state",
  "balance_verified_or_settled",
  "balance_settled_by_adjustment",
  "active_billing_holds",
  "evidence",
  // WP-B, contract versions 2-3 (OI-71 item 1, OI-74): FINANCIAL_STATUS_WPB_ATTRIBUTES.
  "agreement_state",
  "agreement_effective",
  "payment_authorization_ready",
  "payment_authorization_state",
] as const;

export const FULFILLMENT_STATUS_ATTRIBUTES = [
  "project_id",
  "contract_version",
  "implemented",
  "intake_state",
  "intake_accepted",
  "current_release_id",
  "current_release_approved",
  "current_release_approval_id",
  "qa_passed",
  "security_passed",
  "active_fulfillment_holds",
  "evidence",
  // WP-C, contract version 2 (OI-71 item 2): G6 domain readiness.
  "domain_ready",
  "domain_check_id",
  "domain_checked_at",
] as const;

export interface ProjectFinancialStatus {
  project_id: string;
  contract_version: number;
  implemented: boolean;
  deposit_state: DepositState;
  deposit_verified: boolean;
  final_balance_state: FinalBalanceState;
  balance_verified_or_settled: boolean;
  /** G4 must always disclose an adjustment (06 §2). */
  balance_settled_by_adjustment: boolean;
  active_billing_holds: HoldType[];
  evidence: Record<string, unknown>;
  /** WP-B, contract_version 2 (OI-71 item 1): G1 is `agreement_effective`. */
  agreement_state: AgreementState;
  agreement_effective: boolean;
  /** WP-B, contract_version 3 (OI-74): intake needs a ready payment authorization. */
  payment_authorization_ready: boolean;
  payment_authorization_state: PaymentAuthorizationState;
}

export interface ProjectFulfillmentStatus {
  project_id: string;
  contract_version: number;
  implemented: boolean;
  intake_state: IntakeState;
  intake_accepted: boolean;
  current_release_id: string | null;
  current_release_approved: boolean;
  current_release_approval_id: string | null;
  qa_passed: boolean;
  security_passed: boolean;
  active_fulfillment_holds: HoldType[];
  evidence: Record<string, unknown>;
  /** WP-C v2: the latest domain check passed and is within the 24-hour window (06 §5). */
  domain_ready: boolean;
  domain_check_id: string | null;
  domain_checked_at: string | null;
}

export const GATE_CONTRACT_VERSION = 1;
/**
 * Minimum contract version the gate evaluator accepts from each interface
 * (`private.gate_contract_minimums`). An older interface fails closed.
 */
export const FINANCIAL_STATUS_MIN_CONTRACT_VERSION = 1;
export const FULFILLMENT_STATUS_CONTRACT_VERSION = 2;

// --- WP-B section (OI-71 item 1; supabase/migrations/20261124160100_wpb_payments_ledger.sql) ---
/** Attributes WP-B added to `private.project_financial_status`, in order (additive). */
export const FINANCIAL_STATUS_WPB_ATTRIBUTES = [
  "agreement_state",
  "agreement_effective",
  // OI-74 (04 §8.1): WP-C's intake precondition reads payment_authorization_ready.
  "payment_authorization_ready",
  "payment_authorization_state",
] as const;
/** `contract_version` reported by the WP-B implementation of the financial interface. */
export const FINANCIAL_CONTRACT_VERSION = 3;

/** `payment_authorization_state` values (04 §8.1); `none` until one is established. */
export const PAYMENT_AUTHORIZATION_STATES = [
  "none",
  "active",
  "payment_method_unavailable",
  "revoked",
] as const;
export type PaymentAuthorizationState = (typeof PAYMENT_AUTHORIZATION_STATES)[number];

/**
 * Gates G1-G8 (06 §2) and the interface that supplies each (OI-71). Every gate now has a
 * published source: WP-B supplies G1 (`agreement_effective`), WP-C supplies G6.
 */
export const GATE_SOURCES = {
  G1: "financial", // WP-B, OI-71 item 1
  G2: "financial",
  G3: "fulfillment",
  G4: "financial",
  G5: "fulfillment",
  G6: "fulfillment",
  G7: "fulfillment",
  G8: "both",
} as const satisfies Record<string, "financial" | "fulfillment" | "both" | null>;
