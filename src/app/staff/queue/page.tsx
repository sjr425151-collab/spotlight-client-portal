import type { Metadata } from "next";
import Link from "next/link";

import { PageHeading } from "@/components/app/app-shell";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
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
  inactivity_formal_notice_due: "Formal notice due (pending DEP-03)",
  inactivity_suspension_eligible:
    "Administrative suspension or rescheduling eligible (pending DEP-03)",
  inactivity_review_due: "Individual review due (pending DEP-03)",
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
 *
 * AUTH-026 (OI-131): four states. Loading is the route's loading.tsx. A failed call (an
 * error, or no data) is shown as a failure with a retry link and is never presented as an
 * empty queue; it is logged server-side with the error code only. "Nothing needs attention."
 * appears only after a successful, empty result.
 */
export default async function QueuePage() {
  const ctx = await requireStaff({ returnTo: "/staff/queue" });
  const { data, error } = await (await createUserClient()).rpc("operational_queue");
  const failed = Boolean(error) || !Array.isArray(data);
  // The PostgREST error code only (for example 57014), never parameters, results or tokens.
  const failure = error ? error.code : "no_data";
  if (failed) console.error("operational_queue failed", failure);
  const items = (failed ? [] : (data as Item[])).sort((a, b) => a.queue.localeCompare(b.queue));
  const groups = Object.keys(QUEUE_LABELS).filter((q) => items.some((i) => i.queue === q));

  return (
    <StaffShell ctx={ctx}>
      <PageHeading
        title="Work queue"
        intro="Derived from project records. Nothing here is edited by hand."
      />
      {failed ? (
        <div className="flex flex-col gap-3">
          <Notice tone="danger">
            The work queue could not be loaded. Nothing is shown because the result is unknown, not
            because nothing needs attention.
          </Notice>
          <p>
            <Link href="/staff/queue" className="font-medium text-fg underline">
              Try again
            </Link>
          </p>
        </div>
      ) : groups.length === 0 ? (
        <p className="text-fg-muted">Nothing needs attention.</p>
      ) : null}
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
