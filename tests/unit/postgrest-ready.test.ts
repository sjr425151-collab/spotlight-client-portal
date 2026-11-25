import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  PostgrestNotReadyError,
  probePostgrest,
  waitForPostgrestReady,
} from "../support/postgrest-ready";

/**
 * AUTH-008 Amendment 1 (R1-HANDOFFS §3A): the PostgREST readiness gate against deterministic
 * local fake HTTP servers (127.0.0.1, ephemeral port; no Supabase stack, no network). Each
 * scenario scripts the server's answer to every request, so the outcome does not depend on
 * timing beyond the configured deadlines.
 */

type Handler = (req: IncomingMessage, res: ServerResponse, n: number) => void;

const servers: Server[] = [];

async function fakePostgrest(handler: Handler) {
  let n = 0;
  const seen: { aborted: boolean }[] = [];
  const server = createServer((req, res) => {
    const record = { aborted: false };
    seen.push(record);
    // The client gave up on this request (AbortSignal) before the server answered.
    res.on("close", () => {
      if (!res.writableEnded) record.aborted = true;
    });
    handler(req, res, n++);
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return { baseUrl: `http://127.0.0.1:${port}`, requests: () => n, seen };
}

const ok = (res: ServerResponse) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.end("[]");
};
const unavailable = (res: ServerResponse) => {
  res.writeHead(503, { "content-type": "application/json" });
  res.end(
    JSON.stringify({
      code: "PGRST001",
      details: "no connection to the server\n",
      hint: null,
      message: "Database client error. Retrying the connection.",
    }),
  );
};
const neverAnswer = () => {
  /* holds the request open: a stalled PostgREST */
};

afterEach(async () => {
  for (const server of servers.splice(0)) {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});

const fast = { key: "test-only-key", intervalMs: 10 };

describe("waitForPostgrestReady (AUTH-008 Amendment 1)", () => {
  it("immediate readiness: three consecutive successes, no failures, no warning", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const fake = await fakePostgrest((_req, res) => ok(res));
    const readiness = await waitForPostgrestReady({ ...fast, baseUrl: fake.baseUrl });
    expect(readiness.attempts).toBe(3);
    expect(readiness.failures).toEqual([]);
    expect(readiness.failureCounts).toEqual({});
    expect(fake.requests()).toBe(3);
    expect(warn).not.toHaveBeenCalled();
  });

  it("startup recovery: 503 PGRST001 twice, then ready; both failures reported", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const fake = await fakePostgrest((_req, res, n) => (n < 2 ? unavailable(res) : ok(res)));
    const readiness = await waitForPostgrestReady({
      ...fast,
      baseUrl: fake.baseUrl,
      deadlineMs: 5_000,
    });
    expect(readiness.attempts).toBe(5);
    expect(readiness.failureCounts).toEqual({ "http 503 PGRST001": 2 });
    expect(readiness.failures.map((f) => [f.attempt, f.kind, f.status, f.code])).toEqual([
      [1, "http", 503, "PGRST001"],
      [2, "http", 503, "PGRST001"],
    ]);
    expect(readiness.failures.every((f) => f.atMs >= 0 && f.durationMs >= 0)).toBe(true);
    expect(warn).toHaveBeenCalledOnce();
    expect(String(warn.mock.calls[0]![0])).toContain('{"http 503 PGRST001":2}');
  });

  it("persistent unavailability: fails closed at the deadline with the failures", async () => {
    const fake = await fakePostgrest((_req, res) => unavailable(res));
    const started = Date.now();
    const error = await waitForPostgrestReady({
      ...fast,
      baseUrl: fake.baseUrl,
      deadlineMs: 400,
    }).catch((e: unknown) => e);
    const took = Date.now() - started;
    expect(error).toBeInstanceOf(PostgrestNotReadyError);
    const { readiness, message } = error as PostgrestNotReadyError;
    expect(took).toBeGreaterThanOrEqual(400);
    expect(took).toBeLessThan(400 + 1_000);
    expect(readiness.attempts).toBeGreaterThan(1);
    expect(readiness.failureCounts).toEqual({ "http 503 PGRST001": readiness.attempts });
    expect(readiness.waitedMs).toBeGreaterThanOrEqual(400);
    expect(message).toContain("not ready within the 400 ms deadline");
    expect(message).toContain("PGRST001");
  });

  it("a non-responding request is aborted at the request timeout and still fails by the deadline", async () => {
    const fake = await fakePostgrest(neverAnswer);
    const started = Date.now();
    const error = await waitForPostgrestReady({
      ...fast,
      baseUrl: fake.baseUrl,
      requestTimeoutMs: 150,
      deadlineMs: 700,
    }).catch((e: unknown) => e);
    const took = Date.now() - started;
    expect(error).toBeInstanceOf(PostgrestNotReadyError);
    const { readiness } = error as PostgrestNotReadyError;
    expect(took).toBeLessThan(700 + 1_000);
    expect(readiness.attempts).toBeGreaterThanOrEqual(3);
    expect(readiness.failures.every((f) => f.kind === "timeout")).toBe(true);
    // Each stalled request was cut at about the individual timeout, not left hanging.
    expect(readiness.failures.slice(0, -1).every((f) => f.durationMs < 150 + 500)).toBe(true);
    await vi.waitFor(() => expect(fake.seen.every((r) => r.aborted)).toBe(true));
  });

  it("overall-deadline expiry: a stalled request is bounded by the remaining deadline, with diagnostics", async () => {
    const fake = await fakePostgrest(neverAnswer);
    const started = Date.now();
    const error = await waitForPostgrestReady({
      ...fast,
      baseUrl: fake.baseUrl,
      requestTimeoutMs: 30_000, // far longer than the deadline: the deadline must win
      deadlineMs: 300,
    }).catch((e: unknown) => e);
    const took = Date.now() - started;
    expect(error).toBeInstanceOf(PostgrestNotReadyError);
    const { readiness, message } = error as PostgrestNotReadyError;
    expect(took).toBeGreaterThanOrEqual(300);
    expect(took).toBeLessThan(300 + 1_000);
    expect(readiness.attempts).toBe(1);
    expect(readiness.failures).toEqual([
      expect.objectContaining({
        attempt: 1,
        kind: "timeout",
        detail: expect.stringMatching(/^aborted after (29\d|300) ms$/),
      }),
    ]);
    expect(message).toContain("1 attempts");
    expect(message).toContain('"timeout":1');
    await vi.waitFor(() => expect(fake.seen[0]?.aborted).toBe(true));
  });

  it("requires three consecutive successes: alternating answers never pass", async () => {
    const fake = await fakePostgrest((_req, res, n) => (n % 2 === 0 ? ok(res) : unavailable(res)));
    const error = await waitForPostgrestReady({
      ...fast,
      baseUrl: fake.baseUrl,
      deadlineMs: 400,
    }).catch((e: unknown) => e);
    expect(error).toBeInstanceOf(PostgrestNotReadyError);
    expect((error as PostgrestNotReadyError).message).toContain("3 consecutive successes");
  });

  it("reports a refused connection as a network failure", async () => {
    const fake = await fakePostgrest((_req, res) => ok(res));
    const url = fake.baseUrl;
    for (const server of servers.splice(0)) {
      server.closeAllConnections();
      await new Promise((resolve) => server.close(resolve));
    }
    const outcome = await probePostgrest({ baseUrl: url, key: "k", timeoutMs: 1_000 });
    expect(outcome).toMatchObject({ ok: false, kind: "network", status: null });
    expect(outcome.detail).toContain("ECONNREFUSED");
  });

  it("refuses a non-local PostgREST URL", async () => {
    await expect(probePostgrest({ baseUrl: "https://example.com" })).rejects.toThrow(
      "only run against a local Supabase stack",
    );
  });
});
