# shellcheck shell=bash
# bin/estimate-cost (#63): prices from the AWS Price List API, sums in code.
# The stub answers get-products from a small price list, so totals are exact.

# product <usagetype> <usd> [extra attribute json fields]: one Price List entry.
product() {
  local attrs="\"usagetype\":\"$1\",\"licenseModel\":\"No license required\",\"volumeType\":\"General Purpose-GP3\"${3:+,$3}"
  printf '{"product":{"attributes":{%s}},"terms":{"OnDemand":{"t":{"priceDimensions":{"d":{"unit":"Hrs","pricePerUnit":{"USD":"%s"}}}}}}}' "$attrs" "$2" | jq -Rs .
}
# prices: the stub answers each service code with its entries in $TMP/prices/<code>.
prices() {
  mkdir -p "$TMP/prices"
  printf '%s\n' "$(product USE1-Fargate-vCPU-Hours:perCPU 0.04)" "$(product USE1-Fargate-GB-Hours 0.004)" \
    "$(product USE1-Fargate-ARM-vCPU-Hours:perCPU 0.03)" "$(product USE1-Fargate-ARM-GB-Hours 0.003)" > "$TMP/prices/AmazonECS"
  printf '%s\n' "$(product LoadBalancerUsage 0.02)" "$(product TS-LoadBalancerUsage 0.005)" "$(product Outposts-LoadBalancerUsage 0.99)" > "$TMP/prices/AWSELB"
  printf '%s\n' "$(product NatGateway-Hours 0.04)" > "$TMP/prices/AmazonEC2"
  printf '%s\n' "$(product USE1-PublicIPv4:InUseAddress 0.005)" > "$TMP/prices/AmazonVPC"
  printf '%s\n' "$(product InstanceUsage:db.t4g.micro 0.016)" "$(product UnusedBox:db.t4g.micro 0.5)" \
    "$(product Multi-AZUsage:db.t4g.micro 0.032)" "$(product RDS:GP3-Storage 0.1)" "$(product RDS:Multi-AZ-GP3-Storage 0.2)" > "$TMP/prices/AmazonRDS"
  printf '%s\n' "$(product NodeUsage:cache.t4g.micro 0.016)" "$(product USE1-ExtendedSupportYr3-NodeUsage:cache.t4g.micro 0.9)" > "$TMP/prices/AmazonElastiCache"
  stub aws "
case \"\$*\" in
  *'pricing get-products'*)
    code=\$(sed -E 's/.*--service-code ([^ ]+).*/\\1/' <<<\"\$*\")
    printf '{\"PriceList\":[%s]}' \"\$(paste -sd, '$TMP/prices/'\$code 2>/dev/null)\" ;;
esac
exit 0"
}
app() { # app <app.tfvars lines>
  APP="$TMP/app"; mkdir -p "$APP"; touch "$APP/main.tf"
  cp "$DF/templates/full-stack/variables.tf" "$APP/variables.tf"
  printf 'domain_name = "example.com"\n%s\n' "$1" > "$APP/app.tfvars"
}
estimate() { OUT="$("$DF/bin/estimate-cost" --config "$APP" "$@" 2>&1)"; }
total() { sed -nE 's/.*Estimated monthly total.*\$ *([0-9.]+)$/\1/p' <<<"$OUT"; }

t_a_default_app_prices_tasks_alb_nat_and_addresses() {
  prices; app ""
  estimate || fail "must succeed: $OUT"
  # 0.5 vCPU × 730 × 0.04 = 14.60; 1 GB × 730 × 0.004 = 2.92; ALB 730 × 0.02 = 14.60;
  # NAT 730 × 0.04 = 29.20; 3 addresses (2 zones + NAT) × 730 × 0.005 = 10.95
  assert_contains "$OUT" "Fargate vCPU, X86_64 (1 × 0.5 vCPU)"
  assert_contains "$OUT" "Public IPv4 addresses (3)"
  [[ "$(total)" == "72.27" ]] || fail "expected 72.27, got $(total): $OUT"
  assert_called "pricing get-products --region us-east-1 --service-code AmazonECS --filters Type=TERM_MATCH,Field=regionCode,Value=us-east-1 Type=TERM_MATCH,Field=locationType,Value=AWS Region"
  assert_not_contains "$OUT" "0.99"
}

t_only_the_price_list_is_read() {
  prices; app $'enable_database = true\nenable_cache = true'
  estimate || fail "must succeed: $OUT"
  ! grep -vE '^aws (pricing get-products|sts get-caller-identity)' "$CALLS" | grep -q '^aws ' || fail "only pricing calls allowed: $(cat "$CALLS")"
}

t_settings_come_from_app_tfvars_then_variables_tf_defaults() {
  prices; app $'cpu = 1024\nmemory = 2048\ndesired_count = 2\ncpu_architecture = "ARM64"'
  estimate || fail "must succeed: $OUT"
  assert_contains "$OUT" "Fargate vCPU, ARM64 (2 × 1 vCPU)"
  # ARM: 2 × 1 × 730 × 0.03 = 43.80; 2 × 2 × 730 × 0.003 = 8.76; + ALB 14.60 + NAT 29.20 + IPv4 10.95
  [[ "$(total)" == "107.31" ]] || fail "expected 107.31, got $(total)"
}

t_a_database_and_cache_are_added() {
  prices; app $'enable_database = true\ndb_allocated_storage = 50\nenable_cache = true\ncache_num_cache_clusters = 2'
  estimate || fail "must succeed: $OUT"
  # + RDS 730 × 0.016 = 11.68, storage 50 × 0.1 = 5.00, cache 2 × 730 × 0.016 = 23.36
  [[ "$(total)" == "112.31" ]] || fail "expected 112.31, got $(total): $OUT"
  assert_not_contains "$OUT" "× $0.5 "      # UnusedBox, not the instance price
  assert_called "Field=deploymentOption,Value=Single-AZ"
  assert_called "Field=cacheEngine,Value=Redis"
}

t_multi_az_uses_multi_az_prices() {
  prices; app $'enable_database = true\ndb_multi_az = true'
  estimate || fail "must succeed: $OUT"
  assert_contains "$OUT" "RDS PostgreSQL db.t4g.micro, Multi-AZ"
  # 72.27 + 730 × 0.032 = 23.36 + 20 × 0.2 = 4.00
  [[ "$(total)" == "99.63" ]] || fail "expected 99.63, got $(total)"
}

t_a_shared_platform_pays_only_its_own() {
  prices; app $'shared_platform = "host-com"'
  estimate || fail "must succeed: $OUT"
  assert_not_contains "$OUT" "Application Load Balancer"
  assert_not_contains "$OUT" "NAT gateway  "
  assert_not_contains "$OUT" "Public IPv4"
  [[ "$(total)" == "17.52" ]] || fail "expected 17.52, got $(total)"
  assert_contains "$OUT" "the host app pays"
}

t_no_nat_with_public_tasks_counts_their_addresses() {
  prices; app $'enable_nat_gateway = false\ntasks_in_public_subnets = true\ndesired_count = 3'
  estimate || fail "must succeed: $OUT"
  assert_contains "$OUT" "Public IPv4 addresses (5)"
  assert_not_contains "$OUT" "NAT gateway  "
}

t_an_ambiguous_price_is_refused_not_guessed() {
  prices
  printf '%s\n' "$(product NatGateway-Hours 0.04)" "$(product USE1-NatGateway-Hours 0.05)" > "$TMP/prices/AmazonEC2"
  app ""
  estimate && fail "two prices for one thing must stop the estimate"
  assert_contains "$OUT" "several prices for a NAT gateway"
  assert_not_contains "$OUT" "Estimated monthly total"
}

t_a_missing_price_is_refused() {
  prices; app $'enable_database = true\ndb_instance_class = "db.nope.huge"'
  estimate && fail "an unknown class must stop the estimate"
  assert_contains "$OUT" "no on-demand price for RDS PostgreSQL db.nope.huge"
  assert_not_contains "$OUT" "Estimated monthly total"
}

t_region_prefixes_match_and_lookalikes_do_not() {
  prices
  printf '%s\n' "$(product EU-Fargate-vCPU-Hours:perCPU 0.04)" "$(product EU-Fargate-GB-Hours 0.004)" > "$TMP/prices/AmazonECS"
  app $'aws_region = "eu-west-1"'
  estimate || fail "EU- prefixed usage types must match: $OUT"
  assert_called "Field=regionCode,Value=eu-west-1"
  assert_contains "$OUT" "region: eu-west-1"
}

t_bad_settings_and_arguments_are_refused() {
  prices; app $'cpu = "lots"'
  estimate && fail "a non-numeric cpu must fail"
  assert_contains "$OUT" "cpu must be a number"
  app $'cpu_architecture = "POWER9"'
  estimate && fail "an unknown architecture must fail"
  "$DF/bin/estimate-cost" --config "$APP" --bogus >/dev/null 2>&1 && fail "unknown arguments must fail"
  assert_not_called "pricing"
}

t_licensed_rds_prices_are_never_picked() {
  prices
  printf '%s\n' "$(product InstanceUsage:db.t4g.micro 0.016)" "$(product InstanceUsage:db.t4g.micro 0.7 '"licenseModel":"Bring your own license"')" \
    "$(product RDS:GP3-Storage 0.1)" > "$TMP/prices/AmazonRDS"
  app $'enable_database = true'
  estimate || fail "the licence-free price must be chosen: $OUT"
  assert_contains "$OUT" "× \$0.016"
}

t_the_app_roots_own_defaults_win_over_the_scripts() {
  prices; app ""
  # This app root's variables.tf says 2 vCPU by default; app.tfvars doesn't set cpu.
  sed -i.bak '/^variable "cpu" {/,/^}/ s/default = 512/default = 2048/' "$APP/variables.tf"
  grep -A3 '^variable "cpu" {' "$APP/variables.tf" | grep -q "default = 2048" || fail "fixture: couldn't set the cpu default"
  estimate || fail "must succeed: $OUT"
  assert_contains "$OUT" "(1 × 2 vCPU)"
}
