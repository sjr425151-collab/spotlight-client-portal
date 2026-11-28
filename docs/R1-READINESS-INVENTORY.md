# R1 Readiness Inventory

| Field | Value |
|---|---|
| Version | 0.1.0 |
| Status | **Inventory (Tier 0, Main).** It is not a decision, a grant or new scope. It records what remains for the R1 release candidate (01 §9) as of `main` `0841efd`, 2026-11-28, prepared at the Owner's request after AUTH-028. Where it disagrees with AUTHORIZATIONS, 08 or an approved spec, those govern (CLAUDE.md §2). The items it found uncertain or conflicting (§6) are escalated as OI-135 and OI-136, not resolved here |
| Prepared by | Main. A read-only research draft, verified by Main against the cited lines |
| Citation keys | **CS** = docs/CURRENT-STATE.md · **AU** = docs/AUTHORIZATIONS.md · **OI** = OPEN-ISSUES.md · **08** = docs/08-DECISIONS-AND-CHANGELOG.md · **RB** = docs/OWNER-RUNBOOKS.md · **01**, **02**, **03**, **03A**, **04**, **05**, **07** = the specs. Line numbers are at `22eb3fa` and may shift slightly |

## 1. Summary

All R1 implementation that local and CI can reach is merged and verified with synthetic and fixture content. That covers WP-0, WP-B, WP-C, WP-S, WP-H, the integrated T-E2E-01 to T-E2E-10 suite, the contractual architecture (DEP-19: PWP-1, PWP-2, PWP-5a, PWP-5b) and the AUTH-026/027 remediations (CS:19, CS:26, CS:122, OI:279). AUTH-028 (OI-134, test-only) is also complete: PR #88 merged at `0841efd`. The R1 release candidate has not started (CS:39). The 01 §9 criteria require it to pass **in staging with Stripe test mode** (01:146). Nothing is deployed (CS:22).

The remaining work falls into four groups:
1. **Hosted staging (AUTH-003).** Granted but not active. It waits on the Owner's accounts and on the OI-127 rulings. It covers DEP-14, DEP-17, the hosted part of OI-115 and the staging Lighthouse run.
2. **The rest of AUTH-002.** Granted but not active. It waits on the OI-128 rulings and a new restricted key. It covers F7, F8, N1(c) and DEP-15.
3. **Contractual content and evidence.** Counsel approval of the R1 instruments (PWP-3, DEP-03; OD-19), the Owner's DEP-18 scope content, and PWP-4 materialization with R-04 verification. None of these is granted.
4. **Vendor integrations.** Scanii (DEP-07) and Sentry (DEP-12) are conditionally selected, with no account or integration authorized.

Production launch is not authorized (CS:21). DEP-20 is a production gate, not a release-candidate prerequisite (OI:280; 08:1021).

## 2. Table A: engineering requirements

| ID / ref | Requirement | Current state | Blocks R1 RC? | Authorization needed | Evidence |
|---|---|---|---|---|---|
| F7 (DEP-06) | Test-mode stop of automatic collection: `auto_advance=false`, `charged_after_halt`, `payment_action_required`, decline with hosted fallback, timed-out create reconciled | Not run | Yes | Rest of AUTH-002 (not active; OI-128 open) | 04:508; OI:338; CS:122 |
| F8 (DEP-06) | Test-mode saved card: card field after subscription Checkout, setup-mode SetupIntent `off_session`, wallets, detached and updated events | Not run | Yes | Rest of AUTH-002 | 04:509; OI:338; CS:122 |
| N1(c) | Linking criterion: `invoice.paid` charge and payment-intent references, including multi-payment invoices; refunds and disputes attributed | Not run (N1(a) delivered in PR #35) | Yes | Rest of AUTH-002 | 04:510; 04:827; CS:34; CS:122 |
| DEP-15 | Real test-mode webhook verification: signing secret, event delivery to a local server, recorded run (T-PAY-16) | Not started | Yes | Rest of AUTH-002 (OI-128(c), (e)) | OI:275; AU:81; CS:81 |
| DEP-14 (WP-D) | Hosted staging Supabase: create and configure it (sign-up disabled, OTP expiry, signing keys, TOTP, IP forwarding, SMTP), push reviewed migrations only, with no seed and no reset (A3) | Not started; WP-I is the named executor from `spotlight-staging-ops` | Yes | AUTH-003 (not active; OI-127 open) | OI:274; AU:115-123; CS:37; CS:80 |
| A3 boundary | WP-D verifies and documents the migrations-only boundary before hosted-environment acceptance | Not started | Yes | AUTH-003 | AU:118; CS:37 |
| Migration order | Out-of-order files: `20261127125000` and `20261127150000`; `20261128120000` (after `…130000`); `20261128140000` and `20261128140100` (after `…150000`). AUTH-003 creates hosted projects fresh and applies reviewed migrations with `supabase db push` (A3). A first push to a fresh project applies them in filename order, so nothing extra is needed. Any later push that brings in a file timestamped before one already applied needs the explicit include-all handling, recorded per push | Recorded. The hosted runbook states it per push | Conditional: only after the first push | AUTH-003 | AU:118; AU:125; CS:943; CS:976 |
| OI-115 (hosted part) | Environment classification consistency in hosted provisioning, failing closed. Staging with no settings row reads as `production` (D2) | Local part closed (AUTH-016); hosted part open | Yes | AUTH-003, plus the OI-127(d) ruling | OI:157; OI:206; CS:122 |
| DEP-17 | Hosted scheduler for WP-B billing jobs and WP-C scan and deletion retries, with recorded runs and alerting (DEP-12) | Not started; no mechanism named | Yes (staging) | AUTH-003, plus the OI-127(f) ruling. Staging reconciliation may need a Stripe credential (OI-127(h)) | OI:277; OI:208; CS:83 |
| N1(b) | The Owner runs reconciliation before each publication until DEP-17 exists | Procedure drafted (RB §5, [PROPOSED]) | Yes | Owner action; RB review | 04:827; RB:35-37; CS:122 |
| DEP-12 integration | Sentry Team, US region. Owner-critical alerts use it in R1. Sensitive-data exclusion must be demonstrated with synthetic events. Open questions: Next 16 compatibility, monthly price, Supabase data capture | Conditionally selected; no account or integration | Yes | New grant (OI-127(g): the more restrictive reading) | CS:766; OI:272; OI:209; CS:122 |
| DEP-07 integration | Scanii Basic, US region. Verify its checksum algorithm. Establish metadata retention and deletion controls. DPA review and security assessment before any real client file | Conditionally selected; no account or integration | Yes | New grant | CS:765; OI:267; CS:122 |
| Criterion 17 | Staging-build Lighthouse run against the OI-23 thresholds | Not run (CI part passes) | Yes | AUTH-003 (Vercel staging) | 01:166; CS:122 |
| PWP-3 | Counsel and publication evidence: an in-repo manifest of identifiers and hashes only; §3.1 byte verification (OI-109); TV-01 measurement against the limits | Not started; needs counsel output | Yes (OD-19) | New grant (inferred: no PWP-3 record exists in AU) | 04:198; 08:1168; OI:197-200; OI:354 |
| PWP-4 / DEP-18 closure | Authorized non-production materialization of real content, then R-04 end-to-end verification of the complete R1 lifecycle including PWP-5. Loaders activate in `development`/`test` only, so staging may need separately authorized eligibility engineering | Not started. Loader infrastructure exists (AUTH-018, AUTH-021 OD-5) | Yes | New grant, possibly two: content loading and staging eligibility (AU:507) | OI:278; AU:507; 08:1154; 08:1021; OI:188 |
| RC acceptance run | Criteria 1 to 18 pass in staging with Stripe test mode, by automated tests or recorded verification | Not started | Yes (this is the RC) | AUTH-003 plus a Stripe test credential on staging. No record covers that (OI-127(h); inferred) | 01:146-167; CS:39 |
| F10 / DEP-03 wording | R1 wording, including **Approve Website & Authorize Final Payment**, card retention and revocation, is never presented as legally approved until counsel approves it | Placeholder and fixture discipline in place | Yes (presentation constraint) | None: it is a constraint | CS:122; OI:324; CLAUDE.md §5 |

Not blocking, as recorded: the F2 carry-forwards, L1 and L2 (optional), and N2 to N4 (accepted) (CS:123-125). The AUTH-026 review notes WP-B N-1 and N-2 and WP-I N-1 and N-2 were not applied (CS:982).

## 3. Table B: external dependencies

| ID | Dependency | State | Who acts | Blocks |
|---|---|---|---|---|
| DEP-03 | Legal review: R1 instruments, approval wording, card retention, revocation, OI-82 refund terms, OI-92(e), package-scope language (A4), and the evidence standard (OI-107) | Not started; "start now" (longest lead time) | Owner and counsel | R1 RC (OD-19) and production (OI:263; CS:71; OI:315-329) |
| DEP-04 | Tax review and Stripe Tax configuration | Not started | Owner and tax advisor | Production tax collection (OI:264; CS:72) |
| DEP-05 | Privacy and retention review; retention periods are provisional | Not started | Owner and counsel | Production (OI:265; CS:73; CS:56) |
| DEP-06 | Provider verification: Stripe test-mode items (F7, F8, N1); hosted Supabase U-06 to U-08 and U-10; Vercel protected previews and rollback; Resend; the domain registrar | In progress | Implementer; Owner for dashboard checks | Stripe items block the RC; the rest block hosted acceptance and production (OI:266; OI:338-341; 03A:74-78; 02:165-173) |
| DEP-07 | Scanii Basic account, DPA, security assessment | Conditionally selected | Owner | R1 RC integration (OI:267; CS:765) |
| DEP-12 | Sentry Team account, DPA, subprocessor review | Conditionally selected | Owner | R1 RC integration (OI:272; CS:766) |
| DEP-14 | Hosted staging Supabase, Pro plan (OI-50) | Not started. Owner-reported as now being set up | Owner (account), WP-I (execution) | AUTH-003 activation and the RC (OI:274; CS:994) |
| Vercel | Portal project with protected preview and staging (02 §4) | Not recorded as created | Owner (account), WP-I | AUTH-003 activation and criterion 17 (AU:115-116; CS:107) |
| Resend + DNS | SMTP on a separate auth sending subdomain (OI-51). The DNS records are Tier 3 Owner actions | Not recorded | Owner | Staging auth email and AUTH-003 (AU:115-116; CS:107) |
| `spotlight-staging-ops` | Dedicated cloud environment for hosted work. Main confirms isolation; WP-I lists least-privilege permissions | Not recorded as created | Owner (creation approval), Main, WP-I | AUTH-003 activation (AU:123; CS:767) |
| Stripe sandbox | "Spotlight Client Portal - Development". Catalog verified by DEP-01 and Stage A attempt 3 | Ready; the rest of AUTH-002 is not active | Owner (key, allowlist, Customer Portal and Smart Retries settings) | F7, F8, N1(c), DEP-15 (AU:82-85; AU:106-107; OI:261) |
| DEP-15 | Test-mode webhook signing secret and a delivery path (Stripe CLI or other) | Not started | Owner (credential), WP-B | R1 RC (OI:275) |
| DEP-17 | Hosted scheduler mechanism | Not chosen | WP-D (staging), Owner (production) | R1 RC in staging (OI:277; OI:208) |
| DEP-18 | Owner-supplied scope content for Essential, Professional, Advanced, Signature and Prestige; counsel review | In progress: infrastructure done, content not supplied | Owner and counsel | R1 RC (A5) (OI:278) |
| SLM-CPS-002 | Package specification authority, effective once completed, approved and published | Reconstruction draft (v0.1.0) outside Git | Owner and counsel | Entitlement checks (05:79). Scope traceability for DEP-18 (OI:278). R1 status unclear; see §6 |
| DEP-19 | Contractual architecture | **Complete** (synthetic and fixture content) | — | — (OI:279) |
| DEP-20 | Production contractual activation | Not started | Owner (Tier 3) | Production only (OI:280) |
| DEP-02 / DEP-09 | Live Price ID verification / production infrastructure P-1 to P-9 | Not started | Owner (Tier 3) | Production only (OI:262; OI:269) |
| DEP-08 | Brand assets, production part: vector master, variants, favicon, final visual approval | Outstanding | Owner | Production (OI:268; OI:358-365) |

## 4. Table C: Owner actions

| Action | Related ID | Why needed | Blocks |
|---|---|---|---|
| Rule on OI-127 (a) to (h): dev vs staging; the preview Supabase target; `--yes` vs hosted pushes; staging classification; WP-I environment move; scheduler mechanism; monitoring grant; Stripe key on staging | OI-127, AUTH-003 | The AUTH-003 record leaves these unresolved | AUTH-003 execution, DEP-14, DEP-17, OI-115 hosted (OI:202-210; CS:106) |
| Rule on OI-128 (a) to (e): credential mechanism; carry-over of the Stage A controls; how the webhook secret is delivered; the Refunds permission; Stripe CLI and its hosts | OI-128, AUTH-002 | The AUTH-002 record leaves these unresolved | F7, F8, N1(c), DEP-15 (OI:212-217; CS:106) |
| Create the staging Supabase project (Pro) and record its region; check U-06, U-07, U-08 and U-10 on the dashboard | AUTH-003, DEP-14, OI-50 | Activation condition | AUTH-003 (AU:114; CS:107; 03A:74-78) |
| Create the Vercel project (protected preview and staging); set up Resend SMTP; add DNS records (Tier 3) | AUTH-003, OI-51 | Activation condition | AUTH-003, criterion 17 (AU:115-116; CS:107) |
| Approve creating `spotlight-staging-ops`; enter each credential only through the secure form; record accounts and plans (no values) | AUTH-003 | Activation condition and environment isolation | AUTH-003 (AU:116; AU:123; CS:107) |
| Rest of AUTH-002: create a new restricted `rk_test_` key, add `api.stripe.com` (and any verified CLI hosts) to the allowlist, confirm no live credential, pin and checksum-verify the CLI if used, attest, reconcile | AUTH-002 | Activation conditions (1) to (4) | F7, F8, N1(c), DEP-15 (AU:82; CS:108) |
| Apply and record the sandbox Customer Portal and Smart Retries settings | AUTH-002 | Owner-only Dashboard settings | AUTH-002 verification (AU:85) |
| Authorize account creation and integration for Scanii and Sentry; complete the DPA, security and subprocessor reviews | DEP-07, DEP-12 | The selections authorize nothing | DEP-07 and DEP-12 integrations (CS:109; CS:765-766) |
| Engage counsel (DEP-03), a tax advisor (DEP-04) and privacy review (DEP-05); obtain counsel-approved R1 instruments and evidence that meets OI-107 | DEP-03/04/05, PWP-3, OD-19 | Counsel approval is a release-candidate prerequisite | R1 RC (DEP-03); production (DEP-04, DEP-05) (CS:104; OI:328) |
| Supply the standard scope content for all five packages, include it in counsel review, and authorize real content loading | DEP-18, OI-106 | Mandatory before the RC (A5) | PWP-4, R-04 (CS:105; OI:278) |
| Grant PWP-3 and PWP-4 (including any staging eligibility engineering) when their prerequisites exist | PWP-3, PWP-4, OI-125 | No grant exists | Criterion 18 (AU:507; 08:1021) |
| Review OWNER-RUNBOOKS v0.5.0 ([PROPOSED]), in particular §5 and §7 | OI-90, N1(b) | §7 is required before RC acceptance | R1 RC (CS:110; RB:6; RB:45) |
| Run project reconciliation immediately before each publication during the RC | N1(b) | Required until DEP-17 schedules it | Criterion 14, R1 RC (RB:35-37) |
| Change repository visibility (Tier 3), or record a decision on it | FD-03, OI-106 | Recorded as not performed | Not recorded as an RC blocker (CS:111; RB:76-92) |
| Supply brand assets | DEP-08 | Production part outstanding | Production (CS:112) |
| Revoke the AUTH-002 key at expiry; note that AUTH-002 and AUTH-003 both expire on 2027-01-31 | AUTH-002, AUTH-003 | Expiry rows | Timing risk (inferred) (AU:89; AU:120) |
| Accept the R1 release candidate (a separate decision; it does not authorize launch) | 01 §9 | Final gate | — (01:146; CS:21) |

## 5. Suggested critical path

1. **Start counsel (DEP-03) and DEP-18 content now**, in parallel with everything else. They are the longest external lead and gate PWP-3, PWP-4 and criterion 18 (CS:71; OI:200).
2. The Owner rules on OI-127. The Owner then completes the Supabase, Vercel, Resend and DNS accounts and `spotlight-staging-ops`. Main confirms isolation and records AUTH-003 activation (CS:994; AU:123).
3. WP-I provisions staging:
   - migrations only, on a fresh database or with the explicit `--include-all` handling (AU:125; CS:976);
   - classification (hosted part of OI-115);
   - A3 verification;
   - U-06 to U-10.
4. In parallel: the Owner rules on OI-128 and sets up the rest of AUTH-002. WP-B then runs F7, F8, N1(c) and DEP-15 in the sandbox.
5. The Owner authorizes the Scanii and Sentry accounts and completes the DPA reviews. Integration grants follow, then implementation. DEP-12 alerting feeds DEP-17.
6. DEP-17 scheduler on staging, once the mechanism ruling exists and any staging Stripe credential is ruled on.
7. Counsel approval, then a PWP-3 grant and evidence manifest, then a PWP-4 grant for staging materialization (and eligibility engineering if needed), then R-04 end-to-end verification in staging.
8. The RC run in staging with Stripe test mode:
   - criteria 1 to 18;
   - the staging Lighthouse run;
   - the Owner's N1(b) reconciliation;
   - OWNER-RUNBOOKS §5 and §7 reviewed.
9. The Owner accepts the RC. Production steps stay separate and Tier 3: DEP-02, DEP-04, DEP-05, DEP-08, DEP-09, DEP-20.

## 6. Uncertain or conflicting (not resolved here)

1. **DEP-18 state.** CS §4 says "Not started" (CS:84). OI says "In progress (status corrected 2026-11-28)" (OI:278).
2. **DEP-19 in the CS §7 list.** It sits under "Open" while the same cell says implementation is complete (CS:122). The register says Complete (OI:279). Criterion 18 is still labeled "not implemented" (01:167).
3. **DEP-03 timing.** The register still reads "Phase 5 (Prod; before enforcement)" (OI:263). OD-19 and OI-126 require counsel approval of the R1 instruments before the RC (08:1168; OI:197).
4. **Stale labels.** These conflict with the decided or implemented state:
   - 03 still shows [PENDING OI-50/51/52] (03:188, 03:243, 03:615), though these are decided (OI:81-83).
   - 08 §2 says no [PENDING] items exist (08:35), while OI-127 and OI-128 are open.
   - 03 §4 rows say "not implemented: PWP-1/2/5" (03:94-97).
   - 07:63 says "not implemented: PWP-5".
   - RB §9 says the OI-93 candidate blocks remain in R1 (RB:65), though AUTH-010 implemented OI-93 (OI:109).
5. **CS §3 version table** is pinned "as of 59b9aac" and is stale against the file headers. For example, CURRENT-STATE shows 1.47.0 vs 1.57.0, OPEN-ISSUES 0.49.0 vs 0.59.0, AUTHORIZATIONS 1.42.0 vs 1.50.0, and 04 0.11.0 vs 0.11.1 (CS:46-62; CS:5; OI:5; AU:5; CS:944).
6. **Migration ordering is wider than the three files in the brief.** `20261127125000` and `20261127150000` (AU:125) and `20261128120000` (CS:943) are also out of order. It is also unconfirmed which command applies on a hosted database:
   - AUTH-003 names `supabase db push` (AU:118);
   - the completion records name `supabase migration up --include-all` (CS:976);
   - agents may never pass `--yes` (03:581; OI-127(c)).
7. **Staging plus Stripe test mode.** The RC must pass "in staging with Stripe test mode" (01:146). AUTH-002 binds its key to `spotlight-client-portal-dev` (AU:82), and OI-127(h) leaves open whether staging may hold any Stripe key. No current record visibly authorizes the staging RC payment journey (inferred).
8. **AUTH-003 monitoring scope.** AUTH-003 lists monitoring integration "once DEP-12 is selected" (AU:115). OI-127(g) applies the more restrictive reading: a separate grant is required. DEP-14 names dev and staging, while AUTH-003 is staging only (OI:203).
9. **Documents outside the repository.** The "next-wave execution plan" and the "commercial-readiness inventory" (CS:102; CS:883) were Main's reports to the Owner. They are not repository files. Their decisions are recorded in 08 and AUTHORIZATIONS.
10. **Entitlement checks.** It is unclear whether entitlement checks against SLM-CPS-002 are R1 requirements (05:79; AU:569; CS:912). No record classifies them as RC blockers.
11. **Criterion 15 in staging.** Staff deploy to the client's isolated deployment and record it (01:164). No record names a staging client-site deployment target (inferred gap; unconfirmed).
12. **OI-134** is closed by AUTH-028 (PR #88), so it no longer needs classifying.
13. **Owner-reported only.** The Owner's in-progress Supabase setup is recorded as Owner-reported. No account, region or plan evidence is recorded yet (CS:994).
