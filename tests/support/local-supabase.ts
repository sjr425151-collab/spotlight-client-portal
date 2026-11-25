import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

import { clearMailbox, codeFrom, waitForEmail } from "./mailpit";
import { waitForPostgrestReady } from "./postgrest-ready";
import { totp } from "./totp";

/**
 * Connections to the LOCAL Supabase stack only. Keys come from the environment (CI exports
 * them from `supabase status`) or from the developer's untracked .env.local.
 */
if (!process.env.SUPABASE_SECRET_KEY && existsSync(".env.local")) process.loadEnvFile(".env.local");

export const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "http://127.0.0.1:54321";
const PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "";
const SECRET_KEY = process.env.SUPABASE_SECRET_KEY ?? "";

if (!["127.0.0.1", "localhost"].includes(new URL(SUPABASE_URL).hostname)) {
  throw new Error("Integration tests may only run against a local Supabase stack");
}

// F2 (AUTH-008 I-1): every integration file that talks to PostgREST imports this module, so
// each file starts only once PostgREST is serving (it can still be reconnecting after a
// `supabase db reset`; see postgrest-ready.ts). Runs once per file, before any test.
await waitForPostgrestReady();

const options = { auth: { persistSession: false, autoRefreshToken: false } };

export function anonClient(headers: Record<string, string> = {}): SupabaseClient {
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, { ...options, global: { headers } });
}

export function adminClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SECRET_KEY, options);
}

/** A client that sends a fixed access token (simulates a still-unexpired stolen/old JWT). */
export function clientWithToken(accessToken: string): SupabaseClient {
  return createClient(SUPABASE_URL, PUBLISHABLE_KEY, {
    ...options,
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });
}

/**
 * Supabase Auth refuses a second code for the same address within `max_frequency` (1 s,
 * supabase/config.toml). Vitest gives each test file its own module instance, so the last
 * send time is kept in a small file shared by every test file in the run, not in memory:
 * otherwise a file that signs in an address right after another file did is refused.
 */
const LAST_SEND_FILE = join(tmpdir(), "spotlight-portal-otp-last-send.json");

function readLastSend(): Record<string, number> {
  try {
    return JSON.parse(readFileSync(LAST_SEND_FILE, "utf8")) as Record<string, number>;
  } catch {
    return {};
  }
}

function recordLastSend(email: string) {
  writeFileSync(LAST_SEND_FILE, JSON.stringify({ ...readLastSend(), [email]: Date.now() }));
}

/** Signs in with an emailed code read from the local Mailpit. Returns the session client. */
export async function signInWithCode(email: string): Promise<SupabaseClient> {
  const since = Date.now() - (readLastSend()[email] ?? 0);
  if (since < 1100) await new Promise((resolve) => setTimeout(resolve, 1100 - since));
  await clearMailbox(email);
  const client = anonClient();
  const { error } = await client.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: false },
  });
  recordLastSend(email);
  if (error) throw new Error(`signInWithOtp failed: ${error.code}`);
  const code = codeFrom(await waitForEmail(email));
  const { error: verifyError } = await client.auth.verifyOtp({ email, token: code, type: "email" });
  if (verifyError) throw new Error(`verifyOtp failed: ${verifyError.code}`);
  return client;
}

/** Enrolls (or reuses) a TOTP factor and upgrades the session to aal2. */
export async function upgradeToAal2(client: SupabaseClient, secrets: Map<string, string>) {
  const { data: user } = await client.auth.getUser();
  const id = user.user!.id;
  let secret = secrets.get(id);
  let factorId: string;
  if (!secret) {
    const { data, error } = await client.auth.mfa.enroll({
      factorType: "totp",
      friendlyName: `it-${Date.now()}`,
    });
    if (error || !data) throw new Error(`enroll failed: ${error?.code}`);
    secret = data.totp.secret;
    factorId = data.id;
    secrets.set(id, secret);
    secrets.set(`${id}:factor`, factorId);
  } else {
    factorId = secrets.get(`${id}:factor`)!;
  }
  const { error } = await client.auth.mfa.challengeAndVerify({ factorId, code: totp(secret) });
  if (error) throw new Error(`MFA verify failed: ${error.code}`);
}

export async function accessToken(client: SupabaseClient): Promise<string> {
  const { data } = await client.auth.getSession();
  return data.session!.access_token;
}
