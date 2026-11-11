# shellcheck shell=bash
# bin/check-readme-pins fails when the root README pins an older release than the
# newest in CHANGELOG.md, and --fix bumps the pins (#24).

# readme_and_changelog <newest changelog tag> <README pin tag>
readme_and_changelog() {
  printf '# Changelog\n\n## Unreleased\n\n- next\n\n## %s\n\n- this one\n\n## v1.0.0\n\n- first\n' "$1" > "$DF/CHANGELOG.md"
  cat > "$DF/README.md" <<EOF
source = "git::https://example.com//modules/object-store?ref=$2"
bin/new-app --config ../MyApp/.devopsfoundry --module-ref $2
check-compat proves upgrading from v1.2.0 plans no change.
x?ref=$2 y?ref=$2
EOF
}

check() { OUT="$("$DF/bin/check-readme-pins" "$@" 2>&1)"; }

t_stale_pins_fail_and_are_named() {
  readme_and_changelog v1.7.0 v1.6.0
  local before; before="$(cat "$DF/README.md")"
  check && fail "stale pins must fail"
  assert_contains "$OUT" "older release than v1.7.0"
  assert_contains "$OUT" "README.md:1:"
  assert_contains "$OUT" "README.md:2:"
  assert_not_contains "$OUT" "README.md:3:"
  assert_contains "$OUT" "--fix"
  [[ "$(cat "$DF/README.md")" == "$before" ]] || fail "the check must not change README.md"
}

t_current_pins_pass() {
  readme_and_changelog v1.7.0 v1.7.0
  check || fail "current pins must pass: $OUT"
  assert_contains "$OUT" "pins v1.7.0"
}

t_fix_bumps_every_pin_and_nothing_else() {
  readme_and_changelog v1.7.0 v1.6.0
  check --fix || fail "--fix must succeed: $OUT"
  assert_contains "$(cat "$DF/README.md")" "?ref=v1.7.0\""
  assert_contains "$(cat "$DF/README.md")" "--module-ref v1.7.0"
  assert_contains "$(cat "$DF/README.md")" "from v1.2.0 plans"
  assert_not_contains "$(cat "$DF/README.md")" "v1.6.0"
  check || fail "the check must pass after --fix: $OUT"
}

# v1.7.10 starts with v1.7.1 but is a different release.
t_a_pin_that_only_starts_with_the_newest_tag_is_stale() {
  readme_and_changelog v1.7.1 v1.7.10
  check && fail "v1.7.10 is not v1.7.1"
  assert_contains "$OUT" "README.md:1:"
}

t_a_readme_with_no_pins_fails() {
  readme_and_changelog v1.7.0 v1.7.0
  echo "# nothing pinned" > "$DF/README.md"
  check && fail "a README with no pins must fail, not pass by checking nothing"
  assert_contains "$OUT" "no ?ref= or --module-ref pins"
}

t_a_changelog_with_no_release_fails() {
  readme_and_changelog v1.7.0 v1.7.0
  printf '# Changelog\n\n## Unreleased\n' > "$DF/CHANGELOG.md"
  check && fail "a CHANGELOG with no release heading must fail"
  assert_contains "$OUT" "no '## vX.Y.Z' heading"
}

t_unknown_arguments_are_refused() {
  readme_and_changelog v1.7.0 v1.6.0
  check --fxi && fail "a typo must not run the check"
  assert_contains "$OUT" "usage:"
}
