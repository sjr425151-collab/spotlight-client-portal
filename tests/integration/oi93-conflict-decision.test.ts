import { randomUUID } from "node:crypto";

import type { SupabaseClient } from "@supabase/supabase-js";
import { Client } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { withDb } from "../support/db";
import { signInWithCode, upgradeToAal2 } from "../support/local-supabase";

import {
  applyFinancialConflictDecision,
  CONFLICT_ACTION_DEADLINE_MS,
  listFinancialConflicts,
  readFinancialConflictAttemptStatus,
  recordFinancialConflictDecision,
} from "@/server/services/billing";

/**
 * AUTH-010 (OI-93) integration tests against the local stack: real concurrent database
 * connections, the Owner's real session through PostgREST, synthetic data only (signed synthetic
 * events are ingested as the webhook route records them; no Stripe request is made).
 *
 * Lock order of an application attempt: the attempt-request advisory lock, the decision row, the
 * event row, then the merged reversal order inside the extracted path (refund or dispute row,
 * the charge advisory lock, refund_decisions). It never takes an AUTH-009 lock. Each pair below
 * runs in both commit orders: the first transaction holds its locks, the second is shown to wait
 * (or not to wait), the first commits, and the outcome is asserted. Any database error other than
 * the asserted ones, a deadlock (40P01) included, fails a test.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const RUN = Date.now().toString(36);
const FACTORS_CLEANUP = `delete from auth.mfa_factors where user_id in (
  '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002')`;

// Session-local helpers for one setup transaction: the real WP-B workflow to a paid checkout,
// as in supabase/tests/195_wpb_conflict_decision.test.sql.
const SETUP_HELPERS = `
create function pg_temp.act_as(p_uid uuid, p_aal text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_uid, 'role', 'authenticated', 'aal', p_aal,
    'session_id', v_sid, 'amr', '[]'::jsonb)::text, true);
  set local role authenticated;
end; $$;
create function pg_temp.as_service() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  set local role service_role;
end; $$;
create function pg_temp.evt(p_id text, p_type text, p_obj jsonb) returns jsonb language sql as $$
  select jsonb_build_object('id', p_id, 'object', 'event', 'type', p_type, 'api_version', '2026-09-30.endive',
    'livemode', false, 'created', extract(epoch from now())::bigint, 'data', jsonb_build_object('object', p_obj));
$$;
grant execute on function pg_temp.evt(text, text, jsonb) to service_role;
create function pg_temp.deliver(p_event jsonb) returns jsonb language plpgsql as $$
declare v jsonb; r jsonb;
begin
  perform pg_temp.as_service();
  v := public.ingest_stripe_event(p_event, repeat('c', 64));
  r := public.process_stripe_event((v ->> 'webhook_event_id')::bigint);
  reset role;
  return r || jsonb_build_object('webhook_event_id', v -> 'webhook_event_id');
end; $$;
create function pg_temp.paid(p_tag text, p_invoice boolean) returns uuid language plpgsql as $$
declare
  v_business uuid; v_project uuid; v_os uuid; v_acc uuid; v_cs uuid; v_req record; v_tok uuid;
begin
  perform set_config('request.jwt.claims', '{"sub":"${OWNER_ID}","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('OI93 ' || p_tag || ' LLC', 'OI93 ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'OI93 ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '${CLIENT_A_ID}');
  perform pg_temp.act_as('${OWNER_ID}', 'aal2');
  v_os := (public.issue_order_summary(v_project, 'essential', '[]'::jsonb) ->> 'order_summary_id')::uuid;
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'OI93 ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
  v_cs := (public.begin_initial_checkout(v_project) ->> 'checkout_session_id')::uuid;
  reset role;
  perform pg_temp.as_service();
  for v_req in select id, purpose from public.outbound_stripe_requests where project_id = v_project
               order by (purpose = 'customer_create') desc loop
    v_tok := (public.outbound_request_for_execution(v_req.id) ->> 'claim_token')::uuid;
    perform public.confirm_outbound_dispatch(v_req.id, v_tok);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cus_T' || p_tag, false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cs_test_' || p_tag, false, 200, null,
        jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_' || p_tag));
    end if;
  end loop;
  reset role;
  perform pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'co', 'checkout.session.completed', jsonb_build_object(
    'id', 'cs_test_' || p_tag, 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
    'amount_total', 25900, 'payment_status', 'paid', 'customer', 'cus_T' || p_tag,
    'subscription', 'sub_' || p_tag, 'invoice', 'in_' || p_tag,
    'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
    'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
      'checkout_record_id', v_cs))));
  if p_invoice then
    perform pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'ii', 'invoice.paid', jsonb_build_object('id', 'in_' || p_tag,
      'object', 'invoice', 'billing_reason', 'subscription_create', 'currency', 'usd', 'amount_paid', 25900,
      'customer', 'cus_T' || p_tag, 'payment_intent', 'pi_' || p_tag,
      'parent', jsonb_build_object('subscription_details', jsonb_build_object('subscription', 'sub_' || p_tag,
        'metadata', jsonb_build_object('project_id', v_project, 'checkout_record_id', v_cs))),
      'lines', jsonb_build_object('data', jsonb_build_array(
        jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5HxK5j4r4WkVPkRUJ4gnZ')),
        jsonb_build_object('quantity', 1, 'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe')))))));
    perform pg_temp.deliver(pg_temp.evt('evt_' || p_tag || 'su', 'customer.subscription.created', jsonb_build_object(
      'id', 'sub_' || p_tag, 'object', 'subscription', 'status', 'active', 'customer', 'cus_T' || p_tag,
      'metadata', jsonb_build_object('project_id', v_project))));
  end if;
  return v_project;
end; $$;`;

interface Conflict {
  a: string;
  b: string;
  tag: string;
  eventId: number;
  refundId: string;
  decisionId: string;
}

let seq = 0;
/**
 * Project A (paid, initial invoice linked: it holds the charge's obligations), project B (paid,
 * with a recorded renewal charge whose obligation is not posted), and a refund naming A's payment
 * intent and B's charge: an attribution conflict that only A can resolve. With `decide`, the
 * Owner's decision for A is recorded.
 */
async function conflict(decide = true): Promise<Conflict> {
  seq += 1;
  const tag = `X${seq}${RUN}`;
  const refundId = `re_${tag}`;
  return withDb(async (db) => {
    await db.query("begin");
    await db.query(SETUP_HELPERS);
    const a = (await db.query("select pg_temp.paid($1, true) as p", [`${tag}a`])).rows[0]
      .p as string;
    const b = (await db.query("select pg_temp.paid($1, false) as p", [`${tag}b`])).rows[0]
      .p as string;
    await db.query("reset role");
    await db.query(
      `insert into private.stripe_payment_links (stripe_ref, project_id, kind, domain_record_id, stripe_invoice_id)
       values ($1, $2, 'renewal', null, $3)`,
      [`ch_${tag}b`, b, `in_${tag}brenew`],
    );
    const r = (
      await db.query(
        `select pg_temp.deliver(pg_temp.evt($1, 'refund.updated', jsonb_build_object('id', $2::text, 'object', 'refund',
           'amount', 500, 'currency', 'usd', 'status', 'succeeded', 'payment_intent', $3::text, 'charge', $4::text,
           'metadata', '{}'::jsonb))) as r`,
        [`evt_${tag}cf`, refundId, `pi_${tag}a`, `ch_${tag}b`],
      )
    ).rows[0].r as { reason: string; webhook_event_id: number };
    expect(r.reason).toBe("attribution_conflict");
    await db.query("reset role");
    await db.query("commit");
    let decisionId = "";
    if (decide) {
      const c = await open("owner");
      const d = await one(
        c,
        "public.record_financial_conflict_decision($1, $2, '{\"references\": \"synthetic\"}', 'Owner reviewed')",
        [r.webhook_event_id, a],
      );
      await done(c);
      expect(d.ok).toBe(true);
      decisionId = d.decision_id as string;
    }
    return { a, b, tag, eventId: r.webhook_event_id, refundId, decisionId };
  });
}

function local(): string {
  const url =
    process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("local only");
  return url;
}
/** A connection in an open transaction: the server (service_role), the Owner, or raw. */
async function open(as: "service" | "owner" | "raw"): Promise<Client> {
  const c = new Client({ connectionString: local() });
  await c.connect();
  await c.query("begin");
  if (as === "service") {
    await c.query("select set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)");
    await c.query("set local role service_role");
  } else if (as === "owner") {
    const sid = randomUUID();
    await withDb(async (db) => {
      await db.query(
        "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), 'aal2')",
        [sid, OWNER_ID],
      );
      await db.query(
        `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
         select gen_random_uuid(), $1, 'it-oi93', 'totp', 'verified', now(), now()
         where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
        [OWNER_ID],
      );
    });
    const claims = {
      sub: OWNER_ID,
      role: "authenticated",
      aal: "aal2",
      session_id: sid,
      amr: [{ method: "totp", timestamp: Math.floor(Date.now() / 1000) }],
    };
    await c.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)]);
    await c.query("set local role authenticated");
  }
  return c;
}
async function done(c: Client) {
  await c.query("commit");
  await c.end();
}
type Json = Record<string, unknown>;
async function one(c: Client, sql: string, params: unknown[] = []): Promise<Json> {
  const { rows } = await c.query(`select (${sql}) as r`, params);
  return rows[0].r as Json;
}
const attempt = (c: Client, decisionId: string, requestId: string) =>
  one(c, "public.retry_financial_conflict_application($1, $2, 'Apply the recorded decision')", [
    decisionId,
    requestId,
  ]);
const status = (c: Client, requestId: string) =>
  one(c, "public.financial_conflict_attempt_status($1)", [requestId]);
const pidOf = async (c: Client) =>
  (await c.query("select pg_backend_pid() as p")).rows[0].p as number;

/** Waits until `pid` is blocked by another backend; returns the lock type it waits on. */
async function waitsOn(pid: number): Promise<string | null> {
  for (let i = 0; i < 60; i++) {
    const kind = await withDb(async (db) => {
      const { rows } = await db.query(
        `select cardinality(pg_blocking_pids($1)) > 0 as blocked, a.wait_event_type || ':' || a.wait_event as w
           from pg_stat_activity a where a.pid = $1`,
        [pid],
      );
      return rows[0]?.blocked ? (rows[0].w as string) : null;
    });
    if (kind) return kind;
    await new Promise((r) => setTimeout(r, 50));
  }
  return null;
}
/** The strongest relation lock modes `pid` holds on the AUTH-009 tables. */
async function auth009Locks(pid: number): Promise<string[]> {
  return withDb(async (db) => {
    const { rows } = await db.query(
      `select distinct c.relname || ':' || l.mode as m from pg_locks l join pg_class c on c.oid = l.relation
        where l.pid = $1 and c.relname in ('payment_authorizations', 'final_balance_invoices', 'outbound_stripe_requests')
          and l.mode <> 'AccessShareLock' order by 1`,
      [pid],
    );
    return rows.map((r) => r.m as string);
  });
}
const ledger = (refundId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select count(*)::int as n, coalesce(sum(amount_cents), 0)::int as total from public.ledger_entries
        where stripe_object_id = $1`,
      [refundId],
    );
    return rows[0] as { n: number; total: number };
  });
const applications = (eventId: number) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select attempt_no, outcome, attempt_request_id from private.financial_conflict_applications
        where webhook_event_id = $1 order by attempt_no`,
      [eventId],
    );
    return rows as { attempt_no: number; outcome: string; attempt_request_id: string }[];
  });
/** Another event for the same refund, attributable to A alone (the normal webhook path). */
const sameRefundWebhook = (c: Client, f: Conflict, n: number) =>
  one(
    c,
    `public.process_stripe_event((public.ingest_stripe_event(jsonb_build_object('id', $1::text, 'object', 'event',
       'type', 'refund.updated', 'api_version', '2026-09-30.endive', 'livemode', false,
       'created', extract(epoch from now())::bigint + 5, 'data', jsonb_build_object('object', jsonb_build_object(
         'id', $2::text, 'object', 'refund', 'amount', 500, 'currency', 'usd', 'status', 'succeeded',
         'payment_intent', $3::text, 'metadata', '{}'::jsonb))), repeat('d', 64)) ->> 'webhook_event_id')::bigint)`,
    [`evt_${f.tag}w${n}`, f.refundId, `pi_${f.tag}a`],
  );
/** A renewal invoice.paid for project A (the AUTH-009 invoice path on the same project). */
const renewalPaid = (c: Client, f: Conflict, n: number) =>
  one(
    c,
    `public.process_stripe_event((public.ingest_stripe_event(jsonb_build_object('id', $1::text, 'object', 'event',
       'type', 'invoice.paid', 'api_version', '2026-09-30.endive', 'livemode', false,
       'created', extract(epoch from now())::bigint + 5, 'data', jsonb_build_object('object', jsonb_build_object(
         'id', $2::text, 'object', 'invoice', 'billing_reason', 'subscription_cycle', 'currency', 'usd',
         'amount_paid', 9900, 'customer', $3::text, 'subscription', $4::text, 'payment_intent', $5::text,
         'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
           'price', jsonb_build_object('id', 'price_1Uf5I2K5j4r4WkVPJodSnaBe'))))))), repeat('e', 64)) ->> 'webhook_event_id')::bigint)`,
    [
      `evt_${f.tag}r${n}`,
      `in_${f.tag}r${n}`,
      `cus_T${f.tag}a`,
      `sub_${f.tag}a`,
      `pi_${f.tag}r${n}`,
    ],
  );

const totpSecrets = new Map<string, string>();
let owner: SupabaseClient;
let admin: SupabaseClient;

async function signIn(email: string): Promise<SupabaseClient> {
  for (let attempt = 0; ; attempt++) {
    try {
      return await signInWithCode(email);
    } catch (error) {
      if (attempt >= 3 || !String(error).includes("over_email_send_rate_limit")) throw error;
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }
}

beforeAll(async () => {
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(FACTORS_CLEANUP);
  });
  owner = await signIn("owner@example.test");
  await upgradeToAal2(owner, totpSecrets);
  admin = await signIn("admin@example.test");
  await upgradeToAal2(admin, totpSecrets);
});

afterAll(async () => {
  await withDb(async (db) => {
    await db.query("delete from private.rate_limits");
    await db.query(FACTORS_CLEANUP);
  });
});

describe("AUTH-010: the Owner's real session through PostgREST", () => {
  it("records a decision, applies it once, reads its status and lists it; Admin is refused", async () => {
    const f = await conflict(false);
    const refused = await recordFinancialConflictDecision(admin, {
      webhookEventId: f.eventId,
      projectId: f.a,
      evidence: "Stripe Dashboard review",
      reason: "Admin attempt",
    });
    expect(refused).toEqual({ ok: false, error: "forbidden" });
    const decided = await recordFinancialConflictDecision(owner, {
      webhookEventId: f.eventId,
      projectId: f.a,
      evidence: "Stripe Dashboard review of the refund and charge",
      reason: "The refund belongs to project A's initial charge",
    });
    expect(decided.ok).toBe(true);
    const decisionId = (decided as unknown as { decision_id: string }).decision_id;
    const requestId = randomUUID();
    const input = { decisionId, attemptRequestId: requestId, reason: "Apply the decision" };
    const first = await applyFinancialConflictDecision(owner, input, {
      startedAt: performance.now(),
    });
    expect(first).toMatchObject({
      ok: true,
      existing: false,
      attempt: { outcome: "posted", cleared: true },
    });
    const again = await applyFinancialConflictDecision(owner, input, {
      startedAt: performance.now(),
    });
    expect(again).toMatchObject({ ok: true, existing: true, attempt: { outcome: "posted" } });
    expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
    expect(await readFinancialConflictAttemptStatus(owner, requestId)).toMatchObject({
      ok: true,
      status: "recorded",
      conclusive: true,
    });
    const list = await listFinancialConflicts(owner);
    expect(list.ok).toBe(true);
    const listed = (
      list as { events: { webhook_event_id: number; cleared: boolean }[] }
    ).events.find((e) => e.webhook_event_id === f.eventId);
    expect(listed?.cleared).toBe(true);
    expect(await listFinancialConflicts(admin)).toEqual({ ok: false, error: "forbidden" });
    expect(
      await applyFinancialConflictDecision(
        admin,
        { ...input, attemptRequestId: randomUUID() },
        { startedAt: performance.now() },
      ),
    ).toEqual({ ok: false, error: "forbidden" });
  });
});

describe("AUTH-010: serialization of attempts", () => {
  it("two attempts on one decision: the second waits on the decision row and is refused after the first posts", async () => {
    const f = await conflict();
    const c1 = await open("owner");
    const c2 = await open("owner");
    try {
      const r1 = await attempt(c1, f.decisionId, randomUUID());
      expect((r1.attempt as Json).outcome).toBe("posted");
      const pid1 = await pidOf(c2);
      const pending = attempt(c2, f.decisionId, randomUUID());
      expect(await waitsOn(pid1)).toBe("Lock:transactionid");
      await c1.query("commit");
      const r2 = await pending;
      expect(r2).toMatchObject({ ok: false, error: "already_applied" });
      await c2.query("commit");
    } finally {
      await c1.end();
      await c2.end();
    }
    expect((await applications(f.eventId)).map((a) => a.outcome)).toEqual(["posted"]);
    expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
  });

  it("the same attempt_request_id concurrently: the second waits, then returns the recorded attempt; the status read never waits", async () => {
    const f = await conflict();
    const requestId = randomUUID();
    const c1 = await open("owner");
    const c2 = await open("owner");
    const c3 = await open("owner");
    try {
      await attempt(c1, f.decisionId, requestId);
      expect(await status(c3, requestId)).toMatchObject({
        status: "in_progress",
        conclusive: false,
      });
      const pid2 = await pidOf(c2);
      const pending = attempt(c2, f.decisionId, requestId);
      expect(await waitsOn(pid2)).toBe("Lock:advisory");
      await c1.query("commit");
      expect(await pending).toMatchObject({
        ok: true,
        existing: true,
        attempt: { outcome: "posted" },
      });
      await c2.query("commit");
      expect(await status(c3, requestId)).toMatchObject({ status: "recorded", conclusive: true });
      await c3.query("commit");
    } finally {
      await c1.end();
      await c2.end();
      await c3.end();
    }
    expect(await applications(f.eventId)).toHaveLength(1);
  });
});

describe("AUTH-010: the attempt against the same refund's webhook (both orders)", () => {
  it("attempt first: the webhook waits on the refund row, then fails retryably; its retry counts the refund once", async () => {
    const f = await conflict();
    const c1 = await open("owner");
    const c2 = await open("service");
    let webhookId = 0;
    try {
      expect(((await attempt(c1, f.decisionId, randomUUID())).attempt as Json).outcome).toBe(
        "posted",
      );
      const pid3 = await pidOf(c2);
      const pending = sameRefundWebhook(c2, f, 1);
      expect(await waitsOn(pid3)).toBe("Lock:transactionid");
      await c1.query("commit");
      expect(await pending).toMatchObject({ ok: false, status: "failed" });
      await c2.query("commit");
      webhookId = await withDb(async (db) =>
        Number(
          (
            await db.query("select id from public.webhook_events where stripe_event_id = $1", [
              `evt_${f.tag}w1`,
            ])
          ).rows[0].id,
        ),
      );
    } finally {
      await c1.end();
      await c2.end();
    }
    const retry = await open("service");
    expect(await one(retry, "public.process_stripe_event($1)", [webhookId])).toMatchObject({
      ok: true,
      status: "processed",
    });
    await done(retry);
    expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
  });

  it("webhook first: the attempt waits on the refund row, then records operational_failure and keeps nothing", async () => {
    const f = await conflict();
    const c1 = await open("service");
    const c2 = await open("owner");
    try {
      expect(await sameRefundWebhook(c1, f, 2)).toMatchObject({ ok: true, status: "processed" });
      const pid4 = await pidOf(c2);
      const pending = attempt(c2, f.decisionId, randomUUID());
      expect(await waitsOn(pid4)).toBe("Lock:transactionid");
      await c1.query("commit");
      const r = await pending;
      expect(r.attempt as Json).toMatchObject({
        outcome: "operational_failure",
        detail: { stage: "operational", sqlstate: "23505" },
      });
      await c2.query("commit");
    } finally {
      await c1.end();
      await c2.end();
    }
    // Only the webhook's posting exists; the failed step kept nothing; the next attempt waits 60 s.
    expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
    const c = await open("owner");
    expect(await attempt(c, f.decisionId, randomUUID())).toMatchObject({
      ok: false,
      error: "retry_too_soon",
    });
    await done(c);
  });
});

describe("AUTH-010: the re-check under the charge lock", () => {
  it("a posting under another project that commits between classification and posting is refused (recognized_under_other_project)", async () => {
    const f = await conflict();
    // A concurrent transaction holds A's charge lock and records a reversal of this refund under
    // B (a synthetic stand-in for a concurrent posting): classification cannot see it yet.
    const other = await open("raw");
    const c = await open("owner");
    try {
      await other.query(
        `select pg_advisory_xact_lock(hashtextextended('wpb:charge:initial:' || id::text, 0))
           from public.checkout_sessions where project_id = $1`,
        [f.a],
      );
      await other.query(
        `insert into public.ledger_entries (project_id, entry_type, amount_cents, source, webhook_event_id,
           stripe_object_type, stripe_object_id, holding_charge_key, dedupe_key)
         select $1, 'refund', -500, 'webhook', w.id, 'refund', $3, $4, $3 || ':refund:holding:concurrent'
           from public.webhook_events w where w.stripe_event_id = $2`,
        [f.b, `evt_${f.tag}bco`, f.refundId, `renewal:in_${f.tag}brenew`],
      );
      const pid = await pidOf(c);
      const pending = attempt(c, f.decisionId, randomUUID());
      expect(await waitsOn(pid)).toBe("Lock:advisory");
      await other.query("commit");
      const r = await pending;
      expect(r.attempt as Json).toMatchObject({
        outcome: "permanently_unsupported",
        detail: { stage: "post_check", reason: "recognized_under_other_project" },
      });
      await c.query("commit");
    } finally {
      await other.end();
      await c.end();
    }
    expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
    const refunds = await withDb(
      async (db) =>
        (
          await db.query(
            "select count(*)::int as n from public.refunds where stripe_refund_id = $1",
            [f.refundId],
          )
        ).rows[0].n as number,
    );
    expect(refunds).toBe(0);
  });
});

describe("AUTH-010: the attempt against invoice.paid on the same project (both orders)", () => {
  for (const order of ["attempt first", "invoice first"] as const) {
    it(`${order}: neither waits; the attempt holds no AUTH-009 lock`, async () => {
      const f = await conflict();
      const ca = await open("owner");
      const ci = await open("service");
      try {
        if (order === "attempt first") {
          expect(((await attempt(ca, f.decisionId, randomUUID())).attempt as Json).outcome).toBe(
            "posted",
          );
          expect(await auth009Locks(await pidOf(ca))).toEqual([]);
          expect(await renewalPaid(ci, f, 1)).toMatchObject({ ok: true, status: "processed" });
        } else {
          expect(await renewalPaid(ci, f, 2)).toMatchObject({ ok: true, status: "processed" });
          expect(((await attempt(ca, f.decisionId, randomUUID())).attempt as Json).outcome).toBe(
            "posted",
          );
          expect(await auth009Locks(await pidOf(ca))).toEqual([]);
        }
        await ca.query("commit");
        await ci.query("commit");
      } finally {
        await ca.end();
        await ci.end();
      }
      expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
    });
  }
});

describe("AUTH-010 U-4: effective timeouts through PostgREST", () => {
  it("55P03 at about 5 s: the wrapper's lock_timeout bounds a wait on the decision row; nothing is recorded", async () => {
    const f = await conflict();
    const holder = await open("raw");
    try {
      await holder.query(
        "select 1 from private.financial_conflict_decisions where id = $1 for update",
        [f.decisionId],
      );
      const requestId = randomUUID();
      const t0 = performance.now();
      const { error } = await owner.rpc("retry_financial_conflict_application", {
        p_decision_id: f.decisionId,
        p_attempt_request_id: requestId,
        p_reason: "lock wait",
      });
      const elapsed = performance.now() - t0;
      expect(error?.code).toBe("55P03");
      expect(elapsed).toBeGreaterThan(4_500);
      expect(elapsed).toBeLessThan(7_500);
      expect(await applications(f.eventId)).toEqual([]);
    } finally {
      await holder.query("rollback");
      await holder.end();
    }
  });

  // I-1 (a): each call waits on the exact lock its private function takes, held by another client.
  const cases = [
    {
      name: "record_financial_conflict_decision on the event row",
      decide: false,
      hold: "select 1 from public.webhook_events where id = $1 for update",
      key: (f: Conflict) => [f.eventId],
      call: (f: Conflict) =>
        owner.rpc("record_financial_conflict_decision", {
          p_webhook_event_id: f.eventId,
          p_project_id: f.a,
          p_evidence: { references: "lock probe" },
          p_reason: "lock probe",
        }),
    },
    {
      name: "retry_financial_conflict_application on the event row",
      decide: true,
      hold: "select 1 from public.webhook_events where id = $1 for update",
      key: (f: Conflict) => [f.eventId],
      call: (f: Conflict) =>
        owner.rpc("retry_financial_conflict_application", {
          p_decision_id: f.decisionId,
          p_attempt_request_id: randomUUID(),
          p_reason: "lock probe",
        }),
    },
  ] as const;
  for (const c of cases) {
    it(`55P03 at about 5 s: ${c.name}`, async () => {
      const f = await conflict(c.decide);
      const holder = await open("raw");
      try {
        await holder.query(c.hold, c.key(f));
        const t0 = performance.now();
        const { error } = await c.call(f);
        const elapsed = performance.now() - t0;
        expect(error?.code).toBe("55P03");
        expect(elapsed).toBeGreaterThan(4_500);
        expect(elapsed).toBeLessThan(7_500);
      } finally {
        await holder.query("rollback");
        await holder.end();
      }
      expect(await applications(f.eventId)).toEqual([]);
    });
  }

  it("55P03 at about 5 s: retry_financial_conflict_application on its attempt_request_id lock", async () => {
    const f = await conflict();
    const requestId = randomUUID();
    const holder = await open("raw");
    try {
      await holder.query(
        "select pg_advisory_xact_lock(hashtextextended('wpb:oi93:attempt:' || $1::text, 0))",
        [requestId],
      );
      const t0 = performance.now();
      const { error } = await owner.rpc("retry_financial_conflict_application", {
        p_decision_id: f.decisionId,
        p_attempt_request_id: requestId,
        p_reason: "lock probe",
      });
      const elapsed = performance.now() - t0;
      expect(error?.code).toBe("55P03");
      expect(elapsed).toBeGreaterThan(4_500);
      expect(elapsed).toBeLessThan(7_500);
    } finally {
      await holder.query("rollback");
      await holder.end();
    }
    expect(await applications(f.eventId)).toEqual([]);
  });

  it("57014 at about 8 s: the effective statement limit of the API path (an Owner RPC with no lock_timeout)", async () => {
    const f = await conflict(false);
    const holder = await open("raw");
    try {
      await holder.query("select 1 from public.webhook_events where id = $1 for update", [
        f.eventId,
      ]);
      const t0 = performance.now();
      const { error } = await owner.rpc("resolve_quarantined_event", {
        p_webhook_event_id: f.eventId,
        p_resolution: "timeout probe",
      });
      const elapsed = performance.now() - t0;
      expect(error?.code).toBe("57014");
      expect(elapsed).toBeGreaterThan(7_500);
      expect(elapsed).toBeLessThan(10_500);
    } finally {
      await holder.query("rollback");
      await holder.end();
    }
  });
});

describe("AUTH-010: the server action deadline and unknown outcomes", () => {
  it("is 45 seconds from entry; an expired deadline sends nothing", async () => {
    expect(CONFLICT_ACTION_DEADLINE_MS).toBe(45_000);
    let now = 1_000;
    const clock = { now: () => now };
    const startedAt = clock.now();
    now += 45_001;
    expect(
      await applyFinancialConflictDecision(
        owner,
        { decisionId: randomUUID(), attemptRequestId: randomUUID(), reason: "late" },
        { startedAt, clock },
      ),
    ).toEqual({ ok: false, error: "deadline_exceeded" });
  });

  it("a client abort reports outcome_unknown with its id; the status read is not conclusive; the same id resolves it", async () => {
    const f = await conflict();
    const holder = await open("raw");
    const requestId = randomUUID();
    const input = { decisionId: f.decisionId, attemptRequestId: requestId, reason: "deadline" };
    try {
      await holder.query(
        "select 1 from private.financial_conflict_decisions where id = $1 for update",
        [f.decisionId],
      );
      const r = await applyFinancialConflictDecision(owner, input, {
        startedAt: performance.now(),
        deadlineMs: 1_500,
      });
      expect(r).toEqual({ ok: false, error: "outcome_unknown", attemptRequestId: requestId });
      const s = await readFinancialConflictAttemptStatus(owner, requestId);
      expect(s).toMatchObject({ ok: true, conclusive: false });
    } finally {
      await holder.query("rollback");
      await holder.end();
    }
    // Whatever the aborted request did, resubmitting the same id yields one durable attempt.
    const resolved = await applyFinancialConflictDecision(owner, input, {
      startedAt: performance.now(),
    });
    expect(resolved).toMatchObject({ ok: true, attempt: { outcome: "posted" } });
    expect(await readFinancialConflictAttemptStatus(owner, requestId)).toMatchObject({
      status: "recorded",
      conclusive: true,
    });
    expect((await applications(f.eventId)).map((a) => a.attempt_request_id)).toEqual([requestId]);
    expect(await ledger(f.refundId)).toEqual({ n: 1, total: -500 });
  });
});
