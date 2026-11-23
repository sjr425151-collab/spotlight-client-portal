import type { SupabaseClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import { withDb } from "../support/db";
import { clearMailbox, codeFrom, messageCount, waitForEmail } from "../support/mailpit";
import {
  accessToken,
  adminClient,
  anonClient,
  clientWithToken,
  signInWithCode,
  upgradeToAal2,
} from "../support/local-supabase";

/**
 * Phase 2 integration tests (spec 03 §18 table, INT rows) against the local Supabase stack
 * with the synthetic seed. Real Auth sessions are created with emailed codes from Mailpit.
 */

// Server modules that read request headers are given plain local clients instead.
vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

const OWNER = "owner@example.test";
const ADMIN = "admin@example.test";
const CLIENT_A = "client.a@example.test";
const CLIENT_B = "client.b@example.test";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const PROJECT_B = "20000000-0000-4000-8000-0000000000b0";
const RUN = Date.now().toString(36);

const totpSecrets = new Map<string, string>();
const secretsSeen: string[] = [];

async function resetLocalState() {
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(
      `delete from auth.mfa_factors where user_id in (
         '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002')`,
    );
  });
}

let owner: SupabaseClient;

beforeAll(async () => {
  await resetLocalState();
  owner = await signInWithCode(OWNER);
  await upgradeToAal2(owner, totpSecrets);
});

afterAll(resetLocalState);

async function createClientInvitation(email: string, projectId = PROJECT_A) {
  const { data, error } = await owner.rpc("create_invitation", {
    p_kind: "client",
    p_email: email,
    p_full_name: "Integration Invitee",
    p_project_id: projectId,
  });
  expect(error).toBeNull();
  expect(data.ok).toBe(true);
  secretsSeen.push(data.token);
  return data as { invitation_id: string; token: string };
}

/** Provisions the invitee through Supabase's invite email and signs them in with its code. */
async function invitedUserSession(
  email: string,
  invitation: { invitation_id: string; token: string },
) {
  await clearMailbox(email);
  const { error } = await adminClient().auth.admin.inviteUserByEmail(email, {
    redirectTo: `http://localhost:3100/invite/accept?id=${invitation.invitation_id}&t=${invitation.token}`,
  });
  expect(error).toBeNull();
  const code = codeFrom(await waitForEmail(email));
  secretsSeen.push(code);
  const client = anonClient();
  const { error: verifyError } = await client.auth.verifyOtp({ email, token: code, type: "email" });
  expect(verifyError).toBeNull();
  return client;
}

describe("invitation-only sign-up (T-AUTH-01, T-AUTH-12)", () => {
  it("creates no user for un-invited emails, whatever the client asks for", async () => {
    const email = `uninvited.${RUN}@example.test`;
    const before = await withDb((db) => db.query("select count(*)::int as n from auth.users"));

    const otp = await anonClient().auth.signInWithOtp({
      email,
      options: { shouldCreateUser: true },
    });
    expect(otp.error).not.toBeNull();
    const signUp = await anonClient().auth.signUp({ email, password: `x-${RUN}-Aa1!long` });
    expect(signUp.error).not.toBeNull();
    // Even the secret key cannot provision a user without a pending invitation (hook).
    const invite = await adminClient().auth.admin.inviteUserByEmail(email);
    expect(invite.error).not.toBeNull();

    const after = await withDb((db) => db.query("select count(*)::int as n from auth.users"));
    expect(after.rows[0].n).toBe(before.rows[0].n);
    expect(await messageCount(email)).toBe(0);
  });
});

describe("expired invitations with no cleanup job (OI-54 condition)", () => {
  it("rejects an expired invitation at Auth provisioning, the link check, and acceptance", async () => {
    const email = `expired.${RUN}@example.test`;
    const invitation = await createClientInvitation(email);
    await withDb((db) =>
      db.query(
        "update public.invitations set expires_at = now() - interval '1 second' where id = $1",
        [invitation.invitation_id],
      ),
    );

    // Supabase Auth: the before-user-created hook refuses to create the user.
    const invite = await adminClient().auth.admin.inviteUserByEmail(email, {
      redirectTo: `http://localhost:3100/invite/accept?id=${invitation.invitation_id}&t=${invitation.token}`,
    });
    expect(invite.error).not.toBeNull();
    const users = await withDb((db) =>
      db.query("select count(*)::int as n from auth.users where email = $1", [email]),
    );
    expect(users.rows[0].n).toBe(0);
    expect(await messageCount(email)).toBe(0);

    // The server-side link check used by the page, code entry, and "send me a new code".
    const { checkInvitationLink } = await import("@/server/services/invitations");
    expect(
      await checkInvitationLink(invitation.invitation_id, invitation.token, "203.0.113.30"),
    ).toEqual({
      ok: false,
    });

    // The row is still `pending`: rejection does not depend on cleanup.
    const row = await withDb((db) =>
      db.query("select status from public.invitations where id = $1", [invitation.invitation_id]),
    );
    expect(row.rows[0].status).toBe("pending");
  });
});

describe("invitation acceptance (T-AUTH-02, T-AUTH-06, T-AUTH-07, T-AUTH-08)", () => {
  it("lets exactly one of two concurrent acceptances win (T-AUTH-06)", async () => {
    const email = `concurrent.${RUN}@example.test`;
    const invitation = await createClientInvitation(email);
    const invitee = await invitedUserSession(email, invitation);

    const results = await Promise.all([
      invitee.rpc("accept_invitation", {
        p_invitation_id: invitation.invitation_id,
        p_token: invitation.token,
      }),
      invitee.rpc("accept_invitation", {
        p_invitation_id: invitation.invitation_id,
        p_token: invitation.token,
      }),
    ]);
    expect(results.map((result) => result.data.ok).sort()).toEqual([false, true]);

    const replay = await invitee.rpc("accept_invitation", {
      p_invitation_id: invitation.invitation_id,
      p_token: invitation.token,
    });
    expect(replay.data.ok).toBe(false);
    const memberships = await withDb((db) =>
      db.query(
        "select count(*)::int as n from public.project_memberships where invitation_id = $1",
        [invitation.invitation_id],
      ),
    );
    expect(memberships.rows[0].n).toBe(1);
  });

  it("rejects a different signed-in user and tampered tokens, then locks (T-AUTH-07, T-AUTH-08)", async () => {
    const invitation = await createClientInvitation(`bound.${RUN}@example.test`);
    const clientB = await signInWithCode(CLIENT_B);

    const wrongUser = await clientB.rpc("accept_invitation", {
      p_invitation_id: invitation.invitation_id,
      p_token: invitation.token,
    });
    expect(wrongUser.data.ok).toBe(false);

    const tampered = `${invitation.token.slice(0, -1)}${invitation.token.endsWith("A") ? "B" : "A"}`;
    for (let attempt = 0; attempt < 10; attempt += 1) {
      await adminClient().rpc("check_invitation_link", {
        p_invitation_id: invitation.invitation_id,
        p_token: tampered,
      });
    }
    // After the attempt limit even the genuine token is refused.
    const locked = await adminClient().rpc("check_invitation_link", {
      p_invitation_id: invitation.invitation_id,
      p_token: invitation.token,
    });
    expect(locked.data.ok).toBe(false);
    const row = await withDb((db) =>
      db.query("select failed_attempts from public.invitations where id = $1", [
        invitation.invitation_id,
      ]),
    );
    expect(row.rows[0].failed_attempts).toBeGreaterThanOrEqual(10);
  });
});

describe("live revocation with an unexpired access token", () => {
  it("denies a project after its membership is revoked (T-AUTH-03)", async () => {
    const clientA = await signInWithCode(CLIENT_A);
    const token = await accessToken(clientA);
    const membership = await withDb((db) =>
      db.query(
        `insert into public.project_memberships (project_id, user_id) values ($1, $2) returning id`,
        [PROJECT_B, CLIENT_A_ID],
      ),
    );
    const before = await clientWithToken(token).from("projects").select("id").eq("id", PROJECT_B);
    expect(before.data).toHaveLength(1);

    await withDb((db) =>
      db.query(
        `update public.project_memberships set status = 'revoked', revoked_at = now() where id = $1`,
        [membership.rows[0].id],
      ),
    );
    const exp = JSON.parse(Buffer.from(token.split(".")[1]!, "base64url").toString()).exp as number;
    expect(exp * 1000).toBeGreaterThan(Date.now());
    const after = await clientWithToken(token).from("projects").select("id").eq("id", PROJECT_B);
    expect(after.data).toEqual([]);
  });

  it("denies a deactivated user on the next request (T-AUTH-09)", async () => {
    const clientA = await signInWithCode(CLIENT_A);
    const token = await accessToken(clientA);
    try {
      await withDb((db) =>
        db.query(`update public.profiles set status = 'deactivated' where id = $1`, [CLIENT_A_ID]),
      );
      const projects = await clientWithToken(token).from("projects").select("id");
      expect(projects.data).toEqual([]);
      const ctx = await clientWithToken(token).rpc("auth_context");
      expect(ctx.data.active).toBe(false);
    } finally {
      await withDb((db) =>
        db.query(`update public.profiles set status = 'active' where id = $1`, [CLIENT_A_ID]),
      );
    }
  });

  it("denies a staff session after global sign-out, before token expiry (T-AUTH-10)", async () => {
    const admin = await signInWithCode(ADMIN);
    await upgradeToAal2(admin, totpSecrets);
    const token = await accessToken(admin);
    const before = await clientWithToken(token).from("projects").select("id");
    expect(before.data!.length).toBeGreaterThanOrEqual(2);

    const { error } = await admin.auth.signOut({ scope: "global" });
    expect(error).toBeNull();
    const after = await clientWithToken(token).from("projects").select("id");
    expect(after.data).toEqual([]);
    const ctx = await clientWithToken(token).rpc("auth_context");
    expect(ctx.data.session_active).toBe(false);
  });

  it("rejects staff writes at aal1 (T-AUTH-04)", async () => {
    const admin = await signInWithCode(ADMIN);
    const insert = await admin
      .from("client_businesses")
      .insert({ legal_name: "X", display_name: "X" });
    expect(insert.error).not.toBeNull();
    const invite = await admin.rpc("create_invitation", {
      p_kind: "client",
      p_email: `aal1.${RUN}@example.test`,
      p_full_name: "Nope",
      p_project_id: PROJECT_A,
    });
    expect(invite.data.ok).toBe(false);
  });
});

describe("rate limits (T-AUTH-11)", () => {
  it("stops sending codes past the per-email limit with the same generic outcome", async () => {
    const { requestSignInCode } = await import("@/server/services/sign-in");
    await clearMailbox(CLIENT_B);
    for (let attempt = 0; attempt < 7; attempt += 1) {
      await requestSignInCode({ anon: anonClient(), ip: "203.0.113.10" }, CLIENT_B);
      await new Promise((resolve) => setTimeout(resolve, 1100));
    }
    // signInWithCode(CLIENT_B) above used Supabase directly, so the app limit of 5 applies here.
    expect(await messageCount(CLIENT_B)).toBe(5);
  });

  it("stops sending codes past the per-IP limit", async () => {
    const { requestSignInCode } = await import("@/server/services/sign-in");
    const ip = "203.0.113.20";
    for (let attempt = 0; attempt < 20; attempt += 1) {
      await requestSignInCode({ anon: anonClient(), ip }, `nobody.${attempt}.${RUN}@example.test`);
    }
    await clearMailbox(CLIENT_A);
    await requestSignInCode({ anon: anonClient(), ip }, CLIENT_A);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    expect(await messageCount(CLIENT_A)).toBe(0);
  });
});

describe("storage isolation (T-TEN-03)", () => {
  it("lets client A read only project A objects", async () => {
    const admin = adminClient();
    const pathA = `${PROJECT_A}/it-${RUN}.txt`;
    const pathB = `${PROJECT_B}/it-${RUN}.txt`;
    for (const path of [pathA, pathB]) {
      const { error } = await admin.storage
        .from("project-assets")
        .upload(path, new Blob(["synthetic"]), {
          contentType: "text/plain",
        });
      expect(error).toBeNull();
    }

    const clientA = await signInWithCode(CLIENT_A);
    const bucket = clientA.storage.from("project-assets");
    expect((await bucket.download(pathA)).error).toBeNull();
    expect((await bucket.download(pathB)).error).not.toBeNull();
    expect((await bucket.createSignedUrl(pathB, 60)).error).not.toBeNull();
    expect((await bucket.list(PROJECT_B)).data ?? []).toEqual([]);
    expect((await bucket.createSignedUrl(pathA, 60)).error).toBeNull();
    // Malformed paths are denied, not errors.
    expect((await bucket.download("not-a-uuid/x.txt")).error).not.toBeNull();
  });
});

describe("cross-tenant RPCs with project B IDs (T-TEN-04)", () => {
  it("rejects every action without side effects", async () => {
    const clientA = await signInWithCode(CLIENT_A);
    const membershipB = await withDb((db) =>
      db.query(`select id from public.project_memberships where project_id = $1 limit 1`, [
        PROJECT_B,
      ]),
    );
    const auditBefore = await withDb((db) =>
      db.query("select count(*)::int as n from public.audit_events"),
    );

    const calls = await Promise.all([
      clientA.rpc("create_invitation", {
        p_kind: "client",
        p_email: `x.${RUN}@example.test`,
        p_full_name: "X",
        p_project_id: PROJECT_B,
      }),
      clientA.rpc("revoke_membership", { p_membership_id: membershipB.rows[0].id, p_reason: "x" }),
      clientA.rpc("set_user_status", {
        p_user_id: "00000000-0000-4000-8000-0000000000b1",
        p_status: "deactivated",
        p_reason: "x",
      }),
      clientA.rpc("set_staff_role", { p_user_id: CLIENT_A_ID, p_role: "owner", p_reason: "x" }),
    ]);
    for (const call of calls) expect(call.data?.ok ?? false).toBe(false);
    const writes = await Promise.all([
      clientA.from("projects").update({ name: "hijacked" }).eq("id", PROJECT_B).select(),
      clientA.from("client_businesses").insert({ legal_name: "x", display_name: "x" }),
    ]);
    expect(writes[0].data ?? []).toEqual([]);
    expect(writes[1].error).not.toBeNull();

    const membershipState = await withDb((db) =>
      db.query(`select status from public.project_memberships where id = $1`, [
        membershipB.rows[0].id,
      ]),
    );
    expect(membershipState.rows[0].status).toBe("active");
    const auditAfter = await withDb((db) =>
      db.query("select count(*)::int as n from public.audit_events"),
    );
    expect(auditAfter.rows[0].n).toBe(auditBefore.rows[0].n);
  });
});

describe("audit redaction (T-AUD-03)", () => {
  it("never stores OTPs, invitation tokens, token hashes, cookies, or keys", async () => {
    const { rows } = await withDb((db) =>
      db.query(
        `select coalesce(reason, '') || ' ' || coalesce(user_agent, '') || ' ' || summary::text as text
           from public.audit_events`,
      ),
    );
    const text = rows.map((row: { text: string }) => row.text).join("\n");
    expect(secretsSeen.length).toBeGreaterThan(0);
    for (const secret of secretsSeen) expect(text).not.toContain(secret);
    expect(text).not.toMatch(
      /sb_(?:secret|publishable)_|eyJ[A-Za-z0-9_-]{10,}|\\x[0-9a-f]{64}|sb-[a-z0-9]+-auth-token/,
    );
  });
});
