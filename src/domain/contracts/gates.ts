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
 * Open (OI-71): G1 (valid agreement) and G6 (domain readiness) are not yet assigned to either
 * interface, and the reporting interface for `owner_manual_hold` and `dispute_risk_hold` is
 * not yet decided. Extending a status type is additive.
 */
import type { DepositState, FinalBalanceState, HoldType, IntakeState } from "./state-domains";

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
}

export const GATE_CONTRACT_VERSION = 1;

/** Gates G1-G8 (06 §2) and the interface that supplies each; `null` is open in OI-71. */
export const GATE_SOURCES = {
  G1: null,
  G2: "financial",
  G3: "fulfillment",
  G4: "financial",
  G5: "fulfillment",
  G6: null,
  G7: "fulfillment",
  G8: "both",
} as const satisfies Record<string, "financial" | "fulfillment" | "both" | null>;
