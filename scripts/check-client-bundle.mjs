#!/usr/bin/env node
/**
 * T-SEC-01 / spec 02 §9 rule 3: fail if browser-delivered build output contains
 * secret-shaped strings or the value of any server-only environment variable.
 *
 * Run after `pnpm build`. Scans .next/static (everything shipped to the browser).
 * Output names files and rules only; it never prints matched values.
 */
import { readdir, readFile, stat } from "node:fs/promises";
import { join, relative } from "node:path";

const root = new URL("..", import.meta.url).pathname;
const staticDir = join(root, ".next", "static");

const patterns = [
  ["Stripe secret or restricted key", /\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{8,}/],
  ["Stripe webhook secret", /\bwhsec_[A-Za-z0-9]{8,}/],
  ["Resend API key", /\bre_[A-Za-z0-9_]{20,}/],
  ["Supabase service role marker", /service_role/],
  ["Private key block", /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
];

// Values of server-only variables present in this environment must never reach the client.
const serverOnlyValues = Object.entries(process.env)
  .filter(([name, value]) => !name.startsWith("NEXT_PUBLIC_") && value && value.length >= 16)
  .filter(([name]) => /(?:SECRET|TOKEN|PASSWORD|PRIVATE|SERVICE_ROLE|API_KEY)/.test(name));

async function* walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) yield* walk(path);
    else if (/\.(?:js|mjs|css|html|json|txt|map)$/.test(entry.name)) yield path;
  }
}

try {
  await stat(staticDir);
} catch {
  console.error("No .next/static directory found. Run `pnpm build` first.");
  process.exit(2);
}

const findings = [];
let scanned = 0;
for await (const file of walk(staticDir)) {
  scanned += 1;
  const content = await readFile(file, "utf8");
  for (const [rule, pattern] of patterns) {
    if (pattern.test(content)) findings.push(`${relative(root, file)}: ${rule}`);
  }
  for (const [name, value] of serverOnlyValues) {
    if (content.includes(value)) findings.push(`${relative(root, file)}: value of ${name}`);
  }
}

if (findings.length > 0) {
  console.error(`Client bundle check FAILED (${findings.length} finding(s)):`);
  for (const finding of findings) console.error(`  - ${finding}`);
  process.exit(1);
}

console.log(`Client bundle check passed: ${scanned} files scanned, no secrets found.`);
