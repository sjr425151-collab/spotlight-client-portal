# `src/server`: server-side infrastructure adapters

Adapters for external services. Each one arrives only with its authorized phase:

| Adapter | Phase |
|---|---|
| Supabase | Phase 2 |
| Stripe (test mode) | Phase 3 |
| Resend, storage scanning | Phase 4 |

Rules:
- Every module starts with `import "server-only";` so that importing it from client code fails the build.
- Secrets come only from validated configuration (`@/config/env`). Never read `process.env` directly elsewhere.
- Adapters authorize the caller themselves when they bypass RLS (spec 03 §9 rule 6).
- **Phase 1 contains no adapters, and no external service is connected.**
