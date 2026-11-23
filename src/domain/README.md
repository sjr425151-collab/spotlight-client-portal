# `src/domain`: business rules

Framework-independent business logic (spec 02 §1), for example:
- state machines
- publication gate evaluation
- integer-cent money calculations
- the America/Detroit deadline calendar

Rules:
- Pure TypeScript only. No React, no Next.js APIs, no network or database access, and no `server-only` imports. Enforced by ESLint `no-restricted-imports`.
- Every module ships with unit tests under `tests/unit/`.
- **Phase 1 contains no domain modules.** Each workflow arrives with its authorized phase (OI-02). Do not add speculative logic here.
