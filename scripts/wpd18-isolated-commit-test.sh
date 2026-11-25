#!/usr/bin/env bash
# WP-D18 isolated concurrent-commit verification (AUTH-007 Amendment 3, F1).
#
# Proves, on real committed state, that two concurrent sessions creating versions of the same
# package serialize: A commits version 2, B waits, then commits version 3. The commits happen
# only in a disposable database restored from a scoped, allow-listed dump of the local stack's
# package-scope objects, never in the shared test database, and the disposable database is
# always dropped.
#
# Rules (AUTHORIZATIONS, AUTH-007 Amendment 3):
# - the source database is only read (pg_dump -Fc -n private, ACCESS SHARE locks);
# - a fresh database wpd18_iso_<run>_<pid> from template0, refused if it already exists;
# - pg_restore --exit-on-error --single-transaction -L <allow-list>: zero tolerated errors;
#   a missing, duplicate or extra allow-list entry fails;
# - --no-privileges and --no-owner are forbidden (checked below); no privilege, ownership or
#   trigger change anywhere;
# - the disposable database is dropped on exit, error, interrupt and timeout, and its absence
#   is asserted; the source fingerprint and scope state must be identical before and after.
#
# Local stack and the existing local test credential only. Requires Docker and a running
# `supabase start`. Usage: ./scripts/wpd18-isolated-commit-test.sh
set -euo pipefail

if [[ -z "${WPD18_UNDER_TIMEOUT:-}" ]]; then
  # Bounded execution: the whole run is limited to 240 seconds. timeout sends TERM, which the
  # cleanup trap below handles.
  export WPD18_UNDER_TIMEOUT=1
  exec timeout --signal=TERM --kill-after=20 240 "$0" "$@"
fi

container="${SUPABASE_DB_CONTAINER:-supabase_db_spotlight-client-portal}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
allowlist="$here/supabase/tests-isolated/wpd18-restore-allowlist.txt"
parity_sql="$here/supabase/tests-isolated/wpd18_parity.sql"
race_sql="$here/supabase/tests-isolated/wpd18_commit_race.test.sql"
expected_entries=37
expected_fingerprint_lines=67
expected_plan=25

run_id="${GITHUB_RUN_ID:-local}"
db="wpd18_iso_${run_id}_$$"
if [[ ! "$db" =~ ^wpd18_iso_[A-Za-z0-9_]+$ ]]; then
  echo "FAIL: unexpected disposable database name: $db" >&2
  exit 1
fi
remote_dump="/tmp/${db}.dump"
remote_list="/tmp/${db}.list"
work="$(mktemp -d)"

dump_args=(pg_dump -U postgres -d postgres -Fc -n private -f "$remote_dump")
restore_args=(pg_restore -U postgres -d "$db" --exit-on-error --single-transaction -L "$remote_list" "$remote_dump")
for arg in "${dump_args[@]}" "${restore_args[@]}"; do
  if [[ "$arg" == "--no-privileges" || "$arg" == "--no-acl" || "$arg" == "-x" || "$arg" == "--no-owner" || "$arg" == "-O" ]]; then
    echo "FAIL: forbidden dump or restore option: $arg" >&2
    exit 1
  fi
done

step() { echo "== $*"; }
psql_c() { docker exec -i "$container" psql -U postgres -X -q -At -v ON_ERROR_STOP=1 "$@"; }

created=0
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ "$created" == 1 ]] || psql_c -d postgres -c "select 1 from pg_database where datname = '$db'" 2>/dev/null | grep -q 1; then
    psql_c -d postgres -c "drop database if exists \"$db\" with (force)" >/dev/null 2>&1 || true
  fi
  docker exec "$container" rm -f "$remote_dump" "$remote_list" >/dev/null 2>&1 || true
  rm -rf "$work"
  local left
  left="$(psql_c -d postgres -c "select count(*) from pg_database where datname = '$db'" 2>/dev/null || echo unknown)"
  if [[ "$left" != "0" ]]; then
    echo "FAIL: the disposable database $db is still present after cleanup ($left)" >&2
    status=1
  else
    echo "== cleanup: disposable database $db dropped (absence verified)"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

step "preflight"
docker exec "$container" true
if [[ "$(psql_c -d postgres -c "select count(*) from pg_database where datname = '$db'")" != "0" ]]; then
  echo "FAIL: database $db already exists; refusing to reuse it" >&2
  trap - EXIT
  rm -rf "$work"
  exit 1
fi
mapfile -t wanted < <(grep -v '^#' "$allowlist" | sed '/^[[:space:]]*$/d')
if [[ "${#wanted[@]}" -ne "$expected_entries" ]]; then
  echo "FAIL: the allow-list has ${#wanted[@]} entries, expected $expected_entries" >&2
  exit 1
fi
if [[ -n "$(printf '%s\n' "${wanted[@]}" | sort | uniq -d)" ]]; then
  echo "FAIL: the allow-list has duplicate entries" >&2
  exit 1
fi

step "source fingerprint and scope state (before)"
psql_c -d postgres -F '|' < "$parity_sql" > "$work/source.before"
fp_lines="$(grep -c '^fp|' "$work/source.before" || true)"
state_lines="$(grep -c '^state|' "$work/source.before" || true)"
if [[ "$fp_lines" -ne "$expected_fingerprint_lines" || "$state_lines" -lt 1 ]]; then
  echo "FAIL: source fingerprint has $fp_lines lines (expected $expected_fingerprint_lines) and $state_lines state lines" >&2
  exit 1
fi

step "scoped dump of the source (read only)"
docker exec "$container" "${dump_args[@]}"
docker exec "$container" pg_restore -l "$remote_dump" > "$work/full.list"
: > "$work/selected.list"
for entry in "${wanted[@]}"; do
  matches="$(sed -n 's/^[0-9]*; [0-9]* [0-9]* //p' "$work/full.list" | grep -cxF -- "$entry" || true)"
  if [[ "$matches" -ne 1 ]]; then
    echo "FAIL: allow-list entry matched $matches dump entries (expected exactly 1): $entry" >&2
    exit 1
  fi
done
while IFS= read -r line; do
  descriptor="$(sed 's/^[0-9]*; [0-9]* [0-9]* //' <<<"$line")"
  if printf '%s\n' "${wanted[@]}" | grep -qxF -- "$descriptor"; then
    printf '%s\n' "$line" >> "$work/selected.list"
  fi
done < <(grep -E '^[0-9]+; ' "$work/full.list")
selected="$(wc -l < "$work/selected.list")"
if [[ "$selected" -ne "$expected_entries" ]]; then
  echo "FAIL: $selected dump entries selected, expected exactly $expected_entries" >&2
  exit 1
fi
docker exec -i "$container" sh -c "cat > '$remote_list'" < "$work/selected.list"
echo "selected $selected of $(grep -cE '^[0-9]+; ' "$work/full.list") dump entries"

step "disposable database $db (template0) and zero-error restore"
psql_c -d postgres -c "create database \"$db\" template template0"
created=1
psql_c -d "$db" -c "create schema extensions; create extension pgcrypto with schema extensions; create extension dblink with schema extensions;"
docker exec "$container" "${restore_args[@]}"
echo "restore completed with no errors"

step "parity: fingerprint and initial scope state, source against copy"
psql_c -d "$db" -F '|' < "$parity_sql" > "$work/copy.before"
if ! cmp -s "$work/source.before" "$work/copy.before"; then
  echo "FAIL: the disposable copy differs from the source:" >&2
  diff "$work/source.before" "$work/copy.before" >&2 || true
  exit 1
fi
echo "identical: $fp_lines fingerprint lines and $state_lines state lines"

step "two-session concurrent commit (TAP)"
host="$(docker exec "$container" hostname -i | awk '{print $1}')"
docker exec -i -e PGPASSWORD=postgres "$container" \
  psql -h "$host" -U postgres -d "$db" -X -q -At -v ON_ERROR_STOP=1 < "$race_sql" > "$work/race.tap"
cat "$work/race.tap"
oks="$(grep -cE '^ok [0-9]+ - ' "$work/race.tap" || true)"
if ! grep -qx "1..$expected_plan" "$work/race.tap" \
  || grep -qE '^not ok' "$work/race.tap" \
  || grep -q '# SKIP' "$work/race.tap" \
  || [[ "$oks" -ne "$expected_plan" ]]; then
  echo "FAIL: expected plan 1..$expected_plan with $expected_plan ok lines, no 'not ok' and no '# SKIP' (got $oks ok)" >&2
  exit 1
fi

step "source unchanged (after)"
psql_c -d postgres -F '|' < "$parity_sql" > "$work/source.after"
if ! cmp -s "$work/source.before" "$work/source.after"; then
  echo "FAIL: the source database changed during the run:" >&2
  diff "$work/source.before" "$work/source.after" >&2 || true
  exit 1
fi
echo "source fingerprint and scope state identical before and after"
echo "WP-D18 isolated concurrent-commit verification: PASS ($oks/$expected_plan)"
