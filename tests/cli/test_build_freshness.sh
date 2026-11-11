# shellcheck shell=bash
# bin/deploy refuses to upload a static build older than its source, and
# deploy-app tags an image built from uncommitted changes as such (#43).

OLD=202601010000; MID=202601020000; NEW=202601030000   # touch -t stamps

# A project with src/ and its build in dist/, and a provisioned site for it.
# make_site [extra site.env lines]
make_site() {
  PROJ="$TMP/proj"; mkdir -p "$PROJ/src" "$PROJ/dist"
  echo 'console.log(1)' > "$PROJ/src/app.js"
  echo '<h1>hi</h1>' > "$PROJ/dist/index.html"
  mkdir -p "$DF/sites/example.com"
  { echo 'BUILD_DIR="./dist"'; echo 'BUILD_CMD=""'; echo 'SRC_DIR=""'; echo 'BUILD_INPUTS=""'; printf '%s\n' "$@"; } \
    > "$DF/sites/example.com/site.env"
  stub terraform "
case \"\$*\" in
  *'output -raw bucket'*) echo example-bucket ;;
  *'output -raw cloudfront_id'*) echo E123 ;;
  *'output -raw url'*) echo https://example.com ;;
esac
exit 0"
  stub aws 'case "$*" in *create-invalidation*) echo "{\"Invalidation\":{\"Id\":\"I1\"}}" ;; esac; exit 0'
}

# deploy [args...]: runs bin/deploy from the project directory; output in $OUT.
deploy() { OUT="$(cd "$PROJ" && "$DF/bin/deploy" example.com --yes "$@" 2>&1)"; }

t_a_build_older_than_its_source_is_refused_before_upload() {
  make_site
  touch -t "$OLD" "$PROJ/dist/index.html"; touch -t "$NEW" "$PROJ/src/app.js"
  deploy && fail "deploy must fail on a stale build"
  assert_contains "$OUT" "src/app.js changed after the last build"
  assert_contains "$OUT" "--allow-stale"
  assert_not_called "^aws s3"
  assert_not_called "create-invalidation"
}

t_a_build_newer_than_its_source_deploys_and_says_so() {
  make_site
  touch -t "$OLD" "$PROJ/src/app.js"; touch -t "$NEW" "$PROJ/dist/index.html"
  deploy || fail "deploy must succeed: $OUT"
  assert_contains "$OUT" "Build is newer than its source"
  assert_called "^aws s3 sync "
}

# Builds copy static assets with their original times; the build's own time is
# its newest file, so an old copied asset must not make a fresh build stale.
t_old_copied_assets_do_not_make_a_fresh_build_stale() {
  make_site
  echo 'png' > "$PROJ/dist/logo.png"
  touch -t "$OLD" "$PROJ/dist/logo.png"; touch -t "$MID" "$PROJ/src/app.js"; touch -t "$NEW" "$PROJ/dist/index.html"
  deploy || fail "deploy must succeed: $OUT"
  assert_called "^aws s3 sync "
}

t_allow_stale_deploys_a_stale_build() {
  make_site
  touch -t "$OLD" "$PROJ/dist/index.html"; touch -t "$NEW" "$PROJ/src/app.js"
  deploy --allow-stale || fail "--allow-stale must deploy: $OUT"
  assert_contains "$OUT" "--allow-stale"
  assert_called "^aws s3 sync "
}

t_sites_with_a_build_cmd_build_instead_of_checking() {
  make_site 'BUILD_CMD="touch build-ran"'
  touch -t "$OLD" "$PROJ/dist/index.html"; touch -t "$NEW" "$PROJ/src/app.js"
  deploy || fail "deploy must succeed: $OUT"
  [[ -e "$PROJ/build-ran" ]] || fail "BUILD_CMD must run"
  assert_not_contains "$OUT" "newer than its source"
  assert_called "^aws s3 sync "
}

t_dependencies_vcs_data_and_finder_files_are_not_source() {
  make_site
  mkdir -p "$PROJ/node_modules/x" "$PROJ/.git"
  touch "$PROJ/node_modules/x/index.js" "$PROJ/.git/index" "$PROJ/.DS_Store"
  touch -t "$OLD" "$PROJ/src/app.js"; touch -t "$MID" "$PROJ/dist/index.html"
  touch -t "$NEW" "$PROJ/node_modules/x/index.js" "$PROJ/.git/index" "$PROJ/.DS_Store"
  deploy || fail "deploy must succeed: $OUT"
  assert_called "^aws s3 sync "
}

t_build_inputs_outside_the_source_are_checked() {
  make_site 'BUILD_INPUTS="../shared/versions.json"'
  mkdir -p "$TMP/shared"; echo '{}' > "$TMP/shared/versions.json"
  touch -t "$OLD" "$PROJ/src/app.js"; touch -t "$MID" "$PROJ/dist/index.html"; touch -t "$NEW" "$TMP/shared/versions.json"
  deploy && fail "a changed BUILD_INPUTS file must make the build stale"
  assert_contains "$OUT" "versions.json changed after the last build"
  assert_not_called "^aws s3"
}

t_a_missing_build_input_stops_the_deploy() {
  make_site 'BUILD_INPUTS="../nope.json"'
  touch -t "$OLD" "$PROJ/src/app.js"; touch -t "$NEW" "$PROJ/dist/index.html"
  deploy && fail "a missing BUILD_INPUTS path must stop the deploy"
  assert_contains "$OUT" "BUILD_INPUTS path not found: ../nope.json"
  assert_not_called "^aws s3"
}

t_a_hand_written_site_can_be_its_own_source() {
  make_site 'SRC_DIR="./dist"'
  touch -t "$OLD" "$PROJ/dist/index.html"; touch -t "$NEW" "$PROJ/src/app.js"
  deploy || fail "deploy must succeed: $OUT"
  assert_contains "$OUT" "its own source"
  assert_called "^aws s3 sync "
}

t_every_html_page_is_uploaded_uncached_and_assets_are_long_cached() {
  make_site 'SRC_DIR="./dist"'
  echo '<p>privacy</p>' > "$PROJ/dist/privacy.html"
  deploy || fail "deploy must succeed: $OUT"
  assert_called "^aws s3 sync [^ ]+ s3://example-bucket --delete --exclude \*\.html --cache-control max-age=31536000"
  assert_called "^aws s3 cp [^ ]+ s3://example-bucket --recursive --exclude \* --include \*\.html --cache-control no-cache"
  assert_called "^aws s3 sync [^ ]+ s3://example-bucket --delete --exclude \* --include \*\.html --cache-control no-cache"
  assert_not_called "exclude index\.html"
}

t_uncommitted_source_changes_are_warned_about() {
  make_site
  touch -t "$OLD" "$PROJ/src/app.js"; touch -t "$NEW" "$PROJ/dist/index.html"
  stub git 'case "$*" in *status*) echo " M src/app.js" ;; esac; exit 0'
  deploy || fail "a dirty tree warns, it does not stop the deploy: $OUT"
  assert_contains "$OUT" "Uncommitted changes in"
  assert_called "^git -C .* status --porcelain --untracked-files=no"
}

# ── deploy-app ─────────────────────────────────────────
deploy_app_with_status() { # deploy_app_with_status <git status --porcelain output>
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP"; touch "$APP/main.tf" "$APP/app.env" "$TMP/app/Dockerfile"
  echo 'domain_name = "example.com"' > "$APP/app.tfvars"
  stub terraform "
case \"\$*\" in
  *'output -raw ecr_repository_url'*) echo 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo ;;
  *'output -raw cpu_architecture'*) echo X86_64 ;;
  *'output -raw'*) echo x ;;
esac
exit 0"
  stub git "case \"\$*\" in *'rev-parse --short HEAD'*) echo abc1234 ;; *status*) printf '%s' '$1' ;; esac; exit 0"
  OUT="$("$DF/bin/deploy-app" --config "$APP" --yes 2>&1)" || true
}

t_deploy_app_tags_a_dirty_tree_as_dirty() {
  deploy_app_with_status " M src/main.kt"
  assert_called "^docker build .* -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo:git-abc1234-dirty "
  assert_not_called "demo:git-abc1234 "
  assert_contains "$OUT" "Uncommitted changes"
}

t_deploy_app_tags_a_clean_tree_with_the_commit() {
  deploy_app_with_status ""
  assert_called "^docker build .* -t 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo:git-abc1234 "
  assert_not_called "dirty"
  assert_not_contains "$OUT" "Uncommitted changes"
}
