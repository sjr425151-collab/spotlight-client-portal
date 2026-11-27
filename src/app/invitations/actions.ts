"use server";

import { redirect } from "next/navigation";

import { rejectStaff, requireUser } from "@/server/auth/guards";
import { acceptInvitation } from "@/server/services/invitations";
import { createUserClient } from "@/server/supabase/clients";

/**
 * OI-88 option A (AUTH-017): accepts one of the caller's own pending invitations from
 * /invitations. The same email-bound path as the in-portal acceptance (no link token): the
 * database binds the invitation to the caller's verified email, refuses anything else with
 * one generic error and audits it. The invitation id comes from the form but authorizes
 * nothing on its own. The guard is requireUser plus rejectStaff (the requireInvitee rule).
 */
export async function acceptListedInvitationAction(formData: FormData) {
  const ctx = await requireUser();
  rejectStaff(ctx);
  const accepted = await acceptInvitation(
    await createUserClient(),
    String(formData.get("id") ?? ""),
    null,
  );
  if (!accepted.ok) redirect("/invitations?error=invitation_unavailable");
  // Staff must enroll in MFA before anything else (spec 03 §7), as on /invite/accept.
  redirect(
    accepted.kind === "staff"
      ? "/mfa?notice=invitation_accepted"
      : "/portal?notice=invitation_accepted",
  );
}
