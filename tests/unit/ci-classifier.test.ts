import { describe, expect, it } from "vitest";

import { classifyChanges, evaluateResults } from "../../scripts/ci/classify-changes.mjs";

/** OI-70: path-aware CI must fail closed and never report an unexecuted suite as passed. */
describe("CI change classification (OI-70)", () => {
  const pr = (files: unknown) => classifyChanges({ event: "pull_request", files });

  it("treats documentation-only pull requests as docs", () => {
    expect(pr(["docs/04-AGREEMENT-AND-BILLING.md"]).scope).toBe("docs");
    expect(pr(["README.md", "CLAUDE.md", "OPEN-ISSUES.md"]).scope).toBe("docs");
    expect(pr(["docs/proposals/ai-operations/AI-OPERATIONS-ARCHITECTURE.md"]).scope).toBe("docs");
  });

  it("runs everything for any non-documentation path", () => {
    for (const path of [
      "src/app/page.tsx",
      "supabase/migrations/20261124000000_x.sql",
      ".github/workflows/ci.yml",
      "scripts/ci/classify-changes.mjs",
      "package.json",
      "pnpm-lock.yaml",
      "docs/diagram.png",
      "docs/notes.txt",
      "src/README.md",
      "tests/unit/README.md",
    ]) {
      expect(pr(["docs/01-PROJECT-OVERVIEW.md", path]).scope, path).toBe("full");
    }
  });

  it("runs everything for events other than pull requests", () => {
    expect(classifyChanges({ event: "push", files: ["README.md"] }).scope).toBe("full");
    expect(classifyChanges({ event: "workflow_dispatch", files: ["README.md"] }).scope).toBe(
      "full",
    );
    expect(classifyChanges({ event: "", files: ["README.md"] }).scope).toBe("full");
  });

  it("fails closed on empty, missing, or unsafe input", () => {
    expect(pr([]).scope).toBe("full");
    expect(pr(undefined).scope).toBe("full");
    expect(pr("README.md").scope).toBe("full");
    expect(pr([""]).scope).toBe("full");
    expect(pr(["/README.md"]).scope).toBe("full");
    expect(pr(["docs/../src/x.md"]).scope).toBe("full");
    expect(pr(["docs//x.md"]).scope).toBe("full");
    expect(pr([42]).scope).toBe("full");
  });
});

describe("CI result evaluation (OI-70)", () => {
  const allPassed = {
    quality: "success",
    audit: "success",
    secrets: "success",
    e2e: "success",
    lighthouse: "success",
  };

  it("passes a full change only when every suite passed", () => {
    expect(
      evaluateResults({ changesResult: "success", scope: "full", results: allPassed }).ok,
    ).toBe(true);
    for (const suite of Object.keys(allPassed)) {
      for (const result of ["skipped", "failure", "cancelled", ""]) {
        const outcome = evaluateResults({
          changesResult: "success",
          scope: "full",
          results: { ...allPassed, [suite]: result },
        });
        expect(outcome.ok, `${suite}=${result}`).toBe(false);
      }
    }
  });

  it("reports skipped heavy suites as not run for docs-only changes", () => {
    const outcome = evaluateResults({
      changesResult: "success",
      scope: "docs",
      results: { ...allPassed, e2e: "skipped", lighthouse: "skipped" },
    });
    expect(outcome.ok).toBe(true);
    const statuses = outcome.rows.map((row) => row.status);
    expect(statuses.filter((status) => status.startsWith("not run"))).toHaveLength(2);
    expect(outcome.rows.find((row) => row.result === "skipped")?.status).not.toMatch(/pass/);
  });

  it("still requires the always-run suites for docs-only changes", () => {
    for (const suite of ["quality", "audit", "secrets"]) {
      const outcome = evaluateResults({
        changesResult: "success",
        scope: "docs",
        results: { ...allPassed, e2e: "skipped", lighthouse: "skipped", [suite]: "skipped" },
      });
      expect(outcome.ok, suite).toBe(false);
    }
  });

  it("fails when a heavy suite ran and failed, even for docs-only changes", () => {
    const outcome = evaluateResults({
      changesResult: "success",
      scope: "docs",
      results: { ...allPassed, e2e: "failure", lighthouse: "skipped" },
    });
    expect(outcome.ok).toBe(false);
  });

  it("fails closed when classification failed or the scope is unknown", () => {
    expect(
      evaluateResults({ changesResult: "failure", scope: "full", results: allPassed }).ok,
    ).toBe(false);
    expect(evaluateResults({ changesResult: "success", scope: "", results: allPassed }).ok).toBe(
      false,
    );
    expect(
      evaluateResults({ changesResult: "success", scope: "partial", results: allPassed }).ok,
    ).toBe(false);
  });
});
