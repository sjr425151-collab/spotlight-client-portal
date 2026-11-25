import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { isInvitationExpired } from "@/lib/invitations";
import { messageFor } from "@/lib/messages";
import { requireProjectAccess, type StaffContext } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import {
  inviteClientAction,
  resendInvitationAction,
  revokeInvitationAction,
  revokeMembershipAction,
  setUserStatusAction,
} from "../../actions";
import { StaffShell } from "../../staff-shell";
import { FulfillmentPanel } from "./fulfillment-panel";
import { BillingSection } from "./billing-section";

export const metadata: Metadata = { title: "Project", robots: { index: false, follow: false } };

type Props = {
  params: Promise<{ projectId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

export default async function StaffProjectPage({ params, searchParams }: Props) {
  const { projectId } = await params;
  const query = await searchParams;
  const ctx = (await requireProjectAccess(projectId, { staff: true })) as StaffContext;

  const db = await createUserClient();
  const [{ data: project }, { data: members }, { data: invitations }] = await Promise.all([
    db
      .from("projects")
      .select("id, name, client_businesses(display_name, legal_name)")
      .eq("id", projectId)
      .maybeSingle(),
    db
      .from("project_memberships")
      .select(
        "id, user_id, created_at, profiles!project_memberships_user_id_fkey(email, full_name, status)",
      )
      .eq("project_id", projectId)
      .eq("status", "active"),
    db
      .from("invitations")
      .select("id, email, full_name, expires_at, failed_attempts")
      .eq("project_id", projectId)
      .eq("status", "pending")
      .order("created_at", { ascending: false }),
  ]);
  if (!project) notFound();
  const notice = messageFor(query.notice);
  const error = messageFor(query.error);

  return (
    <StaffShell ctx={ctx}>
      <PageHeading title={project.name} intro={businessOf(project.client_businesses)} />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}

      <section aria-labelledby="members-heading" className="flex flex-col gap-4">
        <h2 id="members-heading" className="font-display text-xl font-semibold text-fg">
          Client users
        </h2>
        {(members ?? []).length === 0 ? (
          <p className="text-fg-muted">No client users yet.</p>
        ) : null}
        <ul className="flex flex-col gap-3">
          {(members ?? []).map((member) => {
            const profile = one(member.profiles);
            return (
              <li key={member.id}>
                <Card className="flex flex-wrap items-center justify-between gap-4 p-5 sm:p-5">
                  <div>
                    <p className="font-medium text-fg">{profile?.full_name}</p>
                    <p className="text-sm text-fg-muted">
                      {profile?.email}
                      {profile?.status === "deactivated" ? " · Deactivated" : ""}
                    </p>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    <form action={revokeMembershipAction} className="flex gap-2">
                      <input type="hidden" name="id" value={member.id} />
                      <input type="hidden" name="projectId" value={projectId} />
                      <input type="hidden" name="reason" value="Removed from project by staff" />
                      <Button type="submit" variant="secondary" className="h-9 px-3">
                        Remove from project
                      </Button>
                    </form>
                    <form action={setUserStatusAction}>
                      <input type="hidden" name="userId" value={member.user_id} />
                      <input type="hidden" name="projectId" value={projectId} />
                      <input type="hidden" name="back" value="project" />
                      <input
                        type="hidden"
                        name="status"
                        value={profile?.status === "deactivated" ? "active" : "deactivated"}
                      />
                      <Button type="submit" variant="ghost" className="h-9 px-3">
                        {profile?.status === "deactivated" ? "Reactivate user" : "Deactivate user"}
                      </Button>
                    </form>
                  </div>
                </Card>
              </li>
            );
          })}
        </ul>
      </section>

      <section aria-labelledby="invitations-heading" className="flex flex-col gap-4">
        <h2 id="invitations-heading" className="font-display text-xl font-semibold text-fg">
          Pending invitations
        </h2>
        {(invitations ?? []).length === 0 ? (
          <p className="text-fg-muted">No pending invitations.</p>
        ) : null}
        <ul className="flex flex-col gap-3">
          {(invitations ?? []).map((invitation) => (
            <li key={invitation.id}>
              <Card className="flex flex-wrap items-center justify-between gap-4 p-5 sm:p-5">
                <div>
                  <p className="font-medium text-fg">{invitation.full_name}</p>
                  <p className="text-sm text-fg-muted">
                    {invitation.email} ·{" "}
                    {isInvitationExpired(invitation.expires_at) ? (
                      <span className="text-warning">Expired (can no longer be used)</span>
                    ) : (
                      <>
                        expires{" "}
                        {new Date(invitation.expires_at).toLocaleDateString("en-US", {
                          dateStyle: "medium",
                        })}
                      </>
                    )}
                  </p>
                </div>
                <div className="flex flex-wrap gap-2">
                  {/* Resend revokes this invitation and issues a new one (OI-84(d)). */}
                  <form action={resendInvitationAction}>
                    <input type="hidden" name="id" value={invitation.id} />
                    <input type="hidden" name="projectId" value={projectId} />
                    <Button type="submit" variant="secondary" className="h-9 px-3">
                      Resend
                    </Button>
                  </form>
                  <form action={revokeInvitationAction}>
                    <input type="hidden" name="id" value={invitation.id} />
                    <input type="hidden" name="projectId" value={projectId} />
                    <Button type="submit" variant="secondary" className="h-9 px-3">
                      Revoke
                    </Button>
                  </form>
                </div>
              </Card>
            </li>
          ))}
        </ul>
        <Card className="max-w-xl">
          <h3 className="font-display text-lg font-semibold text-fg">Invite a client user</h3>
          <p className="mt-2 text-sm text-fg-muted">
            Sending a new invitation to the same email replaces the previous one.
          </p>
          <form action={inviteClientAction} className="mt-5 flex flex-col gap-5">
            <input type="hidden" name="projectId" value={projectId} />
            <TextField label="Full name" name="fullName" required maxLength={200} />
            <TextField label="Email" name="email" type="email" required autoComplete="off" />
            <Button type="submit">Send invitation</Button>
          </form>
        </Card>
      </section>

      <FulfillmentPanel projectId={projectId} ctx={ctx} />
      <BillingSection ctx={ctx} projectId={projectId} />
    </StaffShell>
  );
}

function one<T>(value: T | T[] | null): T | null {
  return Array.isArray(value) ? (value[0] ?? null) : value;
}

function businessOf(value: unknown): string {
  const row = Array.isArray(value) ? value[0] : value;
  return row && typeof row === "object" && "display_name" in row ? String(row.display_name) : "";
}
