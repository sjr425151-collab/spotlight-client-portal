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
  inviteStaffAction,
  resetMfaAction,
  revokeInvitationAction,
  revokeStaffAction,
  setStaffRoleAction,
  setUserStatusAction,
} from "../actions";
import { StaffShell } from "../staff-shell";

export const metadata: Metadata = { title: "Team", robots: { index: false, follow: false } };

type Search = Promise<Record<string, string | string[] | undefined>>;

/** Staff management (spec 03 §4). Only the Owner can change staff; Admins can view. */
export default async function TeamPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireStaff({ returnTo: "/staff/team" });
  const isOwner = ctx.staffRole === "owner";
  const db = await createUserClient();
  const [{ data: staff }, { data: invitations }] = await Promise.all([
    db
      .from("staff_roles")
      .select("user_id, role, status, profiles!staff_roles_user_id_fkey(email, full_name, status)")
      .eq("status", "active")
      .order("granted_at", { ascending: true }),
    db
      .from("invitations")
      .select("id, email, full_name, intended_role, expires_at")
      .eq("kind", "staff")
      .eq("status", "pending"),
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
                    {profile?.email} · {member.role === "owner" ? "Owner" : "Admin"}
                    {profile?.status === "deactivated" ? " · Deactivated" : ""}
                  </p>
                </div>
                {isOwner ? (
                  <div className="flex flex-wrap gap-2">
                    <form action={setStaffRoleAction}>
                      <input type="hidden" name="userId" value={member.user_id} />
                      <input
                        type="hidden"
                        name="role"
                        value={member.role === "owner" ? "admin" : "owner"}
                      />
                      <input type="hidden" name="reason" value="Role changed by Owner" />
                      <Button type="submit" variant="secondary" className="h-9 px-3">
                        {member.role === "owner" ? "Make Admin" : "Make Owner"}
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
                    {invitation.full_name} · {invitation.email} · {invitation.intended_role}
                    {isInvitationExpired(invitation.expires_at) ? (
                      <span className="text-warning"> · Expired (can no longer be used)</span>
                    ) : null}
                  </p>
                  <form action={revokeInvitationAction}>
                    <input type="hidden" name="id" value={invitation.id} />
                    <input type="hidden" name="back" value="team" />
                    <Button type="submit" variant="secondary" className="h-9 px-3">
                      Revoke
                    </Button>
                  </form>
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
              </fieldset>
              <Button type="submit">Send staff invitation</Button>
            </form>
          </Card>
        </section>
      ) : null}
    </StaffShell>
  );
}
