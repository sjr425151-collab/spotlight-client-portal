/**
 * Publication gates and approval wording (WP-C; spec 05 §7, 06 §2-§9). Pure TypeScript.
 *
 * The gate evaluator itself runs only in the database (`private.evaluate_publication_gates`)
 * so that authorization and deployment start read the same authoritative records in the
 * same transaction. This module types its result and checks its shape. It contains no
 * way to pass, skip, or override a gate (06 §2; T-PUB-04).
 */

export const GATE_IDS = ["G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8"] as const;
export type GateId = (typeof GATE_IDS)[number];

export const GATE_LABELS: Record<GateId, string> = {
  G1: "Valid agreement",
  G2: "Verified deposit",
  G3: "Client approval of this release",
  G4: "Verified final balance",
  G5: "Release QA passed",
  G6: "Domain readiness (within 24 hours)",
  G7: "Security checks passed",
  G8: "No publication-blocking hold",
};

export interface GateOutcome {
  readonly gate: GateId;
  readonly passed: boolean;
  readonly source: "financial" | "fulfillment" | "both";
  readonly reason: string | null;
}

export interface GateResult {
  readonly eligible: boolean;
  readonly release_id: string | null;
  readonly gates: readonly GateOutcome[];
}

/**
 * Reads a gate result defensively: anything malformed, incomplete, or with a failing gate
 * is not eligible (fail closed). Eligibility also requires all eight gates to be present.
 */
export function parseGateResult(value: unknown): GateResult {
  const fallback: GateResult = { eligible: false, release_id: null, gates: [] };
  if (!value || typeof value !== "object") return fallback;
  const raw = value as { eligible?: unknown; release_id?: unknown; gates?: unknown };
  if (!Array.isArray(raw.gates)) return fallback;
  const gates: GateOutcome[] = [];
  for (const g of raw.gates as unknown[]) {
    if (!g || typeof g !== "object") return fallback;
    const { gate, passed, source, reason } = g as Record<string, unknown>;
    if (!GATE_IDS.includes(gate as GateId)) return fallback;
    gates.push({
      gate: gate as GateId,
      passed: passed === true,
      source: source === "financial" || source === "fulfillment" ? source : "both",
      reason: typeof reason === "string" ? reason : null,
    });
  }
  const complete = GATE_IDS.every((id) => gates.some((g) => g.gate === id));
  return {
    eligible: raw.eligible === true && complete && gates.every((g) => g.passed),
    release_id: typeof raw.release_id === "string" ? raw.release_id : null,
    gates,
  };
}

/**
 * Approval action label (05 §7; 04 §10; T-LC-14). R1 uses the same label as R2 since OI-74:
 * the approval authorizes automatic collection of the final balance. Final wording is for
 * counsel (DEP-03).
 */
export const APPROVAL_LABEL = "Approve Website & Authorize Final Payment";

/**
 * Approval screen disclosure (05 §7; 04 §10, §8.1). No amount is shown until WP-B's
 * interface provides the order-summary snapshot balance (OI-80 item 3).
 */
export const APPROVAL_DISCLOSURE =
  "Approving this version makes the outstanding balance from your order summary due and " +
  "authorizes its automatic charge to the payment method saved at your deposit. If that " +
  "charge fails or needs your confirmation, you will be able to pay the same invoice on a " +
  "secure Stripe-hosted page. Approving again never creates a second charge.";

/** Client-facing label for a publication state (05 §1: display only, never a gate). */
export const PUBLICATION_STATE_LABELS: Record<string, string> = {
  not_eligible: "In progress",
  eligible: "Ready for final review",
  authorized: "Approved for publication",
  deploying: "Publishing",
  live_unverified: "Published, being verified",
  live_verified: "Live",
  failed: "Publishing paused for a fix",
  rolled_back: "Restored to the previous version",
};

export const INTAKE_STATE_LABELS: Record<string, string> = {
  locked: "Available once your deposit and saved payment method are verified",
  open: "Ready for your information",
  submitted: "Submitted, under review",
  accepted_by_staff: "Accepted",
  changes_requested: "Changes requested",
};
