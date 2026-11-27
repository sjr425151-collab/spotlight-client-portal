import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { AuthCard } from "@/components/app/auth-card";
import { Button, ButtonLink } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { getAuthContext } from "@/server/auth/context";
import { homeFor } from "@/server/auth/guards";

import { requestCodeAction, signOutAction, verifyCodeAction } from "./actions";

/** Notices for a signed-in user who has no area to enter (no redirect, or it would loop). */
const NO_ACCESS_NOTICES = new Set(["inactive", "no_active_project"]);

export const metadata: Metadata = { title: "Sign in", robots: { index: false, follow: false } };

type Search = Promise<Record<string, string | string[] | undefined>>;

export default async function SignInPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await getAuthContext();
  const noAccess = typeof params.notice === "string" && NO_ACCESS_NOTICES.has(params.notice);
  if (ctx?.sessionActive && ctx.active && !noAccess) redirect(homeFor(ctx));
  if (ctx?.sessionActive && noAccess) {
    return (
      <AuthCard title="No portal access" intro="Your account has no area to open right now.">
        <Notice>{messageFor(params.notice)}</Notice>
        {params.notice === "no_active_project" ? (
          // OI-88 option A (AUTH-017): a former client who is invited again accepts here.
          <ButtonLink href={"/invitations" as never} className="w-full">
            Your invitations
          </ButtonLink>
        ) : null}
        <form action={signOutAction}>
          <Button type="submit" variant="secondary" className="w-full">
            Sign out
          </Button>
        </form>
      </AuthCard>
    );
  }

  const pendingEmail = (await cookies()).get("sp_signin_email")?.value;
  const codeStep = params.step === "code" && Boolean(pendingEmail);
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  return (
    <AuthCard
      title={codeStep ? "Enter your code" : "Sign in"}
      intro={
        codeStep
          ? "Enter the six-digit code from your email."
          : "Access is by invitation. Enter the email address your invitation was sent to."
      }
    >
      {notice ? <Notice>{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {codeStep ? (
        <>
          <form action={verifyCodeAction} className="flex flex-col gap-5">
            <TextField
              label="Sign-in code"
              name="code"
              inputMode="numeric"
              autoComplete="one-time-code"
              pattern="[0-9]{6}"
              maxLength={6}
              required
              hint="Six digits. The code expires 10 minutes after it was sent."
            />
            <Button type="submit">Sign in</Button>
          </form>
          <form action={requestCodeAction}>
            <input type="hidden" name="email" value={pendingEmail} />
            <Button type="submit" variant="ghost" className="w-full">
              Send a new code
            </Button>
          </form>
        </>
      ) : (
        <form action={requestCodeAction} className="flex flex-col gap-5">
          <TextField label="Email" name="email" type="email" autoComplete="email" required />
          <Button type="submit">Email me a sign-in code</Button>
        </form>
      )}
    </AuthCard>
  );
}
