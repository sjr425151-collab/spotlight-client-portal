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

  it("never logs OTPs, tokens, or secrets (CLAUDE.md §4)", () => {
    const offenders = sources.filter(({ text }) =>
      /console\.\w+\([^)]*\b(?:token|code|secret|otp|password)\b/i.test(text),
    );
    expect(offenders.map(({ path }) => path)).toEqual([]);
  });
});
