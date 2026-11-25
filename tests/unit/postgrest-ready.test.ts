import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import {
  createServer as createTcpServer,
  type AddressInfo,
  type Server as TcpServer,
  type Socket,
} from "node:net";

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  PostgrestNotReadyError,
  probePostgrest,
  waitForPostgrestReady,
} from "../support/postgrest-ready";
import {
  SchemaCacheSyncError,
  SyncBudget,
  pollPooledBackends,
  withSchemaCacheSync,
} from "../support/postgrest-sync";

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
    // Every attempt failed. All but the last are 503 PGRST001; the last may instead be cut
    // off by the deadline itself (its timeout is only the few milliseconds that remain).
    const kinds = readiness.failures.map((f) =>
      `${f.kind} ${f.status ?? ""} ${f.code ?? ""}`.trim(),
    );
    expect(kinds.length).toBe(readiness.attempts);
    expect(kinds.slice(0, -1).every((k) => k === "http 503 PGRST001")).toBe(true);
    expect(["http 503 PGRST001", "timeout"]).toContain(kinds.at(-1));
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

/**
 * W-1 (Owner direction, AUTH-008 Amendment 1): the schema-cache sync helper's own database
 * client against a deterministic fake Postgres (127.0.0.1, ephemeral port). The fake speaks
 * just enough of the wire protocol (startup, AuthenticationOk, ReadyForQuery, simple Query) to
 * script each stall exactly. Every test checks that the client socket is closed afterwards.
 */

type PgMode = {
  /** Answer the startup message (otherwise accept the TCP connection and stay silent). */
  startup: boolean;
  /** Answer simple queries (otherwise never respond to a Query). */
  answer: boolean;
  /** Close the server side when the client closes or terminates (otherwise stall the close). */
  closeOnTerminate: boolean;
  /** pids returned by the pg_stat_activity poll, per poll number. */
  pids: (poll: number) => number[];
};

const tcpServers: TcpServer[] = [];

function msg(type: string, body: Buffer) {
  const head = Buffer.alloc(5);
  head.write(type, 0, "latin1");
  head.writeInt32BE(body.length + 4, 1);
  return Buffer.concat([head, body]);
}
const int16 = (n: number) => {
  const b = Buffer.alloc(2);
  b.writeInt16BE(n);
  return b;
};
const int32 = (n: number) => {
  const b = Buffer.alloc(4);
  b.writeInt32BE(n);
  return b;
};
const cstr = (s: string) => Buffer.from(`${s}\0`, "utf8");
const ready = () => msg("Z", Buffer.from("I"));

async function fakePostgres(mode: PgMode) {
  const sockets: { socket: Socket; closed: boolean }[] = [];
  let polls = 0;
  let queries = 0;
  // allowHalfOpen: the fake closes only when told to, so a stalled close is real.
  const server = createTcpServer({ allowHalfOpen: true }, (socket) => {
    const entry = { socket, closed: false };
    sockets.push(entry);
    socket.on("close", () => {
      entry.closed = true;
    });
    socket.on("error", () => {});
    // The client finished its side (FIN): close ours too, unless the close is to be stalled.
    socket.on("end", () => {
      if (mode.closeOnTerminate) socket.end();
    });
    let buffer = Buffer.alloc(0);
    let started = false;
    socket.on("data", (chunk) => {
      buffer = Buffer.concat([buffer, chunk]);
      for (;;) {
        if (!started) {
          if (buffer.length < 4) return;
          const len = buffer.readInt32BE(0);
          if (buffer.length < len) return;
          buffer = buffer.subarray(len);
          started = true;
          if (mode.startup) socket.write(Buffer.concat([msg("R", int32(0)), ready()]));
          continue;
        }
        if (buffer.length < 5) return;
        const type = String.fromCharCode(buffer[0]!);
        const len = buffer.readInt32BE(1);
        if (buffer.length < len + 1) return;
        const body = buffer.subarray(5, len + 1);
        buffer = buffer.subarray(len + 1);
        if (type === "X") {
          if (mode.closeOnTerminate) socket.end();
          continue;
        }
        if (type !== "Q") continue;
        queries++;
        if (!mode.answer) continue;
        const text = body.toString("utf8");
        if (/^set /i.test(text)) {
          socket.write(Buffer.concat([msg("C", cstr("SET")), ready()]));
          continue;
        }
        const pids = mode.pids(polls++);
        const field = Buffer.concat([
          cstr("pid"),
          int32(0),
          int16(0),
          int32(23),
          int16(4),
          int32(-1),
          int16(0),
        ]);
        const rows = pids.map((pid) => {
          const value = Buffer.from(String(pid));
          return msg("D", Buffer.concat([int16(1), int32(value.length), value]));
        });
        socket.write(
          Buffer.concat([
            msg("T", Buffer.concat([int16(1), field])),
            ...rows,
            msg("C", cstr(`SELECT ${pids.length}`)),
            ready(),
          ]),
        );
      }
    });
  });
  tcpServers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const { port } = server.address() as AddressInfo;
  return {
    url: `postgresql://postgres:postgres@127.0.0.1:${port}/postgres`,
    sockets,
    queries: () => queries,
    polls: () => polls,
    allClosed: () => sockets.length > 0 && sockets.every((s) => s.closed),
    /**
     * Proves the client socket is gone while the server side is held open: writing to a
     * destroyed peer is reset (EPIPE/ECONNRESET), which closes the server's socket.
     */
    pokeOpen: () => {
      for (const s of sockets) if (!s.closed) s.socket.write("\0");
    },
  };
}

afterEach(async () => {
  for (const server of tcpServers.splice(0)) {
    await new Promise((resolve) => server.close(resolve));
  }
});

const responsive: PgMode = {
  startup: true,
  answer: true,
  closeOnTerminate: true,
  pids: () => [42],
};

async function failure(promise: Promise<unknown>) {
  const error = await promise.then(
    () => null,
    (e: unknown) => e,
  );
  expect(error).toBeInstanceOf(SchemaCacheSyncError);
  return error as SchemaCacheSyncError;
}

describe("withSchemaCacheSync deadline (W-1)", () => {
  it("a stalled connection establishment fails at the deadline; the socket is closed", async () => {
    const pg = await fakePostgres({ ...responsive, startup: false });
    const started = Date.now();
    const error = await failure(pollPooledBackends(new SyncBudget(400, 5_000), pg.url));
    expect(Date.now() - started).toBeLessThan(400 + 1_000);
    expect(error.step).toBe("connect");
    expect(error.boundMs).toBeLessThanOrEqual(400);
    expect(error.elapsedMs).toBeGreaterThanOrEqual(350);
    expect(error.detail).toMatch(/timeout/i);
    expect(error.message).toContain("failed at connect");
    expect(pg.queries()).toBe(0);
    await vi.waitFor(() => expect(pg.allClosed()).toBe(true));
  });

  it("a stalled query response fails at the deadline; the connection is destroyed", async () => {
    const pg = await fakePostgres({ ...responsive, answer: false });
    const started = Date.now();
    const error = await failure(pollPooledBackends(new SyncBudget(400, 5_000), pg.url));
    expect(Date.now() - started).toBeLessThan(400 + 1_000);
    expect(error.step).toBe("set-statement-timeout");
    expect(error.detail).toContain("Query read timeout");
    expect(pg.queries()).toBe(1);
    await vi.waitFor(() => expect(pg.allClosed()).toBe(true));
  });

  it("a stalled close is bounded: the socket is destroyed and the step reported", async () => {
    const pg = await fakePostgres({ ...responsive, closeOnTerminate: false });
    const started = Date.now();
    const error = await failure(pollPooledBackends(new SyncBudget(5_000, 300), pg.url));
    expect(Date.now() - started).toBeLessThan(300 + 1_000);
    expect(error.step).toBe("close");
    expect(error.boundMs).toBeLessThanOrEqual(300);
    expect(error.detail).toContain("socket destroyed");
    expect(pg.polls()).toBe(1);
    await vi.waitFor(() => {
      pg.pokeOpen();
      expect(pg.allClosed()).toBe(true);
    });
  });

  it("a responsive database is polled and closed normally", async () => {
    const pg = await fakePostgres(responsive);
    expect(await pollPooledBackends(new SyncBudget(5_000, 1_000), pg.url)).toEqual([42]);
    expect(pg.queries()).toBe(2);
    await vi.waitFor(() => expect(pg.allClosed()).toBe(true));
  });

  it("cumulative deadline exhaustion: repeated polls stop at the budget; the caller's ddl() is excluded", async () => {
    const http = await fakePostgrest((_req, res) => ok(res));
    const pg = await fakePostgres(responsive); // the pooled backend is never released
    const ddl = vi.fn(async () => {
      await new Promise((resolve) => setTimeout(resolve, 500));
      return "ddl-done";
    });
    const started = Date.now();
    const error = await failure(
      withSchemaCacheSync(ddl, {
        databaseUrl: pg.url,
        baseUrl: http.baseUrl,
        key: "test-only-key",
        deadlineMs: 600,
        stepTimeoutMs: 1_000,
      }),
    );
    const wall = Date.now() - started;
    expect(ddl).toHaveBeenCalledOnce();
    expect([
      "reload-wait",
      "poll-wait",
      "connect",
      "set-statement-timeout",
      "query",
      "close",
    ]).toContain(error.step);
    expect(error.message).toMatch(/exhausted|did not complete a reload|timeout/);
    // Helper-owned time stops at the budget; the 500 ms ddl() is not counted against it.
    expect(error.elapsedMs).toBeLessThan(600 + 500);
    expect(wall).toBeGreaterThanOrEqual(600 + 500 - 20); // timer granularity
    expect(wall).toBeLessThan(600 + 500 + 1_000);
    expect(pg.polls()).toBeGreaterThan(2);
    const pollsAtFailure = pg.polls();
    await new Promise((resolve) => setTimeout(resolve, 100));
    expect(pg.polls()).toBe(pollsAtFailure); // no background polling continues
    await vi.waitFor(() => expect(pg.allClosed()).toBe(true));
  });

  it("completes once the pooled backend is released, excluding ddl() from the helper's time", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const http = await fakePostgrest((_req, res) => ok(res));
    const pg = await fakePostgres({ ...responsive, pids: (n) => (n < 2 ? [42] : [7]) });
    const { result, sync } = await withSchemaCacheSync(
      async () => {
        await new Promise((resolve) => setTimeout(resolve, 600));
        return "ddl-done";
      },
      { databaseUrl: pg.url, baseUrl: http.baseUrl, key: "test-only-key", deadlineMs: 5_000 },
    );
    expect(result).toBe("ddl-done");
    // The 600 ms ddl() is excluded: the helper's own steps take far less.
    expect(sync.helperMs).toBeLessThan(500);
    expect(http.requests()).toBe(2);
    await vi.waitFor(() => expect(pg.allClosed()).toBe(true));
  });

  it("a failed PostgREST probe fails the sync before any DDL", async () => {
    const http = await fakePostgrest((_req, res) => unavailable(res));
    const ddl = vi.fn(async () => "never");
    const error = await failure(
      withSchemaCacheSync(ddl, { baseUrl: http.baseUrl, key: "k", deadlineMs: 1_000 }),
    );
    expect(error.step).toBe("probe-before");
    expect(error.detail).toContain("PGRST001");
    expect(ddl).not.toHaveBeenCalled();
  });

  it("refuses a non-local database URL", async () => {
    await expect(
      pollPooledBackends(new SyncBudget(), "postgresql://u:p@db.example.com:5432/postgres"),
    ).rejects.toThrow("only connect to a local database");
  });
});
