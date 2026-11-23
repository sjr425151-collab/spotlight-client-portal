/**
 * Spotlight Marketing design tokens (07 §10, OI-12, OI-38).
 *
 * Single source of truth for color values. `src/app/globals.css` mirrors these in the
 * Tailwind `@theme` block, and `tests/unit/tokens.test.ts` fails if the two drift or if
 * any approved text/background pairing drops below WCAG 2.2 AA contrast.
 *
 * STATUS: provisional. The palette is derived from the confirmed official logo (black
 * field, white wordmark, cool blue-white "eclipse" glow). Final brand colors and
 * typography still require Owner approval before production (DEP-08).
 */

export const colors = {
  /** Page background. Near-black, matched to the logo field. */
  canvas: "#05070b",
  /** Default raised surface (cards, panels). */
  surface: "#0c111a",
  /** Hover and nested surfaces. */
  "surface-raised": "#141b27",
  /** Hairline borders and dividers. */
  line: "#222b3a",
  /** Emphasized borders, input outlines. */
  "line-strong": "#626d80",
  /** Primary text. */
  fg: "#f4f6fa",
  /** Secondary text. */
  "fg-muted": "#aab3c2",
  /** Tertiary text, captions. */
  "fg-subtle": "#8691a3",
  /** Eclipse glow: links, focus rings, highlights. */
  accent: "#8ab4ff",
  /** Accent hover state. */
  "accent-strong": "#b9d1ff",
  /** Error text and borders. */
  danger: "#ff8f85",
  /** Success text. */
  success: "#7fe0b5",
  /** Warning text. */
  warning: "#ffd27a",
} as const;

export type ColorToken = keyof typeof colors;

/** Text-on-background pairs that must meet WCAG 2.2 AA (4.5:1) for body text. */
export const textContrastPairs: ReadonlyArray<readonly [ColorToken, ColorToken]> = [
  ["fg", "canvas"],
  ["fg", "surface"],
  ["fg", "surface-raised"],
  ["fg-muted", "canvas"],
  ["fg-muted", "surface"],
  ["fg-muted", "surface-raised"],
  ["fg-subtle", "canvas"],
  ["fg-subtle", "surface"],
  ["accent", "canvas"],
  ["accent", "surface"],
  ["danger", "canvas"],
  ["danger", "surface"],
  ["success", "surface"],
  ["warning", "surface"],
  // Primary button: canvas-colored label on an fg-colored fill.
  ["canvas", "fg"],
  ["canvas", "accent-strong"],
];

/** Non-text UI pairs that must meet WCAG 2.2 AA (3:1), such as focus rings and input borders. */
export const uiContrastPairs: ReadonlyArray<readonly [ColorToken, ColorToken]> = [
  ["accent", "canvas"],
  ["accent", "surface"],
  ["line-strong", "canvas"],
  ["line-strong", "surface"],
  ["line-strong", "surface-raised"],
  ["danger", "surface"],
];

export const motion = {
  /** Standard interaction transition. Disabled under prefers-reduced-motion. */
  durationFast: "150ms",
  durationBase: "240ms",
  easeOut: "cubic-bezier(0.16, 1, 0.3, 1)",
} as const;

/** WCAG 2.x relative luminance of a #rrggbb color. */
export function relativeLuminance(hex: string): number {
  const match = /^#([0-9a-f]{6})$/i.exec(hex);
  if (!match?.[1]) throw new Error(`Expected a #rrggbb color, received ${hex}`);
  const value = match[1];
  const channels = [0, 2, 4].map((offset) => {
    const channel = parseInt(value.slice(offset, offset + 2), 16) / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  const [r = 0, g = 0, b = 0] = channels;
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/** WCAG 2.x contrast ratio between two #rrggbb colors (1 to 21). */
export function contrastRatio(foreground: string, background: string): number {
  const a = relativeLuminance(foreground);
  const b = relativeLuminance(background);
  const [lighter, darker] = a > b ? [a, b] : [b, a];
  return (lighter + 0.05) / (darker + 0.05);
}
