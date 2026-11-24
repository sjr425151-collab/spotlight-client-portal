import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { computeSignature, verifyStripeSignature } from "@/server/stripe/webhook-signature";

/**
 * T-PAY-03 (signature half): Stripe-format signatures over the raw body, signed with a
 * test-only secret generated for this run (OI-63). Not a real Stripe secret.
 */
const secret = `whsec_${crypto.randomUUID().replace(/-/g, "")}`;
const body = JSON.stringify({ id: "evt_unit0000001", type: "invoice.paid", livemode: false });
const now = 1_795_000_000;
const header = (t: number, sig: string) => `t=${t},v1=${sig}`;

describe("verifyStripeSignature", () => {
  it("accepts a valid signature on the exact raw body", () => {
    expect(
      verifyStripeSignature(body, header(now, computeSignature(secret, now, body)), secret, now),
    ).toEqual({
      ok: true,
      timestamp: now,
    });
  });

  it("rejects a body changed by one byte (re-serialized JSON is not the raw body)", () => {
    const sig = computeSignature(secret, now, body);
    const reformatted = JSON.stringify(JSON.parse(body), null, 1);
    expect(verifyStripeSignature(reformatted, header(now, sig), secret, now)).toEqual({
      ok: false,
      reason: "no_matching_signature",
    });
  });

  it("rejects a signature made with another secret", () => {
    const other = computeSignature("whsec_other", now, body);
    expect(verifyStripeSignature(body, header(now, other), secret, now).ok).toBe(false);
  });

  it("rejects timestamps outside the 300-second tolerance (replay window)", () => {
    const old = now - 301;
    expect(
      verifyStripeSignature(body, header(old, computeSignature(secret, old, body)), secret, now),
    ).toEqual({
      ok: false,
      reason: "timestamp_out_of_tolerance",
    });
  });

  it("accepts any matching v1 among several (secret rotation) and ignores other schemes", () => {
    const good = computeSignature(secret, now, body);
    const value = `t=${now},v0=${"0".repeat(64)},v1=${"f".repeat(64)},v1=${good}`;
    expect(verifyStripeSignature(body, value, secret, now).ok).toBe(true);
  });

  it.each([
    [null, "missing_header"],
    ["", "missing_header"],
    ["v1=abc", "malformed_header"],
    [`t=${now}`, "malformed_header"],
    [`t=abc,v1=${"a".repeat(64)}`, "malformed_header"],
    [`t=${now},v1=${"z".repeat(64)}`, "malformed_header"],
  ])("rejects header %j as %s", (value, reason) => {
    expect(verifyStripeSignature(body, value, secret, now)).toEqual({ ok: false, reason });
  });

  it("refuses to run without a secret (fail closed)", () => {
    expect(() => verifyStripeSignature(body, "t=1,v1=x", "", now)).toThrow();
  });
});
