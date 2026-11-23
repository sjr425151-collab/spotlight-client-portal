import type { Metadata } from "next";

import { AuthCard } from "@/components/app/auth-card";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { getAuthContext } from "@/server/auth/context";
import { checkInvitationLink } from "@/server/services/invitations";
import { requestMeta } from "@/server/request";

import {
  acceptSignedInAction,
  resendInvitationCodeAction,
  verifyInvitationCodeAction,
} from "./actions";

export const metadata: Metadata = {
  title: "Accept invitation",
  robots: { index: false, follow: false },
  // The link carries the invitation token: never leak it through the Referer header.
  referrer: "no-referrer",
};

type Search = Promise<Record<string, string | string[] | undefined>>;

function maskEmail(email: string): string {
  const [local = "", domain = ""] = email.split("@");
  return `${local.slice(0, 1)}${"•".repeat(Math.max(local.length - 1, 2))}@${domain}`;
}

export default async function AcceptInvitationPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const id = typeof params.id === "string" ? params.id : "";
  const token = typeof params.t === "string" ? params.t : "";
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  const link = id && token ? await checkInvitationLink(id, token, (await requestMeta()).ip) : null;
  if (!link?.ok) {
    return (
      <AuthCard title="Invitation" intro="Invitations are sent by Spotlight Marketing.">
        <Notice tone="danger">{messageFor("invalid_invitation")}</Notice>
      </AuthCard>
    );
  }

  const ctx = await getAuthContext();
  const hidden = (
    <>
      <input type="hidden" name="id" value={id} />
      <input type="hidden" name="t" value={token} />
    </>
  );

  if (ctx?.sessionActive) {
    return (
      <AuthCard
        title="Accept your invitation"
        intro={`This invitation was sent to ${maskEmail(link.email)}. You are signed in as ${ctx.email ?? "another account"}.`}
      >
        {error ? <Notice tone="danger">{error}</Notice> : null}
        <form action={acceptSignedInAction}>
          {hidden}
          <Button type="submit" className="w-full">
            Accept invitation
          </Button>
        </form>
      </AuthCard>
    );
  }

  return (
    <AuthCard
      title="Accept your invitation"
      intro={`Enter the six-digit code from the invitation email sent to ${maskEmail(link.email)}.`}
    >
      {notice ? <Notice>{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <form action={verifyInvitationCodeAction} className="flex flex-col gap-5">
        {hidden}
        <TextField
          label="Invitation code"
          name="code"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="[0-9]{6}"
          maxLength={6}
          required
          hint="Codes expire 10 minutes after they are sent."
        />
        <Button type="submit">Accept invitation</Button>
      </form>
      <form action={resendInvitationCodeAction}>
        {hidden}
        <Button type="submit" variant="ghost" className="w-full">
          Send me a new code
        </Button>
      </form>
    </AuthCard>
  );
}
