/**
 * SVG sanitizer (WP-C; spec 05 §5.3 rule 3; T-UP-03). Pure TypeScript, no dependencies.
 *
 * Allowlist, not blocklist: the output contains only the shape, gradient, and text elements
 * and presentation attributes below. Everything else is dropped with its content: scripts,
 * event handlers, `style` (elements and attributes), `foreignObject`, animation elements,
 * external references, and every URL other than a same-document `#fragment`. DTDs and
 * entity declarations are refused outright (XXE, entity expansion). The original stays in
 * quarantine; only this output is ever served.
 */

const ALLOWED_ELEMENTS = new Set([
  "svg",
  "g",
  "path",
  "rect",
  "circle",
  "ellipse",
  "line",
  "polyline",
  "polygon",
  "text",
  "tspan",
  "defs",
  "lineargradient",
  "radialgradient",
  "stop",
  "clippath",
  "mask",
  "title",
  "desc",
  "symbol",
  "use",
  "pattern",
]);
const TEXT_ELEMENTS = new Set(["text", "tspan", "title", "desc"]);

const ALLOWED_ATTRIBUTES = new Set([
  "id",
  "class",
  "d",
  "x",
  "y",
  "x1",
  "y1",
  "x2",
  "y2",
  "cx",
  "cy",
  "r",
  "rx",
  "ry",
  "fx",
  "fy",
  "width",
  "height",
  "viewbox",
  "preserveaspectratio",
  "points",
  "transform",
  "offset",
  "fill",
  "fill-opacity",
  "fill-rule",
  "stroke",
  "stroke-width",
  "stroke-opacity",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-miterlimit",
  "stroke-dasharray",
  "stroke-dashoffset",
  "opacity",
  "stop-color",
  "stop-opacity",
  "gradientunits",
  "gradienttransform",
  "spreadmethod",
  "patternunits",
  "patterncontentunits",
  "patterntransform",
  "clip-path",
  "clip-rule",
  "clippathunits",
  "mask",
  "maskunits",
  "maskcontentunits",
  "font-family",
  "font-size",
  "font-weight",
  "font-style",
  "text-anchor",
  "dominant-baseline",
  "letter-spacing",
  "word-spacing",
  "dx",
  "dy",
  "visibility",
  "display",
  "xmlns",
  "xmlns:xlink",
  "version",
  "href",
  "xlink:href",
]);
/** Attributes that may carry `url(#id)` and nothing else URL-like. */
const URL_REFERENCE_ATTRIBUTES = new Set(["fill", "stroke", "clip-path", "mask"]);
const HREF_ATTRIBUTES = new Set(["href", "xlink:href"]);
const NAMESPACE_VALUES: Record<string, string> = {
  xmlns: "http://www.w3.org/2000/svg",
  "xmlns:xlink": "http://www.w3.org/1999/xlink",
};

export type SvgSanitizeResult =
  | { readonly ok: true; readonly svg: string; readonly removed: number }
  | { readonly ok: false; readonly code: "svg_invalid" };

const NAMED_ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

/** Decodes XML entities. Returns null for an undeclared named entity (never expanded). */
function decodeEntities(value: string): string | null {
  let failed = false;
  const decoded = value.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);?/gi, (_, body: string) => {
    if (body[0] === "#") {
      const code =
        body[1] === "x" || body[1] === "X"
          ? parseInt(body.slice(2), 16)
          : parseInt(body.slice(1), 10);
      if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) {
        failed = true;
        return "";
      }
      return String.fromCodePoint(code);
    }
    const named = NAMED_ENTITIES[body.toLowerCase()];
    if (named === undefined) failed = true;
    return named ?? "";
  });
  return failed ? null : decoded;
}

const escapeText = (value: string) =>
  value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const escapeAttribute = (value: string) => escapeText(value).replace(/"/g, "&quot;");

/** Removes whitespace and control characters, as browsers do when resolving URLs. */
const compact = (value: string) => value.replace(/[\s\p{Cc}]/gu, "").toLowerCase();

function safeAttribute(name: string, rawValue: string): string | null {
  if (!ALLOWED_ATTRIBUTES.has(name)) return null;
  const value = decodeEntities(rawValue);
  if (value === null || value.length > 10_000) return null;
  const flat = compact(value);
  if (NAMESPACE_VALUES[name] !== undefined) return value === NAMESPACE_VALUES[name] ? value : null;
  if (HREF_ATTRIBUTES.has(name))
    return /^#[A-Za-z_][\w.-]*$/.test(value.trim()) ? value.trim() : null;
  if (/(javascript|vbscript|data):/.test(flat) || flat.includes("expression(")) return null;
  if (flat.includes("url(")) {
    if (!URL_REFERENCE_ATTRIBUTES.has(name)) return null;
    if (!/^url\(#[a-z_][\w.-]*\)$/.test(flat)) return null;
  }
  return value;
}

/**
 * Sanitizes an SVG document. Returns `svg_invalid` when the input is not a single `<svg>`
 * document or uses constructs that cannot be handled safely (DTDs, entities, CDATA).
 */
export function sanitizeSvg(input: string): SvgSanitizeResult {
  if (input.length > 5_000_000) return { ok: false, code: "svg_invalid" };
  const source = input.replace(/^﻿/, "");
  if (/<!DOCTYPE|<!ENTITY|<!\[CDATA\[/i.test(source)) return { ok: false, code: "svg_invalid" };

  const tokens =
    /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<\/\s*([A-Za-z][\w:.-]*)\s*>|<([A-Za-z][\w:.-]*)((?:\s+[^\s=/>]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*(\/?)>|([^<]+)|(<)/g;
  const attributePattern = /([^\s=/>]+)(?:\s*=\s*("[^"]*"|'[^']*'|[^\s"'=<>`]+))?/g;

  const out: string[] = [];
  const stack: string[] = [];
  let skipDepth = 0;
  let removed = 0;
  let sawRoot = false;
  let rootClosed = false;

  for (const match of source.matchAll(tokens)) {
    const [whole, endName, startName, attrs = "", selfClose, text, strayLt] = match;
    if (strayLt) return { ok: false, code: "svg_invalid" };
    if (whole.startsWith("<!--") || whole.startsWith("<?")) continue;

    if (text !== undefined) {
      if (skipDepth > 0) continue;
      const current = stack.at(-1);
      if (current && TEXT_ELEMENTS.has(current)) {
        const decoded = decodeEntities(text);
        if (decoded === null) return { ok: false, code: "svg_invalid" };
        out.push(escapeText(decoded));
      } else if (text.trim() !== "") {
        removed++;
      }
      continue;
    }

    if (startName !== undefined) {
      const name = startName.toLowerCase();
      if (skipDepth > 0) {
        if (!selfClose) skipDepth++;
        continue;
      }
      if (
        rootClosed ||
        (!sawRoot && name !== "svg") ||
        (sawRoot && name === "svg" && stack.length === 0)
      ) {
        return { ok: false, code: "svg_invalid" };
      }
      if (!ALLOWED_ELEMENTS.has(name)) {
        removed++;
        if (!selfClose) skipDepth = 1;
        continue;
      }
      sawRoot = true;
      const kept: string[] = [];
      for (const [, rawName = "", rawValue] of attrs.matchAll(attributePattern)) {
        const attrName = rawName.toLowerCase();
        const value = rawValue === undefined ? "" : rawValue.replace(/^["']|["']$/g, "");
        const safe = safeAttribute(attrName, value);
        if (safe === null) {
          removed++;
          continue;
        }
        kept.push(`${rawName}="${escapeAttribute(safe)}"`);
      }
      if (name === "svg" && stack.length === 0 && !kept.some((a) => a.startsWith("xmlns="))) {
        kept.unshift(`xmlns="${NAMESPACE_VALUES.xmlns}"`);
      }
      out.push(`<${startName}${kept.length ? " " + kept.join(" ") : ""}${selfClose ? "/>" : ">"}`);
      if (!selfClose) stack.push(name);
      else if (name === "svg" && stack.length === 0) rootClosed = true;
      continue;
    }

    if (endName !== undefined) {
      if (skipDepth > 0) {
        skipDepth--;
        continue;
      }
      const name = endName.toLowerCase();
      if (stack.at(-1) !== name) return { ok: false, code: "svg_invalid" };
      stack.pop();
      out.push(`</${endName}>`);
      if (stack.length === 0) rootClosed = true;
    }
  }

  if (!sawRoot || stack.length > 0 || skipDepth > 0) return { ok: false, code: "svg_invalid" };
  return { ok: true, svg: out.join(""), removed };
}
