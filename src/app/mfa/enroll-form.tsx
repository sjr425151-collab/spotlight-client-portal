"use client";

import { useActionState } from "react";

import { Button } from "@/components/ui/button";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";

import { completeEnrollmentAction, startEnrollmentAction, type EnrollState } from "./actions";

/**
 * TOTP enrollment. The QR code and setup key come from the server action; the browser
 * never talks to Supabase (spec 03 §6.2).
 */
export function EnrollForm({ next }: { next: string }) {
  const [started, start, starting] = useActionState(startEnrollmentAction, {} as EnrollState);
  const [completed, complete, completing] = useActionState(
    completeEnrollmentAction,
    {} as EnrollState,
  );
  const enrollment = started.factorId ? started : null;
  const error = messageFor(completed.error ?? started.error);

  if (!enrollment) {
    return (
      <form action={start} className="flex flex-col gap-4">
        {error ? <Notice tone="danger">{error}</Notice> : null}
        <Button type="submit" disabled={starting}>
          Set up authenticator app
        </Button>
      </form>
    );
  }

  return (
    <form action={complete} className="flex flex-col gap-5">
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <ol className="flex list-decimal flex-col gap-2 pl-5 text-sm text-fg-muted">
        <li>Scan this QR code with your authenticator app.</li>
        <li>Enter the six-digit code the app shows.</li>
      </ol>
      {/* The QR code is an SVG data URI produced server-side (img-src allows data:). */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={enrollment.qrCode}
        alt="QR code for your authenticator app"
        width={192}
        height={192}
        className="self-center rounded-control bg-fg p-2"
      />
      <p className="text-sm text-fg-muted">
        Can&apos;t scan? Setup key: <code className="break-all text-fg">{enrollment.secret}</code>
      </p>
      <input type="hidden" name="factorId" value={enrollment.factorId} />
      <input type="hidden" name="next" value={next} />
      <TextField
        label="Authenticator code"
        name="code"
        inputMode="numeric"
        autoComplete="one-time-code"
        pattern="[0-9]{6}"
        maxLength={6}
        required
      />
      <Button type="submit" disabled={completing}>
        Verify and continue
      </Button>
    </form>
  );
}
