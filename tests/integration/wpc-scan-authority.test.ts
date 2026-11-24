import { randomBytes } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

/**
 * T-UP-15 with real concurrency (05 §5.5 rules 1-2) against the LOCAL database: scan-result
 * submissions for one upload, from separate connections, serialize on the content and upload
 * row locks (content lock first, review M1);
 * the sequence matches acceptance (commit) order; delayed results for an earlier attempt and
 * duplicates are non-authoritative. Synthetic rows only, written in Project B, and left in a
 * terminal state.
 */

const DATABASE_URL =
  process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const PROJECT = "20000000-0000-4000-8000-0000000000b0";
const UPLOADER = "00000000-0000-4000-8000-0000000000b1";
// Fresh bytes per upload: a malicious verdict blocks its stored hash permanently, in every
// upload and on every later run against the same local database (05 §5.5 rule 3, M1).
const hashes = new Map<string, string>();

async function connect(): Promise<Client> {
  if (!["127.0.0.1", "localhost"].includes(new URL(DATABASE_URL).hostname)) {
    throw new Error("Tests may only connect to a local database");
  }
  const client = new Client({ connectionString: DATABASE_URL });
  await client.connect();
  await client.query(`select set_config('request.jwt.claims', '{"role":"service_role"}', false)`);
  return client;
}

let setup: Client;
const clients: Client[] = [];

async function newUpload(): Promise<{ id: string; attempt: string }> {
  const sha = randomBytes(32).toString("hex");
  const { rows } = await setup.query(
    `insert into public.asset_uploads (project_id, asset_id, version, category, declared_mime, declared_bytes,
       original_name, status, quarantine_path, size_bytes, sha256, completed_at, uploaded_by, id)
     select $1::uuid, gen_random_uuid(), 1, 'logo', 'image/png', 10, 'race.png', 'quarantined',
       'quarantine/' || $1::text || '/' || g.id, 10, $2::text, now(), $3::uuid, g.id
     from (select gen_random_uuid() id) g returning id`,
    [PROJECT, sha, UPLOADER],
  );
  const id = rows[0].id as string;
  hashes.set(id, sha);
  const opened = await setup.query(
    `select private.record_content_check($1, true, 'image/png', null) ->> 'attempt_id' as attempt`,
    [id],
  );
  return { id, attempt: opened.rows[0].attempt as string };
}

const scan = (c: Client, id: string, attempt: string, verdict: string) =>
  c.query(`select private.record_scan_result($1, $2, 'mock_scanner', '1', $3, $4) as r`, [
    id,
    attempt,
    verdict,
    hashes.get(id),
  ]);

beforeAll(async () => {
  setup = await connect();
  for (let i = 0; i < 6; i++) clients.push(await connect());
});

afterAll(async () => {
  for (const c of [...clients, setup]) await c.end();
});

describe("T-UP-15: concurrent scan-result submissions", () => {
  it("a second submission waits for the first's row lock and is sequenced after it", async () => {
    const { id, attempt } = await newUpload();
    const [first, second] = clients as [Client, Client];
    const secondPid = (await second.query("select pg_backend_pid() as pid")).rows[0].pid as number;
    await first.query("begin");
    await scan(first, id, attempt, "clean"); // holds the upload row lock until commit
    const pending = scan(second, id, attempt, "error"); // must wait
    await new Promise((resolve) => setTimeout(resolve, 400));
    const { rows: waiting } = await setup.query(
      `select count(*)::int as n from pg_stat_activity where pid = $1 and wait_event_type = 'Lock'`,
      [secondPid],
    );
    expect(waiting[0].n).toBe(1);
    await first.query("commit");
    const result = (await pending).rows[0].r;
    // Serialized after the clean result: the error for the same attempt, before release,
    // returns the file to quarantine (T-UP-17), and is sequenced after the clean result.
    expect(result).toMatchObject({ status: "quarantined", authoritative: true });
    const { rows } = await setup.query(
      `select verdict, seq from public.upload_scan_results where upload_id = $1 order by seq`,
      [id],
    );
    expect(rows.map((r) => r.verdict)).toEqual(["clean", "error"]);
    expect(Number(rows[1].seq)).toBeGreaterThan(Number(rows[0].seq));
  });

  it("racing duplicate clean results: exactly one is authoritative", async () => {
    const { id, attempt } = await newUpload();
    const results = await Promise.all(clients.map((c) => scan(c, id, attempt, "clean")));
    const dispositions = results.map((r) => r.rows[0].r.disposition ?? "accepted");
    expect(dispositions.filter((d) => d === "accepted")).toHaveLength(1);
    expect(dispositions.filter((d) => d === "duplicate")).toHaveLength(clients.length - 1);
    const { rows } = await setup.query(
      `select count(*) filter (where authoritative)::int as auth, count(*)::int as total
         from public.upload_scan_results where upload_id = $1`,
      [id],
    );
    expect(rows[0]).toEqual({ auth: 1, total: clients.length });
  });

  it("a delayed result for an earlier attempt is non-authoritative; a late malicious one still wins", async () => {
    const { id, attempt: first } = await newUpload();
    await scan(setup, id, first, "invalid_verdict"); // invalid result: back to quarantine
    const reopened = await setup.query(
      `select private.record_content_check($1, true, 'image/png', null) ->> 'attempt_id' as attempt`,
      [id],
    );
    const second = reopened.rows[0].attempt as string;
    const [late, current] = await Promise.all([
      scan(clients[0]!, id, first, "clean"),
      scan(clients[1]!, id, second, "clean"),
    ]);
    expect(late.rows[0].r).toMatchObject({ authoritative: false, disposition: "stale_attempt" });
    expect(current.rows[0].r).toMatchObject({ status: "processing" });
    const malicious = await scan(clients[2]!, id, first, "malicious");
    expect(malicious.rows[0].r).toMatchObject({ status: "rejected" });
    const { rows } = await setup.query(
      `select status::text as s from public.asset_uploads where id = $1`,
      [id],
    );
    expect(rows[0].s).toBe("rejected");
  });
});
