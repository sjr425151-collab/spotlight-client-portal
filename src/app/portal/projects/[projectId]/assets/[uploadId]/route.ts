import { notFound } from "next/navigation";

import { requireProjectAccess } from "@/server/auth/guards";
import { downloadAsset } from "@/server/services/fulfillment";
import { uuidSchema } from "@/server/services/invitations";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Download of an available asset (05 §4; PR #19 review H1). The database authorizes the
 * caller, confirms the asset is currently available, and audits the access; only then does
 * the server read the object with the secret key and stream it. No storage URL ever reaches
 * the browser, and the response is never stored by a shared cache. Quarantined, rejected,
 * and revoked files are never served (T-UP-05, T-UP-09, T-UP-17).
 */
export async function GET(
  _request: Request,
  { params }: { params: Promise<{ projectId: string; uploadId: string }> },
) {
  const { projectId, uploadId } = await params;
  await requireProjectAccess(projectId);
  if (!uuidSchema.safeParse(uploadId).success) notFound();
  const delivery = await downloadAsset(await createUserClient(), projectId, uploadId);
  if (!delivery.ok) notFound();
  return new Response(delivery.body, { headers: delivery.headers });
}
