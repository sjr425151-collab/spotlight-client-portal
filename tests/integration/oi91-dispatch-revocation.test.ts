import { randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, describe, expect, it, vi } from "vitest";

import { withDb } from "../support/db";
import { adminClient } from "../support/local-supabase";

vi.mock("@/server/supabase/admin", async () => {
  const support = await import("../support/local-supabase");
  return { createAdminClient: async () => support.adminClient() };
});

import { executeOutboundRequest } from "@/server/services/billing";
import { MockStripeGateway } from "@/server/stripe/mock-gateway";

/**
 * AUTH-009 (OI-91) integration tests against the local stack, with real concurrent database
 * connections and synthetic data only (no Stripe request; the gateway is the mock).
 *
 * The lock hierarchy is payment authorization, then final-balance invoice, then outbound
 * request, in outbound_request_for_execution, confirm_outbound_dispatch, record_outbound_result,
 * reconcile_outbound_request, handle_invoice_failed and handle_final_balance_paid; revocation
 * (and detachment) already lock the authorization, then the invoice. Each function is raced
 * against the Owner's recorded revocation in both commit orders: the first transaction holds its
 * locks, the second is shown to wait on the payment authorization row, the first commits, and
 * the outcome is asserted (no automatic charge after revocation; one stop request). Each
 * function is also probed directly: it must wait for a higher lock while holding no lower one.
 * Any database error, a deadlock (40P01) included, fails a test. Claim tokens stay in memory.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";
const RUN = Date.now().toString(36);

// Session-local helpers for one setup transaction, as in tests/integration/wph-hardening.test.ts:
// the real WP-B workflow to a verified deposit and an active card, then WP-C's real intake,
// release and approval.
const SETUP_HELPERS = `
create function pg_temp.act_as(p_uid uuid, p_aal text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'it-oi91', 'totp', 'verified', now(), now()
    where not exists (select 1 from auth.mfa_factors where user_id = p_uid and status = 'verified');
  end if;
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
create function pg_temp.ready(p_tag text, p_sha text) returns jsonb language plpgsql as $$
declare
  v_business uuid; v_project uuid; v_os uuid; v_acc uuid; v_cs uuid; v_req record; v jsonb; v_tok uuid;
  v_draft uuid; v_sub uuid; v_release uuid; v_approval uuid;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"${OWNER_ID}","role":"authenticated","aal":"aal2"}', true);
  insert into public.client_businesses (legal_name, display_name) values ('OI91 ' || p_tag || ' LLC', 'OI91 ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'OI91 ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '${CLIENT_A_ID}');
  perform pg_temp.act_as('${OWNER_ID}', 'aal2');
  v_os := (public.issue_order_summary(v_project, 'essential', '[]'::jsonb) ->> 'order_summary_id')::uuid;
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'OI91 ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
  v_cs := (public.begin_initial_checkout(v_project) ->> 'checkout_session_id')::uuid;
  reset role;
  perform pg_temp.as_service();
  for v_req in select id, purpose from public.outbound_stripe_requests where project_id = v_project
               order by (purpose = 'customer_create') desc loop
    -- AUTH-009 (setup): claim, confirm with the one-time token, then record with it.
    v_tok := (public.outbound_request_for_execution(v_req.id) ->> 'claim_token')::uuid;
    perform public.confirm_outbound_dispatch(v_req.id, v_tok);
    if v_req.purpose = 'customer_create' then
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cus_W' || p_tag, false, 200, null, '{}');
    else
      perform public.record_outbound_result(v_req.id, v_tok, 'succeeded', 'cs_test_W' || p_tag, false, 200, null,
        jsonb_build_object('url', 'https://checkout.stripe.com/c/pay/cs_test_W' || p_tag));
    end if;
  end loop;
  v := public.ingest_stripe_event(pg_temp.evt('evt_W' || p_tag, 'checkout.session.completed', jsonb_build_object(
    'id', 'cs_test_W' || p_tag, 'object', 'checkout.session', 'mode', 'subscription', 'currency', 'usd',
    'amount_total', 25900, 'payment_status', 'paid', 'customer', 'cus_W' || p_tag,
    'subscription', 'sub_W' || p_tag, 'invoice', 'in_W' || p_tag,
    'total_details', jsonb_build_object('amount_discount', 0, 'amount_tax', 0),
    'metadata', jsonb_build_object('project_id', v_project, 'order_summary_id', v_os, 'acceptance_id', v_acc,
      'checkout_record_id', v_cs))), repeat('c', 64));
  perform public.process_stripe_event((v ->> 'webhook_event_id')::bigint);
  perform public.record_payment_method_lookup('initial', v_cs, 'pm_W' || p_tag, 'cus_W' || p_tag, false, true);
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_draft := (public.save_intake_draft(v_project, jsonb_build_object('business_legal_name', 'OI91 LLC',
    'business_display_name', 'OI91', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
    'address', '1 Test Street', 'service_areas', 'Test City', 'services_offered', 'Testing',
    'domain_status', 'needs_domain')) ->> 'draft_id')::uuid;
  v_sub := (public.submit_intake(v_project, v_draft) ->> 'submission_id')::uuid;
  reset role;
  perform pg_temp.act_as('${ADMIN_ID}', 'aal2');
  perform public.review_intake(v_sub, 'accepted', 'Accepted');
  -- AUTH-023 (setup only, OD-11(ii)): the scope confirmation (the Admin) and its acknowledgment by the
  -- authorized signer (client A, who accepted the agreement), before the release.
  if not coalesce((public.record_scope_confirmation(v_project, 'Synthetic client requirements', array['Synthetic selection'],
      '{}') ->> 'ok')::boolean, false) then
    raise exception 'fixture: record_scope_confirmation failed';
  end if;
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  if not coalesce((public.acknowledge_scope_confirmation(
      (select c.id from public.scope_confirmations c where c.project_id = v_project order by c.version desc limit 1),
      (select c.content_sha256 from public.scope_confirmations c where c.project_id = v_project order by c.version desc limit 1),
      true, true) ->> 'ok')::boolean, false) then
    raise exception 'fixture: acknowledge_scope_confirmation failed';
  end if;
  reset role;
  perform pg_temp.act_as('${ADMIN_ID}', 'aal2');
  v_release := (public.release_preview(v_project, p_sha, 'dpl_w' || p_tag, 'https://preview.example.test/oi91', '{}')
    ->> 'release_id')::uuid;
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_approval := (public.approve_preview(v_release) ->> 'approval_id')::uuid;
  reset role;
  return jsonb_build_object('project_id', v_project, 'release_id', v_release, 'approval_id', v_approval,
    'event_id', (select id from public.domain_events where dedupe_key = 'release.approved:' || v_release));
end; $$;`;

const sha = () => (randomUUID() + randomUUID()).replace(/-/g, "").slice(0, 40);
const projects: string[] = [];
/** Claim tokens of this file's requests, in memory only (never logged or asserted by value). */
const tokens = new Map<string, string>();

interface Fixture {
  projectId: string;
  fbiId: string;
  createId: string;
}

/** A verified deposit, an active card, an approved release, and the initiated obligation. */
async function initiated(label: string): Promise<Fixture> {
  const tag = `D${label}${RUN}`;
  const r = await withDb(async (db) => {
    await db.query("begin");
    await db.query(SETUP_HELPERS);
    const { rows } = await db.query("select pg_temp.ready($1, $2) as r", [tag, sha()]);
    const ready = rows[0].r as { project_id: string; event_id: number };
    await db.query("reset role");
    await db.query("select set_config('request.jwt.claims', '', true)");
    const consumed = await db.query("select private.consume_release_approved($1) as o", [
      ready.event_id,
    ]);
    expect(consumed.rows[0].o).toBe("created");
    const ids = await db.query(
      `select f.id as fbi, o.id as req from public.final_balance_invoices f
         join public.outbound_stripe_requests o on o.domain_record_id = f.id and o.purpose = 'final_balance_invoice_create'
        where f.project_id = $1 and f.collection_mode = 'automatic'`,
      [ready.project_id],
    );
    await db.query("commit");
    return { projectId: ready.project_id, fbiId: ids.rows[0].fbi, createId: ids.rows[0].req };
  });
  projects.push(r.projectId);
  return r as Fixture;
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
         select gen_random_uuid(), $1, 'it-oi91', 'totp', 'verified', now(), now()
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

// The operations under test, each on a connection with its real caller's role.
async function claim(c: Client, id: string): Promise<Json> {
  const { rows } = await c.query(
    "select r - 'claim_token' as r, r ->> 'claim_token' as t from public.outbound_request_for_execution($1) r",
    [id],
  );
  if (rows[0].t) tokens.set(id, rows[0].t as string);
  return rows[0].r as Json;
}
const confirm = (c: Client, id: string) =>
  one(c, "public.confirm_outbound_dispatch($1, $2)", [id, tokens.get(id) ?? null]);
const record = (c: Client, id: string, outcome: string, objectId: string | null, code?: string) =>
  one(c, "public.record_outbound_result($1, $2, $3, $4, $5, $6, $7, '{}')", [
    id,
    tokens.get(id) ?? null,
    outcome,
    objectId,
    outcome === "succeeded" ? false : null,
    outcome === "succeeded" ? 200 : null,
    code ?? null,
  ]);
const reconcile = (c: Client, id: string, objectId: string) =>
  one(c, "public.reconcile_outbound_request($1, true, $2, 'Found in the test-mode Dashboard')", [
    id,
    objectId,
  ]);
const revoke = (c: Client, projectId: string) =>
  one(c, "public.record_payment_authorization_revocation($1, 'Client revoked in writing')", [
    projectId,
  ]);
/** A synthetic invoice event for the final-balance invoice, ingested and processed (OI-63). */
const invoiceEvent = (c: Client, fbiId: string, type: "invoice.paid" | "invoice.payment_failed") =>
  one(
    c,
    `public.process_stripe_event((public.ingest_stripe_event(jsonb_build_object('id', $2::text, 'object', 'event',
       'type', $3::text, 'api_version', '2026-09-30.endive', 'livemode', false, 'created', extract(epoch from now())::bigint + 5,
       'data', jsonb_build_object('object', (select jsonb_build_object('id', f.stripe_invoice_id, 'object', 'invoice',
         'billing_reason', 'manual', 'currency', 'usd', 'amount_paid', f.amount_cents, 'customer', f.stripe_customer_id,
         'payment_intent', 'pi_' || replace(f.id::text, '-', ''), 'default_payment_method', f.default_payment_method_id,
         'metadata', jsonb_build_object('project_id', f.project_id, 'order_summary_id', f.order_summary_id,
           'final_balance_invoice_id', f.id),
         'lines', jsonb_build_object('data', jsonb_build_array(jsonb_build_object('quantity', 1,
           'price', jsonb_build_object('id', f.balance_price_id))))) from public.final_balance_invoices f where f.id = $1))),
       repeat('d', 64)) ->> 'webhook_event_id')::bigint)`,
    [fbiId, `evt_D${randomUUID().replace(/-/g, "").slice(0, 20)}`, type],
  );

/** Commits one service-role step: claim, confirm, record. */
async function step<T>(as: "service" | "owner", fn: (c: Client) => Promise<T>): Promise<T> {
  const c = await open(as);
  try {
    return await fn(c);
  } finally {
    await done(c);
  }
}
async function claimed(f: Fixture) {
  expect((await step("service", (c) => claim(c, f.createId))).ok).toBe(true);
}
async function confirmed(f: Fixture) {
  await claimed(f);
  expect((await step("service", (c) => confirm(c, f.createId))).confirmed).toBe(true);
}
async function opened(f: Fixture) {
  await confirmed(f);
  const r = await step("service", (c) =>
    record(c, f.createId, "succeeded", `in_D${f.fbiId.slice(0, 8)}`),
  );
  expect(r.status).toBe("succeeded");
}
async function ambiguous(f: Fixture) {
  await confirmed(f);
  const r = await step("service", (c) =>
    record(c, f.createId, "ambiguous", null, "network_timeout"),
  );
  expect(r.status).toBe("ambiguous");
}

/** Waits until `pid` waits on a row lock; returns the table whose row it waits for. */
async function waitsOnRowOf(pid: number): Promise<string | null> {
  // OI-122: one sample can see the waiter blocked before its tuple lock is visible to the same
  // query (pg_locks and pg_blocking_pids are read at different instants). Such a sample is not
  // an answer: keep polling until the table is identified, within the same bounded deadline.
  let last: string | null = null;
  for (let i = 0; i < 40; i++) {
    const rel = await withDb(async (db) => {
      const { rows } = await db.query(
        `select (select c.relname::text from pg_locks l join pg_class c on c.oid = l.relation
                  where l.pid = $1 and l.locktype = 'tuple' limit 1) as rel,
                cardinality(pg_blocking_pids($1)) > 0 as blocked`,
        [pid],
      );
      return rows[0].blocked ? ((rows[0].rel as string | null) ?? "unknown") : null;
    });
    if (rel && rel !== "unknown") return rel;
    last = rel ?? last;
    await new Promise((r) => setTimeout(r, 50));
  }
  return last;
}
const pidOf = async (c: Client) =>
  (await c.query("select pg_backend_pid() as p")).rows[0].p as number;

const state = (f: Fixture) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select f.status::text as invoice, f.collection_mode as mode, f.charged_after_halt as charged_after_halt,
              (select count(*)::int from public.outbound_stripe_requests o where o.domain_record_id = f.id
                 and o.purpose = 'final_balance_invoice_disable_auto') as stops,
              (select o.status::text || ':' || coalesce(o.error_code, '') || ':' || (o.dispatch_confirmed_at is not null)
                 from public.outbound_stripe_requests o where o.id = $2) as create_request,
              (select count(*)::int from public.outbound_stripe_requests o where o.domain_record_id = f.id
                 and o.purpose = 'final_balance_invoice_create' and o.status = 'pending'
                 and o.request_params -> 'auto_advance' = 'false'::jsonb) as hosted_pending,
              (select a.status from public.payment_authorizations a where a.project_id = f.project_id
                order by a.created_at desc limit 1) as authorization
         from public.final_balance_invoices f where f.id = $1`,
      [f.fbiId, f.createId],
    );
    return rows[0] as {
      invoice: string;
      mode: string;
      charged_after_halt: boolean;
      stops: number;
      create_request: string;
      hosted_pending: number;
      authorization: string;
    };
  });

/**
 * OI-122: deterministic cleanup for the two-connection helpers, used only when a step fails. Every
 * connection still open is rolled back (never committed): the lock holders first, so the call
 * under test can settle; then, after a bounded wait for it, the connection running it. Every one is
 * then ended. Only cleanup errors are swallowed; the original error (an assertion, a lock timeout
 * or a 40P01 deadlock) still propagates from the caller's `finally`.
 */
async function abandon(holders: Client[], pending: Promise<unknown> | null, runners: Client[]) {
  for (const h of holders) await h.query("rollback").catch(() => undefined);
  let timer: NodeJS.Timeout | undefined;
  const settled =
    pending === null ||
    (await Promise.race([
      pending.then(
        () => true,
        () => true,
      ),
      new Promise<boolean>((r) => (timer = setTimeout(() => r(false), 10_000))),
    ]));
  clearTimeout(timer);
  // A runner whose call has not settled is ended without a rollback: ending it closes its socket,
  // and the server rolls its transaction back.
  if (settled) for (const c of runners) await c.query("rollback").catch(() => undefined);
  for (const c of [...holders, ...runners]) await c.end().catch(() => undefined);
}

/**
 * One commit order: `first` runs and holds its locks; `second` is shown to wait on a payment
 * authorization row (the top of the hierarchy, so it holds nothing below it); `first` commits;
 * `second` completes. Any database error, a deadlock (40P01) included, fails the test.
 */
async function race<A, B>(
  first: { as: "service" | "owner"; run: (c: Client) => Promise<A> },
  second: { as: "service" | "owner"; run: (c: Client) => Promise<B> },
): Promise<{ a: A; b: B }> {
  const ca = await open(first.as);
  let cb: Client | null = null;
  let pending: Promise<B> | null = null;
  let caOpen = true;
  let cbOpen = false;
  try {
    const a = await first.run(ca);
    cb = await open(second.as);
    cbOpen = true;
    const pid = await pidOf(cb);
    pending = second.run(cb);
    pending.catch(() => undefined);
    expect(await waitsOnRowOf(pid)).toBe("payment_authorizations");
    await done(ca);
    caOpen = false;
    const b = await pending;
    await done(cb);
    cbOpen = false;
    return { a, b };
  } finally {
    if (caOpen || cbOpen) {
      await abandon(caOpen ? [ca] : [], pending, cbOpen && cb ? [cb] : []);
    }
  }
}

/**
 * The hierarchy itself, independent of outcomes: a holder takes a higher lock, the function
 * under test must wait for it while holding nothing lower, and the holder can then take the
 * lower lock without waiting. A function that locked out of order would hold the lower lock
 * already: the holder would wait for it and the database would abort one side (40P01).
 */
async function probe(
  higher: { table: string; sql: string; params: unknown[] },
  lower: { sql: string; params: unknown[] },
  fn: { as: "service" | "owner"; run: (c: Client) => Promise<Json> },
): Promise<Json> {
  const holder = await open("raw");
  let c: Client | null = null;
  let pending: Promise<Json> | null = null;
  let holderOpen = true;
  let cOpen = false;
  try {
    await holder.query("set local lock_timeout = '3s'");
    await holder.query(higher.sql, higher.params);
    c = await open(fn.as);
    cOpen = true;
    const pid = await pidOf(c);
    pending = fn.run(c);
    pending.catch(() => undefined);
    expect(await waitsOnRowOf(pid)).toBe(higher.table);
    await holder.query(lower.sql, lower.params);
    await done(holder);
    holderOpen = false;
    const result = await pending;
    await done(c);
    cOpen = false;
    return result;
  } finally {
    if (holderOpen || cOpen) {
      await abandon(holderOpen ? [holder] : [], pending, cOpen && c ? [c] : []);
    }
  }
}
const lockAuthorizations = (f: Fixture) => ({
  table: "payment_authorizations",
  sql: "select 1 from public.payment_authorizations where project_id = $1 order by id for update",
  params: [f.projectId],
});
const lockInvoice = (f: Fixture) => ({
  table: "final_balance_invoices",
  sql: "select 1 from public.final_balance_invoices where id = $1 for update",
  params: [f.fbiId],
});
const lockRequest = (id: string) => ({
  sql: "select 1 from public.outbound_stripe_requests where id = $1 for update",
  params: [id],
});

/** Every request this file created is settled, so no other suite's dispatcher sends it. */
async function settle() {
  for (let round = 0; round < 5; round++) {
    const pending = await withDb(async (db) => {
      const { rows } = await db.query(
        "select id, claimed_at is not null as claimed from public.outbound_stripe_requests where project_id = any($1::uuid[]) and status = 'pending'",
        [projects],
      );
      return rows as { id: string; claimed: boolean }[];
    });
    if (pending.length === 0) return;
    for (const p of pending) {
      await step("service", async (c) => {
        if (!p.claimed) {
          const r = await claim(c, p.id);
          if (r.ok !== true) return;
        }
        if (!tokens.has(p.id)) return;
        await confirm(c, p.id);
        await record(c, p.id, "failed", null, "it_settled");
      });
    }
  }
}

// AUTH-025 (OI-130): remove the MFA factors this file creates, and only those, whatever the outcome.
afterAll(() =>
  withDb((db) => db.query("delete from auth.mfa_factors where friendly_name = 'it-oi91'")),
);

describe("AUTH-009: the lock hierarchy against revocation (two connections, both commit orders)", () => {
  afterAll(settle);

  it("revocation first: the claim waits, then supersedes the automatic create (never sent)", async () => {
    const f = await initiated("Clm1");
    const { b } = await race(
      { as: "owner", run: (c) => revoke(c, f.projectId) },
      { as: "service", run: (c) => claim(c, f.createId) },
    );
    expect(b.error).toBe("superseded");
    expect(await state(f)).toMatchObject({
      create_request: "failed:authorization_changed:false",
      hosted_pending: 1,
      mode: "hosted_only",
    });
  });

  it("claim first: revocation waits; the in-flight create is then refused at confirmation", async () => {
    const f = await initiated("Clm2");
    const { a, b } = await race(
      { as: "service", run: (c) => claim(c, f.createId) },
      { as: "owner", run: (c) => revoke(c, f.projectId) },
    );
    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true);
    expect((await step("service", (c) => confirm(c, f.createId))).error).toBe("superseded");
    expect(await state(f)).toMatchObject({
      create_request: "failed:authorization_changed:false",
      hosted_pending: 1,
    });
  });

  it("revocation first: confirmation waits, then refuses the automatic create", async () => {
    const f = await initiated("Cnf1");
    await claimed(f);
    const { b } = await race(
      { as: "owner", run: (c) => revoke(c, f.projectId) },
      { as: "service", run: (c) => confirm(c, f.createId) },
    );
    expect(b.error).toBe("superseded");
    expect(await state(f)).toMatchObject({ create_request: "failed:authorization_changed:false" });
  });

  it("confirmation first: revocation waits; after the send, the stop is queued once", async () => {
    const f = await initiated("Cnf2");
    await claimed(f);
    const { a, b } = await race(
      { as: "service", run: (c) => confirm(c, f.createId) },
      { as: "owner", run: (c) => revoke(c, f.projectId) },
    );
    expect(a.confirmed).toBe(true);
    expect(b.ok).toBe(true);
    // The confirmation-to-send gap cannot be closed: the create is sent, then stopped.
    const r = await step("service", (c) =>
      record(c, f.createId, "succeeded", `in_D${f.fbiId.slice(0, 8)}`),
    );
    expect(r.status).toBe("succeeded");
    expect(await state(f)).toMatchObject({ invoice: "open", mode: "hosted_only", stops: 1 });
  });

  it("revocation first: recording waits; the recorded invoice gets one stop", async () => {
    const f = await initiated("Rec1");
    await confirmed(f);
    const { b } = await race(
      { as: "owner", run: (c) => revoke(c, f.projectId) },
      {
        as: "service",
        run: (c) => record(c, f.createId, "succeeded", `in_D${f.fbiId.slice(0, 8)}`),
      },
    );
    expect(b.status).toBe("succeeded");
    expect(await state(f)).toMatchObject({ invoice: "open", stops: 1 });
  });

  it("recording first: revocation waits, then stops the invoice once", async () => {
    const f = await initiated("Rec2");
    await confirmed(f);
    const { a, b } = await race(
      {
        as: "service",
        run: (c) => record(c, f.createId, "succeeded", `in_D${f.fbiId.slice(0, 8)}`),
      },
      { as: "owner", run: (c) => revoke(c, f.projectId) },
    );
    expect(a.status).toBe("succeeded");
    expect(b.ok).toBe(true);
    expect(await state(f)).toMatchObject({ invoice: "open", mode: "hosted_only", stops: 1 });
  });

  it("revocation first: Owner reconciliation waits; the reconciled invoice gets one stop", async () => {
    const f = await initiated("Rcn1");
    await ambiguous(f);
    const { b } = await race(
      { as: "owner", run: (c) => revoke(c, f.projectId) },
      { as: "owner", run: (c) => reconcile(c, f.createId, `in_D${f.fbiId.slice(0, 8)}`) },
    );
    expect(b.ok).toBe(true);
    expect(await state(f)).toMatchObject({ invoice: "open", stops: 1 });
  });

  it("reconciliation first: revocation waits, then stops the invoice once", async () => {
    const f = await initiated("Rcn2");
    await ambiguous(f);
    const { a, b } = await race(
      { as: "owner", run: (c) => reconcile(c, f.createId, `in_D${f.fbiId.slice(0, 8)}`) },
      { as: "owner", run: (c) => revoke(c, f.projectId) },
    );
    expect(a.ok).toBe(true);
    expect(b.ok).toBe(true);
    expect(await state(f)).toMatchObject({ invoice: "open", mode: "hosted_only", stops: 1 });
  });

  it("revocation first: invoice.payment_failed waits, then records the failure", async () => {
    const f = await initiated("Fal1");
    await opened(f);
    const { b } = await race(
      { as: "owner", run: (c) => revoke(c, f.projectId) },
      { as: "service", run: (c) => invoiceEvent(c, f.fbiId, "invoice.payment_failed") },
    );
    expect(b.status).toBe("processed");
    expect(await state(f)).toMatchObject({
      invoice: "payment_failed",
      authorization: "revoked",
      stops: 1,
    });
  });

  it("invoice.payment_failed first: revocation waits; one stop in all", async () => {
    const f = await initiated("Fal2");
    await opened(f);
    const { a, b } = await race(
      { as: "service", run: (c) => invoiceEvent(c, f.fbiId, "invoice.payment_failed") },
      { as: "owner", run: (c) => revoke(c, f.projectId) },
    );
    expect(a.status).toBe("processed");
    expect(b.ok).toBe(true);
    expect(await state(f)).toMatchObject({
      invoice: "payment_failed",
      authorization: "revoked",
      stops: 1,
    });
  });

  it("revocation first: invoice.paid waits; the payment is verified and goes to Owner review", async () => {
    const f = await initiated("Pad1");
    await opened(f);
    const { b } = await race(
      { as: "owner", run: (c) => revoke(c, f.projectId) },
      { as: "service", run: (c) => invoiceEvent(c, f.fbiId, "invoice.paid") },
    );
    expect(b.status).toBe("processed");
    expect(await state(f)).toMatchObject({ invoice: "paid", charged_after_halt: true });
  });

  it("invoice.paid first: revocation waits; a paid invoice is not halted", async () => {
    const f = await initiated("Pad2");
    await opened(f);
    const { a, b } = await race(
      { as: "service", run: (c) => invoiceEvent(c, f.fbiId, "invoice.paid") },
      { as: "owner", run: (c) => revoke(c, f.projectId) },
    );
    expect(a.status).toBe("processed");
    expect(b.ok).toBe(true);
    expect(await state(f)).toMatchObject({ invoice: "paid", charged_after_halt: false, stops: 0 });
  });
});

describe("AUTH-009: each function takes authorization, then invoice, then outbound request", () => {
  afterAll(settle);

  it("the claim", async () => {
    const f = await initiated("PbC1");
    expect(
      (
        await probe(lockAuthorizations(f), lockInvoice(f), {
          as: "service",
          run: (c) => claim(c, f.createId),
        })
      ).ok,
    ).toBe(true);
    const g = await initiated("PbC2");
    expect(
      (
        await probe(lockInvoice(g), lockRequest(g.createId), {
          as: "service",
          run: (c) => claim(c, g.createId),
        })
      ).ok,
    ).toBe(true);
  });

  it("the confirmation", async () => {
    const f = await initiated("PbF1");
    await claimed(f);
    expect(
      (
        await probe(lockAuthorizations(f), lockInvoice(f), {
          as: "service",
          run: (c) => confirm(c, f.createId),
        })
      ).confirmed,
    ).toBe(true);
    const g = await initiated("PbF2");
    await claimed(g);
    expect(
      (
        await probe(lockInvoice(g), lockRequest(g.createId), {
          as: "service",
          run: (c) => confirm(c, g.createId),
        })
      ).confirmed,
    ).toBe(true);
  });

  it("the recording", async () => {
    const f = await initiated("PbR1");
    await confirmed(f);
    const object = `in_D${f.fbiId.slice(0, 8)}`;
    expect(
      (
        await probe(lockAuthorizations(f), lockInvoice(f), {
          as: "service",
          run: (c) => record(c, f.createId, "succeeded", object),
        })
      ).status,
    ).toBe("succeeded");
    const g = await initiated("PbR2");
    await confirmed(g);
    expect(
      (
        await probe(lockInvoice(g), lockRequest(g.createId), {
          as: "service",
          run: (c) => record(c, g.createId, "succeeded", `in_D${g.fbiId.slice(0, 8)}`),
        })
      ).status,
    ).toBe("succeeded");
  });

  it("the Owner reconciliation", async () => {
    const f = await initiated("PbO1");
    await ambiguous(f);
    expect(
      (
        await probe(lockAuthorizations(f), lockInvoice(f), {
          as: "owner",
          run: (c) => reconcile(c, f.createId, `in_D${f.fbiId.slice(0, 8)}`),
        })
      ).ok,
    ).toBe(true);
    const g = await initiated("PbO2");
    await ambiguous(g);
    expect(
      (
        await probe(lockInvoice(g), lockRequest(g.createId), {
          as: "owner",
          run: (c) => reconcile(c, g.createId, `in_D${g.fbiId.slice(0, 8)}`),
        })
      ).ok,
    ).toBe(true);
  });

  it("invoice.payment_failed and invoice.paid", async () => {
    const f = await initiated("PbW1");
    await opened(f);
    expect(
      (
        await probe(lockAuthorizations(f), lockInvoice(f), {
          as: "service",
          run: (c) => invoiceEvent(c, f.fbiId, "invoice.payment_failed"),
        })
      ).status,
    ).toBe("processed");
    const g = await initiated("PbW2");
    await opened(g);
    expect(
      (
        await probe(lockAuthorizations(g), lockInvoice(g), {
          as: "service",
          run: (c) => invoiceEvent(c, g.fbiId, "invoice.paid"),
        })
      ).status,
    ).toBe("processed");
  });

  it("engineering default: a dispatch function waits at most 5 seconds for a lock", async () => {
    const f = await initiated("Lto1");
    const holder = await open("raw");
    await holder.query(lockAuthorizations(f).sql, lockAuthorizations(f).params);
    const c = await open("service");
    const started = Date.now();
    const error = await claim(c, f.createId).then(
      () => null,
      (e: { code?: string }) => e.code,
    );
    expect(error).toBe("55P03");
    expect(Date.now() - started).toBeGreaterThanOrEqual(4_500);
    await c.query("rollback");
    await c.end();
    await done(holder);
  }, 20_000);
});

describe("AUTH-009: the executor's send deadline (fake clock, mocked gateway)", () => {
  afterAll(settle);

  it("a confirmation that completes after 30 seconds is never sent; the request is failed as not initiated", async () => {
    const f = await initiated("Dln1");
    const gateway = new MockStripeGateway();
    let reads = 0;
    const clock = { now: () => (reads++ === 0 ? 1_000 : 31_001) };
    expect(
      await executeOutboundRequest(adminClient(), gateway, f.createId, undefined, clock),
    ).toEqual({ ok: false, error: "dispatch_not_initiated" });
    expect(gateway.calls.filter((c) => c.method === "invoices.create_finalize_send")).toEqual([]);
    expect(await state(f)).toMatchObject({
      invoice: "creation_failed",
      create_request: "failed:dispatch_not_initiated:true",
    });
  });

  it("within the bound the create is sent once and recorded", async () => {
    const f = await initiated("Dln2");
    const gateway = new MockStripeGateway();
    let reads = 0;
    const clock = { now: () => (reads++ === 0 ? 1_000 : 30_999) };
    expect(
      (await executeOutboundRequest(adminClient(), gateway, f.createId, undefined, clock)).ok,
    ).toBe(true);
    expect(gateway.calls.filter((c) => c.method === "invoices.create_finalize_send")).toHaveLength(
      1,
    );
    expect(await state(f)).toMatchObject({ invoice: "open", create_request: "succeeded::true" });
  });
});

describe("AUTH-009 S1 and S2: the Owner's stop retry and token confidentiality", () => {
  afterAll(settle);

  const retry = (c: Client, fbiId: string, reason: string) =>
    one(c, "public.retry_final_balance_stop($1, $2)", [fbiId, reason]);

  /** An opened automatic invoice whose stop the Owner reconciled as absent. */
  async function unresolvedStop(label: string) {
    const f = await initiated(label);
    await opened(f);
    expect((await step("owner", (c) => revoke(c, f.projectId))).ok).toBe(true);
    const stop = await withDb(async (db) => {
      const { rows } = await db.query(
        "select id from public.outbound_stripe_requests where domain_record_id = $1 and purpose = 'final_balance_invoice_disable_auto'",
        [f.fbiId],
      );
      return rows[0].id as string;
    });
    expect((await step("service", (c) => claim(c, stop))).ok).toBe(true);
    expect((await step("service", (c) => confirm(c, stop))).confirmed).toBe(true);
    await step("service", (c) => record(c, stop, "failed", null, "invoice_not_editable"));
    const r = await step("owner", (c) =>
      one(c, "public.reconcile_outbound_request($1, false, null, 'Still on in Stripe')", [stop]),
    );
    expect(r.ok).toBe(true);
    return f;
  }
  const stops = (f: Fixture) =>
    withDb(async (db) => {
      const { rows } = await db.query(
        `select id, status::text from public.outbound_stripe_requests
          where domain_record_id = $1 and purpose = 'final_balance_invoice_disable_auto' order by attempt`,
        [f.fbiId],
      );
      return rows as { id: string; status: string }[];
    });

  it("simultaneous Owner retries serialize: the second waits, then returns the first's attempt", async () => {
    const f = await unresolvedStop("Rty1");
    const { a, b } = await race(
      { as: "owner", run: (c) => retry(c, f.fbiId, "Retry the stop (first)") },
      { as: "owner", run: (c) => retry(c, f.fbiId, "Retry the stop (second)") },
    );
    expect(a).toMatchObject({ ok: true, existing: false });
    expect(b).toEqual({ ok: true, existing: true, request_id: a.request_id });
    expect(await stops(f)).toEqual([
      { id: expect.any(String), status: "reconciled_absent" },
      { id: a.request_id, status: "pending" },
    ]);
    const audits = await withDb(
      async (db) =>
        (
          await db.query(
            "select count(*)::int as n from public.audit_events where action = 'outbound.request_retried' and target_id = $1",
            [f.fbiId],
          )
        ).rows[0].n,
    );
    expect(audits).toBe(1);
  });

  it("the retry waits for revocation-shaped locks in hierarchy order (authorization, then invoice)", async () => {
    const f = await unresolvedStop("Rty2");
    const r = await probe(lockAuthorizations(f), lockInvoice(f), {
      as: "owner",
      run: (c) => retry(c, f.fbiId, "Retry under contention"),
    });
    expect(r).toMatchObject({ ok: true, existing: false });
  });

  it("S2: no claim token reaches an application log during execution", async () => {
    const f = await initiated("Log1");
    const seen: string[] = [];
    const admin = adminClient();
    const watched = new Proxy(admin, {
      get(target, prop, receiver) {
        if (prop !== "rpc") return Reflect.get(target, prop, receiver);
        return async (fn: string, args?: Record<string, unknown>) => {
          const out = await target.rpc(fn, args);
          const t = (out.data as { claim_token?: unknown } | null)?.claim_token;
          if (typeof t === "string") seen.push(t);
          return out;
        };
      },
    });
    const logged: string[] = [];
    const methods = ["log", "info", "warn", "error", "debug"] as const;
    const spies = methods.map((m) =>
      vi.spyOn(console, m).mockImplementation((...args: unknown[]) => {
        logged.push(args.map((x) => (typeof x === "string" ? x : JSON.stringify(x))).join(" "));
      }),
    );
    try {
      // A complete claim, confirm, send and record through the executor, with every console
      // method captured.
      const result = await executeOutboundRequest(watched, new MockStripeGateway(), f.createId);
      expect(result.ok).toBe(true);
      console.error("probe line so the capture is shown to work");
    } finally {
      for (const s of spies) s.mockRestore();
    }
    expect(seen).toHaveLength(1);
    expect(logged).toEqual(["probe line so the capture is shown to work"]);
    for (const line of logged) for (const t of seen) expect(line.includes(t)).toBe(false);
  });
});
