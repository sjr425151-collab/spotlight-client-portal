# `src/domain`: business rules

Framework-independent business logic (spec 02 §1), for example:
- state machines
- publication gate evaluation
- integer-cent money calculations
- the America/Detroit deadline calendar

Rules:
- Pure TypeScript only. No React, no Next.js APIs, no network or database access, and no `server-only` imports. Enforced by ESLint `no-restricted-imports`.
- Every module ships with unit tests under `tests/unit/`.
- Each workflow arrives with its authorized work package (AUTHORIZATIONS.md). Do not add speculative logic here.

Modules:
- `contracts/` (WP-0, spec 01 §7): the shared contracts WP-B and WP-C build on. State-domain types, the domain-event registry, the notification outbox states, the gate-interface shapes, and the shared audit action names. Each list mirrors the WP-0 migration and is checked against it by `tests/unit/contracts.test.ts`. A package adds its own event types and audit names in its own section, citing the spec.
- `uploads.ts`, `svg-sanitize.ts`, `image-safety.ts` (WP-C, spec 05 §5): upload rules mirrored from the database, content and magic-byte validation, the allowlist SVG sanitizer, and raster dimension limits with metadata stripping.
- `intake.ts` (WP-C, spec 05 §3): intake fields mirrored from the database.
- `publication.ts` (WP-C, spec 05 §7, 06 §2): the gate-result shape (fail-closed parsing) and the R1 approval wording. Gates are evaluated only in the database.
- `billing/` (WP-B, spec 04): integer-cents package pricing (`pricing.ts`) and the verbatim 04 §3.1 clause and OI-69 fixture label (`agreement.ts`). Both are checked against the WP-B migrations and spec 04 by `tests/unit/wpb-contracts.test.ts`. The deadline calendar lives only in the database (`private.add_business_days`, `private.end_of_local_day`), so it is computed in one place (02 §13).
