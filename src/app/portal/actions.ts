"use server";

import { redirect } from "next/navigation";

import { requireClient } from "@/server/auth/guards";
import { acceptInvitation } from "@/server/services/invitations";
import { createUserClient } from "@/server/supabase/clients";

/**
 * In-portal acceptance for a signed-in client (spec 03 §6.1 step 2; 03A S-06). No link
 * token: the database binds the invitation to the caller's verified email.
 */
export async function acceptPendingInvitationAction(formData: FormData) {
  await requireClient();
  const accepted = await acceptInvitation(
    await createUserClient(),
    String(formData.get("id") ?? ""),
    null,
  );
  redirect(accepted.ok ? "/portal?notice=invitation_accepted" : "/portal?error=invalid_invitation");
}
