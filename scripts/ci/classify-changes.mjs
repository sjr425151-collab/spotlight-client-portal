#!/usr/bin/env node
/**
 * Path-aware, fail-closed CI scoping (OI-70; docs/DEVELOPMENT.md §5).
 *
 * classify  Decide whether a pull request is "docs" (every changed path is documentation)
 *           or "full" (anything else). Any doubt, error, or non-PR event means "full".
 * evaluate  Decide the aggregate "CI result" from the scope and each job's result. A suite
 *           that did not run is reported as "not run", never as passed.
 *
 * CI runs this file from the pull request's BASE commit, so a pull request cannot change
 * how its own changes are classified or evaluated.
 */
import { execFileSync } from "node:child_process";
import { appendFileSync } from "node:fs";
import { pathToFileURL } from "node:url";

/** Documentation paths that may skip the heavy suites. Everything else is "full". */
export const DOCS_ONLY_PATTERNS = [/^docs\/(?:[^/]+\/)*[^/]+\.md$/, /^[^/]+\.md$/];

/** Suites that run on every change, and suites that run only for "full" changes. */
export const ALWAYS_SUITES = ["quality", "audit", "secrets"];
export const FULL_ONLY_SUITES = ["e2e", "lighthouse"];

export const SUITE_LABELS = {
  quality: "Lint, types, format, unit tests",
  audit: "Dependency audit",
  secrets: "Secret scan (gitleaks, full history)",
  e2e: "Database, integration, and e2e tests (local Supabase)",
  lighthouse: "Lighthouse budgets (spec 02 §7)",
};

function isSafePath(path) {
  return (
    typeof path === "string" &&
    path.length > 0 &&
    !path.startsWith("/") &&
    !path.split("/").some((segment) => segment === "" || segment === "." || segment === "..")
  );
}

/**
 * @param {{ event: string, files: unknown }} input
 * @returns {{ scope: "docs" | "full", reason: string }}
 */
export function classifyChanges({ event, files }) {
  if (event !== "pull_request") {
    return { scope: "full", reason: `event "${event}" always runs every suite` };
  }
  if (!Array.isArray(files) || files.length === 0) {
    return { scope: "full", reason: "the changed-file list is empty or unavailable" };
  }
  for (const path of files) {
    if (!isSafePath(path)) {
      return { scope: "full", reason: "a changed path could not be interpreted safely" };
    }
    if (!DOCS_ONLY_PATTERNS.some((pattern) => pattern.test(path))) {
      return { scope: "full", reason: `non-documentation change: ${path}` };
    }
  }
  return { scope: "docs", reason: `all ${files.length} changed path(s) are documentation` };
}

/**
 * @param {{ changesResult: string, scope: string, results: Record<string, string> }} input
 * @returns {{ ok: boolean, failures: string[], rows: { suite: string, result: string, status: string }[] }}
 */
export function evaluateResults({ changesResult, scope, results }) {
  const failures = [];
  const rows = [];

  if (changesResult !== "success") {
    failures.push(`change classification did not succeed (${changesResult || "missing"})`);
  }
  if (scope !== "docs" && scope !== "full") {
    failures.push(`unknown change scope "${scope || "missing"}"`);
  }

  for (const suite of [...ALWAYS_SUITES, ...FULL_ONLY_SUITES]) {
    const result = results[suite] || "missing";
    const required = ALWAYS_SUITES.includes(suite) || scope !== "docs";
    let status;
    if (result === "success") {
      status = "ran: passed";
    } else if (!required && result === "skipped") {
      status = "not run (documentation-only change)";
    } else {
      status = required ? `required: ${result}` : `unexpected: ${result}`;
      failures.push(`${SUITE_LABELS[suite]}: ${result}`);
    }
    rows.push({ suite: SUITE_LABELS[suite], result, status });
  }

  return { ok: failures.length === 0, failures, rows };
}

function changedFiles(base, head) {
  const output = execFileSync(
    "git",
    ["diff", "--name-only", "--no-renames", "-z", `${base}...${head}`],
    { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
  );
  return output.split("\0").filter((path) => path.length > 0);
}

function runClassify(env) {
  let result;
  try {
    const base = env.BASE_SHA || "";
    const head = env.HEAD_SHA || "";
    if (env.EVENT_NAME === "pull_request" && !/^[0-9a-f]{40}$/.test(base)) {
      result = { scope: "full", reason: "the base commit is unknown" };
    } else if (env.EVENT_NAME === "pull_request" && !/^[0-9a-f]{40}$/.test(head)) {
      result = { scope: "full", reason: "the head commit is unknown" };
    } else {
      const files = env.EVENT_NAME === "pull_request" ? changedFiles(base, head) : [];
      result = classifyChanges({ event: env.EVENT_NAME || "", files });
    }
  } catch {
    result = { scope: "full", reason: "the changed files could not be listed" };
  }
  process.stdout.write(`scope=${result.scope}\n`);
  process.stderr.write(`CI scope: ${result.scope} (${result.reason})\n`);
}

function runEvaluate(env) {
  const scope = env.SCOPE || "";
  const { ok, failures, rows } = evaluateResults({
    changesResult: env.CHANGES_RESULT || "",
    scope,
    results: Object.fromEntries(
      [...ALWAYS_SUITES, ...FULL_ONLY_SUITES].map((suite) => [
        suite,
        env[`RESULT_${suite.toUpperCase()}`] || "",
      ]),
    ),
  });
  const summary = [
    `### CI result: ${ok ? "passed" : "failed"} (scope: ${scope || "unknown"})`,
    "",
    "| Suite | Job result | Status |",
    "|---|---|---|",
    ...rows.map((row) => `| ${row.suite} | ${row.result} | ${row.status} |`),
    "",
    scope === "docs"
      ? "Documentation-only change: suites marked *not run* did not execute and are not reported as passed."
      : "Full change: every suite was required.",
    "",
  ].join("\n");
  if (env.GITHUB_STEP_SUMMARY) appendFileSync(env.GITHUB_STEP_SUMMARY, summary);
  process.stderr.write(summary);
  if (!ok) {
    process.stderr.write(`\nFailing: ${failures.join("; ")}\n`);
    process.exitCode = 1;
  }
}

const invokedDirectly =
  process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  const command = process.argv[2];
  if (command === "classify") {
    runClassify(process.env);
  } else if (command === "evaluate") {
    runEvaluate(process.env);
  } else {
    process.stderr.write("usage: classify-changes.mjs classify|evaluate\n");
    process.exitCode = 2;
  }
}
