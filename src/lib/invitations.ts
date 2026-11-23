/**
 * Display-only expiry label for staff lists. Enforcement never relies on this: every
 * database boundary compares `expires_at` with the current time (spec 03 §6.1; OI-54).
 */
export function isInvitationExpired(expiresAt: string, now: Date = new Date()): boolean {
  return new Date(expiresAt).getTime() <= now.getTime();
}
