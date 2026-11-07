# Changelog

All notable changes. Versions are git tags; pin modules with `?ref=<tag>`. v1.2.0 is the first public release;
the earlier versions below were private and their tags are not in this repository.

## v1.2.2

- README links to modules and docs are absolute GitHub URLs, so they work on the Terraform Registry page.

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
