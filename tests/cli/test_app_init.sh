# shellcheck shell=bash
# App scripts initialize Terraform when the checkout has none: .terraform/ is
# gitignored, so a fresh clone or a moved app repo has .devopsfoundry/ but no
# backend or modules (#45).

# fresh_app [initialized]: an app root, with or without a .terraform from init.
fresh_app() {
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP"
  printf 'domain_name = "example.com"\naws_region  = "us-east-1"\nenable_email = true\n' > "$APP/app.tfvars"
  touch "$APP/main.tf"
  printf 'DOCKERFILE="Dockerfile"\n' > "$APP/app.env"
  if [[ "${1:-}" == initialized ]]; then
    mkdir -p "$APP/.terraform/modules"
    touch "$APP/.terraform/terraform.tfstate" "$APP/.terraform/modules/modules.json"
  fi
}

t_a_fresh_clone_is_initialized_with_the_shared_backend_before_anything_else() {
  fresh_app
  "$DF/bin/email-status" --config "$APP" >/dev/null 2>&1 || true
  assert_called "init -input=false -backend-config=$DF/backend.tfvars$"
  assert_before " init " " output "
}

t_an_app_owned_backend_wins() {
  fresh_app
  printf 'bucket = "venture-state"\n' > "$APP/backend.tfvars"
  "$DF/bin/email-status" --config "$APP" >/dev/null 2>&1 || true
  assert_called "init -input=false -backend-config=$APP/backend.tfvars$"
  assert_not_called "backend-config=$DF/backend.tfvars"
}

t_an_initialized_app_is_not_initialized_again() {
  fresh_app initialized
  "$DF/bin/email-status" --config "$APP" >/dev/null 2>&1 || true
  assert_not_called " init "
}

t_a_half_initialized_app_is_initialized() {
  fresh_app
  mkdir -p "$APP/.terraform"; touch "$APP/.terraform/terraform.tfstate"   # backend, but no modules
  "$DF/bin/email-status" --config "$APP" >/dev/null 2>&1 || true
  assert_called " init -input=false"
}

t_a_failed_init_stops_the_deploy_before_it_touches_anything() {
  fresh_app
  stub terraform 'case "$*" in *" init "*) echo "Error: Failed to get existing workspaces: AccessDenied" >&2; exit 1 ;; esac; exit 0'
  OUT="$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1)" && fail "deploy-app must stop when init fails"
  assert_contains "$OUT" "terraform init failed in $APP"
  assert_not_called " apply "
  assert_not_called "^docker "
}

t_no_backend_config_at_all_is_said() {
  fresh_app
  rm -f "$DF/backend.tfvars"
  OUT="$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1)" && fail "no backend config must fail"
  assert_contains "$OUT" "No state backend config"
  assert_not_called " init "
}

t_every_app_script_initializes_a_fresh_clone() {
  local s
  for s in deploy-app destroy-app release-nameservers rotate-secret; do
    fresh_app; : > "$CALLS"
    case "$s" in
      rotate-secret) cp "$DF/templates/full-stack/main.tf.tmpl" "$APP/main.tf"; cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
                     "$DF/bin/$s" --config "$APP" smtp --yes >/dev/null 2>&1 </dev/null || true ;;
      *)             "$DF/bin/$s" --config "$APP" --yes >/dev/null 2>&1 </dev/null || true ;;
    esac
    grep -qE -- "^terraform -chdir=$APP init -input=false -backend-config=" "$CALLS" || fail "$s did not initialize a fresh clone"
  done
}

t_new_app_initializes_with_the_apps_own_backend() {
  APP="$TMP/app/.devopsfoundry"
  printf 'bucket = "venture-state"\nregion = "us-east-1"\n' > "$TMP/venture-backend.tfvars"
  stub terraform "case \"\$*\" in *'output -json name_servers'*) echo '[\"ns-1.awsdns-01.org\"]' ;; *'show -json'*) echo '{\"resource_changes\":[]}' ;; *'output -raw'*) echo x ;; esac; exit 0"
  stub dig "echo ns-1.awsdns-01.org."
  NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/new-app" example.com --config "$APP" --backend-config "$TMP/venture-backend.tfvars" --yes >/dev/null 2>&1 || true
  assert_called "init -input=false -backend-config=$APP/backend.tfvars$"
  assert_not_called "backend-config=$DF/backend.tfvars"
}

# installed_modules <key> <source>...: what .terraform/modules/modules.json says init installed.
installed_modules() {
  local json='{"Modules":[{"Key":"","Source":"","Dir":"."}'
  while [[ $# -gt 0 ]]; do json="$json,{\"Key\":\"$1\",\"Source\":\"$2\",\"Dir\":\".terraform/modules/$1\"}"; shift 2; done
  printf '%s]}\n' "$json" > "$APP/.terraform/modules/modules.json"
}
# A root shaped like the template: providers with their own `source`, a nested block, a comment.
root_main_tf() {
  cat > "$APP/main.tf" <<TF
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}
# module "old" { source = "./not-this" }
module "app" {
  source = "$1"
  tags   = { Name = "x" }
}
TF
}

t_a_moved_module_pin_is_initialized_again() {
  fresh_app initialized
  root_main_tf "git::ssh://git@github.com/o/r//modules/full-stack?ref=v1.17.0"
  installed_modules app "git::ssh://git@github.com/o/r//modules/full-stack?ref=v1.2.8" app.networking "../networking"
  OUT="$("$DF/bin/email-status" --config "$APP" 2>&1)" || true
  assert_called " init -input=false -backend-config=$DF/backend.tfvars$"
  assert_not_called "init.*-upgrade"
  assert_contains "$OUT" "a module source changed since the last init: app ("
  assert_contains "$OUT" "?ref=v1.2.8 -> "
}

t_matching_module_sources_are_not_initialized_again() {
  fresh_app initialized
  root_main_tf "git::ssh://git@github.com/o/r//modules/full-stack?ref=v1.17.0"
  installed_modules app "git::ssh://git@github.com/o/r//modules/full-stack?ref=v1.17.0" app.networking "../networking"
  "$DF/bin/email-status" --config "$APP" >/dev/null 2>&1 || true
  assert_not_called " init "
}

t_a_module_added_since_the_last_init_is_initialized() {
  fresh_app initialized
  root_main_tf "../modules/full-stack"
  printf 'module "files" {\n  source = "../modules/object-store"\n}\n' > "$APP/files.tf"
  installed_modules app "../modules/full-stack"
  "$DF/bin/email-status" --config "$APP" >/dev/null 2>&1 || true
  assert_called " init -input=false"
}
