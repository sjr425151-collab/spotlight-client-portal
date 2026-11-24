import { notFound } from "next/navigation";

import { requireProjectAccess } from "@/server/auth/guards";
import { uuidSchema } from "@/server/services/invitations";
import { callRpc } from "@/server/services/fulfillment";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Download of an available asset (05 §4). The database confirms access and that the asset
 * passed scanning, and audits the access; the object is read with the user's own client, so
 * storage RLS applies too. Quarantined and rejected files are never served (T-UP-05, T-UP-09).
 */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ projectId: string; uploadId: string }> },
) {
  const { projectId, uploadId } = await params;
  await requireProjectAccess(projectId);
  if (!uuidSchema.safeParse(uploadId).success) notFound();
  const db = await createUserClient();
  const access = await callRpc(db, "record_asset_access", { p_upload_id: uploadId });
  if (!access.ok) notFound();
  const path = String(access.data.released_path);
  if (!path.startsWith(`${projectId}/assets/`)) notFound();
  const { data, error } = await db.storage.from("project-assets").download(path);
  if (error || !data) notFound();
  const name = String(access.data.name).replace(/[^\w.-]+/g, "_");
  return new Response(data, {
    headers: {
      "Content-Type": String(access.data.mime),
      "Content-Disposition": `attachment; filename="${name}"`,
      "X-Content-Type-Options": "nosniff",
      "Content-Security-Policy": "default-src 'none'; sandbox",
      "Cache-Control": "private, no-store",
    },
  });
}
