# Changelog

All notable changes. Versions are git tags; pin modules with `?ref=<tag>`. v1.2.0 is the first public release;
the earlier versions below were private and their tags are not in this repository.

## v1.7.0

- `bin/deploy` refuses to upload a stale static build (#43). Without a `BUILD_CMD`, it compares the newest file in
  `BUILD_DIR` with its source (`SRC_DIR`, else `BUILD_DIR`'s parent, skipping `.git` and `node_modules`) and any
  new `BUILD_INPUTS` paths, and stops before uploading if a source file is newer, naming it. `--allow-stale` deploys
  anyway; `SRC_DIR` = `BUILD_DIR` marks a hand-written site with no build. A passing check is printed, and
  uncommitted source changes are warned about. The newest build file, not the oldest, marks the last build:
  builds often copy static assets with their original times.
- `deploy-app` tags an image built with uncommitted changes to tracked files `git-<sha>-dirty`, with a warning.
- Fix: `release-nameservers` left a blank line between every line of the `manage_nameservers` variable it adds.

## v1.6.0

- Shared platforms can be renamed (#30). `full-stack` takes an opt-in `platform_name`: the host then publishes a
  platform descriptor, the SSM parameter `/devopsfoundry/platform/<platform_name>`, holding its VPC, subnet, ALB
  security group, ALB and cluster IDs. `shared-platform` reads it before falling back to naming conventions, so
  guests can switch to `shared_platform = "<platform_name>"` with no plan changes and nothing in AWS renamed or
  replaced. A malformed descriptor stops the plan before any lookup. See *Renaming a shared platform* in the
  README. Off by default: existing stacks plan no changes. Guests now read `/devopsfoundry/platform` at plan,
  which needs `ssm:GetParametersByPath` on that path.
- `container-service` outputs `alb_arn`; `shared-platform` outputs `platform_source` (`descriptor` or `naming`);
  `full-stack` outputs `platform_descriptor_name`.
- `templates/full-stack` exposes `platform_name`.

## v1.5.1

- Fix: `bin/release-nameservers` on app roots scaffolded before v1.5.0. Their `main.tf` doesn't pass
  `manage_nameservers` to the module, so setting it in `app.tfvars` did nothing and the next apply recreated the
  Namecheap record. The script now adds the variable and argument (default `true`, so nothing changes yet), checks
  offline with `terraform validate` that the app's module accepts it, and only then touches state. A module older than
  v1.2.5 is refused with the files restored. A literal `manage_nameservers = false` in `main.tf` counts as released.
- Fix: `release-nameservers`, the `deploy-app` guard and `destroy-app` now recognise states not applied since v1.2.5,
  whose Namecheap record and zone still have their unindexed addresses (`module.app.module.namecheap_ns...` rather
  than `namecheap_ns[0]`). Before, `release-nameservers` reported such apps as having nothing to release.

## v1.5.0

- CLI:
  - `bin/release-nameservers --config DIR` (#35): once a domain answers only with its Route53 nameservers, it
    removes the Namecheap record from Terraform state and then sets `manage_nameservers = false` (the other
    order would delete the delegation). `new-app` runs it after provisioning, so `deploy-app` never calls
    Namecheap or needs a whitelisted IP. For an existing app, run it once. `deploy-app` refuses a hand-set
    `manage_nameservers = false` while the record is still in state, and `destroy-app` re-adopts a released
    record so it still reverts the delegation (unless `--keep-ns`).
  - `bin/put-secret NAME [--env ENV_NAME]` (#27): stores a secret from a hidden prompt or stdin, passing it to the
    AWS CLI on stdin so it never reaches argv or shell history; creates the secret or adds a version, and prints
    the ARN or the `app.tfvars` line.
  - `deploy-app` checks every secret in `app.tfvars` before building (#28): it must exist, not be scheduled for
    deletion, and have a non-empty value. Values are never printed.
  - `new-app` plans each phase, shows a summary, asks before applying (unless `--yes`) and applies exactly the
    reviewed plan (#29). `--plan-only` applies nothing; on a new app only phase 1a can be planned exactly.
  - `terraform init` in `new-app` and `new-site` retries network errors (#32), not configuration errors.
- `container-service` and `full-stack`: `cpu_architecture` (`X86_64` default, or `ARM64` for Graviton) and a
  `cpu_architecture` output (#31). `deploy-app` builds `linux/arm64` or `linux/amd64` to match.
- The `new-app` scaffold exposes `manage_nameservers` and `cpu_architecture`, and ignores `*.tfplan`.
- `tests/cli` tests the `bin/` scripts against stub `aws`, `terraform` and `docker` commands; `bin/check-modules`
  (and so CI) runs them.

## v1.4.0

- New opt-in settings, all off by default, so existing plans are unchanged:
  - `container-service`: ALB access logs (#17). `alb_access_logs` writes them to a private, SSE-S3 encrypted
    bucket `<name>-alb-logs-<account>` with TLS-only access and a lifecycle expiry
    (`alb_access_logs_retention_days`, default 90), or to an existing bucket named in `alb_access_logs_bucket`.
  - Customer managed KMS keys (#19): `cache` `kms_key_arn` (setting it on an existing cache replaces it),
    `container-service` `log_kms_key_arn` and `secrets_kms_key_arns` (grants the task execution role
    `kms:Decrypt`), `email` `kms_key_arn` and `networking` `flow_log_kms_key_arn`. Keys must be key ARNs, not
    aliases.
  - `database`: Postgres slow-query logging (#20). `log_min_duration_ms` creates a parameter group for the engine's
    major version; an existing instance picks it up at its next reboot.
- New module `route53-zone-security` (#21): DNSSEC signing (an ECC_NIST_P256 KMS key, a key-signing key, and the
  DS record as an output) and DNS query logging for a hosted zone, in us-east-1. Turning DNSSEC on and off needs
  registrar steps in a set order: see `docs/dnssec.md`.
- `full-stack` exposes them: `alb_access_logs`, `alb_access_logs_bucket`, `alb_access_logs_retention_days`,
  `kms_key_arn` (one key for Redis, the Redis and SMTP secrets, the app's logs and flow logs),
  `db_log_min_duration_ms`, `enable_dnssec`, `enable_dns_query_logging` and `dns_query_log_retention_days`, plus
  outputs `dnssec_ds_record`, `dnssec_ds_record_fields` and `dns_query_log_group_name`. DNSSEC and query logging
  apply only to a zone the stack created, never one named in `existing_zone_name`. The `new-app` scaffold
  includes them.

## v1.3.1

- Fix (#34): a guest app on a shared platform built without a NAT gateway put its tasks in the host's private
  subnets, which have no route out, so they never started and `deploy-app` failed only after its 20-minute timeout.
  The plan now fails instead, saying to set `tasks_in_public_subnets = true` as the host does (or give the host a
  NAT gateway).
  - `shared-platform` checks the host's private route tables for a default route, takes a new
    `tasks_in_public_subnets` input (default `false`) and outputs `private_subnets_have_egress`.
  - `full-stack` passes `tasks_in_public_subnets` to it.
- No change for guests on a host with a NAT gateway. Deploying a guest now also needs `ec2:DescribeRouteTables`.

## v1.3.0

- New opt-in settings, all off by default, so existing plans are unchanged:
  - `networking`: `enable_flow_logs` sends VPC flow logs to a CloudWatch log group with its own delivery role;
    `flow_log_traffic_type` (`ACCEPT`, `REJECT` or `ALL`) and `flow_log_retention_days` tune it. New output
    `flow_log_group_name`.
  - `container-service`: `container_insights` and `alb_deletion_protection`.
  - `database`: `performance_insights_enabled` (free 7-day retention), `monitoring_interval` for enhanced monitoring
    (creates the monitoring role), and `iam_database_authentication_enabled`.
  - `cache`: `num_cache_clusters`; 2 or more adds replicas with Multi-AZ automatic failover.
  - `full-stack` passes them all through: `enable_flow_logs`, `flow_log_traffic_type`, `flow_log_retention_days`,
    `container_insights`, `alb_deletion_protection`, `db_performance_insights_enabled`, `db_monitoring_interval`,
    `db_iam_database_authentication_enabled` and `cache_num_cache_clusters`.
- Opt-in WAF on the ALB (`container-service`, passed through by `full-stack` and the `new-app` template):
  - `create_waf` creates a regional web ACL with a per-IP rate limit (`waf_rate_limit`, default 2000 requests per
    5 minutes) and AWS managed rule groups (`waf_managed_rule_groups`, default IP reputation, core rule set and
    known bad inputs), and attaches it to the ALB. About $5/month + $1/rule + $0.60 per million requests.
  - `waf_count_only` counts matches without blocking, for a safe first rollout on a live ALB; `waf_rule_overrides`
    counts individual managed rules instead of blocking them.
  - `waf_web_acl_arn` attaches an existing web ACL instead.
  - All are ignored in shared-platform mode: set them on the platform that owns the ALB and every guest app is
    covered. New output `waf_web_acl_arn`.
- `database` and `cache` have tests.
- The remaining accepted checkov findings are tracked as GitHub issues.

## v1.2.8

- Documentation only. Module READMEs show the Terraform Registry source with `version = "~> 1.2"` instead of a git
  source pinned to v1.2.1, and the main README's git examples pin v1.2.7. No module changes.

## v1.2.7

- Inputs that used to fail only at apply, or publish a broken record, now fail at plan:
  - `email`: `dmarc_policy` must be `none`, `quarantine` or `reject` (any case), `dmarc_rua_email` must be an email
    address, and `mail_from_subdomain` must be empty or DNS labels.
  - `kms-key`: `deletion_window_in_days` must be a whole number from 7 to 30, `rotation_period_in_days` from 90 to 2560.
  - `container-service`: `create_alb = false` needs `existing_alb_dns_name`, `existing_alb_zone_id` and
    `existing_https_listener_arn`; `create_cluster = false` needs `existing_cluster_arn` and `existing_cluster_name`.
- No resource changes for valid inputs. A plan that now fails had a value AWS would reject or that produced an invalid
  DMARC record.

## v1.2.6

- `container-service`, `kms-key`, `shared-filesystem` and `task-runner` no longer use `data.aws_region.current.name`,
  which aws provider 6.x deprecates. They read the region in a way that works on both 5.x and 6.x, so the minimum
  provider versions are unchanged. No resource changes.

## v1.2.5

- `full-stack` gains `manage_nameservers` (default `true`, no change for existing callers). Set it `false` once the
  Namecheap delegation is in place, so plans and deploys stop calling the Namecheap API and no longer need a
  whitelisted IP. The `namecheap` provider must still be passed in and its env vars set, but it makes no API calls.
  On an existing stack, run this once before the first apply with it `false`, or Terraform deletes the delegation:

  ```sh
  terraform state rm 'module.app.module.namecheap_ns[0].namecheap_domain_records.ns'
  ```

## v1.2.4

- Every module declares `required_version = ">= 1.7.0"` and minimum provider versions. The twelve modules that had
  none now state the floor they already needed: aws `>= 5.0` (`>= 5.60` for `container-service` and `full-stack`,
  which already required it through `ecr-repository`), namecheap `>= 2.1.0`, random `>= 3.0`. No resource changes.
- tflint warnings now fail CI for every module, not only the ones added in v1.2.0.

## v1.2.3

- README links to modules and docs are absolute GitHub URLs, so they work on the Terraform Registry page.

## v1.2.2

- Same code as v1.2.1; the tag was created on the v1.2.1 commit by mistake.

## v1.2.1

- The repository is renamed `terraform-aws-devopsfoundry` for the Terraform Registry
  (`theJuddson/devopsfoundry/aws//modules/<name>`). GitHub redirects the old URL; update pins when convenient.
- An empty root module, which the registry requires.
- README leads with the modules; the CLI is documented as clone-and-run.
- `bin/new-app --module-ref` writes the new repository URL.

## v1.2.0

- Apache-2.0 license, NOTICE, SECURITY, CONTRIBUTING, provenance notes.
- `backend.tfvars` is no longer tracked: copy `backend.tfvars.example`. **After pulling this change, restore your
  local `backend.tfvars`** (git deletes the previously tracked copy).
- `bin/preflight` checks the AWS account only when `DF_EXPECTED_AWS_ACCOUNT` is set.
- READMEs with terraform-docs tables for every module.
- New modules: `object-store`, `kms-key`, `shared-filesystem`, `task-runner`, `ecr-repository`, `ec2-host`,
  `budget-alarm`, each with an example under `examples/`.
- `container-service` builds its ECR repository through `ecr-repository`; `moved` blocks keep existing stacks
  unchanged.
- `bin/check-modules`, `bin/check-compat` and a CI workflow; `bin/soci-index` and `docs/soci.md`.

## v1.1.0

- Existing-zone mode (`--existing-zone`) and app-owned state (`--backend-config`) for `new-app`.
- Outputs for companion stacks: database endpoint and secret, RDS and task security groups, subnets.

## v1.0.0

- Static sites (S3 + CloudFront + ACM + Route53 with Namecheap delegation) and container apps (ECS Fargate behind an
  HTTPS ALB, optional RDS, Redis and SES), shared-platform mode, optional NAT gateway, `VERIFY_SCRIPT` for deploys.
