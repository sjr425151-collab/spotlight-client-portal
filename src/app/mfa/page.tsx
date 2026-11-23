import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { AuthCard } from "@/components/app/auth-card";
import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { requireUser, safeReturnPath } from "@/server/auth/guards";
import { verifiedTotpFactor } from "@/server/services/mfa";
import { createUserClient } from "@/server/supabase/clients";

import { signOutAction } from "../sign-in/actions";
import { verifyMfaAction } from "./actions";
import { EnrollForm } from "./enroll-form";

export const metadata: Metadata = {
  title: "Two-step verification",
  robots: { index: false, follow: false },
};

type Search = Promise<Record<string, string | string[] | undefined>>;

/** Staff MFA (spec 03 §7): enrollment, aal2 step-up, and fresh re-verification. */
export default async function MfaPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireUser();
  if (!ctx.staffRole) redirect("/portal");

  const next = safeReturnPath(typeof params.next === "string" ? params.next : null, "/staff");
  const reauth = params.reauth === "1";
  if (ctx.aal === "aal2" && !reauth) redirect(next as never);

  const factor = await verifiedTotpFactor(await createUserClient());
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  return (
    <AuthCard
      title={
        factor
          ? reauth
            ? "Confirm it's you"
            : "Two-step verification"
          : "Set up two-step verification"
      }
      intro={
        factor
          ? reauth
            ? "This action needs a recent authenticator check. Enter the current code from your app."
            : "Enter the current code from your authenticator app."
          : "Staff accounts require an authenticator app (TOTP). Set it up to continue."
      }
    >
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {factor ? (
        <form action={verifyMfaAction} className="flex flex-col gap-5">
          <input type="hidden" name="next" value={next} />
          {reauth ? <input type="hidden" name="reauth" value="1" /> : null}
          <TextField
            label="Authenticator code"
            name="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            maxLength={6}
            required
          />
          <Button type="submit">Verify</Button>
        </form>
      ) : (
        <EnrollForm next={next} />
      )}
      <form action={signOutAction}>
        <Button type="submit" variant="ghost" className="w-full">
          Sign out
        </Button>
      </form>
    </AuthCard>
  );
}
