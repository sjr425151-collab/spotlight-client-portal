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
  // WP-C: intake and uploads (05 §3-§5)
  intake_saved: "Your progress is saved. You can come back and finish later.",
  intake_submitted: "Thank you. Your information was submitted for review.",
  intake_locked: "This becomes available once your deposit is verified.",
  intake_not_editable: "This information can't be changed right now.",
  incomplete: "Please complete every required field before submitting.",
  note_required: "Please explain what needs to change.",
  reason_required: "Please give a reason.",
  stale: "This was already reviewed or replaced. Reload the page.",
  nothing_to_correct: "There is no submitted intake to correct.",
  client_draft_open: "The client has a draft open. Ask them to submit it first.",
  upload_available: "File uploaded, scanned, and ready.",
  upload_quarantined: "File received. It stays in quarantine until it passes the security scan.",
  upload_held: "File received and scanned. It needs additional processing before it can be used.",
  upload_rejected:
    "This file was rejected. See the guidance next to it and upload a corrected copy.",
  upload_failed_upload: "The upload did not complete. Please try again.",
  file_too_large: "That file is larger than the limit for its category.",
  type_not_allowed: "That file type is not allowed for this category.",
  type_exception_required: "This file type needs approval first. Request an exception below.",
  quota_files: "This project has reached its 100-file limit.",
  quota_bytes: "This project has reached its 2 GB storage limit.",
  exception_requested: "Your request was sent for review.",
  // WP-C: previews and approvals (05 §6-§8)
  preview_released: "The preview was released to the client.",
  preview_approved: "Thank you. Your approval of this preview was recorded.",
  revisions_requested: "Your revision request was sent.",
  release_superseded: "A newer preview was released. Reload the page to review it.",
  confirmation_required: "Please confirm before continuing.",
  intake_not_accepted: "Accept the client's intake before releasing a preview.",
  asset_not_available: "Only scanned, available assets can be used in a release.",
  not_current_release: "That is not the current release.",
  invalid_date: "That date is outside the allowed range.",
  outreach_required: "Record the day-14 personal follow-up before placing a hold.",
  too_early: "A hold can be placed only from day 21 after the release.",
  hold_active: "An approval hold is already active.",
  release_approved: "The current release is already approved.",
  no_current_release: "There is no current release.",
  client_response_required: "An Admin can clear this hold only after the client responds.",
  already_classified: "This request was already classified.",
  // WP-C: publication (06)
  publication_authorized: "Publication authorized for this release.",
  gates_failed: "Publication is blocked: not every gate passes. See the gate list.",
  reauthentication_required: "Please verify with your authenticator again to continue.",
  deployment_started:
    "Deployment started. Deploy exactly the recorded commit, then record the result.",
  authorization_invalid: "That authorization is no longer valid. A new authorization is needed.",
  no_isolated_target: "Register the client's isolated deployment target first.",
  already_recorded: "This deployment's result was already recorded.",
  already_registered: "A deployment target is already registered.",
  target_in_use: "That deployment target belongs to another project.",
  verification_recorded: "Live verification was recorded.",
} as const;

export type MessageCode = keyof typeof MESSAGES;

export function messageFor(code: string | string[] | undefined): string | null {
  if (typeof code !== "string") return null;
  return Object.hasOwn(MESSAGES, code) ? MESSAGES[code as MessageCode] : null;
}
