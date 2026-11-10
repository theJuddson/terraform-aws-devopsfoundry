# shellcheck shell=bash
# bin/put-secret (#27): the value goes through stdin, never argv; create or new version.

VALUE='sk_live_SuperSecret123'
ARN='arn:aws:secretsmanager:us-east-1:123456789012:secret:myapp/stripe-AbCdEf'

aws_with_secret() { # aws_with_secret <exists:true|false|deleted>
  stub aws "
case \"\$*\" in
  *describe-secret*) case '$1' in true) echo None ;; deleted) echo 2026-11-01T00:00:00Z ;; *) exit 254 ;; esac ;;
  *'file:///dev/stdin'*) cat > '$TMP/stdin'; echo '$ARN' ;;
esac
exit 0"
}

t_creates_a_new_secret_from_stdin_without_putting_the_value_in_argv() {
  aws_with_secret false
  local out; out=$(printf '%s\n' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --description "Stripe key" 2>&1) || fail "should succeed: $out"
  assert_called "create-secret --name myapp/stripe --region us-east-1 --description Stripe key --secret-string file:///dev/stdin"
  assert_not_called "$VALUE"
  [[ "$(cat "$TMP/stdin")" == "$VALUE" ]] || fail "the value must arrive on stdin, without the trailing newline: '$(cat "$TMP/stdin")'"
  assert_contains "$out" "$ARN"
  assert_not_contains "$out" "$VALUE"
}

t_adds_a_version_to_an_existing_secret() {
  aws_with_secret true
  printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe >/dev/null 2>&1 || fail "should succeed"
  assert_called "put-secret-value --secret-id myapp/stripe --region us-east-1 --secret-string file:///dev/stdin"
  assert_not_called "create-secret"
  assert_not_called "$VALUE"
}

t_env_flag_prints_the_tfvars_line() {
  aws_with_secret false
  local out; out=$(printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --env STRIPE_KEY 2>/dev/null)
  assert_contains "$out" "STRIPE_KEY = \"$ARN\""
}

t_refuses_an_empty_value() {
  aws_with_secret false
  printf '\n' | "$DF/bin/put-secret" myapp/stripe >/dev/null 2>&1 && fail "an empty value must be refused"
  assert_not_called "secretsmanager (create-secret|put-secret-value)"
}

t_refuses_a_secret_scheduled_for_deletion() {
  aws_with_secret deleted
  local out; out=$(printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe 2>&1) && fail "must refuse"
  assert_contains "$out" "restore-secret"
  assert_not_called "put-secret-value"
}

t_rejects_bad_names() {
  aws_with_secret false
  printf '%s' "$VALUE" | "$DF/bin/put-secret" 'my app' >/dev/null 2>&1 && fail "spaces are not allowed"
  printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/x --env 1BAD >/dev/null 2>&1 && fail "--env must be a variable name"
  assert_not_called "secretsmanager"
}
