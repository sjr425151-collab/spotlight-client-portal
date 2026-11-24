import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { PACKAGES, formatUsd } from "@/domain/billing/pricing";
import type { StaffContext } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import {
  clearBillingHoldAction,
  issueOrderSummaryAction,
  placeBillingHoldAction,
  recordAuthorizationRevocationAction,
  reviewAuthorizationRevocationAction,
} from "../../billing-actions";

/**
 * WP-B section of the staff project page (spec 04 §4, §14; 03 §4; 05 §9; OI-72, OI-83).
 * Owner and Admin see the six derived operational states and the agreed order-summary
 * pricing (total, deposit, balance). Owner-restricted detail (ledger, holds, the payment
 * authorization) is read through RLS, which returns nothing to an Admin: the database, not
 * this component, is the control.
 */

const STATE_LABELS: Array<[string, string]> = [
  ["deposit_requirement_satisfied", "Deposit requirement"],
  ["final_balance_requirement_satisfied", "Final balance requirement"],
  ["payment_recovery_required", "Payment recovery required"],
  ["publication_financially_eligible", "Financial publication requirements"],
  ["billing_operational_hold", "Billing-related operational hold"],
  ["owner_intervention_required", "Owner intervention required"],
];

export async function BillingSection({ ctx, projectId }: { ctx: StaffContext; projectId: string }) {
  const db = await createUserClient();
  const isOwner = ctx.staffRole === "owner";
  const [
    { data: states },
    { data: summary },
    { data: ledger },
    { data: holds },
    { data: authorizations },
  ] = await Promise.all([
    db.rpc("operational_payment_states", { p_project_ids: [projectId] }),
    db
      .from("order_summaries")
      .select(
        "id, revision, package_key, package_total_cents, deposit_cents, balance_cents, status, agreement_acceptances(id, business_name_matches)",
      )
      .eq("project_id", projectId)
      .eq("status", "presented")
      .maybeSingle(),
    isOwner
      ? db
          .from("ledger_entries")
          .select(
            "id, entry_type, amount_cents, service_category, obligation_id, holding_charge_key, posted_at",
          )
          .eq("project_id", projectId)
          .order("id")
      : Promise.resolve({ data: [] as never[] }),
    isOwner
      ? db
          .from("billing_holds")
          .select("id, hold_type, reason, placed_at")
          .eq("project_id", projectId)
          .is("cleared_at", null)
      : Promise.resolve({ data: [] as never[] }),
    isOwner
      ? db
          .from("payment_authorizations")
          .select(
            "id, status, authorized_balance_cents, revoked_at, revocation_source, revocation_reviewed_at",
          )
          .eq("project_id", projectId)
          .order("created_at", { ascending: false })
      : Promise.resolve({ data: [] as never[] }),
  ]);
  const authorization = (authorizations ?? [])[0] as
    | {
        id: string;
        status: string;
        authorized_balance_cents: number;
        revoked_at: string | null;
        revocation_source: string | null;
        revocation_reviewed_at: string | null;
      }
    | undefined;
  const row = (Array.isArray(states) ? states[0] : null) as Record<string, boolean> | null;
  const acceptance = summary
    ? ((Array.isArray(summary.agreement_acceptances)
        ? summary.agreement_acceptances[0]
        : summary.agreement_acceptances) as { id: string; business_name_matches: boolean } | null)
    : null;

  return (
    <section aria-labelledby="billing-heading" className="flex flex-col gap-4">
      <h2 id="billing-heading" className="font-display text-xl font-semibold text-fg">
        Agreement and payments
      </h2>
      <Card className="flex flex-col gap-3" data-testid="derived-payment-states">
        <h3 className="font-display text-lg font-semibold text-fg">Operational status</h3>
        {row ? (
          <dl className="grid gap-2 text-sm sm:grid-cols-[1fr_auto]">
            {STATE_LABELS.map(([key, label]) => (
              <div key={key} className="contents">
                <dt className="text-fg-muted">{label}</dt>
                <dd className="font-medium text-fg sm:text-right">
                  {key.endsWith("_satisfied") || key.endsWith("_eligible")
                    ? row[key]
                      ? "Satisfied"
                      : "Not satisfied"
                    : row[key]
                      ? "Yes"
                      : "No"}
                </dd>
              </div>
            ))}
          </dl>
        ) : (
          <p className="text-sm text-fg-muted">Status unavailable.</p>
        )}
      </Card>

      <Card className="flex flex-col gap-4">
        <h3 className="font-display text-lg font-semibold text-fg">Order summary</h3>
        {summary ? (
          <p className="text-sm text-fg-muted">
            Revision {summary.revision}: {PACKAGES.find((p) => p.key === summary.package_key)?.name}
            . Total {formatUsd(summary.package_total_cents)}, deposit{" "}
            {formatUsd(summary.deposit_cents)}, balance {formatUsd(summary.balance_cents)}.{" "}
            {acceptance
              ? acceptance.business_name_matches
                ? "Accepted."
                : "Accepted; the business name differs from the summary and needs review."
              : "Awaiting acceptance."}
          </p>
        ) : (
          <p className="text-sm text-fg-muted">No order summary has been issued.</p>
        )}
        <form action={issueOrderSummaryAction} className="flex max-w-xl flex-col gap-4">
          <input type="hidden" name="projectId" value={projectId} />
          <label className="flex flex-col gap-2 text-sm font-medium text-fg">
            Package
            <select
              name="packageKey"
              className="h-11 rounded-control border border-line-strong bg-surface px-3 text-fg"
            >
              {PACKAGES.map((p) => (
                <option key={p.key} value={p.key}>
                  {p.name} ({formatUsd(p.totalCents)})
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-2 text-sm font-medium text-fg">
            Included scope (one item per line)
            <textarea
              name="scopeItems"
              rows={3}
              maxLength={8000}
              className="rounded-control border border-line-strong bg-surface p-3 text-fg"
            />
          </label>
          {summary ? (
            <TextField
              label="Reason for the new summary (material change)"
              name="changeReason"
              required
              maxLength={1000}
            />
          ) : null}
          <Button type="submit" variant="secondary">
            {summary ? "Issue a new order summary" : "Issue order summary"}
          </Button>
        </form>
      </Card>

      {isOwner ? (
        <Card className="flex flex-col gap-4" data-testid="owner-financial-detail">
          <h3 className="font-display text-lg font-semibold text-fg">Ledger (Owner only)</h3>
          {(ledger ?? []).length === 0 ? (
            <p className="text-sm text-fg-muted">No entries.</p>
          ) : null}
          <ul className="flex flex-col gap-1 text-sm">
            {(ledger ?? []).map((entry) => (
              <li key={entry.id} className="flex justify-between gap-4 text-fg-muted">
                <span>
                  {entry.entry_type} ·{" "}
                  {entry.service_category ?? `unresolved (${entry.holding_charge_key ?? ""})`}
                </span>
                <span className="font-medium text-fg">{formatUsd(Number(entry.amount_cents))}</span>
              </li>
            ))}
          </ul>
          <h3 className="font-display text-lg font-semibold text-fg">
            Final-payment authorization (Owner only)
          </h3>
          <p className="text-sm text-fg-muted" data-testid="owner-authorization-state">
            {authorization
              ? `${authorization.status}; authorized balance ${formatUsd(
                  Number(authorization.authorized_balance_cents),
                )}${
                  authorization.revoked_at
                    ? `; revoked by ${authorization.revocation_source ?? "unknown"}${
                        authorization.revocation_reviewed_at ? ", reviewed" : ", awaiting review"
                      }`
                    : ""
                }`
              : "No authorization recorded."}
          </p>
          {authorization && authorization.status !== "revoked" ? (
            <form
              action={recordAuthorizationRevocationAction}
              className="flex flex-wrap items-end gap-3"
            >
              <input type="hidden" name="projectId" value={projectId} />
              <TextField label="Reason" name="reason" required maxLength={1000} />
              <Button type="submit" variant="secondary">
                Record revocation received outside the portal
              </Button>
            </form>
          ) : null}
          {authorization?.revoked_at && !authorization.revocation_reviewed_at ? (
            <form
              action={reviewAuthorizationRevocationAction}
              className="flex flex-wrap items-end gap-3"
            >
              <input type="hidden" name="projectId" value={projectId} />
              <TextField label="Review note" name="note" required maxLength={1000} />
              <Button type="submit" variant="secondary">
                Record review
              </Button>
            </form>
          ) : null}
          <h3 className="font-display text-lg font-semibold text-fg">Active billing holds</h3>
          <ul className="flex flex-col gap-3">
            {(holds ?? []).map((hold) => (
              <li key={hold.id}>
                <form action={clearBillingHoldAction} className="flex flex-wrap items-end gap-3">
                  <input type="hidden" name="projectId" value={projectId} />
                  <input type="hidden" name="holdId" value={hold.id} />
                  <input type="hidden" name="holdType" value={hold.hold_type} />
                  <span className="text-sm text-fg">{hold.hold_type}</span>
                  <TextField label="Reason" name="reason" required maxLength={1000} />
                  <Button type="submit" variant="ghost">
                    {hold.hold_type === "maintenance_payment_hold"
                      ? "Authorize exception"
                      : "Clear hold"}
                  </Button>
                </form>
              </li>
            ))}
          </ul>
          <form action={placeBillingHoldAction} className="flex flex-wrap items-end gap-3">
            <input type="hidden" name="projectId" value={projectId} />
            <label className="flex flex-col gap-2 text-sm font-medium text-fg">
              Hold type
              <select
                name="holdType"
                className="h-11 rounded-control border border-line-strong bg-surface px-3 text-fg"
              >
                <option value="owner_manual_hold">Owner manual hold</option>
                <option value="dispute_risk_hold">Dispute risk hold</option>
              </select>
            </label>
            <TextField label="Reason" name="reason" required maxLength={1000} />
            <Button type="submit" variant="secondary">
              Place hold
            </Button>
          </form>
        </Card>
      ) : null}
    </section>
  );
}
