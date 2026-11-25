import type { ReactNode } from "react";

import { AppShell } from "@/components/app/app-shell";
import type { SalesContext } from "@/server/auth/guards";

import { signOutAction } from "../sign-in/actions";

/** The Sales Representative area frame (03 §4.1). No staff navigation is offered. */
export function SalesShell({ ctx, children }: { ctx: SalesContext; children: ReactNode }) {
  return (
    <AppShell
      email={ctx.email}
      roleLabel="Sales Representative"
      nav={[{ href: "/sales", label: "Customers" }]}
      signOutAction={signOutAction}
    >
      {children}
    </AppShell>
  );
}
