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
