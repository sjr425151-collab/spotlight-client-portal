/**
 * User-facing messages for result codes passed in the URL (`?error=` / `?notice=`).
 * Only codes from this list are ever rendered, so the URL cannot inject text. Messages are
 * deliberately generic where detail would reveal account existence (spec 03 TM-03).
 */
export const MESSAGES = {
  // Sign-in
  code_sent:
    "If this email belongs to a portal account, we have sent a six-digit sign-in code. It expires in 10 minutes.",
  invalid_code: "That code did not work. Check the latest email, or request a new code.",
  rate_limited: "Too many attempts. Please wait a while before trying again.",
  signed_out: "You have been signed out.",
  inactive: "This account is not active. Contact Spotlight Marketing if you need access.",
  // Invitations
  invalid_invitation:
    "This invitation link is not valid. It may have expired, been replaced, or already been used.",
  invitation_accepted: "Invitation accepted.",
  invite_sent: "Invitation created and emailed.",
  invite_existing_user:
    "Invitation created. This person already has a portal account and will see the invitation after signing in.",
  role_not_assignable: "That role cannot be assigned.",
  too_many_pending: "This project already has the maximum number of pending invitations.",
  project_not_found: "That project was not found or is archived.",
  // MFA
  mfa_enrolled: "Two-step verification is set up.",
  invalid_mfa_code: "That authenticator code did not work. Try the current code.",
  mfa_reset: "The authenticator was reset. The user will set up a new one at next sign-in.",
  // Administration
  saved: "Saved.",
  forbidden: "You do not have permission to do that.",
  last_owner: "The last active Owner cannot be removed, demoted, or deactivated.",
  not_found: "That record was not found or has already changed.",
  invalid_input: "Please check the form and try again.",
  unavailable: "Something went wrong. Please try again.",
  partial: "The change was saved, but the sign-in block could not be updated. Try again.",
} as const;

export type MessageCode = keyof typeof MESSAGES;

export function messageFor(code: string | string[] | undefined): string | null {
  if (typeof code !== "string") return null;
  return Object.hasOwn(MESSAGES, code) ? MESSAGES[code as MessageCode] : null;
}
