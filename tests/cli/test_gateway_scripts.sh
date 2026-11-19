# shellcheck shell=bash
# With NAMECHEAP_GATEWAY set, new-app, new-site, destroy-app and destroy-site
# delegate and reset the domain through bin/namecheap (the gateway Lambda), never
# through Terraform's Namecheap provider, and need no Namecheap key or client IP.
# NAMECHEAP_DIRECT=1 keeps the provider path.

GW_NS_RE='"action":"set_nameservers","domain":"example.com","nameservers":\["ns-1.awsdns-01.org","ns-2.awsdns-02.net"\]'
GW_RESET_RE='"action":"reset_default","domain":"example.com"'
APP_ADDR='module.app.module.namecheap_ns[0].namecheap_domain_records.ns'
SITE_ADDR='module.namecheap_ns[0].namecheap_domain_records.ns'

# The gateway answers every invocation with {} unless $TMP/lambda-fails exists.
stub_gateway() {
  stub aws "
case \"\$*\" in
  *'lambda invoke'*)
    for last; do :; done
    if [[ -f '$TMP/lambda-fails' ]]; then
      echo '{\"errorMessage\":\"namecheap.domains.dns.setDefault failed: 2019166: Domain not found\"}' > \"\$last\"
      echo '{\"StatusCode\": 200, \"FunctionError\": \"Unhandled\"}'
    else
      echo '{}' > \"\$last\"; echo '{\"StatusCode\": 200}'
    fi ;;
esac
exit 0"
}

# Terraform: plans are saved, state comes from $TMP/state, the zone's nameservers are fixed.
stub_tf() {
  # The roots' paths, set here at the test's top level: the $(...) the scripts
  # run in can't set them for the test.
  APP="$TMP/app/.devopsfoundry"; SITE="$TMP/site/.devopsfoundry"
  : > "$TMP/state"
  stub terraform "
args=\"\$*\"
case \"\$args\" in
  *' plan '*) for a in \"\$@\"; do [[ \"\$a\" == -out=* ]] && echo \"\$args\" > \"\${a#-out=}\"; done ;;
  *' show -json '*) echo '{\"resource_changes\":[]}' ;;
  *' state list'*) cat '$TMP/state' ;;
  *' state rm '*) grep -vxF \"\${@: -1}\" '$TMP/state' > '$TMP/state.new'; mv '$TMP/state.new' '$TMP/state' ;;
  *'output -json name_servers'*) echo '[\"ns-1.awsdns-01.org\",\"ns-2.awsdns-02.net\"]' ;;
  *'output -raw'*) echo https://api.example.com ;;
esac
exit 0"
  stub dig "printf 'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.\n'"
}

new_app_gw() { NAMECHEAP_GATEWAY=devopsfoundry-namecheap "$DF/bin/new-app" example.com --config "$APP" "$@" 2>&1; }
new_site_gw() { NAMECHEAP_GATEWAY=devopsfoundry-namecheap "$DF/bin/new-site" example.com --config "$SITE" --module-ref v9.9.9 "$@" 2>&1; }
tfvar() { bash -c "source $DF/lib/common.sh; df_tfvar $1 $2"; }

# ── new-app ─────────────────────────────────────────────

t_new_app_delegates_through_the_gateway_with_no_namecheap_key() {
  stub_tf; stub_gateway
  local out; out=$(NAMECHEAP_API_KEY= NAMECHEAP_CLIENT_IP= new_app_gw --yes) || fail "new-app should succeed: $out"
  assert_called "plan .*-target=module\.app\.module\.route53_zone$"
  assert_not_called "-target=module\.app\.module\.namecheap_ns"
  assert_called "lambda invoke --function-name devopsfoundry-namecheap .*$GW_NS_RE"
  assert_before "apply .*phase-1b" "lambda invoke"
  assert_before "lambda invoke" "apply .*phase-2"
  assert_not_called "state rm"           # nothing to release: Terraform never had it
  assert_not_called "^curl"              # no client IP to detect
  [[ "$(tfvar "$APP/app.tfvars" manage_nameservers)" == false ]] || fail "the root must start with manage_nameservers = false"
  grep -q 'user_name = "unused"' "$APP/namecheap.tf" || fail "namecheap.tf must hold placeholders"
}

t_new_app_asks_before_delegating_without_yes() {
  stub_tf; stub_gateway
  local out; out=$(printf 'y\ny\nn\n' | new_app_gw) && fail "answering no to the delegation must stop"
  assert_contains "$out" "Point example.com at these nameservers at Namecheap?"
  assert_not_called "lambda invoke"
  assert_not_called "phase-2"
}

t_new_app_plan_only_says_what_the_gateway_would_do() {
  stub_tf; stub_gateway
  local out; out=$(new_app_gw --plan-only) || fail "plan-only should succeed: $out"
  assert_contains "$out" "bin/namecheap set example.com"
  assert_not_called "lambda invoke"
  assert_not_called " apply "
}

t_new_app_refuses_sandbox_with_the_gateway() {
  stub_tf; stub_gateway
  local out; out=$(new_app_gw --sandbox --yes) && fail "--sandbox must be refused"
  assert_contains "$out" "NAMECHEAP_DIRECT=1"
  assert_not_called "^terraform"
}

t_new_app_resume_refuses_a_root_whose_provider_holds_the_delegation() {
  stub_tf; stub_gateway
  new_app_gw --plan-only >/dev/null || fail "scaffold"
  printf '%s\n' 'module.app.module.route53_zone[0].aws_route53_zone.main' "$APP_ADDR" > "$TMP/state"
  local out; out=$(new_app_gw --resume --yes) && fail "must refuse"
  assert_contains "$out" "release-nameservers"
  assert_not_called "lambda invoke"
}

t_new_app_direct_opt_out_uses_the_provider() {
  stub_tf; stub_gateway
  NAMECHEAP_DIRECT=1 NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 new_app_gw --plan-only >/dev/null || fail "should plan"
  assert_called "plan .*-target=module\.app\.module\.namecheap_ns"
  grep -q 'provider "namecheap" {}' "$APP/namecheap.tf" || fail "the live provider must be configured"
}

# ── new-site ────────────────────────────────────────────

t_new_site_scaffolds_released_and_delegates_through_the_gateway() {
  stub_tf; stub_gateway
  local out; out=$(NAMECHEAP_API_KEY= NAMECHEAP_CLIENT_IP= new_site_gw --yes) || fail "new-site should succeed: $out"
  [[ -f "$SITE/namecheap.tf.released" && ! -e "$SITE/namecheap.tf" ]] || fail "the root must start released"
  assert_called "apply -input=false -auto-approve -target=module\.route53_zone$"
  assert_not_called "-target=module\.namecheap_ns"
  assert_called "lambda invoke .*$GW_NS_RE"
  assert_before "-target=module\.route53_zone" "lambda invoke"
  assert_not_called "state rm"
  assert_not_called "^curl"
}

t_new_site_stops_when_the_gateway_fails() {
  stub_tf; stub_gateway; touch "$TMP/lambda-fails"
  local out; out=$(new_site_gw --yes) && fail "a gateway failure must stop new-site"
  assert_contains "$out" "Could not delegate example.com through the gateway"
  assert_count " apply " 2   # 1a and 1b only
}

# ── destroy-site ────────────────────────────────────────

make_gw_site() { # make_gw_site released|managed
  stub_tf; stub_gateway
  SITE="$TMP/site/.devopsfoundry"; mkdir -p "$SITE/.terraform/modules"
  touch "$SITE/.terraform/terraform.tfstate" "$SITE/.terraform/modules/modules.json" "$SITE/main.tf"
  printf 'domain_name = "example.com"\nsite_name   = "example-com"\nexisting_zone_id = ""\n' > "$SITE/terraform.tfvars"
  echo 'BUILD_DIR="public"' > "$SITE/site.env"
  echo 'module.route53_zone[0].aws_route53_zone.main' > "$TMP/state"
  if [[ "$1" == managed ]]; then
    cp "$DF/templates/static/namecheap.tf.tmpl" "$SITE/namecheap.tf"; echo "$SITE_ADDR" >> "$TMP/state"
  else
    cp "$DF/templates/static/namecheap.tf.tmpl" "$SITE/namecheap.tf.released"
  fi
}
destroy_site_gw() { NAMECHEAP_GATEWAY=devopsfoundry-namecheap "$DF/bin/destroy-site" --config "$SITE" --yes "$@" 2>&1; }

t_destroy_site_resets_through_the_gateway_before_destroying() {
  make_gw_site released
  local out; out=$(destroy_site_gw) || fail "destroy should succeed: $out"
  assert_called "lambda invoke .*$GW_RESET_RE"
  assert_before "lambda invoke" " destroy "
  assert_not_called " apply "            # no re-adopting through the provider
  [[ ! -e "$SITE/namecheap.tf" ]] || fail "namecheap.tf must stay aside"
}

t_destroy_site_drops_a_provider_record_without_calling_namecheap() {
  make_gw_site managed
  destroy_site_gw >/dev/null || fail "destroy should succeed"
  assert_called "state rm module\.namecheap_ns"
  [[ -f "$SITE/namecheap.tf.released" && ! -e "$SITE/namecheap.tf" ]] || fail "namecheap.tf must be set aside"
  assert_before "state rm" "lambda invoke"
  assert_before "lambda invoke" " destroy "
}

t_destroy_site_keeps_everything_when_the_reset_fails() {
  make_gw_site released; touch "$TMP/lambda-fails"
  local out; out=$(destroy_site_gw) && fail "must stop"
  assert_contains "$out" "Domain not found"
  assert_contains "$out" "--keep-ns"
  assert_not_called " destroy "
}

t_destroy_site_keep_ns_never_calls_the_gateway() {
  make_gw_site released
  destroy_site_gw --keep-ns >/dev/null || fail "destroy should succeed"
  assert_not_called "lambda invoke"
  assert_called " destroy "
}

# ── destroy-app ─────────────────────────────────────────

make_gw_app() { # make_gw_app <record in state: true|false>
  stub_tf; stub_gateway
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP/.terraform/modules"
  touch "$APP/.terraform/terraform.tfstate"
  printf '{"Modules":[{"Key":"","Source":"","Dir":"."}]}\n' > "$APP/.terraform/modules/modules.json"
  local t
  for t in main.tf app.tfvars; do
    sed -e 's/__DOMAIN__/example.com/g' -e 's/__SUBDOMAIN__/api/g' -e 's/__EXISTING_ZONE__//g' \
        -e 's|__MODULE_SOURCE__|../../DevOpsFoundry/modules/full-stack|' \
        -e 's/__ENABLE_[A-Z]*__/false/g' "$DF/templates/full-stack/$t.tmpl" > "$APP/$t"
  done
  cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
  echo 'module.app.module.route53_zone[0].aws_route53_zone.main' > "$TMP/state"
  if $1; then
    cp "$DF/templates/full-stack/namecheap.tf.tmpl" "$APP/namecheap.tf"; echo "$APP_ADDR" >> "$TMP/state"
  else
    cp "$DF/templates/full-stack/namecheap-unused.tf.tmpl" "$APP/namecheap.tf"
    echo 'manage_nameservers = false' >> "$APP/app.tfvars"
  fi
}
destroy_app_gw() { NAMECHEAP_GATEWAY=devopsfoundry-namecheap "$DF/bin/destroy-app" --config "$APP" --yes "$@" 2>&1; }

t_destroy_app_resets_a_released_app_through_the_gateway() {
  make_gw_app false
  local out; out=$(destroy_app_gw) || fail "destroy should succeed: $out"
  assert_called "lambda invoke .*$GW_RESET_RE"
  assert_before "lambda invoke" " destroy "
  assert_not_called " apply "
  assert_not_called "manage_nameservers=true"
  assert_not_called "^curl"
}

t_destroy_app_drops_a_provider_record_first() {
  make_gw_app true
  destroy_app_gw >/dev/null || fail "destroy should succeed"
  assert_called "state rm module\.app\.module\.namecheap_ns\[0\]\.namecheap_domain_records\.ns"
  grep -q 'user_name = "unused"' "$APP/namecheap.tf" || fail "namecheap.tf must switch to placeholders"
  assert_before "state rm" "lambda invoke"
  assert_before "lambda invoke" " destroy "
}

t_destroy_app_keeps_everything_when_the_reset_fails() {
  make_gw_app false; touch "$TMP/lambda-fails"
  destroy_app_gw >/dev/null && fail "must stop"
  assert_not_called " destroy "
}

t_destroy_app_leaves_an_existing_zone_domain_alone() {
  make_gw_app false
  : > "$TMP/state"
  destroy_app_gw >/dev/null || fail "destroy should succeed"
  assert_not_called "lambda invoke"
  assert_called " destroy "
}

# ── preflight ───────────────────────────────────────────

t_preflight_with_the_gateway_skips_the_ip_check_and_fails_when_it_is_down() {
  stub_gateway; touch "$TMP/lambda-fails"
  printf 'bucket = "b"\n' > "$DF/backend.tfvars"
  local out; out=$(NAMECHEAP_GATEWAY=devopsfoundry-namecheap NAMECHEAP_API_KEY= "$DF/bin/preflight" 2>&1) && fail "a broken gateway must fail preflight"
  assert_contains "$out" "this machine's key and IP aren't used"
  assert_not_contains "$out" "NAMECHEAP_API_KEY not set"
  assert_not_contains "$out" "Public IPv4"
  assert_contains "$out" "Domain not found"
}
