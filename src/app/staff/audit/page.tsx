import type { Metadata } from "next";

import { PageHeading } from "@/components/app/app-shell";
import { requireStaff } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import { StaffShell } from "../staff-shell";

export const metadata: Metadata = { title: "Audit log", robots: { index: false, follow: false } };

/**
 * Append-only audit log (spec 03 §11). RLS limits Admins to non-financial categories.
 * Summaries never contain secrets, OTPs, or tokens.
 */
export default async function AuditPage() {
  const ctx = await requireStaff({ returnTo: "/staff/audit" });
  const { data: events } = await (
    await createUserClient()
  )
    .from("audit_events")
    .select("id, occurred_at, actor_role, action, target_type, target_id, category")
    .order("occurred_at", { ascending: false })
    .limit(200);

  return (
    <StaffShell ctx={ctx}>
      <PageHeading
        title="Audit log"
        intro="The 200 most recent events. Entries can never be edited or deleted."
      />
      <div className="overflow-x-auto rounded-card border border-line">
        <table className="w-full min-w-[40rem] text-left text-sm">
          <thead className="bg-surface text-fg-muted">
            <tr>
              <th scope="col" className="px-4 py-3 font-medium">
                When (UTC)
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Actor
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Action
              </th>
              <th scope="col" className="px-4 py-3 font-medium">
                Target
              </th>
            </tr>
          </thead>
          <tbody>
            {(events ?? []).map((event) => (
              <tr key={event.id} className="border-t border-line">
                <td className="px-4 py-3 whitespace-nowrap text-fg-muted">
                  {new Date(event.occurred_at).toISOString().replace("T", " ").slice(0, 19)}
                </td>
                <td className="px-4 py-3 text-fg-muted">{event.actor_role}</td>
                <td className="px-4 py-3 font-mono text-fg">{event.action}</td>
                <td className="px-4 py-3 text-fg-muted">{event.target_type ?? "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </StaffShell>
  );
}
