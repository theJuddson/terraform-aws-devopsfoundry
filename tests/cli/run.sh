#!/usr/bin/env bash
# Runs every t_* function in tests/cli/test_*.sh, each in its own subshell with a
# fresh setup. Usage: tests/cli/run.sh [file-pattern]
set -uo pipefail
cd "$(dirname "$0")"
pass=0; failed=0
for f in test_*${1:-}*.sh; do
  for t in $(bash -c "source ./lib.sh; source ./$f; declare -F" | awk '$3 ~ /^t_/ {print $3}'); do
    if ( set -euo pipefail; source ./lib.sh; source "./$f"; setup; trap teardown EXIT; "$t" ) >/dev/null 2>"$f.$t.err"; then
      pass=$((pass + 1)); rm -f "$f.$t.err"
    else
      failed=$((failed + 1)); echo "FAIL $f: $t"; sed 's/^/  /' "$f.$t.err"; rm -f "$f.$t.err"
    fi
  done
done
echo "cli tests: $pass passed, $failed failed"
[[ $failed -eq 0 ]]
