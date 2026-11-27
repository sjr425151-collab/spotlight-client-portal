import type { Metadata } from "next";

import { AuthCard } from "@/components/app/auth-card";
import { Button } from "@/components/ui/button";
import { Notice } from "@/components/ui/notice";
import { invitationDescription } from "@/lib/invitations";
import { messageFor } from "@/lib/messages";
import { requireInvitee } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import { signOutAction } from "../sign-in/actions";
import { acceptListedInvitationAction } from "./actions";

export const metadata: Metadata = {
  title: "Your invitations",
  robots: { index: false, follow: false },
};

type Search = Promise<Record<string, string | string[] | undefined>>;

/**
 * OI-88 option A (AUTH-017): the caller's own pending invitations, for a signed-in user with
 * no staff role, with or without an active membership. This is how a former client who is
 * invited again (Supabase sends no email to an existing account, 03A S-06) accepts.
 *
 * RLS returns only pending, unexpired invitations addressed to the caller's verified email.
 * Acceptance is the existing email-bound path (accept_invitation with no link token). This
 * page grants no client access: every client page keeps the strict requireClient.
 */
export default async function InvitationsPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  await requireInvitee();
  const { data: invitations } = await (
    await createUserClient()
  )
    .from("invitations")
    .select("id, kind, intended_role, expires_at")
    .eq("status", "pending")
    .order("created_at", { ascending: true });
  const error = messageFor(params.error);
  const pending = invitations ?? [];

  return (
    <AuthCard
      title="Your invitations"
      intro={
        pending.length > 0
          ? "Invitations sent to your email address. Accept one to open the project."
          : "There are no pending invitations for your email address."
      }
    >
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {pending.length > 0 ? (
        <ul className="flex flex-col gap-4" data-testid="invitation-list">
          {pending.map((invitation) => (
            <li key={invitation.id} className="flex flex-col gap-3">
              <p className="text-sm text-fg-muted">
                {invitationDescription(invitation.kind, invitation.intended_role)} This invitation
                expires on{" "}
                {new Date(invitation.expires_at).toLocaleDateString("en-US", {
                  dateStyle: "medium",
                })}
                .
              </p>
              <form action={acceptListedInvitationAction}>
                <input type="hidden" name="id" value={invitation.id} />
                <Button type="submit" className="w-full">
                  Accept invitation
                </Button>
              </form>
            </li>
          ))}
        </ul>
      ) : (
        <p className="text-sm text-fg-muted" data-testid="no-invitations">
          If you expected an invitation, contact Spotlight Marketing.
        </p>
      )}
      <form action={signOutAction}>
        <Button type="submit" variant="secondary" className="w-full">
          Sign out
        </Button>
      </form>
    </AuthCard>
  );
}
