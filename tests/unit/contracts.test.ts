import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { describe, expect, it } from "vitest";

import {
  AGREEMENT_STATES,
  AUDIT_ACTIONS,
  AUDIT_ACTION_MAX_LENGTH,
  AUDIT_ACTION_PATTERN,
  DEPOSIT_STATES,
  DEVELOPMENT_STATES,
  DIMENSION_DOMAIN,
  DOMAIN_EVENT_PAYLOAD_MAX_BYTES,
  DOMAIN_EVENT_TYPES,
  EVENT_TYPE_PATTERN,
  FINAL_BALANCE_STATES,
  FINANCIAL_STATUS_ATTRIBUTES,
  FULFILLMENT_STATUS_ATTRIBUTES,
  GATE_SOURCES,
  HOLD_TYPES,
  INTAKE_STATES,
  NOTIFICATION_RECIPIENT_ROLES,
  NOTIFICATION_STATUSES,
  NOTIFICATION_TRANSITIONS,
  PUBLICATION_STATES,
  R1_NOTIFICATION_STATUS,
  RELEASE_APPROVAL_STATES,
  SERVICE_TERMINATION_STATES,
  STATE_DOMAINS,
  SUBSCRIPTION_STATUSES,
  auditAction,
  canTransition,
  isFinancialDomain,
  isPayloadSafe,
  notificationIdempotencyKey,
} from "@/domain/contracts";

/**
 * WP-0 contract consistency (spec 01 §7). The TypeScript contracts and the WP-0 migration
 * must describe the same values; this reads the migration file itself, so a change to one
 * without the other fails here before any database runs.
 */
const migration = readFileSync(
  join(process.cwd(), "supabase/migrations/20261124120000_wp0_shared_contracts.sql"),
  "utf8",
);

function sqlEnum(name: string): string[] {
  const match = new RegExp(`create type public\\.${name} as enum \\(([^;]*?)\\);`, "s").exec(
    migration,
  );
  if (!match?.[1]) throw new Error(`enum public.${name} not found in the WP-0 migration`);
  return [...match[1].matchAll(/'([^']+)'/g)].map((m) => m[1] ?? "");
}

/** Every migration, in apply order (file names start with a timestamp). */
const allMigrations = readdirSync(join(process.cwd(), "supabase/migrations"))
  .filter((name) => name.endsWith(".sql"))
  .sort()
  .map((name) => readFileSync(join(process.cwd(), "supabase/migrations", name), "utf8"));

/**
 * Attributes of a composite type as created in WP-0, followed by every additive
 * `alter type ... add attribute` in later migrations, in order (OI-71: extensions are
 * additive; each package extends only its own interface).
 */
function sqlComposite(name: string): string[] {
  const match = new RegExp(`create type private\\.${name} as \\(([^;]*?)\\n\\);`, "s").exec(
    migration,
  );
  if (!match?.[1]) throw new Error(`composite private.${name} not found in the WP-0 migration`);
  const created = match[1]
    .split("\n")
    .map((line) => line.trim().split(/\s+/)[0] ?? "")
    .filter(Boolean);
  const added = allMigrations.flatMap((sql) =>
    [...sql.matchAll(new RegExp(`alter type private\\.${name}\\s+([^;]*);`, "g"))].flatMap((m) =>
      [...(m[1] ?? "").matchAll(/add attribute (\w+)/g)].map((a) => a[1] ?? ""),
    ),
  );
  return [...created, ...added];
}

describe("WP-0 state-domain types match the migration", () => {
  it.each([
    ["state_domain", STATE_DOMAINS],
    ["agreement_state", AGREEMENT_STATES],
    ["deposit_state", DEPOSIT_STATES],
    ["final_balance_state", FINAL_BALANCE_STATES],
    ["subscription_status", SUBSCRIPTION_STATUSES],
    ["service_termination_state", SERVICE_TERMINATION_STATES],
    ["intake_state", INTAKE_STATES],
    ["development_state", DEVELOPMENT_STATES],
    ["release_approval_state", RELEASE_APPROVAL_STATES],
    ["publication_state", PUBLICATION_STATES],
    ["hold_type", HOLD_TYPES],
    ["notification_status", NOTIFICATION_STATUSES],
    ["notification_recipient_role", NOTIFICATION_RECIPIENT_ROLES],
  ] as const)("public.%s", (name, values) => {
    expect(sqlEnum(name)).toEqual([...values]);
  });

  it("maps every state dimension to one of the six domains, and every dimension exists in SQL", () => {
    for (const [dimension, domain] of Object.entries(DIMENSION_DOMAIN)) {
      expect(STATE_DOMAINS).toContain(domain);
      expect(sqlEnum(dimension).length).toBeGreaterThan(0);
    }
  });

  it("treats only payment and subscription as financial", () => {
    expect(STATE_DOMAINS.filter(isFinancialDomain)).toEqual(["payment", "subscription"]);
    expect(migration).toContain(
      "select p_domain in ('payment'::public.state_domain, 'subscription'::public.state_domain);",
    );
  });
});

describe("WP-0 domain-event registry", () => {
  const seeded = [...migration.matchAll(/\('([a-z_.]+)', '([a-z]+)', '(WP-[BC])', '[^']+'\)/g)].map(
    (m) => ({ type: m[1], domain: m[2], owner: m[3] }),
  );

  it("registers exactly the TypeScript event types, with the same domain and owner", () => {
    expect(seeded).toEqual(
      DOMAIN_EVENT_TYPES.map((e) => ({ type: e.type, domain: e.domain, owner: e.owner })),
    );
  });

  it("uses well-formed, unique names and versions", () => {
    const names = DOMAIN_EVENT_TYPES.map((e) => e.type);
    expect(new Set(names).size).toBe(names.length);
    for (const e of DOMAIN_EVENT_TYPES) {
      expect(e.type).toMatch(EVENT_TYPE_PATTERN);
      expect(e.schemaVersion).toBeGreaterThanOrEqual(1);
      expect(e.consumers).not.toContain(e.owner);
    }
  });

  it("declares the cross-package handoff WP-C -> WP-B for release.approved (01 §7)", () => {
    const approved = DOMAIN_EVENT_TYPES.find((e) => e.type === "release.approved");
    expect(approved?.owner).toBe("WP-C");
    expect(approved?.consumers).toContain("WP-B");
  });
});

describe("WP-0 payload safety mirrors the database rule", () => {
  it("accepts ordinary payloads, including keys that merely contain a forbidden word", () => {
    expect(
      isPayloadSafe(
        { company: "Synthetic A", release_number: 3, capacity: 1 },
        DOMAIN_EVENT_PAYLOAD_MAX_BYTES,
      ),
    ).toBe(true);
  });

  it.each([
    [{ session_token: "x" }],
    [{ approval: { api_key: "x" } }],
    [{ items: [{ card_number: "4242" }] }],
    [{ otp: "123456" }],
    [{ Authorization: "Bearer x" }],
  ])("rejects secret-like keys at any depth: %j", (payload) => {
    expect(isPayloadSafe(payload, DOMAIN_EVENT_PAYLOAD_MAX_BYTES)).toBe(false);
  });

  it("rejects non-objects and oversized payloads", () => {
    expect(isPayloadSafe([1, 2], DOMAIN_EVENT_PAYLOAD_MAX_BYTES)).toBe(false);
    expect(isPayloadSafe(null, DOMAIN_EVENT_PAYLOAD_MAX_BYTES)).toBe(false);
    expect(isPayloadSafe({ blob: "x".repeat(9000) }, DOMAIN_EVENT_PAYLOAD_MAX_BYTES)).toBe(false);
  });

  it("uses the same forbidden-key pattern as the migration", () => {
    expect(migration).toContain(
      "(^|_)(secret|token|password|passcode|otp|apikey|api_key|card|cvc|cvv|pan|authorization|cookie)s?(_|$)",
    );
  });
});

describe("WP-0 notification outbox contract (07 §2-§3)", () => {
  it("writes R1 rows as recorded, which is terminal", () => {
    expect(R1_NOTIFICATION_STATUS).toBe("recorded");
    expect(NOTIFICATION_TRANSITIONS.recorded).toEqual([]);
    for (const to of NOTIFICATION_STATUSES) expect(canTransition("recorded", to)).toBe(false);
  });

  it("allows only the delivery transitions the database guard allows", () => {
    expect(canTransition("pending", "sending")).toBe(true);
    expect(canTransition("sending", "sent")).toBe(true);
    expect(canTransition("sending", "failed")).toBe(true);
    expect(canTransition("failed", "sending")).toBe(true);
    expect(canTransition("failed", "dead")).toBe(true);
    expect(canTransition("pending", "sent")).toBe(false);
    expect(canTransition("dead", "sending")).toBe(false);
    expect(canTransition("sent", "failed")).toBe(false);
    expect(migration).toContain("(old.status = 'pending' and new.status = 'sending')");
    expect(migration).toContain("(old.status = 'sending' and new.status in ('sent', 'failed'))");
    expect(migration).toContain("(old.status = 'failed' and new.status in ('sending', 'dead'))");
  });

  it("builds the 07 §3 idempotency key", () => {
    expect(notificationIdempotencyKey("preview.released", "rel_1", 1)).toBe(
      "preview.released:rel_1:1",
    );
    expect(() => notificationIdempotencyKey("preview.released", "rel_1", 0)).toThrow(RangeError);
  });
});

describe("WP-0 gate interfaces (06 §2)", () => {
  it("matches the financial and fulfillment composite types attribute for attribute", () => {
    expect(sqlComposite("project_financial_status")).toEqual([...FINANCIAL_STATUS_ATTRIBUTES]);
    expect(sqlComposite("project_fulfillment_status")).toEqual([...FULFILLMENT_STATUS_ATTRIBUTES]);
  });

  it("covers G1-G8; G1 is supplied by WP-B and G6 by WP-C, so no gate is unassigned (OI-71)", () => {
    expect(Object.keys(GATE_SOURCES)).toEqual(["G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8"]);
    // OI-71 item 1 (WP-B): G1 comes from the financial interface.
    expect(GATE_SOURCES.G1).toBe("financial");
    expect(
      Object.entries(GATE_SOURCES)
        .filter(([, source]) => source === null)
        .map(([g]) => g),
    ).toEqual([]);
    expect(GATE_SOURCES.G6).toBe("fulfillment");
  });

  it("ships fail-closed stubs: not implemented and no satisfied gate input", () => {
    expect(migration).toMatch(
      /p_project_id, 1::smallint, false,\s+'not_started'::public\.deposit_state, false,/,
    );
    expect(migration).toMatch(
      /p_project_id, 1::smallint, false,\s+'locked'::public\.intake_state, false,/,
    );
  });
});

describe("WP-0 audit action names (03 §11)", () => {
  it("are unique, well-formed, within the audit_events length limit, and cite a spec", () => {
    const names = AUDIT_ACTIONS.map((a) => a.action);
    expect(new Set(names).size).toBe(names.length);
    for (const a of AUDIT_ACTIONS) {
      expect(a.action).toMatch(AUDIT_ACTION_PATTERN);
      expect(a.action.length).toBeLessThanOrEqual(AUDIT_ACTION_MAX_LENGTH);
      expect(a.spec).toMatch(/^0[3-7] §\d/);
    }
  });

  it("marks exactly the payment and subscription actions as financial", () => {
    for (const a of AUDIT_ACTIONS) {
      expect(a.category, a.action).toBe(isFinancialDomain(a.domain) ? "financial" : "general");
    }
  });

  it("assigns WP-B the billing actions and WP-C the fulfillment actions", () => {
    for (const a of AUDIT_ACTIONS) {
      const wpB = ["agreement", "payment", "subscription"].includes(a.domain);
      expect(a.owner, a.action).toBe(wpB ? "WP-B" : "WP-C");
    }
  });

  it("rejects unregistered names", () => {
    expect(auditAction("preview.approved").owner).toBe("WP-C");
    expect(() => auditAction("payment.marked_paid")).toThrow(/Unregistered/);
  });
});
