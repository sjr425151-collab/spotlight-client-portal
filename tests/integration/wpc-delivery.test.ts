import { randomBytes, randomUUID } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";
import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

// The billing service used by createPaidProject imports the admin client module; the same
// mock as tests/integration/wpb-billing.test.ts (the local stack's secret-key client).
vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

import { processObjectDeletions } from "@/server/uploads/deletions";
import { assetResponseHeaders, deliverAsset } from "@/server/uploads/delivery";
import { recordScanVerdict, runUploadPipeline } from "@/server/uploads/pipeline";
import { mockScanner } from "@/server/uploads/scanner";

import { withDb } from "../support/db";
import {
  SUPABASE_URL,
  adminClient,
  signInWithCode,
  upgradeToAal2,
} from "../support/local-supabase";
import { callRpc } from "../support/rpc";
import { BUCKET, createPaidProject, createProject, freeQuota, png } from "../support/wpc-fixtures";

/**
 * PR #19 review corrections against the LOCAL Supabase stack (real Auth sessions, the real
 * Storage API, real RLS, real parallel database connections):
 *   H1  no user-JWT path to a released object (download, sign, list, public URL); delivery
 *       only through the authorized, audited server route; revocation honoured per request;
 *       durable deletion with explicit result checks, failures, retries, interruptions, the
 *       Owner retry, and audit evidence
 *   M1  identical bytes revoked across uploads and projects; release racing a malicious
 *       verdict for identical bytes, in both orders; racing deletion claims
 * Storage failures are injected by wrapping the real secret-key client, so the database
 * state machine and the Storage API are the real ones.
 *
 * Projects (AUTH-008 I-1): project A is a fresh project paid through real WP-B records
 * (createPaidProject; no financial function is replaced), and project B is a fresh unpaid
 * project whose only client is client B. The seeded projects are not used or changed.
 */

const DATABASE_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const CLIENT_B_ID = "00000000-0000-4000-8000-0000000000b1";
const OWNER_ID = "00000000-0000-4000-8000-000000000001";

let projectA: string;
let projectB: string;
let clientA: SupabaseClient;
let clientB: SupabaseClient;
let owner: SupabaseClient;

type StorageOverrides = Partial<Record<"remove" | "exists" | "download", unknown>>;

/** The real secret-key client with some storage calls replaced (failure injection). */
function withStorage(admin: SupabaseClient, overrides: StorageOverrides): SupabaseClient {
  return new Proxy(admin, {
    get(target, prop, receiver) {
      if (prop === "storage") {
        return {
          from(bucket: string) {
            const real = target.storage.from(bucket);
            return new Proxy(real, {
              get(api, name) {
                if (typeof name === "string" && name in overrides)
                  return overrides[name as keyof StorageOverrides];
                const value = Reflect.get(api, name);
                return typeof value === "function" ? value.bind(api) : value;
              },
            });
          },
        };
      }
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as SupabaseClient;
}

/** A clean file uploaded by client A through the real pipeline, released. */
async function released(bytes = png()) {
  const req = await callRpc<{ ok: boolean; upload_id: string; quarantine_path: string }>(
    clientA,
    "request_upload",
    {
      p_project_id: projectA,
      p_category: "logo",
      p_mime: "image/png",
      p_bytes: bytes.length,
      p_original_name: "asset.png",
    },
  );
  expect(req.ok).toBe(true);
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
  const { data: row } = await adminClient()
    .from("asset_uploads")
    .select("sha256, released_path")
    .eq("id", req.upload_id)
    .single();
  return { id: req.upload_id, sha: row!.sha256 as string, path: row!.released_path as string };
}

const present = async (path: string) =>
  (await adminClient().storage.from(BUCKET).exists(path)).data === true;

const deletionOf = async (uploadId: string) =>
  (
    await adminClient()
      .from("asset_object_deletions")
      .select("id, status, attempts, last_error, manual_retries")
      .eq("upload_id", uploadId)
      .single()
  ).data!;

const malicious = (id: string, sha: string, admin = adminClient()) =>
  recordScanVerdict(
    admin,
    id,
    null,
    "mock_scanner",
    { verdict: "malicious", engineVersion: "mock-1", signature: "it" },
    sha,
  );

/** Records the verdict in the database only (the process stops before deleting). */
const maliciousNoWorker = (id: string, sha: string) =>
  callRpc<{ revoked?: boolean; deletion_ids?: string[] }>(adminClient(), "record_scan_result", {
    p_upload_id: id,
    p_attempt_id: null,
    p_scanner: "mock_scanner",
    p_engine_version: "mock-1",
    p_verdict: "malicious",
    p_scanned_sha256: sha,
    p_signature: "it",
  });

const makeDue = (deletionId: string) =>
  withDb((db) =>
    db.query(
      "update public.asset_object_deletions set next_attempt_at = now() - interval '1 second' where id = $1",
      [deletionId],
    ),
  );

beforeAll(async () => {
  await withDb((db) => db.query("delete from private.rate_limits"));
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
  clientA = await signInWithCode("client.a@example.test");
  clientB = await signInWithCode("client.b@example.test");
  owner = await signInWithCode("owner@example.test");
  await upgradeToAal2(owner, new Map());
  projectA = (
    await createPaidProject({
      label: "WP-C delivery A",
      owner,
      client: clientA,
      clientUserId: CLIENT_A_ID,
    })
  ).projectId;
  projectB = (await createProject("WP-C delivery B", CLIENT_B_ID)).projectId;
  await withDb((db) => db.query("delete from private.rate_limits"));
  await freeQuota(projectA);
});

afterAll(async () => {
  await freeQuota(projectA);
  await withDb((db) => db.query(`delete from auth.mfa_factors where user_id = '${OWNER_ID}'`));
});

describe("H1: no user-JWT path to a released object", () => {
  it("neither the owning client nor another client can download, sign, list, or fetch it", async () => {
    const asset = await released();
    for (const client of [clientA, clientB]) {
      expect((await client.storage.from(BUCKET).download(asset.path)).data).toBeNull();
      expect((await client.storage.from(BUCKET).createSignedUrl(asset.path, 60)).data).toBeNull();
      const many = await client.storage.from(BUCKET).createSignedUrls([asset.path], 60);
      expect((many.data ?? []).filter((d) => d.signedUrl)).toEqual([]);
      const listed = await client.storage.from(BUCKET).list(`${projectA}/assets`);
      expect((listed.data ?? []).map((o) => o.name)).not.toContain(asset.id);
    }
    // The bucket is private: the public URL form serves nothing.
    const publicUrl = clientA.storage.from(BUCKET).getPublicUrl(asset.path).data.publicUrl;
    expect(publicUrl.startsWith(SUPABASE_URL)).toBe(true);
    expect((await fetch(publicUrl)).ok).toBe(false);
  });

  it("the server route serves the exact released bytes privately and audits the access", async () => {
    const asset = await released();
    const delivered = await deliverAsset(clientA, adminClient(), projectA, asset.id);
    expect(delivered.ok).toBe(true);
    if (!delivered.ok) return;
    const stored = await adminClient().storage.from(BUCKET).download(asset.path);
    expect(Buffer.from(await delivered.body.arrayBuffer())).toEqual(
      Buffer.from(await stored.data!.arrayBuffer()),
    );
    expect(delivered.headers["Cache-Control"]).toBe("private, no-store, max-age=0");
    expect(delivered.headers["Content-Disposition"]).toMatch(/^attachment; /);
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select actor_user_id::text as actor, project_id::text as project from public.audit_events
          where action = 'upload.accessed' and target_id = $1`,
        [asset.id],
      );
      expect(rows).toEqual([{ actor: CLIENT_A_ID, project: projectA }]);
    });
  });

  it("another client is refused and leaves no access record", async () => {
    const asset = await released();
    expect(await deliverAsset(clientB, adminClient(), projectA, asset.id)).toEqual({
      ok: false,
      error: "not_found",
    });
    // A mismatched project in the URL is refused too, even for the owning client.
    expect((await deliverAsset(clientA, adminClient(), projectB, asset.id)).ok).toBe(false);
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select count(*)::int as n from public.audit_events where action = 'upload.accessed'
          and target_id = $1 and actor_user_id = $2`,
        [asset.id, CLIENT_B_ID],
      );
      expect(rows[0].n).toBe(0);
    });
  });

  it("a revocation that commits while the object is being read is honoured: nothing is served", async () => {
    const asset = await released();
    const admin = adminClient();
    const racing = withStorage(admin, {
      download: async (path: string) => {
        await maliciousNoWorker(asset.id, asset.sha); // commits between authorization and read
        return admin.storage.from(BUCKET).download(path);
      },
    });
    expect(await deliverAsset(clientA, racing, projectA, asset.id)).toEqual({
      ok: false,
      error: "not_available",
    });
    expect(await deliverAsset(clientA, admin, projectA, asset.id)).toEqual({
      ok: false,
      error: "not_available",
    });
  });

  it("asset responses are never stored by a shared cache", () => {
    const headers = assetResponseHeaders("image/png", "a b.png");
    expect(headers["Cache-Control"]).toBe("private, no-store, max-age=0");
    expect(headers.Pragma).toBe("no-cache");
    expect(headers["Content-Disposition"]).toBe('attachment; filename="a_b.png"');
  });
});

describe("H1: durable deletion of revoked objects", () => {
  it("a failed storage deletion stays pending, alerts the Owner, and a retry deletes it", async () => {
    const asset = await released();
    const failing = withStorage(adminClient(), {
      remove: async () => ({ data: null, error: new Error("injected storage failure") }),
    });
    expect(await malicious(asset.id, asset.sha, failing)).toMatchObject({ revoked: true });
    const row = await deletionOf(asset.id);
    expect(row).toMatchObject({ status: "pending", attempts: 1, last_error: "storage_error" });
    expect(await present(asset.path)).toBe(true); // still stored, but never served:
    expect((await deliverAsset(clientA, adminClient(), projectA, asset.id)).ok).toBe(false);
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select recipient_roles::text[] as roles from public.notification_outbox
          where idempotency_key = $1`,
        [`upload.object_deletion_failed:${row.id}:1`],
      );
      expect(rows).toEqual([{ roles: ["owner"] }]);
    });
    await makeDue(row.id);
    expect(await processObjectDeletions(adminClient(), [row.id])).toEqual([
      { id: row.id, attempt: 2, deleted: true },
    ]);
    expect(await present(asset.path)).toBe(false);
    expect(await deletionOf(asset.id)).toMatchObject({ status: "deleted", last_error: null });
  });

  it("a deletion call that reports success without deleting is caught by the presence check", async () => {
    const asset = await released();
    const silent = withStorage(adminClient(), {
      remove: async () => ({ data: [], error: null }),
    });
    await malicious(asset.id, asset.sha, silent);
    expect(await deletionOf(asset.id)).toMatchObject({
      status: "pending",
      last_error: "still_present",
    });
    expect(await present(asset.path)).toBe(true);
  });

  it("an unconfirmable deletion is a failure, not a success", async () => {
    const asset = await released();
    const blind = withStorage(adminClient(), {
      exists: async () => {
        throw new Error("injected");
      },
    });
    await malicious(asset.id, asset.sha, blind);
    expect(await deletionOf(asset.id)).toMatchObject({
      status: "pending",
      last_error: "verify_failed",
    });
  });

  it("a process stopping right after the revocation leaves a pending deletion that completes later", async () => {
    const asset = await released();
    const verdict = await maliciousNoWorker(asset.id, asset.sha);
    expect(verdict.deletion_ids).toHaveLength(1);
    expect(await deletionOf(asset.id)).toMatchObject({ status: "pending", attempts: 0 });
    expect(await present(asset.path)).toBe(true);
    expect((await deliverAsset(clientA, adminClient(), projectA, asset.id)).ok).toBe(false);
    const [outcome] = await processObjectDeletions(adminClient(), verdict.deletion_ids!);
    expect(outcome).toMatchObject({ deleted: true, attempt: 1 });
    expect(await present(asset.path)).toBe(false);
  });

  it("a process stopping mid-attempt is recovered once its lease expires", async () => {
    const asset = await released();
    const verdict = await maliciousNoWorker(asset.id, asset.sha);
    const id = verdict.deletion_ids![0]!;
    // A worker claims the row and dies before deleting or reporting.
    await callRpc(adminClient(), "claim_object_deletions", { p_ids: [id], p_limit: 1 });
    expect(await processObjectDeletions(adminClient(), [id])).toEqual([]); // lease still live
    await withDb((db) =>
      db.query(
        "update public.asset_object_deletions set leased_until = now() - interval '1 second' where id = $1",
        [id],
      ),
    );
    expect(await processObjectDeletions(adminClient(), [id])).toEqual([
      { id, attempt: 2, deleted: true },
    ]);
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select (summary ->> 'attempt')::int as attempt from public.audit_events
          where action = 'upload.object_deleted' and target_id = $1`,
        [id],
      );
      expect(rows).toEqual([{ attempt: 2 }]);
    });
  });

  it("racing workers never claim one deletion twice", async () => {
    const asset = await released();
    const verdict = await maliciousNoWorker(asset.id, asset.sha);
    const id = verdict.deletion_ids![0]!;
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        callRpc<{ claimed: unknown[] }>(adminClient(), "claim_object_deletions", {
          p_ids: [id],
          p_limit: 1,
        }),
      ),
    );
    const claimed = results.map((r) => r.claimed.length);
    expect(claimed.sort()).toEqual([0, 0, 0, 0, 1]);
    await withDb((db) =>
      db.query(
        "update public.asset_object_deletions set leased_until = now() - interval '1 second' where id = $1",
        [id],
      ),
    );
    await processObjectDeletions(adminClient(), [id]);
  });

  it("after the last attempt fails, only an Owner retry allows another, and it is audited", async () => {
    const asset = await released();
    const failing = withStorage(adminClient(), {
      remove: async () => ({ data: null, error: new Error("injected storage failure") }),
    });
    await malicious(asset.id, asset.sha, failing);
    const { id } = await deletionOf(asset.id);
    for (let attempt = 2; attempt <= 5; attempt++) {
      await makeDue(id);
      await processObjectDeletions(failing, [id]);
    }
    expect(await deletionOf(asset.id)).toMatchObject({ status: "failed", attempts: 5 });
    expect(await processObjectDeletions(adminClient(), [id])).toEqual([]);

    const refused = await callRpc(clientA, "retry_object_deletion", { p_deletion_id: id });
    expect(refused).toMatchObject({ ok: false, error: "forbidden" });
    const allowed = await callRpc(owner, "retry_object_deletion", { p_deletion_id: id });
    expect(allowed).toMatchObject({ ok: true });
    expect(await processObjectDeletions(adminClient(), [id])).toEqual([
      { id, attempt: 6, deleted: true },
    ]);
    expect(await present(asset.path)).toBe(false);
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select action, actor_user_id::text as actor from public.audit_events
          where target_id = $1 order by id`,
        [id],
      );
      expect(rows.filter((r) => r.action === "upload.object_deletion_failed")).toHaveLength(5);
      expect(rows.filter((r) => r.action === "upload.object_deletion_retried")).toEqual([
        { action: "upload.object_deletion_retried", actor: OWNER_ID },
      ]);
      expect(rows.filter((r) => r.action === "upload.object_deleted")).toHaveLength(1);
    });
  });
});

describe("M1: malicious bytes are identified by the stored hash", () => {
  it("identical released bytes in another upload and another project are revoked and deleted", async () => {
    const bytes = png();
    const first = await released(bytes);
    const second = await released(bytes);
    expect(second.sha).toBe(first.sha);
    // The same bytes released in Project B (synthetic record and object; project B is unpaid, so B's intake is locked).
    const other = randomUUID();
    const otherPath = `${projectB}/assets/${other}`;
    await withDb((db) =>
      db.query(
        `insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
           original_name, status, quarantine_path, released_path, size_bytes, sha256, released_sha256, released_bytes,
           completed_at, uploaded_by)
         values ($1, $2, gen_random_uuid(), 1, 'logo', 'image/png', 100, 'b.png', 'available', $3, $4, 100, $5, $5, 100,
           now(), $6)`,
        [other, projectB, `quarantine/${projectB}/${other}`, otherPath, first.sha, CLIENT_B_ID],
      ),
    );
    expect(
      (await adminClient().storage.from(BUCKET).upload(otherPath, bytes, { upsert: false })).error,
    ).toBeNull();

    const verdict = await malicious(first.id, first.sha);
    expect(verdict).toMatchObject({ revoked: true });
    for (const asset of [first, second, { id: other, path: otherPath }]) {
      expect(await present(asset.path)).toBe(false);
      expect(await deletionOf(asset.id)).toMatchObject({ status: "deleted" });
    }
    expect((await deliverAsset(clientA, adminClient(), projectA, second.id)).ok).toBe(false);
    // Project B's client is told only about Project B's upload.
    await withDb(async (db) => {
      const { rows } = await db.query(
        `select project_id::text as project, recipient_user_ids::text[] as users from public.notification_outbox
          where notification_type = 'upload.rejected' and payload_ref ->> 'upload_id' = $1`,
        [other],
      );
      expect(rows).toEqual([{ project: projectB, users: [CLIENT_B_ID] }]);
      const { rows: leaks } = await db.query(
        `select count(*)::int as n from public.notification_outbox
          where project_id = $1 and payload_ref::text like '%' || $2 || '%'`,
        [projectB, first.id],
      );
      expect(leaks[0].n).toBe(0);
    });
  });

  it("a verdict reporting another upload's hash acts on the stored bytes only", async () => {
    const target = await released();
    const bystander = await released();
    // The scanner reports the bystander's hash for the target upload.
    await malicious(target.id, bystander.sha);
    expect((await deliverAsset(clientA, adminClient(), projectA, target.id)).ok).toBe(false);
    expect((await deliverAsset(clientA, adminClient(), projectA, bystander.id)).ok).toBe(true);
  });
});

describe("M1: release racing a malicious verdict for identical bytes (real concurrency)", () => {
  const connections: Client[] = [];
  const connect = async () => {
    if (!["127.0.0.1", "localhost"].includes(new URL(DATABASE_URL).hostname)) {
      throw new Error("Tests may only connect to a local database");
    }
    const c = new Client({ connectionString: DATABASE_URL });
    await c.connect();
    await c.query(`select set_config('request.jwt.claims', '{"role":"service_role"}', false)`);
    connections.push(c);
    return c;
  };
  afterAll(async () => {
    for (const c of connections) await c.end();
  });

  /** X (project A) ready to release and Y (project B) scanning, both holding the same bytes. */
  async function pair(setup: Client) {
    const sha = randomBytes(32).toString("hex");
    const ids: string[] = [];
    for (const [project, uploader] of [
      [projectA, CLIENT_A_ID],
      [projectB, CLIENT_B_ID],
    ] as const) {
      const { rows } = await setup.query(
        `insert into public.asset_uploads (id, project_id, asset_id, version, category, declared_mime, declared_bytes,
           original_name, status, quarantine_path, size_bytes, sha256, completed_at, uploaded_by)
         select g.id, $1::uuid, gen_random_uuid(), 1, 'logo', 'image/png', 10, 'race.png', 'quarantined',
           'quarantine/' || $1::text || '/' || g.id, 10, $2::text, now(), $3::uuid
         from (select gen_random_uuid() id) g returning id`,
        [project, sha, uploader],
      );
      ids.push(rows[0].id as string);
    }
    const [x, y] = ids as [string, string];
    const xAttempt = (
      await setup.query(
        "select private.record_content_check($1, true, 'image/png', null) ->> 'attempt_id' as a",
        [x],
      )
    ).rows[0].a;
    await setup.query(
      "select private.record_scan_result($1, $2, 'mock_scanner', '1', 'clean', $3)",
      [x, xAttempt, sha],
    );
    await setup.query("select private.confirm_source_hash($1, $2)", [x, sha]);
    await setup.query("select private.record_content_check($1, true, 'image/png', null)", [y]);
    return { x, y, sha };
  }

  const status = async (setup: Client, id: string) =>
    (
      await setup.query(
        "select status::text as s, revoked_at is not null as r from public.asset_uploads where id = $1",
        [id],
      )
    ).rows[0];

  it("release first: the verdict waits on the content lock, then revokes the just-released file", async () => {
    const [setup, releaser, scanner] = [await connect(), await connect(), await connect()];
    const { x, y, sha } = await pair(setup);
    const scannerPid = (await scanner.query("select pg_backend_pid() as pid")).rows[0].pid;
    await releaser.query("begin");
    const rel = await releaser.query("select private.release_upload($1, $2, 10) as r", [x, sha]);
    expect(rel.rows[0].r).toMatchObject({ status: "available" });
    const verdict = scanner.query(
      "select private.record_scan_result($1, null, 'mock_scanner', '1', 'malicious', $2) as r",
      [y, sha],
    );
    await new Promise((resolve) => setTimeout(resolve, 400));
    const { rows: waiting } = await setup.query(
      "select count(*)::int as n from pg_stat_activity where pid = $1 and wait_event_type = 'Lock'",
      [scannerPid],
    );
    expect(waiting[0].n).toBe(1);
    await releaser.query("commit");
    expect((await verdict).rows[0].r).toMatchObject({ revoked_count: 1 });
    expect(await status(setup, x)).toEqual({ s: "rejected", r: true });
    const { rows } = await setup.query(
      "select status from public.asset_object_deletions where upload_id = $1",
      [x],
    );
    expect(rows).toEqual([{ status: "pending" }]);
    await processObjectDeletions(adminClient()); // the object never existed: absence is confirmed
  });

  it("verdict first: the release waits, then is refused; the file is never available", async () => {
    const [setup, releaser, scanner] = [await connect(), await connect(), await connect()];
    const { x, y, sha } = await pair(setup);
    const releaserPid = (await releaser.query("select pg_backend_pid() as pid")).rows[0].pid;
    await scanner.query("begin");
    await scanner.query(
      "select private.record_scan_result($1, null, 'mock_scanner', '1', 'malicious', $2)",
      [y, sha],
    );
    const rel = releaser.query("select private.release_upload($1, $2, 10) as r", [x, sha]);
    await new Promise((resolve) => setTimeout(resolve, 400));
    const { rows: waiting } = await setup.query(
      "select count(*)::int as n from pg_stat_activity where pid = $1 and wait_event_type = 'Lock'",
      [releaserPid],
    );
    expect(waiting[0].n).toBe(1);
    await scanner.query("commit");
    expect((await rel).rows[0].r).toMatchObject({ ok: false });
    expect(await status(setup, x)).toEqual({ s: "rejected", r: false });
    const { rows } = await setup.query(
      "select count(*)::int as n from public.audit_events where action = 'upload.released' and target_id = $1",
      [x],
    );
    expect(rows[0].n).toBe(0);
  });
});
