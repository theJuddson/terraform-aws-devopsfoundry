# shellcheck shell=bash
# bin/namecheap: calls go to the gateway Lambda with the right event, set and reset
# ask first, gateway failures stop the script, and put-key sends the key on stdin
# only. preflight reports the gateway when NAMECHEAP_GATEWAY is set.

KEY='nc-SuperSecretKey-123'

# lambda_answers <result json> [function error]: what the gateway returns.
lambda_answers() {
  printf '%s' "$1" > "$TMP/result.json"
  local meta='{"StatusCode": 200}'
  [[ -n "${2:-}" ]] && meta='{"StatusCode": 200, "FunctionError": "Unhandled"}'
  printf '%s' "$meta" > "$TMP/meta.json"
  stub aws "
case \"\$*\" in
  *'lambda invoke'*)
    for last; do :; done
    cp '$TMP/result.json' \"\$last\"; cat '$TMP/meta.json' ;;
  *describe-parameters*) cat '$TMP/exists' 2>/dev/null || echo 0 ;;
  *put-parameter*) cat > '$TMP/stdin' ;;
  *get-caller-identity*) echo 111111111111 ;;
esac
exit 0"
}

t_check_invokes_the_gateway() {
  lambda_answers '{"ok": true, "client_ip": "203.0.113.10"}'
  local out; out=$("$DF/bin/namecheap" check 2>&1) || fail "should succeed: $out"
  assert_called 'lambda invoke --function-name devopsfoundry-namecheap --region us-east-1 --cli-binary-format raw-in-base64-out --payload \{"action":"check"\} --output json'
  assert_contains "$out" "203.0.113.10"
}

t_get_sends_the_domain() {
  lambda_answers '{"domain": "example.com", "using_namecheap_dns": true, "nameservers": []}'
  NAMECHEAP_GATEWAY=other-fn NAMECHEAP_GATEWAY_REGION=us-west-2 "$DF/bin/namecheap" get example.com >/dev/null 2>&1 || fail "should succeed"
  assert_called 'lambda invoke --function-name other-fn --region us-west-2 .*"action":"get_nameservers","domain":"example.com"'
}

t_set_asks_first_and_stops_without_a_yes() {
  lambda_answers '{}'
  "$DF/bin/namecheap" set example.com ns1.example.net ns2.example.net </dev/null >/dev/null 2>&1 && fail "set must need a yes"
  assert_not_called "lambda invoke"
}

t_set_with_yes_sends_every_nameserver() {
  lambda_answers '{"domain": "example.com", "nameservers": ["ns1.example.net", "ns2.example.net"]}'
  "$DF/bin/namecheap" set example.com ns1.example.net ns2.example.net --yes >/dev/null 2>&1 || fail "should succeed"
  assert_called '"action":"set_nameservers","domain":"example.com","nameservers":\["ns1.example.net","ns2.example.net"\]'
}

t_set_needs_two_nameservers() {
  lambda_answers '{}'
  "$DF/bin/namecheap" set example.com ns1.example.net --yes >/dev/null 2>&1 && fail "one nameserver must be refused"
  assert_not_called "lambda invoke"
}

t_reset_with_yes_resets_to_default_dns() {
  lambda_answers '{"domain": "example.com", "using_namecheap_dns": true}'
  "$DF/bin/namecheap" reset example.com --yes >/dev/null 2>&1 || fail "should succeed"
  assert_called '"action":"reset_default","domain":"example.com"'
}

t_a_gateway_error_fails_with_its_message() {
  lambda_answers '{"errorMessage": "namecheap.users.getBalances failed: 1011150: Invalid request IP", "errorType": "GatewayError"}' error
  local out; out=$("$DF/bin/namecheap" check 2>&1) && fail "a function error must fail"
  assert_contains "$out" "Invalid request IP"
}

t_put_key_creates_a_securestring_from_stdin_only() {
  lambda_answers '{}'
  local out; out=$(NAMECHEAP_API_KEY="$KEY" "$DF/bin/namecheap" put-key 2>&1) || fail "should succeed: $out"
  assert_called 'ssm put-parameter --region us-east-1 --name /devopsfoundry/namecheap/api-key --type SecureString .*--tags Key=Project,Value=devopsfoundry --value file:///dev/stdin'
  assert_not_called "$KEY"
  assert_not_contains "$out" "$KEY"
  [[ "$(cat "$TMP/stdin")" == "$KEY" ]] || fail "the key must arrive on stdin"
}

t_put_key_overwrites_an_existing_parameter_from_a_pipe() {
  lambda_answers '{}'
  echo 1 > "$TMP/exists"
  printf '%s\n' "$KEY" | NAMECHEAP_API_KEY= "$DF/bin/namecheap" put-key - >/dev/null 2>&1 || fail "should succeed"
  assert_called 'ssm put-parameter .*--overwrite --value file:///dev/stdin'
  assert_not_called "$KEY"
  [[ "$(cat "$TMP/stdin")" == "$KEY" ]] || fail "the piped key must arrive on stdin without its newline"
}

t_put_key_refuses_an_empty_key() {
  lambda_answers '{}'
  NAMECHEAP_API_KEY= "$DF/bin/namecheap" put-key >/dev/null 2>&1 && fail "an empty key must be refused"
  assert_not_called "put-parameter"
}

t_preflight_reports_the_gateway() {
  lambda_answers '{"ok": true, "client_ip": "203.0.113.10"}'
  printf 'bucket = "b"\n' > "$DF/backend.tfvars"
  local out; out=$(NAMECHEAP_GATEWAY=devopsfoundry-namecheap NAMECHEAP_USER_NAME=u NAMECHEAP_API_USER=u NAMECHEAP_API_KEY=k \
    "$DF/bin/preflight" 2>&1) || true
  assert_contains "$out" "Namecheap gateway: Namecheap answers the gateway (devopsfoundry-namecheap) from 203.0.113.10"
}

t_preflight_skips_the_gateway_when_unset() {
  lambda_answers '{}'
  printf 'bucket = "b"\n' > "$DF/backend.tfvars"
  NAMECHEAP_USER_NAME=u NAMECHEAP_API_USER=u NAMECHEAP_API_KEY=k "$DF/bin/preflight" >/dev/null 2>&1 || true
  assert_not_called "lambda invoke"
}
