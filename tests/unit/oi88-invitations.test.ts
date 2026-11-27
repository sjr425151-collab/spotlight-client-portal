import { readFileSync } from "node:fs";

import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

// next/navigation: redirect throws, as it does in Next.js, so a guard or action stops.
class Redirect extends Error {
  constructor(public readonly to: string) {
    super(`redirect:${to}`);
  }
}
vi.mock("next/navigation", () => ({
  redirect: (to: string) => {
    throw new Redirect(to);
  },
  notFound: () => {
    throw new Redirect("404");
  },
}));

const ctxMock = vi.fn();
vi.mock("@/server/auth/context", () => ({ getAuthContext: () => ctxMock() }));

let memberships: { id: string }[] = [];
vi.mock("@/server/supabase/clients", () => ({
  createUserClient: async () => ({
    from: () => {
      const q = {
        select: () => q,
        eq: () => q,
        limit: async () => ({ data: memberships, error: null }),
      };
      return q;
    },
  }),
}));

const acceptMock = vi.fn();
vi.mock("@/server/services/invitations", () => ({
  acceptInvitation: (...args: unknown[]) => acceptMock(...args),
}));

const { requireClient, requireInvitee } = await import("@/server/auth/guards");
const { acceptListedInvitationAction } = await import("@/app/invitations/actions");
const { messageFor } = await import("@/lib/messages");

type Ctx = {
  staffRole: "owner" | "admin" | null;
  sales: boolean;
  anyStaffRole: boolean;
  active: boolean;
  sessionActive: boolean;
};
function ctx(partial: Partial<Ctx> = {}) {
  return {
    userId: "00000000-0000-4000-8000-000000000009",
    email: "former.client@example.test",
    active: true,
    sessionActive: true,
    mfaFresh: false,
    staffRole: null,
    sales: false,
    anyStaffRole: false,
    aal: "aal1",
    ...partial,
  };
}
async function outcome(fn: () => Promise<unknown>): Promise<string> {
  try {
    await fn();
    return "allowed";
  } catch (error) {
    if (error instanceof Redirect) return error.to;
    throw error;
  }
}
function form(id: string) {
  const data = new FormData();
  data.set("id", id);
  return data;
}

const INVITATION = "30000000-0000-4000-8000-000000000001";

beforeEach(() => {
  memberships = [];
  acceptMock.mockReset();
});

describe("OI-88 option A (AUTH-017): requireInvitee", () => {
  it("admits a signed-in user with no staff role, with or without an active membership", async () => {
    ctxMock.mockResolvedValue(ctx());
    expect(await outcome(requireInvitee)).toBe("allowed");
    memberships = [{ id: "m1" }];
    expect(await outcome(requireInvitee)).toBe("allowed");
  });

  it("refuses every staff role, exactly as requireClient does", async () => {
    ctxMock.mockResolvedValue(ctx({ staffRole: "owner", anyStaffRole: true }));
    expect(await outcome(requireInvitee)).toBe("/staff");
    ctxMock.mockResolvedValue(ctx({ staffRole: "admin", anyStaffRole: true }));
    expect(await outcome(requireInvitee)).toBe("/staff");
    ctxMock.mockResolvedValue(ctx({ sales: true, anyStaffRole: true }));
    expect(await outcome(requireInvitee)).toBe("/sales");
    // An unknown future staff role is never treated as an invitee (fail closed).
    ctxMock.mockResolvedValue(ctx({ anyStaffRole: true }));
    expect(await outcome(requireInvitee)).toBe("/sign-in?notice=inactive");
  });

  it("refuses a signed-out caller, an ended session and an inactive account", async () => {
    ctxMock.mockResolvedValue(null);
    expect(await outcome(requireInvitee)).toBe("/sign-in");
    ctxMock.mockResolvedValue(ctx({ sessionActive: false }));
    expect(await outcome(requireInvitee)).toBe("/sign-in");
    ctxMock.mockResolvedValue(ctx({ active: false }));
    expect(await outcome(requireInvitee)).toBe("/sign-in?notice=inactive");
  });

  it("leaves the strict requireClient unchanged: no membership is still no client access", async () => {
    ctxMock.mockResolvedValue(ctx());
    expect(await outcome(requireClient)).toBe("/sign-in?notice=no_active_project");
  });
});

describe("OI-88 option A (AUTH-017): acceptListedInvitationAction", () => {
  it("accepts through the email-bound path (no link token) and opens the portal", async () => {
    ctxMock.mockResolvedValue(ctx());
    acceptMock.mockResolvedValue({ ok: true, kind: "client", projectId: "p1" });
    expect(await outcome(() => acceptListedInvitationAction(form(INVITATION)))).toBe(
      "/portal?notice=invitation_accepted",
    );
    expect(acceptMock).toHaveBeenCalledTimes(1);
    expect(acceptMock.mock.calls[0]?.slice(1)).toEqual([INVITATION, null]);
  });

  it("sends an accepted staff invitation to MFA enrollment first", async () => {
    ctxMock.mockResolvedValue(ctx());
    acceptMock.mockResolvedValue({ ok: true, kind: "staff", projectId: null });
    expect(await outcome(() => acceptListedInvitationAction(form(INVITATION)))).toBe(
      "/mfa?notice=invitation_accepted",
    );
  });

  it("refuses an invitation the database does not accept, with one generic message", async () => {
    ctxMock.mockResolvedValue(ctx());
    acceptMock.mockResolvedValue({ ok: false });
    expect(await outcome(() => acceptListedInvitationAction(form(INVITATION)))).toBe(
      "/invitations?error=invitation_unavailable",
    );
    expect(messageFor("invitation_unavailable")).toMatch(/no longer available/);
  });

  it("never calls the database for a staff caller or a signed-out caller", async () => {
    ctxMock.mockResolvedValue(ctx({ sales: true, anyStaffRole: true }));
    expect(await outcome(() => acceptListedInvitationAction(form(INVITATION)))).toBe("/sales");
    ctxMock.mockResolvedValue(ctx({ staffRole: "admin", anyStaffRole: true }));
    expect(await outcome(() => acceptListedInvitationAction(form(INVITATION)))).toBe("/staff");
    ctxMock.mockResolvedValue(null);
    expect(await outcome(() => acceptListedInvitationAction(form(INVITATION)))).toBe("/sign-in");
    expect(acceptMock).not.toHaveBeenCalled();
  });
});

describe("OI-88 option A (AUTH-017): messages", () => {
  it("tells the inviter that no email was sent and where the invitee finds the invitation", () => {
    const text = messageFor("invite_existing_user") ?? "";
    expect(text).toContain("already has a portal account");
    expect(text).toContain("no email was sent");
    expect(text).toContain("Your invitations");
    expect(text).not.toMatch(/open the link/i);
  });

  it("points an account without an active project to its invitations, not to an email", () => {
    const text = messageFor("no_active_project") ?? "";
    expect(text).toContain("open your invitations");
    expect(text).not.toMatch(/link in that email/i);
  });

  it("shows the invitations link only on the no-active-project card", () => {
    const page = readFileSync("src/app/sign-in/page.tsx", "utf8");
    expect(page).toMatch(
      /params\.notice === "no_active_project"[\s\S]{0,200}href=\{"\/invitations"/,
    );
  });
});
