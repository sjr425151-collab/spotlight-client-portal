import { randomUUID } from "node:crypto";

import type { Metadata } from "next";
import { z } from "zod";

import { PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { requireOwner } from "@/server/auth/guards";
import { type ConflictEvent, listFinancialConflicts } from "@/server/services/billing";
import { createUserClient } from "@/server/supabase/clients";

import { StaffShell } from "../../staff-shell";
import {
  applyConflictDecisionAction,
  conflictAttemptStatusAction,
  recordConflictDecisionAction,
} from "./actions";

export const metadata: Metadata = {
  title: "Financial conflicts",
  robots: { index: false, follow: false },
};

type Search = Promise<Record<string, string | string[] | undefined>>;

const PATH = "/staff/billing/conflicts";
const uuid = z.uuid();
const areaClass =
  "rounded-control border border-line-strong bg-surface p-3 text-base text-fg sm:text-sm";

const OUTCOME_LABELS: Record<string, string> = {
  posted: "Posted",
  represented: "Already represented",
  awaiting_evidence: "Awaiting evidence",
  operational_failure: "Temporary failure",
  permanently_unsupported: "Not supported",
};

function label(value: string | null | undefined): string {
  return value ? value.replaceAll("_", " ") : "";
}

function when(value: string | null | undefined): string {
  return value ? new Date(value).toISOString().replace("T", " ").slice(0, 19) + " UTC" : "";
}

function terminal(event: ConflictEvent): boolean {
  return (
    event.attempts.some((a) =>
      ["posted", "represented", "permanently_unsupported"].includes(a.outcome),
    ) || event.attempts.length >= 10
  );
}

function Reason({ id }: { id: string }) {
  return (
    <label htmlFor={id} className="flex flex-col gap-2 text-sm font-medium text-fg">
      Reason
      <textarea id={id} name="reason" rows={2} maxLength={1000} required className={areaClass} />
    </label>
  );
}

/**
 * OI-93 conflict decisions (AUTH-010; Owner only, fresh MFA). An event whose authoritative
 * relationships name more than one project blocks every candidate project. The Owner records one
 * decision per event, then applies it; only a posted or represented application that the
 * database re-verifies clears the block. A decision alone never does.
 */
export default async function FinancialConflictsPage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireOwner({ fresh: true, returnTo: PATH });
  const result = await listFinancialConflicts(await createUserClient());
  const events = result.ok ? result.events : [];
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);
  const pending = uuid.safeParse(params.pending).success ? String(params.pending) : null;
  const pendingDecision = uuid.safeParse(params.decision).success ? String(params.decision) : null;

  return (
    <StaffShell ctx={ctx}>
      <PageHeading
        title="Financial conflicts"
        intro="Refund and dispute events that name more than one project. Each candidate project stays blocked until a decision is applied and verified."
      />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {!result.ok ? (
        <Notice tone="danger">{messageFor(result.error) ?? messageFor("unavailable")}</Notice>
      ) : null}
      {result.ok && events.length === 0 ? (
        <p className="text-fg-muted">There are no financial conflicts.</p>
      ) : null}
      <ul className="flex flex-col gap-6" data-testid="conflict-list">
        {events.map((event) => {
          const headingId = `conflict-${event.webhook_event_id}`;
          const chosen = event.candidates.find((c) => c.project_id === event.decision?.project_id);
          const isPending = pending !== null && event.decision?.id === pendingDecision;
          return (
            <li key={event.webhook_event_id}>
              <Card>
                <section aria-labelledby={headingId} className="flex flex-col gap-4">
                  <h2 id={headingId} className="font-display text-lg font-semibold text-fg">
                    {label(event.event_type)} · {event.object_id ?? event.stripe_event_id}
                  </h2>
                  <dl className="grid grid-cols-1 gap-x-6 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
                    <dt className="text-fg-muted">Stripe event</dt>
                    <dd className="text-fg">{event.stripe_event_id}</dd>
                    <dt className="text-fg-muted">Event time</dt>
                    <dd className="text-fg">{when(event.stripe_created_at)}</dd>
                    <dt className="text-fg-muted">Block</dt>
                    <dd className="font-medium text-fg">{event.cleared ? "Cleared" : "Blocked"}</dd>
                  </dl>
                  <div>
                    <h3 className="text-sm font-semibold text-fg">Candidate projects</h3>
                    <ul className="mt-2 flex flex-col gap-1 text-sm text-fg-muted">
                      {event.candidates.map((c) => (
                        <li key={c.project_id}>
                          <span className="text-fg">{c.project_name}</span> ·{" "}
                          {c.sources.map(label).join(", ")} ·{" "}
                          {c.classification.outcome
                            ? `${OUTCOME_LABELS[c.classification.outcome] ?? label(c.classification.outcome)}`
                            : "Can be applied"}
                        </li>
                      ))}
                    </ul>
                  </div>

                  {event.decision ? (
                    <div className="flex flex-col gap-3">
                      <h3 className="text-sm font-semibold text-fg">Decision</h3>
                      <p className="text-sm text-fg-muted">
                        <span className="text-fg">
                          {chosen?.project_name ?? event.decision.project_id}
                        </span>{" "}
                        · {when(event.decision.decided_at)} · {event.decision.reason}
                      </p>
                      {event.attempts.length > 0 ? (
                        <table className="text-left text-sm">
                          <caption className="sr-only">Application attempts</caption>
                          <thead>
                            <tr className="text-fg-muted">
                              <th scope="col" className="py-1 pr-4 font-medium">
                                Attempt
                              </th>
                              <th scope="col" className="py-1 pr-4 font-medium">
                                Outcome
                              </th>
                              <th scope="col" className="py-1 font-medium">
                                Time
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            {event.attempts.map((a) => (
                              <tr key={a.attempt_request_id} className="text-fg">
                                <td className="py-1 pr-4">{a.attempt_no}</td>
                                <td className="py-1 pr-4">
                                  {OUTCOME_LABELS[a.outcome] ?? label(a.outcome)}
                                  {a.terminal_reason ? " (no attempts left)" : ""}
                                </td>
                                <td className="py-1">{when(a.created_at)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      ) : null}
                      {isPending ? (
                        <div className="flex flex-col gap-3">
                          <Notice tone="info">
                            The last request has no known outcome. Check its status, or resubmit the
                            same request (safe to repeat). A new attempt is offered only once the
                            outcome is known.
                          </Notice>
                          <form action={conflictAttemptStatusAction}>
                            <input type="hidden" name="attemptRequestId" value={pending} />
                            <input type="hidden" name="decisionId" value={event.decision.id} />
                            <Button type="submit" variant="secondary">
                              Check status
                            </Button>
                          </form>
                          <form
                            action={applyConflictDecisionAction}
                            className="flex flex-col gap-3"
                          >
                            <input type="hidden" name="decisionId" value={event.decision.id} />
                            <input type="hidden" name="attemptRequestId" value={pending} />
                            <Reason id={`${headingId}-resubmit-reason`} />
                            <Button type="submit">Resubmit the same request</Button>
                          </form>
                        </div>
                      ) : !event.cleared && !terminal(event) ? (
                        <form action={applyConflictDecisionAction} className="flex flex-col gap-3">
                          <input type="hidden" name="decisionId" value={event.decision.id} />
                          <input type="hidden" name="attemptRequestId" value={randomUUID()} />
                          {event.retry_after ? (
                            <p className="text-sm text-fg-muted">
                              Earliest next attempt: {when(event.retry_after)}
                            </p>
                          ) : null}
                          <Reason id={`${headingId}-apply-reason`} />
                          <Button type="submit">Apply decision</Button>
                        </form>
                      ) : null}
                    </div>
                  ) : (
                    <form action={recordConflictDecisionAction} className="flex flex-col gap-4">
                      <input type="hidden" name="webhookEventId" value={event.webhook_event_id} />
                      <fieldset className="flex flex-col gap-2">
                        <legend className="text-sm font-medium text-fg">
                          Project the event belongs to
                        </legend>
                        {event.candidates.map((c) => (
                          <label
                            key={c.project_id}
                            className="flex items-center gap-2 text-sm text-fg-muted"
                          >
                            <input type="radio" name="projectId" value={c.project_id} required />{" "}
                            {c.project_name}
                          </label>
                        ))}
                      </fieldset>
                      <label
                        htmlFor={`${headingId}-evidence`}
                        className="flex flex-col gap-2 text-sm font-medium text-fg"
                      >
                        Evidence references
                        <textarea
                          id={`${headingId}-evidence`}
                          name="evidence"
                          rows={2}
                          maxLength={4000}
                          required
                          className={areaClass}
                        />
                      </label>
                      <Reason id={`${headingId}-decision-reason`} />
                      <Button type="submit">Record decision</Button>
                    </form>
                  )}
                </section>
              </Card>
            </li>
          );
        })}
      </ul>
    </StaffShell>
  );
}
