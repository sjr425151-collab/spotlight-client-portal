import { test as setup } from "@playwright/test";

import { withDb } from "../support/db";

/**
 * Resets local-only state that would otherwise make repeated runs depend on each other:
 * application rate-limit windows and the seeded staff users' MFA factors.
 */
setup("reset local auth state", async () => {
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(
      `delete from auth.mfa_factors where user_id in (
         '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002')`,
    );
  });
});
