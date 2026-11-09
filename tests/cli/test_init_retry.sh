# shellcheck shell=bash
# df_tf_init (#32): retries network failures, fails fast on config errors.

init_with() { # init_with <errors-before-success> <stderr text>
  printf '%s' "$1" > "$TMP/init-failures"
  stub terraform "
if [[ \"\$*\" == *' init '* ]]; then
  n=\$(cat '$TMP/init-failures')
  if [[ \$n -gt 0 ]]; then echo \$((n - 1)) > '$TMP/init-failures'; echo '$2' >&2; exit 1; fi
fi
exit 0"
}

run_init() { bash -c "source '$DF/lib/common.sh'; df_tf_init '$TMP' -input=false" 2>&1; }

t_succeeds_after_a_registry_504() {
  init_with 2 "Error while installing namecheap/namecheap v2.9.10: could not query provider registry: 504 Gateway Timeout"
  run_init >/dev/null || fail "init should succeed on the third attempt"
  assert_count "terraform -chdir=.* init" 3
}

t_gives_up_after_three_network_failures() {
  init_with 5 "the request failed after 2 attempts"
  local out; out=$(run_init) && fail "init should fail after three attempts"
  assert_count "terraform -chdir=.* init" 3
  assert_contains "$out" "request failed after"
}

t_does_not_retry_a_configuration_error() {
  init_with 5 'Error: Unsupported argument "bogus"'
  local out; out=$(run_init) && fail "init should fail"
  assert_count "terraform -chdir=.* init" 1
  assert_contains "$out" "Unsupported argument"
}
