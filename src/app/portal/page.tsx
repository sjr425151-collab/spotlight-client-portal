import type { Metadata } from "next";

import { AppShell, PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { invitationDescription } from "@/lib/invitations";
import { messageFor } from "@/lib/messages";
import { requireClient } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import { signOutAction } from "../sign-in/actions";
import { acceptPendingInvitationAction } from "./actions";

export const metadata: Metadata = {
  title: "Your projects",
  robots: { index: false, follow: false },
};

type Search = Promise<Record<string, string | string[] | undefined>>;

/** Client home. Every row shown is filtered by RLS to the caller's own memberships. */
export default async function PortalPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireClient();
  const db = await createUserClient();

  const [{ data: projects }, { data: invitations }] = await Promise.all([
    db
      .from("projects")
      .select("id, name, created_at, client_businesses(display_name)")
      .is("archived_at", null)
      .order("created_at", { ascending: true }),
    db
      .from("invitations")
      .select("id, kind, intended_role, full_name, expires_at")
      .eq("status", "pending"),
  ]);
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  return (
    <AppShell
      email={ctx.email}
      roleLabel="Client"
      nav={[{ href: "/portal", label: "Projects" }]}
      signOutAction={signOutAction}
    >
      <PageHeading title="Your projects" intro="Projects you have been invited to appear here." />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}

      {invitations && invitations.length > 0 ? (
        <section aria-labelledby="pending-heading" className="flex flex-col gap-4">
          <h2 id="pending-heading" className="font-display text-xl font-semibold text-fg">
            Pending invitations
          </h2>
          <ul className="grid gap-4 sm:grid-cols-2">
            {invitations.map((invitation) => (
              <li key={invitation.id}>
                <Card className="flex flex-col gap-4 p-6 sm:p-6">
                  <p className="text-sm text-fg-muted">
                    {invitationDescription(invitation.kind, invitation.intended_role)} This
                    invitation expires on{" "}
                    {new Date(invitation.expires_at).toLocaleDateString("en-US", {
                      dateStyle: "medium",
                    })}
                    .
                  </p>
                  <form action={acceptPendingInvitationAction}>
                    <input type="hidden" name="id" value={invitation.id} />
                    <Button type="submit">Accept invitation</Button>
                  </form>
                </Card>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section aria-labelledby="projects-heading" className="flex flex-col gap-4">
        <h2 id="projects-heading" className="sr-only">
          Projects
        </h2>
        {projects && projects.length > 0 ? (
          <ul className="grid gap-4 sm:grid-cols-2" data-testid="project-list">
            {projects.map((project) => (
              <li key={project.id}>
                <Card className="p-6 sm:p-6">
                  <h3 className="font-display text-lg font-semibold text-fg">{project.name}</h3>
                  <p className="mt-1 text-sm text-fg-muted">
                    {businessName(project.client_businesses)}
                  </p>
                </Card>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-fg-muted">You do not have any active projects yet.</p>
        )}
      </section>
    </AppShell>
  );
}

function businessName(value: unknown): string {
  const row = Array.isArray(value) ? value[0] : value;
  return row && typeof row === "object" && "display_name" in row ? String(row.display_name) : "";
}
