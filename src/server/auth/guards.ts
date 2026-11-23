import "server-only";

import { notFound, redirect } from "next/navigation";
import { z } from "zod";

import { getAuthContext, type AuthContext, type StaffRole } from "@/server/auth/context";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Server-side guards (spec 03 §10). Every page and server action outside the public
 * sign-in and invitation flow calls one of these first; tests/static/guards.test.ts
 * enforces that for every exported server action. Guards never trust client input.
 */

export type ActiveContext = AuthContext & { active: true; sessionActive: true };
export type StaffContext = ActiveContext & { staffRole: StaffRole; aal: "aal2" };

/** Any signed-in, active user with a live session. */
export async function requireUser(): Promise<ActiveContext> {
  const ctx = await getAuthContext();
  if (!ctx || !ctx.sessionActive) redirect("/sign-in");
  if (!ctx.active) redirect("/sign-in?notice=inactive");
  return ctx as ActiveContext;
}

/** A client user (not staff). Staff are sent to the staff area. */
export async function requireClient(): Promise<ActiveContext> {
  const ctx = await requireUser();
  if (ctx.staffRole) redirect("/staff");
  return ctx;
}

/**
 * Staff at aal2 (spec 03 §7). `fresh` additionally requires a TOTP verification within
 * the last five minutes (high-risk actions, §7 table); otherwise the user re-verifies.
 */
export async function requireStaff(
  options: { fresh?: boolean; returnTo?: string } = {},
): Promise<StaffContext> {
  const ctx = await requireUser();
  if (!ctx.staffRole) redirect("/portal");
  const next = safeReturnPath(options.returnTo ?? "/staff");
  if (ctx.aal !== "aal2") redirect(`/mfa?next=${encodeURIComponent(next)}`);
  if (options.fresh && !ctx.mfaFresh) {
    redirect(`/mfa?reauth=1&next=${encodeURIComponent(next)}`);
  }
  return ctx as StaffContext;
}

export async function requireOwner(
  options: { fresh?: boolean; returnTo?: string } = {},
): Promise<StaffContext> {
  const ctx = await requireStaff(options);
  if (ctx.staffRole !== "owner") redirect("/staff?notice=forbidden");
  return ctx;
}

/**
 * Project scope (spec 03 §10). The project ID from the request is re-resolved through RLS
 * on the user client: a project the caller cannot access is indistinguishable from one
 * that does not exist (404).
 */
export async function requireProjectAccess(
  projectId: string,
  options: { staff?: boolean } = {},
): Promise<ActiveContext & { projectId: string }> {
  const ctx = options.staff
    ? await requireStaff({ returnTo: `/staff/projects/${projectId}` })
    : await requireUser();
  if (!z.uuid().safeParse(projectId).success) notFound();
  const { data } = await (
    await createUserClient()
  )
    .from("projects")
    .select("id")
    .eq("id", projectId)
    .maybeSingle();
  if (!data) notFound();
  return { ...ctx, projectId };
}

/** Only same-origin absolute paths are accepted as redirect targets (no open redirects). */
export function safeReturnPath(value: string | null | undefined, fallback = "/"): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\")) {
    return fallback;
  }
  return /^\/[A-Za-z0-9/_\-?=&.%]*$/.test(value) ? value : fallback;
}
