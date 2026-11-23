import type { ReactNode } from "react";

import { Container } from "@/components/layout/container";
import { Card } from "@/components/ui/card";
import { Eyebrow } from "@/components/ui/eyebrow";

/** Centered card used by the sign-in, invitation, and MFA pages. */
export function AuthCard({
  title,
  intro,
  children,
}: {
  title: string;
  intro: string;
  children: ReactNode;
}) {
  return (
    <Container className="flex justify-center py-16 sm:py-24">
      <Card className="flex w-full max-w-md flex-col gap-6">
        <div>
          <Eyebrow>Secure access</Eyebrow>
          <h1 className="mt-4 font-display text-2xl font-bold tracking-tight text-fg">{title}</h1>
          <p className="mt-3 text-sm leading-relaxed text-fg-muted">{intro}</p>
        </div>
        {children}
      </Card>
    </Container>
  );
}
