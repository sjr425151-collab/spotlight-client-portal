import type { Metadata } from "next";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import { AuthCard } from "@/components/app/auth-card";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { getAuthContext } from "@/server/auth/context";

import { requestCodeAction, verifyCodeAction } from "./actions";

export const metadata: Metadata = { title: "Sign in", robots: { index: false, follow: false } };

type Search = Promise<Record<string, string | string[] | undefined>>;

export default async function SignInPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await getAuthContext();
  if (ctx?.sessionActive && ctx.active) redirect(ctx.staffRole ? "/staff" : "/portal");

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
