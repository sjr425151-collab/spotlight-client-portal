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
  // OI-88 option A (AUTH-017): no email is sent to an existing account (03A S-06); the
  // invitee finds the invitation under "Your invitations" (/invitations) after signing in.
  invite_existing_user:
    "Invitation created. This person already has a portal account, so no email was sent. After signing in with an emailed code, they will find the invitation under Your invitations.",
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
  scan_backoff: "The scanner failed recently. Wait a few minutes before retrying.",
  scan_retries_exhausted: "The scan failed five times. The file stays in quarantine for review.",
  deletion_completed: "The revoked file was deleted from storage.",
  deletion_failed: "The revoked file could not be deleted yet. It stays inaccessible; retry later.",
  already_deleted: "That file was already deleted.",
  deletion_in_progress: "A deletion attempt is running. Try again in a few minutes.",
  retry_limit:
    "This deletion has reached its retry limit. The file stays inaccessible; check storage before retrying.",
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
  // Agreement and payments (WP-B)
  agreement_accepted: "Agreement accepted. You can now make the initial payment.",
  explicit_acceptance_required:
    "Please tick both boxes to accept the agreement and confirm your authority.",
  signer_details_required:
    "Please enter your full legal name, the business legal name, and your title.",
  order_summary_superseded: "This order summary has been replaced. Please review the current one.",
  already_accepted: "This order summary has already been accepted.",
  hash_mismatch: "This agreement could not be verified. Spotlight Marketing has been alerted.",
  agreement_version_not_usable:
    "This agreement version is not available. Spotlight Marketing has been alerted.",
  email_not_verified: "Your email address must be verified before you can accept.",
  acceptance_required: "Please accept the current agreement before paying.",
  deposit_already_verified: "Your deposit has already been received.",
  catalog_mismatch: "Payment is temporarily unavailable. Spotlight Marketing has been alerted.",
  price_verification_failed:
    "Payment is temporarily unavailable. Spotlight Marketing has been alerted.",
  checkout_in_progress: "A payment is already in progress for this project.",
  checkout_unavailable: "Payment is temporarily unavailable. Please try again.",
  reconciliation_required:
    "Your payment is being checked. Please do not pay again; we will contact you.",
  payments_unavailable: "Online payment is not available in this environment.",
  stripe_rejected: "Payment could not be started. Please try again.",
  cancellation_received:
    "Your cancellation request was received. We will confirm the effective date.",
  order_summary_issued: "Order summary issued.",
  // OI-81: once the deposit is verified, the accepted pricing is fixed.
  price_change_after_deposit:
    "The deposit has been paid, so this project's total, deposit and balance cannot change.",
  no_usable_agreement_version: "No approved agreement version is available.",
  hold_placed: "Hold placed.",
  hold_cleared: "Hold cleared.",
  hold_type_not_manual: "That hold type cannot be placed manually.",
  // Final-payment authorization (WP-B, OI-74)
  recovery_unavailable: "The secure card page is not available right now. Please try again.",
  deposit_required: "The initial payment must be received first.",
  authorization_active: "A card is already saved for the final balance.",
  new_acceptance_required:
    "Automatic final payment was turned off. Please contact Spotlight Marketing to set it up again.",
  card_saved: "Thank you. Stripe will confirm your card shortly.",
  authorization_revoked:
    "Automatic final payment is turned off. You can pay the final balance on its Stripe invoice page.",
  no_authorization: "There is no saved card to turn off.",
  authorization_revoked_staff: "Revocation recorded. Automatic final payment is off.",
  revocation_reviewed: "Revocation review recorded.",
  signer_required:
    "Only the person who accepted the agreement can turn off automatic final payment.",
  client_reauthentication_required:
    "For your security, please sign in again with a new code, then turn off automatic final payment within five minutes.",
  // WP-S: Sales Representatives (03 §4.1; OI-77, OI-78, OI-84)
  no_active_project:
    "Your account has no active project. If you have been invited to a project, open your invitations.",
  invitation_unavailable:
    "This invitation is no longer available. It may have expired, been replaced, or already been used.",
  invalid_recipient: "That address cannot receive a client invitation.",
  invitation_resent: "A new invitation was sent. The previous link no longer works.",
  invitation_revoked: "Invitation revoked.",
  customer_created: "Customer and project created. You are assigned to this project.",
  customer_exists: "This customer and project already exist in your list.",
  scope_not_allowed:
    "The package's standard scope is applied automatically; scope items cannot be entered.",
  notes_not_allowed: "Project notes cannot be added to a sales order summary.",
  scope_definition_missing:
    "This package has no approved standard scope yet, so an order summary cannot be issued.",
  replacement_after_acceptance:
    "The client has already accepted, so the order summary can no longer be replaced. Contact an Admin.",
  not_sales_representative: "That person is not an active Sales Representative.",
  client_membership: "This person is a client on a project and cannot be given the Sales role.",
  assignment_saved: "Assignment saved.",
  assignment_ended: "Assignment ended.",
} as const;

export type MessageCode = keyof typeof MESSAGES;

export function messageFor(code: string | string[] | undefined): string | null {
  if (typeof code !== "string") return null;
  return Object.hasOwn(MESSAGES, code) ? MESSAGES[code as MessageCode] : null;
}
