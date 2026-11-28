import { randomUUID } from "node:crypto";

import { Client } from "pg";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { withDb } from "../support/db";

/**
 * WP-H (AUTH-006) integration tests against the local stack, with real concurrent database
 * connections (synthetic sessions, as in pgTAP and tests/integration/wps-sales.test.ts).
 *
 * OI-86: issue_order_summary locks the project row FOR NO KEY UPDATE (20261126120000). Each case
 * below runs both orders deterministically: the first transaction holds its lock while the
 * second is shown to wait; the first commits; the second's outcome is asserted. A deadlock
 * abort (40P01) is never a passing outcome: every statement must return normally.
 */

const OWNER_ID = "00000000-0000-4000-8000-000000000001";
const SALES_ID = "00000000-0000-4000-8000-000000000005";
const RUN = Date.now().toString(36);

async function clearLimits() {
  await withDb((db) =>
    db.query("delete from private.rate_limits where bucket like 'sales-%' or bucket = $1", [
      `invite:${SALES_ID}`,
    ]),
  );
}
beforeEach(clearLimits);
afterAll(clearLimits);

async function dbSession(userId: string, aal: "aal1" | "aal2" = "aal2"): Promise<string> {
  const sid = randomUUID();
  await withDb(async (db) => {
    await db.query(
      "insert into auth.sessions (id, user_id, created_at, updated_at, aal) values ($1, $2, now(), now(), $3)",
      [sid, userId, aal],
    );
    if (aal === "aal2") {
      await db.query(
        `insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
         select gen_random_uuid(), $1, 'it-wph', 'totp', 'verified', now(), now()
         where not exists (select 1 from auth.mfa_factors where user_id = $1 and status = 'verified')`,
        [userId],
      );
    }
  });
  return sid;
}

/** A connection inside an open transaction, acting as `userId` in session `sid`. */
async function openTx(userId: string, sid: string): Promise<Client> {
  const url =
    process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("local only");
  const c = new Client({ connectionString: url });
  await c.connect();
  await c.query("begin");
  await c.query("select set_config('request.jwt.claims', $1, true)", [
    JSON.stringify({ sub: userId, role: "authenticated", aal: "aal2", session_id: sid, amr: [] }),
  ]);
  await c.query("set local role authenticated");
  return c;
}
async function close(c: Client, commit: boolean) {
  await c.query(commit ? "commit" : "rollback");
  await c.end();
}
type Result = { ok: boolean; error?: string } & Record<string, unknown>;
async function rpc(c: Client, sql: string, params: unknown[] = []): Promise<Result> {
  const { rows } = await c.query(`select (${sql}) as r`, params);
  return rows[0].r as Result;
}
async function once(userId: string, sid: string, sql: string, params: unknown[] = []) {
  const c = await openTx(userId, sid);
  try {
    return await rpc(c, sql, params);
  } finally {
    await close(c, true);
  }
}
/** Starts a call that is expected to block; reports whether it was still pending after 400 ms. */
async function startBlocked<T>(p: Promise<T>): Promise<{ result: Promise<T>; blocked: boolean }> {
  let settled = false;
  const result = p.finally(() => {
    settled = true;
  });
  await new Promise((r) => setTimeout(r, 400));
  return { result, blocked: !settled };
}

async function newClientUser(email: string): Promise<string> {
  const id = randomUUID();
  await withDb((db) =>
    db.query(
      `insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
         raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
         email_change_token_new, email_change, email_change_token_current, reauthentication_token,
         phone_change, phone_change_token)
       values ('00000000-0000-0000-0000-000000000000', $1, 'authenticated', 'authenticated', $2, '', now(),
         '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '', '', '', '', '')`,
      [id, email],
    ),
  );
  return id;
}

/** A Sales project with a presented Sales order summary and a client member. */
async function salesProject(label: string) {
  await clearLimits();
  const sid = await dbSession(SALES_ID);
  const ownerSid = await dbSession(OWNER_ID);
  const legalName = `WPH ${label} ${RUN} LLC`;
  const project = await once(SALES_ID, sid, "public.sales_create_customer_project($1, null, $2)", [
    legalName,
    `${label} site`,
  ]);
  expect(project.ok).toBe(true);
  const projectId = project.project_id as string;
  const summary = await once(SALES_ID, sid, "public.issue_order_summary($1, 'essential')", [
    projectId,
  ]);
  expect(summary.ok).toBe(true);
  const email = `wph.${label.toLowerCase()}.${RUN}@example.test`;
  const inv = await once(SALES_ID, sid, "public.create_invitation('client', $1, 'Client', $2)", [
    email,
    projectId,
  ]);
  const clientId = await newClientUser(email);
  const clientSid = await dbSession(clientId, "aal1");
  expect(
    (
      await once(clientId, clientSid, "public.accept_invitation($1, $2)", [
        inv.invitation_id,
        inv.token,
      ])
    ).ok,
  ).toBe(true);
  return {
    sid,
    ownerSid,
    projectId,
    orderSummaryId: summary.order_summary_id as string,
    clientId,
    clientSid,
    legalName,
  };
}

const salesIssue = "public.issue_order_summary($1, 'essential', '[]'::jsonb, null, 'oi86')";
const ownerIssue = "public.issue_order_summary($1, 'professional', '[]'::jsonb, null, 'oi86')";
const acceptSql = "public.accept_agreement($1, true, true, 'Client Signer', $2, 'Owner', true)";

const presented = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select count(*)::int as n, max(revision)::int as revision,
              (array_agg(issued_by::text order by revision desc))[1] as issued_by
         from public.order_summaries where project_id = $1 and status = 'presented'`,
      [projectId],
    );
    return rows[0] as { n: number; revision: number; issued_by: string };
  });

/**
 * Runs `first` in an open transaction, shows `second` waits on it, commits `first`, and returns
 * both outcomes. Any database error (including 40P01) fails the test.
 */
async function serialize(
  first: { user: string; sid: string; sql: string; params: unknown[] },
  second: { user: string; sid: string; sql: string; params: unknown[] },
) {
  const a = await openTx(first.user, first.sid);
  const firstResult = await rpc(a, first.sql, first.params);
  const b = await openTx(second.user, second.sid);
  const pending = await startBlocked(rpc(b, second.sql, second.params));
  expect(pending.blocked).toBe(true);
  await close(a, true);
  const secondResult = await pending.result;
  await close(b, true);
  return { firstResult, secondResult };
}

describe("OI-86: issue_order_summary serializes with every project-lock caller (two connections)", () => {
  it("end_sales_assignment first: the Sales issuance waits, then is refused", async () => {
    const p = await salesProject("EndFirst");
    const assignment = await withDb((db) =>
      db.query("select id from public.project_sales_assignments where project_id = $1 and active", [
        p.projectId,
      ]),
    );
    const { firstResult, secondResult } = await serialize(
      {
        user: OWNER_ID,
        sid: p.ownerSid,
        sql: "public.end_sales_assignment($1, 'oi86')",
        params: [assignment.rows[0].id],
      },
      { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult).toMatchObject({ ok: false, error: "forbidden" });
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 1 });
  });

  it("Sales issuance first: end_sales_assignment waits, then ends the assignment", async () => {
    const p = await salesProject("IssueBeforeEnd");
    const assignment = await withDb((db) =>
      db.query("select id from public.project_sales_assignments where project_id = $1 and active", [
        p.projectId,
      ]),
    );
    const { firstResult, secondResult } = await serialize(
      { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] },
      {
        user: OWNER_ID,
        sid: p.ownerSid,
        sql: "public.end_sales_assignment($1, 'oi86')",
        params: [assignment.rows[0].id],
      },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult.ok).toBe(true);
    // The issuance happened while the assignment was active; it was then ended.
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 2, issued_by: SALES_ID });
    const active = await withDb((db) =>
      db.query(
        "select count(*)::int as n from public.project_sales_assignments where project_id = $1 and active",
        [p.projectId],
      ),
    );
    expect(active.rows[0].n).toBe(0);
  });

  it("assign_sales_representative and issuance serialize in both orders", async () => {
    const p = await salesProject("Assign");
    const assign = {
      user: OWNER_ID,
      sid: p.ownerSid,
      sql: "public.assign_sales_representative($1, $2, 'oi86')",
      params: [p.projectId, SALES_ID],
    };
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    const one = await serialize(assign, issue);
    expect(one.firstResult).toMatchObject({ ok: true, existing: true });
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, assign);
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult).toMatchObject({ ok: true, existing: true });
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("begin_initial_checkout first: the Owner replacement waits, then supersedes the unpaid summary", async () => {
    const p = await salesProject("CheckoutFirst");
    expect(
      (await once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName])).ok,
    ).toBe(true);
    const { firstResult, secondResult } = await serialize(
      {
        user: p.clientId,
        sid: p.clientSid,
        sql: "public.begin_initial_checkout($1)",
        params: [p.projectId],
      },
      { user: OWNER_ID, sid: p.ownerSid, sql: ownerIssue, params: [p.projectId] },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult.ok).toBe(true);
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 2, issued_by: OWNER_ID });
    // The checkout created first stays bound to the summary it was created for.
    const cs = await withDb((db) =>
      db.query(
        "select order_summary_id::text from public.checkout_sessions where project_id = $1",
        [p.projectId],
      ),
    );
    expect(cs.rows).toEqual([{ order_summary_id: p.orderSummaryId }]);
  });

  it("Owner replacement first: begin_initial_checkout waits, then requires the new acceptance", async () => {
    const p = await salesProject("ReplaceBeforeCheckout");
    expect(
      (await once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName])).ok,
    ).toBe(true);
    const { firstResult, secondResult } = await serialize(
      { user: OWNER_ID, sid: p.ownerSid, sql: ownerIssue, params: [p.projectId] },
      {
        user: p.clientId,
        sid: p.clientSid,
        sql: "public.begin_initial_checkout($1)",
        params: [p.projectId],
      },
    );
    expect(firstResult.ok).toBe(true);
    expect(secondResult).toMatchObject({ ok: false, error: "acceptance_required" });
    const cs = await withDb((db) =>
      db.query("select count(*)::int as n from public.checkout_sessions where project_id = $1", [
        p.projectId,
      ]),
    );
    expect(cs.rows[0].n).toBe(0);
  });

  it("begin_payment_method_recovery and issuance serialize in both orders", async () => {
    const p = await salesProject("Recovery");
    const recovery = {
      user: p.clientId,
      sid: p.clientSid,
      sql: "public.begin_payment_method_recovery($1)",
      params: [p.projectId],
    };
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    // The recovery takes its project lock before its eligibility checks, so it holds the lock
    // (and is refused: no deposit yet) while the issuance waits, and the reverse.
    const one = await serialize(recovery, issue);
    expect(one.firstResult).toMatchObject({ ok: false, error: "deposit_required" });
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, recovery);
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult).toMatchObject({ ok: false, error: "deposit_required" });
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("create_invitation and issuance serialize in both orders", async () => {
    const p = await salesProject("Invite");
    const invite = (n: number) => ({
      user: SALES_ID,
      sid: p.sid,
      sql: "public.create_invitation('client', $1, 'Client', $2)",
      params: [`wph.invite${n}.${RUN}@example.test`, p.projectId],
    });
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    const one = await serialize(invite(1), issue);
    expect(one.firstResult.ok).toBe(true);
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, invite(2));
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult.ok).toBe(true);
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("revoke_invitation and issuance serialize in both orders", async () => {
    const p = await salesProject("Revoke");
    const pending = async (n: number) =>
      (
        await once(SALES_ID, p.sid, "public.create_invitation('client', $1, 'Client', $2)", [
          `wph.revoke${n}.${RUN}@example.test`,
          p.projectId,
        ])
      ).invitation_id as string;
    const revoke = (id: string) => ({
      user: SALES_ID,
      sid: p.sid,
      sql: "public.revoke_invitation($1)",
      params: [id],
    });
    const issue = { user: SALES_ID, sid: p.sid, sql: salesIssue, params: [p.projectId] };
    const one = await serialize(revoke(await pending(1)), issue);
    expect(one.firstResult.ok).toBe(true);
    expect(one.secondResult.ok).toBe(true);
    const two = await serialize(issue, revoke(await pending(2)));
    expect(two.firstResult.ok).toBe(true);
    expect(two.secondResult.ok).toBe(true);
    expect(await presented(p.projectId)).toMatchObject({ n: 1, revision: 3 });
  });

  it("the acceptance's foreign-key lock no longer conflicts with the issuer's project lock", async () => {
    // The mechanism of the deadlock, isolated: a connection holds only the lock issuance now
    // takes on the project row. The acceptance's insert takes FOR KEY SHARE through its foreign
    // key and must proceed at once; under the former FOR UPDATE it waited (control below).
    const url =
      process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
    for (const [mode, expectWait] of [
      ["for no key update", false],
      ["for update", true],
    ] as const) {
      const p = await salesProject(mode === "for update" ? "LockControl" : "LockNoKey");
      const holder = new Client({ connectionString: url });
      await holder.connect();
      await holder.query("begin");
      await holder.query(`select 1 from public.projects where id = $1 ${mode}`, [p.projectId]);
      const accept = await startBlocked(
        once(p.clientId, p.clientSid, acceptSql, [p.orderSummaryId, p.legalName]),
      );
      expect(accept.blocked).toBe(expectWait);
      await holder.query("rollback");
      await holder.end();
      expect((await accept.result).ok).toBe(true);
    }
  });
});

/**
 * AUTH-006 Amendment 1: the release-approval cross-check under real concurrency. The consumer
 * (private.consume_release_approved) takes WP-C's per-project release lock
 * (hashtextextended('release:' || project_id, 0)) and then FOR SHARE on the event's release row,
 * before the payment-authorization lock. WP-C's release_preview and approve_preview take the same
 * advisory lock; withdraw_preview locks the release row FOR UPDATE. Each race runs both orders
 * with WP-C's real functions: the first transaction holds its locks, the second is shown to wait,
 * the first commits, and the outcome is asserted. Any database error (including 40P01) fails.
 */
const ADMIN_ID = "00000000-0000-4000-8000-000000000002";
const CLIENT_A_ID = "00000000-0000-4000-8000-0000000000a1";

// Session-local helpers for one setup transaction (as in supabase/tests/190): the real WP-B
// workflow to a verified deposit and active card, then WP-C's real intake, release, and approval.
const SETUP_HELPERS = `
create function pg_temp.act_as(p_uid uuid, p_aal text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid();
begin
  insert into auth.sessions (id, user_id, created_at, updated_at, aal) values (v_sid, p_uid, now(), now(), p_aal::auth.aal_level);
  if p_aal = 'aal2' then
    insert into auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at)
    select gen_random_uuid(), p_uid, 'it-wph', 'totp', 'verified', now(), now()
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
  insert into public.client_businesses (legal_name, display_name) values ('WPH ' || p_tag || ' LLC', 'WPH ' || p_tag)
  returning id into v_business;
  insert into public.projects (client_business_id, name) values (v_business, 'WPH ' || p_tag) returning id into v_project;
  insert into public.project_memberships (project_id, user_id) values (v_project, '${CLIENT_A_ID}');
  perform pg_temp.act_as('${OWNER_ID}', 'aal2');
  v_os := (public.issue_order_summary(v_project, 'essential', '[]'::jsonb) ->> 'order_summary_id')::uuid;
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_acc := (public.accept_agreement(v_os, true, true, 'Alex Client', 'WPH ' || p_tag || ' LLC', 'Owner', true) ->> 'acceptance_id')::uuid;
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
  v_draft := (public.save_intake_draft(v_project, jsonb_build_object('business_legal_name', 'WPH LLC',
    'business_display_name', 'WPH', 'contact_phone', '555-0100', 'contact_email', 'client.a@example.test',
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
  v_release := (public.release_preview(v_project, p_sha, 'dpl_w' || p_tag, 'https://preview.example.test/wph', '{}')
    ->> 'release_id')::uuid;
  reset role;
  perform pg_temp.act_as('${CLIENT_A_ID}', 'aal1');
  v_approval := (public.approve_preview(v_release) ->> 'approval_id')::uuid;
  reset role;
  return jsonb_build_object('project_id', v_project, 'release_id', v_release, 'approval_id', v_approval,
    'event_id', (select id from public.domain_events where dedupe_key = 'release.approved:' || v_release));
end; $$;`;

const sha = () => (randomUUID() + randomUUID()).replace(/-/g, "").slice(0, 40);

/** A project with a verified deposit, an active card, accepted intake, and an approved release. */
async function approvedRelease(label: string) {
  const tag = `${label}${RUN}`;
  const r = await withDb(async (db) => {
    await db.query("begin");
    await db.query(SETUP_HELPERS);
    const { rows } = await db.query("select pg_temp.ready($1, $2) as r", [tag, sha()]);
    await db.query("commit");
    return rows[0].r as {
      project_id: string;
      release_id: string;
      approval_id: string;
      event_id: number;
    };
  });
  expect(r.release_id).toBeTruthy();
  expect(r.approval_id).toBeTruthy();
  expect(r.event_id).toBeTruthy();
  raceProjects.push(r.project_id);
  return r;
}

/**
 * The races commit real obligations. Their final-balance creates are settled afterwards through
 * the executor's normal path (claimed, then a recorded mock result), so no pending request is
 * left for another suite's billing-job run to send.
 */
const raceProjects: string[] = [];
async function settleRaceRequests() {
  await withDb(async (db) => {
    await db.query("begin");
    await db.query("select set_config('request.jwt.claims', '{\"role\":\"service_role\"}', true)");
    await db.query("set local role service_role");
    const { rows } = await db.query(
      `select id from public.outbound_stripe_requests
        where project_id = any($1::uuid[]) and purpose = 'final_balance_invoice_create' and status = 'pending'`,
      [raceProjects],
    );
    for (const { id } of rows as { id: string }[]) {
      // AUTH-009 (setup): claim, confirm with the one-time token, then record with it. The
      // token stays in memory and is never logged or asserted.
      const claim = await db.query(
        "select public.outbound_request_for_execution($1) ->> 'claim_token' as token",
        [id],
      );
      const token = (claim.rows[0] as { token: string | null }).token;
      await db.query("select public.confirm_outbound_dispatch($1, $2)", [id, token]);
      await db.query(
        "select public.record_outbound_result($1, $2, 'succeeded', $3, false, 200, null, '{}')",
        [id, token, `in_W${id.slice(0, 8)}`],
      );
    }
    await db.query("commit");
  });
}

/** A connection inside an open transaction as the database owner (the consumer's job context). */
async function openConsumer(): Promise<Client> {
  const url =
    process.env.SUPABASE_DB_URL ?? "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
  if (!["127.0.0.1", "localhost"].includes(new URL(url).hostname)) throw new Error("local only");
  const c = new Client({ connectionString: url });
  await c.connect();
  await c.query("begin");
  return c;
}
const consume = async (c: Client, eventId: number) =>
  (await c.query("select private.consume_release_approved($1) as o", [eventId])).rows[0]
    .o as string;

const consumption = (eventId: number) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select outcome, detail from private.event_consumptions
        where consumer = 'wpb.final_balance_invoice' and domain_event_id = $1`,
      [eventId],
    );
    return rows[0] as { outcome: string; detail: string | null };
  });
const obligations = (projectId: string) =>
  withDb(async (db) => {
    const { rows } = await db.query(
      `select f.release_id, f.approval_id,
              (select count(*)::int from public.outbound_stripe_requests o
                where o.project_id = $1 and o.purpose = 'final_balance_invoice_create') as creates
         from public.final_balance_invoices f where f.project_id = $1`,
      [projectId],
    );
    return rows as { release_id: string; approval_id: string; creates: number }[];
  });

const releaseSql = "public.release_preview($1, $2, $3, 'https://preview.example.test/wph2', '{}')";
const withdrawSql = "public.withdraw_preview($1, 'Withdrawn in the race test')";
const approveSql = "public.approve_preview($1)";

describe("AUTH-006 Amendment 1: release-approval cross-check against WP-C writers (two connections)", () => {
  afterAll(settleRaceRequests);

  it("superseding release first: consumption waits, then rejects the superseded approval", async () => {
    const r = await approvedRelease("SupA");
    const adminSid = await dbSession(ADMIN_ID);
    const b = await openTx(ADMIN_ID, adminSid);
    expect((await rpc(b, releaseSql, [r.project_id, sha(), `dpl_s${RUN}a`])).ok).toBe(true);
    const a = await openConsumer();
    const pending = await startBlocked(consume(a, r.event_id));
    expect(pending.blocked).toBe(true);
    await close(b, true);
    expect(await pending.result).toBe("rejected");
    await close(a, true);
    expect(await consumption(r.event_id)).toEqual({
      outcome: "rejected",
      detail: "release_superseded",
    });
    expect(await obligations(r.project_id)).toEqual([]);
  });

  it("consumption first: release_preview waits; the obligation is initiated before supersession", async () => {
    const r = await approvedRelease("SupB");
    const adminSid = await dbSession(ADMIN_ID);
    const a = await openConsumer();
    expect(await consume(a, r.event_id)).toBe("created");
    const b = await openTx(ADMIN_ID, adminSid);
    const pending = await startBlocked(rpc(b, releaseSql, [r.project_id, sha(), `dpl_s${RUN}b`]));
    expect(pending.blocked).toBe(true);
    await close(a, true);
    expect((await pending.result).ok).toBe(true);
    await close(b, true);
    // OI-92(e): a later supersession keeps the durably initiated obligation.
    expect(await obligations(r.project_id)).toEqual([
      { release_id: r.release_id, approval_id: r.approval_id, creates: 1 },
    ]);
  });

  it("withdrawal first: consumption waits on the release row, then rejects the withdrawn release", async () => {
    const r = await approvedRelease("WdrA");
    const adminSid = await dbSession(ADMIN_ID);
    const b = await openTx(ADMIN_ID, adminSid);
    expect((await rpc(b, withdrawSql, [r.release_id])).ok).toBe(true);
    const a = await openConsumer();
    const pending = await startBlocked(consume(a, r.event_id));
    expect(pending.blocked).toBe(true);
    await close(b, true);
    expect(await pending.result).toBe("rejected");
    await close(a, true);
    expect(await consumption(r.event_id)).toEqual({
      outcome: "rejected",
      detail: "release_withdrawn",
    });
    expect(await obligations(r.project_id)).toEqual([]);
  });

  it("consumption first: withdraw_preview waits; the obligation is initiated before withdrawal", async () => {
    const r = await approvedRelease("WdrB");
    const adminSid = await dbSession(ADMIN_ID);
    const a = await openConsumer();
    expect(await consume(a, r.event_id)).toBe("created");
    const b = await openTx(ADMIN_ID, adminSid);
    const pending = await startBlocked(rpc(b, withdrawSql, [r.release_id]));
    expect(pending.blocked).toBe(true);
    await close(a, true);
    expect((await pending.result).ok).toBe(true);
    await close(b, true);
    expect(await obligations(r.project_id)).toEqual([
      { release_id: r.release_id, approval_id: r.approval_id, creates: 1 },
    ]);
  });

  it("approval first: a stale approval's consumption waits, is rejected, and only the new approval creates", async () => {
    // Release 1 approved (its event pending), then superseded by release 2 through WP-C.
    const r = await approvedRelease("AppA");
    const adminSid = await dbSession(ADMIN_ID);
    const rel2 = await once(ADMIN_ID, adminSid, releaseSql, [r.project_id, sha(), `dpl_a${RUN}a`]);
    expect(rel2.ok).toBe(true);
    const clientSid = await dbSession(CLIENT_A_ID, "aal1");
    const b = await openTx(CLIENT_A_ID, clientSid);
    const approval2 = await rpc(b, approveSql, [rel2.release_id]);
    expect(approval2.ok).toBe(true);
    const a = await openConsumer();
    const pending = await startBlocked(consume(a, r.event_id));
    expect(pending.blocked).toBe(true);
    await close(b, true);
    expect(await pending.result).toBe("rejected");
    await close(a, true);
    expect((await consumption(r.event_id)).detail).toBe("release_superseded");
    const event2 = await withDb(
      async (db) =>
        (
          await db.query("select id from public.domain_events where dedupe_key = $1", [
            `release.approved:${rel2.release_id}`,
          ])
        ).rows[0].id as number,
    );
    const c = await openConsumer();
    expect(await consume(c, event2)).toBe("created");
    await close(c, true);
    expect(await obligations(r.project_id)).toEqual([
      { release_id: rel2.release_id, approval_id: approval2.approval_id, creates: 1 },
    ]);
  });

  it("consumption first: approve_preview waits for a stale approval's rejection; one obligation", async () => {
    const r = await approvedRelease("AppB");
    const adminSid = await dbSession(ADMIN_ID);
    const rel2 = await once(ADMIN_ID, adminSid, releaseSql, [r.project_id, sha(), `dpl_a${RUN}b`]);
    expect(rel2.ok).toBe(true);
    const a = await openConsumer();
    expect(await consume(a, r.event_id)).toBe("rejected");
    const clientSid = await dbSession(CLIENT_A_ID, "aal1");
    const b = await openTx(CLIENT_A_ID, clientSid);
    const pending = await startBlocked(rpc(b, approveSql, [rel2.release_id]));
    expect(pending.blocked).toBe(true);
    await close(a, true);
    const approval2 = await pending.result;
    expect(approval2.ok).toBe(true);
    await close(b, true);
    expect((await consumption(r.event_id)).detail).toBe("release_superseded");
    const event2 = await withDb(
      async (db) =>
        (
          await db.query("select id from public.domain_events where dedupe_key = $1", [
            `release.approved:${rel2.release_id}`,
          ])
        ).rows[0].id as number,
    );
    const c = await openConsumer();
    expect(await consume(c, event2)).toBe("created");
    expect(await consume(c, event2)).toBe("already_consumed");
    await close(c, true);
    expect(await obligations(r.project_id)).toEqual([
      { release_id: rel2.release_id, approval_id: approval2.approval_id, creates: 1 },
    ]);
  });
});
