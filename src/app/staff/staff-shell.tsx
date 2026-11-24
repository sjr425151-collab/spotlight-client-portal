import type { ReactNode } from "react";

import { AppShell } from "@/components/app/app-shell";
import type { StaffContext } from "@/server/auth/guards";

import { signOutAction } from "../sign-in/actions";

export function StaffShell({ ctx, children }: { ctx: StaffContext; children: ReactNode }) {
  return (
    <AppShell
      email={ctx.email}
      roleLabel={ctx.staffRole === "owner" ? "Owner" : "Admin"}
      nav={[
        { href: "/staff", label: "Projects" },
        { href: "/staff/queue", label: "Queue" },
        { href: "/staff/team", label: "Team" },
        { href: "/staff/audit", label: "Audit log" },
      ]}
      signOutAction={signOutAction}
    >
      {children}
    </AppShell>
  );
}
