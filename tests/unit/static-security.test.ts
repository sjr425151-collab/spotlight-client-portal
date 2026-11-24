import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

/**
 * Static security checks over the source tree (spec 03 §10, §15, §18).
 * They fail the build if a guard, boundary, or forbidden API slips in.
 */
const root = new URL("../..", import.meta.url).pathname;

function filesUnder(directory: string): string[] {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) return filesUnder(path);
    return /\.(?:ts|tsx|mts|mjs)$/.test(name) ? [path] : [];
  });
}

const sources = filesUnder(join(root, "src")).map((path) => ({
  path: relative(root, path),
  text: readFileSync(path, "utf8"),
}));

describe("static security checks", () => {
  it("never uses getSession() for authorization (T-AUTH-13)", () => {
    const offenders = sources.filter(({ text }) => /\bgetSession\s*\(/.test(text));
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("never creates auth users directly: only invitations provision users (03A S-07)", () => {
    const offenders = sources.filter(({ text }) =>
      /admin\s*\.\s*createUser\s*\(|\.signUp\s*\(/.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("keeps the Supabase secret key inside src/server/supabase/admin.ts (spec 03 §9.1 rule 6)", () => {
    const allowed = ["src/config/env-schema.ts", "src/server/supabase/admin.ts"];
    const offenders = sources.filter(
      ({ path, text }) => text.includes("SUPABASE_SECRET_KEY") && !allowed.includes(path),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("never signs or publishes storage URLs: released assets are server-mediated only (review H1)", () => {
    const offenders = sources.filter(({ text }) =>
      /\.createSignedUrls?\s*\(|\.getPublicUrl\s*\(|\.createSignedUploadUrl\s*\(/.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("reads released assets only after the database authorized and audited the access (review H1)", () => {
    const delivery = sources.find(({ path }) => path === "src/server/uploads/delivery.ts")!.text;
    const authorize = delivery.indexOf('rpc("record_asset_access"');
    const read = delivery.indexOf("admin.storage.from(BUCKET).download(");
    const recheck = delivery.indexOf('.from("asset_uploads")');
    expect(authorize).toBeGreaterThan(0);
    expect(read).toBeGreaterThan(authorize);
    expect(recheck).toBeGreaterThan(read);
    expect(delivery).toContain('"Cache-Control": "private, no-store, max-age=0"');
    const route = sources.find(({ path }) =>
      path.endsWith("portal/projects/[projectId]/assets/[uploadId]/route.ts"),
    )!.text;
    expect(route).toContain("downloadAsset(");
    const service = sources.find(({ path }) => path === "src/server/services/fulfillment.ts")!.text;
    expect(service).toMatch(
      /return deliverAsset\(user, await createAdminClient\(\), projectId, uploadId\)/,
    );
    expect(route).not.toMatch(/redirect\(|Response\.redirect|Location/);
    // Storage downloads anywhere in src happen with the secret-key client inside src/server.
    const downloads = sources.filter(({ text }) => /\.download\s*\(/.test(text));
    expect(downloads.every(({ path }) => path.startsWith("src/server/uploads/"))).toBe(true);
  });

  it("imports the admin client only from src/server (spec 03 §10)", () => {
    const offenders = sources.filter(
      ({ path, text }) => !path.startsWith("src/server/") && /supabase\/admin["']/.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("records security events only through the server-side helper (Phase 2 remediation D1)", () => {
    const callers = sources.filter(({ text }) => /record_security_event/.test(text));
    expect(callers.map(({ path }) => path)).toEqual(["src/server/auth/security-events.ts"]);
    const helper = callers[0]!.text;
    expect(helper).toMatch(/createAdminClient\(\)/);
    expect(helper).toMatch(/p_actor_user_id: actorUserId/);
    // No caller may hand a user-scoped client to the helper.
    const passesClient = sources.filter(({ text }) =>
      /recordSecurityEvent\([^)]*,\s*(?:user|db|client)\s*,?\s*\)/.test(text),
    );
    expect(passesClient.map(({ path }) => path)).toEqual([]);
  });

  it("never imports server modules into client components", () => {
    const offenders = sources.filter(
      ({ text }) =>
        /^\s*["']use client["']/m.test(text) &&
        /from\s+["'](?:@\/server\/|@\/config\/env["']|server-only)/.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("does not call Supabase from the browser (no client-side Supabase client)", () => {
    const offenders = sources.filter(
      ({ text }) => /^\s*["']use client["']/m.test(text) && /@supabase\//.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("guards every exported server action (spec 03 §10)", () => {
    const actionFiles = sources.filter(({ text }) => /^\s*["']use server["']/m.test(text));
    expect(actionFiles.length).toBeGreaterThan(0);
    const unguarded: string[] = [];
    for (const { path, text } of actionFiles) {
      const exports = [
        ...text.matchAll(/((?:[ \t]*\/\/[^\n]*\n)*)export async function (\w+)\([^)]*\)[^{]*\{/g),
      ];
      for (const match of exports) {
        const [, comment = "", name] = match;
        const body = text.slice(match.index + match[0].length, match.index + match[0].length + 400);
        const guarded = /^\s*(?:const \w+ = )?await require(?:User|Client|Staff|Owner)\(/.test(
          body,
        );
        const publicAction = /\/\/ public-action: \S/.test(comment);
        if (!guarded && !publicAction) unguarded.push(`${path}: ${name}`);
      }
    }
    expect(unguarded).toEqual([]);
  });

  it("does not use inline style attributes (nonce CSP has no 'unsafe-inline')", () => {
    const offenders = sources.filter(({ text }) => /\sstyle=\{/.test(text));
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("never logs OTPs, tokens, or secrets (CLAUDE.md §3)", () => {
    const offenders = sources.filter(({ text }) =>
      /console\.\w+\([^)]*\b(?:token|code|secret|otp|password)\b/i.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("guards every route handler before it reads the request (spec 03 §10)", () => {
    const routes = sources.filter(({ path }) => /^src\/app\/.*\/route\.ts$/.test(path));
    expect(routes.length).toBeGreaterThan(0);
    const unguarded = routes.flatMap(({ path, text }) =>
      [
        ...text.matchAll(
          /export async function (GET|POST|PUT|PATCH|DELETE)\([^)]*\)[^{]*\{([\s\S]{0,300})/g,
        ),
      ]
        .filter(
          ([, , body]) =>
            !/await require(?:User|Client|Staff|Owner|ProjectAccess)\(/.test(body ?? ""),
        )
        .map(([, method]) => `${path}: ${method}`),
    );
    // The single reviewed exception (WP-B, 04 §11): the Stripe webhook is authenticated by
    // the signature on the raw body, never by a session. It must fail closed without a
    // signing secret before it reads the body, and hand the raw body to the verifier.
    const signatureAuthenticated = ["src/app/api/stripe/webhook/route.ts: POST"];
    expect(unguarded).toEqual(signatureAuthenticated);
    const webhook = routes.find(({ path }) => path === "src/app/api/stripe/webhook/route.ts")!.text;
    expect(webhook.indexOf("if (!secret)")).toBeGreaterThan(0);
    expect(webhook.indexOf("if (!secret)")).toBeLessThan(webhook.indexOf("request.text()"));
    expect(webhook).toMatch(/receiveStripeWebhook\(\s*rawBody,/);
  });

  it("WP-C code has no payment path: publication and recovery never call Stripe (T-PUB-18)", () => {
    const wpc = sources.filter(({ path }) =>
      /src\/(server\/(uploads|publication|services\/fulfillment)|app\/(portal|staff)\/(projects|queue))/.test(
        path,
      ),
    );
    // WP-B's billing page, actions and staff billing section sit under the same routes but are
    // the payment path itself (04); they are covered by tests/unit/wpb-static.test.ts.
    const wpbBilling = (path: string) =>
      /^src\/app\/portal\/projects\/\[projectId\]\/billing\//.test(path) ||
      path === "src/app/staff/projects/[projectId]/billing-section.tsx";
    expect(wpc.filter(({ path }) => wpbBilling(path)).length).toBe(3);
    wpc.splice(0, wpc.length, ...wpc.filter(({ path }) => !wpbBilling(path)));
    expect(wpc.length).toBeGreaterThan(5);
    expect(
      wpc
        .filter(({ text }) =>
          /from\s+["'][^"']*stripe|api\.stripe\.com|STRIPE_|\.rpc\(\s*["'][^"']*(?:invoice|charge|payment)/i.test(
            text,
          ),
        )
        .map(({ path }) => path),
    ).toEqual([]);
  });

  it("has no force, override, bypass, or mark-paid capability anywhere (06 §2; T-PUB-04)", () => {
    const offenders = sources.filter(({ text }) =>
      /\b(?:force_?publish|forcePublish|skip_?gates?|skipGates?|override_?gates?|overrideGates?|bypass_?gates?|mark_?paid|markPaid)\b/i.test(
        text,
      ),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });

  it("uses the mocked malware scanner only in development and test (DEP-07)", () => {
    const scanner = sources.find(({ path }) => path === "src/server/uploads/scanner.ts")!.text;
    expect(scanner).toMatch(
      /appEnv === "development" \|\| appEnv === "test" \? mockScanner : null/,
    );
    const users = sources
      .filter(({ text }) => /\bmockScanner\b/.test(text))
      .map(({ path }) => path);
    expect(users).toEqual(["src/server/uploads/scanner.ts"]);
  });
});
