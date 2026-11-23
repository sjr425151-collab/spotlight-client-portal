import type { Metadata } from "next";
import Link from "next/link";

import { PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { messageFor } from "@/lib/messages";
import { requireStaff } from "@/server/auth/guards";
import { createUserClient } from "@/server/supabase/clients";

import { createProjectAction } from "./actions";
import { StaffShell } from "./staff-shell";

export const metadata: Metadata = { title: "Staff", robots: { index: false, follow: false } };

type Search = Promise<Record<string, string | string[] | undefined>>;

export default async function StaffHomePage({ searchParams }: { searchParams: Search }) {
  const params = await searchParams;
  const ctx = await requireStaff();
  const { data: projects } = await (
    await createUserClient()
  )
    .from("projects")
    .select("id, name, archived_at, client_businesses(display_name)")
    .order("created_at", { ascending: false });
  const notice = messageFor(params.notice);
  const error = messageFor(params.error);

  return (
    <StaffShell ctx={ctx}>
      <PageHeading title="Projects" intro="Client businesses and their website projects." />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}
      <ul className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3" data-testid="project-list">
        {(projects ?? []).map((project) => (
          <li key={project.id}>
            <Link href={`/staff/projects/${project.id}`} className="block rounded-card">
              <Card className="p-6 hover:border-line-strong sm:p-6">
                <h2 className="font-display text-lg font-semibold text-fg">{project.name}</h2>
                <p className="mt-1 text-sm text-fg-muted">
                  {displayName(project.client_businesses)}
                  {project.archived_at ? " · Archived" : ""}
                </p>
              </Card>
            </Link>
          </li>
        ))}
      </ul>
      <section aria-labelledby="new-project-heading">
        <Card className="max-w-xl">
          <h2 id="new-project-heading" className="font-display text-lg font-semibold text-fg">
            New client project
          </h2>
          <form action={createProjectAction} className="mt-5 flex flex-col gap-5">
            <TextField label="Business legal name" name="legalName" required maxLength={200} />
            <TextField
              label="Business display name"
              name="displayName"
              maxLength={200}
              hint="Defaults to the legal name."
            />
            <TextField label="Project name" name="projectName" required maxLength={200} />
            <Button type="submit">Create project</Button>
          </form>
        </Card>
      </section>
    </StaffShell>
  );
}

function displayName(value: unknown): string {
  const row = Array.isArray(value) ? value[0] : value;
  return row && typeof row === "object" && "display_name" in row ? String(row.display_name) : "";
}
