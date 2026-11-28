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
# The merged definition of private.project_financial_status. Several WP-C files (210, 215, 220, 225,
# 240) replace it with a fixture inside their own transaction; the check restores the merged
# definition first (still inside that rolled-back transaction), so the helper is always compared
# with the real per-project function over the data the file built. Substitution is reported.
pfs_def="$(psql "$DB_URL" -At -c "select pg_get_functiondef('private.project_financial_status(uuid)'::regprocedure)")"
pfs_md5="$(psql "$DB_URL" -At -c "select md5(prosrc) from pg_proc where oid = 'private.project_financial_status(uuid)'::regprocedure")"
check="reset role;
select 'OI131_SUBST', (select md5(prosrc) from pg_proc where oid = 'private.project_financial_status(uuid)'::regprocedure) <> '$pfs_md5';
$pfs_def;
$(cat <<'SQL'
create function pg_temp.oi131_pfs(p uuid, out failed boolean, out status jsonb) language plpgsql as $f$
begin
  status := to_jsonb(private.project_financial_status(p));
  failed := false;
exception when others then
  status := null;
  failed := true;
end;
$f$;
select 'OI131_EQ', count(*) as projects,
       count(*) filter (where e.failed is distinct from x.failed
                          or to_jsonb(e.status) is distinct from x.status) as mismatches,
       count(*) filter (where e.failed) as failed
  from private.financial_evaluation_for_projects((select array_agg(id) from public.projects)) e
  cross join lateral pg_temp.oi131_pfs(e.project_id) x;
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
  subst="$(echo "$out" | grep '^OI131_SUBST' | tail -1 | cut -d'|' -f2)"
  n="$(echo "$eq" | cut -d'|' -f2)"; m="$(echo "$eq" | cut -d'|' -f3)"; fl="$(echo "$eq" | cut -d'|' -f4)"
  echo "$name projects=${n:-?} mismatches=${m:-?} failed=${fl:-?} pfs_substituted=${subst:-?} kinds=${kinds}"
  total=$((total + 1))
  if [ -z "$eq" ] || [ "${m:-1}" != "0" ]; then bad=$((bad + 1)); fi
done
echo "OI131 suite equivalence: files=$total failing=$bad"
[ "$bad" -eq 0 ]
