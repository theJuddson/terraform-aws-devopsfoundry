# shellcheck shell=bash
# bin/rotate-secret rotates the Redis token or the SMTP key without a failed
# request: publish while the old credential still works, roll the service, then
# retire the old one; app.tfvars records progress so a re-run carries on (#22).
# preflight warns about secrets older than 90 days.

# rotation_app <app.tfvars lines>: an app root made from the current templates.
rotation_app() {
  APP="$TMP/app"; mkdir -p "$APP"
  cp "$DF/templates/full-stack/main.tf.tmpl" "$APP/main.tf"
  cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
  printf 'domain_name  = "example.com"\naws_region   = "eu-west-1"\nenable_cache = true\nenable_email = true\n%s\n' "$1" > "$APP/app.tfvars"
  # The plan stub notes which step it planned; show answers with that step's
  # resource changes ($TMP/show-publish.json / show-retire.json), none by default.
  stub terraform "
case \"\$*\" in
  *'output -raw ecs_cluster_name'*) echo demo-cluster ;;
  *'output -raw ecs_service_name'*) echo demo-svc ;;
  *' plan '*)
    case \"\$*\" in *'strategy=SET'*|*'standby_key=inactive'*) echo retire ;; *) echo publish ;; esac > '$TMP/phase'
    [[ -f '$TMP/plan-fails' ]] && exit 1 ;;
  *' apply '*) [[ -f '$TMP/apply-fails' ]] && exit 1 ;;
  *'show -json'*) f='$TMP/show-'\$(cat '$TMP/phase')'.json'; [[ -f \$f ]] && cat \$f || echo '{\"resource_changes\":[]}' ;;
esac
exit 0"
}

changes() { # changes <step> <address>...: the plan for that step updates these
  local step="$1" a json=""; shift
  for a in "$@"; do json="$json${json:+,}{\"address\":$(jq -Rn --arg a "$a" '$a'),\"change\":{\"actions\":[\"update\"]}}"; done
  echo "{\"resource_changes\":[$json]}" > "$TMP/show-$step.json"
}

rotate() { OUT="$(DF_KEY_SETTLE_SECONDS=0 "$DF/bin/rotate-secret" "$@" 2>&1)"; }
tfv() { df_tfvar_in "$APP/app.tfvars" "$1"; }
df_tfvar_in() { (source "$DF/lib/common.sh" >/dev/null 2>&1; df_tfvar "$1" "$2"); }

R='module.app.module.cache[0]'
E='module.app.module.email[0]'

# ── Redis ───────────────────────────────────────────────
t_a_first_redis_rotation_publishes_rolls_then_retires() {
  rotation_app ""
  changes publish "$R.random_password.auth_token" "$R.aws_elasticache_replication_group.main" "module.app.aws_secretsmanager_secret_version.redis_auth[0]"
  changes retire "$R.aws_elasticache_replication_group.main"
  rotate --config "$APP" redis --yes || fail "rotate-secret must succeed: $OUT"
  assert_called "^terraform -chdir=$APP plan .*-var-file=app.tfvars -var cache_auth_token_generation=1 -var cache_auth_token_update_strategy=ROTATE"
  assert_called "^aws ecs update-service --cluster demo-cluster --service demo-svc --force-new-deployment --region eu-west-1"
  assert_called "^aws ecs wait services-stable --cluster demo-cluster --services demo-svc --region eu-west-1"
  assert_called "^terraform -chdir=$APP plan .*-var cache_auth_token_generation=1 -var cache_auth_token_update_strategy=SET"
  assert_count "^terraform -chdir=$APP apply " 2
  assert_before "cache_auth_token_update_strategy=ROTATE" "^aws ecs update-service"
  assert_before "^aws ecs wait services-stable" "cache_auth_token_update_strategy=SET"
  [[ "$(tfv cache_auth_token_generation)" == 1 && "$(tfv cache_auth_token_update_strategy)" == SET ]] \
    || fail "app.tfvars must record generation 1, retired: $(cat "$APP/app.tfvars")"
}

t_the_next_redis_rotation_bumps_the_generation() {
  rotation_app $'cache_auth_token_generation = 4\ncache_auth_token_update_strategy = "SET"'
  rotate --config "$APP" redis --yes || fail "rotate-secret must succeed: $OUT"
  assert_called "cache_auth_token_generation=5 -var cache_auth_token_update_strategy=ROTATE"
  [[ "$(tfv cache_auth_token_generation)" == 5 ]] || fail "the generation must be 5"
  [[ "$(grep -c cache_auth_token_generation "$APP/app.tfvars")" == 1 ]] || fail "the tfvar must be replaced, not added twice"
}

t_a_failed_roll_keeps_the_old_token_and_a_rerun_carries_on() {
  rotation_app ""
  stub aws "case \"\$*\" in *'wait services-stable'*) exit 255 ;; esac; exit 0"
  rotate --config "$APP" redis --yes && fail "a service that never stabilizes must fail the rotation"
  assert_contains "$OUT" "old Redis token still works"
  assert_not_called "strategy=SET"
  [[ "$(tfv cache_auth_token_update_strategy)" == ROTATE ]] || fail "app.tfvars must record that generation 1 is published"

  : > "$CALLS"; stub aws 'exit 0'
  rotate --config "$APP" redis --yes || fail "the re-run must succeed: $OUT"
  assert_contains "$OUT" "already published"
  assert_not_called "strategy=ROTATE"
  assert_called "cache_auth_token_generation=1 -var cache_auth_token_update_strategy=SET"
  assert_called "^aws ecs update-service"
  [[ "$(tfv cache_auth_token_generation)" == 1 && "$(tfv cache_auth_token_update_strategy)" == SET ]] || fail "the re-run must finish generation 1, not start 2"
}

t_a_plan_that_changes_anything_else_is_refused() {
  rotation_app ""
  changes publish "$R.random_password.auth_token" "module.app.module.container_service.aws_ecs_service.main"
  local before; before="$(cat "$APP/app.tfvars")"
  rotate --config "$APP" redis --yes && fail "unrelated changes must stop the rotation"
  assert_contains "$OUT" "module.app.module.container_service.aws_ecs_service.main"
  assert_contains "$OUT" "Apply those first"
  assert_not_called "^terraform -chdir=$APP apply"
  assert_not_called "^aws ecs update-service"
  [[ "$(cat "$APP/app.tfvars")" == "$before" ]] || fail "a refused rotation must not change app.tfvars"
}

t_the_publish_plan_may_not_touch_other_app_resources() {
  rotation_app ""
  changes publish "$R.random_password.auth_token" "module.app.aws_secretsmanager_secret.redis_auth[0]"
  rotate --config "$APP" redis --yes && fail "only the secret's version may change, not the secret"
  assert_contains "$OUT" "module.app.aws_secretsmanager_secret.redis_auth[0]"
  assert_not_called "^terraform -chdir=$APP apply"
}

t_a_failed_apply_records_nothing_and_rolls_nothing() {
  rotation_app ""
  touch "$TMP/apply-fails"
  rotate --config "$APP" redis --yes && fail "a failed apply must fail the rotation"
  assert_contains "$OUT" "terraform apply failed"
  [[ -z "$(tfv cache_auth_token_update_strategy)" ]] || fail "a failed publish must not be recorded"
  assert_not_called "^aws ecs update-service"
}

t_the_retire_plan_may_only_touch_the_replication_group() {
  rotation_app $'cache_auth_token_generation = 2\ncache_auth_token_update_strategy = "ROTATE"'
  changes retire "$R.aws_elasticache_replication_group.main" "$R.random_password.auth_token"
  rotate --config "$APP" redis --yes && fail "a retire plan that makes a new token must be refused"
  assert_contains "$OUT" "$R.random_password.auth_token"
  assert_not_called "^terraform -chdir=$APP apply"
  [[ "$(tfv cache_auth_token_update_strategy)" == ROTATE ]] || fail "a refused retire must leave the rotation published"
}

t_a_failed_plan_changes_nothing() {
  rotation_app ""
  touch "$TMP/plan-fails"
  rotate --config "$APP" redis --yes && fail "a failed plan must fail"
  assert_contains "$OUT" "terraform plan failed"
  [[ -z "$(tfv cache_auth_token_update_strategy)" ]] || fail "app.tfvars must be untouched"
  assert_not_called "^aws ecs"
}

t_without_yes_nothing_is_applied_unconfirmed() {
  rotation_app ""
  rotate --config "$APP" redis && fail "with no answer the rotation must not go ahead"
  assert_not_called "^terraform -chdir=$APP apply"
  assert_not_called "^aws ecs update-service"
}

# ── SMTP ────────────────────────────────────────────────
t_a_first_smtp_rotation_adds_slot_b_then_retires_a() {
  rotation_app ""
  changes publish "$E.aws_iam_access_key.ses_smtp[\"b\"]" "$E.aws_secretsmanager_secret_version.smtp"
  changes retire "$E.aws_iam_access_key.ses_smtp[\"a\"]"
  rotate --config "$APP" smtp --yes || fail "rotate-secret must succeed: $OUT"
  assert_called "plan .*-var smtp_active_key=b -var smtp_standby_key=active$"
  assert_not_called "-replace"
  assert_called "plan .*-var smtp_active_key=b -var smtp_standby_key=inactive$"
  assert_before "smtp_standby_key=active" "^aws ecs update-service"
  assert_before "^aws ecs wait services-stable" "smtp_standby_key=inactive"
  [[ "$(tfv smtp_active_key)" == b && "$(tfv smtp_standby_key)" == inactive ]] \
    || fail "app.tfvars must record slot b active, a retired: $(cat "$APP/app.tfvars")"
}

t_the_next_smtp_rotation_replaces_the_retired_key() {
  rotation_app $'smtp_active_key = "b"\nsmtp_standby_key = "inactive"'
  rotate --config "$APP" smtp --yes || fail "rotate-secret must succeed: $OUT"
  assert_called "plan .*-var smtp_active_key=a -var smtp_standby_key=active -replace=module.app.module.email\[0\].aws_iam_access_key.ses_smtp\[\"a\"\]"
  assert_called "plan .*-var smtp_active_key=a -var smtp_standby_key=inactive$"
  [[ "$(tfv smtp_active_key)" == a && "$(tfv smtp_standby_key)" == inactive ]] || fail "slot a must end active"
}

t_a_published_smtp_key_is_rolled_and_retired_on_rerun() {
  rotation_app $'smtp_active_key = "b"\nsmtp_standby_key = "active"'
  rotate --config "$APP" smtp --yes || fail "rotate-secret must succeed: $OUT"
  assert_contains "$OUT" "already published"
  assert_not_called "smtp_standby_key=active"
  assert_called "plan .*-var smtp_active_key=b -var smtp_standby_key=inactive$"
}

t_the_smtp_publish_plan_may_not_touch_redis() {
  rotation_app ""
  changes publish "$E.aws_iam_access_key.ses_smtp[\"b\"]" "$R.aws_elasticache_replication_group.main"
  rotate --config "$APP" smtp --yes && fail "an SMTP rotation must not change Redis"
  assert_not_called "^terraform -chdir=$APP apply"
}

# ── Refusals ────────────────────────────────────────────
t_the_smtp_publish_plan_may_only_touch_the_keys_and_secret_version() {
  rotation_app ""
  changes publish "$E.aws_iam_access_key.ses_smtp[\"b\"]" "$E.aws_iam_user.ses_smtp"
  rotate --config "$APP" smtp --yes && fail "the SMTP user must not change in a rotation"
  assert_contains "$OUT" "$E.aws_iam_user.ses_smtp"
  assert_not_called "^terraform -chdir=$APP apply"
}

t_an_app_without_the_service_is_refused() {
  rotation_app ""
  sed -i.bak 's/^enable_cache = true/enable_cache = false/' "$APP/app.tfvars"
  rotate --config "$APP" redis --yes && fail "no cache, nothing to rotate"
  assert_contains "$OUT" "enable_cache is not true"
  assert_not_called "^terraform -chdir=$APP plan"
}

t_an_app_root_from_before_rotation_is_told_what_to_add() {
  rotation_app ""
  grep -v smtp_standby_key "$APP/main.tf" > "$APP/main.tf.new" && mv "$APP/main.tf.new" "$APP/main.tf"
  rotate --config "$APP" smtp --yes && fail "an old app root must be refused"
  assert_contains "$OUT" "predates secret rotation"
  assert_not_called "^terraform -chdir=$APP plan"
}

t_bad_recorded_state_is_refused() {
  rotation_app 'smtp_active_key = "c"'
  rotate --config "$APP" smtp --yes && fail "an unknown slot must be refused"
  assert_contains "$OUT" "must be a or b"
  rotation_app 'cache_auth_token_generation = "two"'
  rotate --config "$APP" redis --yes && fail "a non-numeric generation must be refused"
  assert_contains "$OUT" "not a whole number"
  assert_not_called "^terraform -chdir=$APP plan"
}

t_usage_errors() {
  rotation_app ""
  rotate --config "$APP" --yes && fail "no target must fail"
  assert_contains "$OUT" "usage:"
  rotate --config "$APP" postgres --yes && fail "an unknown target must fail"
  rotate --config "$APP" redis smtp --yes && fail "two targets must fail"
  rotate --config && fail "--config without a value must fail"
  assert_not_called "^terraform"
}

# ── preflight: secret age ───────────────────────────────
# secrets <list-secrets names JSON> <CreatedDate JSON value>
secrets() {
  printf '%s' "$1" > "$TMP/names.json"
  printf '{"Versions":[{"VersionStages":["AWSPREVIOUS"],"CreatedDate":"2019-01-01T00:00:00+00:00"},{"VersionStages":["AWSCURRENT"],"CreatedDate":%s}]}' "$2" > "$TMP/versions.json"
  stub aws "case \"\$*\" in *'list-secrets'*) cat '$TMP/names.json' ;; *'list-secret-version-ids'*) cat '$TMP/versions.json' ;; esac; exit 0"
}
age() { OUT="$(bash -c 'source "$1/lib/common.sh"; df_secret_age_report us-east-1' _ "$DF" 2>&1)"; }

t_an_old_secret_is_named_with_the_command_to_rotate_it() {
  secrets '["demo/redis/auth","demo/ses/smtp","demo/app/api-key"]' '"2020-01-01T00:00:00.123000+00:00"'
  age || fail "the age report must never fail: $OUT"
  assert_contains "$OUT" "demo/redis/auth is "
  assert_contains "$OUT" "bin/rotate-secret --config <demo's .devopsfoundry> redis"
  assert_contains "$OUT" "bin/rotate-secret --config <demo's .devopsfoundry> smtp"
  assert_not_contains "$OUT" "api-key"
  secrets '["shop/ses/smtp"]' '"2020-01-01T00:00:00+00:00"'
  age; assert_contains "$OUT" "shop/ses/smtp is "; assert_contains "$OUT" "<shop's .devopsfoundry> smtp"
  assert_not_contains "$OUT" "> redis"
  assert_called "list-secrets --region us-east-1 --filters Key=tag-key,Values=Project Key=tag-value,Values=devopsfoundry"
  assert_not_called "get-secret-value"
}

t_a_fresh_secret_passes() {
  secrets '["demo/redis/auth"]' "\"$(date -u +%Y-%m-%dT%H:%M:%S).000000+00:00\""
  age || fail "the age report must never fail: $OUT"
  assert_contains "$OUT" "rotated within 90 days"
  assert_not_contains "$OUT" "days old"
}

t_epoch_dates_and_the_limit_are_honoured() {
  secrets '["demo/ses/smtp"]' "$(( $(date +%s) - 40 * 86400 )).5"
  age; assert_contains "$OUT" "rotated within 90 days"
  OUT="$(DF_SECRET_MAX_AGE_DAYS=30 bash -c 'source "$1/lib/common.sh"; df_secret_age_report us-east-1' _ "$DF" 2>&1)"
  assert_contains "$OUT" "demo/ses/smtp is 40 days old"
}

t_no_app_secrets_says_nothing() {
  secrets '[]' '0'
  age || fail "must not fail"
  [[ -z "$OUT" ]] || fail "no secrets, no output: $OUT"
  stub aws 'exit 255'
  age || fail "an unreadable list must not fail preflight: $OUT"
}
