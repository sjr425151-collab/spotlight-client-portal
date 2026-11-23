import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import { LOGO_HEIGHT, LOGO_WIDTH } from "@/components/brand/logo";

const root = new URL("../../", import.meta.url).pathname;

describe("official logo master (OI-38, OI-49)", () => {
  it("is byte-identical to the Owner-confirmed master", () => {
    const bytes = readFileSync(join(root, "public/brand/spotlight-marketing-logo.jpg"));
    expect(createHash("sha256").update(bytes).digest("hex")).toBe(
      "6cc6edb39da3a8a6e5412d14989c590039632aff85e4114812c21a2ce8b2bd3c",
    );
  });

  it("is rendered at its intrinsic 597 x 335 ratio", () => {
    expect([LOGO_WIDTH, LOGO_HEIGHT]).toEqual([597, 335]);
  });
});

/** Future light-theme compatibility (OI-48): colors come only from design tokens. */
describe("token-only colors in UI code", () => {
  function sourceFiles(directory: string): string[] {
    return readdirSync(directory).flatMap((name) => {
      const path = join(directory, name);
      if (statSync(path).isDirectory()) return sourceFiles(path);
      return /\.tsx?$/.test(name) ? [path] : [];
    });
  }

  const files = [
    ...sourceFiles(join(root, "src/app")),
    ...sourceFiles(join(root, "src/components")),
  ];

  it.each(files.map((file) => [file.slice(root.length)]))(
    "%s contains no hard-coded color literals",
    (file) => {
      const source = readFileSync(join(root, file), "utf8");
      expect(source).not.toMatch(/#[0-9a-fA-F]{3,8}\b|\brgba?\(|\bhsla?\(/);
    },
  );
});
