# shellcheck shell=bash
# bin/deploy-app, bin/deploy and bin/rotate-secret open a Watchtower deployment window
# when WATCHTOWER_URL is set (lib/watchtower.sh): start after the confirmation, extend
# before a long wait, poll until the target settles, then done. Watchtower being down
# only warns, and the deploy token never reaches a command line.

TOKEN=wtd_SECRETTOKEN123
export DF_WT_POLL_SECONDS=0

# The curl stub answers the deployments API from these files, all optional:
#   start-code      start's status (default 201); 409 answers with a running_id
#   start-in        seconds from now to start's deadline (default 3600)
#   extend-in       seconds from now to extend's deadline (default 3600)
#   settled-in      seconds from now to the deadline /settled reports (default 3600)
#   unsettled       how many polls answer settled: false (default 0)
#   unreachable     every API call fails as curl does when it can't connect
# Other URLs (the health check) answer 200. stdin, where the token goes, is kept in curl-stdin.
wt_stub() {
  stub curl "
url='' method='' out='' w='' cfg=''
while [[ \$# -gt 0 ]]; do
  case \"\$1\" in
    -X) method=\"\$2\"; shift 2 ;;
    -o) out=\"\$2\"; shift 2 ;;
    -w) w=\"\$2\"; shift 2 ;;
    --config) cfg=\"\$2\"; shift 2 ;;
    -H|--data-binary|--max-time|--retry|--retry-delay) shift 2 ;;
    -*) shift ;;
    *) url=\"\$1\"; shift ;;
  esac
done
if [[ \"\$url\" != *'/api/v1/deployments'* ]]; then [[ -z \"\$w\" ]] || printf 200; exit 0; fi
[[ \"\$cfg\" != - ]] || cat >> '$TMP/curl-stdin'
if [[ -f '$TMP/unreachable' ]]; then echo 'curl: (7) Failed to connect to watch.example.com port 443' >&2; printf 000; exit 7; fi
val() { cat \"$TMP/\$1\" 2>/dev/null || echo \"\$2\"; }
ms() { echo \$(( (\$(date +%s) + \$1) * 1000 )); }
code=200
case \"\$method \$url\" in
  'POST '*/deployments)
    code=\$(val start-code 201)
    if [[ \$code == 409 ]]; then body='{\"error\":\"a deployment of demo is already running\",\"running_id\":\"dep0\"}'
    elif [[ \$code == 201 ]]; then body=\"{\\\"id\\\":\\\"dep1\\\",\\\"deadline_ms\\\":\$(ms \$(val start-in 3600)),\\\"estimate_seconds\\\":120,\\\"settle_window_seconds\\\":60}\"
    else body='{\"error\":\"database is locked\"}'; fi ;;
  'POST '*/extend) body=\"{\\\"deadline_ms\\\":\$(ms \$(val extend-in 3600))}\" ;;
  'GET '*/settled)
    n=\$(val polls 0); echo \$((n + 1)) > '$TMP/polls'
    s=false; (( n >= \$(val unsettled 0) )) && s=true
    body=\"{\\\"settled\\\":\$s,\\\"normal_for_seconds\\\":60,\\\"settle_window_seconds\\\":60,\\\"deadline_ms\\\":\$(ms \$(val settled-in 3600)),\\\"state\\\":\\\"running\\\",\\\"reasons\\\":[\\\"probe home is failing\\\"]}\" ;;
  'POST '*/done) body='{\"state\":\"done\"}' ;;
  *) code=404; body='{\"error\":\"not found\"}' ;;
esac
printf '%s' \"\$body\" > \"\$out\"
printf '%s' \"\$code\""
}

# aws: the token from SSM, an ECS service that rolls to <primary> (default the new
# deployment), and a CloudFront invalidation.
aws_stub() {
  stub aws "case \"\$*\" in
  *'ssm get-parameter'*) [[ -f '$TMP/no-token' ]] && { echo 'ParameterNotFound' >&2; exit 254; }; echo $TOKEN ;;
  *'ecs update-service'*) echo ecs-svc/new ;;
  *'ecs describe-services'*) printf '%s\t%s\n' '${1:-ecs-svc/new}' COMPLETED ;;
  *create-invalidation*) echo '{\"Invalidation\":{\"Id\":\"I1\"}}' ;;
esac; exit 0"
}

WT_ENV=$'WATCHTOWER_URL=https://watch.example.com\nWATCHTOWER_TOKEN_PARAMETER=/demo/watchtower/deploy-token'

# An app root; app.env holds <app.env lines>.
wt_app() {
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP/.terraform/modules"
  touch "$APP/.terraform/terraform.tfstate" "$APP/.terraform/modules/modules.json" "$APP/main.tf" "$TMP/app/Dockerfile"
  printf '%s\n' "${1:-}" > "$APP/app.env"
  printf 'name = "demo"\ndomain_name = "example.com"\n' > "$APP/app.tfvars"
  stub terraform 'case "$*" in *"output -raw cpu_architecture"*) echo X86_64 ;; *"output -raw ecr_repository_url"*) echo 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo ;; *"output -raw ecs_cluster_name"*) echo demo-cluster ;; *"output -raw ecs_service_name"*) echo demo-svc ;; *"output -raw service_url"*) echo https://example.com ;; *"output -raw"*) echo x ;; esac; exit 0'
  stub git 'case "$*" in *"rev-parse --short"*) echo abc1234 ;; esac; exit 0'
  wt_stub; aws_stub "${2:-}"
}
deploy_app() { OUT="$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1)"; }

START='^curl .*-X POST .*/api/v1/deployments$'
EXTEND='^curl .*-X POST .*/api/v1/deployments/dep1/extend$'
SETTLED='^curl .*-X GET .*/api/v1/deployments/dep1/settled$'
DONE='^curl .*-X POST .*/api/v1/deployments/dep1/done$'

no_token_in_argv() {
  assert_not_called "$TOKEN"
  grep -q "header = \"Authorization: Bearer $TOKEN\"" "$TMP/curl-stdin" || fail "curl must get the token on stdin"
}

t_without_watchtower_url_nothing_is_called() {
  wt_app ""
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_not_called 'api/v1/deployments'
  assert_not_called 'ssm get-parameter'
  assert_not_contains "$OUT" "Watchtower"
}

t_without_a_token_parameter_it_warns_and_calls_nothing() {
  wt_app "WATCHTOWER_URL=https://watch.example.com"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_contains "$OUT" "WATCHTOWER_TOKEN_PARAMETER is not"
  assert_not_called 'api/v1/deployments'
  assert_not_called 'ssm get-parameter'
}

t_deploy_app_starts_extends_waits_for_settled_then_closes_in_order() {
  wt_app "$WT_ENV"
  echo 60 > "$TMP/start-in"; echo 2 > "$TMP/unsettled"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_called '^aws ssm get-parameter --name /demo/watchtower/deploy-token --with-decryption --query Parameter.Value --output text'
  assert_called "$START"
  assert_called '"target":"demo".*"caller":"devopsfoundry/deploy-app"'
  assert_not_called 'estimate_seconds'
  assert_before "$START" '^docker build'
  assert_before "$START" "$EXTEND"
  assert_called '"seconds":600'
  assert_before "$EXTEND" '^aws ecs update-service'
  assert_before '^aws ecs describe-services' "$SETTLED"
  assert_count "$SETTLED" 3
  assert_before "$SETTLED" "$DONE"
  assert_count "$DONE" 1
  assert_called '"outcome":"succeeded","note":"git-abc1234 is live; settled after'
  assert_contains "$OUT" "window dep1 opened for demo, 1 min"
  assert_contains "$OUT" "extended by 10 min"
  assert_contains "$OUT" "demo settled after"
  no_token_in_argv
}

t_a_long_window_is_extended_only_near_its_deadline_while_waiting() {
  wt_app "$WT_ENV"
  echo 1 > "$TMP/unsettled"; echo 30 > "$TMP/settled-in"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_count "$EXTEND" 1
  assert_called '"seconds":120,"reason":"waiting for demo to settle"'
  assert_before "$SETTLED" "$EXTEND"
}

# A target that never settles is the unusual deployment Watchtower reports: the window is left
# open to run into its deadline, not closed as succeeded, and the exit trap doesn't close it either.
t_a_target_that_does_not_settle_is_left_open_for_watchtower_to_report() {
  wt_app "$WT_ENV"$'\nWATCHTOWER_SETTLE_TIMEOUT=0'
  echo 99 > "$TMP/unsettled"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_count "$SETTLED" 1
  assert_contains "$OUT" "not settled after 0 s: probe home is failing"
  assert_contains "$OUT" "leaving deployment"
  assert_count "$DONE" 0
}

t_a_die_closes_the_window_as_failed_with_the_error() {
  wt_app "$WT_ENV"
  stub docker 'case "$*" in build*) exit 1 ;; esac; exit 0'
  deploy_app && fail "a failed build must fail the deploy"
  assert_count "$DONE" 1
  assert_called '"outcome":"failed","note":"docker build failed"'
  assert_not_called "$SETTLED"
  no_token_in_argv
}

t_an_ecs_rollback_closes_the_window_as_rolled_back() {
  wt_app "$WT_ENV" ecs-svc/rollback
  deploy_app && fail "a rolled-back deploy must fail"
  assert_count "$DONE" 1
  assert_called '"outcome":"rolled-back"'
  assert_not_called '"outcome":"failed"'
  assert_contains "$OUT" "rolled the service back"
}

t_a_deployment_already_running_warns_and_the_deploy_goes_on_without_a_window() {
  wt_app "$WT_ENV"
  echo 409 > "$TMP/start-code"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_contains "$OUT" "already running (dep0)"
  assert_called '^aws ecs update-service'
  assert_not_called '/dep[0-9]/'
  assert_contains "$OUT" "Deployed"
}

t_an_error_from_watchtower_is_shown_without_the_token() {
  wt_app "$WT_ENV"
  echo 500 > "$TMP/start-code"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_contains "$OUT" "HTTP 500: database is locked"
  assert_not_contains "$OUT" "$TOKEN"
  assert_not_called '/dep1/'
}

t_an_unreachable_collector_warns_and_the_deploy_succeeds() {
  wt_app "$WT_ENV"
  touch "$TMP/unreachable"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_contains "$OUT" "could not reach https://watch.example.com"
  assert_contains "$OUT" "Deployed"
  assert_not_called '/dep1/'
  assert_not_contains "$OUT" "$TOKEN"
}

t_settings_in_dotenv_apply_and_app_env_overrides_them() {
  wt_app "WATCHTOWER_TARGET=demo-api"
  printf '%s\nWATCHTOWER_TARGET=ignored\nWATCHTOWER_SOURCES="web-1, web-2"\nWATCHTOWER_PROBES=home\n' "$WT_ENV" > "$DF/.env"
  deploy_app || fail "deploy-app must succeed: $OUT"
  assert_called '"target":"demo-api","scope":\{"sources":\["web-1","web-2"\],"groups":\[\],"probes":\["home"\]\}'
}

t_a_static_deploy_waits_for_the_invalidation_then_closes() {
  PROJ="$TMP/proj"; mkdir -p "$PROJ/dist" "$DF/sites/example.com"; echo hi > "$PROJ/dist/index.html"
  { echo 'BUILD_DIR="./dist"'; echo 'SRC_DIR="./dist"'; echo "$WT_ENV"; } > "$DF/sites/example.com/site.env"
  stub terraform "case \"\$*\" in *'output -raw bucket'*) echo example-bucket ;; *'output -raw cloudfront_id'*) echo E123 ;; *'output -raw url'*) echo https://example.com ;; esac; exit 0"
  wt_stub; aws_stub
  OUT="$(cd "$PROJ" && "$DF/bin/deploy" example.com --yes 2>&1)" || fail "deploy must succeed: $OUT"
  assert_called '"target":"example.com".*"caller":"devopsfoundry/deploy"'
  assert_before "$START" '^aws s3 '
  assert_called '^aws cloudfront wait invalidation-completed --distribution-id E123 --id I1$'
  assert_before 'create-invalidation' 'wait invalidation-completed'
  assert_before 'wait invalidation-completed' "$SETTLED"
  assert_before "$SETTLED" "$DONE"
  assert_called '"outcome":"succeeded"'
  no_token_in_argv
}

t_a_static_deploy_without_watchtower_does_not_wait_for_the_invalidation() {
  PROJ="$TMP/proj"; mkdir -p "$PROJ/dist" "$DF/sites/example.com"; echo hi > "$PROJ/dist/index.html"
  printf 'BUILD_DIR="./dist"\nSRC_DIR="./dist"\n' > "$DF/sites/example.com/site.env"
  stub terraform "case \"\$*\" in *'output -raw bucket'*) echo example-bucket ;; *'output -raw cloudfront_id'*) echo E123 ;; *'output -raw url'*) echo https://example.com ;; esac; exit 0"
  wt_stub; aws_stub
  OUT="$(cd "$PROJ" && "$DF/bin/deploy" example.com --yes 2>&1)" || fail "deploy must succeed: $OUT"
  assert_not_called 'wait invalidation-completed'
  assert_not_called 'api/v1/deployments'
}

t_rotate_secret_covers_publish_roll_and_retire_with_one_window() {
  APP="$TMP/app"; mkdir -p "$APP"
  cp "$DF/templates/full-stack/main.tf.tmpl" "$APP/main.tf"; cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
  printf 'name = "demo"\naws_region = "eu-west-1"\nenable_cache = true\n' > "$APP/app.tfvars"
  printf '%s\n' "$WT_ENV" > "$APP/app.env"
  stub terraform "case \"\$*\" in *'output -raw ecs_cluster_name'*) echo demo-cluster ;; *'output -raw ecs_service_name'*) echo demo-svc ;; *'show -json'*) echo '{\"resource_changes\":[]}' ;; esac; exit 0"
  wt_stub; aws_stub
  OUT="$(DF_KEY_SETTLE_SECONDS=0 "$DF/bin/rotate-secret" --config "$APP" redis --yes 2>&1)" || fail "rotate-secret must succeed: $OUT"
  assert_count "$START" 1
  assert_called '"target":"demo".*"caller":"devopsfoundry/rotate-secret"'
  assert_before "$START" 'strategy=ROTATE'
  assert_before 'strategy=ROTATE' '^aws ecs update-service'
  assert_before '^aws ecs update-service' 'strategy=SET'
  assert_before 'strategy=SET' "$DONE"
  assert_count "$DONE" 1
  assert_called '"outcome":"succeeded"'
  no_token_in_argv
}
