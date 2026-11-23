# 03A — Supabase and Next.js Provider Verification (Phase 2)

| Field | Value |
|---|---|
| Version | 0.2.0 |
| Status | **Verification evidence.** Supporting evidence for spec 03 v0.4.0 (Owner-approved 2026-11-23, Phase 2 authorization). This is not a decision record. v0.2.0 adds the Phase 2 local spike results (§5). |
| Purpose | Evidence for spec 03 v0.4.0 under OI-39 (provider verification) and DEP-06 |
| Verified on | 2026-11-23 (documentation); 2026-11-23 (local spike, §5) |

## 1. Method and limitations

- **The published sites were not reachable.** This session's network policy blocks `supabase.com` and `nextjs.org` (DNS failure). No finding below was filled in from memory.
- **Sources instead:** the official documentation source files in the vendors' public GitHub repositories, read at these commits:

| Repository | Commit | Commit date | Path read |
|---|---|---|---|
| `supabase/supabase` | `4a73166675642dc3c1d1fc767a65adbee746d894` | 2026-11-23 | `apps/docs/content/guides/**` (published at `https://supabase.com/docs/guides/...`) |
| `supabase/cli` | `78370ebad862dcf854f38b8ff467b728515159bd` | 2026-11-23 | `apps/cli/src/shared/init/testdata/templates/config.toml` (the CLI's test copy of the `config.toml` template) |
| `vercel/next.js` | `9f632df7a7a15d832a1f4924da5a13ab3479b732` | 2026-11-22 | `docs/01-app/**` (published at `https://nextjs.org/docs/app/...`) |

- **Citations** use the form `guides/<path>.mdx:<line>`, relative to `apps/docs/content/` in `supabase/supabase` unless another repository is named.
- **Limitations:**
  - Repository source can differ slightly from the published site.
  - The pricing page and the provider dashboards could not be checked.
  - Items marked **Unverified** must be confirmed in the Phase 2 local verification spike (03 §16) or by the Owner before they are relied on.

## 2. Verified findings

| ID | Topic | Finding | Evidence |
|---|---|---|---|
| F-01 | Email OTP | Email OTP is a **six-digit code**, emitted with `{{ .Token }}` in the email template. `signInWithOtp` **creates a user by default**. `shouldCreateUser: false` prevents that. | `guides/auth/auth-email-passwordless.mdx:39,180,188-193`; `auth-email-templates.mdx:37` |
| F-02 | OTP and link expiry | One **Email OTP Expiration** setting governs OTPs, magic links, and **invitation links**. Default is **1 hour**. The local default is `otp_expiry = 3600` and `otp_length = 6`. | `auth-email-passwordless.mdx:196-200`; `users.mdx:127`; CLI `config.toml:235-237` |
| F-03 | Disable public sign-up | Project setting "**Allow new users to sign up**": "If this config is disabled, only existing users can sign in." The local keys are `[auth] enable_signup` and `[auth.email] enable_signup`. | `general-configuration.mdx:25`; CLI `config.toml:179,224` |
| F-04 | Invitations | `inviteUserByEmail()` is an admin action that needs the **secret key** on a trusted server. It creates an **unconfirmed** user. Inviting an already-confirmed user returns an **error**. A `redirectTo` that is not on the redirect allow-list is **silently ignored**. The invitation uses the customizable "Invite user" template. | `users.mdx:79-123` |
| F-05 | Invite verification | Templates expose `{{ .Token }}`, `{{ .TokenHash }}`, and `{{ .RedirectTo }}`. A custom link can carry `token_hash` with `type=invite`, verified server-side by `verifyOtp({ token_hash, type })`. Email link scanners can **consume links instantly**. The documented mitigation is to use an OTP code (`{{ .Token }}`). | `auth-email-templates.mdx:37-40,138-143,180-198` |
| F-06 | Before-user-created hook | The hook runs **before a user is created**, and can reject creation (Postgres function or HTTP endpoint). A returned error blocks the creation. Documented uses include "invite-only beta access". | `auth-hooks/before-user-created-hook.mdx:7-9,141-172,196` |
| F-07 | Default SMTP | The built-in SMTP sends **only to the project team's addresses** and is rate-limited with **no SLA**. It is "**not meant for production use**". | `auth-smtp.mdx:16-30` |
| F-08 | Custom SMTP | After custom SMTP is configured, an initial **30 messages/hour** limit applies and can be raised. The guide recommends a separate auth sending domain and From address. | `auth-smtp.mdx:77,112-133` |
| F-09 | Rate limits | Configurable per project. IP-limited endpoints use a **token bucket**, most with capacity 30. **Server-side callers are rate-limited by the server's IP** unless IP forwarding is enabled and `Sb-Forwarded-For` is sent. Local defaults include `email_sent = 2`/h, `sign_in_sign_ups = 30`, `token_verifications = 30`, `token_refresh = 150`. | `rate-limits.mdx:6,37-39,49-72`; CLI `config.toml:200-212` |
| F-10 | CAPTCHA | hCaptcha and Cloudflare Turnstile are supported on auth forms. | `auth-captcha.mdx:8,47` |
| F-11 | MFA factors | MFA supports **TOTP** and **phone**. "TOTP MFA API is **free** to use and is enabled on all Supabase projects by default." Locally, TOTP enroll and verify are **disabled by default** and must be enabled. `max_enrolled_factors = 10`. | `auth-mfa.mdx:20`; `auth-mfa/totp.mdx:41`; CLI `config.toml:301-308` |
| F-12 | AAL | The JWT `aal` claim is `aal1` or `aal2` (missing means `aal1`). The documented RLS template is a **restrictive** policy using `(select auth.jwt()->>'aal') = 'aal2'`. | `auth-mfa.mdx:39-51,183-201`; `row-level-security.mdx:687-690` |
| F-13 | Freshness (`amr`) | Access tokens carry an `amr` array of `{method, timestamp}`, **most recent first**. Comparing method and timestamp to enforce recency is documented. | `auth-mfa.mdx:304-338` |
| F-14 | Unenroll lag | Unenrolling a factor downgrades `aal2` to `aal1` **only after the refresh interval**, unless the session is refreshed. | `auth-mfa.mdx:124` |
| F-15 | Session tokens | Access tokens are short-lived ("usually between 5 minutes and 1 hour"); the default of 1 hour is recommended. Refresh tokens are single-use, with a **10 s reuse interval**. Reuse outside the exceptions **terminates the session**. | `sessions.mdx:15,89-117`; CLI `config.toml:168-177` |
| F-16 | Session limits | **Time-boxed sessions, inactivity timeout, and single-session-per-user are "only available on Pro Plans and up."** They are enforced when the session is next refreshed. | `sessions.mdx:63-83` |
| F-17 | Revocation | `signOut` scopes are `global` (default in JS), `local`, and `others`. Global revokes all of the user's refresh tokens. "**Access Tokens of revoked sessions remain valid until their expiry time.**" For strong guarantees, check the JWT `session_id` against `auth.sessions`. | `signout.mdx:84-96,170`; `sessions.mdx:48,133-137` |
| F-18 | Server-side checks | `getUser()` is "the only way to detect that a session ended server-side". `getClaims()` verifies signature and expiry. **Never trust `getSession()` in server code.** | `server-side/advanced-guide.mdx:51`; `server-side/creating-a-client.mdx:293-297` |
| F-19 | Next.js integration | Use `@supabase/ssr` with cookies. On Next.js 16, a `proxy.ts` refreshes tokens with `getClaims()` and must return the response carrying the refreshed cookies. ISR or CDN caching can serve another user's session cookie. | `server-side/creating-a-client.mdx:8,30-46,210-231,273-283,1001` |
| F-20 | API keys | **Publishable** (`sb_publishable_…`) for browsers; **secret** (`sb_secret_…`) for servers only, and it **bypasses RLS**. A secret-key client that carries a user token runs under that user's RLS. Legacy `anon` and `service_role` JWT keys still exist. | `getting-started/api-keys.mdx:22-23,50-63,80-90`; `row-level-security.mdx:805-811` |
| F-21 | Signing keys | Asymmetric signing keys (ES256/RS256) are recommended: local verification, and automatic revocation via JWKS. HS256 is "**not recommended for production**". | `auth/signing-keys.mdx:18-32,134-137`; `auth/jwts.mdx:182-263` |
| F-22 | RLS fundamentals | Enable RLS on **every table in an exposed schema**. On projects that still grant `anon` and `authenticated` by default, revoke those grants. Wrap `auth.uid()` as `(select auth.uid())`. Use `to authenticated`. **Views bypass RLS** unless `security_invoker = true`. | `row-level-security.mdx:12,25,41,105-107,527,588,600-608` |
| F-23 | Security definer | Set `search_path = ''` and schema-qualify names. **Never create a security definer function in an exposed schema.** Revoke `execute` from `public`, `anon`, and `authenticated`, including default privileges. Prefer `security invoker`. | `row-level-security.mdx:694-801`; `database/functions.mdx:426-484` |
| F-24 | Auth audit log | Auth events are logged. Optional copy to `auth.audit_log_entries`. | `auth/audit-logs.mdx:8-33` |
| F-25 | Local development | Needs the Supabase CLI plus Docker (**at least 7 GB RAM**). `supabase start` and `supabase db reset` apply all migrations, then `seed.sql`. Includes local Studio and a local email testing server (`[local_smtp]`). | `local-development/cli-workflows.mdx:18,49,158-195,420-423,511-513`; CLI `config.toml:105-113` |
| F-26 | Hosted safety | CLI commands target the **local stack by default**. `--remote` is explicit. Hosted changes require confirmation. An AI agent "**never gets a prompt**", so a hosted change without `--yes` fails and changes nothing. | `local-development/local-and-hosted-projects.mdx:17-23,160-172,241-257` |
| F-27 | Migrations | `supabase migration new`, `db diff`, `db push --remote`. **Never change the remote database directly.** `migration repair` fixes history only. | `deployment/database-migrations.mdx:34,203-231,335,367,458-515` |
| F-28 | RLS testing | pgTAP through `supabase test db`. Impersonate with `set local role authenticated` and `request.jwt.claims`. Tests run in a transaction that rolls back. | `database/postgres/testing-row-level-security.mdx:8-124`; `local-development/testing/overview.mdx:11-86` |
| F-29 | Storage | **No uploads without RLS policies** on `storage.objects`. Path-scoped policies use `storage.foldername(name)`. Secret and service keys bypass storage RLS. | `storage/security/access-control.mdx:15-111` |
| F-30 | Next.js nonce CSP | "You **must use dynamic rendering** to add nonces." The proxy creates a per-request nonce, sets `Content-Security-Policy` and `x-nonce`, and Next.js applies the nonce to its scripts automatically. The example uses `'strict-dynamic'`. `'unsafe-eval'` is needed **only in development**. The matcher should skip static assets and prefetches. | `vercel/next.js` `docs/01-app/02-guides/content-security-policy.mdx:24-214` |
| F-31 | Next.js proxy | `middleware` is **renamed `proxy`** in Next.js 16. The proxy defaults to the **Node.js runtime**; the `runtime` option is unavailable. | `vercel/next.js` `docs/01-app/03-api-reference/03-file-conventions/proxy.mdx:11,255-257` |

## 3. Unverified items (must be confirmed before reliance)

U-01 to U-05 and U-11 were resolved by the Phase 2 local spike on 2026-11-23. See §5 for the observations; the rows below are kept for traceability.

| ID | Item | How to resolve |
|---|---|---|
| U-01 | Whether `inviteUserByEmail` still works when public sign-up is disabled (F-03 says only existing users can **sign in**) | **Resolved (S-01).** Phase 2 local spike, test with `enable_signup = false` |
| U-02 | Whether an invited, unconfirmed user can sign in with `signInWithOtp({ shouldCreateUser: false })`, or must verify the `invite` OTP type first | **Resolved (S-02); the spec deferred this choice to the spike.** Local spike |
| U-03 | What `signInWithOtp({ shouldCreateUser: false })` returns for an unknown email (account-enumeration risk) | **Resolved (S-03).** Local spike. The design returns a generic response regardless (03 §5). |
| U-04 | Whether a fresh TOTP challenge at `aal2` adds a new `amr` entry with a current timestamp (needed for "fresh reauthentication") | **Resolved (S-04), with an ordering caveat.** Local spike |
| U-05 | Admin API for removing a lost staff MFA factor | **Resolved (S-05).** Check the reference docs (not in the guides read) and run a local spike |
| U-06 | Hosted default rate limits and the allowed range for Email OTP Expiration | Owner checks the hosted dashboard when a hosted project is authorized |
| U-07 | **Plan prices and feature gating** (pricing page unreachable). Only "Pro and up" for session controls (F-16) is verified. | **Owner** checks `supabase.com/pricing` (OI-50) |
| U-08 | Plan availability of the before-user-created hook | Owner and dashboard check (OI-50) |
| U-09 | Phone MFA pricing (in a documentation partial not retrieved) | Not needed. The design uses TOTP only. |
| U-10 | Hosted Postgres major version vs the local default (`major_version = 17`) | Check at hosted project creation |
| U-11 | Admin API that terminates all sessions of a deactivated user (the guides read cover only user-initiated `signOut` scopes, F-17) | **Resolved (S-05).** Reference docs plus local spike. Data access is already denied live through `profiles.status` (03 §6.2). |

## 4. Material conflicts with existing specifications (escalated, not silently changed)

| # | Conflict | Specification affected | Resolution proposed in 03 v0.4.0 |
|---|---|---|---|
| C-1 | Supabase invitation links and OTPs share one expiry, default 1 hour (F-02). Spec 03 proposed a **7-day** invitation. | 03 §6 | **Two layers.** The app's own invitation record (hashed token) is valid for 7 days **[PROPOSED]**. The Supabase invite only provisions the user, and every sign-in uses a fresh short-lived OTP (03 §6). No approved decision changes. |
| C-2 | Access tokens of revoked sessions stay valid until expiry (F-17). Spec 03 proposed denial "within 60 s". | 03 §6 | Authorization reads **live** state (membership, profile status, `auth.sessions` row) on every request and in RLS, so revocation takes effect immediately for data access (03 §7). |
| C-3 | Session time-box, inactivity timeout, and single-session controls require a **Pro plan** (F-16). Spec 03 proposed idle and absolute limits. | 03 §6 | The limits depend on the plan decision (**OI-50**). App-level fallbacks are specified for local development. |
| C-4 | A nonce CSP **requires dynamic rendering** (F-30). Phase 1 pages are static. | 02 §7 (performance), 03 T-SEC-03 | Every HTML route becomes dynamic. The performance budgets still apply and must pass. This is an explicit approval item, not a decision change. |
| C-5 | Default SMTP cannot deliver to clients (F-07). OI-04 requires "appropriately configured email delivery". | OI-04 | Local development uses the local email testing server. A custom SMTP provider is needed before any hosted environment (**OI-51**). |

## 5. Phase 2 local verification spike (spec 03 §18), 2026-11-23

**Environment.** Supabase CLI 3.2.0 (release checksum verified), local stack in Docker, Postgres image `17.4.1.054`, `enable_signup = false`, `otp_expiry = 600`, `jwt_expiry = 900`, TOTP enroll and verify enabled, the before-user-created hook enabled. Synthetic `@example.test` users only; email read from the local Mailpit. No hosted project, SMTP provider, or real address was used.

**Method.** Scripted calls with `@supabase/supabase-js` 2.119.2 against the local API, then database inspection. The same behaviors are now pinned by the automated suites: pgTAP (`supabase/tests`), integration (`tests/integration`), and Playwright (`tests/e2e/auth.spec.ts`).

| ID | Question | Observation | Conclusion |
|---|---|---|---|
| S-01 (U-01) | Does `admin.inviteUserByEmail` work with sign-up disabled? | No error. An **unconfirmed** user is created. The email contains the six-digit code and the allow-listed `{{ .RedirectTo }}` link. A redirect that is not allow-listed is not used (matches F-04). | Yes. Provisioning works with sign-up disabled. |
| S-02 (U-02) | Can an invited, unconfirmed user request a fresh code with `signInWithOtp({ shouldCreateUser: false })`? | **No.** 422 `signup_disabled`, and no email. The code in the invitation email verifies with `verifyOtp({ type: 'email' })` (and with `type: 'invite'`), creates a session, and confirms the email. Re-inviting an unconfirmed user sends a **new** code and expires the old one (`otp_expired`). Re-inviting a confirmed user returns 422 `email_exists`. A confirmed user can use `signInWithOtp`. | The first sign-in uses `type: 'email'` with the code from the invitation email. "Send me a new code" on a valid invitation link re-invites while the user is unconfirmed, and uses `signInWithOtp` once they are confirmed. **This refines 03 §6.1 step 3** ("requests a fresh sign-in OTP"), which assumed `signInWithOtp` works before confirmation. All approved values are unchanged. Flagged for Owner confirmation (03 §18.1, OI-53). |
| S-03 (U-03) | What does `signInWithOtp({ shouldCreateUser: false })` return for an unknown email? | 422 `otp_disabled` ("Signups not allowed for otp"), no email, no user. `shouldCreateUser: true` also fails (422 `signup_disabled`). | The raw error distinguishes unknown emails, so the server maps every outcome to one generic response (03 §5, TM-03). Implemented in `src/server/services/sign-in.ts`. |
| S-04 (U-04) | Does a fresh TOTP challenge at `aal2` add a current `amr` entry? | Yes: re-challenging refreshes the `totp` timestamp. **But `amr[0]` was `otp`, not `totp`, right after the first TOTP verification.** The array is not reliably ordered most-recent-first, despite F-13. | Freshness is enforceable. `private.mfa_is_fresh()` checks **every** `amr` entry for a `totp` timestamp within 5 minutes, instead of only `amr[0]` (03 §7, §9.2 say `amr[0]`). This is as strict as intended and avoids false rejections. Flagged for Owner confirmation (03 §18.1). |
| S-05 (U-05, U-11) | Lost-factor reset, and terminating a deactivated user's sessions | `auth.admin.mfa.deleteFactor` removes the factor. Banning a user (`updateUserById`, `ban_duration`) blocks refresh (`user_banned`) but **leaves `auth.sessions` rows**. Global `signOut` deletes the user's session rows. | Factor reset: secret-key call after an Owner fresh-MFA check (`src/server/services/staff.ts`). Deactivation: `private.set_user_status` deletes the user's `auth.sessions` rows (their refresh tokens die with them), live `profiles.status` checks deny data on the next request, and an Auth ban blocks new sign-ins. |
| S-06 | Can an existing, confirmed user be emailed an invitation to another project? | No: `inviteUserByEmail` returns `email_exists` (as F-04 predicts), and Resend is not authorized. | As 03 §6.1 step 2 specifies, the invitee signs in and accepts the pending invitation **in the portal**, with no link token. `accept_invitation(id, null)` binds it to the caller's verified email and does not count a mismatch as a token guess. Flagged for Owner confirmation, because §6.1 step 4 lists a token check (03 §18.1). |
| S-07 | Can the secret key create users that bypass the hook? | `admin.inviteUserByEmail` for an email without a pending invitation is **rejected by the hook** (403). `admin.createUser` **bypasses** the before-user-created hook. | The application never calls `createUser` or `signUp`; a static test enforces this (`tests/unit/static-security.test.ts`). |
| S-08 | Local stack limits that affect tests | The local `auth.email.max_frequency` is 1 s per address, and the CLI template's `email_sent` limit is 2 per hour. | Local and CI `email_sent` is raised to 100 per hour (Mailpit only). The app limits of 03 §17 apply on top. Not a hosted setting (U-06 stands). |

**Also confirmed during implementation:**
- The audit trigger, append-only triggers, and grants behave as designed (pgTAP 040).
- `next/image` adds an inline `style="color:transparent"` attribute, which the nonce CSP blocks (`style-src` has no `'unsafe-inline'`). The logo is rendered from `getImageProps()` without that attribute (T-SEC-04).
- **C-4 outcome:** with every page dynamic, the Lighthouse budgets still pass locally: home performance 99, accessibility 100, best practices 100, SEO 100; `/sign-in` 100/100/100 (SEO is not assessed because the page is `noindex`) (T-PERF-01).

**Contradictions.** None of these results contradicts an approved decision or an approved value. S-02, S-04, and S-06 refine mechanics that 03 left to the spike or did not anticipate. They are recorded in 03 §18.1 and OI-53 for Owner confirmation, and are listed in the implementation pull request.

