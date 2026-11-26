import type { SupabaseClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

// The billing service used by createPaidProject imports the admin client module; the same
// mock as tests/integration/wpb-billing.test.ts (the local stack's secret-key client).
vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

import { EICAR_SIGNATURE } from "@/domain/uploads";
import { deliverAsset } from "@/server/uploads/delivery";
import { recordScanVerdict, runUploadPipeline } from "@/server/uploads/pipeline";
import { mockScanner } from "@/server/uploads/scanner";

import { withDb } from "../support/db";
import { adminClient, signInWithCode, upgradeToAal2 } from "../support/local-supabase";
import { callRpc, selectOk } from "../support/rpc";
import { BUCKET, PROJECT_B, createPaidProject, freeQuota, png } from "../support/wpc-fixtures";

/**
 * WP-C uploads against the LOCAL Supabase stack (real Auth sessions, the real Storage API,
 * real RLS): T-UP-04 under concurrency, T-UP-05, T-UP-06, T-UP-09, and the AUTH-004
 * combined-policy behaviour through the Storage API (read, list, sign, copy, move, upload).
 * Server-mediated delivery and durable deletion (review H1) are covered in detail in
 * wpc-delivery.test.ts.
 *
 * Projects (AUTH-008 I-1): project A is a fresh project paid through real WP-B records
 * (createPaidProject; no financial function is replaced). The seeded PROJECT_B (client B,
 * unpaid) is only read: its intake stays locked.
 */

const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";

let projectA: string;
let clientA: SupabaseClient;
let clientB: SupabaseClient;

async function request(
  client: SupabaseClient,
  category: string,
  mime: string,
  size: number,
  name: string,
) {
  const { data, error } = await client.rpc("request_upload", {
    p_project_id: projectA,
    p_category: category,
    p_mime: mime,
    p_bytes: size,
    p_original_name: name,
  });
  // Reports the complete PostgREST error (F2); the assertion below is unchanged.
  if (error) throw new Error(`rpc request_upload failed: ${JSON.stringify(error)}`);
  expect(error).toBeNull();
  return data as { ok: boolean; error?: string; upload_id: string; quarantine_path: string };
}

beforeAll(async () => {
  await withDb((db) => db.query("delete from private.rate_limits"));
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
  clientA = await signInWithCode("client.a@example.test");
  clientB = await signInWithCode("client.b@example.test");
  const owner = await signInWithCode("owner@example.test");
  await upgradeToAal2(owner, new Map());
  projectA = (
    await createPaidProject({
      label: "WP-C uploads A",
      owner,
      client: clientA,
      clientUserId: CLIENT_A_ID,
    })
  ).projectId;
  await withDb((db) => db.query("delete from private.rate_limits"));
  await freeQuota(projectA);
});

afterAll(async () => {
  await freeQuota(projectA);
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
});

describe("upload pipeline end to end (05 §5.3)", () => {
  it("quarantines, scans, and releases a clean file; only the server serves the released copy", async () => {
    const bytes = png();
    const req = await request(clientA, "logo", "image/png", bytes.length, "logo.png");
    expect(req.ok).toBe(true);
    expect(req.quarantine_path).toBe(`quarantine/${projectA}/${req.upload_id}`);

    const outcome = await runUploadPipeline(
      adminClient(),
      {
        uploadId: req.upload_id,
        projectId: projectA,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("available");

    const released = `${projectA}/assets/${req.upload_id}`;
    // H1: the released copy reaches the uploader only through the server download route.
    const delivered = await deliverAsset(clientA, adminClient(), projectA, req.upload_id);
    expect(delivered.ok).toBe(true);
    expect(delivered.ok && delivered.body.size).toBeGreaterThan(0);
    expect((await clientA.storage.from(BUCKET).download(released)).data).toBeNull();
    expect((await clientA.storage.from(BUCKET).createSignedUrl(released, 60)).data).toBeNull();

    // AUTH-004 combined policies through the Storage API: the quarantined original is
    // unreachable for the uploader too, and nothing can be copied or moved out of it.
    expect((await clientA.storage.from(BUCKET).download(req.quarantine_path)).data).toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).createSignedUrl(req.quarantine_path, 60)).data,
    ).toBeNull();
    expect((await clientA.storage.from(BUCKET).list(`quarantine/${projectA}`)).data ?? []).toEqual(
      [],
    );
    expect(
      (await clientA.storage.from(BUCKET).copy(req.quarantine_path, `${projectA}/assets/copied`))
        .error,
    ).not.toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).move(req.quarantine_path, `${projectA}/assets/moved`))
        .error,
    ).not.toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).upload(`${projectA}/assets/self-released`, bytes)).error,
    ).not.toBeNull();
    expect(
      (await clientA.storage.from(BUCKET).upload(`quarantine/${projectA}/direct`, bytes)).error,
    ).not.toBeNull();
    expect((await clientA.storage.from(BUCKET).remove([released])).data ?? []).toEqual([]);

    // T-UP-06: client B can neither read nor sign Project A's released asset.
    expect((await clientB.storage.from(BUCKET).download(released)).data).toBeNull();
    expect((await clientB.storage.from(BUCKET).createSignedUrl(released, 60)).data).toBeNull();
    expect((await clientB.storage.from(BUCKET).list(projectA)).data ?? []).toEqual([]);

    const access = await callRpc<{ ok: boolean }>(clientA, "record_asset_access", {
      p_upload_id: req.upload_id,
    });
    expect(access.ok).toBe(true);
    const denied = await callRpc<{ ok: boolean }>(clientB, "record_asset_access", {
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
        projectId: projectA,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("available");
    const released = `${projectA}/assets/${req.upload_id}`;
    expect((await deliverAsset(clientA, adminClient(), projectA, req.upload_id)).ok).toBe(true);
    const row = await selectOk(
      "asset_uploads sha256",
      adminClient().from("asset_uploads").select("sha256").eq("id", req.upload_id).single(),
    );
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
    expect(await deliverAsset(clientA, adminClient(), projectA, req.upload_id)).toEqual({
      ok: false,
      error: "not_available",
    });
    expect((await clientA.storage.from(BUCKET).createSignedUrl(released, 60)).data).toBeNull();
    expect((await adminClient().storage.from(BUCKET).download(released)).data).toBeNull(); // deleted
    const deletion = await selectOk(
      "asset_object_deletions",
      adminClient()
        .from("asset_object_deletions")
        .select("status, attempts")
        .eq("upload_id", req.upload_id)
        .single(),
    );
    expect(deletion).toEqual({ status: "deleted", attempts: 1 });
    const access = await callRpc<{ ok: boolean }>(clientA, "record_asset_access", {
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
        projectId: projectA,
        category: "business_document",
        declaredMime: "application/pdf",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      mockScanner,
    );
    expect(outcome).toBe("rejected");
    expect(
      (await adminClient().storage.from(BUCKET).download(`${projectA}/assets/${req.upload_id}`))
        .data,
    ).toBeNull();
    const access = await callRpc<{ ok: boolean }>(clientA, "record_asset_access", {
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
        projectId: projectA,
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
        projectId: projectA,
        category: "logo",
        declaredMime: "image/png",
        quarantinePath: req.quarantine_path,
      },
      bytes,
      null,
    );
    expect(outcome).toBe("quarantined");
    const data = await selectOk(
      "asset_uploads status",
      clientA.from("asset_uploads").select("status").eq("id", req.upload_id).single(),
    );
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
    await freeQuota(projectA);
    // Occupy all but 500 MB of the quota with reservations, then race five 249 MB requests.
    const usage = await selectOk(
      "asset_uploads usage",
      clientA
        .from("asset_uploads")
        .select("declared_bytes, size_bytes, status")
        .eq("project_id", projectA) // client A is a member of more than one project
        .not("status", "in", "(failed_upload,rejected)"),
    );
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
    await freeQuota(projectA);
  });

  it("client B cannot reserve quota in Project A", async () => {
    const data = await callRpc(clientB, "request_upload", {
      p_project_id: projectA,
      p_category: "logo",
      p_mime: "image/png",
      p_bytes: 10,
      p_original_name: "x.png",
    });
    expect(data).toMatchObject({ ok: false, error: "forbidden" });
    const own = await callRpc(clientB, "request_upload", {
      p_project_id: PROJECT_B,
      p_category: "logo",
      p_mime: "image/png",
      p_bytes: 10,
      p_original_name: "x.png",
    });
    expect(own).toMatchObject({ ok: false, error: "intake_locked" });
  });
});
