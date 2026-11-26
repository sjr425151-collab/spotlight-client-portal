import { describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

import { mockScanner, scannerFor } from "@/server/uploads/scanner";

/**
 * AUTH-008 I-2 fail-closed path: `scannerFor` returns the mocked scanner only for an
 * affirmative `development` or `test` classification. Every other value, including a missing
 * or unknown one, has no scanner, so uploads stay in quarantine (05 §5.3; DEP-07).
 */
describe("scannerFor outside development and test", () => {
  it.each(["development", "test"])("%s has the mocked scanner", (env) => {
    expect(scannerFor(env)).toBe(mockScanner);
  });

  it.each([
    "production",
    "staging",
    "preview",
    "",
    "unknown",
    "Test",
    "DEVELOPMENT",
    " test",
    "test ",
  ])("%j has no scanner (uploads stay quarantined)", (env) => {
    expect(scannerFor(env)).toBeNull();
  });

  it("a missing classification has no scanner", () => {
    expect(scannerFor(undefined as unknown as string)).toBeNull();
  });
});
