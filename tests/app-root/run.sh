#!/usr/bin/env bash
# Renders templates/full-stack the way bin/new-app --existing-zone does and
# plans it with the real Namecheap provider and no Namecheap credentials
# (AWS mocked). No AWS or Namecheap call.
# Usage: tests/app-root/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT="$PWD"
source lib/retry.sh
# Inside the repo: the module source must be a relative path, since
# Terraform reads an absolute one as a package its ../ submodules may not leave.
WORK="$(mktemp -d "$ROOT/tests/app-root/work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
unset NAMECHEAP_API_USER NAMECHEAP_API_KEY NAMECHEAP_USER_NAME NAMECHEAP_CLIENT_IP NAMECHEAP_USE_SANDBOX

dir="$WORK/existing_zone"; mkdir -p "$dir/tests"
for f in templates/full-stack/*; do
  base="$(basename "$f")"
  case "$base" in
    gitignore.tmpl | app.env.tmpl | app.tfvars.tmpl | backend.tf.tmpl | namecheap.tf.tmpl) ;;
    namecheap-existing-zone.tf.tmpl) cp "$f" "$dir/namecheap.tf" ;;
    *.tmpl) sed -e "s|__MODULE_SOURCE__|../../../../modules/full-stack|g" -e "s|__DOMAIN__|example.com|g" "$f" > "$dir/${base%.tmpl}" ;;
    *) cp "$f" "$dir/$base" ;;
  esac
done
cp tests/app-root/existing_zone.tftest.hcl "$dir/tests/"
printf '\n== test: app root (existing_zone, no Namecheap credentials)\n'
cd "$dir" && retry terraform init -backend=false -input=false -no-color >/dev/null && terraform test -no-color
