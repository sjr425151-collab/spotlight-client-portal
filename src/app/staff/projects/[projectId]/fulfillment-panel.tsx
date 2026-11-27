import type { ReactNode } from "react";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { TextField } from "@/components/ui/field";
import { INTAKE_FIELDS } from "@/domain/intake";
import { GATE_LABELS, INTAKE_STATE_LABELS, parseGateResult } from "@/domain/publication";
import type { StaffContext } from "@/server/auth/guards";
import { callRpc } from "@/server/services/fulfillment";
import { createUserClient } from "@/server/supabase/clients";

import * as act from "./fulfillment-actions";

const inputClass =
  "rounded-control border border-line-strong bg-surface px-3.5 py-2.5 text-base text-fg sm:text-sm";
const QA_AREAS = [
  "functional",
  "responsive",
  "branding_content",
  "performance",
  "accessibility",
  "security",
  "domain_operational",
  "monitoring_rollback",
];
const SECURITY_KEYS = [
  "https_hsts",
  "security_headers",
  "no_exposed_secrets",
  "dependency_scan",
  "form_abuse_protection",
  "no_debug_endpoints",
  "admin_surfaces_protected",
];

function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={`${id}-heading`} className="flex flex-col gap-4">
      <h2 id={`${id}-heading`} className="font-display text-xl font-semibold text-fg">
        {title}
      </h2>
      {children}
    </section>
  );
}

function Hidden({ projectId, extra = {} }: { projectId: string; extra?: Record<string, string> }) {
  return (
    <>
      <input type="hidden" name="projectId" value={projectId} />
      {Object.entries(extra).map(([k, v]) => (
        <input key={k} type="hidden" name={k} value={v} />
      ))}
    </>
  );
}

function Area({ name, label, required }: { name: string; label: string; required?: boolean }) {
  return (
    <label className="flex flex-col gap-2 text-sm font-medium text-fg">
      {label}
      <textarea name={name} rows={2} maxLength={2000} required={required} className={inputClass} />
    </label>
  );
}

function PassFail({ name, label }: { name: string; label: string }) {
  return (
    <label className="flex items-center justify-between gap-3 text-sm text-fg">
      {label}
      <select name={name} defaultValue="fail" className={inputClass}>
        <option value="pass">Pass</option>
        <option value="fail">Fail</option>
        <option value="not_applicable">Not applicable</option>
      </select>
    </label>
  );
}

/**
 * Staff fulfillment and publication controls (05, 06). Everything shown is read through RLS
 * and the database's derived state; every button calls a server action that the database
 * re-authorizes. The gate list is the database evaluator's own result (Admin sees derived
 * states only, OI-72). There is no control that passes or skips a gate.
 */
export async function FulfillmentPanel({
  projectId,
  ctx,
}: {
  projectId: string;
  ctx: StaffContext;
}) {
  const db = await createUserClient();
  const isOwner = ctx.staffRole === "owner";
  const [
    status,
    report,
    submissions,
    uploads,
    exceptions,
    releases,
    outreach,
    holds,
    revisions,
    authorizations,
    deployments,
    incidents,
    target,
    deletions,
  ] = await Promise.all([
    callRpc(db, "project_status", { p_project_id: projectId }),
    callRpc(db, "publication_gate_report", { p_project_id: projectId }),
    db
      .from("intake_submissions")
      .select("id, version, status, source, submitted_at, content")
      .eq("project_id", projectId)
      .order("version", { ascending: false })
      .limit(5),
    db
      .from("asset_uploads")
      .select("id, original_name, category, status, rejection_code, processing_note, used")
      .eq("project_id", projectId)
      .order("created_at", { ascending: false })
      .limit(50),
    db
      .from("upload_exceptions")
      .select("id, kind, requested_mime, justification")
      .eq("project_id", projectId)
      .eq("status", "requested"),
    db
      .from("preview_releases")
      .select("id, release_number, commit_sha, preview_url, released_at, withdrawn_at")
      .eq("project_id", projectId)
      .order("release_number", { ascending: false })
      .limit(5),
    db
      .from("approval_outreach_records")
      .select("id, release_id, kind, channel, occurred_on")
      .eq("project_id", projectId)
      .order("occurred_on", { ascending: false })
      .limit(20),
    db
      .from("approval_holds")
      .select("id, placed_at, reason, cleared_at")
      .eq("project_id", projectId)
      .order("placed_at", { ascending: false })
      .limit(3),
    db
      .from("preview_revision_requests")
      .select("id, release_id, comments, requested_at, revision_classifications(scope)")
      .eq("project_id", projectId)
      .order("requested_at", { ascending: false })
      .limit(10),
    db
      .from("publication_authorizations")
      .select("id, release_id, authorized_at, invalidated_at, invalidated_reason")
      .eq("project_id", projectId)
      .order("authorized_at", { ascending: false })
      .limit(5),
    db
      .from("publication_deployments")
      .select(
        "id, authorization_id, release_id, commit_sha, target_ref, outcome, production_url, started_at",
      )
      .eq("project_id", projectId)
      .order("seq", { ascending: false })
      .limit(5),
    db
      .from("publication_incidents")
      .select("id, kind, severity, summary, opened_at")
      .eq("project_id", projectId)
      .is("resolved_at", null),
    db.from("client_site_targets").select("target_ref").eq("project_id", projectId).maybeSingle(),
    db
      .from("asset_object_deletions")
      .select("id, upload_id, status, attempts, last_error, next_attempt_at")
      .eq("project_id", projectId)
      .neq("status", "deleted")
      .order("created_at", { ascending: false })
      .limit(20),
  ]);

  const intakeState = status.ok ? String(status.data.intake_state) : "locked";
  const latestSubmitted = (submissions.data ?? []).find((s) => s.status === "submitted");
  const current = (releases.data ?? [])[0];
  const currentReleaseId = current && !current.withdrawn_at ? current.id : null;
  const gates = parseGateResult(report.ok ? report.data.result : null);
  const activeHold = (holds.data ?? []).find((h) => !h.cleared_at);
  const activeAuth = (authorizations.data ?? []).find((a) => !a.invalidated_at);
  // AUTH-015 (OI-114): the latest deployment (highest seq first) of the current release, under the
  // active authorization, after a failed deployment or a failed live verification. The database
  // re-checks every condition.
  const latestDeployment = (deployments.data ?? [])[0];
  const recoverable =
    isOwner &&
    status.ok &&
    status.data.publication_state === "failed" &&
    latestDeployment !== undefined &&
    latestDeployment.release_id === currentReleaseId &&
    activeAuth?.id === latestDeployment.authorization_id;
  const available = (uploads.data ?? []).filter((u) => u.status === "available");

  return (
    <>
      <Section id="gates" title="Publication gates">
        <Card>
          <ul className="flex flex-col gap-2" data-testid="gate-list">
            {gates.gates.map((g) => (
              <li key={g.gate} className="flex justify-between gap-3 text-sm">
                <span className="text-fg">
                  {g.gate} · {GATE_LABELS[g.gate]}
                </span>
                <span className={g.passed ? "text-success" : "text-danger"}>
                  {g.passed
                    ? "Passes"
                    : `Blocked${g.reason ? ` (${g.reason.replaceAll("_", " ")})` : ""}`}
                </span>
              </li>
            ))}
          </ul>
          <p className="mt-3 text-sm text-fg-muted">
            {gates.eligible
              ? "Every gate passes for the current release."
              : "Publication is not eligible."}
          </p>
        </Card>
      </Section>

      <Section id="intake" title={`Intake: ${INTAKE_STATE_LABELS[intakeState] ?? intakeState}`}>
        {latestSubmitted ? (
          <details>
            <summary className="cursor-pointer text-sm text-fg-muted">
              Correct intake on the client&apos;s behalf (creates version{" "}
              {latestSubmitted.version + 1})
            </summary>
            <form action={act.correctIntakeAction} className="mt-3 flex flex-col gap-3">
              <Hidden projectId={projectId} />
              {INTAKE_FIELDS.map((field) => {
                const value = (latestSubmitted.content as Record<string, unknown>)[field.key];
                return (
                  <label
                    key={field.key}
                    className="flex flex-col gap-2 text-sm font-medium text-fg"
                  >
                    {field.label}
                    <textarea
                      name={field.key}
                      rows={field.kind === "list" || field.kind === "textarea" ? 3 : 1}
                      defaultValue={
                        Array.isArray(value)
                          ? value.join("\n")
                          : typeof value === "string"
                            ? value
                            : ""
                      }
                      className={inputClass}
                    />
                  </label>
                );
              })}
              <TextField
                label="Reason for the correction (required, audited)"
                name="reason"
                required
                maxLength={1000}
              />
              <Button type="submit" variant="secondary">
                Save correction as a new version
              </Button>
            </form>
          </details>
        ) : null}
        {intakeState === "submitted" && latestSubmitted ? (
          <Card>
            <form action={act.reviewIntakeAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ submissionId: latestSubmitted.id }} />
              <p className="text-sm text-fg-muted">
                Version {latestSubmitted.version} ({latestSubmitted.source.replace("_", " ")}).
              </p>
              <Area name="note" label="Note to the client (required to request changes)" />
              <div className="flex gap-3">
                <Button type="submit" name="decision" value="accepted">
                  Accept intake
                </Button>
                <Button type="submit" name="decision" value="changes_requested" variant="secondary">
                  Request changes
                </Button>
              </div>
            </form>
          </Card>
        ) : null}
      </Section>

      <Section id="uploads" title="Uploads">
        <ul className="flex flex-col gap-2 text-sm">
          {(uploads.data ?? []).map((u) => (
            <li key={u.id} className="text-fg">
              {u.original_name} · {u.category.replace("_", " ")} · {u.status}
              {u.rejection_code ? ` (${u.rejection_code})` : ""}
              {u.processing_note ? ` (${u.processing_note})` : ""}
              {u.used ? " · used" : ""}
              {u.status === "quarantined" ? (
                <form action={act.retryScanAction} className="ml-2 inline">
                  <Hidden projectId={projectId} extra={{ uploadId: u.id }} />
                  <Button type="submit" variant="ghost" className="h-8 px-2">
                    Retry scan
                  </Button>
                </form>
              ) : null}
            </li>
          ))}
        </ul>
        {(deletions.data ?? []).length > 0 ? (
          <div className="flex flex-col gap-2">
            <h3 className="text-sm font-medium text-fg">Revoked files awaiting deletion</h3>
            <ul className="flex flex-col gap-2 text-sm" data-testid="pending-deletions">
              {(deletions.data ?? []).map((d) => (
                <li key={d.id} className="text-fg">
                  Upload {String(d.upload_id).slice(0, 8)} · {d.status} · {d.attempts} attempt
                  {d.attempts === 1 ? "" : "s"}
                  {d.last_error ? ` (${d.last_error})` : ""}
                  {isOwner ? (
                    <form action={act.retryDeletionAction} className="ml-2 inline">
                      <Hidden projectId={projectId} extra={{ deletionId: d.id }} />
                      <Button type="submit" variant="ghost" className="h-8 px-2">
                        Retry deletion
                      </Button>
                    </form>
                  ) : null}
                </li>
              ))}
            </ul>
          </div>
        ) : null}
        {(exceptions.data ?? []).map((e) => (
          <Card key={e.id}>
            <form action={act.decideUploadExceptionAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ exceptionId: e.id }} />
              <p className="text-sm text-fg">
                Requested type {e.requested_mime}: {e.justification}
              </p>
              <TextField label="Reason" name="reason" required maxLength={1000} />
              <div className="flex gap-3">
                <Button type="submit" name="decision" value="approve">
                  Approve
                </Button>
                <Button type="submit" name="decision" value="deny" variant="secondary">
                  Deny
                </Button>
              </div>
            </form>
          </Card>
        ))}
      </Section>

      <Section id="releases" title="Preview releases">
        <ul className="flex flex-col gap-2 text-sm">
          {(releases.data ?? []).map((r) => (
            <li key={r.id} className="text-fg">
              Release {r.release_number} · {r.commit_sha.slice(0, 12)} ·{" "}
              {r.withdrawn_at ? "withdrawn" : r.id === currentReleaseId ? "current" : "superseded"}
            </li>
          ))}
        </ul>
        <Card>
          <form action={act.releasePreviewAction} className="flex flex-col gap-3">
            <Hidden projectId={projectId} />
            <TextField
              label="Commit SHA (40 characters)"
              name="commitSha"
              required
              pattern="[0-9a-f]{40}"
            />
            <TextField label="Deployment ID" name="deploymentId" required maxLength={100} />
            <TextField label="Protected preview URL" name="previewUrl" type="url" required />
            <fieldset className="flex flex-col gap-1 text-sm">
              <legend className="font-medium text-fg">
                Assets incorporated (scanned and available only)
              </legend>
              {available.map((u) => (
                <label key={u.id} className="flex gap-2">
                  <input type="checkbox" name="assetIds" value={u.id} />
                  {u.original_name}
                </label>
              ))}
            </fieldset>
            <Area name="note" label="Release note" />
            <Button type="submit">Release preview to client</Button>
          </form>
        </Card>
        {currentReleaseId ? (
          <Card>
            <form action={act.withdrawPreviewAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ releaseId: currentReleaseId }} />
              <TextField label="Withdrawal reason" name="reason" required maxLength={1000} />
              <Button type="submit" variant="secondary">
                Withdraw current release
              </Button>
            </form>
          </Card>
        ) : null}
        {(revisions.data ?? []).map((q) => (
          <Card key={q.id} className="p-4 sm:p-4">
            <p className="text-sm text-fg">Revision request: {q.comments}</p>
            {Array.isArray(q.revision_classifications) &&
            q.revision_classifications.length === 0 ? (
              <form action={act.classifyRevisionAction} className="mt-2 flex gap-2">
                <Hidden projectId={projectId} extra={{ revisionRequestId: q.id }} />
                <Button
                  type="submit"
                  name="scope"
                  value="in_scope"
                  variant="secondary"
                  className="h-9 px-3"
                >
                  In scope
                </Button>
                <Button
                  type="submit"
                  name="scope"
                  value="out_of_scope"
                  variant="secondary"
                  className="h-9 px-3"
                >
                  Out of scope
                </Button>
              </form>
            ) : null}
          </Card>
        ))}
      </Section>

      {currentReleaseId ? (
        <Section id="outreach" title="Approval outreach and hold">
          <ul className="text-sm text-fg">
            {(outreach.data ?? [])
              .filter((o) => o.release_id === currentReleaseId)
              .map((o) => (
                <li key={o.id}>
                  {o.kind.replaceAll("_", " ")} · {o.channel} · {o.occurred_on}
                </li>
              ))}
          </ul>
          <Card>
            <form action={act.recordOutreachAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ releaseId: currentReleaseId }} />
              <label className="flex flex-col gap-2 text-sm font-medium text-fg">
                Outreach
                <select name="kind" className={inputClass}>
                  <option value="reminder_1">Day 3 reminder</option>
                  <option value="reminder_2">Day 7 reminder</option>
                  <option value="admin_notified">Day 7 Admin notification</option>
                  <option value="personal_followup">Day 14 personal follow-up</option>
                </select>
              </label>
              <label className="flex flex-col gap-2 text-sm font-medium text-fg">
                Channel
                <select name="channel" className={inputClass}>
                  {["email", "phone", "sms", "video_call", "in_person", "portal", "other"].map(
                    (c) => (
                      <option key={c} value={c}>
                        {c.replace("_", " ")}
                      </option>
                    ),
                  )}
                </select>
              </label>
              <TextField label="Date (America/Detroit)" name="occurredOn" type="date" required />
              <Area name="summary" label="Summary" required />
              <Button type="submit" variant="secondary">
                Record outreach
              </Button>
            </form>
          </Card>
          {activeHold ? (
            <Card className="flex flex-col gap-3">
              <p className="text-sm text-fg">
                Approval hold active since{" "}
                {new Date(activeHold.placed_at).toLocaleDateString("en-US")}: {activeHold.reason}
              </p>
              <form action={act.clearApprovalHoldAction} className="flex flex-col gap-3">
                <Hidden projectId={projectId} extra={{ holdId: activeHold.id }} />
                <TextField label="Reason for clearing" name="reason" required maxLength={1000} />
                <Button type="submit" variant="secondary">
                  Clear hold
                </Button>
              </form>
              <form action={act.recordHoldResumptionAction} className="flex gap-2">
                <Hidden projectId={projectId} extra={{ holdId: activeHold.id }} />
                <select name="decision" className={inputClass} aria-label="Resumption decision">
                  <option value="resume_development">Resume development</option>
                  <option value="proceed_to_final_payment">Proceed to final payment</option>
                  <option value="remain_held">Remain held</option>
                </select>
                <Button type="submit" variant="secondary">
                  Record decision
                </Button>
              </form>
            </Card>
          ) : (
            <Card>
              <form action={act.placeApprovalHoldAction} className="flex flex-col gap-3">
                <Hidden projectId={projectId} />
                <TextField
                  label="Hold reason (day 21+, after documented outreach)"
                  name="reason"
                  required
                  maxLength={1000}
                />
                <Button type="submit" variant="secondary">
                  Place approval hold
                </Button>
              </form>
            </Card>
          )}
        </Section>
      ) : null}

      {currentReleaseId ? (
        <Section id="evidence" title="Release evidence">
          <Card>
            <form action={act.recordQaAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ releaseId: currentReleaseId }} />
              <h3 className="font-medium text-fg">QA for the current release</h3>
              {QA_AREAS.map((a) => (
                <PassFail key={a} name={`qa_${a}`} label={a.replaceAll("_", " ")} />
              ))}
              <Button type="submit" variant="secondary">
                Record QA result
              </Button>
            </form>
          </Card>
          <Card>
            <form action={act.recordSecurityAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ releaseId: currentReleaseId }} />
              <h3 className="font-medium text-fg">Security checks for the current release</h3>
              {SECURITY_KEYS.map((k) => (
                <PassFail key={k} name={`sec_${k}`} label={k.replaceAll("_", " ")} />
              ))}
              <Button type="submit" variant="secondary">
                Record security result
              </Button>
            </form>
          </Card>
          {isOwner ? (
            <Card>
              <form action={act.approvePerformanceExceptionAction} className="flex flex-col gap-3">
                <Hidden projectId={projectId} extra={{ releaseId: currentReleaseId }} />
                <h3 className="font-medium text-fg">
                  Performance exception (Owner, performance items only)
                </h3>
                <TextField
                  label='Measured values (JSON, for example {"lcp_ms": 2900})'
                  name="measuredValues"
                  required
                />
                <TextField label="Reason" name="reason" required maxLength={1000} />
                <Button type="submit" variant="secondary">
                  Approve performance exception
                </Button>
              </form>
            </Card>
          ) : null}
        </Section>
      ) : null}

      <Section id="domain" title="Domain readiness and deployment target">
        <Card>
          <form action={act.recordDomainCheckAction} className="flex flex-col gap-3">
            <Hidden projectId={projectId} />
            <TextField label="Domain" name="domain" required maxLength={253} />
            {[
              ["dnsOk", "DNS points to the client's target"],
              ["tlsOk", "TLS certificate valid"],
              ["redirectOk", "www/apex redirect configured"],
              ["registrantOk", "Registrant in the client's name"],
              ["chargesDisclosed", "Third-party domain charges disclosed and approved"],
              ["spotlightRegistered", "Registered by Spotlight"],
            ].map(([name, label]) => (
              <label key={name} className="flex gap-2 text-sm text-fg">
                <input type="checkbox" name={name} />
                {label}
              </label>
            ))}
            <TextField
              label="Registration date (if registered by Spotlight)"
              name="registrationDate"
              type="date"
            />
            <TextField
              label="Registrar expiry (if registered by Spotlight)"
              name="registrarExpiry"
              type="date"
            />
            <Button type="submit" variant="secondary">
              Record domain check
            </Button>
          </form>
        </Card>
        {target.data ? (
          <p className="text-sm text-fg-muted">
            Isolated deployment target: {target.data.target_ref}
          </p>
        ) : isOwner ? (
          <Card>
            <form action={act.registerSiteTargetAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} />
              <TextField
                label="Client deployment target (project reference)"
                name="targetRef"
                required
                pattern="[a-z0-9][a-z0-9_\-]{2,99}"
              />
              <Button type="submit" variant="secondary">
                Register target
              </Button>
            </form>
          </Card>
        ) : null}
      </Section>

      <Section id="publication" title="Publication">
        {isOwner && currentReleaseId && !activeAuth ? (
          <Card>
            <form action={act.authorizePublicationAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ releaseId: currentReleaseId }} />
              <label className="flex gap-2 text-sm text-fg">
                <input type="checkbox" name="confirm" value="yes" required />
                Authorize publication of release {current?.release_number} exactly as approved.
              </label>
              <Button type="submit">Authorize publication</Button>
              <p className="text-sm text-fg-muted">
                Requires every gate to pass and a fresh authenticator check.
              </p>
            </form>
          </Card>
        ) : null}
        {activeAuth &&
        !(deployments.data ?? []).some((d) => d.authorization_id === activeAuth.id) ? (
          <Card>
            <form action={act.startDeploymentAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ authorizationId: activeAuth.id }} />
              <p className="text-sm text-fg">
                Authorization active. Gates are evaluated again when you start.
              </p>
              <Button type="submit">Start deployment</Button>
            </form>
          </Card>
        ) : null}
        {recoverable ? (
          <Card>
            <form action={act.reopenFailedPublicationAction} className="flex flex-col gap-3">
              <Hidden projectId={projectId} extra={{ deploymentId: latestDeployment.id }} />
              <p className="text-sm text-fg">
                The latest deployment failed or failed live verification. Recovery closes its
                authorization; a new authorization must pass every gate again, and nothing is
                redeployed automatically.
              </p>
              <TextField label="Recovery reason" name="reason" required maxLength={1000} />
              <label className="flex gap-2 text-sm text-fg">
                <input type="checkbox" name="confirm" value="yes" required />
                Close this deployment&apos;s authorization so the release can be authorized again.
              </label>
              <Button type="submit" variant="secondary">
                Recover failed publication
              </Button>
            </form>
          </Card>
        ) : null}
        {(deployments.data ?? []).map((d) => (
          <Card key={d.id} className="flex flex-col gap-3">
            <p className="text-sm text-fg">
              Deployment of {d.commit_sha.slice(0, 12)} to {d.target_ref}: {d.outcome}
            </p>
            {d.outcome === "started" ? (
              <form action={act.recordDeploymentAction} className="flex flex-col gap-3">
                <Hidden projectId={projectId} extra={{ deploymentId: d.id }} />
                <TextField
                  label="Provider deployment ID"
                  name="providerDeploymentId"
                  maxLength={100}
                />
                <TextField label="Production URL" name="productionUrl" type="url" />
                <TextField
                  label="Failure reason (if failed)"
                  name="failureReason"
                  maxLength={1000}
                />
                <div className="flex gap-3">
                  <Button type="submit" name="outcome" value="succeeded">
                    Record success
                  </Button>
                  <Button type="submit" name="outcome" value="failed" variant="secondary">
                    Record failure
                  </Button>
                </div>
              </form>
            ) : null}
            {d.outcome === "succeeded" ? (
              <form action={act.verifyLiveAction}>
                <Hidden projectId={projectId} extra={{ deploymentId: d.id }} />
                <Button type="submit" variant="secondary">
                  Verify live site
                </Button>
              </form>
            ) : null}
          </Card>
        ))}
        {(incidents.data ?? []).map((i) => (
          <Card key={i.id} className="flex flex-col gap-3">
            <p className="text-sm text-danger">
              Incident ({i.severity}): {i.summary}
            </p>
            {isOwner ? (
              <form action={act.resolveIncidentAction} className="flex flex-col gap-3">
                <Hidden projectId={projectId} extra={{ incidentId: i.id }} />
                <TextField label="Resolution" name="resolution" required maxLength={2000} />
                <Button type="submit" variant="secondary">
                  Resolve incident
                </Button>
              </form>
            ) : null}
          </Card>
        ))}
      </Section>
    </>
  );
}
