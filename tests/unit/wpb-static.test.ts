import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { describe, expect, it } from "vitest";

import { EnvValidationError, parseServerEnv } from "@/config/env-schema";
import { AUDIT_ACTIONS } from "@/domain/contracts/audit-actions";

/**
 * WP-B static and configuration checks (code-search halves of T-PAY-10, T-ARC-04, T-ARC-08,
 * T-AGR-08, T-BIL-08, T-BIL-18, T-BIL-19, T-BIL-22; CLAUDE.md §3-§4, §8).
 */
const root = new URL("../..", import.meta.url).pathname;
function filesUnder(directory: string): string[] {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name);
    if (statSync(path).isDirectory()) return filesUnder(path);
    return /\.(?:ts|tsx|mts|mjs)$/.test(name) ? [path] : [];
  });
}
const sources = filesUnder(join(root, "src")).map((path) => ({
  path: relative(root, path),
  text: readFileSync(path, "utf8"),
}));
const offenders = (pattern: RegExp, allowed: string[] = []) =>
  sources
    .filter(({ path, text }) => pattern.test(text) && !allowed.includes(path))
    .map(({ path }) => path);

describe("WP-B static security checks", () => {
  it("T-PAY-10: no code writes the ledger, payment states, or a 'mark as paid' path", () => {
    expect(
      offenders(
        /from\(\s*["'](?:ledger_entries|webhook_events|final_balance_invoices|checkout_sessions)["']\s*\)\s*\.\s*(?:insert|update|upsert|delete)/,
      ),
    ).toEqual([]);
    expect(offenders(/mark_?as_?paid|markAsPaid|force_?publish|forcePublish/i)).toEqual([]);
  });

  it("T-ARC-04: every Stripe create goes through the outbound executor", () => {
    const allowed = [
      "src/server/stripe/gateway.ts",
      "src/server/stripe/mock-gateway.ts",
      "src/server/services/billing.ts",
    ];
    expect(
      offenders(
        /\.(?:createCheckoutSession|createFinalBalanceInvoice|createCustomer|createRecoverySession|disableAutomaticCollection)\(/,
        allowed,
      ),
    ).toEqual([]);
    const billing = sources.find((s) => s.path === "src/server/services/billing.ts")!.text;
    // The only create and update calls sit in call(), which runs after
    // outbound_request_for_execution claimed the request (OI-74 adds recovery and the stop)
    // and, since AUTH-009, after confirm_outbound_dispatch confirmed it.
    const callFn = billing.slice(billing.indexOf("async function call("));
    const callBody = callFn.slice(0, callFn.indexOf("\n}\n"));
    expect(billing.match(/gateway\.(?:create\w+|disableAutomaticCollection)\(/g)).toHaveLength(5);
    expect(callBody.match(/gateway\.(?:create\w+|disableAutomaticCollection)\(/g)).toHaveLength(5);
  });

  it("CLAUDE.md §4 / §8: no Stripe SDK, no Stripe network call, no Stripe credential in code", () => {
    const pkg = readFileSync(join(root, "package.json"), "utf8");
    expect(pkg).not.toMatch(/"stripe"\s*:/);
    expect(offenders(/from\s+["']stripe["']|api\.stripe\.com/)).toEqual([]);
    expect(offenders(/\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{8,}|whsec_[A-Za-z0-9]{16,}/)).toEqual(
      [],
    );
    expect(offenders(/\bfetch\(/).filter((p) => p.startsWith("src/server/stripe/"))).toEqual([]);
  });

  it("WP-H (AUTH-006): the four WP-H migrations keep the WP-B payment invariants", () => {
    const wph = [
      "20261126120000_wph_oi86_issue_order_summary_lock.sql",
      "20261126120100_wph_oi87_order_summary_column_privileges.sql",
      "20261126120200_wph_n1a_attribution.sql",
      "20261126120300_wph_release_approval_crosscheck.sql",
    ].map((f) => readFileSync(join(root, "supabase/migrations", f), "utf8"));
    expect(wph).toHaveLength(4);
    for (const sql of wph) {
      // No new outbound purpose, no non-card payment method, no subscription or default-card
      // write, no "mark as paid" or "force publish" path, no provider call (CLAUDE.md §3-§4).
      expect(sql).not.toMatch(/alter type public\.outbound_request_purpose/i);
      expect(sql).not.toMatch(/payment_method_types', jsonb_build_array\('(?!card')/);
      expect(sql).not.toMatch(/'invoice_settings'/);
      expect(sql).not.toMatch(/mark_?as_?paid|force_?publish/i);
      expect(sql).not.toMatch(/api\.stripe\.com|\bhttp_(?:get|post)\(|net\.http_/);
    }
  });

  it("AUTH-009 (OI-91): the dispatch migration keeps the payment invariants and the token stays secret", () => {
    const sql = ["20261127120000_wpb_oi91_dispatch.sql", "20261127120100_wpb_oi91_stop_retry.sql"]
      .map((f) => readFileSync(join(root, "supabase/migrations", f), "utf8"))
      .join("\n");
    // The same invariants as WP-H: no new outbound purpose, card-only, no default-card write,
    // no "mark as paid" or "force publish" path, no provider call (CLAUDE.md §3-§4).
    expect(sql).not.toMatch(/alter type public\.outbound_request_purpose/i);
    expect(sql).not.toMatch(/payment_method_types', jsonb_build_array\('(?!card')/);
    expect(sql).not.toMatch(/'invoice_settings'/);
    expect(sql).not.toMatch(/mark_?as_?paid|force_?publish/i);
    expect(sql).not.toMatch(/api\.stripe\.com|\bhttp_(?:get|post)\(|net\.http_/);
    // Only the SHA-256 of the claim token is stored (A2), and no idempotency key changes.
    const tokenWrites = [...sql.matchAll(/claim_token_sha256 = ([^\n]+)/g)].map((m) => m[1]);
    expect(tokenWrites).toEqual(["encode(sha256(convert_to(v_token::text, 'UTF8')), 'hex')"]);
    expect(sql).not.toMatch(/set\s+idempotency_key|idempotency_key\s*=/);
    // S2 (Owner, 2026-11-26): every audit action the AUTH-009 migrations write is registered as
    // financial, and no audit or notification call passes a token or its hash.
    const actions = [...sql.matchAll(/audit_financial\('([a-z_.]+)'/g)].map((m) => m[1]);
    expect(actions).toContain("outbound.claim_token_rejected");
    expect(actions).toContain("outbound.request_retried");
    for (const action of actions) {
      const entry = AUDIT_ACTIONS.find((a) => a.action === action);
      expect(entry, action).toBeDefined();
      expect(entry!.category, action).toBe("financial");
    }
    const calls = [...sql.matchAll(/(?:audit_financial|notify_owner)\([^;]*;/g)].map((m) => m[0]);
    expect(calls.length).toBeGreaterThan(10);
    // Quoted names (such as the action itself) are not values: only identifiers are checked.
    for (const call of calls)
      expect(call.replace(/'[^']*'/g, "''")).not.toMatch(/claim_token|v_token|token_sha256/);
    // The executor confirms before the provider request and never logs or returns the token.
    const billing = sources.find((s) => s.path === "src/server/services/billing.ts")!.text;
    const execute = billing.slice(billing.indexOf("export async function executeOutboundRequest("));
    const executeBody = execute.slice(0, execute.indexOf("\n}\n"));
    // On the send path: the deadline clock starts, the dispatch is confirmed, then the gateway.
    const sendPath = executeBody.slice(
      executeBody.indexOf("const confirmationStarted = clock.now();"),
    );
    const confirmAt = sendPath.indexOf("= await confirmDispatch(admin, requestId, claimToken);");
    expect(confirmAt).toBeGreaterThan(0);
    expect(sendPath.indexOf("await call(gateway")).toBeGreaterThan(confirmAt);
    expect(executeBody.match(/await call\(gateway/g)).toHaveLength(1);
    expect(billing).toContain("export const SEND_DEADLINE_MS = 30_000;");
    expect(offenders(/console\.\w+\([^)]*(?:claim_?token|claimToken)/i)).toEqual([]);
    expect(
      offenders(/claim_?token|claimToken/i, [
        "src/server/services/billing.ts",
        "src/domain/contracts/audit-actions.ts",
      ]),
    ).toEqual([]);
  });

  it("T-ARC-08: no portal path issues a refund or responds to a dispute", () => {
    expect(offenders(/refunds\.create|disputes\.(?:update|close)|createRefund/)).toEqual([]);
  });

  it("T-PAY-09 / 04 §10: no final Checkout Session exists; only the initial kind", () => {
    const migration = readFileSync(
      join(root, "supabase/migrations/20261124160100_wpb_payments_ledger.sql"),
      "utf8",
    );
    expect(migration).toContain("constraint checkout_kind check (kind = 'initial')");
  });

  it("T-PAY-24: no code creates a PaymentIntent or a charge, or writes the subscription's card", () => {
    expect(
      offenders(
        /paymentIntents\.create|createPaymentIntent|charges\.create|createCharge|\/v1\/payment_intents|\/v1\/charges/,
      ),
    ).toEqual([]);
    const payments = readFileSync(
      join(root, "supabase/migrations/20261124160100_wpb_payments_ledger.sql"),
      "utf8",
    );
    // The only final-balance collection is the single invoice (04 §10). No request purpose
    // updates a subscription or a customer's default card (OI-74).
    const purposes = /create type public\.outbound_request_purpose as enum \(([^;]*)\);/.exec(
      payments,
    )?.[1];
    expect(purposes).toBeDefined();
    expect(purposes).not.toMatch(/payment_intent|charge|subscription_update|customer_update/);
    expect(payments).not.toMatch(/'invoice_settings'|default_payment_method'\s*,\s*.*subscription/);
  });

  it("OI-74: every Checkout Session the database builds is card-only", () => {
    const payments = readFileSync(
      join(root, "supabase/migrations/20261124160100_wpb_payments_ledger.sql"),
      "utf8",
    );
    const builders = [
      ...payments.matchAll(/'(?:checkout_session_create|recovery_session_create)'[\s\S]{0,800}/g),
    ].filter((m) => /jsonb_build_object\('mode'/.test(m[0]));
    expect(builders.length).toBeGreaterThanOrEqual(1);
    expect(
      payments.match(/'allowed_payment_method_types', jsonb_build_array\('card'\)/g),
    ).toHaveLength(2);
    expect(payments).not.toMatch(/payment_method_types', jsonb_build_array\('(?!card')/);
  });

  it("T-PAY-29: reversal allocation has no deposit-first, maintenance-first or proportional path", () => {
    const payments = readFileSync(
      join(root, "supabase/migrations/20261124160100_wpb_payments_ledger.sql"),
      "utf8",
    );
    const apply = payments.slice(payments.indexOf("create function private.apply_reversal("));
    const body = apply.slice(0, apply.indexOf("\n$$;"));
    expect(body.length).toBeGreaterThan(500);
    // No ratio, percentage, rounding, or ordering by obligation kind decides an allocation.
    expect(body).not.toMatch(
      /\bround\(|\bfloor\(|\bceil\(|::numeric|\/\s*v_|\*\s*v_\w+_cents\s*\//,
    );
    // Every amount posted is the whole reversal on a single target (rules a, d), each
    // obligation's full original amount (rule b), or an Owner-recorded decision line (rule c).
    // Iteration order is fixed for determinism but never changes an amount.
    const amounts = [
      ...body.matchAll(/post_reversal_entry\(p_link\.project_id, p_type,\s*([^,]+?(?:\)\))?),/g),
    ].map((m) => m[1]!.replace(/\s+/g, " ").trim());
    expect(amounts.length).toBe(4);
    for (const amount of amounts) {
      expect(
        ["-p_amount", "-v_ob.original_cents"].includes(amount) ||
          /^-\(select l\.amount_cents from public\.refund_decision_lines l where l\.refund_decision_id = v_decision\.id and l\.obligation_id = v_ob\.id\)$/.test(
            amount,
          ),
        amount,
      ).toBe(true);
    }
    // Code only: the comments state the rule itself ("never deposit-first, ...").
    const code = payments.replace(/--[^\n]*/g, "");
    expect(code).not.toMatch(/deposit_first|maintenance_first|proportional/i);
    // Money is integer cents only (CLAUDE.md §3).
    // (Unix timestamps from Stripe are converted with to_timestamp(...::double precision).)
    const noTimestamps = code.replace(/to_timestamp\(\([^()]*\)::double precision\)/g, "");
    expect(noTimestamps).not.toMatch(/\b(?:numeric|decimal|real|double precision|money)\b(?!_)/i);
  });

  it("T-BIL-08, T-BIL-19: no registrar or domain-cancellation integration exists", () => {
    expect(
      offenders(/registrar|domain\.(?:cancel|delete|transfer)|cancelDomain|deleteDomain/i).filter(
        // WP-C records a registrar expiry date the Owner enters by hand (06 §10); that is a
        // field, not an integration. Any other registrar reference still fails.
        (path) =>
          sources
            .find((s) => s.path === path)!
            .text.replace(/registrar_?[Ee]xpiry|Registrar expiry/g, "")
            .match(/registrar|domain\.(?:cancel|delete|transfer)|cancelDomain|deleteDomain/i),
      ),
    ).toEqual([]);
  });

  it("T-BIL-18: no code path deliberately degrades a client website", () => {
    expect(offenders(/degrad|throttle(?:Site|Website)|disableSite|takedown|takeDown/i)).toEqual([]);
  });

  it("T-BIL-22: no R1 path offers or applies a discount, coupon, credit or waiver", () => {
    expect(
      offenders(
        /\bcoupon|promotion_code|allow_promotion_codes:\s*true|["']waiver["']|["']discount["']/i,
      ),
    ).toEqual([]);
  });

  it("the webhook route verifies the signature on the raw body before any database call", () => {
    const route = sources.find((s) => s.path === "src/app/api/stripe/webhook/route.ts")!.text;
    expect(route).toMatch(/await request\.text\(\)/);
    expect(route).not.toMatch(/request\.json\(\)/);
    const service = sources.find((s) => s.path === "src/server/services/billing.ts")!.text;
    const handler = service.slice(service.indexOf("export async function handleStripeWebhook"));
    expect(handler.indexOf("verifyStripeSignature(")).toBeGreaterThan(0);
    expect(handler.indexOf("verifyStripeSignature(")).toBeLessThan(handler.indexOf(".rpc("));
  });

  it("T-AGR-08: every page that shows agreement text renders it through AgreementDocument (fixture label)", () => {
    const showing = sources.filter(
      ({ path, text }) => path.startsWith("src/app/") && /canonical_text/.test(text),
    );
    expect(showing.length).toBeGreaterThan(0);
    for (const { path, text } of showing) expect(text, path).toMatch(/<AgreementDocument/);
  });
});

describe("WP-B environment rules (OI-69, CLAUDE.md §4)", () => {
  const base = {
    NEXT_PUBLIC_SITE_URL: "http://localhost:3000",
    NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:54321",
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: "sb_publishable_placeholder",
    SUPABASE_SECRET_KEY: "sb_secret_placeholder",
  };
  const issues = (source: Record<string, string>) => {
    try {
      parseServerEnv(source);
      return [];
    } catch (error) {
      return error instanceof EnvValidationError ? [...error.issues] : ["unexpected"];
    }
  };

  it("T-AGR-08: the environment schema rejects the test-only fixture when APP_ENV=production", () => {
    expect(
      issues({
        ...base,
        APP_ENV: "production",
        NEXT_PUBLIC_SUPABASE_URL: "https://x.supabase.co",
        AGREEMENT_TEST_FIXTURE: "enabled",
      }),
    ).toContain(
      "AGREEMENT_TEST_FIXTURE: the test-only agreement fixture is not allowed in production",
    );
    for (const appEnv of ["development", "test", "preview", "staging"]) {
      const supabase =
        appEnv === "staging" ? { NEXT_PUBLIC_SUPABASE_URL: "https://x.supabase.co" } : {};
      expect(
        issues({ ...base, ...supabase, APP_ENV: appEnv, AGREEMENT_TEST_FIXTURE: "enabled" }),
      ).toEqual([]);
    }
  });

  it("allows the mocked gateway only in development and test", () => {
    expect(issues({ ...base, APP_ENV: "test", STRIPE_GATEWAY: "mock" })).toEqual([]);
    expect(issues({ ...base, APP_ENV: "development", STRIPE_GATEWAY: "mock" })).toEqual([]);
    expect(issues({ ...base, APP_ENV: "preview", STRIPE_GATEWAY: "mock" })).toContain(
      "STRIPE_GATEWAY: the mocked Stripe gateway is allowed only in development and test",
    );
  });

  it("validates the webhook signing secret's shape without echoing it", () => {
    const found = issues({ ...base, APP_ENV: "test", STRIPE_WEBHOOK_SECRET: "not-a-secret-shape" });
    expect(found.some((i) => i.startsWith("STRIPE_WEBHOOK_SECRET"))).toBe(true);
    expect(found.join(" ")).not.toContain("not-a-secret-shape");
    expect(issues({ ...base, APP_ENV: "test", STRIPE_WEBHOOK_SECRET: "whsec_abc123" })).toEqual([]);
  });
});
