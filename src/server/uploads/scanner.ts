import "server-only";

import { EICAR_SIGNATURE } from "@/domain/uploads";

/**
 * Malware scanner contract (WP-C; spec 05 §5.3 rule 2; DEP-07).
 *
 * The vendor is selected after provider and cost verification (DEP-07). Until then the only
 * implementation is a local mock, which is used only when APP_ENV is development or test.
 * The database independently refuses to release a file on a mock result unless it is a
 * seeded development or test database (`private.scanner_permitted`), so a mock "clean"
 * cannot release anything in a hosted environment even if this guard were bypassed.
 */
export interface ScanVerdict {
  readonly verdict: "clean" | "malicious" | "error";
  readonly engineVersion: string;
  readonly signature?: string;
}

export interface MalwareScanner {
  /** Database scanner identifier: lowercase snake_case. */
  readonly id: string;
  scan(bytes: Uint8Array): Promise<ScanVerdict>;
}

/** Flags the public EICAR test string; everything else is reported clean. Local only. */
export const mockScanner: MalwareScanner = {
  id: "mock_scanner",
  async scan(bytes) {
    const text = new TextDecoder("latin1").decode(bytes);
    return text.includes(EICAR_SIGNATURE)
      ? { verdict: "malicious", engineVersion: "mock-1", signature: "EICAR-Test-File" }
      : { verdict: "clean", engineVersion: "mock-1" };
  },
};

/** No scanner outside development and test: uploads stay in quarantine (DEP-07). */
export function scannerFor(appEnv: string): MalwareScanner | null {
  return appEnv === "development" || appEnv === "test" ? mockScanner : null;
}
