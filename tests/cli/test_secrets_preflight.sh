# shellcheck shell=bash
# deploy-app's secret check (#28): every secret in app.tfvars must exist, not be
# scheduled for deletion, and have a current version, before anything is built.
# Only describe-secret is called; values are never read (#55).

ARN_OK='arn:aws:secretsmanager:us-east-1:123456789012:secret:demo/ok-AbCdEf'
ARN_MISSING='arn:aws:secretsmanager:us-east-1:123456789012:secret:demo/missing-AbCdEf'
ARN_NOVALUE='arn:aws:secretsmanager:us-east-1:123456789012:secret:demo/novalue-AbCdEf'
ARN_DELETED='arn:aws:secretsmanager:eu-west-1:123456789012:secret:demo/deleted-AbCdEf'

make_deployable() { # make_deployable <secrets block lines>
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP"; touch "$APP/main.tf" "$APP/app.env" "$TMP/app/Dockerfile"
  printf 'domain_name = "example.com"\n%s\n' "$1" > "$APP/app.tfvars"
  stub terraform 'case "$*" in *"output -raw cpu_architecture"*) echo X86_64 ;; *"output -raw ecr_repository_url"*) echo 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo ;; *"output -raw"*) echo x ;; esac; exit 0'
  stub aws "
case \"\$*\" in
  *'describe-secret --secret-id $ARN_MISSING'*) echo 'ResourceNotFoundException' >&2; exit 254 ;;
  *'describe-secret --secret-id $ARN_DELETED'*) printf '2026-11-01T00:00:00Z\t1\n' ;;
  *'describe-secret --secret-id $ARN_NOVALUE'*) printf 'None\t0\n' ;;
  *describe-secret*) printf 'None\t1\n' ;;
esac
exit 0"
}

t_all_secrets_present_lets_the_deploy_continue() {
  make_deployable "secrets = {
  API_KEY  = \"$ARN_OK\"
  PASSWORD = \"$ARN_OK:password::\"
}"
  "$DF/bin/deploy-app" --config "$APP" --yes >/dev/null 2>&1 || true
  assert_count "describe-secret" 1          # one secret, however many keys select from it
  assert_called "^docker build"
}

t_missing_empty_and_deleted_secrets_stop_the_deploy_before_building() {
  make_deployable "secrets = {
  A = \"$ARN_MISSING\"
  B = \"$ARN_NOVALUE\"
  C = \"$ARN_DELETED\"
  D = \"$ARN_OK\"
}"
  local out; out=$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1) && fail "deploy must stop"
  assert_contains "$out" "missing:   $ARN_MISSING"
  assert_contains "$out" "no value:  $ARN_NOVALUE"
  assert_contains "$out" "deleted:   $ARN_DELETED"
  assert_not_contains "$out" "$ARN_OK"
  assert_not_called "^docker"
  assert_not_called " apply "
}

t_each_secret_is_checked_in_its_own_region() {
  make_deployable "secrets = { C = \"$ARN_DELETED\" }"
  "$DF/bin/deploy-app" --config "$APP" --yes >/dev/null 2>&1 || true
  assert_called "describe-secret --secret-id $ARN_DELETED --region eu-west-1"
}

t_commented_out_secrets_are_ignored() {
  make_deployable "secrets = {
  # OLD = \"$ARN_MISSING\"
}"
  "$DF/bin/deploy-app" --config "$APP" --yes >/dev/null 2>&1 || true
  assert_not_called "secretsmanager"
  assert_called "^docker build"
}

t_secret_values_are_never_read() {
  make_deployable "secrets = { A = \"$ARN_OK\" }"
  "$DF/bin/deploy-app" --config "$APP" --yes >/dev/null 2>&1 || true
  assert_called "describe-secret --secret-id $ARN_OK --region us-east-1 --query .*AWSCURRENT"
  assert_not_called "get-secret-value"
  assert_not_called "batch-get-secret-value"
}
