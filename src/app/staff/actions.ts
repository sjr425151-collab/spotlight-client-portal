"use server";

import { redirect } from "next/navigation";
import { z } from "zod";

import { env } from "@/config/env";
import { requireOwner, requireStaff } from "@/server/auth/guards";
import {
  createInvitation,
  createInvitationSchema,
  resendInvitation,
  uuidSchema,
} from "@/server/services/invitations";
import {
  assignSalesRepresentative,
  endSalesAssignment,
  resetMfa,
  revokeInvitation,
  revokeMembership,
  revokeStaff,
  setStaffRole,
  setUserStatus,
} from "@/server/services/staff";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Staff server actions (spec 03 §4). Each one starts with a guard; the database
 * re-authorizes every write (RLS and definer checks), so a missing guard can never
 * grant access on its own.
 */

const text = (formData: FormData, key: string) => String(formData.get(key) ?? "");
const reasonOf = (formData: FormData) => text(formData, "reason").trim().slice(0, 500);

function done(path: string, result: { ok: boolean; error?: string }, okCode = "saved"): never {
  const query = result.ok ? `notice=${okCode}` : `error=${result.error ?? "unavailable"}`;
  redirect(`${path}?${query}` as never);
}

function projectPath(projectId: string) {
  return uuidSchema.safeParse(projectId).success ? `/staff/projects/${projectId}` : "/staff";
}

const projectSchema = z.object({
  legalName: z.string().trim().min(1).max(200),
  displayName: z.string().trim().min(1).max(200),
  projectName: z.string().trim().min(1).max(200),
});

export async function createProjectAction(formData: FormData) {
  await requireStaff();
  const input = projectSchema.safeParse({
    legalName: text(formData, "legalName"),
    displayName: text(formData, "displayName") || text(formData, "legalName"),
    projectName: text(formData, "projectName"),
  });
  if (!input.success) done("/staff", { ok: false, error: "invalid_input" });
  const db = await createUserClient();
  const { data: business, error } = await db
    .from("client_businesses")
    .insert({ legal_name: input.data.legalName, display_name: input.data.displayName })
    .select("id")
    .single();
  if (error || !business) done("/staff", { ok: false, error: "unavailable" });
  const { data: project, error: projectError } = await db
    .from("projects")
    .insert({ client_business_id: business.id, name: input.data.projectName })
    .select("id")
    .single();
  if (projectError || !project) done("/staff", { ok: false, error: "unavailable" });
  done(projectPath(project.id), { ok: true });
}

export async function inviteClientAction(formData: FormData) {
  await requireStaff();
  const projectId = text(formData, "projectId");
  const input = createInvitationSchema.safeParse({
    kind: "client",
    email: text(formData, "email"),
    fullName: text(formData, "fullName"),
    projectId,
  });
  if (!input.success) done(projectPath(projectId), { ok: false, error: "invalid_input" });
  const result = await createInvitation(
    {
      user: await createUserClient(),
      siteUrl: env.NEXT_PUBLIC_SITE_URL,
    },
    input.data,
  );
  done(
    projectPath(projectId),
    result,
    result.ok && !result.emailSent ? "invite_existing_user" : "invite_sent",
  );
}

export async function revokeInvitationAction(formData: FormData) {
  await requireStaff();
  const back =
    text(formData, "back") === "team" ? "/staff/team" : projectPath(text(formData, "projectId"));
  done(back, await revokeInvitation(await createUserClient(), text(formData, "id")));
}

/**
 * Resend (OI-84(d)): revoke, then reissue with a new token and expiry. The invitation's
 * address and name are read from the database through RLS, never from the form; the two
 * database calls authorize the caller again (staff invitations: Owner with fresh MFA).
 */
export async function resendInvitationAction(formData: FormData) {
  await requireStaff();
  const id = text(formData, "id");
  const back =
    text(formData, "back") === "team" ? "/staff/team" : projectPath(text(formData, "projectId"));
  if (!uuidSchema.safeParse(id).success) done(back, { ok: false, error: "not_found" });
  const db = await createUserClient();
  const { data: invitation } = await db
    .from("invitations")
    .select("id, kind, email, full_name, project_id, intended_role")
    .eq("id", id)
    .eq("status", "pending")
    .maybeSingle();
  if (!invitation) done(back, { ok: false, error: "not_found" });
  const role = invitation.intended_role;
  const result = await resendInvitation(
    { user: db, siteUrl: env.NEXT_PUBLIC_SITE_URL },
    {
      id: invitation.id,
      kind: invitation.kind === "staff" ? "staff" : "client",
      email: String(invitation.email),
      fullName: invitation.full_name,
      projectId: invitation.project_id,
      role: role === "owner" || role === "admin" || role === "sales" ? role : undefined,
    },
  );
  done(back, result, "invitation_resent");
}

/** Owner or Admin: assign or reassign a project to a Sales Representative (03 §4.1). */
export async function assignSalesRepresentativeAction(formData: FormData) {
  await requireStaff({ returnTo: "/staff/team" });
  done(
    "/staff/team",
    await assignSalesRepresentative(
      await createUserClient(),
      text(formData, "projectId"),
      text(formData, "salesUserId"),
      reasonOf(formData),
    ),
    "assignment_saved",
  );
}

/** Owner or Admin: end an assignment; access ends at the next check (OI-78). */
export async function endSalesAssignmentAction(formData: FormData) {
  await requireStaff({ returnTo: "/staff/team" });
  done(
    "/staff/team",
    await endSalesAssignment(
      await createUserClient(),
      text(formData, "assignmentId"),
      reasonOf(formData),
    ),
    "assignment_ended",
  );
}

export async function revokeMembershipAction(formData: FormData) {
  await requireStaff();
  const path = projectPath(text(formData, "projectId"));
  done(
    path,
    await revokeMembership(await createUserClient(), text(formData, "id"), reasonOf(formData)),
  );
}

export async function inviteStaffAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: "/staff/team" });
  const input = createInvitationSchema.safeParse({
    kind: "staff",
    email: text(formData, "email"),
    fullName: text(formData, "fullName"),
    role: text(formData, "role"),
  });
  if (!input.success) done("/staff/team", { ok: false, error: "invalid_input" });
  const result = await createInvitation(
    {
      user: await createUserClient(),
      siteUrl: env.NEXT_PUBLIC_SITE_URL,
    },
    input.data,
  );
  done(
    "/staff/team",
    result,
    result.ok && !result.emailSent ? "invite_existing_user" : "invite_sent",
  );
}

export async function setStaffRoleAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: "/staff/team" });
  const role = text(formData, "role");
  // "fulfillment" reaches the database, which rejects and audits it (OI-03). "sales" is
  // rejected by the database for a user with an active membership (03 §4.1(a)).
  if (role !== "owner" && role !== "admin" && role !== "sales" && role !== "fulfillment") {
    done("/staff/team", { ok: false, error: "invalid_input" });
  }
  done(
    "/staff/team",
    await setStaffRole(
      await createUserClient(),
      text(formData, "userId"),
      role,
      reasonOf(formData),
    ),
  );
}

export async function revokeStaffAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: "/staff/team" });
  done(
    "/staff/team",
    await revokeStaff(await createUserClient(), text(formData, "userId"), reasonOf(formData)),
  );
}

function statusReturnPath(formData: FormData) {
  return text(formData, "back") === "project"
    ? projectPath(text(formData, "projectId"))
    : "/staff/team";
}

export async function setUserStatusAction(formData: FormData) {
  await requireStaff({ fresh: true, returnTo: statusReturnPath(formData) });
  const back = statusReturnPath(formData);
  const status = text(formData, "status") === "active" ? "active" : "deactivated";
  done(
    back,
    await setUserStatus(
      await createUserClient(),
      text(formData, "userId"),
      status,
      reasonOf(formData),
    ),
  );
}

export async function resetMfaAction(formData: FormData) {
  await requireOwner({ fresh: true, returnTo: "/staff/team" });
  const userId = text(formData, "userId");
  if (!uuidSchema.safeParse(userId).success)
    done("/staff/team", { ok: false, error: "invalid_input" });
  done("/staff/team", await resetMfa(await createUserClient(), userId), "mfa_reset");
}
