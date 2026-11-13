# shellcheck shell=bash
# new-site --existing-zone puts a site's records into a Route53 zone that already
# exists: the domain's own zone (apex + www) or a parent's (a subdomain site, no
# www). No zone is created and Namecheap is never called. Without the flag,
# new-site still won't create a second zone where one already serves the domain.

# zones <name:id:count[:private]>...: what `aws route53 list-hosted-zones` holds.
# Public DNS (dig) answers the zones' own nameservers unless dig_answers says otherwise.
zones() {
  local z name id count private json=""
  for z in "$@"; do
    IFS=: read -r name id count private <<<"$z"
    json="${json:+$json,}{\"Id\":\"/hostedzone/$id\",\"Name\":\"$name.\",\"ResourceRecordSetCount\":$count,\"Config\":{\"PrivateZone\":${private:-false}}}"
  done
  printf '{"HostedZones":[%s]}' "$json" > "$TMP/zones.json"
  stub aws "case \"\$*\" in
  *'route53 list-hosted-zones'*) cat '$TMP/zones.json' ;;
  *'route53 get-hosted-zone'*)
    args=\"\$*\"; id=\"\${args##*--id }\"; id=\"\${id%% *}\"
    name=\$(jq -r --arg id \"/hostedzone/\$id\" '.HostedZones[] | select(.Id == \$id) | .Name' '$TMP/zones.json')
    printf '{\"HostedZone\":{\"Id\":\"/hostedzone/%s\",\"Name\":\"%s\"},\"DelegationSet\":{\"NameServers\":[\"ns-1.awsdns-01.org\",\"ns-2.awsdns-02.com\"]}}' \"\$id\" \"\$name\" ;;
  *'sts get-caller-identity'*) echo 123456789012 ;;
esac; exit 0"
  dig_answers "ns-2.awsdns-02.com." "ns-1.awsdns-01.org."
  stub terraform "case \"\$*\" in *'output -raw url'*) echo https://example.com ;; *'output -raw'*) echo x ;; esac; exit 0"
}
# dig_answers <ns>...: the NS records public DNS gives for the zone's name.
dig_answers() { printf '%s\n' "$@" > "$TMP/dig.out"; stub dig "case \"\$*\" in *'NS '*) cat '$TMP/dig.out' ;; esac; exit 0"; }

CFG_DIR() { echo "$TMP/site-repo/.devopsfoundry"; }
# site <domain> <args...>: new-site with no Namecheap settings at all.
site() { local d="$1"; shift; env -u NAMECHEAP_API_KEY -u NAMECHEAP_CLIENT_IP "$DF/bin/new-site" "$d" --config "$(CFG_DIR)" --module-ref v9.9.9 "$@" 2>&1; }
tfvar() { awk -v k="$1" '$1 == k { v = $0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); print v }' "$(CFG_DIR)/terraform.tfvars"; }

t_named_zone_equal_to_the_domain_serves_apex_and_www_without_namecheap() {
  zones example.com:Z1:5
  local out; out="$(site example.com --existing-zone example.com --yes)" || fail "new-site must succeed: $out"
  [[ "$(tfvar existing_zone_id)" == Z1 ]] || fail "the zone must be recorded in terraform.tfvars"
  [[ "$(tfvar include_www)" == true ]] || fail "a site at the zone's apex serves www too"
  [[ ! -e "$(CFG_DIR)/namecheap.tf" ]] || fail "an existing-zone root has no Namecheap provider"
  assert_not_called "^curl"
  assert_not_called "route53_zone|namecheap_ns"
  assert_before "apply .*-target=module\.acm_cert" "apply -input=false -auto-approve$"
  assert_before "^dig .*NS example\.com" " apply "
  assert_contains "$out" "EXISTING zone example.com (Z1)"
}

t_named_parent_zone_makes_a_subdomain_site_without_www() {
  zones example.com:Z1:5
  local out; out="$(site blog.example.com --existing-zone example.com --yes)" || fail "new-site must succeed: $out"
  [[ "$(tfvar existing_zone_id)" == Z1 ]] || fail "the parent zone must be recorded"
  [[ "$(tfvar include_www)" == false ]] || fail "a subdomain site has no www"
  assert_called "^dig .*NS example\.com"
}

t_equals_form_and_zone_id_work() {
  zones example.com:Z1:5 example.com:Z2:3
  site example.com --existing-zone=Z2 --yes >/dev/null || fail "a zone id must pick one of two same-named zones"
  [[ "$(tfvar existing_zone_id)" == Z2 ]] || fail "the named id must be recorded"
}

t_refuses_a_zone_that_is_not_the_domain_or_a_parent() {
  zones other.com:Z9:2
  local out; out="$(site example.com --existing-zone other.com --yes)" && fail "must refuse"
  assert_contains "$out" "other.com is not example.com or a parent of it"
  assert_not_called "^terraform"
}

t_refuses_a_zone_the_account_does_not_have() {
  zones example.org:Z9:2
  local out; out="$(site example.com --existing-zone example.com --yes)" && fail "must refuse"
  assert_contains "$out" "No public Route53 zone named example.com"
  assert_not_called "^terraform"
}

t_refuses_two_zones_of_one_name_and_names_their_ids() {
  zones example.com:Z1:5 example.com:Z2:3
  local out; out="$(site example.com --existing-zone example.com --yes)" && fail "must refuse"
  assert_contains "$out" "Z1"; assert_contains "$out" "Z2"
  assert_contains "$out" "--existing-zone Z1"
  assert_not_called "^terraform"
}

t_a_private_zone_is_never_used() {
  zones example.com:Z1:5:true
  local out; out="$(site example.com --existing-zone example.com --yes)" && fail "must refuse a private zone"
  assert_contains "$out" "No public Route53 zone named example.com"
}

t_public_dns_not_answering_the_zone_stops_with_resume() {
  zones example.com:Z1:5
  dig_answers "dns1.registrar-servers.com." "dns2.registrar-servers.com."
  local out rc=0; out="$(site example.com --existing-zone example.com --yes)" || rc=$?
  [[ $rc == 75 ]] || fail "must stop with EX_TEMPFAIL (75), got $rc: $out"
  assert_contains "$out" "dns1.registrar-servers.com"
  assert_contains "$out" "ns-1.awsdns-01.org"
  assert_contains "$out" "--existing-zone example.com --resume --yes"
  assert_not_called " apply "
}

t_existing_zone_refuses_sandbox_and_email() {
  zones example.com:Z1:5
  local out
  out="$(site example.com --existing-zone example.com --sandbox --yes)" && fail "must refuse --sandbox"
  assert_contains "$out" "--sandbox"
  out="$(site example.com --existing-zone example.com --email --yes)" && fail "must refuse --email"
  assert_contains "$out" "--email"
  assert_not_called "^terraform"
}

t_bare_flag_before_the_domain_is_refused_as_ambiguous() {
  zones example.com:Z1:5
  local out; out="$(env -u NAMECHEAP_API_KEY "$DF/bin/new-site" --existing-zone example.com --config "$(CFG_DIR)" --module-ref v9.9.9 --yes 2>&1)" && fail "must refuse"
  assert_contains "$out" "--existing-zone=ZONE"
  assert_not_called "^terraform"
}

# ── Bare --existing-zone: choose from the zones that fit ──

t_bare_flag_with_one_zone_asks_and_uses_the_choice() {
  zones example.com:Z1:5 example.org:Z8:4
  local out; out="$(printf '1\ny\n' | site example.com --existing-zone)" || fail "new-site must succeed: $out"
  assert_contains "$out" "1) example.com  Z1  5 records"
  assert_not_contains "$out" "example.org"
  [[ "$(tfvar existing_zone_id)" == Z1 ]] || fail "the chosen zone must be recorded"
}

t_bare_flag_with_several_zones_lists_the_closest_first() {
  zones example.com:Z1:5 blog.example.com:Z3:2
  local out; out="$(printf '2\ny\n' | site blog.example.com --existing-zone)" || fail "new-site must succeed: $out"
  assert_contains "$out" "1) blog.example.com  Z3  2 records"
  assert_contains "$out" "2) example.com  Z1  5 records"
  [[ "$(tfvar existing_zone_id)" == Z1 ]] || fail "choice 2 must be recorded"
  [[ "$(tfvar include_www)" == false ]] || fail "a parent zone means no www"
}

t_bare_flag_with_no_fitting_zone_says_so_and_stops() {
  zones example.org:Z8:4
  local out; out="$(printf '1\n' | site example.com --existing-zone)" && fail "must stop"
  assert_contains "$out" "No public Route53 zone in this account is example.com or a parent of it"
  assert_not_called "^terraform"
  [[ ! -e "$(CFG_DIR)/main.tf" ]] || fail "nothing may be scaffolded"
}

t_bare_flag_refuses_an_invalid_choice() {
  zones example.com:Z1:5
  local out; out="$(printf '7\n' | site example.com --existing-zone)" && fail "must refuse"
  assert_contains "$out" "Not a choice: 7"
  assert_not_called "^terraform"
  [[ ! -e "$(CFG_DIR)/main.tf" ]] || fail "nothing may be scaffolded"
}

t_bare_flag_with_yes_never_guesses() {
  zones example.com:Z1:5
  local out; out="$(site example.com --existing-zone --yes)" && fail "must refuse to guess"
  assert_contains "$out" "--existing-zone example.com"
  assert_not_called "^terraform"
}

# ── No flag: never create a second zone ──

new_site_nc() { NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/new-site" example.com --config "$(CFG_DIR)" --module-ref v9.9.9 "$@" 2>&1; }

t_without_the_flag_an_existing_zone_is_offered_not_duplicated() {
  zones example.com:Z1:5
  local out; out="$(printf '1\ny\n' | new_site_nc)" || fail "new-site must succeed: $out"
  assert_contains "$out" "already"
  [[ "$(tfvar existing_zone_id)" == Z1 ]] || fail "the chosen zone must be used"
  [[ ! -e "$(CFG_DIR)/namecheap.tf" ]] || fail "no Namecheap delegation for an existing zone"
  assert_not_called "route53_zone|namecheap_ns"
}

t_without_the_flag_answering_no_stops() {
  zones example.com:Z1:5
  local out; out="$(printf 'n\n' | new_site_nc)" || true
  assert_contains "$out" "Stopped"
  assert_not_called "^terraform"
}

t_without_the_flag_yes_refuses_and_names_the_flag() {
  zones example.com:Z1:5
  local out; out="$(new_site_nc --yes)" && fail "must refuse"
  assert_contains "$out" "--existing-zone example.com"
  assert_not_called "^terraform"
}

t_without_the_flag_and_no_zone_creates_one_and_delegates() {
  zones example.org:Z8:4
  new_site_nc --yes >/dev/null || true
  [[ -e "$(CFG_DIR)/namecheap.tf" ]] || fail "a new zone is delegated at Namecheap (namecheap.tf)"
  [[ -z "$(tfvar existing_zone_id)" ]] || fail "no existing zone recorded"
  assert_called "apply .*-target=module\.route53_zone -target=module\.namecheap_ns"
}

# ── Resume, deploy, destroy ──

t_resume_uses_the_recorded_zone() {
  zones example.com:Z1:5
  site example.com --existing-zone example.com --yes >/dev/null || fail "first run must succeed"
  : > "$CALLS"
  site example.com --resume --yes >/dev/null || fail "resume must succeed without the flag"
  assert_not_called "route53_zone|namecheap_ns"
  assert_not_called "list-hosted-zones"
}

t_destroy_site_removes_only_the_site_s_records() {
  zones example.com:Z1:5
  site example.com --existing-zone example.com --yes >/dev/null || fail "new-site must succeed"
  mkdir -p "$(CFG_DIR)/.terraform/modules"; touch "$(CFG_DIR)/.terraform/terraform.tfstate" "$(CFG_DIR)/.terraform/modules/modules.json"
  : > "$CALLS"
  local out; out="$(env -u NAMECHEAP_CLIENT_IP "$DF/bin/destroy-site" --config "$(CFG_DIR)" --yes 2>&1)" || fail "destroy-site must succeed: $out"
  assert_called "destroy -input=false -auto-approve"
  assert_not_called "^curl"
  assert_not_called "state rm"
  assert_contains "$out" "only this site's records from zone Z1"
  out="$("$DF/bin/destroy-site" --config "$(CFG_DIR)" --keep-ns --yes 2>&1)" && fail "--keep-ns has nothing to keep"
  assert_contains "$out" "--keep-ns"
}

t_preflight_existing_zone_needs_no_namecheap() {
  zones example.com:Z1:5
  local out; out="$(env -u NAMECHEAP_API_KEY -u NAMECHEAP_USER_NAME -u NAMECHEAP_API_USER "$DF/bin/preflight" --existing-zone 2>&1)" || fail "preflight must pass: $out"
  assert_not_contains "$out" "NAMECHEAP"
  assert_not_called "^curl"
}

t_preflight_config_reads_the_site_s_backend() {
  zones example.com:Z1:5
  mkdir -p "$(CFG_DIR)"; printf 'bucket = "site-state"\n' > "$(CFG_DIR)/backend.tfvars"; rm -f "$DF/backend.tfvars"
  local out; out="$(env -u NAMECHEAP_API_KEY "$DF/bin/preflight" --existing-zone --config "$(CFG_DIR)" 2>&1)" || fail "preflight must pass: $out"
  assert_called "head-bucket --bucket site-state"
}
