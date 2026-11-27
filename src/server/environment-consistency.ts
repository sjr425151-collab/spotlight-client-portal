import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * OI-115 (AUTH-016) application check: the deployment's `APP_ENV` must agree with the
 * database's own classifications before a test seam (the mocked malware scanner, the mocked
 * live verifier or the mocked Stripe gateway) can activate. The database cannot read
 * `APP_ENV`, so this check lives here; the database independently refuses to run any
 * environment-dependent privileged path when its two classifications disagree
 * (`private.app_environment()` raises).
 *
 * Database classifications, read through the service-role-only
 * `public.environment_classification()`:
 * - `c1`: `private.environment_settings` (development, test, preview or staging; null reads
 *   as production);
 * - `c2`: `private.runtime_environment` (development or test; null means no mock scanner).
 *
 * Rule [PENDING OI-119: the Owner decides the development/test branch]:
 * - `APP_ENV` development or test: `c2` is present and `c1` equals it. CI runs with
 *   `APP_ENV=test` against the seed's `development` classification, so the database values
 *   must agree with each other, not with `APP_ENV` itself.
 * - `APP_ENV` preview, staging or production: `c2` is absent and `c1` is absent (production,
 *   at least as strict) or equals `APP_ENV`.
 * - Anything else, an unreadable classification or a malformed response: refused.
 */

export type DatabaseClassification = { c1: string | null; c2: string | null };

const LOCAL_ENVIRONMENTS = new Set(["development", "test"]);
const HOSTED_ENVIRONMENTS = new Set(["preview", "staging", "production"]);
const C1_VALUES = new Set(["development", "test", "preview", "staging"]);

export class EnvironmentInconsistentError extends Error {
  constructor(detail: string) {
    super(`environment classification disagreement (OI-115): ${detail}`);
    this.name = "EnvironmentInconsistentError";
  }
}

/** Strictly parses the RPC response; anything unexpected is null (refused). */
export function parseClassification(value: unknown): DatabaseClassification | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (keys.length !== 2 || keys[0] !== "c1" || keys[1] !== "c2") return null;
  const { c1, c2 } = record;
  if (c1 !== null && !(typeof c1 === "string" && C1_VALUES.has(c1))) return null;
  if (c2 !== null && !(typeof c2 === "string" && LOCAL_ENVIRONMENTS.has(c2))) return null;
  return { c1: c1 as string | null, c2: c2 as string | null };
}

export function environmentConsistent(appEnv: string, db: DatabaseClassification): boolean {
  if (LOCAL_ENVIRONMENTS.has(appEnv)) return db.c2 !== null && db.c1 === db.c2;
  if (HOSTED_ENVIRONMENTS.has(appEnv))
    return db.c2 === null && (db.c1 === null || db.c1 === appEnv);
  return false;
}

export type ClassificationReader = () => Promise<unknown>;

/** Reads the classification with a service-role client; an RPC error throws. */
export function rpcClassificationReader(
  client: () => Promise<SupabaseClient>,
): ClassificationReader {
  return async () => {
    const { data, error } = await (await client()).rpc("environment_classification");
    if (error) throw new Error("environment_classification failed");
    return data;
  };
}

/**
 * A check for one `APP_ENV`. Only a passing result is remembered (once per process); a
 * failure is never cached, so every later use is checked again and refused again.
 */
export function createEnvironmentCheck(
  appEnv: string,
  read: ClassificationReader,
): () => Promise<void> {
  let passed = false;
  return async () => {
    if (passed) return;
    let raw: unknown;
    try {
      raw = await read();
    } catch {
      throw new EnvironmentInconsistentError(
        `APP_ENV=${JSON.stringify(appEnv)}; the database classification could not be read`,
      );
    }
    const db = parseClassification(raw);
    if (!db) {
      throw new EnvironmentInconsistentError(
        `APP_ENV=${JSON.stringify(appEnv)}; the database classification is malformed`,
      );
    }
    if (!environmentConsistent(appEnv, db)) {
      throw new EnvironmentInconsistentError(
        `APP_ENV=${JSON.stringify(appEnv)}; database c1=${JSON.stringify(db.c1)}, ` +
          `c2=${JSON.stringify(db.c2)}`,
      );
    }
    passed = true;
  };
}
