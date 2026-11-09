# shellcheck shell=bash
# Test helpers for the bin/ scripts. Each test runs against a copy of bin/, lib/
# and templates/ in a temp directory, with stub commands (aws, terraform, docker,
# dig, curl, ...) first on PATH. Stubs record every call in $CALLS and answer
# from small scripts the test writes, so no real account, registrar or network
# is ever touched, and the repo's own .env and backend.tfvars are never read.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setup() {
  TMP="$(mktemp -d)"
  DF="$TMP/df"; STUBS="$TMP/stubs"; CALLS="$TMP/calls.log"
  mkdir -p "$DF" "$STUBS"
  cp -R "$REPO/bin" "$REPO/lib" "$REPO/templates" "$DF/"
  printf 'bucket = "test-state"\nregion = "us-east-1"\n' > "$DF/backend.tfvars"
  : > "$CALLS"
  export PATH="$STUBS:$PATH" CALLS DF_RETRY_DELAYS="0 0"
  # Stubs for everything the scripts may reach; tests override what they need.
  for cmd in aws terraform docker dig curl git; do stub "$cmd" 'exit 0'; done
}

teardown() { rm -rf "$TMP"; }

# stub <command> <bash body>: the body runs with the call's arguments as "$@".
stub() {
  local name="$1" body="$2"
  cat > "$STUBS/$name" <<STUB
#!/usr/bin/env bash
printf '%s\n' "$name \$*" >> "\$CALLS"
$body
STUB
  chmod +x "$STUBS/$name"
}

fail() { echo "    FAIL: $*" >&2; exit 1; }

assert_called()     { grep -qE -- "$1" "$CALLS" || fail "expected a call matching: $1"$'\n'"$(sed 's/^/      /' "$CALLS")"; }
assert_not_called() { ! grep -qE -- "$1" "$CALLS" || fail "unexpected call matching: $1"$'\n'"$(grep -E -- "$1" "$CALLS" | sed 's/^/      /')"; }
assert_count()      { local n; n=$(grep -cE -- "$1" "$CALLS" || true); [[ "$n" == "$2" ]] || fail "expected $2 calls matching $1, got $n"; }
assert_contains()   { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"$'\n'"      got: $1"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "expected output NOT to contain: $2"; }
# Order of first matching calls: assert_before A B
assert_before() {
  local a b
  a=$(grep -nE -- "$1" "$CALLS" | head -1 | cut -d: -f1); b=$(grep -nE -- "$2" "$CALLS" | head -1 | cut -d: -f1)
  [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]] || fail "expected a call matching $1 before one matching $2"
}
