import type { SupabaseClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { EICAR_SIGNATURE } from "@/domain/uploads";
import { recordScanVerdict, runUploadPipeline } from "@/server/uploads/pipeline";
import { mockScanner } from "@/server/uploads/scanner";

import { withDb } from "../support/db";
import { adminClient, signInWithCode } from "../support/local-supabase";

/**
 * WP-C uploads against the LOCAL Supabase stack (real Auth sessions, the real Storage API,
 * real RLS): T-UP-04 under concurrency, T-UP-05, T-UP-06, T-UP-09, and the AUTH-004
 * combined-policy behaviour through the Storage API (read, list, sign, copy, move, upload).
 *
 * The deposit comes from a test-only fixture of the approved WP-B interface. The original
 * function definition is saved first and restored exactly afterwards.
 */

const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
const BUCKET = "project-assets";

let originalFinancialFunction = "";
let addedReadyAttribute = false;
let clientA: SupabaseClient;
let clientB: SupabaseClient;

const png = () =>
  new Uint8Array([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 4,
    0, 0, 0, 4, 8, 6, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x49, 0x45, 0x4e, 0x44, 0, 0, 0, 0,
  ]);

async function request(
  client: SupabaseClient,
  category: string,
  mime: string,
  size: number,
  name: string,
) {
  const { data, error } = await client.rpc("request_upload", {
    p_project_id: PROJECT_A,
    p_category: category,
    p_mime: mime,
    p_bytes: size,
    p_original_name: name,
  });
  expect(error).toBeNull();
  return data as { ok: boolean; error?: string; upload_id: string; quarantine_path: string };
}

async function freeQuota() {
  await withDb((db) =>
    db.query(
      `update public.asset_uploads set status = 'failed_upload'
        where project_id = $1 and status = 'uploading'`,
      [PROJECT_A],
    ),
  );
}

beforeAll(async () => {
  await withDb(async (db) => {
    const { rows } = await db.query(
      "select pg_get_functiondef('private.project_financial_status(uuid)'::regprocedure) as def",
    );
    originalFinancialFunction = rows[0].def;
    // WP-B's approved attribute (04 §8.1), added for the test only if WP-B has not yet, and
    // removed again afterwards.
    const { rows: attr } = await db.query(
      `select 1 from pg_attribute where attrelid = 'private.project_financial_status'::regclass
         and attname = 'payment_authorization_ready' and not attisdropped`,
    );
    addedReadyAttribute = attr.length === 0;
    if (addedReadyAttribute) {
      await db.query(
        "alter type private.project_financial_status add attribute payment_authorization_ready boolean",
      );
    }
    // Fixture: Project A's deposit is verified; every other project keeps the real answer.
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
  await freeQuota();
  clientA = await signInWithCode("client.a@example.test");
  clientB = await signInWithCode("client.b@example.test");
});

afterAll(async () => {
  await freeQuota();
  await withDb(async (db) => {
    // Drop the test attribute first: the original stub must match the type it was written for.
    if (addedReadyAttribute) {
      await db.query(
        "alter type private.project_financial_status drop attribute payment_authorization_ready",
      );
    }
    await db.query(originalFinancialFunction);
  });
});

describe("upload pipeline end to end (05 §5.3)", () => {
  it("quarantines, scans, and releases a clean file; only the released copy is readable", async () => {
    const bytes = png();
    const req = await request(clientA, "logo", "image/png", bytes.length, "logo.png");
    expect(req.ok).toBe(true);
    expect(req.quarantine_path).toBe(`quarantine/${PROJECT_A}/${req.upload_id}`);

    const outcome = await runUploadPipeline(
      adminClient(),
      {
        uploadId: req.upload_id,
        projectId: PROJECT_A,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("available");

    const released = `${PROJECT_A}/assets/${req.upload_id}`;
    const ownRead = await clientA.storage.from(BUCKET).download(released);
    expect(ownRead.error).toBeNull();
    expect((await ownRead.data!.arrayBuffer()).byteLength).toBeGreaterThan(0);

    // AUTH-004 combined policies through the Storage API: the quarantined original is
    // unreachable for the uploader too, and nothing can be copied or moved out of it.
    expect((await clientA.storage.from(BUCKET).download(req.quarantine_path)).data).toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).createSignedUrl(req.quarantine_path, 60)).data,
    ).toBeNull();
    expect((await clientA.storage.from(BUCKET).list(`quarantine/${PROJECT_A}`)).data ?? []).toEqual(
      [],
    );
    expect(
      (await clientA.storage.from(BUCKET).copy(req.quarantine_path, `${PROJECT_A}/assets/copied`))
        .error,
    ).not.toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).move(req.quarantine_path, `${PROJECT_A}/assets/moved`))
        .error,
    ).not.toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).upload(`${PROJECT_A}/assets/self-released`, bytes)).error,
    ).not.toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).upload(`quarantine/${PROJECT_A}/direct`, bytes)).error,
    ).not.toBeNull();
    expect((await clientA.storage.from(BUCKET).remove([released])).data ?? []).toEqual([]);

    // T-UP-06: client B can neither read nor sign Project A's released asset.
    expect((await clientB.storage.from(BUCKET).download(released)).data).toBeNull();
    expect((await clientB.storage.from(BUCKET).createSignedUrl(released, 60)).data).toBeNull();
    expect((await clientB.storage.from(BUCKET).list(PROJECT_A)).data ?? []).toEqual([]);

    const { data: access } = await clientA.rpc("record_asset_access", {
      p_upload_id: req.upload_id,
    });
    expect(access.ok).toBe(true);
    const { data: denied } = await clientB.rpc("record_asset_access", {
      p_upload_id: req.upload_id,
    });
    expect(denied.ok).toBe(false);
  });

  it("T-UP-17: a late malicious verdict revokes a released file at once and deletes it", async () => {
    const bytes = png();
    const req = await request(clientA, "logo", "image/png", bytes.length, "late.png");
    const outcome = await runUploadPipeline(
      adminClient(),
      {
        uploadId: req.upload_id,
        projectId: PROJECT_A,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("available");
    const released = `${PROJECT_A}/assets/${req.upload_id}`;
    expect((await clientA.storage.from(BUCKET).download(released)).error).toBeNull();
    const { data: row } = await adminClient()
      .from("asset_uploads")
      .select("sha256")
      .eq("id", req.upload_id)
      .single();
    // A delayed malicious callback from the vendor, for an attempt that is no longer current.
    const late = await recordScanVerdict(
      adminClient(),
      req.upload_id,
      null,
      "mock_scanner",
      { verdict: "malicious", engineVersion: "mock-1", signature: "late" },
      row!.sha256 as string,
    );
    expect(late).toMatchObject({ status: "rejected", revoked: true });
    expect((await clientA.storage.from(BUCKET).download(released)).data).toBeNull();
    expect((await clientA.storage.from(BUCKET).createSignedUrl(released, 60)).data).toBeNull();
    expect((await adminClient().storage.from(BUCKET).download(released)).data).toBeNull(); // deleted
    const { data: access } = await clientA.rpc("record_asset_access", {
      p_upload_id: req.upload_id,
    });
    expect(access).toMatchObject({ ok: false, error: "not_available" });
  });

  it("T-UP-09: a file failing the scan is rejected, never released, and both parties are notified", async () => {
    const bytes = new TextEncoder().encode(`%PDF-1.4\n${EICAR_SIGNATURE}\n`);
    const req = await request(
      clientA,
      "business_document",
      "application/pdf",
      bytes.length,
      "infected.pdf",
    );
    const outcome = await runUploadPipeline(
      adminClient(),
      {
        uploadId: req.upload_id,
        projectId: PROJECT_A,
        category: "business_document",
        declaredMime: "application/pdf",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("rejected");
    expect(
      (await adminClient().storage.from(BUCKET).download(`${PROJECT_A}/assets/${req.upload_id}`))
        .data,
    ).toBeNull();
    const { data: access } = await clientA.rpc("record_asset_access", {
      p_upload_id: req.upload_id,
    });
    expect(access).toMatchObject({ ok: false, error: "not_available" });
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select recipient_user_ids::text[] as users, recipient_roles::text[] as roles from public.notification_outbox
          where notification_type = 'upload.rejected' and payload_ref ->> 'upload_id' = $1`,
        [req.upload_id],
      );
      expect(rows).toEqual([{ users: ["00000000-0000-4000-8000-0000000000a1"], roles: ["staff"] }]);
    });
  });

  it("T-UP-02: a renamed executable is rejected before scanning", async () => {
    const bytes = new Uint8Array([0x4d, 0x5a, 0x90, 0, 3, 0, 0, 0]);
    const req = await request(clientA, "logo", "image/png", bytes.length, "logo.png");
    const outcome = await runUploadPipeline(
      adminClient(),
      {
        uploadId: req.upload_id,
        projectId: PROJECT_A,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("rejected");
  });

  it("DEP-07: without a scanner the file stays in quarantine", async () => {
    const bytes = png();
    const req = await request(clientA, "logo", "image/png", bytes.length, "unscanned.png");
    const outcome = await runUploadPipeline(
      adminClient(),
      {
        uploadId: req.upload_id,
        projectId: PROJECT_A,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      null,
    );
    expect(outcome).toBe("quarantined");
    const { data } = await clientA
      .from("asset_uploads")
      .select("status")
      .eq("id", req.upload_id)
      .single();
    expect(data?.status).toBe("quarantined");
  });

  it("a client cannot record a scan result or release a file (no self-certification)", async () => {
    const { error } = await clientA.rpc("record_scan_result", {
      p_upload_id: "00000000-0000-4000-8000-000000000000",
      p_attempt_id: "00000000-0000-4000-8000-000000000000",
      p_scanner: "mock_scanner",
      p_engine_version: "1",
      p_verdict: "clean",
      p_scanned_sha256: "a".repeat(64),
    });
    expect(error).not.toBeNull();
    const { error: releaseError } = await clientA.rpc("release_upload", {
      p_upload_id: "00000000-0000-4000-8000-000000000000",
      p_released_sha256: "a".repeat(64),
      p_released_bytes: 1,
    });
    expect(releaseError).not.toBeNull();
  });
});

describe("T-UP-04: quota under concurrent uploads", () => {
  it("never exceeds the 2 GB quota when requests race", async () => {
    await freeQuota();
    // Occupy all but 500 MB of the quota with reservations, then race five 249 MB requests.
    const { data: usage } = await clientA
      .from("asset_uploads")
      .select("declared_bytes, size_bytes, status")
      .not("status", "in", "(failed_upload,rejected)");
    const used = (usage ?? []).reduce((n, u) => n + Number(u.size_bytes ?? u.declared_bytes), 0);
    let remaining = 2_000_000_000 - used - 500_000_000;
    const fillers: Promise<unknown>[] = [];
    while (remaining > 0) {
      const size = Math.min(remaining, 249_000_000);
      fillers.push(request(clientA, "video", "video/mp4", size, "filler.mp4"));
      remaining -= size;
    }
    await Promise.all(fillers);
    const results = await Promise.all(
      Array.from({ length: 5 }, (_, i) =>
        request(clientA, "video", "video/mp4", 249_000_000, `race-${i}.mp4`),
      ),
    );
    expect(results.filter((r) => r.ok)).toHaveLength(2);
    expect(results.filter((r) => !r.ok).map((r) => r.error)).toEqual([
      "quota_bytes",
      "quota_bytes",
      "quota_bytes",
    ]);
    await freeQuota();
  });

  it("client B cannot reserve quota in Project A", async () => {
    const { data } = await clientB.rpc("request_upload", {
      p_project_id: PROJECT_A,
      p_category: "logo",
      p_mime: "image/png",
      p_bytes: 10,
      p_original_name: "x.png",
    });
    expect(data).toMatchObject({ ok: false, error: "forbidden" });
    const { data: own } = await clientB.rpc("request_upload", {
      p_project_id: PROJECT_B,
      p_category: "logo",
      p_mime: "image/png",
      p_bytes: 10,
      p_original_name: "x.png",
    });
    expect(own).toMatchObject({ ok: false, error: "intake_locked" });
  });
});
