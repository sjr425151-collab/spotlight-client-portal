#!/usr/bin/env bash
# T-MIG-02 (spec 03 §16): migrations already merged to the base branch are immutable.
# Fails if any file under supabase/migrations that exists on the base ref was modified,
# renamed, or deleted. New migration files are allowed.
# Usage: scripts/check-migrations.sh [base-ref]   (default: origin/main)
set -euo pipefail

base="${1:-origin/main}"
merge_base="$(git merge-base "$base" HEAD)"

violations="$(git diff --name-status "$merge_base" HEAD -- supabase/migrations | grep -v '^A' || true)"
if [[ -n "$violations" ]]; then
  echo "Merged migrations must never be edited, renamed, or deleted (T-MIG-02):"
  echo "$violations"
  exit 1
fi

# Every migration file name must be <14-digit timestamp>_<snake_case>.sql.
bad_names="$(git ls-files supabase/migrations | grep -vE '^supabase/migrations/[0-9]{14}_[a-z0-9_]+\.sql$' || true)"
if [[ -n "$bad_names" ]]; then
  echo "Migration files must be named <YYYYMMDDHHMMSS>_<snake_case>.sql:"
  echo "$bad_names"
  exit 1
fi

echo "Migration check passed: no merged migration was changed (base ${base})."
