import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { auditAction } from "@/domain/contracts/audit-actions";

/**
 * PWP-1 (AUTH-021; 04 §4A; OI-109; OD-9): golden vectors for the canonical serializations,
 * computed independently of the database, and lexical guards for the fixture labels and the
 * internal constructors (FD-14 style).
 */

const PWP1_MIGRATION = "20261128100000_pwp1_contract_instruments.sql";
const migrations = readdirSync("supabase/migrations").filter((f) => f.endsWith(".sql"));
const read = (f: string) => readFileSync(join("supabase/migrations", f), "utf8");
const seed = readFileSync("supabase/seed.sql", "utf8");

const len = (s: string) => Buffer.byteLength(s, "utf8");
const sha = (s: string) => createHash("sha256").update(s, "utf8").digest("hex");

/** spotlight.contract_instrument.v1 (the migration's private.contract_instrument_sha256). */
function instrumentSha(
  kind: string,
  pkg: string | null,
  version: number,
  title: string,
  body: string,
  provisions: string[],
): string {
  return sha(
    "spotlight.contract_instrument.v1" +
      `|kind${len(kind)}:${kind}` +
      `|pkg${pkg === null ? "-" : `${len(pkg)}:${pkg}`}` +
      `|v${version}` +
      `|t${len(title)}:${title}` +
      `|b${len(body)}:${body}` +
      `|n${provisions.length}` +
      provisions.map((p) => `|p${len(p)}:${p}`).join(""),
  );
}

type Pair = readonly [string, string];

/** spotlight.contract_bundle.v1 (the migration's private.contract_bundle_sha256). */
function bundleSha(
  pkg: string,
  version: number,
  title: string,
  components: readonly [Pair, Pair, Pair, Pair],
  scope: readonly [number, string],
  map: string[],
): string {
  const [a, ip, im, is] = components;
  return sha(
    "spotlight.contract_bundle.v1" +
      `|k${len(pkg)}:${pkg}` +
      `|v${version}` +
      `|t${len(title)}:${title}` +
      `|a${a[0]}:${a[1]}` +
      `|ip${ip[0]}:${ip[1]}` +
      `|im${im[0]}:${im[1]}` +
      `|is${is[0]}:${is[1]}` +
      `|s${scope[0]}:${scope[1]}` +
      `|n${map.length}` +
      map.map((m, i) => `|m${i + 1}:${len(m)}:${m}`).join(""),
  );
}

describe("PWP-1 golden vectors (OI-109)", () => {
  it("spotlight.contract_instrument.v1 reproduces the recorded vectors", () => {
    expect(
      instrumentSha(
        "package_specification",
        "essential",
        1,
        "Golden title",
        "Golden body line 1\nline 2 — ünïcödé",
        ["GV-P1", "GV-P2"],
      ),
    ).toBe("5f94b322b79461dc965b98f47db3dddf79bb2e9e49b93945a8ffa8055c8a4b0d");
    expect(instrumentSha("shared_terms", null, 3, "T", "B", ["X"])).toBe(
      "3cc806a6959c8b922616020221aa679737cc23aac35a9ad82f92fbaba5f1bf41",
    );
  });

  it("spotlight.contract_bundle.v1 reproduces the recorded vector", () => {
    expect(
      bundleSha(
        "essential",
        2,
        "Golden bundle",
        [
          ["11111111-1111-4111-8111-111111111111", "a".repeat(64)],
          ["22222222-2222-4222-8222-222222222222", "b".repeat(64)],
          ["33333333-3333-4333-8333-333333333333", "c".repeat(64)],
          ["44444444-4444-4444-8444-444444444444", "d".repeat(64)],
        ],
        [1, "e".repeat(64)],
        ["GV-P1", "GV-P2", "GV-P1"],
      ),
    ).toBe("0c91eddd2cbb598687711b22e575a2b3bd5769fec7f223060e6bc799c0e038db");
  });

  it("is sensitive to every field (no field is silently dropped)", () => {
    const base = instrumentSha("shared_terms", null, 3, "T", "B", ["X"]);
    expect(instrumentSha("shared_terms", null, 4, "T", "B", ["X"])).not.toBe(base);
    expect(instrumentSha("shared_terms", null, 3, "T2", "B", ["X"])).not.toBe(base);
    expect(instrumentSha("shared_terms", null, 3, "T", "B2", ["X"])).not.toBe(base);
    expect(instrumentSha("shared_terms", null, 3, "T", "B", ["Y"])).not.toBe(base);
    expect(instrumentSha("shared_terms", "essential", 3, "T", "B", ["X"])).not.toBe(base);
    // Length prefixes keep field boundaries unambiguous.
    expect(instrumentSha("shared_terms", null, 3, "TB", "", ["X"])).not.toBe(
      instrumentSha("shared_terms", null, 3, "T", "B", ["X"]),
    );
  });
});

describe("PWP-1 lexical guards (OD-9, FD-14 style)", () => {
  const INSTRUMENT_LABEL = /not[\W_]*a[\W_]*contract[\W_]*(instrument|bundle)/i;
  const CONSTRUCTORS = /construct[\W_]*contract[\W_]*(instrument|bundle)/i;

  it("only the PWP-1 migration and the seed carry the PWP-1 fixture labels", () => {
    expect(migrations).toContain(PWP1_MIGRATION);
    for (const f of migrations) {
      if (f === PWP1_MIGRATION) continue;
      expect(INSTRUMENT_LABEL.test(read(f)), f).toBe(false);
    }
    expect(INSTRUMENT_LABEL.test(read(PWP1_MIGRATION))).toBe(true);
    expect(INSTRUMENT_LABEL.test(seed)).toBe(true);
  });

  it("no migration other than the PWP-1 migration names the internal constructors", () => {
    for (const f of migrations) {
      if (f === PWP1_MIGRATION) continue;
      expect(CONSTRUCTORS.test(read(f)), f).toBe(false);
    }
  });

  it("the PWP-1 migration never calls an internal constructor with the fixture flag", () => {
    const sql = read(PWP1_MIGRATION);
    const calls = [
      ...sql.matchAll(/private\.construct_contract_(instrument|bundle)\(([^;]*?)\)\s*;/gs),
    ];
    expect(calls.length).toBeGreaterThan(0);
    for (const c of calls) expect(c[2], c[0]).toMatch(/,\s*false\s*$/);
    expect(sql).not.toMatch(/construct_contract_(instrument|bundle)\([^;]*,\s*true\s*\)/s);
  });

  it("the seed creates fixtures only through the constructors, labeled, after the development classification", () => {
    expect(seed).not.toMatch(/insert\s+into\s+private\.contract_/i);
    const first = seed.indexOf("select private.construct_contract_instrument(");
    expect(first).toBeGreaterThan(seed.indexOf("insert into private.environment_settings"));
    const block = seed.slice(first);
    expect(block).toMatch(/'TEST FIXTURE — NOT A CONTRACT INSTRUMENT \(/);
    expect(block).toMatch(/'TEST FIXTURE — NOT A CONTRACT BUNDLE \(/);
    for (const c of block.matchAll(
      /select private\.construct_contract_(instrument|bundle)\(([^;]*?)\)\s*(\nfrom[^;]*)?;/gs,
    )) {
      expect(c[2], c[0]).toMatch(/,\s*true\s*$/);
    }
  });

  it("synthetic offending inputs are caught (no vacuous pass)", () => {
    expect(INSTRUMENT_LABEL.test("select 'TEST FIXTURE — NOT A CONTRACT BUNDLE';")).toBe(true);
    expect(INSTRUMENT_LABEL.test("select 'not a ' || 'contract instrument';")).toBe(true);
    expect(
      CONSTRUCTORS.test(
        "select private.construct_contract_instrument('x', null, 't', 'b', array['p'], true);",
      ),
    ).toBe(true);
    expect(INSTRUMENT_LABEL.test("create table private.example (id int);")).toBe(false);
  });
});

describe("PWP-1 audit actions (04 §4A)", () => {
  it("are registered", () => {
    for (const a of [
      "contract_instrument.created",
      "contract_instrument.load_rejected",
      "contract_bundle.sealed",
      "contract_bundle.seal_rejected",
      "contract_bundle.approval_recorded",
      "contract_bundle.approval_rejected",
      "contract_bundle.activated",
      "contract_bundle.activation_rejected",
      "contract_bundle.withdrawn",
      "contract_bundle.withdrawal_rejected",
    ]) {
      expect(auditAction(a).category).toBe("general");
    }
  });

  it("every audit action the PWP-1 migration writes is registered", () => {
    const sql = read(PWP1_MIGRATION);
    const written = [...sql.matchAll(/record_audit_event\('([a-z_.]+)'/g)].map((m) => m[1] ?? "");
    expect(written.length).toBeGreaterThan(0);
    for (const a of written) expect(() => auditAction(a), a).not.toThrow();
  });
});
