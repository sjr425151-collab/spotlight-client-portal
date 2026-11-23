import { describe, expect, it } from "vitest";

import { invitationDescription, isInvitationExpired } from "@/lib/invitations";

describe("isInvitationExpired (display only; OI-54)", () => {
  const now = new Date("2026-11-23T12:00:00Z");

  it("treats the exact expiry instant as expired, matching the database (expires_at <= now)", () => {
    expect(isInvitationExpired("2026-11-23T12:00:00Z", now)).toBe(true);
    expect(isInvitationExpired("2026-11-23T11:59:59Z", now)).toBe(true);
    expect(isInvitationExpired("2026-11-23T12:00:01Z", now)).toBe(false);
  });
});

describe("invitationDescription (Phase 2 finding D3)", () => {
  it("never describes a staff invitation as a project invitation", () => {
    expect(invitationDescription("staff", "admin")).toContain("team as an Admin");
    expect(invitationDescription("staff", "owner")).toContain("team as an Owner");
    expect(invitationDescription("staff", "admin")).not.toContain("project");
  });

  it("describes client invitations as project invitations", () => {
    expect(invitationDescription("client", null)).toBe("You have been invited to a new project.");
  });
});
