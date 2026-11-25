import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import {
  FINAL_PAYMENT_CLAUSE,
  TEST_FIXTURE_LABEL,
  TEST_FIXTURE_TEXT,
  canonicalText,
} from "@/domain/billing/agreement";
import {
  MAINTENANCE_MONTHLY_CENTS,
  PACKAGES,
  balanceFor,
  depositFor,
  formatUsd,
  initialChargeFor,
} from "@/domain/billing/pricing";
import {
  AUDIT_ACTIONS,
  EVENT_TYPE_PATTERN,
  FINANCIAL_CONTRACT_VERSION,
  FINANCIAL_STATUS_ATTRIBUTES,
  FINANCIAL_STATUS_WPB_ATTRIBUTES,
  RELEASE_APPROVED_CONSUMER_CONTRACT,
  WP_B_DOMAIN_EVENT_TYPES,
  isFinancialDomain,
} from "@/domain/contracts";

/**
 * WP-B contract consistency: the TypeScript mirrors and the WP-B migrations must describe
 * the same values. These tests read the migration files themselves.
 */
const root = process.cwd();
const read = (path: string) => readFileSync(join(root, path), "utf8");
const agreements = read("supabase/migrations/20261124160000_wpb_agreements.sql");
const payments = read("supabase/migrations/20261124160100_wpb_payments_ledger.sql");
const wpbSql = `${agreements}\n${payments}`;
// WP-H (AUTH-006): the four reserved migrations, all covered by the static guards below.
const WPH_MIGRATIONS = [
  "supabase/migrations/20261126120000_wph_oi86_issue_order_summary_lock.sql",
  "supabase/migrations/20261126120100_wph_oi87_order_summary_column_privileges.sql",
  "supabase/migrations/20261126120200_wph_n1a_attribution.sql",
  "supabase/migrations/20261126120300_wph_release_approval_crosscheck.sql",
];
const wphSql = WPH_MIGRATIONS.map(read).join("\n");

describe("WP-B domain events", () => {
  const registered = [...agreements.matchAll(/\('([a-z_.]+)', '([a-z]+)', 'WP-B', '[^']+'\)/g)].map(
    (m) => ({
      type: m[1],
      domain: m[2],
    }),
  );

  it("registers exactly the TypeScript WP-B event types, with the same domains", () => {
    expect(registered).toEqual(
      WP_B_DOMAIN_EVENT_TYPES.map((e) => ({ type: e.type, domain: e.domain })),
    );
    for (const e of WP_B_DOMAIN_EVENT_TYPES) {
      expect(e.type).toMatch(EVENT_TYPE_PATTERN);
      expect(e.owner).toBe("WP-B");
    }
  });

  it("emits only registered event types", () => {
    const emitted = new Set(
      [...wpbSql.matchAll(/emit_domain_event\('([a-z_.]+)'/g)].map((m) => m[1]),
    );
    const known = new Set([
      ...WP_B_DOMAIN_EVENT_TYPES.map((e) => e.type),
      "agreement.accepted",
      "payment.deposit_verified",
    ]);
    for (const type of emitted) expect(known.has(type ?? ""), type).toBe(true);
  });

  it("documents the release.approved consumer contract the migration implements", () => {
    expect(RELEASE_APPROVED_CONSUMER_CONTRACT.consumer).toBe("wpb.final_balance_invoice");
    expect(payments).toContain(
      `v_consumer constant text := '${RELEASE_APPROVED_CONSUMER_CONTRACT.consumer}'`,
    );
    expect(payments).toContain("v_ev.payload ->> 'approval_id'");
  });
});

describe("WP-B audit actions (03 §11)", () => {
  const registered = new Map(AUDIT_ACTIONS.map((a) => [a.action, a]));

  it("registers every action the WP-B migrations write, in the right category", () => {
    const financial = [
      ...wpbSql.matchAll(
        /audit_financial\(\s*(?:case[^']*'([a-z_.]+)'[^']*'([a-z_.]+)'\s*end|'([a-z_.]+)')/g,
      ),
    ]
      .flatMap((m) => [m[1], m[2], m[3]])
      .filter((x): x is string => Boolean(x));
    const general = [...wpbSql.matchAll(/record_audit_event\('([a-z_.]+)'/g)].map(
      (m) => m[1] ?? "",
    );
    expect(financial.length).toBeGreaterThan(30);
    for (const action of financial) {
      const entry = registered.get(action);
      expect(entry, action).toBeDefined();
      expect(isFinancialDomain(entry!.domain), action).toBe(true);
    }
    for (const action of general) {
      const entry = registered.get(action);
      expect(entry, action).toBeDefined();
      expect(entry!.category, action).toBe("general");
    }
  });
});

describe("WP-B financial gate interface (OI-71)", () => {
  it("adds the G1 and OI-74 attributes additively and reports contract version 3", () => {
    expect(payments).toContain(
      "alter type private.project_financial_status\n  add attribute agreement_state public.agreement_state,\n  add attribute agreement_effective boolean,\n",
    );
    expect(payments).toContain(
      "  add attribute payment_authorization_ready boolean,\n  add attribute payment_authorization_state text;",
    );
    // The WP-0 attributes, then WP-B's four, in order (OI-71: additive extension).
    expect(FINANCIAL_STATUS_ATTRIBUTES).toHaveLength(14);
    expect(FINANCIAL_STATUS_ATTRIBUTES.slice(-4)).toEqual([...FINANCIAL_STATUS_WPB_ATTRIBUTES]);
    expect(FINANCIAL_STATUS_WPB_ATTRIBUTES).toEqual([
      "agreement_state",
      "agreement_effective",
      "payment_authorization_ready",
      "payment_authorization_state",
    ]);
    expect(FINANCIAL_CONTRACT_VERSION).toBe(3);
    expect(payments).toMatch(
      new RegExp(`p_project_id, ${FINANCIAL_CONTRACT_VERSION}::smallint, true,`),
    );
  });
});

describe("WP-B pricing mirrors the migration (04 §5.1, §7)", () => {
  it("matches every package row", () => {
    for (const p of PACKAGES) {
      expect(agreements).toContain(
        `('${p.key}', '${p.name}', ${p.totalCents}, ${p.depositCents}, ${p.balanceCents})`,
      );
    }
  });

  it("T-PAY-01: the initial charge is deposit + 9900 for every package", () => {
    expect(PACKAGES.map((p) => initialChargeFor(p.totalCents))).toEqual([
      25900, 39800, 59800, 79800, 109800,
    ]);
    expect(MAINTENANCE_MONTHLY_CENTS).toBe(9900);
  });

  it("T-PAY-02: deposit = round_half_up(20%) and deposit + balance = total (property-based)", () => {
    let seed = 20261124;
    const next = () => (seed = (seed * 1103515245 + 12345) % 2 ** 31);
    for (let i = 0; i < 5000; i++) {
      const total = next() % 50_000_000;
      const deposit = depositFor(total);
      expect(deposit + balanceFor(total)).toBe(total);
      // round_half_up via integer arithmetic only: compare to the decimal definition.
      const twenty = total * 20;
      expect(deposit).toBe(twenty % 100 >= 50 ? Math.ceil(twenty / 100) : Math.floor(twenty / 100));
    }
    expect(() => depositFor(10.5)).toThrow(RangeError);
    expect(() => depositFor(-1)).toThrow(RangeError);
  });

  it("formats integer cents without floating-point money", () => {
    expect(formatUsd(149500)).toBe("$1,495.00");
    expect(formatUsd(9900)).toBe("$99.00");
    expect(formatUsd(-3100)).toBe("-$31.00");
    expect(() => formatUsd(1.5)).toThrow(RangeError);
  });

  it("the mocked gateway's catalog is exactly the DEP-01 test catalog in the migration", () => {
    const mock = read("src/server/stripe/mock-gateway.ts");
    const sqlPrices = [
      ...agreements.matchAll(/'(price_1Uf5[A-Za-z0-9]+)', (\d+), '(one_time|recurring)'/g),
    ].map((m) => `${m[1]}:${m[2]}:${m[3]}`);
    const mockPrices = [
      ...mock.matchAll(
        /(price_1Uf5[A-Za-z0-9]+): \{ amount: (\d+), type: "(one_time|recurring)" \}/g,
      ),
    ].map((m) => `${m[1]}:${m[2]}:${m[3]}`);
    expect(sqlPrices).toHaveLength(11);
    expect(mockPrices.sort()).toEqual(sqlPrices.sort());
  });

  it("loads no live Price ID (04 §5.2: production only, after DEP-02)", () => {
    const live = read("docs/04-AGREEMENT-AND-BILLING.md").match(/price_1Ue[A-Za-z0-9]+/g) ?? [];
    expect(live.length).toBeGreaterThan(0);
    const sources = [wpbSql, read("src/server/stripe/mock-gateway.ts")].join("\n");
    for (const id of live) expect(sources).not.toContain(id);
  });
});

describe("Authorization for Final Payment clause (04 §3.1; T-PAY-15; CLAUDE.md §5)", () => {
  it("is the spec 04 clause verbatim", () => {
    const spec = read("docs/04-AGREEMENT-AND-BILLING.md");
    const block = spec.slice(spec.indexOf("> **Authorization for Final Payment**"));
    const lines = block.split("\n").slice(0, 9);
    const fromSpec = lines
      .map((line) => line.replace(/^> ?/, "").replace(/\*\*/g, ""))
      .join("\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
    expect(FINAL_PAYMENT_CLAUSE).toBe(fromSpec);
  });

  it("is byte-identical to private.final_payment_clause() in the migration", () => {
    const fn = agreements.slice(
      agreements.indexOf("create function private.final_payment_clause()"),
    );
    const body = fn.slice(fn.indexOf("as $$") + 5, fn.indexOf("$$;"));
    // Tokenize string literals in order; E'...' literals are the \n\n separators.
    const sql = [...body.matchAll(/(E?)'((?:[^']|'')*)'/g)]
      .map((m) =>
        m[1] === "E" ? (m[2] ?? "").replace(/\\n/g, "\n") : (m[2] ?? "").replace(/''/g, "'"),
      )
      .join("");
    expect(sql).toBe(FINAL_PAYMENT_CLAUSE);
  });

  it("the fixture is the label followed only by the clause (OI-69)", () => {
    expect(TEST_FIXTURE_TEXT).toBe(`${TEST_FIXTURE_LABEL}\n\n${FINAL_PAYMENT_CLAUSE}`);
    expect(agreements).toContain("select 'TEST FIXTURE — NOT AN AGREEMENT';");
    expect(canonicalText("a\r\nb\rc")).toBe("a\nb\nc");
  });
});

describe("WP-B migrations stay within AUTH-001", () => {
  it("never alter or drop Phase 2 or WP-0 objects (additive only)", () => {
    expect(wpbSql).not.toMatch(
      /\b(drop|alter)\s+(table|policy|function)\s+public\.(profiles|staff_roles|client_businesses|projects|invitations|project_memberships|audit_events|domain_events|notification_outbox)\b/i,
    );
    expect(wpbSql).not.toMatch(
      /create or replace function private\.(?!project_financial_status\b)/,
    );
    expect(wpbSql).not.toMatch(/on storage\.objects/);
  });

  it("WP-H (AUTH-006 and Amendment 1): the migrations stay within the authorized objects", () => {
    // Exactly the four reserved migrations.
    expect(
      readdirSync(join(root, "supabase/migrations"))
        .filter((f) => f.includes("_wph_"))
        .sort(),
    ).toEqual(WPH_MIGRATIONS.map((p) => p.replace("supabase/migrations/", "")));
    // The exact create-or-replace allow-list: project_financial_status (B1) and the existing
    // functions AUTH-006 and its Amendment 1 name. Nothing else is replaced, public or private.
    const replaced = [
      ...`${wpbSql}\n${wphSql}`.matchAll(/create or replace function ([a-z_]+\.[a-z_]+)/g),
    ]
      .map((m) => m[1])
      .sort();
    expect(replaced).toEqual(
      [
        "private.consume_release_approved",
        "private.handle_charge_refunded",
        "private.handle_dispute",
        "private.handle_refund",
        "private.issue_order_summary",
        "private.process_stripe_event",
        "private.project_financial_anomalies",
        "private.project_financial_status",
        "private.resolve_quarantined_event",
      ].sort(),
    );
    // The same additive-only restrictions as WP-B.
    expect(wphSql).not.toMatch(
      /\b(drop|alter)\s+(table|policy|function)\s+public\.(profiles|staff_roles|client_businesses|projects|invitations|project_memberships|audit_events|domain_events|notification_outbox)\b/i,
    );
    expect(wphSql).not.toMatch(/on storage\.objects/);
    expect(wphSql).not.toMatch(/\bdrop\s+(table|function|policy|trigger)\b/i);
    // The only new table is the N1(a) candidate table; the only grant is OI-87's column grant.
    expect([...wphSql.matchAll(/create table ([a-z_.]+)/g)].map((m) => m[1])).toEqual([
      "private.financial_event_project_candidates",
    ]);
    expect(
      [...wphSql.matchAll(/^\s*grant\s+([^;]+?)\s+on\s+([a-z_.]+)/gim)].map((m) => m[2]),
    ).toEqual(["public.order_summaries"]);
  });

  it("number WP-B pgTAP files 1xx", () => {
    const files = readdirSync(join(root, "supabase/tests")).filter((f) => f.includes("wpb"));
    expect(files.length).toBeGreaterThanOrEqual(3);
    for (const f of files) expect(f).toMatch(/^1\d\d_wpb_[a-z_]+\.test\.sql$/);
  });
});
