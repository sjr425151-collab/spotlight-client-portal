import type { SupabaseClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { EICAR_SIGNATURE } from "@/domain/uploads";
import { deliverAsset } from "@/server/uploads/delivery";
import { recordScanVerdict, runUploadPipeline } from "@/server/uploads/pipeline";
import { mockScanner } from "@/server/uploads/scanner";

import { withDb } from "../support/db";
import { adminClient, signInWithCode } from "../support/local-supabase";
import {
  BUCKET,
  PROJECT_A,
  PROJECT_B,
  freeQuota,
  installDepositFixture,
  png,
  type DepositFixture,
} from "../support/wpc-fixtures";

/**
 * WP-C uploads against the LOCAL Supabase stack (real Auth sessions, the real Storage API,
 * real RLS): T-UP-04 under concurrency, T-UP-05, T-UP-06, T-UP-09, and the AUTH-004
 * combined-policy behaviour through the Storage API (read, list, sign, copy, move, upload).
 * Server-mediated delivery and durable deletion (review H1) are covered in detail in
 * wpc-delivery.test.ts.
 */

let fixture: DepositFixture;
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
    p_project_id: PROJECT_A,
    p_category: category,
    p_mime: mime,
    p_bytes: size,
    p_original_name: name,
  });
  expect(error).toBeNull();
  return data as { ok: boolean; error?: string; upload_id: string; quarantine_path: string };
}

beforeAll(async () => {
  fixture = await installDepositFixture();
  await freeQuota();
  clientA = await signInWithCode("client.a@example.test");
  clientB = await signInWithCode("client.b@example.test");
});

afterAll(async () => {
  await freeQuota();
  await fixture.restore();
});

describe("upload pipeline end to end (05 §5.3)", () => {
  it("quarantines, scans, and releases a clean file; only the server serves the released copy", async () => {
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
    // H1: the released copy reaches the uploader only through the server download route.
    const delivered = await deliverAsset(clientA, adminClient(), PROJECT_A, req.upload_id);
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
    expect((await deliverAsset(clientA, adminClient(), PROJECT_A, req.upload_id)).ok).toBe(true);
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
    expect(await deliverAsset(clientA, adminClient(), PROJECT_A, req.upload_id)).toEqual({
      ok: false,
      error: "not_available",
    });
    expect((await clientA.storage.from(BUCKET).createSignedUrl(released, 60)).data).toBeNull();
    expect((await adminClient().storage.from(BUCKET).download(released)).data).toBeNull(); // deleted
    const { data: deletion } = await adminClient()
      .from("asset_object_deletions")
      .select("status, attempts")
      .eq("upload_id", req.upload_id)
      .single();
    expect(deletion).toEqual({ status: "deleted", attempts: 1 });
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
