# shellcheck shell=bash
# df_roll_service forces a new ECS deployment and waits for it. With the
# circuit breaker on, a failing deployment is rolled back and the service
# settles on the previous one, so "stable" alone isn't success (#54).

# ecs <started id> <wait exit> <primary id> <primary rolloutState> [update exit]
ecs() {
  stub aws "case \"\$*\" in
  *'ecs update-service'*) [[ '${5:-0}' == 0 ]] || exit ${5:-0}; echo '$1' ;;
  *'ecs wait services-stable'*) exit $2 ;;
  *'ecs describe-services'*) printf '%s\t%s\n' '$3' '$4' ;;
esac; exit 0"
}
roll() { RC=0; OUT="$(bash -c 'source "$1/lib/common.sh"; df_roll_service demo-cluster demo-svc eu-west-1' _ "$DF" 2>&1)" || RC=$?; }

t_a_deployment_that_settles_succeeds() {
  ecs ecs-svc/new 0 ecs-svc/new COMPLETED
  roll
  [[ "$RC" == 0 ]] || fail "expected success, got $RC: $OUT"
  assert_called "^aws ecs update-service --cluster demo-cluster --service demo-svc --force-new-deployment --region eu-west-1"
  assert_before "ecs update-service" "ecs wait services-stable"
  assert_before "ecs wait services-stable" "ecs describe-services"
}

t_a_rolled_back_deployment_fails_even_though_the_service_is_stable() {
  ecs ecs-svc/new 0 ecs-svc/rollback COMPLETED
  roll
  [[ "$RC" == 2 ]] || fail "a rollback must fail the roll (2), got $RC"
  assert_contains "$OUT" "deployment ecs-svc/new failed; demo-svc is on ecs-svc/rollback"
}

t_a_failed_primary_deployment_fails() {
  ecs ecs-svc/new 0 ecs-svc/new FAILED
  roll
  [[ "$RC" == 2 ]] || fail "a FAILED rollout must fail the roll (2), got $RC"
}

t_a_deployment_that_never_settles_times_out() {
  ecs ecs-svc/new 255 ecs-svc/new IN_PROGRESS
  roll
  [[ "$RC" == 3 ]] || fail "no settle must be 3, got $RC"
}

t_a_rollback_found_after_a_timeout_is_still_a_rollback() {
  ecs ecs-svc/new 255 ecs-svc/rollback IN_PROGRESS
  roll
  [[ "$RC" == 2 ]] || fail "expected 2, got $RC"
}

t_update_service_failing_stops_before_waiting() {
  ecs "" 0 "" "" 254
  roll
  [[ "$RC" == 1 ]] || fail "expected 1, got $RC"
  assert_not_called "ecs wait"
}

# A failed rotation roll leaves the old credential in place and says so.
t_rotate_secret_reports_a_rollback() {
  APP="$TMP/app"; mkdir -p "$APP/.terraform/modules"; touch "$APP/.terraform/terraform.tfstate" "$APP/.terraform/modules/modules.json"
  cp "$DF/templates/full-stack/main.tf.tmpl" "$APP/main.tf"; cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
  printf 'aws_region = "eu-west-1"\nenable_cache = true\n' > "$APP/app.tfvars"
  stub terraform "case \"\$*\" in *'output -raw ecs_cluster_name'*) echo demo-cluster ;; *'output -raw ecs_service_name'*) echo demo-svc ;; *'show -json'*) echo '{\"resource_changes\":[]}' ;; esac; exit 0"
  ecs ecs-svc/new 0 ecs-svc/rollback COMPLETED
  OUT="$(DF_KEY_SETTLE_SECONDS=0 "$DF/bin/rotate-secret" --config "$APP" redis --yes 2>&1)" && fail "a rolled-back roll must fail the rotation"
  assert_contains "$OUT" "rolled demo-svc back"
  assert_contains "$OUT" "old Redis token still works"
  assert_not_called "strategy=SET"
}

# deploy-app says the image didn't go live when ECS rolls its deployment back.
t_deploy_app_reports_a_rollback_instead_of_success() {
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP/.terraform/modules"; touch "$APP/.terraform/terraform.tfstate" "$APP/.terraform/modules/modules.json"
  touch "$APP/main.tf" "$APP/app.env" "$TMP/app/Dockerfile"
  printf 'domain_name = "example.com"\n' > "$APP/app.tfvars"
  stub terraform 'case "$*" in *"output -raw cpu_architecture"*) echo X86_64 ;; *"output -raw ecr_repository_url"*) echo 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo ;; *"output -raw ecs_cluster_name"*) echo demo-cluster ;; *"output -raw ecs_service_name"*) echo demo-svc ;; *"output -raw log_group"*) echo /ecs/demo ;; *"output -raw"*) echo x ;; esac; exit 0'
  ecs ecs-svc/new 0 ecs-svc/rollback COMPLETED
  OUT="$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1)" && fail "a rolled-back deploy must fail"
  assert_contains "$OUT" "rolled the service back to the previous one"
  assert_contains "$OUT" "/ecs/demo"
  assert_not_contains "$OUT" "Service stable"
}
