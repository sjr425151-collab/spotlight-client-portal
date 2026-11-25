import { readdirSync, readFileSync } from "node:fs";
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

  it("T-SALES-36: no migration contains a synthetic or fixture package-scope row (A2)", () => {
    for (const file of migrations) {
      const sql = readFileSync(join("supabase/migrations", file), "utf8");
      // The label may appear only inside the constraint that recognizes it, never in a row.
      const inserts = [
        ...sql.matchAll(/insert\s+into\s+private\.billing_package_scope[\s\S]*?;/gi),
      ];
      expect(inserts, file).toEqual([]);
      const labelUses = sql.split("TEST FIXTURE — NOT A DELIVERABLE").length - 1;
      expect(labelUses, file).toBe(file.includes("wps_sales_representative") ? 1 : 0);
    }
  });

  it("T-SALES-36: the seed's fixture rows are all flagged and labeled", () => {
    const seed = readFileSync("supabase/seed.sql", "utf8");
    const block = seed.slice(seed.indexOf("insert into private.billing_package_scope"));
    expect(block).toMatch(/'TEST FIXTURE — NOT A DELIVERABLE \(/);
    expect(block).toMatch(/, true\s*\nfrom private\.billing_packages/);
    // The fixture rows come after the development classification, so the trigger admits them.
    expect(seed.indexOf("insert into private.environment_settings")).toBeLessThan(
      seed.indexOf("insert into private.billing_package_scope"),
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
});
