/**
 * Display-only expiry label for staff lists. Enforcement never relies on this: every
 * database boundary compares `expires_at` with the current time (spec 03 §6.1; OI-54).
 */
export function isInvitationExpired(expiresAt: string, now: Date = new Date()): boolean {
  return new Date(expiresAt).getTime() <= now.getTime();
}

/**
 * Client-facing description of a pending invitation (Phase 2 finding D3). A staff
 * invitation must never be described as a project invitation. Display only: acceptance is
 * authorized by the database (accept_invitation), never by this text.
 */
export function invitationDescription(kind: string, intendedRole: string | null): string {
  if (kind === "staff") {
    const role = intendedRole === "owner" ? "an Owner" : "an Admin";
    return `You have been invited to join the Spotlight Marketing team as ${role}. Staff access requires setting up two-step verification.`;
  }
  return "You have been invited to a new project.";
}
