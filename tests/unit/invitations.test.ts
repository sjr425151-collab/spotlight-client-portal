import { describe, expect, it } from "vitest";

import { isInvitationExpired } from "@/lib/invitations";

describe("isInvitationExpired (display only; OI-54)", () => {
  const now = new Date("2026-11-23T12:00:00Z");

  it("treats the exact expiry instant as expired, matching the database (expires_at <= now)", () => {
    expect(isInvitationExpired("2026-11-23T12:00:00Z", now)).toBe(true);
    expect(isInvitationExpired("2026-11-23T11:59:59Z", now)).toBe(true);
    expect(isInvitationExpired("2026-11-23T12:00:01Z", now)).toBe(false);
  });
});
