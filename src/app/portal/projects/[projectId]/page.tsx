import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { AppShell, PageHeading } from "@/components/app/app-shell";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { Notice } from "@/components/ui/notice";
import { INTAKE_FIELDS } from "@/domain/intake";
import {
  INTAKE_STATE_LABELS,
  PUBLICATION_STATE_LABELS,
  R1_APPROVAL_LABEL,
} from "@/domain/publication";
import { CATEGORY_RULES, REJECTION_GUIDANCE } from "@/domain/uploads";
import { messageFor } from "@/lib/messages";
import { requireClient, requireProjectAccess } from "@/server/auth/guards";
import { callRpc } from "@/server/services/fulfillment";
import { createUserClient } from "@/server/supabase/clients";

import { signOutAction } from "../../../sign-in/actions";
import {
  approvePreviewAction,
  requestRevisionsAction,
  requestUploadExceptionAction,
  saveIntakeDraftAction,
} from "./actions";

export const metadata: Metadata = { title: "Project", robots: { index: false, follow: false } };

type Props = {
  params: Promise<{ projectId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

const inputClass =
  "rounded-control border border-line-strong bg-surface px-3.5 py-2.5 text-base text-fg sm:text-sm";

/**
 * Client project page (R1 acceptance item 11): every status shown is derived from
 * authoritative records by the database (`project_status`); nothing here decides anything.
 */
export default async function ClientProjectPage({ params, searchParams }: Props) {
  const { projectId } = await params;
  const query = await searchParams;
  const ctx = await requireClient();
  await requireProjectAccess(projectId);
  const db = await createUserClient();

  const [status, { data: project }, { data: draftRows }, { data: uploads }, { data: reviews }] =
    await Promise.all([
      callRpc(db, "project_status", { p_project_id: projectId }),
      db.from("projects").select("id, name").eq("id", projectId).maybeSingle(),
      db
        .from("intake_submissions")
        .select("id, version, status, content")
        .eq("project_id", projectId)
        .order("version", { ascending: false })
        .limit(1),
      db
        .from("asset_uploads")
        .select(
          "id, asset_id, version, category, original_name, status, rejection_code, created_at",
        )
        .eq("project_id", projectId)
        .not("status", "in", "(uploading,failed_upload)")
        .order("created_at", { ascending: false }),
      db
        .from("intake_reviews")
        .select("decision, note, reviewed_at")
        .eq("project_id", projectId)
        .order("reviewed_at", { ascending: false })
        .limit(1),
    ]);
  if (!project || !status.ok) notFound();
  const s = status.data as {
    intake_state: string;
    current_release: null | {
      id: string;
      release_number: number;
      preview_url: string;
      released_at: string;
      approved: boolean;
    };
    approval_hold: string | null;
    publication_state: string;
  };
  const latest = draftRows?.[0];
  const content = (latest?.content ?? {}) as Record<string, unknown>;
  const editable = s.intake_state === "open" || s.intake_state === "changes_requested";
  const lastReview = reviews?.[0];
  const notice = messageFor(query.notice);
  const error = messageFor(query.error);

  return (
    <AppShell
      email={ctx.email}
      roleLabel="Client"
      nav={[{ href: "/portal", label: "Projects" }]}
      signOutAction={signOutAction}
    >
      <PageHeading title={project.name} intro="Your project status and next steps." />
      {notice ? <Notice tone="success">{notice}</Notice> : null}
      {error ? <Notice tone="danger">{error}</Notice> : null}

      <section aria-labelledby="status-heading">
        <h2 id="status-heading" className="font-display text-xl font-semibold text-fg">
          Status
        </h2>
        <dl className="mt-4 grid gap-4 sm:grid-cols-3" data-testid="project-status">
          <Card className="p-5 sm:p-5">
            <dt className="text-sm text-fg-muted">Project information</dt>
            <dd className="mt-1 font-medium text-fg">{INTAKE_STATE_LABELS[s.intake_state]}</dd>
          </Card>
          <Card className="p-5 sm:p-5">
            <dt className="text-sm text-fg-muted">Website preview</dt>
            <dd className="mt-1 font-medium text-fg">
              {s.approval_hold ??
                (s.current_release
                  ? s.current_release.approved
                    ? `Version ${s.current_release.release_number} approved`
                    : `Version ${s.current_release.release_number} ready for your review`
                  : "Not released yet")}
            </dd>
          </Card>
          <Card className="p-5 sm:p-5">
            <dt className="text-sm text-fg-muted">Publication</dt>
            <dd className="mt-1 font-medium text-fg">
              {PUBLICATION_STATE_LABELS[s.publication_state]}
            </dd>
          </Card>
        </dl>
      </section>

      {s.current_release && !s.current_release.approved ? (
        <section aria-labelledby="preview-heading" className="flex flex-col gap-4">
          <h2 id="preview-heading" className="font-display text-xl font-semibold text-fg">
            Review your website preview
          </h2>
          <Card className="flex flex-col gap-4">
            <p className="text-fg-muted">
              Version {s.current_release.release_number} is ready.{" "}
              <a
                className="text-accent underline"
                href={s.current_release.preview_url}
                rel="noreferrer noopener"
                target="_blank"
              >
                Open the preview
              </a>
              . Your approval applies to this version only. Nothing is approved until you choose to
              approve it.
            </p>
            <p className="text-sm text-fg-muted" data-testid="final-balance-disclosure">
              After you approve, your final balance from your order summary becomes due, and you
              will be shown a secure Stripe page to pay it.
            </p>
            <form action={approvePreviewAction} className="flex flex-col gap-3">
              <input type="hidden" name="projectId" value={projectId} />
              <input type="hidden" name="releaseId" value={s.current_release.id} />
              <label className="flex flex-col gap-2 text-sm font-medium text-fg">
                Comment (optional)
                <textarea name="comment" maxLength={2000} rows={2} className={inputClass} />
              </label>
              <label className="flex items-start gap-2 text-sm text-fg">
                <input type="checkbox" name="confirm" value="yes" required />I have reviewed version{" "}
                {s.current_release.release_number} and approve it.
              </label>
              <Button type="submit">{R1_APPROVAL_LABEL}</Button>
            </form>
            <form action={requestRevisionsAction} className="flex flex-col gap-3">
              <input type="hidden" name="projectId" value={projectId} />
              <input type="hidden" name="releaseId" value={s.current_release.id} />
              <label className="flex flex-col gap-2 text-sm font-medium text-fg">
                What should change?
                <textarea
                  name="comments"
                  required
                  maxLength={4000}
                  rows={3}
                  className={inputClass}
                />
              </label>
              <Button type="submit" variant="secondary">
                Request revisions
              </Button>
            </form>
          </Card>
        </section>
      ) : null}

      <section aria-labelledby="intake-heading" className="flex flex-col gap-4">
        <h2 id="intake-heading" className="font-display text-xl font-semibold text-fg">
          Project information
        </h2>
        {s.intake_state === "locked" ? (
          <p className="text-fg-muted">{INTAKE_STATE_LABELS.locked}.</p>
        ) : null}
        {s.intake_state === "changes_requested" && lastReview?.note ? (
          <Notice>Changes requested: {lastReview.note}</Notice>
        ) : null}
        {editable ? (
          <Card>
            <form action={saveIntakeDraftAction} className="flex flex-col gap-5">
              <input type="hidden" name="projectId" value={projectId} />
              {INTAKE_FIELDS.map((field) => {
                const value = content[field.key];
                const text = Array.isArray(value)
                  ? value.join("\n")
                  : typeof value === "string"
                    ? value
                    : "";
                if (field.kind === "text") {
                  return (
                    <TextField
                      key={field.key}
                      label={field.label}
                      name={field.key}
                      defaultValue={text}
                      {...(field.hint ? { hint: field.hint } : {})}
                      maxLength={2000}
                      required={false}
                    />
                  );
                }
                if (field.kind === "choice") {
                  return (
                    <label
                      key={field.key}
                      className="flex flex-col gap-2 text-sm font-medium text-fg"
                    >
                      {field.label}
                      <select name={field.key} defaultValue={text} className={inputClass}>
                        <option value="">Choose…</option>
                        {field.choices?.map((c) => (
                          <option key={c.value} value={c.value}>
                            {c.label}
                          </option>
                        ))}
                      </select>
                    </label>
                  );
                }
                return (
                  <label
                    key={field.key}
                    className="flex flex-col gap-2 text-sm font-medium text-fg"
                  >
                    {field.label}
                    {field.hint ? (
                      <span className="font-normal text-fg-subtle">{field.hint}</span>
                    ) : null}
                    <textarea
                      name={field.key}
                      defaultValue={text}
                      rows={3}
                      maxLength={field.kind === "list" ? 15000 : 2000}
                      className={inputClass}
                    />
                  </label>
                );
              })}
              <div className="flex flex-wrap gap-3">
                <Button type="submit" name="intent" value="save" variant="secondary">
                  Save and finish later
                </Button>
                <Button type="submit" name="intent" value="submit">
                  Submit for review
                </Button>
              </div>
            </form>
          </Card>
        ) : null}
      </section>

      {s.intake_state !== "locked" ? (
        <section aria-labelledby="uploads-heading" className="flex flex-col gap-4">
          <h2 id="uploads-heading" className="font-display text-xl font-semibold text-fg">
            Files
          </h2>
          <p className="text-sm text-fg-muted">
            Files stay private. Each file is checked and scanned before anyone can use it.
          </p>
          <Card>
            <form
              action={`/portal/projects/${projectId}/uploads`}
              method="post"
              encType="multipart/form-data"
              className="flex flex-col gap-4"
            >
              <label className="flex flex-col gap-2 text-sm font-medium text-fg">
                Category
                <select name="category" required className={inputClass}>
                  {Object.entries(CATEGORY_RULES).map(([key, rule]) => (
                    <option key={key} value={key}>
                      {rule.label} (up to {rule.maxBytes / 1_000_000} MB)
                    </option>
                  ))}
                  <option value="other">Other (approved type only)</option>
                </select>
              </label>
              <label className="flex flex-col gap-2 text-sm font-medium text-fg">
                File
                <input type="file" name="file" required className="text-sm" />
              </label>
              <Button type="submit">Upload</Button>
            </form>
          </Card>
          <ul className="flex flex-col gap-2" data-testid="upload-list">
            {(uploads ?? []).map((u) => (
              <li key={u.id}>
                <Card className="flex flex-wrap items-center justify-between gap-3 p-4 sm:p-4">
                  <div>
                    <p className="font-medium text-fg">{u.original_name}</p>
                    <p className="text-sm text-fg-muted">
                      {u.status === "available"
                        ? "Ready"
                        : u.status === "rejected"
                          ? "Rejected"
                          : "Being checked"}
                      {u.version > 1 ? ` · version ${u.version}` : ""}
                    </p>
                    {u.status === "rejected" && u.rejection_code ? (
                      <p className="text-sm text-danger">
                        {REJECTION_GUIDANCE[u.rejection_code] ?? REJECTION_GUIDANCE.content_invalid}
                      </p>
                    ) : null}
                  </div>
                  {u.status === "available" ? (
                    <Link
                      className="text-sm text-accent underline"
                      href={`/portal/projects/${projectId}/assets/${u.id}`}
                      prefetch={false}
                    >
                      Download
                    </Link>
                  ) : null}
                </Card>
              </li>
            ))}
          </ul>
          <details>
            <summary className="cursor-pointer text-sm text-fg-muted">
              Need a different file type?
            </summary>
            <form action={requestUploadExceptionAction} className="mt-3 flex flex-col gap-3">
              <input type="hidden" name="projectId" value={projectId} />
              <TextField
                label="File type (MIME)"
                name="mime"
                required
                maxLength={100}
                hint="For example font/woff2"
              />
              <TextField label="Why is it needed?" name="justification" required maxLength={1000} />
              <Button type="submit" variant="secondary">
                Request approval
              </Button>
            </form>
          </details>
        </section>
      ) : null}
    </AppShell>
  );
}
