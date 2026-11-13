#!/usr/bin/env bash
# Renders templates/static the way bin/new-site does, once as a Namecheap root
# and once as an --existing-zone root (no namecheap.tf), and runs each mode's
# tests against mocked providers. No AWS or Namecheap call.
# Usage: tests/static-root/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
source lib/retry.sh
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

render() { # render <template> <out>
  sed -e "s|__DOMAIN__|example.com|g" -e "s|__SITE_NAME__|example-com|g" \
    -e "s|__STATE_KEY__|devopsfoundry/example.com/terraform.tfstate|g" -e "s|__BUILD_DIR__|./dist|g" \
    -e "s|__MODULES__|$ROOT/modules|g" -e "s|__MODULE_QUERY__||g" \
    -e "s|__EXISTING_ZONE_ID__||g" -e "s|__INCLUDE_WWW__|true|g" "$1" > "$2"
}

fail=0
for mode in namecheap existing_zone; do
  dir="$WORK/$mode"; mkdir -p "$dir/tests"
  for f in templates/static/*; do
    base="$(basename "$f")"
    case "$base" in
      gitignore.tmpl) ;;
      namecheap.tf.tmpl) [[ "$mode" == namecheap ]] && render "$f" "$dir/namecheap.tf" ;;
      *.tmpl) render "$f" "$dir/${base%.tmpl}" ;;
      *) cp "$f" "$dir/$base" ;;
    esac
  done
  cp "tests/static-root/$mode.tftest.hcl" "$dir/tests/"
  printf '\n== test: static site root (%s)\n' "$mode"
  (cd "$dir" && retry terraform init -backend=false -input=false -no-color >/dev/null && terraform test -no-color) || fail=1
done
exit $fail
