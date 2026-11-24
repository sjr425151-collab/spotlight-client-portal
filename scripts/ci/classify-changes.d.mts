// Type declarations for classify-changes.mjs (used by tests/unit/ci-classifier.test.ts).

export declare const DOCS_ONLY_PATTERNS: readonly RegExp[];
export declare const ALWAYS_SUITES: readonly string[];
export declare const FULL_ONLY_SUITES: readonly string[];
export declare const SUITE_LABELS: Readonly<Record<string, string>>;

export declare function classifyChanges(input: { event: string; files: unknown }): {
  scope: "docs" | "full";
  reason: string;
};

export declare function evaluateResults(input: {
  changesResult: string;
  scope: string;
  results: Record<string, string>;
}): {
  ok: boolean;
  failures: string[];
  rows: { suite: string; result: string; status: string }[];
};
