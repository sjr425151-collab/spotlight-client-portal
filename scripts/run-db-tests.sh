#!/usr/bin/env bash
# Runs supabase/tests/*.test.sql with psql inside the local Supabase database container
# and checks the TAP output. Equivalent to `supabase test db`, for machines that cannot
# pull the pg_prove image. CI uses `supabase test db`.
set -euo pipefail

container="${SUPABASE_DB_CONTAINER:-supabase_db_spotlight-client-portal}"
status=0
total=0
failed=0

for file in supabase/tests/*.test.sql; do
  output="$(docker exec -i "$container" psql -U postgres -d postgres -X -q -t -A -v ON_ERROR_STOP=1 < "$file" 2>&1)" || {
    echo "not ok - $file (psql error)"
    echo "$output" | sed 's/^/    /'
    failed=$((failed + 1))
    status=1
    continue
  }
  plan="$(echo "$output" | grep -E '^1\.\.[0-9]+$' | head -1 | cut -d. -f3)"
  passed="$(echo "$output" | grep -cE '^ok [0-9]+' || true)"
  notok="$(echo "$output" | grep -E '^not ok [0-9]+' || true)"
  total=$((total + ${plan:-0}))
  if [[ -n "$notok" || -z "$plan" || "$passed" -ne "$plan" ]]; then
    echo "not ok - $file (planned ${plan:-?}, passed $passed)"
    echo "$output" | grep -E '^(not ok|#)' | sed 's/^/    /'
    failed=$((failed + 1))
    status=1
  else
    echo "ok - $file ($passed/$plan)"
  fi
done

echo "Database tests: $total assertions planned; files failed: $failed"
exit "$status"
