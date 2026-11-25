import type { Metadata } from "next";

import { PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { isInvitationExpired } from "@/lib/invitations";
import { messageFor } from "@/lib/messages";
import { requireStaff } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import {
  assignSalesRepresentativeAction,
  endSalesAssignmentAction,
  inviteStaffAction,
  resendInvitationAction,
  resetMfaAction,
  revokeInvitationAction,
  revokeStaffAction,
  setStaffRoleAction,
  setUserStatusAction,
} from "../actions";
import { StaffShell } from "../staff-shell";

export const metadata: Metadata = { title: "Team", robots: { index: false, follow: false } };

type Search = Promise<Record<string, string | string[] | undefined>>;

const ROLE_LABELS: Record<string, string> = {
  owner: "Owner",
  admin: "Admin",
  sales: "Sales Representative",
};
const roleLabel = (role: string | null) => (role ? (ROLE_LABELS[role] ?? role) : "");

/**
 * Staff management (spec 03 §4). Only the Owner can change staff; Admins can view. Sales
 * assignments (03 §4.1) are managed here by the Owner and Admins.
 */
export default async function TeamPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireStaff({ returnTo: "/staff/team" });
  const isOwner = ctx.staffRole === "owner";
  const db = await createUserClient();
  const [{ data: staff }, { data: invitations }, { data: assignments }, { data: projects }] =
    await Promise.all([
      db
        .from("staff_roles")
        .select(
          "user_id, role, status, profiles!staff_roles_user_id_fkey(email, full_name, status)",
        )
        .eq("status", "active")
        .order("granted_at", { ascending: true }),
      db
        .from("invitations")
        .select("id, email, full_name, intended_role, expires_at")
        .eq("kind", "staff")
        .eq("status", "pending"),
      db
        .from("project_sales_assignments")
        .select("id, project_id, sales_user_id, assigned_at, projects(name)")
        .eq("active", true)
        .order("assigned_at", { ascending: false }),
      db
        .from("projects")
        .select("id, name")
        .is("archived_at", null)
        .order("created_at", { ascending: true }),
    ]);
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  return (
    <StaffShell ctx={ctx}>
      <PageHeading
        title="Team"
        intro={
          isOwner
            ? "Changes to staff access need a recent authenticator check."
            : "Only the Owner can change staff access."
        }
      />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}

      <ul className="flex flex-col gap-3" data-testid="staff-list">
        {(staff ?? []).map((member) => {
          const profile = Array.isArray(member.profiles) ? member.profiles[0] : member.profiles;
          const self = member.user_id === ctx.userId;
          return (
            <li key={member.user_id}>
              <Card className="flex flex-col gap-4 p-5 sm:p-5">
                <div>
                  <p className="font-medium text-fg">
                    {profile?.full_name}{" "}
                    {self ? <span className="text-fg-subtle">(you)</span> : null}
                  </p>
                  <p className="text-sm text-fg-muted">
                    {profile?.email} · {roleLabel(member.role)}
                    {profile?.status === "deactivated" ? " · Deactivated" : ""}
                  </p>
                </div>
                {isOwner ? (
                  <div className="flex flex-wrap gap-2">
                    <form action={setStaffRoleAction} className="flex flex-wrap items-center gap-2">
                      <input type="hidden" name="userId" value={member.user_id} />
                      <input type="hidden" name="reason" value="Role changed by Owner" />
                      <label className="sr-only" htmlFor={`role-${member.user_id}`}>
                        Role for {profile?.full_name}
                      </label>
                      <select
                        id={`role-${member.user_id}`}
                        name="role"
                        defaultValue={member.role}
                        className="h-9 rounded-control border border-line bg-surface px-2 text-sm text-fg"
                      >
                        <option value="owner">Owner</option>
                        <option value="admin">Admin</option>
                        <option value="sales">Sales Representative</option>
                      </select>
                      <Button type="submit" variant="secondary" className="h-9 px-3">
                        Change role
                      </Button>
                    </form>
                    <form action={revokeStaffAction}>
                      <input type="hidden" name="userId" value={member.user_id} />
                      <input type="hidden" name="reason" value="Staff access revoked by Owner" />
                      <Button type="submit" variant="secondary" className="h-9 px-3">
                        Revoke staff access
                      </Button>
                    </form>
                    <form action={setUserStatusAction}>
                      <input type="hidden" name="userId" value={member.user_id} />
                      <input
                        type="hidden"
                        name="status"
                        value={profile?.status === "deactivated" ? "active" : "deactivated"}
                      />
                      <input type="hidden" name="reason" value="Changed by Owner" />
                      <Button type="submit" variant="ghost" className="h-9 px-3">
                        {profile?.status === "deactivated" ? "Reactivate" : "Deactivate"}
                      </Button>
                    </form>
                    <form action={resetMfaAction}>
                      <input type="hidden" name="userId" value={member.user_id} />
                      <Button type="submit" variant="ghost" className="h-9 px-3">
                        Reset authenticator
                      </Button>
                    </form>
                  </div>
                ) : null}
                {member.role === "sales" ? (
                  <SalesAssignments
                    salesUserId={member.user_id}
                    assignments={(assignments ?? []).filter(
                      (a) => a.sales_user_id === member.user_id,
                    )}
                    projects={projects ?? []}
                  />
                ) : null}
              </Card>
            </li>
          );
        })}
      </ul>

      {isOwner ? (
        <section aria-labelledby="staff-invite-heading" className="flex flex-col gap-4">
          <h2 id="staff-invite-heading" className="font-display text-xl font-semibold text-fg">
            Staff invitations
          </h2>
          <ul className="flex flex-col gap-3">
            {(invitations ?? []).map((invitation) => (
              <li key={invitation.id}>
                <Card className="flex flex-wrap items-center justify-between gap-4 p-5 sm:p-5">
                  <p className="text-sm text-fg-muted">
                    {invitation.full_name} · {invitation.email} ·{" "}
                    {roleLabel(invitation.intended_role)}
                    {isInvitationExpired(invitation.expires_at) ? (
                      <span className="text-warning"> · Expired (can no longer be used)</span>
                    ) : null}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <form action={resendInvitationAction}>
                      <input type="hidden" name="id" value={invitation.id} />
                      <input type="hidden" name="back" value="team" />
                      <Button type="submit" variant="secondary" className="h-9 px-3">
                        Resend
                      </Button>
                    </form>
                    <form action={revokeInvitationAction}>
                      <input type="hidden" name="id" value={invitation.id} />
                      <input type="hidden" name="back" value="team" />
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
            <form action={inviteStaffAction} className="flex flex-col gap-5">
              <TextField label="Full name" name="fullName" required maxLength={200} />
              <TextField label="Email" name="email" type="email" required autoComplete="off" />
              <fieldset className="flex flex-col gap-2">
                <legend className="text-sm font-medium text-fg">Role</legend>
                <label className="flex items-center gap-2 text-sm text-fg-muted">
                  <input type="radio" name="role" value="admin" defaultChecked /> Admin
                </label>
                <label className="flex items-center gap-2 text-sm text-fg-muted">
                  <input type="radio" name="role" value="owner" /> Owner
                </label>
                <label className="flex items-center gap-2 text-sm text-fg-muted">
                  <input type="radio" name="role" value="sales" /> Sales Representative
                </label>
              </fieldset>
              <Button type="submit">Send staff invitation</Button>
            </form>
          </Card>
        </section>
      ) : null}
    </StaffShell>
  );
}

type AssignmentRow = {
  id: string;
  project_id: string;
  sales_user_id: string;
  assigned_at: string;
  projects: { name: string } | { name: string }[] | null;
};

/** Active assignments of one Sales Representative, with assign and end controls (03 §4.1). */
function SalesAssignments({
  salesUserId,
  assignments,
  projects,
}: {
  salesUserId: string;
  assignments: AssignmentRow[];
  projects: { id: string; name: string }[];
}) {
  return (
    <div
      className="flex flex-col gap-3 border-t border-line/70 pt-4"
      data-testid="sales-assignments"
    >
      <p className="text-sm font-medium text-fg">Assigned projects</p>
      {assignments.length === 0 ? <p className="text-sm text-fg-muted">None.</p> : null}
      <ul className="flex flex-col gap-2">
        {assignments.map((a) => {
          const project = Array.isArray(a.projects) ? a.projects[0] : a.projects;
          return (
            <li key={a.id} className="flex flex-wrap items-center justify-between gap-3">
              <span className="text-sm text-fg-muted">{project?.name ?? a.project_id}</span>
              <form action={endSalesAssignmentAction}>
                <input type="hidden" name="assignmentId" value={a.id} />
                <input type="hidden" name="reason" value="Ended by staff" />
                <Button type="submit" variant="ghost" className="h-9 px-3">
                  End assignment
                </Button>
              </form>
            </li>
          );
        })}
      </ul>
      <form action={assignSalesRepresentativeAction} className="flex flex-wrap items-center gap-2">
        <input type="hidden" name="salesUserId" value={salesUserId} />
        <input type="hidden" name="reason" value="Assigned by staff" />
        <label className="sr-only" htmlFor={`assign-${salesUserId}`}>
          Project to assign
        </label>
        <select
          id={`assign-${salesUserId}`}
          name="projectId"
          className="h-9 rounded-control border border-line bg-surface px-2 text-sm text-fg"
        >
          {projects.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name}
            </option>
          ))}
        </select>
        <Button type="submit" variant="secondary" className="h-9 px-3">
          Assign project
        </Button>
      </form>
    </div>
  );
}
