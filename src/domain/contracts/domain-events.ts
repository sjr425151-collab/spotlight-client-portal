/**
 * Domain-event contract (WP-0; spec 01 §7).
 *
 * Events are typed, append-only, and written by `private.emit_domain_event` inside the same
 * database transaction as the state change they describe. Only SECURITY DEFINER
 * state-change functions can call it (no API role holds EXECUTE).
 *
 * Registration: an event type must exist in `private.domain_event_types` before it can be
 * emitted. Each work package registers its own types in its own migration and adds them
 * here, in its own section, so WP-B and WP-C never edit each other's entries.
 */
import type { StateDomain } from "./state-domains";

export const EVENT_TYPE_PATTERN = /^[a-z][a-z_]*\.[a-z][a-z_]*$/;

export type OwnerPackage = "WP-B" | "WP-C";

export interface DomainEventType {
  readonly type: string;
  readonly domain: StateDomain;
  readonly owner: OwnerPackage;
  readonly schemaVersion: number;
  /** The packages that read this event, if any besides the owner. */
  readonly consumers: readonly OwnerPackage[];
}

/** Registered in the WP-0 migration: the cross-package events named in 01 §7. */
export const DOMAIN_EVENT_TYPES = [
  {
    type: "agreement.accepted",
    domain: "agreement",
    owner: "WP-B",
    schemaVersion: 1,
    consumers: [],
  },
  {
    type: "payment.deposit_verified",
    domain: "payment",
    owner: "WP-B",
    schemaVersion: 1,
    consumers: ["WP-C"],
  },
  // WP-C emits; WP-B consumes it to create the final-balance invoice (01 §7).
  {
    type: "release.approved",
    domain: "approval",
    owner: "WP-C",
    schemaVersion: 1,
    consumers: ["WP-B"],
  },
  {
    type: "publication.authorized",
    domain: "deployment",
    owner: "WP-C",
    schemaVersion: 1,
    consumers: [],
  },
] as const satisfies readonly DomainEventType[];

export type RegisteredDomainEventType = (typeof DOMAIN_EVENT_TYPES)[number]["type"];

// --- WP-B section (registered in supabase/migrations/20261124160000_wpb_agreements.sql) ---
const wpb = (type: string, domain: StateDomain, consumers: readonly OwnerPackage[] = []) =>
  ({ type, domain, owner: "WP-B", schemaVersion: 1, consumers }) as const satisfies DomainEventType;

/** WP-B's own event types (01 §7). Additive; WP-0's list above is unchanged. */
export const WP_B_DOMAIN_EVENT_TYPES: readonly DomainEventType[] = [
  wpb("agreement.effective", "agreement"),
  wpb("agreement.reacceptance_required", "agreement"),
  wpb("order_summary.issued", "agreement"),
  wpb("payment.balance_due", "payment"),
  wpb("payment.balance_invoice_opened", "payment"),
  wpb("payment.balance_verified", "payment", ["WP-C"]),
  wpb("payment.balance_failed", "payment"),
  wpb("payment.hold_placed", "payment"),
  wpb("payment.hold_cleared", "payment"),
  wpb("payment.refund_recorded", "payment"),
  wpb("payment.dispute_opened", "payment"),
  wpb("payment.dispute_closed", "payment"),
  wpb("subscription.status_changed", "subscription"),
  wpb("subscription.payment_failed", "subscription"),
  wpb("subscription.payment_recovered", "subscription"),
  wpb("subscription.cancellation_exception", "subscription"),
  wpb("subscription.cancellation_requested", "subscription"),
  wpb("subscription.termination_authorized", "subscription"),
  wpb("subscription.termination_effective", "subscription"),
];

/**
 * What WP-B's durable consumer requires of `release.approved` (schema version 1), emitted by
 * WP-C: `project_id` set, `subject_type` "preview_release", `subject_id` the approved release
 * ID, and `payload.approval_id` the client approval ID (both UUIDs). The consumer is
 * idempotent per event, and the obligation it creates is unique per order summary and per
 * project, so replays, repeated approvals, and later releases never create a second invoice.
 */
export const RELEASE_APPROVED_CONSUMER_CONTRACT = {
  eventType: "release.approved",
  schemaVersion: 1,
  subjectType: "preview_release",
  payloadKeys: ["approval_id"],
  consumer: "wpb.final_balance_invoice",
} as const;

/** Limits enforced by the database (`private.payload_is_safe`). */
export const DOMAIN_EVENT_PAYLOAD_MAX_BYTES = 8192;
export const NOTIFICATION_PAYLOAD_MAX_BYTES = 2048;

/**
 * Payload keys the database rejects at any depth, matched per snake_case segment, so
 * `company` is allowed and `card_number` is not. Mirrors `private.payload_is_safe`.
 */
export const FORBIDDEN_PAYLOAD_KEY_PATTERN =
  /(^|_)(secret|token|password|passcode|otp|apikey|api_key|card|cvc|cvv|pan|authorization|cookie)s?(_|$)/;

/** Same rule as the database, for checking payloads before they reach it. */
export function isPayloadSafe(payload: unknown, maxBytes: number): boolean {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) return false;
  if (new TextEncoder().encode(JSON.stringify(payload)).length > maxBytes) return false;
  const visit = (value: unknown): boolean => {
    if (Array.isArray(value)) return value.every(visit);
    if (typeof value === "object" && value !== null) {
      return Object.entries(value).every(
        ([key, child]) => !FORBIDDEN_PAYLOAD_KEY_PATTERN.test(key.toLowerCase()) && visit(child),
      );
    }
    return true;
  };
  return visit(payload);
}
