# shellcheck shell=bash
# deploy-app builds for the service's CPU architecture (#31).

deploy_with_arch() { # deploy_with_arch <cpu_architecture output, or "none">
  APP="$TMP/app/.devopsfoundry"; mkdir -p "$APP"; touch "$APP/main.tf" "$APP/app.env" "$TMP/app/Dockerfile"
  echo 'domain_name = "example.com"' > "$APP/app.tfvars"
  stub terraform "
case \"\$*\" in
  *'output -raw cpu_architecture'*) [[ '$1' == none ]] && exit 1; echo '$1' ;;
  *'output -raw ecr_repository_url'*) echo 123456789012.dkr.ecr.us-east-1.amazonaws.com/demo ;;
  *'output -raw'*) echo x ;;
esac
exit 0"
  "$DF/bin/deploy-app" --config "$APP" --yes >/dev/null 2>&1 || true
}

t_arm64_service_gets_an_arm64_image() {
  deploy_with_arch ARM64
  assert_called "^docker build --platform linux/arm64 "
}

t_x86_64_service_gets_an_amd64_image() {
  deploy_with_arch X86_64
  assert_called "^docker build --platform linux/amd64 "
}

t_app_roots_without_the_output_keep_amd64() {
  deploy_with_arch none
  assert_called "^docker build --platform linux/amd64 "
}
