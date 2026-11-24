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
    expect(unguarded).toEqual([]);
  });

  it("WP-C code has no payment path: publication and recovery never call Stripe (T-PUB-18)", () => {
    const wpc = sources.filter(({ path }) =>
      /src\/(server\/(uploads|publication|services\/fulfillment)|app\/(portal|staff)\/(projects|queue))/.test(
        path,
      ),
    );
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
