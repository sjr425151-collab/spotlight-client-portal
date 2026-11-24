import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Deletion of revoked released objects (05 §5.5 rule 3; PR #19 review H1).
 *
 * The database writes a pending row in the same transaction as each revocation
 * (`public.asset_object_deletions`), so nothing here can lose a deletion. This worker claims
 * due rows (a 5-minute lease and one counted attempt each), deletes the object with the
 * secret key, then CONFIRMS it is gone before reporting success. A storage error, an object
 * still present, or a failed confirmation is reported as a failure: the database backs off,
 * audits it, and alerts the Owner; after five attempts the row fails until the Owner retries.
 * If this process dies mid-attempt, the lease expires and the row is claimed again.
 *
 * Runs right after a revocation, opportunistically before each scan, and on the Owner's
 * retry. Hosted scheduling (DEP-17) will call the same function.
 */

const BUCKET = "project-assets";

export type DeletionOutcome = { id: string; attempt: number; deleted: boolean; error?: string };

type Claimed = { id: string; object_path: string; attempt: number };

/** True if the object is present, false if absent, null if presence could not be confirmed. */
async function objectPresent(admin: SupabaseClient, path: string): Promise<boolean | null> {
  try {
    const { data } = await admin.storage.from(BUCKET).exists(path);
    return typeof data === "boolean" ? data : null;
  } catch {
    return null;
  }
}

/** Deletes one object and returns the failure code, or null once its absence is confirmed. */
async function deleteObject(admin: SupabaseClient, path: string): Promise<string | null> {
  try {
    const { error } = await admin.storage.from(BUCKET).remove([path]);
    if (error) return "storage_error";
  } catch {
    return "storage_error";
  }
  // `remove` also succeeds for an absent object (an earlier attempt may have deleted it), so
  // success is decided by confirming absence, never by the call's result alone.
  const present = await objectPresent(admin, path);
  if (present === null) return "verify_failed";
  return present ? "still_present" : null;
}

/**
 * Processes due deletions: the given rows only, or any due rows. Returns what happened.
 * Never throws; a database failure leaves the rows pending for the next run.
 */
export async function processObjectDeletions(
  admin: SupabaseClient,
  ids: readonly string[] | null = null,
  limit = 10,
): Promise<DeletionOutcome[]> {
  let claimed: Claimed[] = [];
  try {
    const { data, error } = await admin.rpc("claim_object_deletions", {
      p_ids: ids && ids.length > 0 ? ids : null,
      p_limit: limit,
    });
    const rows = (data as { claimed?: Claimed[] } | null)?.claimed;
    if (error || !Array.isArray(rows)) return [];
    claimed = rows;
  } catch {
    return [];
  }
  const outcomes: DeletionOutcome[] = [];
  for (const row of claimed) {
    const failure = await deleteObject(admin, row.object_path);
    try {
      await admin.rpc("record_object_deletion", {
        p_deletion_id: row.id,
        p_attempt: row.attempt,
        p_deleted: failure === null,
        p_error: failure,
      });
    } catch {
      // Unreported: the lease expires and the row is claimed again (interruption recovery).
    }
    outcomes.push(
      failure === null
        ? { id: row.id, attempt: row.attempt, deleted: true }
        : { id: row.id, attempt: row.attempt, deleted: false, error: failure },
    );
  }
  return outcomes;
}
