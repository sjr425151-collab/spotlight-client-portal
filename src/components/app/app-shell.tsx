import Link from "next/link";
import type { ReactNode } from "react";

import { Container } from "@/components/layout/container";
import { Button } from "@/components/ui/button";

export interface NavItem {
  href: "/portal" | "/staff" | "/staff/queue" | "/staff/team" | "/staff/audit";
  label: string;
}

/** Signed-in page frame: account bar with navigation and sign-out. */
export function AppShell({
  email,
  roleLabel,
  nav,
  signOutAction,
  children,
}: {
  email: string | null;
  roleLabel: string;
  nav: readonly NavItem[];
  signOutAction: () => Promise<void>;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col">
      <div className="border-b border-line/70 bg-surface/40">
        <Container className="flex flex-wrap items-center justify-between gap-4 py-3">
          <nav aria-label="Portal">
            <ul className="flex flex-wrap gap-1">
              {nav.map((item) => (
                <li key={item.href}>
                  <Link
                    href={item.href}
                    className="rounded-control px-3 py-2 text-sm text-fg-muted hover:bg-surface-raised hover:text-fg"
                  >
                    {item.label}
                  </Link>
                </li>
              ))}
            </ul>
          </nav>
          <div className="flex items-center gap-3 text-sm text-fg-muted">
            <span>
              <span className="sr-only">Signed in as </span>
              {email} · {roleLabel}
            </span>
            <form action={signOutAction}>
              <Button type="submit" variant="secondary" className="h-9 px-3">
                Sign out
              </Button>
            </form>
          </div>
        </Container>
      </div>
      <Container className="flex flex-col gap-10 py-12">{children}</Container>
    </div>
  );
}

export function PageHeading({ title, intro }: { title: string; intro?: string }) {
  return (
    <header>
      <h1 className="font-display text-3xl font-bold tracking-tight text-fg">{title}</h1>
      {intro ? <p className="mt-3 max-w-2xl text-fg-muted">{intro}</p> : null}
    </header>
  );
}
