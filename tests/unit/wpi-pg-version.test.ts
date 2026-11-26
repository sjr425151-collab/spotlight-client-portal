import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

import type * as PgModule from "pg";
import { describe, expect, it } from "vitest";

/**
 * AUTH-008 I-2 carried-forward disposition (iii) (WP-C N-2, WP-B N-1): tests/support/postgrest-sync.ts
 * destroys a timed-out connection through `pg`'s internal `client.connection.stream`, verified
 * against the pinned `pg` 8.16.3 only. This guard fails when the resolved `pg` is any other
 * version. A version change is allowed after the compatibility is re-verified explicitly
 * (the internal still exists and still is the `net.Socket`; the stalled-connect, stalled-query
 * and stalled-close cases in tests/unit/postgrest-ready.test.ts pass) and this constant is
 * updated in the same change. It is not a permanent freeze.
 */
const VERIFIED_PG_VERSION = "8.16.3";

describe("pg version guard", () => {
  it(`the resolved pg is the verified ${VERIFIED_PG_VERSION}`, () => {
    const require = createRequire(import.meta.url);
    const entry = require.resolve("pg");
    const manifest = join(
      entry.slice(0, entry.lastIndexOf("/node_modules/pg/") + 17),
      "package.json",
    );
    const { name, version } = JSON.parse(readFileSync(manifest, "utf8")) as {
      name: string;
      version: string;
    };
    expect(name).toBe("pg");
    expect(
      version,
      `pg ${version} is not the verified ${VERIFIED_PG_VERSION}: re-verify the connection.stream ` +
        "internal used by tests/support/postgrest-sync.ts before changing VERIFIED_PG_VERSION",
    ).toBe(VERIFIED_PG_VERSION);
  });

  it("package.json pins pg exactly", () => {
    const pkg = JSON.parse(readFileSync("package.json", "utf8")) as {
      dependencies?: Record<string, string>;
      devDependencies?: Record<string, string>;
    };
    expect(pkg.devDependencies?.pg ?? pkg.dependencies?.pg).toBe(VERIFIED_PG_VERSION);
  });

  it("the internal the sync helper relies on is still present in this pg", () => {
    const require = createRequire(import.meta.url);
    const { Client } = require("pg") as typeof PgModule;
    const client = new Client({ connectionString: "postgresql://u:p@127.0.0.1:1/none" });
    const stream = (client as unknown as { connection?: { stream?: { destroy?: unknown } } })
      .connection?.stream;
    expect(typeof stream?.destroy).toBe("function");
  });
});
