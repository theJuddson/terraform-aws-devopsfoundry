# shellcheck shell=bash
# Namecheap hand-off (#35): bin/release-nameservers, the tfvars helpers, the
# deploy-app guard, and new-app running the release after provisioning.

ADDR='module.app.module.namecheap_ns[0].namecheap_domain_records.ns'
ADDR_RE='module\.app\.module\.namecheap_ns\[0\]\.namecheap_domain_records\.ns'
R53_NS='["ns-1.awsdns-01.org","ns-2.awsdns-02.net"]'

# An app root as new-app leaves it, with state and DNS answers chosen per test.
make_app() { # make_app <state-has-record:true|false> <public NS lines>
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP"
  local t
  for t in main.tf app.tfvars; do
    sed -e 's/__DOMAIN__/example.com/g' -e 's/__SUBDOMAIN__/api/g' -e 's/__EXISTING_ZONE__//g' \
        -e 's|__MODULE_SOURCE__|../../DevOpsFoundry/modules/full-stack|' \
        -e 's/__ENABLE_[A-Z]*__/false/g' "$DF/templates/full-stack/$t.tmpl" > "$APP/$t"
  done
  cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
  if [[ -n "${OLD_ADDRS:-}" ]]; then  # a state not applied since v1.2.5: unindexed addresses
    { echo 'module.app.module.route53_zone.aws_route53_zone.main'; $1 && echo "${ADDR/\[0\]/}"; } > "$TMP/state"
  else
    { echo 'module.app.module.route53_zone[0].aws_route53_zone.main'; $1 && echo "$ADDR"; } > "$TMP/state"
  fi
  printf '%s\n' "$2" > "$TMP/dig"
  stub terraform "
case \"\$*\" in
  *' state list'*) cat '$TMP/state' ;;
  *' state rm '*)  echo \"tfvars at state rm: \$(grep -c '^manage_nameservers = false' '$APP/app.tfvars')\" >> \"\$CALLS\"
                   [[ -f '$TMP/state-rm-fails' ]] && exit 1
                   grep -vxF \"\${@: -1}\" '$TMP/state' > '$TMP/state.new'; mv '$TMP/state.new' '$TMP/state' ;;
  *'output -json name_servers'*) echo '$R53_NS' ;;
  *'output -raw cpu_architecture'*) echo X86_64 ;;
  *'output -raw'*) echo 'https://api.example.com' ;;
esac
exit 0"
  stub dig "cat '$TMP/dig'"
}

# An app root scaffolded before v1.5.0: no manage_nameservers anywhere.
make_old_root() {
  grep -v 'manage_nameservers' "$APP/main.tf" > "$APP/main.tf.new" && mv "$APP/main.tf.new" "$APP/main.tf"
  awk '/^variable "manage_nameservers"/ { skip = 1 } !skip { print } skip && /^}/ { skip = 0 }' "$APP/variables.tf" > "$APP/v.new" && mv "$APP/v.new" "$APP/variables.tf"
}
tfvar() { bash -c "source $DF/lib/common.sh; df_tfvar $APP/app.tfvars $1"; }
app_arg() { awk '/^module "app"/,/^}/' "$APP/main.tf" | grep -E '^[[:space:]]*manage_nameservers[[:space:]]*=' | sed 's/.*= *//'; }

t_release_wires_an_old_app_root_before_touching_state() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  make_old_root
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "release should succeed"
  [[ "$(app_arg)" == "var.manage_nameservers" ]] || fail "main.tf must now pass manage_nameservers to the module"
  grep -q '^variable "manage_nameservers"' "$APP/variables.tf" || fail "variables.tf must declare it"
  [[ "$(awk '/^variable "manage_nameservers"/,/^}/' "$APP/variables.tf" | grep -c '^$')" == 0 ]] \
    || fail "the variable block must have no blank lines"$'\n'"$(cat "$APP/variables.tf")"
  assert_before " validate " "state rm"
  [[ "$(tfvar manage_nameservers)" == "false" ]] || fail "app.tfvars must end with manage_nameservers = false"
  [[ ! -e "$APP/main.tf.release-bak" ]] || fail "backups must be cleaned up"
}

t_release_refuses_a_module_too_old_for_the_setting() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  make_old_root
  cp "$APP/main.tf" "$TMP/main.before"; cp "$APP/variables.tf" "$TMP/vars.before"
  sed -i.bak 's/^exit 0$/[[ "$*" == *" validate"* ]] \&\& { echo "An argument named \\"manage_nameservers\\" is not expected here." >\&2; exit 1; }; exit 0/' "$STUBS/terraform"
  local out; out=$("$DF/bin/release-nameservers" --config "$APP" --yes 2>&1) && fail "must refuse"
  assert_contains "$out" "older than v1.2.5"
  assert_not_called "state rm"
  cmp -s "$APP/main.tf" "$TMP/main.before" && cmp -s "$APP/variables.tf" "$TMP/vars.before" || fail "main.tf and variables.tf must be restored"
  [[ -z "$(tfvar manage_nameservers)" ]] || fail "app.tfvars must be unchanged"
}

t_release_treats_a_literal_false_in_main_tf_as_released() {
  make_app false $'ns-1.awsdns-01.org.'
  make_old_root
  sed -i.bak 's|^  source *= .*|&\n  manage_nameservers = false|' "$APP/main.tf"
  [[ "$(app_arg)" == "false" ]] || fail "fixture: main.tf should set a literal false"
  local out; out=$("$DF/bin/release-nameservers" --config "$APP" --yes 2>&1) || fail "should succeed"
  assert_contains "$out" "Already released"
  [[ -z "$(tfvar manage_nameservers)" ]] || fail "app.tfvars must be left alone"
}

t_release_finishes_an_old_root_whose_record_was_removed_by_hand() {
  make_app false $'ns-1.awsdns-01.org.'
  make_old_root
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "should succeed"
  [[ "$(app_arg)" == "var.manage_nameservers" && "$(tfvar manage_nameservers)" == "false" ]] || fail "must wire the root and set false"
}

t_tfvar_reads_live_values_only() {
  printf '# manage_nameservers = true\ndomain_name = "example.com"  # apex\nflag=false\n' > "$TMP/x.tfvars"
  local lib="$DF/lib/common.sh"
  [[ "$(bash -c "source $lib; df_tfvar $TMP/x.tfvars domain_name")" == "example.com" ]] || fail "quoted value with comment"
  [[ "$(bash -c "source $lib; df_tfvar $TMP/x.tfvars flag")" == "false" ]] || fail "unspaced value"
  [[ -z "$(bash -c "source $lib; df_tfvar $TMP/x.tfvars manage_nameservers")" ]] || fail "a commented line must not count"
}

t_set_tfvar_uncomments_replaces_or_appends() {
  local lib="$DF/lib/common.sh"
  printf 'a = 1\n# manage_nameservers = true\nb = 2\n' > "$TMP/x.tfvars"
  bash -c "source $lib; df_set_tfvar $TMP/x.tfvars manage_nameservers false"
  [[ "$(cat "$TMP/x.tfvars")" == $'a = 1\nmanage_nameservers = false\nb = 2' ]] || fail "should uncomment in place: $(cat "$TMP/x.tfvars")"
  bash -c "source $lib; df_set_tfvar $TMP/x.tfvars manage_nameservers true"
  [[ "$(grep -c manage_nameservers "$TMP/x.tfvars")" == 1 && "$(bash -c "source $lib; df_tfvar $TMP/x.tfvars manage_nameservers")" == true ]] || fail "should replace, not duplicate"
  bash -c "source $lib; df_set_tfvar $TMP/x.tfvars c 3"
  [[ "$(tail -1 "$TMP/x.tfvars")" == "c = 3" ]] || fail "should append a new key"
}

t_release_removes_state_before_flipping_the_variable() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "release should succeed"
  assert_called "state rm $ADDR_RE"
  assert_called "tfvars at state rm: 0"
  [[ "$(bash -c "source $DF/lib/common.sh; df_tfvar $APP/app.tfvars manage_nameservers")" == "false" ]] || fail "manage_nameservers must end false"
}

t_release_refuses_while_namecheap_still_answers() {
  make_app true $'dns1.registrar-servers.com.\ndns2.registrar-servers.com.'
  "$DF/bin/release-nameservers" --config "$APP" --yes && fail "must refuse before delegation is live"
  assert_not_called "state rm"
  [[ -z "$(bash -c "source $DF/lib/common.sh; df_tfvar $APP/app.tfvars manage_nameservers")" ]] || fail "app.tfvars must be unchanged"
}

t_release_refuses_a_mix_of_old_and_new_nameservers() {
  make_app true $'ns-1.awsdns-01.org.\ndns1.registrar-servers.com.'
  "$DF/bin/release-nameservers" --config "$APP" --yes && fail "a half-propagated delegation must not be released"
  assert_not_called "state rm"
}

t_release_leaves_tfvars_alone_if_state_rm_fails() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  touch "$TMP/state-rm-fails"
  "$DF/bin/release-nameservers" --config "$APP" --yes && fail "must fail when state rm fails"
  [[ -z "$(bash -c "source $DF/lib/common.sh; df_tfvar $APP/app.tfvars manage_nameservers")" ]] || fail "app.tfvars must be unchanged"
}

t_release_is_idempotent() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  "$DF/bin/release-nameservers" --config "$APP" --yes
  : > "$CALLS"
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "a second run must succeed"
  assert_not_called "state rm"
  assert_not_called "^dig "
}

t_release_does_nothing_for_an_existing_zone_app() {
  make_app false $'ns-1.awsdns-01.org.'
  printf '' > "$TMP/state"
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "nothing to release is not an error"
  assert_not_called "state rm"
  [[ -z "$(bash -c "source $DF/lib/common.sh; df_tfvar $APP/app.tfvars manage_nameservers")" ]] || fail "app.tfvars must be unchanged"
}

t_deploy_refuses_a_hand_flipped_variable() {
  make_app true $'ns-1.awsdns-01.org.'
  echo 'manage_nameservers = false' >> "$APP/app.tfvars"
  : > "$APP/app.env"; touch "$TMP/app/Dockerfile"
  local out; out=$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1) && fail "deploy must stop"
  assert_contains "$out" "release-nameservers"
  assert_not_called "^docker build"
  assert_not_called " apply "
}

t_new_app_releases_after_provisioning() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  rm -rf "$TMP/app/.devopsfoundry"   # new-app scaffolds it
  NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 \
    "$DF/bin/new-app" example.com --config "$TMP/app/.devopsfoundry" --yes || fail "new-app should succeed"
  assert_before " apply .*phase-2" "state rm $ADDR_RE"
  [[ "$(bash -c "source $DF/lib/common.sh; df_tfvar $TMP/app/.devopsfoundry/app.tfvars manage_nameservers")" == "false" ]] || fail "new-app must leave manage_nameservers = false"
}

t_destroy_reverts_a_released_delegation() {
  make_app false $'ns-1.awsdns-01.org.'
  echo 'manage_nameservers = false' >> "$APP/app.tfvars"
  "$DF/bin/destroy-app" --config "$APP" --yes || fail "destroy should succeed"
  assert_called " apply .*-var manage_nameservers=true -target=module\.app\.module\.namecheap_ns"
  assert_called " destroy .*-var manage_nameservers=true"
  assert_before " apply .*-target=module\.app\.module\.namecheap_ns" " destroy "
}

t_destroy_keep_ns_leaves_a_released_delegation_alone() {
  make_app false $'ns-1.awsdns-01.org.'
  echo 'manage_nameservers = false' >> "$APP/app.tfvars"
  "$DF/bin/destroy-app" --config "$APP" --keep-ns --yes || fail "destroy should succeed"
  assert_not_called " apply "
  assert_not_called "manage_nameservers=true"
}

t_destroy_of_an_unreleased_app_is_unchanged() {
  make_app true $'ns-1.awsdns-01.org.'
  "$DF/bin/destroy-app" --config "$APP" --yes || fail "destroy should succeed"
  assert_not_called " apply "
  assert_called " destroy -input=false -auto-approve -var-file=app.tfvars$"
}

OLD_ADDR_RE='module\.app\.module\.namecheap_ns\.namecheap_domain_records\.ns'

t_release_handles_a_state_with_pre_v1_2_5_addresses() {
  OLD_ADDRS=1 make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "release should succeed"
  assert_called "state rm $OLD_ADDR_RE$"
  ! grep -q namecheap "$TMP/state" || fail "the record must be gone from state"
  [[ "$(tfvar manage_nameservers)" == "false" ]] || fail "manage_nameservers must end false"
}

t_deploy_guard_sees_a_pre_v1_2_5_address() {
  OLD_ADDRS=1 make_app true $'ns-1.awsdns-01.org.'
  echo 'manage_nameservers = false' >> "$APP/app.tfvars"
  : > "$APP/app.env"; touch "$TMP/app/Dockerfile"
  "$DF/bin/deploy-app" --config "$APP" --yes >/dev/null 2>&1 && fail "deploy must stop"
  assert_not_called "^docker build"
}

t_destroy_readopts_with_a_pre_v1_2_5_zone_address() {
  OLD_ADDRS=1 make_app false $'ns-1.awsdns-01.org.'
  echo 'manage_nameservers = false' >> "$APP/app.tfvars"
  "$DF/bin/destroy-app" --config "$APP" --yes || fail "destroy should succeed"
  assert_called " apply .*-var manage_nameservers=true -target=module\.app\.module\.namecheap_ns"
}

t_release_reports_other_validate_errors_as_they_are() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  make_old_root
  cp "$APP/main.tf" "$TMP/main.before"
  sed -i.bak 's/^exit 0$/[[ "$*" == *" validate"* ]] \&\& { echo "Error: Module not installed" >\&2; exit 1; }; exit 0/' "$STUBS/terraform"
  local out; out=$("$DF/bin/release-nameservers" --config "$APP" --yes 2>&1) && fail "must stop"
  assert_contains "$out" "Module not installed"
  assert_not_contains "$out" "older than v1.2.5"
  assert_not_called "state rm"
  cmp -s "$APP/main.tf" "$TMP/main.before" || fail "main.tf must be restored"
}

t_release_installs_modules_before_validating() {
  make_app true $'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'
  make_old_root
  "$DF/bin/release-nameservers" --config "$APP" --yes || fail "release should succeed"
  assert_before " get -no-color" " validate "
  assert_not_called " init"
}
