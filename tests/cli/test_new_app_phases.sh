# shellcheck shell=bash
# new-app plans each phase, shows it, asks (unless --yes) and applies exactly
# that plan; --plan-only applies nothing (#29).

ADDR_RE='module\.app\.module\.namecheap_ns\[0\]\.namecheap_domain_records\.ns'
PLAN_JSON='{"resource_changes":[
 {"address":"aws_x.new","change":{"actions":["create"]}},
 {"address":"aws_x.changed","change":{"actions":["update"]}},
 {"address":"aws_x.replaced","change":{"actions":["delete","create"]}},
 {"address":"aws_x.gone","change":{"actions":["delete"]}},
 {"address":"aws_x.same","change":{"actions":["no-op"]}}]}'

setup_new_app() {
  APP="$TMP/app/.devopsfoundry"
  cat > "$TMP/state" <<'S'
module.app.module.route53_zone[0].aws_route53_zone.main
module.app.module.namecheap_ns[0].namecheap_domain_records.ns
S
  printf '%s' "$PLAN_JSON" > "$TMP/plan.json"
  stub terraform "
args=\"\$*\"
case \"\$args\" in
  *' plan '*)
    if [[ -f '$TMP/cert-missing' && ( \"\$args\" == *route53_zone* || \"\$args\" == *desired_count* ) ]]; then
      echo 'Error: Invalid for_each argument' >&2; exit 1
    fi
    for a in \"\$@\"; do [[ \"\$a\" == -out=* ]] && echo \"\$args\" > \"\${a#-out=}\"; done ;;
  *' show -json '*) cat '$TMP/plan.json' ;;
  *' state list'*) cat '$TMP/state' ;;
  *' state rm '*) : ;;
  *'output -json name_servers'*) echo '[\"ns-1.awsdns-01.org\"]' ;;
  *'output -raw'*) echo https://api.example.com ;;
esac
exit 0"
  stub dig "echo ns-1.awsdns-01.org."
}

new_app() { NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/new-app" example.com --config "$APP" "$@" 2>&1; }

t_yes_applies_each_reviewed_plan() {
  setup_new_app
  new_app --yes >/dev/null || fail "new-app should succeed"
  assert_count " apply -input=false $APP/\.terraform/devopsfoundry-plans/phase-[^ ]*\.tfplan$" 3
  assert_not_called "-auto-approve"
  assert_before "plan .*-target=module\.app\.module\.acm_cert" "apply .*phase-1a"
  assert_before "apply .*phase-1b" "plan .*-var desired_count=0"
  assert_before "apply .*phase-2" "state rm $ADDR_RE"
  [[ -z "$(ls "$APP/.terraform/devopsfoundry-plans" 2>/dev/null)" ]] || fail "applied plan files must be removed (they contain secrets)"
}

t_shows_the_plan_summary() {
  setup_new_app
  local out; out=$(new_app --yes)
  assert_contains "$out" "Plan: 2 to add, 1 to change, 2 to destroy."
  assert_contains "$out" "-/+ aws_x.replaced"
  assert_contains "$out" "  + aws_x.new"
  assert_not_contains "$out" "aws_x.same"
}

t_answering_no_stops_before_applying() {
  setup_new_app
  local out; out=$(printf 'n\n' | new_app) || fail "stopping is not an error"
  assert_contains "$out" "Stopped before: Phase 1a"
  assert_not_called " apply "
}

t_answering_yes_applies_each_phase_after_asking() {
  setup_new_app
  local out; out=$(printf 'y\ny\ny\n' | new_app) || fail "new-app should succeed"
  assert_count " apply " 3
  [[ $(grep -c "Apply this?" <<<"$out") == 3 ]] || fail "each phase must be confirmed"
}

t_plan_only_on_a_new_app_plans_phase_1a_and_stops() {
  setup_new_app
  touch "$TMP/cert-missing"
  local out; out=$(new_app --plan-only) || fail "plan-only should succeed"
  assert_not_called " apply "
  assert_not_called "state rm"
  assert_contains "$out" "can't be planned yet"
  [[ -f "$APP/.terraform/devopsfoundry-plans/phase-1a-acm-certificate.tfplan" ]] || fail "the phase 1a plan must be kept for review"
}

t_plan_only_after_phase_1a_plans_the_rest() {
  setup_new_app
  touch "$TMP/cert-missing"; new_app --plan-only >/dev/null
  rm "$TMP/cert-missing"; : > "$CALLS"
  local out; out=$(new_app --resume --plan-only) || fail "plan-only should succeed"
  assert_called "plan .*-target=module\.app\.module\.route53_zone"
  assert_called "plan .*-var desired_count=0"
  assert_not_called " apply "
  assert_not_called "^dig "
  assert_contains "$out" "nothing applied"
}

t_a_namecheap_app_reads_namecheap_credentials_from_the_environment_until_released() {
  setup_new_app
  touch "$TMP/cert-missing"; new_app --plan-only >/dev/null   # scaffolds, delegates nothing
  [[ "$(grep -v '^#' "$APP/namecheap.tf")" == 'provider "namecheap" {}' ]] || fail "namecheap.tf must configure the provider from the environment"
  assert_not_contains "$(cat "$APP/main.tf")" 'provider "namecheap"'
  rm "$TMP/cert-missing"
  new_app --resume --yes >/dev/null || fail "new-app should succeed"
  assert_contains "$(cat "$APP/namecheap.tf")" 'api_key   = "unused"'
}

t_an_existing_zone_app_needs_no_namecheap_credentials() {
  setup_new_app
  stub aws 'echo /hostedzone/Z0EXISTING'
  env -u NAMECHEAP_API_KEY -u NAMECHEAP_CLIENT_IP "$DF/bin/new-app" example.com --config "$APP" --subdomain api --existing-zone example.com --yes >/dev/null 2>&1 \
    || fail "new-app --existing-zone should succeed with no NAMECHEAP_* set"
  assert_contains "$(cat "$APP/namecheap.tf")" 'api_key   = "unused"'
  assert_not_contains "$(cat "$APP/main.tf")" 'provider "namecheap"'
  assert_not_called "^curl "
}
