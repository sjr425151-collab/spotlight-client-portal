import type { Metadata } from "next";
import Link from "next/link";

import { PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { requireSales } from "@/server/auth/guards";
import { listCustomers } from "@/server/services/sales";
import { createUserClient } from "@/server/supabase/clients";

import { createCustomerAction } from "./actions";
import { SalesShell } from "./sales-shell";

export const metadata: Metadata = { title: "Customers", robots: { index: false, follow: false } };

type Search = Promise<Record<string, string | string[] | undefined>>;

/** The representative's own customers: active assignments only (OI-78). */
export default async function SalesHomePage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireSales();
  const result = await listCustomers(await createUserClient());
  const customers = result.ok ? result.customers : [];
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  return (
    <SalesShell ctx={ctx}>
      <PageHeading
        title="Your customers"
        intro="Customers and projects assigned to you. Pricing and the standard package scope come from the approved catalog."
      />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}

      {/* OI-95: the empty-state message is outside the list, and the list is rendered only with
          items; the container keeps data-testid="sales-customers" in both states. */}
      <div data-testid="sales-customers">
        {customers.length === 0 ? (
          <p className="text-fg-muted">No assigned customers yet.</p>
        ) : (
          <ul className="flex flex-col gap-3">
            {customers.map((c) => (
              <li key={c.project_id}>
                <Card className="flex flex-wrap items-center justify-between gap-4 p-5 sm:p-5">
                  <div>
                    <p className="font-medium text-fg">{c.business_display_name}</p>
                    <p className="text-sm text-fg-muted">{c.project_name}</p>
                  </div>
                  <Link
                    href={`/sales/projects/${c.project_id}`}
                    className="rounded-control px-3 py-2 text-sm text-fg underline-offset-4 hover:underline"
                  >
                    Open {c.project_name}
                  </Link>
                </Card>
              </li>
            ))}
          </ul>
        )}
      </div>

      <Card className="max-w-xl">
        <h2 className="font-display text-xl font-semibold text-fg">New customer</h2>
        <p className="mt-2 text-sm text-fg-muted">
          Creates the business and its project, and assigns the project to you.
        </p>
        <form action={createCustomerAction} className="mt-5 flex flex-col gap-5">
          <TextField label="Business legal name" name="legalName" required maxLength={200} />
          <TextField label="Display name" name="displayName" maxLength={200} />
          <TextField label="Project name" name="projectName" required maxLength={200} />
          <Button type="submit">Create customer</Button>
        </form>
      </Card>
    </SalesShell>
  );
}
