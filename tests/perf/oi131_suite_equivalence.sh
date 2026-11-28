#!/usr/bin/env bash
# AUTH-026 (OI-131): suite-wide equivalence of private.financial_evaluation_for_projects.
# Test-only evidence runner (local stack only; not part of run-db-tests.sh). For every pgTAP file,
# it runs the file unchanged except that, just before the file's final ROLLBACK, it compares, for
# EVERY project in the database at that point (the states the suite reached), the helper's row with
# private.project_financial_status (to_jsonb byte for byte, plus failure parity), and records the
# anomaly kind x gate pairs present, so the coverage of the matrix is visible. Nothing persists.
#
# usage: tests/perf/oi131_suite_equivalence.sh   (after a fresh `supabase db reset`)
set -euo pipefail
DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
case "$DB_URL" in *@127.0.0.1:*|*@localhost:*) ;; *) echo "local only" >&2; exit 2 ;; esac
cd "$(dirname "$0")/../.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
check="$(cat <<'SQL'
reset role;
select 'OI131_EQ', count(*) as projects,
       count(*) filter (where e.failed is distinct from x.failed
                          or to_jsonb(e.status) is distinct from x.status) as mismatches
  from private.financial_evaluation_for_projects((select array_agg(id) from public.projects)) e
  cross join lateral (select false as failed, to_jsonb(private.project_financial_status(e.project_id)) as status) x;
select 'OI131_KINDS', coalesce(string_agg(distinct k, ',' order by k), '')
  from (select a.kind || ':' || g as k from public.projects p
          cross join lateral private.project_financial_anomalies(p.id) a cross join lateral unnest(a.gates) g) y;
SQL
)"
total=0; bad=0
for f in supabase/tests/*.test.sql; do
  name="$(basename "$f")"
  python3 - "$f" "$tmp/$name" "$check" <<'PY'
import sys
src, dst, check = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(src).read()
i = s.rstrip().rfind("rollback;")
if i < 0:
    raise SystemExit(f"no final rollback in {src}")
open(dst, "w").write(s[:i] + check + "\n" + s[i:])
PY
  out="$(psql "$DB_URL" -At -v ON_ERROR_STOP=0 -f "$tmp/$name" 2>/dev/null | grep -E '^OI131_' || true)"
  eq="$(echo "$out" | grep '^OI131_EQ' | tail -1)"
  kinds="$(echo "$out" | grep '^OI131_KINDS' | tail -1 | cut -d'|' -f2)"
  n="$(echo "$eq" | cut -d'|' -f2)"; m="$(echo "$eq" | cut -d'|' -f3)"
  echo "$name projects=${n:-?} mismatches=${m:-?} kinds=${kinds}"
  total=$((total + 1))
  if [ -z "$eq" ] || [ "${m:-1}" != "0" ]; then bad=$((bad + 1)); fi
done
echo "OI131 suite equivalence: files=$total failing=$bad"
[ "$bad" -eq 0 ]
