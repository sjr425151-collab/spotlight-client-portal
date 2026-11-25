import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("server-only", () => ({}));

// next/navigation: redirect and notFound throw, as they do in Next.js, so a guard stops.
class Redirect extends Error {
  constructor(public readonly to: string) {
    super(`redirect:${to}`);
  }
}
vi.mock("next/navigation", () => ({
  redirect: (to: string) => {
    throw new Redirect(to);
  },
  notFound: () => {
    throw new Redirect("404");
  },
}));

const ctxMock = vi.fn();
vi.mock("@/server/auth/context", () => ({ getAuthContext: () => ctxMock() }));

let memberships: { id: string }[] = [];
vi.mock("@/server/supabase/clients", () => ({
  createUserClient: async () => ({
    from: () => {
      const q = {
        select: () => q,
        eq: () => q,
        limit: async () => ({ data: memberships, error: null }),
      };
      return q;
    },
  }),
}));

const { requireClient, requireSales, requireStaff, homeFor } = await import("@/server/auth/guards");
const { AUDIT_ACTIONS, AUDIT_ACTION_PATTERN, WP_S_AUDIT_ACTIONS } =
  await import("@/domain/contracts/audit-actions");

type Ctx = {
  staffRole: "owner" | "admin" | null;
  sales: boolean;
  anyStaffRole: boolean;
  aal: "aal1" | "aal2";
};
function ctx(partial: Partial<Ctx>) {
  return {
    userId: "00000000-0000-4000-8000-000000000009",
    email: "x@example.test",
    active: true,
    sessionActive: true,
    mfaFresh: false,
    staffRole: null,
    sales: false,
    anyStaffRole: false,
    aal: "aal2",
    ...partial,
  };
}
async function outcome(fn: () => Promise<unknown>): Promise<string> {
  try {
    await fn();
    return "allowed";
  } catch (error) {
    if (error instanceof Redirect) return error.to;
    throw error;
  }
}

const SALES = { sales: true, anyStaffRole: true };

beforeEach(() => {
  memberships = [{ id: "m1" }];
});

describe("WP-S app guards (03 §4.1; T-SALES-12, T-SALES-24, T-SALES-03)", () => {
  it("requireClient admits only a user with no staff role of any kind and an active membership", async () => {
    ctxMock.mockResolvedValue(ctx({}));
    expect(await outcome(requireClient)).toBe("allowed");

    ctxMock.mockResolvedValue(ctx(SALES));
    expect(await outcome(requireClient)).toBe("/sales");

    ctxMock.mockResolvedValue(ctx({ staffRole: "admin", anyStaffRole: true }));
    expect(await outcome(requireClient)).toBe("/staff");

    // An unknown future staff role is never treated as a client (fail closed).
    ctxMock.mockResolvedValue(ctx({ anyStaffRole: true }));
    expect(await outcome(requireClient)).toBe("/sign-in?notice=inactive");

    memberships = [];
    ctxMock.mockResolvedValue(ctx({}));
    expect(await outcome(requireClient)).toBe("/sign-in?notice=no_active_project");
  });

  it("requireClient denies a Sales Representative even when it holds a membership", async () => {
    memberships = [{ id: "fixture" }];
    ctxMock.mockResolvedValue(ctx(SALES));
    expect(await outcome(requireClient)).toBe("/sales");
  });

  it("requireStaff stays Owner and Admin; a Sales Representative is sent to /sales", async () => {
    ctxMock.mockResolvedValue(ctx(SALES));
    expect(await outcome(() => requireStaff())).toBe("/sales");
    ctxMock.mockResolvedValue(ctx({ staffRole: "admin", anyStaffRole: true }));
    expect(await outcome(() => requireStaff())).toBe("allowed");
  });

  it("requireSales forces MFA and denies staff and clients", async () => {
    ctxMock.mockResolvedValue(ctx({ ...SALES, aal: "aal1" }));
    expect(await outcome(() => requireSales())).toBe("/mfa?next=%2Fsales");
    ctxMock.mockResolvedValue(ctx(SALES));
    expect(await outcome(() => requireSales())).toBe("allowed");
    ctxMock.mockResolvedValue(ctx({ staffRole: "owner", anyStaffRole: true }));
    expect(await outcome(() => requireSales())).toBe("/staff");
    ctxMock.mockResolvedValue(ctx({}));
    expect(await outcome(() => requireSales())).toBe("/portal");
    ctxMock.mockResolvedValue({ ...ctx(SALES), sessionActive: false });
    expect(await outcome(() => requireSales())).toBe("/sign-in");
  });

  it("homeFor routes each role to its own area", () => {
    expect(homeFor({ staffRole: "owner", sales: false })).toBe("/staff");
    expect(homeFor({ staffRole: null, sales: true })).toBe("/sales");
    expect(homeFor({ staffRole: null, sales: false })).toBe("/portal");
  });
});

describe("WP-S audit action names (03 §11, §4.1)", () => {
  it("are unique, well-formed, general, cite 03 §4.1, and do not collide with WP-B or WP-C", () => {
    const names = WP_S_AUDIT_ACTIONS.map((a) => a.action);
    expect(new Set(names).size).toBe(names.length);
    const existing = new Set(AUDIT_ACTIONS.map((a) => a.action));
    for (const a of WP_S_AUDIT_ACTIONS) {
      expect(a.action).toMatch(AUDIT_ACTION_PATTERN);
      expect(a.category).toBe("general");
      expect(a.spec).toBe("03 §4.1");
      expect(existing.has(a.action)).toBe(false);
    }
  });

  it("are exactly the names the WP-S migration writes", () => {
    const sql = readFileSync(
      "supabase/migrations/20261125120100_wps_sales_representative.sql",
      "utf8",
    );
    const written = new Set(
      [...sql.matchAll(/record_audit_event\('([a-z_]+\.[a-z_]+)'/g)].map((m) => m[1] ?? ""),
    );
    const wpS = new Set(WP_S_AUDIT_ACTIONS.map((a) => a.action));
    const existing = new Set(AUDIT_ACTIONS.map((a) => a.action));
    // Every name the migration writes is registered here, or is an existing Phase 2 / WP-B name.
    const phase2OrWpB = [
      "staff_role.fulfillment_assignment_attempted",
      "staff_role.last_owner_protected",
      "invitation.accept_failed",
      "order_summary.catalog_mismatch",
      "order_summary.price_change_rejected",
      "order_summary.superseded",
      "order_summary.issued",
      "agreement.reacceptance_required",
    ];
    for (const name of written) {
      expect(wpS.has(name) || existing.has(name) || phase2OrWpB.includes(name), name).toBe(true);
    }
    for (const name of wpS) expect(written.has(name), name).toBe(true);
  });
});

describe("WP-S repository checks", () => {
  const migrations = readdirSync("supabase/migrations").filter((f) => f.endsWith(".sql"));

  // T-SALES-36 migration-insertion check (Change 1) with the D-1 exact-filename correction
  // (AUTH-007 Amendment 3). One helper, used unchanged for the real migrations and for the
  // synthetic mutation inputs. Lexical limitation (disclosed in the D-1 record): it recognizes
  // `insert into private.billing_package_scope…` only; quoted or unqualified names, COPY, MERGE,
  // dynamic SQL and comments inside the statement are not recognized here and are rejected at
  // runtime by private.billing_package_scope_construction_guard.
  function scopeInsertViolations(file: string, sql: string): string[] {
    const inserts = [
      ...sql.matchAll(/insert\s+into\s+private\.billing_package_scope(?:_versions)?\b[\s\S]*?;/gi),
    ].map((m) => m[0]);
    const violations: string[] = [];
    if (inserts.some((statement) => /'/.test(statement))) violations.push("literal");
    if (file !== "20261126140000_wpd18_scope_version_sealing.sql" && inserts.length > 0) {
      violations.push("insert-outside-sealing-migration");
    }
    return violations;
  }

  it("D-1 (AUTH-007 Amendment 3): the migration-insertion exemption is the exact file name, shown on mutation inputs", () => {
    const nonLiteralInsert =
      "insert into private.billing_package_scope select * from private.staging_rows;";
    const cases: ReadonlyArray<readonly [string, string, string[]]> = [
      // The exact sealing migration may copy parameters or rows (no literal).
      ["20261126140000_wpd18_scope_version_sealing.sql", nonLiteralInsert, []],
      // A similarly named migration is not exempt (the former substring exemption let it pass).
      [
        "20270101000000_wpd18_scope_version_sealing_v2.sql",
        nonLiteralInsert,
        ["insert-outside-sealing-migration"],
      ],
      [
        "20270101000000_x_wpd18_scope_version_sealing.sql",
        nonLiteralInsert,
        ["insert-outside-sealing-migration"],
      ],
      [
        "20261126140000_wpd18_scope_version_sealing.sql.bak",
        nonLiteralInsert,
        ["insert-outside-sealing-migration"],
      ],
      // Any other migration with an insert fails, into either scope table.
      [
        "20270101000000_later_change.sql",
        "insert into private.billing_package_scope_versions select * from private.staging_headers;",
        ["insert-outside-sealing-migration"],
      ],
      // A literal fails everywhere, including in the exact sealing migration.
      [
        "20261126140000_wpd18_scope_version_sealing.sql",
        "insert into private.billing_package_scope values ('essential', 9, 1, 'Item', false);",
        ["literal"],
      ],
      // A clean later migration passes, so the check is not trivially failing.
      [
        "20270101000000_later_change.sql",
        "create table private.example (id integer primary key);",
        [],
      ],
    ];
    for (const [file, sql, expected] of cases) {
      expect(scopeInsertViolations(file, sql), `${file}: ${sql}`).toEqual(expected);
    }
  });

  it("T-SALES-36: no migration contains a synthetic or fixture package-scope row (A2)", () => {
    for (const file of migrations) {
      const sql = readFileSync(join("supabase/migrations", file), "utf8");
      // The label may appear only inside the constraint that recognizes it, never in a row.
      // Refined for WP-D18 (Owner, 2026-11-25; AUTH-007 requires the version constructor in a
      // migration): an insert into the scope tables may only copy function parameters or existing
      // rows, never a literal, so no migration can carry synthetic or fixture content.
      // D-1 exact-filename correction (AUTH-007 Amendment 3): only the exact sealing migration
      // may insert at all; see scopeInsertViolations and its mutation test below.
      expect(scopeInsertViolations(file, sql), file).toEqual([]);
      const labelUses = sql.split("TEST FIXTURE — NOT A DELIVERABLE").length - 1;
      expect(labelUses, file).toBe(file.includes("wps_sales_representative") ? 1 : 0);
    }
  });

  it("T-SALES-36: the seed's fixture rows are all flagged and labeled", () => {
    const seed = readFileSync("supabase/seed.sql", "utf8");
    // Refined for WP-D18 (Owner, 2026-11-25): AUTH-007 replaces the seed's direct insert with
    // the version constructor, so the same properties are checked on the constructor calls,
    // and the seed may not write the scope tables any other way.
    expect(seed).not.toMatch(/insert\s+into\s+private\.billing_package_scope/i);
    const block = seed.slice(seed.indexOf("select private.create_package_scope_version("));
    expect(block).toMatch(/'TEST FIXTURE — NOT A DELIVERABLE \(/);
    expect(block).toMatch(/\], true\)\s*\nfrom private\.billing_packages/);
    // The fixture rows come after the development classification, so the trigger admits them.
    expect(seed.indexOf("insert into private.environment_settings")).toBeLessThan(
      seed.indexOf("select private.create_package_scope_version("),
    );
  });

  it("T-SALES-06: the Sales order path sends no amount, scope item, or project note", () => {
    const service = readFileSync("src/server/services/sales.ts", "utf8");
    const call = service.slice(service.indexOf('rpc("issue_order_summary"'));
    const args = call.slice(0, call.indexOf("});"));
    expect(args).not.toMatch(/p_scope_items|p_project_notes|cents|price|amount/);
    const forms = readFileSync("src/app/sales/projects/[projectId]/page.tsx", "utf8");
    expect(forms).not.toMatch(/name="(?:scopeItems|projectNotes|amount|price|quantity|discount)"/);
  });

  it("T-SALES-02: WP-S changes no merged migration and narrows is_staff() to Owner and Admin", () => {
    const sql = readFileSync(
      "supabase/migrations/20261125120100_wps_sales_representative.sql",
      "utf8",
    );
    expect(sql).toMatch(
      /create or replace function private\.is_staff\(\)[\s\S]*?coalesce\(private\.staff_role_of\(\(select auth\.uid\(\)\)\) in \('owner', 'admin'\), false\)/,
    );
    // Only the AUTH-005 objects are replaced.
    const replaced = [...sql.matchAll(/create or replace function (\w+\.\w+)/g)].map((m) => m[1]);
    expect(replaced.sort()).toEqual(
      [
        "private.accept_invitation",
        "private.create_invitation",
        "private.is_staff",
        "private.issue_order_summary",
        "private.revoke_invitation",
        "private.set_staff_role",
      ].sort(),
    );
    const altered = [...sql.matchAll(/alter table (\S+) (?:drop|add) constraint (\w+)/g)].map(
      (m) => `${m[1]}:${m[2]}`,
    );
    expect(altered).toEqual([
      "public.invitations:invitations_kind_shape",
      "public.invitations:invitations_kind_shape",
    ]);
  });

  it("OI-85 correction: the new migration changes only C1 to C5, and checks for conflicts first", () => {
    const sql = readFileSync("supabase/migrations/20261125120200_wps_oi85_separation.sql", "utf8");
    const code = sql
      .split("\n")
      .filter((line) => !line.trimStart().startsWith("--"))
      .join("\n");
    expect([...code.matchAll(/create or replace function (\w+\.\w+)/g)].map((m) => m[1])).toEqual([
      "private.is_project_member",
    ]);
    expect([...code.matchAll(/create function (\w+\.\w+)/g)].map((m) => m[1])).toEqual([
      "private.project_memberships_sales_separation",
      "private.staff_roles_sales_separation",
    ]);
    expect(
      [...code.matchAll(/create trigger (\w+)\s+(?:before|after) [\w ]+ on (\S+)/g)].map(
        (m) => `${m[2]}:${m[1]}`,
      ),
    ).toEqual([
      "public.project_memberships:project_memberships_sales_separation",
      "public.staff_roles:staff_roles_sales_separation",
      "private.billing_package_scope:billing_package_scope_append_only",
      "private.billing_package_scope:billing_package_scope_no_truncate",
    ]);
    // No data change and no other DDL statement (statements start a line).
    expect(code).not.toMatch(/^\s*(?:alter|drop|update|delete|insert|grant|truncate)\b/im);
    // C4 runs before C2 and C3 exist.
    expect(code.indexOf("raise exception 'OI-85: %")).toBeGreaterThan(-1);
    expect(code.indexOf("raise exception 'OI-85: %")).toBeLessThan(
      code.indexOf("create trigger project_memberships_sales_separation"),
    );
    // The reviewed WP-S migrations are unchanged from the reviewed head (byte-for-byte is
    // checked by scripts/check-migrations.sh against main once merged; here: no new edits).
    expect(
      readFileSync("supabase/migrations/20261125120000_wps_staff_role_sales.sql", "utf8"),
    ).toContain("alter type public.staff_role add value if not exists 'sales';");
  });

  it("WP-D18 (AUTH-007): the sealing migration changes only the authorized objects and adds no content", () => {
    const sql = readFileSync(
      "supabase/migrations/20261126140000_wpd18_scope_version_sealing.sql",
      "utf8",
    );
    const code = sql
      .split("\n")
      .filter((line) => !line.trimStart().startsWith("--"))
      .join("\n");
    expect([...code.matchAll(/create table (\S+)/g)].map((m) => m[1])).toEqual([
      "private.billing_package_scope_versions",
    ]);
    expect(
      [...code.matchAll(/create (?:or replace )?function (\w+\.\w+)/g)].map((m) => m[1]),
    ).toEqual([
      "private.billing_package_scope_construction_guard",
      "private.create_package_scope_version",
      "private.current_package_scope",
    ]);
    // No literal package content: the fixture label never appears, and no VALUES clause writes items.
    expect(sql).not.toContain("TEST FIXTURE");
    expect(code).not.toMatch(
      /insert\s+into\s+private\.billing_package_scope\s*\([^)]*\)\s*values/i,
    );
    // No API role is granted anything.
    expect(code).not.toMatch(/\bgrant\b/i);
    // A non-fixture row stops the migration before anything is sealed.
    expect(code.indexOf("where not is_test_fixture")).toBeGreaterThan(-1);
    expect(code.indexOf("where not is_test_fixture")).toBeLessThan(
      code.indexOf("insert into private.billing_package_scope_versions"),
    );
    // No WP-B object is touched (issue_order_summary keeps calling the resolver unchanged).
    expect(code).not.toMatch(/issue_order_summary|order_summaries/);
  });

  it("WP-D18 (AUTH-007): the seed creates every fixture version through the constructor, labeled", () => {
    const seed = readFileSync("supabase/seed.sql", "utf8");
    expect(seed).not.toMatch(/insert\s+into\s+private\.billing_package_scope/i);
    const call = seed.slice(seed.indexOf("select private.create_package_scope_version("));
    expect(call).toMatch(/^select private\.create_package_scope_version\(p\.package_key, array\[/);
    expect((call.match(/'TEST FIXTURE — NOT A DELIVERABLE \(/g) ?? []).length).toBe(3);
    expect(call).toMatch(/\], true\)\s*\nfrom private\.billing_packages p/);
    expect(seed.indexOf("insert into private.environment_settings")).toBeLessThan(
      seed.indexOf("select private.create_package_scope_version("),
    );
  });

  // AUTH-007 Amendment 1, item 1 (FD-14): compensating controls for the T-SALES-36 migration
  // check. They do not ratify or replace Change 1 (its disposition is the Owner's); they add
  // failures that Change 1 alone does not give. Outside the one defining migration, identified
  // by its exact file name, no migration may call the version constructor, use the construction
  // marker, or carry the fixture label in any recognizable form. The only label occurrence
  // allowed elsewhere is the merged label constraint itself (20261125120100, never edited).
  const SEALING_MIGRATION = "20261126140000_wpd18_scope_version_sealing.sql";
  const LABEL_CONSTRAINT_MIGRATION = "20261125120100_wps_sales_representative.sql";
  const LABEL_CONSTRAINT_TEXT =
    "constraint billing_package_scope_fixture_label check (\n    is_test_fixture = starts_with(item_text, 'TEST FIXTURE — NOT A DELIVERABLE'))";
  const SCOPE_CONTENT_CONTROLS: ReadonlyArray<readonly [string, RegExp]> = [
    // The constructor by name, including names split by concatenation or quoting.
    ["constructor", /create[\W_]*package[\W_]*scope[\W_]*version/i],
    // The construction marker, including split forms.
    ["marker", /scope[\W_]*construction|wpd18\s*\./i],
    // The fixture label: any case, any separators (spaces, dashes, quotes, ||), either half alone.
    ["label", /test[\W_]*fixture[\W_]*not[\W_]*a[\W_]*deliverable|not[\W_]*a[\W_]*deliverable/i],
    // The label's halves hex-encoded (UTF-8) or base64-encoded, as decode() would take them.
    ["label", /5445535420464958545552|44454c4956455241424c45|VEVTVCBGSVhUVVJF|REVMSVZFUkFCTEU/i],
  ];
  function scopeContentViolations(file: string, sql: string): string[] {
    if (file === SEALING_MIGRATION) return [];
    const scanned =
      file === LABEL_CONSTRAINT_MIGRATION ? sql.replace(LABEL_CONSTRAINT_TEXT, "") : sql;
    return SCOPE_CONTENT_CONTROLS.filter(([, pattern]) => pattern.test(scanned)).map(
      ([name]) => name,
    );
  }

  it("FD-14 compensating controls: no migration but the sealing migration calls the constructor, uses the marker, or carries the label", () => {
    // Non-vacuous scan: every migration is read, including the two named above.
    expect(migrations).toContain(SEALING_MIGRATION);
    expect(migrations).toContain(LABEL_CONSTRAINT_MIGRATION);
    expect(migrations.length).toBeGreaterThan(10);
    // The merged constraint exemption matches exactly once (it would silently exempt nothing otherwise).
    expect(
      readFileSync(join("supabase/migrations", LABEL_CONSTRAINT_MIGRATION), "utf8").split(
        LABEL_CONSTRAINT_TEXT,
      ).length - 1,
    ).toBe(1);
    for (const file of migrations) {
      const sql = readFileSync(join("supabase/migrations", file), "utf8");
      expect(scopeContentViolations(file, sql), file).toEqual([]);
    }
  });

  it("FD-14 compensating controls fail on synthetic offending inputs (no vacuous pass)", () => {
    const later = "20270101000000_later_change.sql";
    const cases: ReadonlyArray<readonly [string, string, string[]]> = [
      // A clean later migration passes, so the controls are not trivially failing.
      [later, "create table private.example (id integer primary key);", []],
      [
        later,
        "select private.create_package_scope_version('essential', array['Item'], false);",
        ["constructor"],
      ],
      [
        later,
        "do $$ begin execute format('select private.%s(%L, %L, false)', 'create_package_' || 'scope_version', 'essential', '{Item}'); end $$;",
        ["constructor"],
      ],
      [later, "select set_config('wpd18.scope_construction', 'essential:9', true);", ["marker"]],
      [later, "select set_config('wpd18.' || 'scope_' || 'construction', 'x', true);", ["marker"]],
      [
        later,
        "insert into private.example values ('TEST FIXTURE — NOT A DELIVERABLE (item)');",
        ["label"],
      ],
      [later, "select 'test fixture - not a deliverable';", ["label"]],
      [later, "select 'TEST FIXTURE' || ' — NOT A ' || 'DELIVERABLE';", ["label"]],
      [later, "select convert_from(decode('5445535420464958545552', 'hex'), 'UTF8');", ["label"]],
      [later, "select convert_from(decode('VEVTVCBGSVhUVVJF', 'base64'), 'UTF8');", ["label"]],
      // The exemption is the exact file name, not a substring: a similarly named file is checked.
      [
        "20270101000000_wpd18_scope_version_sealing_v2.sql",
        "select private.create_package_scope_version('essential', array['Item'], false);",
        ["constructor"],
      ],
      // The merged constraint exemption removes only the constraint text itself.
      [
        LABEL_CONSTRAINT_MIGRATION,
        `${LABEL_CONSTRAINT_TEXT}\nselect 'TEST FIXTURE — NOT A DELIVERABLE (extra)';`,
        ["label"],
      ],
    ];
    for (const [file, sql, expected] of cases) {
      expect(scopeContentViolations(file, sql), `${file}: ${sql}`).toEqual(expected);
    }
  });

  // D-1 stricter lexical rule (AUTH-007 Amendment 3 and its correction, option (a), active at a5dfad0);
  // exemptions are exactly three file names, with no other form. Outside the migrations that legitimately
  // define or protect the package-scope tables, a migration that names billing_package_scope in
  // any form fails. Before matching, comments are removed with a quote-aware lexer (string,
  // E-string, dollar-quoted and quoted-identifier contents are kept, so a name inside a string or
  // a dynamic-SQL body still counts), identifier quotes are dropped, and whitespace around dots is
  // collapsed. Remaining exposure: a name assembled from fragments at run time (for example
  // 'billing_package_' || 'scope'); the runtime construction guard remains the enforcing control.
  const SCOPE_TABLE_MIGRATIONS = new Set([
    "20261125120100_wps_sales_representative.sql",
    "20261125120200_wps_oi85_separation.sql",
    "20261126140000_wpd18_scope_version_sealing.sql",
  ]);
  function withoutSqlComments(sql: string): string {
    let out = "";
    let i = 0;
    while (i < sql.length) {
      const rest = sql.slice(i);
      if (rest.startsWith("--")) {
        const end = sql.indexOf("\n", i);
        i = end < 0 ? sql.length : end;
        out += " ";
        continue;
      }
      if (rest.startsWith("/*")) {
        let depth = 1;
        let j = i + 2;
        while (j < sql.length && depth > 0) {
          if (sql.startsWith("/*", j)) {
            depth += 1;
            j += 2;
          } else if (sql.startsWith("*/", j)) {
            depth -= 1;
            j += 2;
          } else j += 1;
        }
        i = j;
        out += " ";
        continue;
      }
      const dollar = /^\$([A-Za-z_][A-Za-z_0-9]*)?\$/.exec(rest);
      if (dollar && !/[A-Za-z0-9_]/.test(sql[i - 1] ?? "")) {
        const close = sql.indexOf(dollar[0], i + dollar[0].length);
        const end = close < 0 ? sql.length : close + dollar[0].length;
        out += sql.slice(i, end);
        i = end;
        continue;
      }
      const c = sql[i];
      if (c === "'" || c === '"') {
        const escapes =
          c === "'" && /[eE]/.test(sql[i - 1] ?? "") && !/[A-Za-z0-9_]/.test(sql[i - 2] ?? "");
        let j = i + 1;
        while (j < sql.length) {
          if (escapes && sql[j] === "\\") {
            j += 2;
            continue;
          }
          if (sql[j] === c) {
            if (sql[j + 1] === c) {
              j += 2;
              continue;
            }
            break;
          }
          j += 1;
        }
        out += sql.slice(i, j + 1);
        i = j + 1;
        continue;
      }
      out += c;
      i += 1;
    }
    return out;
  }
  function namesScopeTables(sql: string): boolean {
    const normalized = withoutSqlComments(sql)
      .replace(/"/g, "")
      .replace(/\s*\.\s*/g, ".");
    return /billing_package_scope/i.test(normalized);
  }
  function stricterScopeViolations(file: string, sql: string): string[] {
    return !SCOPE_TABLE_MIGRATIONS.has(file) && namesScopeTables(sql) ? ["names-scope-table"] : [];
  }

  it("D-1 stricter lexical rule: no other migration names the package-scope tables in any form", () => {
    for (const file of SCOPE_TABLE_MIGRATIONS) expect(migrations, file).toContain(file);
    for (const file of SCOPE_TABLE_MIGRATIONS) {
      expect(namesScopeTables(readFileSync(join("supabase/migrations", file), "utf8")), file).toBe(
        true,
      );
    }
    for (const file of migrations) {
      const sql = readFileSync(join("supabase/migrations", file), "utf8");
      expect(stricterScopeViolations(file, sql), file).toEqual([]);
    }
  });

  it("D-1 stricter lexical rule fails on synthetic offending inputs (no vacuous pass)", () => {
    const later = "20270101000000_later_change.sql";
    const offending = [
      "insert into private.billing_package_scope select * from x;",
      'insert into "private"."billing_package_scope" select * from x;',
      "insert into private . billing_package_scope select * from x;",
      "set search_path = private; insert into billing_package_scope select * from x;",
      "copy private.billing_package_scope from stdin;",
      "merge into private.billing_package_scope s using x on false when not matched then insert values (x.a);",
      "do $$ begin execute format('insert into private.%I select * from x', 'billing_package_scope'); end $$;",
      "insert /* hidden */ into private.billing_package_scope select * from x;",
      "insert into private.BILLING_PACKAGE_SCOPE_VERSIONS select * from x;",
      "create trigger t before insert on private.billing_package_scope for each row execute function f();",
    ];
    for (const sql of offending)
      expect(stricterScopeViolations(later, sql), sql).toEqual(["names-scope-table"]);
    // Exempt only by exact file name.
    const plainInsert = "insert into private.billing_package_scope select * from x;";
    expect(stricterScopeViolations("20270101000000_wps_oi85_separation.sql", plainInsert)).toEqual([
      "names-scope-table",
    ]);
    expect(stricterScopeViolations("20261125120200_wps_oi85_separation.sql", plainInsert)).toEqual(
      [],
    );
    // Not trivially failing: comments alone, and an unrelated table, pass.
    expect(
      stricterScopeViolations(
        later,
        "-- billing_package_scope is mentioned only in a comment\nselect 1;",
      ),
    ).toEqual([]);
    expect(
      stricterScopeViolations(later, "/* billing_package_scope /* nested */ */ select 1;"),
    ).toEqual([]);
    expect(
      stricterScopeViolations(later, "create table private.billing_packages_audit (id int);"),
    ).toEqual([]);
    // Disclosed remaining exposure: a name assembled from fragments is not recognized lexically.
    expect(
      stricterScopeViolations(
        later,
        "do $$ begin execute 'insert into private.billing_package_' || 'scope select 1'; end $$;",
      ),
    ).toEqual([]);
  });

  // F5 presence check (AUTH-007 Amendment 3, F6): the isolated concurrent-commit verification is a
  // mandatory step of the database job, exactly as recorded: after "Database tests (pgTAP)", before
  // "Integration tests", with no `continue-on-error` and no `if:`, so the aggregate `CI result`
  // cannot pass without it.
  const F5_STEP = [
    "      - name: WP-D18 isolated concurrent-commit verification",
    "        run: ./scripts/wpd18-isolated-commit-test.sh",
    "        timeout-minutes: 5",
  ];
  function f5Violations(workflow: string): string[] {
    const lines = workflow.split("\n");
    const starts = lines.flatMap((l, i) => (/^ {6}- /.test(l) ? [i] : []));
    const steps = starts.map((start, k) => {
      let end = starts[k + 1] ?? lines.length;
      for (let j = start + 1; j < end; j += 1) {
        if (!/^ {8}|^\s*$/.test(lines[j] ?? "")) {
          end = j;
          break;
        }
      }
      return { start, lines: lines.slice(start, end).filter((l) => l.trim() !== "") };
    });
    const named = (name: string) => steps.findIndex((s) => s.lines[0] === `      - name: ${name}`);
    const found = steps.filter((s) =>
      s.lines.some((l) => l.includes("wpd18-isolated-commit-test.sh")),
    );
    const violations: string[] = [];
    if (found.length !== 1) violations.push(`step count ${found.length}`);
    const f5 = named("WP-D18 isolated concurrent-commit verification");
    if (f5 < 0) return [...violations, "step missing"];
    const block = steps[f5]!.lines;
    if (block.some((l) => /continue-on-error/.test(l))) violations.push("continue-on-error");
    if (block.some((l) => /^\s+if:/.test(l))) violations.push("if");
    if (JSON.stringify(block) !== JSON.stringify(F5_STEP)) violations.push("step content");
    if (named("Database tests (pgTAP)") !== f5 - 1) violations.push("not right after pgTAP");
    if (named("Integration tests") !== f5 + 1) violations.push("not right before integration");
    const job = (i: number) => {
      for (let j = i; j >= 0; j -= 1)
        if (/^ {2}[a-z][a-z0-9_-]*:\s*$/.test(lines[j] ?? "")) return lines[j];
      return undefined;
    };
    const pg = named("Database tests (pgTAP)");
    if (pg < 0 || job(steps[pg]!.start) !== job(steps[f5]!.start))
      violations.push("not in the database job");
    return violations;
  }

  it("F5 (AUTH-007 Amendment 3): the isolated verification is a mandatory, unconditional database-job step", () => {
    const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
    expect(f5Violations(workflow)).toEqual([]);
    // The script it runs exists and is executable.
    expect(statSync("scripts/wpd18-isolated-commit-test.sh").mode & 0o111).not.toBe(0);
  });

  it("F5 presence check fails on synthetic offending workflows (no vacuous pass)", () => {
    const workflow = readFileSync(".github/workflows/ci.yml", "utf8");
    const step = F5_STEP.join("\n") + "\n";
    const cases: ReadonlyArray<readonly [string, string, string]> = [
      ["removed", workflow.replace(step, ""), "step missing"],
      [
        "continue-on-error",
        workflow.replace(step, step + "        continue-on-error: true\n"),
        "continue-on-error",
      ],
      ["if", workflow.replace(step, step + "        if: github.event_name == 'push'\n"), "if"],
      [
        "other command",
        workflow.replace("run: ./scripts/wpd18-isolated-commit-test.sh", "run: echo skipped"),
        "step content",
      ],
      [
        "moved after integration",
        workflow
          .replace(step, "")
          .replace(
            "      - name: Integration tests\n        run: pnpm test:integration\n",
            "      - name: Integration tests\n        run: pnpm test:integration\n" + step,
          ),
        "not right after pgTAP",
      ],
      ["duplicated", workflow.replace(step, step + step), "step count 2"],
    ];
    for (const [label, mutated, expected] of cases) {
      expect(mutated, label).not.toBe(workflow);
      expect(f5Violations(mutated), label).toContain(expected);
    }
  });
});
