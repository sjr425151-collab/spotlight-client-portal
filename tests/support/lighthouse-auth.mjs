/**
 * Authenticated Lighthouse pages (AUTH-008 I-2, P-2 option A; 02 §7; T-E2E-10). LOCAL stack
 * only, synthetic data only, no new dependency (the existing @playwright/test and @lhci/cli).
 *
 * Run by the CI Lighthouse job after `lhci collect` has collected the public pages:
 *   1. serves the test build on port 3200 (`next start`, as lighthouserc.json does);
 *   2. launches Chrome with a persistent profile and a local remote-debugging port, and signs
 *      the synthetic seed client `client.a@example.test` in at aal1 through the existing
 *      email-code flow, with the code read from the local Mailpit;
 *   3. checks each approved page (Owner, 2026-11-26): HTTP 200, the expected final route and
 *      a positive page-specific rendering check. A sign-in redirect, an error page or a
 *      not-found state fails the job (stop condition); no other page is ever substituted;
 *   4. runs `lhci collect --additive` for exactly those pages, with Lighthouse attached to that
 *      signed-in browser (`settings.port`), so the reports join the public ones;
 *   5. verifies every collected report: each approved page has its runs, each run ended on
 *      the requested route with HTTP 200, and no report contains a session token or auth
 *      cookie name.
 * Nothing is stored or printed: no password, token, cookie, TOTP seed or sign-in code. The
 * public pages keep their signed-out collection; their URLs and thresholds are unchanged.
 */
import { spawn, spawnSync } from "node:child_process";
import { mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { chromium } from "@playwright/test";

const ORIGIN = "http://localhost:3200";
const DEBUG_PORT = 9333;
/** The audit browser's temporary profile (outside every uploaded path; deleted afterwards). */
const PROFILE_PREFIX = "lighthouse-auth-";
const REPORTS = ".lighthouseci";
const RUNS_PER_URL = 3;
const CLIENT_EMAIL = "client.a@example.test";
const PROJECT_A = "20000000-0000-4000-8000-0000000000a0";
const MAILPIT = process.env.MAILPIT_URL || "http://127.0.0.1:54324";
const SUPABASE = process.env.NEXT_PUBLIC_SUPABASE_URL || "";

/** The approved authenticated pages and each page's positive rendering check. */
export const AUTHENTICATED = [
  { path: "/portal", selector: '[data-testid="project-list"]', text: "Project A website" },
  {
    path: `/portal/projects/${PROJECT_A}`,
    selector: '[data-testid="project-status"]',
    text: "Project information",
  },
  {
    path: `/portal/projects/${PROJECT_A}/billing`,
    selector: '[data-testid="payment-status"]',
    text: "Payments",
  },
];
export const PUBLIC = ["/", "/sign-in"];

const LOCAL_HOSTS = new Set(["127.0.0.1", "localhost"]);
function assertLocal(url, label) {
  if (!LOCAL_HOSTS.has(new URL(url).hostname)) {
    throw new Error(`lighthouse-auth: ${label} must be on the local stack`);
  }
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const search = (email) => `${MAILPIT}/api/v1/search?query=${encodeURIComponent(`to:"${email}"`)}`;

/** The six-digit code from the newest email to the address; it is never logged. */
async function waitForCode(email, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const response = await fetch(search(email));
    if (!response.ok)
      throw new Error(`lighthouse-auth: Mailpit search failed (${response.status})`);
    const { messages } = await response.json();
    if (messages.length > 0) {
      const message = await (await fetch(`${MAILPIT}/api/v1/message/${messages[0].ID}`)).json();
      await fetch(search(email), { method: "DELETE" });
      const match = /\b(\d{6})\b/.exec(message.Text || "");
      if (!match) throw new Error("lighthouse-auth: no six-digit code in the sign-in email");
      return match[1];
    }
    await sleep(250);
  }
  throw new Error("lighthouse-auth: no sign-in email arrived");
}

async function signIn(page) {
  await fetch(search(CLIENT_EMAIL), { method: "DELETE" });
  await page.goto(`${ORIGIN}/sign-in`);
  await page.getByLabel("Email").fill(CLIENT_EMAIL);
  await page.getByRole("button", { name: "Email me a sign-in code" }).click();
  await page
    .locator("main")
    .getByRole("status")
    .filter({ hasText: "If this email belongs to a portal account" })
    .waitFor();
  await page.getByLabel("Sign-in code").fill(await waitForCode(CLIENT_EMAIL));
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL(`${ORIGIN}/portal`);
}

/** HTTP 200, the expected final route and the page's own content. */
async function checkRenders(page, { path, selector, text }) {
  const response = await page.goto(`${ORIGIN}${path}`);
  const status = response ? response.status() : 0;
  const finalPath = new URL(page.url()).pathname;
  if (status !== 200 || finalPath !== path) {
    throw new Error(
      `lighthouse-auth: ${path} did not render (HTTP ${status}, final route ${finalPath})`,
    );
  }
  const content = (await page.locator(selector).first().textContent({ timeout: 10_000 })) ?? "";
  if (!content.includes(text)) {
    throw new Error(`lighthouse-auth: ${path} did not render ${selector} with "${text}"`);
  }
}

async function startServer() {
  const server = spawn("pnpm", ["exec", "next", "start", "--port", "3200"], {
    stdio: ["ignore", "ignore", "inherit"],
  });
  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    try {
      if ((await fetch(ORIGIN)).ok) return server;
    } catch {
      // not serving yet
    }
    await sleep(500);
  }
  server.kill();
  throw new Error("lighthouse-auth: the test build did not start on port 3200");
}

/** Checks every collected report; returns the problems found (empty when all pass). */
export function verifyReports(dir = REPORTS) {
  const problems = [];
  const runs = new Map();
  for (const file of readdirSync(dir).filter((f) => /^lhr-[0-9-]+\.json$/.test(f))) {
    const raw = readFileSync(join(dir, file), "utf8");
    const lhr = JSON.parse(raw);
    const requested = new URL(lhr.requestedUrl).pathname;
    const final = new URL(lhr.finalDisplayedUrl || lhr.mainDocumentUrl || "about:blank").pathname;
    runs.set(requested, (runs.get(requested) || 0) + 1);
    if (final !== requested) problems.push(`${requested}: a run ended on ${final}`);
    if (lhr.audits?.["http-status-code"]?.score !== 1) {
      problems.push(`${requested}: a run's main document was not HTTP 200`);
    }
    if (/access_token|refresh_token|sb-[a-z0-9-]*-auth-token/i.test(raw)) {
      problems.push(`${file}: contains a session token or auth cookie name`);
    }
    if (raw.includes(PROFILE_PREFIX)) {
      problems.push(`${file}: contains the audit browser's profile path`);
    }
  }
  for (const path of [...PUBLIC, ...AUTHENTICATED.map((p) => p.path)]) {
    if ((runs.get(path) || 0) < RUNS_PER_URL) {
      problems.push(`${path}: ${runs.get(path) || 0} of ${RUNS_PER_URL} runs collected`);
    }
  }
  return problems;
}

/** One Chrome DevTools Protocol call on a browser endpoint (Node's built-in WebSocket). */
function cdp(webSocketUrl, method, params) {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(webSocketUrl);
    socket.onopen = () => socket.send(JSON.stringify({ id: 1, method, params }));
    socket.onmessage = (event) => {
      const message = JSON.parse(String(event.data));
      if (message.id !== 1) return;
      socket.close();
      if (message.error) reject(new Error(`lighthouse-auth: ${method} failed`));
      else resolve(message.result);
    };
    socket.onerror = () => reject(new Error(`lighthouse-auth: ${method} failed`));
  });
}

async function devtoolsEndpoint() {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    try {
      const version = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json/version`)).json();
      if (version.webSocketDebuggerUrl) return version.webSocketDebuggerUrl;
    } catch {
      // not listening yet
    }
    await sleep(250);
  }
  throw new Error("lighthouse-auth: the audit browser did not start");
}

async function main() {
  assertLocal(MAILPIT, "Mailpit");
  if (SUPABASE) assertLocal(SUPABASE, "Supabase");
  const executablePath = process.env.CHROME_PATH || chromium.executablePath();
  const server = await startServer();
  const profile = mkdtempSync(join(tmpdir(), PROFILE_PREFIX));
  let auditBrowser = null;
  try {
    // 1. Sign in and check every approved page with Playwright. The session cookies stay in
    //    memory only and are never printed.
    const browser = await chromium.launch({
      headless: true,
      executablePath,
      args: ["--no-sandbox"],
    });
    let cookies;
    try {
      const context = await browser.newContext();
      const page = await context.newPage();
      await signIn(page);
      for (const target of AUTHENTICATED) await checkRenders(page, target);
      cookies = await context.cookies(ORIGIN);
    } finally {
      await browser.close();
    }

    // 2. A separate Chrome for Lighthouse, holding only that session (Lighthouse attaches to it
    //    through `settings.port`; no other client is connected while it audits).
    auditBrowser = spawn(
      executablePath,
      [
        "--headless=new",
        "--no-sandbox",
        "--no-first-run",
        "--no-default-browser-check",
        "--remote-debugging-address=127.0.0.1",
        `--remote-debugging-port=${DEBUG_PORT}`,
        `--user-data-dir=${profile}`,
        "about:blank",
      ],
      { stdio: "ignore" },
    );
    await cdp(await devtoolsEndpoint(), "Storage.setCookies", {
      cookies: cookies.map((c) => ({
        name: c.name,
        value: c.value,
        domain: c.domain,
        path: c.path,
        httpOnly: c.httpOnly,
        secure: c.secure,
        sameSite: c.sameSite,
        ...(c.expires > 0 ? { expires: c.expires } : {}),
      })),
    });

    // 3. Collect exactly the approved pages into the same report directory.
    const collect = spawnSync(
      "pnpm",
      [
        "exec",
        "lhci",
        "collect",
        "--additive",
        "--startServerCommand=",
        `--settings.port=${DEBUG_PORT}`,
        ...AUTHENTICATED.map((p) => `--url=${ORIGIN}${p.path}`),
      ],
      { stdio: ["ignore", "inherit", "inherit"], timeout: 900_000 },
    );
    if (collect.status !== 0) {
      throw new Error(`lighthouse-auth: lhci collect exited ${collect.status}`);
    }
  } finally {
    auditBrowser?.kill();
    server.kill();
    rmSync(profile, { recursive: true, force: true });
  }

  // 4. Every report: its own route, HTTP 200, the expected number of runs, no session data.
  const problems = verifyReports();
  if (problems.length > 0) {
    throw new Error(`lighthouse-auth: ${problems.length} problem(s):\n${problems.join("\n")}`);
  }
  console.warn("lighthouse-auth: every approved page was audited on its own route with HTTP 200");
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
