import { TEST_FIXTURE_LABEL } from "@/domain/billing/agreement";
import { formatUsd } from "@/domain/billing/pricing";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";

/**
 * Agreement presentation and acceptance (spec 04 §1-§3; OI-28, OI-69; 07 §10-§11).
 * Server components only: no client JavaScript is needed, and the server validates every
 * field again (T-AGR-01, T-AGR-06). The two checkboxes are separate and unchecked by default.
 */

/** OI-69: shown on every screen that displays the test-only fixture. */
export function FixtureLabel() {
  return (
    <p
      role="note"
      data-testid="test-fixture-label"
      className="rounded-control border border-warning/70 bg-surface px-4 py-3 text-sm font-semibold tracking-wide text-warning"
    >
      {TEST_FIXTURE_LABEL}. This placeholder is used only in tests and non-production environments.
    </p>
  );
}

export interface OrderSummaryView {
  id: string;
  revision: number;
  packageName: string;
  totalCents: number;
  depositCents: number;
  balanceCents: number;
  maintenanceMonthlyCents: number;
  scopeItems: string[];
  businessLegalName: string;
}

export function OrderSummaryCard({ summary }: { summary: OrderSummaryView }) {
  const rows: Array<[string, string]> = [
    ["Package", summary.packageName],
    ["Package total", formatUsd(summary.totalCents)],
    ["Deposit (due now)", formatUsd(summary.depositCents)],
    [
      "Website Care & Maintenance (due now, then monthly)",
      `${formatUsd(summary.maintenanceMonthlyCents)} per month`,
    ],
    ["Initial payment", formatUsd(summary.depositCents + summary.maintenanceMonthlyCents)],
    ["Remaining balance (due on your final approval)", formatUsd(summary.balanceCents)],
  ];
  return (
    <Card className="flex flex-col gap-4">
      <h2 className="font-display text-xl font-semibold text-fg">
        Order summary <span className="text-fg-subtle">(revision {summary.revision})</span>
      </h2>
      <p className="text-sm text-fg-muted">For {summary.businessLegalName}</p>
      <dl className="grid gap-2 text-sm sm:grid-cols-[1fr_auto]">
        {rows.map(([term, value]) => (
          <div key={term} className="contents">
            <dt className="text-fg-muted">{term}</dt>
            <dd className="font-medium text-fg sm:text-right">{value}</dd>
          </div>
        ))}
      </dl>
      {summary.scopeItems.length > 0 ? (
        <ul className="list-disc pl-5 text-sm text-fg-muted">
          {summary.scopeItems.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ul>
      ) : null}
    </Card>
  );
}

export function AgreementDocument({
  versionLabel,
  text,
  isTestFixture,
}: {
  versionLabel: string;
  text: string;
  isTestFixture: boolean;
}) {
  return (
    <Card className="flex flex-col gap-4">
      {isTestFixture ? <FixtureLabel /> : null}
      <h2 className="font-display text-xl font-semibold text-fg">
        Agreement version {versionLabel}
      </h2>
      <div className="max-h-96 overflow-y-auto whitespace-pre-wrap rounded-control border border-line bg-bg p-4 text-sm leading-relaxed text-fg-muted">
        {text}
      </div>
    </Card>
  );
}

export function AcceptanceForm({
  action,
  projectId,
  orderSummaryId,
  businessLegalName,
  isTestFixture,
}: {
  action: (formData: FormData) => void | Promise<void>;
  projectId: string;
  orderSummaryId: string;
  businessLegalName: string;
  isTestFixture: boolean;
}) {
  return (
    <Card className="flex flex-col gap-5">
      {isTestFixture ? <FixtureLabel /> : null}
      <h2 className="font-display text-xl font-semibold text-fg">Accept the agreement</h2>
      <form action={action} className="flex flex-col gap-5" data-testid="acceptance-form">
        <input type="hidden" name="projectId" value={projectId} />
        <input type="hidden" name="orderSummaryId" value={orderSummaryId} />
        <input type="hidden" name="checkboxDefault" value="unchecked" />
        {/* Checkbox labels are interim UI wording; the final authority wording requires legal
            review (04 §3, DEP-03) and is not agreement text. */}
        <TextField
          label="Your full legal name"
          name="signerFullLegalName"
          required
          maxLength={200}
          autoComplete="name"
        />
        <TextField
          label="Business legal name"
          name="businessLegalName"
          required
          maxLength={200}
          hint={`As shown on the order summary: ${businessLegalName}`}
        />
        <TextField
          label="Your position or title"
          name="signerTitle"
          required
          maxLength={200}
          autoComplete="organization-title"
        />
        <label className="flex items-start gap-3 text-sm text-fg">
          <input type="checkbox" name="accepted" value="true" required className="mt-1 size-4" />
          <span>I have read and accept this agreement and the order summary above.</span>
        </label>
        <label className="flex items-start gap-3 text-sm text-fg">
          <input
            type="checkbox"
            name="authorityConfirmed"
            value="true"
            required
            className="mt-1 size-4"
          />
          <span>
            I confirm that I am authorized to accept this agreement on behalf of the business.
          </span>
        </label>
        <Button type="submit">Accept agreement</Button>
      </form>
    </Card>
  );
}
