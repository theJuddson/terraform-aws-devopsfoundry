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
  assert_called "create-secret --name myapp/stripe --region us-east-1 --description Stripe key --tags Key=Project,Value=devopsfoundry Key=App,Value=myapp --secret-string file:///dev/stdin"
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

# ── KMS key and tags (#56) ──────────────────────────────
KEY='arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555'

t_a_new_secret_can_use_a_customer_managed_key() {
  aws_with_secret false
  printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --kms-key "$KEY" >/dev/null 2>&1 || fail "should succeed"
  assert_called "create-secret --name myapp/stripe --region us-east-1 --kms-key-id $KEY --tags"
}

t_an_existing_secret_gets_the_key_before_the_new_value_and_is_tagged() {
  aws_with_secret true
  printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --kms-key alias/myapp >/dev/null 2>&1 || fail "should succeed"
  assert_called "update-secret --secret-id myapp/stripe --region us-east-1 --kms-key-id alias/myapp"
  assert_before "update-secret" "put-secret-value"
  assert_called "tag-resource --secret-id myapp/stripe --region us-east-1 --tags Key=Project,Value=devopsfoundry Key=App,Value=myapp"
  assert_not_called "$VALUE"
}

t_without_a_key_nothing_changes_the_key() {
  aws_with_secret true
  printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe >/dev/null 2>&1 || fail "should succeed"
  assert_not_called "update-secret"
  assert_not_called "kms-key-id"
}

t_the_app_tag_can_be_named_and_a_flat_name_gets_none() {
  aws_with_secret false
  printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --app shop >/dev/null 2>&1 || fail "should succeed"
  assert_called "Key=App,Value=shop"
  : > "$CALLS"
  printf '%s' "$VALUE" | "$DF/bin/put-secret" stripe-key >/dev/null 2>&1 || fail "should succeed"
  assert_called "--tags Key=Project,Value=devopsfoundry --secret-string"
  assert_not_called "Key=App"
}

t_a_bad_key_is_refused_before_reading_the_value() {
  aws_with_secret false
  local out; out=$(printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --kms-key "not a key" 2>&1) && fail "must refuse"
  assert_contains "$out" "--kms-key must be"
  assert_not_called "secretsmanager"
}

t_a_failed_key_change_stores_nothing() {
  stub aws "case \"\$*\" in *describe-secret*) echo None ;; *update-secret*) exit 254 ;; *'file:///dev/stdin'*) cat > '$TMP/stdin'; echo '$ARN' ;; esac; exit 0"
  local out; out=$(printf '%s' "$VALUE" | "$DF/bin/put-secret" myapp/stripe --kms-key alias/myapp 2>&1) && fail "must fail"
  assert_contains "$out" "nothing stored"
  assert_not_called "put-secret-value"
}
