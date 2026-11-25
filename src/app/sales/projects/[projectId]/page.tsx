import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { formatUsd, PACKAGES } from "@/domain/billing/pricing";
import { isInvitationExpired } from "@/lib/invitations";
import { messageFor } from "@/lib/messages";
import { requireSales } from "@/server/auth/guards";
import { projectProgress } from "@/server/services/sales";
import { createUserClient } from "@/server/supabase/clients";

import {
  inviteClientAction,
  issueOrderSummaryAction,
  resendInvitationAction,
  revokeInvitationAction,
} from "../../actions";
import { SalesShell } from "../../sales-shell";

export const metadata: Metadata = { title: "Customer", robots: { index: false, follow: false } };

type Props = {
  params: Promise<{ projectId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const yesNo = (value: boolean) => (value ? "Satisfied" : "Not yet");

/**
 * One assigned project (03 §4.1): commercial progress (derived states only, OI-72), the agreed
 * order-summary pricing (OI-83), and the pending client invitations (OI-84(e)). Every value
 * comes from sales_project_progress, which checks the active assignment on every request; an
 * unassigned or ended project is a 404.
 */
export default async function SalesProjectPage({ params, searchParams }: Props) {
  const { projectId } = await params;
  const query = await searchParams;
  const ctx = await requireSales({ returnTo: `/sales/projects/${projectId}` });
  const result = await projectProgress(await createUserClient(), projectId);
  if (!result.ok) notFound();
  const { project, business, order_summary: summary, progress } = result;
  const accepted = !["not_presented", "presented"].includes(progress.agreement_state ?? "");
  const notice = messageFor(query.notice);
  const error = messageFor(query.error);

  return (
    <SalesShell ctx={ctx}>
      <PageHeading title={project.name} intro={business.display_name} />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}

      <section aria-labelledby="progress-heading" className="flex flex-col gap-4">
        <h2 id="progress-heading" className="font-display text-xl font-semibold text-fg">
          Progress
        </h2>
        <Card>
          <dl className="grid gap-3 text-sm sm:grid-cols-2" data-testid="sales-progress">
            <div>
              <dt className="text-fg-subtle">Agreement</dt>
              <dd className="text-fg">{(progress.agreement_state ?? "").replaceAll("_", " ")}</dd>
            </div>
            <div>
              <dt className="text-fg-subtle">Deposit requirement</dt>
              <dd className="text-fg">{yesNo(progress.deposit_requirement_satisfied)}</dd>
            </div>
            <div>
              <dt className="text-fg-subtle">Final balance requirement</dt>
              <dd className="text-fg">{yesNo(progress.final_balance_requirement_satisfied)}</dd>
            </div>
            <div>
              <dt className="text-fg-subtle">Intake</dt>
              <dd className="text-fg">{(progress.intake_state ?? "").replaceAll("_", " ")}</dd>
            </div>
            <div>
              <dt className="text-fg-subtle">Preview approved</dt>
              <dd className="text-fg">{progress.preview_approved ? "Yes" : "No"}</dd>
            </div>
            <div>
              <dt className="text-fg-subtle">Ready to publish</dt>
              <dd className="text-fg">{progress.publication_eligible ? "Yes" : "No"}</dd>
            </div>
          </dl>
        </Card>
      </section>

      <section aria-labelledby="order-heading" className="flex flex-col gap-4">
        <h2 id="order-heading" className="font-display text-xl font-semibold text-fg">
          Order summary
        </h2>
        {summary ? (
          <Card data-testid="sales-order-summary">
            <p className="font-medium text-fg">
              {summary.package_display_name ?? summary.package_key} · revision {summary.revision}
              {summary.status === "superseded" ? " (replaced)" : ""}
            </p>
            <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-3">
              <div>
                <dt className="text-fg-subtle">Total development price</dt>
                <dd className="text-fg">{formatUsd(summary.package_total_cents)}</dd>
              </div>
              <div>
                <dt className="text-fg-subtle">Deposit (20%)</dt>
                <dd className="text-fg">{formatUsd(summary.deposit_cents)}</dd>
              </div>
              <div>
                <dt className="text-fg-subtle">Remaining contractual balance</dt>
                <dd className="text-fg">{formatUsd(summary.balance_cents)}</dd>
              </div>
            </dl>
            <p className="mt-3 text-sm text-fg-muted">
              Maintenance: {formatUsd(summary.maintenance_monthly_cents)} per month.
            </p>
            <h3 className="mt-4 text-sm font-medium text-fg">Standard package scope</h3>
            <ul className="mt-2 list-disc pl-5 text-sm text-fg-muted">
              {summary.scope_items.map((item) => (
                <li key={item}>{item}</li>
              ))}
            </ul>
            <p className="mt-3 text-xs text-fg-subtle">
              Scope wording is pending legal review and is not presented as legally approved.
            </p>
          </Card>
        ) : (
          <p className="text-fg-muted">No order summary yet.</p>
        )}
        {accepted ? (
          <p className="text-sm text-fg-muted">
            The client has accepted, so the order summary can no longer be replaced here.
          </p>
        ) : (
          <Card className="max-w-xl">
            <form action={issueOrderSummaryAction} className="flex flex-col gap-5">
              <input type="hidden" name="projectId" value={project.id} />
              <label
                className="flex flex-col gap-2 text-sm font-medium text-fg"
                htmlFor="packageKey"
              >
                Package
                <select
                  id="packageKey"
                  name="packageKey"
                  required
                  className="h-11 rounded-control border border-line bg-surface px-3 text-fg"
                >
                  {PACKAGES.map((p) => (
                    <option key={p.key} value={p.key}>
                      {p.name} · {formatUsd(p.totalCents)}
                    </option>
                  ))}
                </select>
              </label>
              <TextField
                label="Change reason"
                name="changeReason"
                maxLength={1000}
                hint="Internal note for the audit log; not part of the agreement. Required when replacing a summary."
              />
              <Button type="submit">
                {summary ? "Replace order summary" : "Issue order summary"}
              </Button>
            </form>
          </Card>
        )}
      </section>

      <section aria-labelledby="invitations-heading" className="flex flex-col gap-4">
        <h2 id="invitations-heading" className="font-display text-xl font-semibold text-fg">
          Client invitations
        </h2>
        {result.pending_invitations.length === 0 ? (
          <p className="text-fg-muted">No pending invitations.</p>
        ) : null}
        <ul className="flex flex-col gap-3" data-testid="sales-invitations">
          {result.pending_invitations.map((invitation) => (
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
                  <form action={resendInvitationAction}>
                    <input type="hidden" name="id" value={invitation.id} />
                    <input type="hidden" name="projectId" value={project.id} />
                    <Button type="submit" variant="secondary" className="h-9 px-3">
                      Resend
                    </Button>
                  </form>
                  <form action={revokeInvitationAction}>
                    <input type="hidden" name="id" value={invitation.id} />
                    <input type="hidden" name="projectId" value={project.id} />
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
          <h3 className="font-display text-lg font-semibold text-fg">Invite the client contact</h3>
          <form action={inviteClientAction} className="mt-5 flex flex-col gap-5">
            <input type="hidden" name="projectId" value={project.id} />
            <TextField label="Full name" name="fullName" required maxLength={200} />
            <TextField label="Email" name="email" type="email" required autoComplete="off" />
            <Button type="submit">Send invitation</Button>
          </form>
        </Card>
      </section>
    </SalesShell>
  );
}
