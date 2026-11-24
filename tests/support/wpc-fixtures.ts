import { withDb } from "./db";

/**
 * Shared WP-C integration fixtures (local stack, synthetic data only).
 *
 * The deposit comes from a test-only fixture of the approved WP-B interface (04 §8.1): the
 * original function definition is saved first and restored exactly afterwards, and the
 * `payment_authorization_ready` attribute is added only if WP-B has not added it yet.
 */

export const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
export const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
export const BUCKET = "project-assets";

/**
 * A minimal PNG with a unique tEXt chunk per call. Unique bytes matter: a malicious verdict
 * blocks those exact bytes in every upload, permanently (05 §5.5 rule 3), and that evidence
 * persists across runs on a local database. The served copy strips tEXt chunks.
 */
let pngCount = 0;
const RUN = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
const u32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const chunk = (type: string, data: number[]) => [
  ...u32(data.length),
  ...[...type].map((ch) => ch.charCodeAt(0)),
  ...data,
  0,
  0,
  0,
  0, // CRC (not checked by the pipeline's header parser)
];
export const png = () => {
  const tag = [...`run-${RUN}-${pngCount++}`].map((ch) => ch.charCodeAt(0));
  return new Uint8Array([
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    ...chunk("IHDR", [...u32(4), ...u32(4), 8, 6, 0, 0, 0]),
    ...chunk("tEXt", tag),
    ...chunk("IEND", []),
  ]);
};

export type DepositFixture = { restore: () => Promise<void> };

/** Project A's deposit and payment authorization read as verified; every other project keeps the real answer. */
export async function installDepositFixture(): Promise<DepositFixture> {
  let original = "";
  let addedAttribute = false;
  await withDb(async (db) => {
    const { rows } = await db.query(
      "select pg_get_functiondef('private.project_financial_status(uuid)'::regprocedure) as def",
    );
    original = rows[0].def;
    const { rows: attr } = await db.query(
      `select 1 from pg_attribute where attrelid = 'private.project_financial_status'::regclass
         and attname = 'payment_authorization_ready' and not attisdropped`,
    );
    addedAttribute = attr.length === 0;
    if (addedAttribute) {
      await db.query(
        "alter type private.project_financial_status add attribute payment_authorization_ready boolean",
      );
    }
    await db.query(`
      create or replace function private.project_financial_status(p_project_id uuid)
      returns private.project_financial_status
      language sql stable security definer set search_path = '' as $fixture$
        select jsonb_populate_record(null::private.project_financial_status, jsonb_build_object(
          'project_id', p_project_id, 'contract_version', 1,
          'implemented', p_project_id = '${PROJECT_A}', 'deposit_state', 'verified',
          'deposit_verified', p_project_id = '${PROJECT_A}', 'final_balance_state', 'not_due',
          'payment_authorization_ready', p_project_id = '${PROJECT_A}',
          'balance_verified_or_settled', false, 'balance_settled_by_adjustment', false,
          'active_billing_holds', '[]'::jsonb, 'evidence', '{}'::jsonb));
      $fixture$`);
    await db.query("delete from private.rate_limits");
  });
  return {
    restore: () =>
      withDb(async (db) => {
        // Drop the test attribute first: the original stub must match the type it was written for.
        if (addedAttribute) {
          await db.query(
            "alter type private.project_financial_status drop attribute payment_authorization_ready",
          );
        }
        await db.query(original);
      }),
  };
}

/** Frees Project A's quota from abandoned reservations. */
export async function freeQuota() {
  await withDb((db) =>
    db.query(
      `update public.asset_uploads set status = 'failed_upload'
        where project_id = $1 and status = 'uploading'`,
      [PROJECT_A],
    ),
  );
}
