import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { AUDIT_ACTIONS, AUDIT_ACTION_PATTERN } from "@/domain/contracts";
import { MAX_IMAGE_SIDE, imageDimensions, processRasterImage } from "@/domain/image-safety";
import {
  INTAKE_ALLOWED_KEYS,
  INTAKE_REQUIRED_KEYS,
  intakeDraftSchema,
  intakeFromForm,
  missingRequiredFields,
} from "@/domain/intake";
import {
  GATE_IDS,
  R1_APPROVAL_LABEL,
  R1_FORBIDDEN_APPROVAL_WORDS,
  parseGateResult,
} from "@/domain/publication";
import { sanitizeSvg } from "@/domain/svg-sanitize";
import {
  CATEGORY_RULES,
  DOCX_MIME,
  EICAR_SIGNATURE,
  QUOTA_BYTES,
  QUOTA_FILES,
  maxBytesFor,
  sanitizeFileName,
  sniffMime,
  validateContent,
} from "@/domain/uploads";

const migrationsDir = join(process.cwd(), "supabase/migrations");
const wpc = readdirSync(migrationsDir)
  .filter((f) => /_wpc_/.test(f))
  .sort()
  .map((f) => readFileSync(join(migrationsDir, f), "utf8"))
  .join("\n");

const bytes = (...parts: (number[] | string)[]) =>
  new Uint8Array(
    parts.flatMap((p) => (typeof p === "string" ? [...p].map((c) => c.charCodeAt(0)) : p)),
  );
const PNG_SIG = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const u32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];
const pngChunk = (type: string, data: number[]) => [
  ...u32(data.length),
  ...bytes(type),
  ...data,
  0,
  0,
  0,
  0,
];
const png = (w: number, h: number, extra: number[] = []) =>
  new Uint8Array([
    ...PNG_SIG,
    ...pngChunk("IHDR", [...u32(w), ...u32(h), 8, 6, 0, 0, 0]),
    ...extra,
    ...pngChunk("IDAT", [1, 2, 3]),
    ...pngChunk("IEND", []),
  ]);
const jpeg = (w: number, h: number) =>
  new Uint8Array([
    0xff,
    0xd8,
    0xff,
    0xe1,
    0x00,
    0x0a,
    ...bytes("Exif"),
    0,
    0,
    0x47,
    0x50, // APP1 (EXIF, "GP")
    0xff,
    0xc0,
    0x00,
    0x0b,
    8,
    (h >> 8) & 255,
    h & 255,
    (w >> 8) & 255,
    w & 255,
    1,
    1,
    0x11,
    0,
    0xff,
    0xda,
    0x00,
    0x02,
    0x12,
    0x34,
    0xff,
    0xd9,
  ]);

describe("upload rules mirror the database (05 §5)", () => {
  it("uses the same per-category types and limits as private.upload_max_bytes", () => {
    const body = /create function private\.upload_max_bytes[\s\S]*?\$\$;/.exec(wpc)?.[0] ?? "";
    const clauses = [
      ...body.matchAll(
        /when p_category = '([a-z_]+)' and p_mime (?:= '([^']+)'|in \(([^)]*)\)) then (\d+)/g,
      ),
    ].map((m) => ({
      category: m[1],
      mimes: m[2] ? [m[2]] : [...(m[3] ?? "").matchAll(/'([^']+)'/g)].map((x) => x[1]),
      max: Number(m[4]),
    }));
    expect(clauses).toEqual(
      Object.entries(CATEGORY_RULES).map(([category, rule]) => ({
        category,
        mimes: [...rule.mimes],
        max: rule.maxBytes,
      })),
    );
    expect(wpc).toContain(`select ${QUOTA_FILES} $$`);
    expect(wpc).toContain(`select ${QUOTA_BYTES}::bigint $$`);
  });

  it("T-UP-01: rejects a disallowed type for a category and 'other' without an exception", () => {
    expect(maxBytesFor("logo", "application/pdf")).toBeNull();
    expect(maxBytesFor("other", "application/zip")).toBeNull();
    expect(maxBytesFor("video", "video/mp4")).toBe(250_000_000);
  });

  it("stores display names only, never path-like", () => {
    expect(sanitizeFileName("../../etc/passwd")).toBe(".._.._etc_passwd");
    expect(sanitizeFileName("a\u0000b\\c")).toBe("a_b_c");
    expect(sanitizeFileName("   ")).toBe("upload");
  });
});

describe("content validation (T-UP-02)", () => {
  it("accepts real content matching the declared type", () => {
    expect(validateContent("logo", "image/png", png(10, 10))).toEqual({
      ok: true,
      detectedMime: "image/png",
    });
    expect(validateContent("photo", "image/jpeg", jpeg(10, 10)).ok).toBe(true);
    expect(validateContent("brand_guidelines", "application/pdf", bytes("%PDF-1.7\n")).ok).toBe(
      true,
    );
    expect(sniffMime(bytes([0, 0, 0, 0x18], "ftypqt  "))).toBe("video/quicktime");
    expect(sniffMime(bytes([0, 0, 0, 0x18], "ftypheic"))).toBe("image/heic");
  });

  it("rejects a renamed executable whatever its declared type", () => {
    expect(validateContent("logo", "image/png", bytes("MZ\x90\x00"))).toEqual({
      ok: false,
      code: "executable",
    });
    expect(validateContent("other", "application/zip", bytes([0x7f], "ELF"))).toEqual({
      ok: false,
      code: "executable",
    });
    expect(validateContent("business_document", "application/pdf", bytes("#!/bin/sh\n"))).toEqual({
      ok: false,
      code: "executable",
    });
  });

  it("rejects an extension/MIME mismatch", () => {
    expect(validateContent("logo", "image/png", jpeg(1, 1))).toEqual({
      ok: false,
      code: "type_mismatch",
    });
    expect(validateContent("business_document", DOCX_MIME, bytes("%PDF-1.4"))).toEqual({
      ok: false,
      code: "type_mismatch",
    });
    expect(validateContent("logo", "image/png", bytes("hello"))).toEqual({
      ok: false,
      code: "unrecognized_type",
    });
  });

  it("rejects polyglots: an archive, PDF, or script embedded in an image", () => {
    const withZip = new Uint8Array([...png(1, 1), 0x50, 0x4b, 0x03, 0x04]);
    const withScript = new Uint8Array([...png(1, 1), ...bytes("<script>alert(1)</script>")]);
    const withPdf = new Uint8Array([...jpeg(1, 1), ...bytes("%PDF-1.4")]);
    expect(validateContent("logo", "image/png", withZip)).toEqual({ ok: false, code: "polyglot" });
    expect(validateContent("logo", "image/png", withScript)).toEqual({
      ok: false,
      code: "polyglot",
    });
    expect(validateContent("photo", "image/jpeg", withPdf)).toEqual({
      ok: false,
      code: "polyglot",
    });
  });

  it("detects DOCX by its package structure, not by the ZIP signature alone", () => {
    const docx = bytes([0x50, 0x4b, 0x03, 0x04], "....[Content_Types].xml....word/document.xml");
    expect(validateContent("business_document", DOCX_MIME, docx).ok).toBe(true);
    expect(
      validateContent("business_document", DOCX_MIME, bytes([0x50, 0x4b, 0x03, 0x04], "plain.zip"))
        .ok,
    ).toBe(false);
  });

  it("ships the EICAR test signature for the mocked scanner", () => {
    expect(EICAR_SIGNATURE).toContain("EICAR-STANDARD-ANTIVIRUS-TEST-FILE");
  });
});

describe("SVG sanitization (T-UP-03)", () => {
  const clean = (svg: string) => {
    const result = sanitizeSvg(svg);
    if (!result.ok) throw new Error("expected sanitization to succeed");
    return result.svg;
  };

  it("removes scripts, event handlers, foreignObject, style, and external references", () => {
    const out = clean(
      `<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><script>alert(2)</script>` +
        `<style>@import url(https://evil.test/x.css)</style>` +
        `<foreignObject><iframe src="https://evil.test"></iframe></foreignObject>` +
        `<rect width="10" height="10" fill="url(https://evil.test/p)" onclick="x()"/>` +
        `<use href="https://evil.test/sprite.svg#a"/><use xlink:href="#ok"/>` +
        `<a href="javascript:alert(3)"><text>click</text></a>` +
        `<image href="data:image/png;base64,AAA"/><animate attributeName="href" to="javascript:x"/>` +
        `<circle r="5" style="background:url(javascript:x)" fill="url(#grad)"/></svg>`,
    );
    for (const active of [
      /script/i,
      /onload/i,
      /onclick/i,
      /foreignObject/i,
      /iframe/i,
      /style/i,
      /evil\.test/,
      /javascript/i,
      /data:/i,
      /<image/i,
      /<animate/i,
      /<a[\s>]/i,
    ]) {
      expect(out).not.toMatch(active);
    }
    expect(out).toContain('fill="url(#grad)"');
    expect(out).toContain('xlink:href="#ok"');
    expect(out).toContain("<rect");
  });

  it("decodes entities before checking, so encoded URLs cannot slip through", () => {
    const out = clean(
      `<svg><use href="&#106;avascript:alert(1)"/><rect fill="u&#114;l(https://x.test)"/></svg>`,
    );
    expect(out).not.toMatch(/javascript|x\.test/i);
  });

  it("refuses DTDs, entities, CDATA, and non-SVG roots", () => {
    expect(sanitizeSvg(`<!DOCTYPE svg [<!ENTITY a "b">]><svg>&a;</svg>`).ok).toBe(false);
    expect(sanitizeSvg(`<svg><![CDATA[<script>x</script>]]></svg>`).ok).toBe(false);
    expect(sanitizeSvg(`<html><svg/></html>`).ok).toBe(false);
    expect(sanitizeSvg(`<svg><g></svg>`).ok).toBe(false);
    expect(sanitizeSvg(`<svg/><svg/>`).ok).toBe(false);
  });

  it("keeps escaped text content and adds the SVG namespace", () => {
    const out = clean(`<svg><text>A &amp; B &lt;c&gt;</text></svg>`);
    expect(out).toBe(
      `<svg xmlns="http://www.w3.org/2000/svg"><text>A &amp; B &lt;c&gt;</text></svg>`,
    );
  });
});

describe("raster image safety (05 §5.3 rule 5)", () => {
  it("reads dimensions from headers and enforces pixel limits", () => {
    expect(imageDimensions("image/png", png(640, 480))).toEqual({ width: 640, height: 480 });
    expect(imageDimensions("image/jpeg", jpeg(300, 200))).toEqual({ width: 300, height: 200 });
    expect(processRasterImage("image/png", png(MAX_IMAGE_SIDE + 1, 10))).toEqual({
      ok: false,
      code: "image_too_large",
    });
    expect(processRasterImage("image/png", png(11_000, 11_000))).toEqual({
      ok: false,
      code: "image_too_large",
    });
  });

  it("strips EXIF (including location) from JPEG and text/EXIF chunks from PNG", () => {
    const j = processRasterImage("image/jpeg", jpeg(10, 10));
    expect(j.ok && new TextDecoder("latin1").decode(j.bytes)).not.toContain("Exif");
    const p = processRasterImage(
      "image/png",
      png(10, 10, pngChunk("tEXt", [...bytes("GPS 42.3")])),
    );
    expect(p.ok && new TextDecoder("latin1").decode(p.bytes)).not.toContain("GPS");
    expect(p.ok && imageDimensions("image/png", p.bytes)).toEqual({ width: 10, height: 10 });
  });

  it("holds formats it cannot process (HEIC) instead of serving them", () => {
    expect(processRasterImage("image/heic", bytes([0, 0, 0, 0x18], "ftypheic")).ok).toBe(false);
  });
});

describe("intake fields mirror the database (05 §3)", () => {
  const keys = (fn: string) =>
    [
      ...(
        new RegExp(`create function private\\.${fn}\\(\\)[\\s\\S]*?array\\[([\\s\\S]*?)\\];`).exec(
          wpc,
        )?.[1] ?? ""
      ).matchAll(/'([a-z_]+)'/g),
    ].map((m) => m[1]);

  it("uses the same allowed and required keys", () => {
    expect(keys("intake_allowed_keys")).toEqual(INTAKE_ALLOWED_KEYS);
    expect(keys("intake_required_keys")).toEqual(INTAKE_REQUIRED_KEYS);
  });

  it("parses form input into bounded content and reports missing required fields", () => {
    const content = intakeFromForm(
      (k) =>
        ({
          business_legal_name: " A LLC ",
          service_areas: "Detroit\n\nAnn Arbor",
          domain_status: "existing",
        })[k] ?? null,
    );
    expect(content).toEqual({
      business_legal_name: "A LLC",
      service_areas: ["Detroit", "Ann Arbor"],
      domain_status: "existing",
    });
    expect(missingRequiredFields(content)).toContain("existing_domain");
    expect(() => intakeDraftSchema.parse({ unknown: "x" })).toThrow();
  });
});

describe("publication gate results (06 §2; T-PUB-04)", () => {
  const all = (passed: boolean) =>
    GATE_IDS.map((gate) => ({ gate, passed, source: "both", reason: null }));

  it("is eligible only when the result says so and all eight gates pass", () => {
    expect(parseGateResult({ eligible: true, release_id: "r", gates: all(true) }).eligible).toBe(
      true,
    );
    expect(parseGateResult({ eligible: true, gates: all(true).slice(0, 7) }).eligible).toBe(false);
    expect(
      parseGateResult({
        eligible: true,
        gates: [...all(true).slice(1), { gate: "G1", passed: false }],
      }).eligible,
    ).toBe(false);
    expect(parseGateResult({ eligible: false, gates: all(true) }).eligible).toBe(false);
    expect(parseGateResult(null).eligible).toBe(false);
    expect(
      parseGateResult({ eligible: true, gates: [{ gate: "G9", passed: true }] }).eligible,
    ).toBe(false);
  });

  it("uses an R1 approval label that does not imply an automatic charge (T-LC-15)", () => {
    for (const word of R1_FORBIDDEN_APPROVAL_WORDS) expect(R1_APPROVAL_LABEL).not.toMatch(word);
  });
});

describe("WP-C audit actions are registered (03 §11)", () => {
  it("registers every action the WP-C migrations write", () => {
    const written = new Set([
      ...[...wpc.matchAll(/record_audit_event\(\s*'([a-z0-9_.]+)'/g)].map((m) => m[1]),
      ...[...wpc.matchAll(/then '((?:intake|approval|deployment)\.[a-z0-9_]+)'/g)].map((m) => m[1]),
      ...[...wpc.matchAll(/else '((?:intake|approval|deployment)\.[a-z0-9_]+)'/g)].map((m) => m[1]),
      "deployment.verification_recorded",
    ]);
    const registered = new Set(
      AUDIT_ACTIONS.filter((a) => a.owner === "WP-C").map((a) => a.action),
    );
    expect([...written].filter((a) => !registered.has(a!))).toEqual([]);
    for (const a of written) expect(a).toMatch(AUDIT_ACTION_PATTERN);
  });
});
