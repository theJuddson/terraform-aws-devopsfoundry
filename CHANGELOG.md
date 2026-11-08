# Changelog

All notable changes. Versions are git tags; pin modules with `?ref=<tag>`. v1.2.0 is the first public release;
the earlier versions below were private and their tags are not in this repository.

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
