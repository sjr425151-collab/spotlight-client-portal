import Link from "next/link";

import { Logo } from "@/components/brand/logo";
import { Container } from "@/components/layout/container";
import { site } from "@/config/site";

export function SiteHeader() {
  return (
    <header className="border-b border-line/70">
      <Container className="flex h-20 items-center justify-between gap-6">
        <Link href="/" aria-label={`${site.name}, home`} className="-ml-2 rounded-control p-2">
          <Logo priority className="w-28 sm:w-32" />
        </Link>
        <p className="rounded-full border border-line px-3.5 py-1.5 font-display text-[0.6875rem] font-semibold tracking-eyebrow text-fg-muted uppercase">
          {site.shortName}
        </p>
      </Container>
    </header>
  );
}
