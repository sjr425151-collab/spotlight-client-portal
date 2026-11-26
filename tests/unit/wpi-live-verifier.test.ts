import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { mockLiveFetch, observeLiveSite, verifierFor } from "@/server/publication/verifier";

/**
 * AUTH-008 I-2 seam (b): `verifierFor(appEnv)` selects the stub only for an affirmative
 * `development` or `test` classification; every other classification selects the real,
 * unchanged verifier. The stub never reaches the network and serves only reserved `.test`
 * hosts.
 */
const SHA = "a".repeat(40);
const OTHER = "b".repeat(40);
const LIVE = `https://${SHA}.live.example.test/`;

afterEach(() => {
  vi.unstubAllGlobals();
});

/** A global `fetch` that records each call and fails it, so no request leaves the test. */
function recordGlobalFetch() {
  const calls: string[] = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url: string) => {
      calls.push(String(url));
      throw new TypeError("network disabled in unit tests");
    }),
  );
  return calls;
}

const FAILED = {
  servedBuildId: null,
  httpOk: false,
  tlsOk: false,
  keyPagesOk: false,
  formsOk: false,
};

describe("verifierFor: affirmative development/test classification only", () => {
  it.each(["development", "test"])(
    "%s selects the stub and never calls the network",
    async (env) => {
      const calls = recordGlobalFetch();
      expect(await verifierFor(env)(LIVE)).toEqual({
        servedBuildId: SHA,
        httpOk: true,
        tlsOk: true,
        keyPagesOk: true,
        formsOk: true,
      });
      expect(calls).toEqual([]);
    },
  );

  it.each(["production", "staging", "preview", "", "unknown", "Test", "DEVELOPMENT", " test"])(
    "%j selects the real verifier (global fetch), never the stub",
    async (env) => {
      const calls = recordGlobalFetch();
      // The real verifier fetches; the disabled network makes it a failed observation.
      expect(await verifierFor(env)(LIVE)).toEqual(FAILED);
      expect(calls).toEqual([LIVE]);
    },
  );

  it("a missing classification selects the real verifier", async () => {
    const calls = recordGlobalFetch();
    expect(await verifierFor(undefined as unknown as string)(LIVE)).toEqual(FAILED);
    expect(calls).toEqual([LIVE]);
  });
});

describe("the stub", () => {
  it("serves the build identifier from a 40-hex first host label", async () => {
    const calls = recordGlobalFetch();
    expect((await verifierFor("test")(`https://${OTHER}.live.example.test/x`)).servedBuildId).toBe(
      OTHER,
    );
    expect(calls).toEqual([]);
  });

  it("serves no build identifier for any other .test host, so verification cannot match", async () => {
    for (const url of [
      "https://live.example.test/",
      `https://${SHA.slice(0, 39)}.live.example.test/`,
      `https://${SHA}0.live.example.test/`,
      `https://x${SHA}.live.example.test/`,
    ]) {
      expect((await verifierFor("test")(url)).servedBuildId, url).toBeNull();
    }
  });

  it.each([
    `https://${SHA}.example.com/`,
    `https://${SHA}.live.example.test.evil.com/`,
    "https://localhost/",
    "https://127.0.0.1/",
    "https://test/",
  ])("refuses a host outside the reserved .test domain: %s", async (url) => {
    const calls = recordGlobalFetch();
    await expect(mockLiveFetch(url)).rejects.toThrow(/only reserved \.test hosts/);
    expect(await verifierFor("development")(url)).toEqual(FAILED);
    expect(calls).toEqual([]);
  });

  it("keeps the real verifier's own refusals (non-https, malformed)", async () => {
    const calls = recordGlobalFetch();
    for (const url of [`http://${SHA}.live.example.test/`, "not a url"]) {
      expect(await verifierFor("test")(url)).toEqual(FAILED);
    }
    expect(calls).toEqual([]);
  });

  it("observeLiveSite itself is unchanged: it uses the global fetch by default", async () => {
    const calls = recordGlobalFetch();
    expect(await observeLiveSite(LIVE)).toEqual(FAILED);
    expect(calls).toEqual([LIVE]);
  });
});
