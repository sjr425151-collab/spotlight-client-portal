# `src/server`: server-side infrastructure adapters

Adapters for external services. Each one arrives only with its authorized phase:

| Adapter | Phase |
|---|---|
| Supabase (local stack) | Phase 2 (implemented) |
| Stripe: `stripe/` gateway contract, network-free mock, raw-body signature verification | WP-B (implemented, mocked only; a real test-mode gateway needs AUTH-002) |
| Resend, storage scanning | Phase 4 |

Rules:
- Every module starts with `import "server-only";` so that importing it from client code fails the build.
- Secrets come only from validated configuration (`@/config/env`). Never read `process.env` directly elsewhere.
- Adapters authorize the caller themselves when they bypass RLS (spec 03 §9 rule 6).
- Only `supabase/admin.ts` reads the secret key, and only `src/server/**` may import it (ESLint rule and static test). Every use follows an explicit authorization check (spec 03 §9.1 rule 6).
- **Only a local Supabase stack is connected.** No hosted service and no Stripe API is connected. `src/server/stripe/index.ts` fails closed when no gateway is configured.
