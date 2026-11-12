# shellcheck shell=bash
# A static site's root can live in its own repo's .devopsfoundry/, passed as
# --config, like an app's. site.env paths are then relative to the repo, not to
# where the script runs, and the modules come from a pinned release.

# A site repo with its build in public/ and a provisioned root in .devopsfoundry/.
# make_site_repo [initialized]
make_site_repo() {
  REPO_DIR="$TMP/site-repo"; CFG="$REPO_DIR/.devopsfoundry"
  mkdir -p "$REPO_DIR/public" "$CFG"
  echo '<h1>hi</h1>' > "$REPO_DIR/public/index.html"
  touch "$CFG/main.tf"
  printf 'domain_name = "example.com"\nsite_name   = "example-com"\n' > "$CFG/terraform.tfvars"
  { echo 'BUILD_DIR="public"'; echo 'BUILD_CMD=""'; echo 'SRC_DIR=""'; echo 'BUILD_INPUTS=""'; } > "$CFG/site.env"
  if [[ "${1:-}" == initialized ]]; then
    mkdir -p "$CFG/.terraform/modules"
    touch "$CFG/.terraform/terraform.tfstate" "$CFG/.terraform/modules/modules.json"
  fi
  stub terraform "
case \"\$*\" in
  *'output -raw bucket'*) echo example-bucket ;;
  *'output -raw cloudfront_id'*) echo E123 ;;
  *'output -raw url'*) echo https://example.com ;;
esac
exit 0"
  stub aws 'case "$*" in *create-invalidation*) echo "{\"Invalidation\":{\"Id\":\"I1\"}}" ;; esac; exit 0'
}

t_deploy_config_reads_the_root_and_resolves_paths_against_the_repo() {
  make_site_repo initialized
  local out; out="$(cd "$TMP" && "$DF/bin/deploy" --config "$CFG" --yes 2>&1)" || fail "deploy must succeed: $out"
  assert_called "^terraform -chdir=$CFG output -raw bucket"
  assert_called "^aws s3 sync $REPO_DIR/public s3://example-bucket"
  assert_contains "$out" "Deploying $REPO_DIR/public"
  assert_not_called " init "
}

t_deploy_config_initializes_a_fresh_clone_first() {
  make_site_repo
  (cd "$TMP" && "$DF/bin/deploy" --config "$CFG" --yes >/dev/null 2>&1) || fail "deploy must succeed"
  assert_called "^terraform -chdir=$CFG init -input=false -backend-config=$DF/backend.tfvars$"
  assert_before " init " " output "
}

# SRC_DIR defaults to BUILD_DIR's parent, which here holds .devopsfoundry/ too:
# its .terraform/ changes on every init and must not count as site source.
t_the_deploy_config_is_not_site_source() {
  make_site_repo initialized
  echo 'x' > "$REPO_DIR/page.md"
  touch -t 202601010000 "$REPO_DIR/page.md"
  touch -t 202601020000 "$REPO_DIR/public/index.html"
  touch -t 202601030000 "$CFG/main.tf" "$CFG/.terraform/terraform.tfstate"
  local out; out="$(cd "$TMP" && "$DF/bin/deploy" --config "$CFG" --yes 2>&1)" || fail "deploy must succeed: $out"
  assert_contains "$out" "Build is newer than its source"
}

t_deploy_refuses_a_config_and_a_domain_together() {
  make_site_repo initialized
  local out; out="$("$DF/bin/deploy" example.com --config "$CFG" --yes 2>&1)" && fail "must refuse both"
  assert_contains "$out" "not both"
  assert_not_called "^aws s3"
}

t_deploy_refuses_a_config_that_is_not_a_site_root() {
  mkdir -p "$TMP/app/.devopsfoundry"; touch "$TMP/app/.devopsfoundry/main.tf"
  local out; out="$("$DF/bin/deploy" --config "$TMP/app/.devopsfoundry" --yes 2>&1)" && fail "must refuse an app root"
  assert_contains "$out" "Not a DevOpsFoundry site root"
}

new_site() { NAMECHEAP_API_KEY=x NAMECHEAP_CLIENT_IP=203.0.113.9 "$DF/bin/new-site" example.com "$@" 2>&1; }

t_new_site_config_scaffolds_a_pinned_committable_root() {
  local cfg="$TMP/site-repo/.devopsfoundry"
  new_site --config "$cfg" --module-ref v9.9.9 --build-dir public >/dev/null || true   # stops at the prompt
  [[ -f "$cfg/main.tf" ]] || fail "main.tf must be scaffolded into --config"
  grep -q 'source *= "git::ssh://git@github.com/theJuddson/terraform-aws-devopsfoundry//modules/static-site?ref=v9.9.9"' \
    "$cfg/main.tf" || fail "modules must be pinned to the release: $(grep source "$cfg/main.tf")"
  ! grep -q '\.\./\.\./modules\|__MODULE' "$cfg/main.tf" || fail "no relative or unrendered module sources"
  grep -q 'key = "devopsfoundry/example.com/terraform.tfstate"' "$cfg/backend.tf" || fail "state key must not depend on where the root lives"
  grep -q '^\.terraform/$' "$cfg/.gitignore" || fail ".gitignore must keep .terraform/ out of the repo"
  grep -q '^BUILD_DIR="public"$' "$cfg/site.env" || fail "build dir must be written as given"
  [[ ! -d "$DF/sites/example.com" ]] || fail "nothing may be written to sites/"
  assert_called "^terraform -chdir=$cfg init -input=false -backend-config=$DF/backend.tfvars$"
  assert_not_called " apply "
}

t_new_site_config_needs_a_module_release() {
  local out; out="$(new_site --config "$TMP/site-repo/.devopsfoundry")" && fail "must refuse without --module-ref"
  assert_contains "$out" "--module-ref"
  assert_not_called "^terraform"
}

t_legacy_new_site_still_uses_the_checkout_modules() {
  new_site >/dev/null || true
  local root="$DF/sites/example.com"
  grep -q 'source *= "\.\./\.\./modules/static-site"' "$root/main.tf" || fail "legacy root keeps ../../modules: $(grep source "$root/main.tf")"
  [[ ! -e "$root/.gitignore" && ! -e "$root/gitignore" ]] || fail "legacy root gets no gitignore"
}

t_destroy_site_config_purge_needs_the_typed_confirmation() {
  make_site_repo initialized
  local out; out="$("$DF/bin/destroy-site" --config "$CFG" --purge --yes 2>&1)" && fail "must refuse --purge --yes"
  assert_contains "$out" "confirm"
  assert_not_called " destroy "
  [[ -f "$CFG/main.tf" ]] || fail "the repo's config must survive"
}

t_destroy_site_config_runs_in_the_root() {
  make_site_repo initialized
  "$DF/bin/destroy-site" --config "$CFG" --yes >/dev/null 2>&1 || fail "destroy-site must succeed"
  assert_called "^terraform -chdir=$CFG destroy -input=false -auto-approve"
}
