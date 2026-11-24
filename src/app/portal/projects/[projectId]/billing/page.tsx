import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { AppShell, PageHeading } from "@/components/app/app-shell";
import {
  AcceptanceForm,
  AgreementDocument,
  OrderSummaryCard,
} from "@/components/billing/agreement-acceptance";
import { Button, ButtonLink } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/ui/notice";
import { env } from "@/config/env";
import { PACKAGES, formatUsd } from "@/domain/billing/pricing";
import { messageFor } from "@/lib/messages";
import { requireClient } from "@/server/auth/guards";
import { getBillingStatus } from "@/server/services/billing";
import { createUserClient } from "@/server/supabase/clients";

import { signOutAction } from "../../../../sign-in/actions";
import {
  acceptAgreementAction,
  beginRecoveryAction,
  requestCancellationAction,
  revokeAuthorizationAction,
  startCheckoutAction,
} from "./actions";

export const metadata: Metadata = {
  title: "Agreement and payments",
  robots: { index: false, follow: false },
};

type Props = {
  params: Promise<{ projectId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const DEPOSIT_LABELS: Record<string, string> = {
  not_started: "Not started",
  pending: "Payment processing",
  verified: "Received",
  failed: "Not completed",
  refunded: "Refunded",
  disputed: "Under dispute",
};
const BALANCE_LABELS: Record<string, string> = {
  not_due: "Not yet due",
  due: "Due (your invoice is being prepared)",
  pending: "Awaiting payment",
  verified: "Received",
  failed: "Payment not completed",
  refunded: "Refunded",
  disputed: "Under dispute",
  settled_by_adjustment: "Settled",
};

const AUTHORIZATION_LABELS: Record<string, string> = {
  none: "No card is saved for the final balance yet.",
  active: "Your card is saved for the final balance.",
  payment_method_unavailable: "Your saved card can no longer be used. Please save a new card.",
  revoked:
    "Automatic final payment is turned off. You can pay the final balance on its Stripe invoice page.",
};

/**
 * Client agreement and payment page (spec 04 §1-§3, §8, §10; 05 §2). Every state shown is
 * derived from records in the database. Returning from Stripe never changes it: the page
 * shows "Payment processing" until the signature-verified webhook is processed (T-PAY-04).
 */
export default async function ClientBillingPage({ params, searchParams }: Props) {
  const { projectId } = await params;
  const query = await searchParams;
  const ctx = await requireClient();
  const db = await createUserClient();
  const status = await getBillingStatus(db, projectId);
  if (!status) notFound();

  const [{ data: project }, { data: summary }] = await Promise.all([
    db.from("projects").select("id, name").eq("id", projectId).maybeSingle(),
    status.orderSummaryId
      ? db
          .from("order_summaries")
          .select(
            "id, revision, package_key, package_total_cents, deposit_cents, balance_cents, maintenance_monthly_cents, scope_items, business_legal_name, agreement_versions(version_label, canonical_text, is_test_fixture)",
          )
          .eq("id", status.orderSummaryId)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);
  if (!project) notFound();
  const version = summary
    ? ((Array.isArray(summary.agreement_versions)
        ? summary.agreement_versions[0]
        : summary.agreement_versions) as {
        version_label: string;
        canonical_text: string;
        is_test_fixture: boolean;
      } | null)
    : null;
  // OI-69: a fixture is presented only where the environment explicitly enables it.
  const fixtureBlocked =
    version?.is_test_fixture === true && env.AGREEMENT_TEST_FIXTURE !== "enabled";
  const notice = messageFor(query.notice);
  const error = messageFor(query.error);
  const returned = query.checkout === "returned";

  return (
    <AppShell
      email={ctx.email}
      roleLabel="Client"
      nav={[{ href: "/portal", label: "Projects" }]}
      signOutAction={signOutAction}
    >
      <PageHeading title={project.name} intro="Agreement and payments" />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      {returned && status.depositState !== "verified" ? (
        <Notice>
          Payment processing. We will confirm your payment as soon as Stripe notifies us. You do not
          need to pay again.
        </Notice>
      ) : null}

      {summary && version && !fixtureBlocked ? (
        <>
          <OrderSummaryCard
            summary={{
              id: summary.id,
              revision: summary.revision,
              packageName:
                PACKAGES.find((p) => p.key === summary.package_key)?.name ?? summary.package_key,
              totalCents: summary.package_total_cents,
              depositCents: summary.deposit_cents,
              balanceCents: summary.balance_cents,
              maintenanceMonthlyCents: summary.maintenance_monthly_cents,
              scopeItems: Array.isArray(summary.scope_items)
                ? (summary.scope_items as string[])
                : [],
              businessLegalName: summary.business_legal_name,
            }}
          />
          <AgreementDocument
            versionLabel={version.version_label}
            text={version.canonical_text}
            isTestFixture={version.is_test_fixture}
          />
          {status.agreementState === "presented" ||
          status.agreementState === "reacceptance_required" ? (
            <AcceptanceForm
              action={acceptAgreementAction}
              projectId={projectId}
              orderSummaryId={summary.id}
              businessLegalName={summary.business_legal_name}
              isTestFixture={version.is_test_fixture}
            />
          ) : null}
        </>
      ) : (
        <Card>
          <p className="text-fg-muted">
            Your order summary is not ready yet. Spotlight Marketing will let you know.
          </p>
        </Card>
      )}

      <Card className="flex flex-col gap-4" data-testid="payment-status">
        <h2 className="font-display text-xl font-semibold text-fg">Payments</h2>
        <dl className="grid gap-2 text-sm sm:grid-cols-[1fr_auto]">
          <dt className="text-fg-muted">Deposit and first maintenance payment</dt>
          <dd className="font-medium text-fg sm:text-right">
            {DEPOSIT_LABELS[status.depositState] ?? "Unknown"}
          </dd>
          <dt className="text-fg-muted">Final balance</dt>
          <dd className="font-medium text-fg sm:text-right">
            {BALANCE_LABELS[status.finalBalanceState] ?? "Unknown"}
          </dd>
        </dl>
        {status.agreementState === "accepted_pending_payment" &&
        status.depositState !== "pending" ? (
          <form action={startCheckoutAction}>
            <input type="hidden" name="projectId" value={projectId} />
            <Button type="submit">
              Pay {formatUsd((status.depositCents ?? 0) + (status.maintenanceMonthlyCents ?? 0))}{" "}
              securely with Stripe
            </Button>
          </form>
        ) : null}
        {status.checkoutUrl && status.depositState === "pending" && !returned ? (
          <ButtonLink href={status.checkoutUrl as never} variant="secondary">
            Continue to secure payment
          </ButtonLink>
        ) : null}
        {status.finalInvoiceUrl && status.finalInvoiceAmountCents !== null ? (
          <ButtonLink href={status.finalInvoiceUrl as never}>
            Pay the final balance of {formatUsd(status.finalInvoiceAmountCents)} on Stripe
          </ButtonLink>
        ) : null}
        {status.billingHoldActive ? (
          <Notice tone="danger">
            A maintenance payment is overdue. Your website stays online, and you can pay the open
            invoice from your Stripe email.
          </Notice>
        ) : null}
      </Card>

      {status.depositState === "verified" || status.paymentAuthorizationState !== "none" ? (
        <Card className="flex flex-col gap-3" data-testid="payment-authorization">
          <h2 className="font-display text-lg font-semibold text-fg">Final payment card</h2>
          <p className="text-sm text-fg" data-state={status.paymentAuthorizationState}>
            {AUTHORIZATION_LABELS[status.paymentAuthorizationState] ?? "Unknown"}
          </p>
          {status.recoveryUrl ? (
            <ButtonLink href={status.recoveryUrl as never} variant="secondary">
              Continue to the secure card page
            </ButtonLink>
          ) : status.paymentAuthorizationState === "none" ||
            status.paymentAuthorizationState === "payment_method_unavailable" ? (
            <form action={beginRecoveryAction}>
              <input type="hidden" name="projectId" value={projectId} />
              <Button type="submit">Save a card securely with Stripe</Button>
            </form>
          ) : null}
          {status.paymentAuthorizationState !== "revoked" &&
          status.paymentAuthorizationState !== "none" &&
          status.isAuthorizationSigner ? (
            <form action={revokeAuthorizationAction} className="flex flex-col gap-2">
              <input type="hidden" name="projectId" value={projectId} />
              <label className="text-sm text-fg-muted" htmlFor="revoke-reason">
                Reason for turning off automatic final payment
              </label>
              <textarea
                id="revoke-reason"
                name="reason"
                required
                maxLength={1000}
                className="rounded-control border border-line-strong bg-surface p-3 text-fg"
              />
              <Button type="submit" variant="secondary">
                Turn off automatic final payment
              </Button>
            </form>
          ) : null}
        </Card>
      ) : null}

      {status.agreementState === "effective" ? (
        <Card className="flex flex-col gap-3">
          <h2 className="font-display text-lg font-semibold text-fg">
            Cancel Website Care & Maintenance
          </h2>
          <p className="text-sm text-fg-muted">
            Submitting a request records it; Spotlight Marketing confirms the effective date with
            you.
          </p>
          <form action={requestCancellationAction}>
            <input type="hidden" name="projectId" value={projectId} />
            <Button type="submit" variant="secondary">
              Request cancellation
            </Button>
          </form>
        </Card>
      ) : null}
    </AppShell>
  );
}
