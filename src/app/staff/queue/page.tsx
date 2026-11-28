import type { Metadata } from "next";
import Link from "next/link";

import { PageHeading } from "@/components/app/app-shell";
import { Card } from "@/components/ui/card";
import { requireStaff } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import { StaffShell } from "../staff-shell";

export const metadata: Metadata = { title: "Work queue", robots: { index: false, follow: false } };

const QUEUE_LABELS: Record<string, string> = {
  awaiting_deposit: "Awaiting deposit",
  intake_pending: "Intake pending",
  intake_review: "Intake review",
  in_development: "In development",
  awaiting_scope_acknowledgment: "Awaiting scope acknowledgment",
  awaiting_client_approval: "Awaiting client approval",
  approval_outreach_due: "Approval outreach due",
  approval_followup_due: "Approval follow-up due",
  approval_hold_eligible: "Approval hold eligible",
  approval_hold_review: "Approval hold review",
  awaiting_final_payment: "Awaiting final payment",
  ready_for_publication_review: "Ready for publication review",
  blocked_by_hold: "Blocked by hold",
  publication_verification_failed: "Publication verification failed",
  upload_review: "Upload review",
  domain_expiries: "Domain expiries",
};

type Item = {
  queue: string;
  project_id: string;
  project_name: string;
  due_on?: string;
  detail?: Record<string, unknown>;
};

function describe(detail: Record<string, unknown> | undefined): string {
  if (!detail) return "";
  return Object.entries(detail)
    .map(([k, v]) => `${k.replaceAll("_", " ")}: ${String(v).replaceAll("_", " ")}`)
    .join(" · ");
}

/**
 * Derived operational queue (05 §9). Computed by the database on every request from
 * authoritative records; never maintained by hand. OI-72: the database returns financial
 * inputs only as derived states, and billing hold types to the Owner only.
 */
export default async function QueuePage() {
  const ctx = await requireStaff({ returnTo: "/staff/queue" });
  const { data } = await (await createUserClient()).rpc("operational_queue");
  const items = ((data ?? []) as Item[]).sort((a, b) => a.queue.localeCompare(b.queue));
  const groups = Object.keys(QUEUE_LABELS).filter((q) => items.some((i) => i.queue === q));

  return (
    <StaffShell ctx={ctx}>
      <PageHeading
        title="Work queue"
        intro="Derived from project records. Nothing here is edited by hand."
      />
      {groups.length === 0 ? <p className="text-fg-muted">Nothing needs attention.</p> : null}
      {groups.map((queue) => (
        <section key={queue} aria-labelledby={`q-${queue}`} className="flex flex-col gap-3">
          <h2 id={`q-${queue}`} className="font-display text-lg font-semibold text-fg">
            {QUEUE_LABELS[queue]}
          </h2>
          <ul className="flex flex-col gap-2">
            {items
              .filter((i) => i.queue === queue)
              .map((i, index) => (
                <li key={`${i.project_id}-${index}`}>
                  <Card className="p-4 sm:p-4">
                    <Link
                      href={`/staff/projects/${i.project_id}`}
                      className="font-medium text-fg hover:underline"
                    >
                      {i.project_name}
                    </Link>
                    <p className="text-sm text-fg-muted">
                      {describe(i.detail)}
                      {i.due_on ? ` · due ${i.due_on}` : ""}
                    </p>
                  </Card>
                </li>
              ))}
          </ul>
        </section>
      ))}
    </StaffShell>
  );
}
