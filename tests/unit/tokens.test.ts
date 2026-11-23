import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

import {
  colors,
  contrastRatio,
  relativeLuminance,
  textContrastPairs,
  uiContrastPairs,
} from "@/design/tokens";

const css = readFileSync(new URL("../../src/app/globals.css", import.meta.url), "utf8");

describe("design tokens", () => {
  it("keeps globals.css @theme colors in sync with tokens.ts", () => {
    const declared = Object.fromEntries(
      [...css.matchAll(/--color-([a-z-]+):\s*(#[0-9a-f]{6});/g)].map((m) => [m[1], m[2]]),
    );
    expect(declared).toEqual(colors);
  });

  it("computes WCAG contrast correctly for reference colors", () => {
    expect(relativeLuminance("#000000")).toBe(0);
    expect(relativeLuminance("#ffffff")).toBeCloseTo(1, 10);
    expect(contrastRatio("#ffffff", "#000000")).toBeCloseTo(21, 5);
  });

  it.each(textContrastPairs)("text %s on %s meets 4.5:1 (WCAG 2.2 AA)", (fg, bg) => {
    expect(contrastRatio(colors[fg], colors[bg])).toBeGreaterThanOrEqual(4.5);
  });

  it.each(uiContrastPairs)("UI element %s on %s meets 3:1 (WCAG 2.2 AA)", (fg, bg) => {
    expect(contrastRatio(colors[fg], colors[bg])).toBeGreaterThanOrEqual(3);
  });

  it("disables animation and transitions under prefers-reduced-motion (T-DES-03)", () => {
    expect(css).toMatch(
      /@media \(prefers-reduced-motion: reduce\)[\s\S]*animation-duration: 0\.01ms/,
    );
  });
});
