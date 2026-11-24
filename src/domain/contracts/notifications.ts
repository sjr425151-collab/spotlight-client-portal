/**
 * Notification outbox contract (WP-0; spec 07 §2-§3).
 *
 * Rows are written by `private.enqueue_notification` in the same transaction as the state
 * change. In R1 every row is `recorded` and never sent; R2 delivery starts new rows at
 * `pending`. The database enforces the transitions below (`private.notification_outbox_guard`).
 */

export const NOTIFICATION_STATUSES = [
  "recorded",
  "pending",
  "sending",
  "sent",
  "failed",
  "dead",
] as const;
export type NotificationStatus = (typeof NOTIFICATION_STATUSES)[number];

export const NOTIFICATION_RECIPIENT_ROLES = ["client", "owner", "admin", "staff"] as const;
export type NotificationRecipientRole = (typeof NOTIFICATION_RECIPIENT_ROLES)[number];

/** The status every R1 row is written with. */
export const R1_NOTIFICATION_STATUS: NotificationStatus = "recorded";

/** Allowed status transitions. `recorded`, `sent`, and `dead` are terminal. */
export const NOTIFICATION_TRANSITIONS = {
  recorded: [],
  pending: ["sending"],
  sending: ["sent", "failed"],
  sent: [],
  failed: ["sending", "dead"],
  dead: [],
} as const satisfies Record<NotificationStatus, readonly NotificationStatus[]>;

export function canTransition(from: NotificationStatus, to: NotificationStatus): boolean {
  return (NOTIFICATION_TRANSITIONS[from] as readonly NotificationStatus[]).includes(to);
}

/** Idempotency key per 07 §3: `event_type:subject_id:version`. */
export function notificationIdempotencyKey(
  eventType: string,
  subjectId: string,
  version: number,
): string {
  if (!Number.isInteger(version) || version < 1)
    throw new RangeError("version must be a positive integer");
  return `${eventType}:${subjectId}:${version}`;
}
