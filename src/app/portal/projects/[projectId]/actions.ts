"use server";

import { redirect } from "next/navigation";

import { intakeFromForm } from "@/domain/intake";
import { requireClient } from "@/server/auth/guards";
import { uuidSchema } from "@/server/services/invitations";
import { callRpc, type Result } from "@/server/services/fulfillment";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Client actions (05 §3, §7-§8). Each starts with a guard; the database re-authorizes the
 * caller as an active member of the project on every call (03 §10). IDs from the form are
 * never trusted: the database resolves the release and project itself.
 */

const text = (formData: FormData, key: string) => String(formData.get(key) ?? "");

function back(formData: FormData, result: Result, okCode: string): never {
  const projectId = text(formData, "projectId");
  const path = uuidSchema.safeParse(projectId).success
    ? `/portal/projects/${projectId}`
    : "/portal";
  redirect(`${path}?${result.ok ? `notice=${okCode}` : `error=${result.error}`}` as never);
}

function contentFrom(formData: FormData) {
  try {
    return intakeFromForm((key) => {
      const value = formData.get(key);
      return typeof value === "string" ? value : null;
    });
  } catch {
    return null;
  }
}

export async function saveIntakeDraftAction(formData: FormData) {
  await requireClient();
  const content = contentFrom(formData);
  if (!content) back(formData, { ok: false, error: "invalid_input" }, "");
  const db = await createUserClient();
  const saved = await callRpc(db, "save_intake_draft", {
    p_project_id: text(formData, "projectId"),
    p_content: content,
  });
  if (!saved.ok || text(formData, "intent") !== "submit") back(formData, saved, "intake_saved");
  back(
    formData,
    await callRpc(db, "submit_intake", {
      p_project_id: text(formData, "projectId"),
      p_draft_id: saved.data.draft_id,
    }),
    "intake_submitted",
  );
}

export async function approvePreviewAction(formData: FormData) {
  await requireClient();
  if (text(formData, "confirm") !== "yes")
    back(formData, { ok: false, error: "confirmation_required" }, "");
  back(
    formData,
    await callRpc(await createUserClient(), "approve_preview", {
      p_release_id: text(formData, "releaseId"),
      p_comment: text(formData, "comment").slice(0, 2000) || null,
    }),
    "preview_approved",
  );
}

export async function requestRevisionsAction(formData: FormData) {
  await requireClient();
  back(
    formData,
    await callRpc(await createUserClient(), "request_revisions", {
      p_release_id: text(formData, "releaseId"),
      p_comments: text(formData, "comments").slice(0, 4000),
    }),
    "revisions_requested",
  );
}

export async function requestUploadExceptionAction(formData: FormData) {
  await requireClient();
  back(
    formData,
    await callRpc(await createUserClient(), "request_upload_exception", {
      p_project_id: text(formData, "projectId"),
      p_kind: "file_type",
      p_requested_mime: text(formData, "mime").trim().toLowerCase(),
      p_max_bytes: 25_000_000,
      p_extra_files: null,
      p_extra_bytes: null,
      p_justification: text(formData, "justification").slice(0, 1000),
    }),
    "exception_requested",
  );
}
