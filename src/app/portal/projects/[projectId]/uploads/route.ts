import { redirect } from "next/navigation";

import { requireProjectAccess } from "@/server/auth/guards";
import { uuidSchema } from "@/server/services/invitations";
import { acceptUpload, isUploadCategory } from "@/server/services/fulfillment";
import { createUserClient } from "@/server/supabase/clients";

/**
 * Upload endpoint (05 §4). The browser never talks to Supabase: the file comes here, the
 * database authorizes the caller and reserves quota, and the server pipeline quarantines
 * and scans it. A route handler (not a server action) so large files are not subject to
 * the server-action body limit.
 */
export async function POST(
  request: Request,
  { params }: { params: Promise<{ projectId: string }> },
) {
  const { projectId } = await params;
  const ctx = await requireProjectAccess(projectId);
  const back = ctx.staffRole ? `/staff/projects/${projectId}` : `/portal/projects/${projectId}`;
  const form = await request.formData().catch(() => null);
  const file = form?.get("file");
  const category = String(form?.get("category") ?? "");
  const replaces = String(form?.get("replaces") ?? "");
  if (!(file instanceof File) || file.size === 0 || !isUploadCategory(category)) {
    redirect(`${back}?error=invalid_input`);
  }
  const result = await acceptUpload(
    await createUserClient(),
    projectId,
    category,
    file,
    uuidSchema.safeParse(replaces).success ? replaces : null,
  );
  redirect(result.ok ? `${back}?notice=upload_${result.outcome}` : `${back}?error=${result.error}`);
}
