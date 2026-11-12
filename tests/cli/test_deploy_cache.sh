# shellcheck shell=bash
# bin/deploy sets each file's cache header from its name: hashed assets are cached
# for a year, HTML never, and everything else is revalidated on every request.

# A provisioned site whose build is dist/; the files are named in the call.
# make_cache_site <file under dist>...
make_cache_site() {
  PROJ="$TMP/proj"; mkdir -p "$PROJ/dist"
  local f
  for f in "$@"; do mkdir -p "$(dirname "$PROJ/dist/$f")"; echo "$f" > "$PROJ/dist/$f"; done
  mkdir -p "$DF/sites/example.com"
  { echo 'BUILD_DIR="./dist"'; echo 'BUILD_CMD=""'; echo 'SRC_DIR="./dist"'; echo 'BUILD_INPUTS=""'; } \
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

deploy_cache() { OUT="$(cd "$PROJ" && "$DF/bin/deploy" example.com --yes 2>&1)"; }

t_hashed_names_are_told_apart_from_plain_ones() {
  source "$DF/lib/common.sh"
  local f
  for f in assets/index-B4kq9z1x.js main.3f2a9c1b.css chunk-2a3b4c5d6e.js fonts/inter.a1b2c3d4.woff2; do
    df_is_hashed_asset "$f" || fail "$f should count as hashed"
  done
  for f in styles.css index.html og-image.png mountains-background.png robots.txt favicon.svg \
           assets/vendor-abcdefgh.js .htaccess noextension; do
    ! df_is_hashed_asset "$f" || fail "$f should not count as hashed"
  done
}

t_each_kind_of_file_gets_its_own_cache_header() {
  make_cache_site index.html about.html styles.css og-image.png assets/index-B4kq9z1x.js
  deploy_cache || fail "deploy must succeed: $OUT"
  # hashed: synced alone, a year, immutable
  assert_called '^aws s3 sync .* --exclude \* --include assets/index-B4kq9z1x\.js --cache-control max-age=31536000,public,immutable'
  # everything else but HTML: revalidated, and the hashed file left out
  assert_called '^aws s3 cp .* --recursive --exclude \*\.html --exclude assets/index-B4kq9z1x\.js --cache-control no-cache$'
  # every HTML file, not only index.html: never cached
  assert_called '^aws s3 cp .* --recursive --exclude \* --include \*\.html --cache-control no-cache,no-store,must-revalidate'
  # nothing else is uploaded with the immutable header
  assert_count 'immutable' 1
  # old files are deleted only after everything is up
  assert_called '^aws s3 sync .* --delete --size-only'
  assert_before 'immutable' '--cache-control no-cache$'
  assert_before '--cache-control no-cache$' 'no-store'
  assert_before 'no-store' '--delete --size-only'
  assert_before '--delete --size-only' 'create-invalidation'
}

t_a_site_without_hashed_files_skips_the_year_long_pass() {
  make_cache_site index.html styles.css
  deploy_cache || fail "deploy must succeed: $OUT"
  assert_not_called 'immutable'
  assert_called '^aws s3 cp .* --recursive --exclude \*\.html --cache-control no-cache$'
}
