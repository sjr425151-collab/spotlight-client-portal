import type { Metadata } from "next";

import { Container } from "@/components/layout/container";
import { ButtonLink } from "@/components/ui/button";
import { Eyebrow } from "@/components/ui/eyebrow";

export const metadata: Metadata = {
  title: "Page not found",
  robots: { index: false, follow: false },
};

export default function NotFound() {
  return (
    <Container className="flex flex-col items-start gap-6 py-28">
      <Eyebrow>404</Eyebrow>
      <h1 className="font-display text-3xl font-bold tracking-tight text-fg sm:text-4xl">
        This page could not be found.
      </h1>
      <p className="max-w-lg text-fg-muted">
        The link may be out of date. If you were sent here from an email, contact your Spotlight
        Marketing project lead.
      </p>
      <ButtonLink href="/" variant="secondary">
        Return home
      </ButtonLink>
    </Container>
  );
}
