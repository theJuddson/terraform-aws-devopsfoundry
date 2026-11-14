# shellcheck shell=bash
# A static site's Namecheap hand-off: bin/release-nameservers on a site root
# takes the delegation out of state, then sets namecheap.tf aside as
# namecheap.tf.released, so plans need no Namecheap credentials. new-site runs
# it once the site is live; destroy-site renames the file back to revert.

SITE_ADDR='module.namecheap_ns.namecheap_domain_records.ns'
SITE_ADDR_RE='module\.namecheap_ns\.namecheap_domain_records\.ns'
SITE_LIVE_NS=$'ns-1.awsdns-01.org.\nns-2.awsdns-02.net.'

# A provisioned, initialized site root, with state and DNS answers chosen per test.
make_site() { # make_site <state-has-record:true|false> <public NS lines>
  CFG="$TMP/site-repo/.devopsfoundry"; mkdir -p "$CFG/.terraform/modules"
  touch "$CFG/.terraform/terraform.tfstate" "$CFG/.terraform/modules/modules.json" "$CFG/main.tf"
  printf 'domain_name = "example.com"\nsite_name   = "example-com"\nexisting_zone_id = ""\n' > "$CFG/terraform.tfvars"
  echo 'BUILD_DIR="public"' > "$CFG/site.env"
  cp "$DF/templates/static/namecheap.tf.tmpl" "$CFG/namecheap.tf"
  { echo 'module.route53_zone[0].aws_route53_zone.main'; $1 && echo "$SITE_ADDR"; } > "$TMP/state"
  printf '%s\n' "$2" > "$TMP/dig"
  stub terraform "
case \"\$*\" in
  *' state list'*) cat '$TMP/state' ;;
  *' state rm '*)  echo \"namecheap.tf at state rm: \$(ls '$CFG' | grep -c '^namecheap.tf\$')\" >> \"\$CALLS\"
                   [[ -f '$TMP/state-rm-fails' ]] && exit 1
                   grep -vxF \"\${@: -1}\" '$TMP/state' > '$TMP/state.new'; mv '$TMP/state.new' '$TMP/state' ;;
  *' apply '*)     echo \"namecheap.tf at apply: \$(ls '$CFG' | grep -c '^namecheap.tf\$')\" >> \"\$CALLS\"
                   [[ -f '$TMP/apply-fails' ]] && exit 1 ;;
  *'output -json name_servers'*) echo '[\"ns-1.awsdns-01.org\",\"ns-2.awsdns-02.net\"]' ;;
  *'output -raw'*) echo x ;;
esac
exit 0"
  stub dig "cat '$TMP/dig'"
}
release() { "$DF/bin/release-nameservers" --config "$CFG" --yes 2>&1; }
set_aside() { [[ ! -e "$CFG/namecheap.tf" && -f "$CFG/namecheap.tf.released" ]]; }

t_site_release_removes_state_before_setting_namecheap_tf_aside() {
  make_site true "$SITE_LIVE_NS"
  release >/dev/null || fail "release should succeed"
  assert_called "state rm $SITE_ADDR_RE"
  assert_called "namecheap.tf at state rm: 1"
  set_aside || fail "namecheap.tf must become namecheap.tf.released"
}

t_site_release_refuses_while_namecheap_still_answers() {
  make_site true $'dns1.registrar-servers.com.\ndns2.registrar-servers.com.'
  release >/dev/null && fail "must refuse before delegation is live"
  assert_not_called "state rm"
  [[ -f "$CFG/namecheap.tf" ]] || fail "namecheap.tf must stay"
}

t_site_release_keeps_namecheap_tf_if_state_rm_fails() {
  make_site true "$SITE_LIVE_NS"
  touch "$TMP/state-rm-fails"
  release >/dev/null && fail "must fail when state rm fails"
  [[ -f "$CFG/namecheap.tf" ]] || fail "namecheap.tf must stay: without it the record in state would be destroyed"
}

t_site_release_is_idempotent() {
  make_site true "$SITE_LIVE_NS"
  release >/dev/null
  : > "$CALLS"
  local out; out="$(release)" || fail "a second run must succeed"
  assert_contains "$out" "Already released"
  assert_not_called "state rm"
  assert_not_called "^dig "
}

t_site_release_finishes_when_the_record_was_removed_by_hand() {
  make_site false "$SITE_LIVE_NS"
  release >/dev/null || fail "release should succeed"
  set_aside || fail "namecheap.tf must be set aside"
  assert_not_called "state rm"
}

t_site_release_does_nothing_for_an_existing_zone_site() {
  make_site false "$SITE_LIVE_NS"
  rm "$CFG/namecheap.tf"; printf '' > "$TMP/state"
  sed -i.bak 's/^existing_zone_id = ""/existing_zone_id = "Z1"/' "$CFG/terraform.tfvars"
  local out; out="$(release)" || fail "nothing to release is not an error"
  assert_contains "$out" "existing zone"
  [[ ! -e "$CFG/namecheap.tf.released" ]] || fail "nothing may be written"
}

t_destroy_site_puts_namecheap_tf_back_to_revert_a_released_delegation() {
  make_site true "$SITE_LIVE_NS"
  release >/dev/null; : > "$CALLS"
  NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/destroy-site" --config "$CFG" --yes >/dev/null 2>&1 || fail "destroy should succeed"
  assert_called "apply .*-target=module\.namecheap_ns"
  assert_called "namecheap.tf at apply: 1"
  assert_before "apply .*-target=module\.namecheap_ns" " destroy "
}

t_destroy_site_sets_namecheap_tf_aside_again_when_re_adopting_fails() {
  make_site true "$SITE_LIVE_NS"
  release >/dev/null; : > "$CALLS"
  touch "$TMP/apply-fails"
  local out; out="$(NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/destroy-site" --config "$CFG" --yes 2>&1)" && fail "destroy must stop"
  assert_contains "$out" "--keep-ns"
  assert_not_called " destroy "
  set_aside || fail "a failed re-adopt must leave namecheap.tf aside"
}

t_destroy_site_keep_ns_leaves_a_released_delegation_alone() {
  make_site true "$SITE_LIVE_NS"
  release >/dev/null; : > "$CALLS"
  NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/destroy-site" --config "$CFG" --keep-ns --yes >/dev/null 2>&1 || fail "destroy should succeed"
  assert_not_called " apply "
  assert_called " destroy "
  set_aside || fail "namecheap.tf must stay aside"
}

t_new_site_releases_once_the_site_is_live() {
  make_site true "$SITE_LIVE_NS"
  rm -rf "$CFG"   # new-site scaffolds it
  stub aws "case \"\$*\" in *'list-hosted-zones'*) echo '{\"HostedZones\":[]}' ;; esac; exit 0"
  NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/new-site" example.com --config "$CFG" \
    --module-ref v9.9.9 --build-dir public --yes >/dev/null 2>&1 || fail "new-site should succeed"
  assert_before "apply -input=false -auto-approve$" "state rm $SITE_ADDR_RE"
  set_aside || fail "new-site must leave namecheap.tf set aside"
}
