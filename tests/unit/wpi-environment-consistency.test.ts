import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import {
  createEnvironmentCheck,
  environmentConsistent,
  EnvironmentInconsistentError,
  parseClassification,
  rpcClassificationReader,
} from "@/server/environment-consistency";

/**
 * OI-115 (AUTH-016) application check: APP_ENV must agree with the database classifications
 * (c1 = private.environment_settings, c2 = private.runtime_environment) before any test seam
 * activates. Every combination is enumerated; only the listed ones pass.
 */
const APP_ENVS = ["development", "test", "preview", "staging", "production", "", "unknown"];
const C1S = [null, "development", "test", "preview", "staging"];
const C2S = [null, "development", "test"];

const PASSING = new Set([
  // development/test: c2 present and c1 equal to it
  "development|development|development",
  "development|test|test",
  "test|development|development",
  "test|test|test",
  // hosted: no c2; c1 absent (production) or equal to APP_ENV
  "preview|null|null",
  "preview|preview|null",
  "staging|null|null",
  "staging|staging|null",
  "production|null|null",
]);

describe("environmentConsistent: every APP_ENV x c1 x c2 combination", () => {
  for (const appEnv of APP_ENVS)
    for (const c1 of C1S)
      for (const c2 of C2S) {
        const key = `${appEnv}|${c1}|${c2}`;
        const expected = PASSING.has(key);
        it(`${key} -> ${expected ? "consistent" : "refused"}`, () => {
          expect(environmentConsistent(appEnv, { c1, c2 })).toBe(expected);
        });
      }
});

describe("parseClassification: strict", () => {
  it("accepts the two known keys with known values or null", () => {
    expect(parseClassification({ c1: "development", c2: "development" })).toEqual({
      c1: "development",
      c2: "development",
    });
    expect(parseClassification({ c1: null, c2: null })).toEqual({ c1: null, c2: null });
  });
  it.each([
    ["null", null],
    ["a string", "development"],
    ["an array", ["development", "development"]],
    ["a missing key", { c1: "development" }],
    ["an extra key", { c1: null, c2: null, c3: null }],
    ["an undefined value", { c1: undefined, c2: null }],
    ["c1 production (never written)", { c1: "production", c2: null }],
    ["c2 staging (not a runtime value)", { c1: null, c2: "staging" }],
    ["a non-string value", { c1: 1, c2: null }],
    ["a differently cased value", { c1: "Development", c2: "development" }],
  ])("refuses %s", (_label, value) => {
    expect(parseClassification(value)).toBeNull();
  });
});

describe("createEnvironmentCheck: fail closed", () => {
  it("passes on agreement and remembers only the pass", async () => {
    const read = vi.fn(async () => ({ c1: "development", c2: "development" }));
    const check = createEnvironmentCheck("test", read);
    await expect(check()).resolves.toBeUndefined();
    await expect(check()).resolves.toBeUndefined();
    expect(read).toHaveBeenCalledTimes(1);
  });

  it("refuses a disagreement and never caches the failure", async () => {
    const read = vi.fn(async () => ({ c1: "staging", c2: "development" }));
    const check = createEnvironmentCheck("development", read);
    await expect(check()).rejects.toBeInstanceOf(EnvironmentInconsistentError);
    await expect(check()).rejects.toThrow(/c1="staging", c2="development"/);
    expect(read).toHaveBeenCalledTimes(2);
  });

  it("refuses a stray development classification under APP_ENV=staging (G2)", async () => {
    const check = createEnvironmentCheck("staging", async () => ({ c1: "development", c2: null }));
    await expect(check()).rejects.toBeInstanceOf(EnvironmentInconsistentError);
  });

  it("refuses when the classification cannot be read", async () => {
    const check = createEnvironmentCheck("test", async () => {
      throw new Error("network down");
    });
    await expect(check()).rejects.toThrow(/could not be read/);
  });

  it("refuses a malformed response", async () => {
    const check = createEnvironmentCheck("test", async () => ({ c1: "test" }));
    await expect(check()).rejects.toThrow(/malformed/);
  });
});

describe("rpcClassificationReader", () => {
  it("calls the service-role RPC and returns its data", async () => {
    const rpc = vi.fn(async () => ({ data: { c1: null, c2: null }, error: null }));
    const read = rpcClassificationReader(async () => ({ rpc }) as never);
    await expect(read()).resolves.toEqual({ c1: null, c2: null });
    expect(rpc).toHaveBeenCalledWith("environment_classification");
  });

  it("throws on an RPC error, so the check refuses", async () => {
    const rpc = vi.fn(async () => ({ data: null, error: { message: "permission denied" } }));
    const check = createEnvironmentCheck(
      "test",
      rpcClassificationReader(async () => ({ rpc }) as never),
    );
    await expect(check()).rejects.toThrow(/could not be read/);
  });
});
