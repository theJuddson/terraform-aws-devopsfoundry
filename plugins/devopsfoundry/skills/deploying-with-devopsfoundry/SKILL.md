---
name: deploying-with-devopsfoundry
description: >
  Puts an app or static site on AWS with DevOpsFoundry, the Terraform toolkit whose bin/ scripts build a
  container service (ECS Fargate behind HTTPS, optional Postgres, Redis and SES email) or an S3 and CloudFront
  site, with DNS and certificates. Use when deploying, redeploying, rotating secrets, checking email status or
  tearing down an app that has a .devopsfoundry/ folder, or when someone asks to deploy this app to AWS with
  DevOpsFoundry. Covers what a person must approve, secret handling, the .devopsfoundry/ contract and failure
  handling. Not for changing DevOpsFoundry itself (read its AGENTS.md) or for CDK or CloudFormation stacks.
license: Apache-2.0
metadata:
  version: "1"
---

# Deploying with DevOpsFoundry

DevOpsFoundry runs from a **checkout** of its repository: its `bin/` scripts read credentials from that
checkout's `.env`, and the app's settings from the app repo's `.devopsfoundry/` folder. This skill is installed in
your tool's plugin cache, not in that checkout, so first find the checkout:

1. Ask the person where their DevOpsFoundry checkout is (often a sibling folder named `DevOpsFoundry`). Call it
   `$DOF`. Confirm `$DOF/bin/new-app` exists.
2. Read `$DOF/AGENTS.md`. Its rules come first, before this skill and before general AWS guidance.
3. Run `$DOF/bin/preflight`. It checks tools, AWS sign-in, the state bucket and Namecheap access, and says how to fix
   each. Don't carry on past a failed hard check.

Never read, print or `source` `$DOF/.env`. The scripts load it themselves.

## What a person must approve

Show what will change and wait for a yes before anything that costs money, changes live DNS or mail, reaches
outside the AWS account, or can't be undone:

| Step | Why |
| --- | --- |
| `bin/new-app`, `bin/new-site` | A billed stack, and the domain's nameservers at the registrar |
| `bin/deploy-app`, `bin/deploy` | A new version goes live |
| `bin/destroy-app`, `bin/destroy-site` | Deletes the stack; reverts the nameservers |
| `bin/rotate-secret` | Rolls the running service |
| `bin/release-nameservers` | Moves the domain's delegation out of Terraform state |
| `bin/email-status --request-production` | A request to AWS, account-wide for the region |
| Any `terraform apply` or `destroy`, any AWS call that changes something | Real infrastructure |

The scripts show each plan and ask before applying. Don't pass `--yes` unless the person has seen that plan and
said yes in this conversation. Reading is always fine: `bin/preflight`, `bin/email-status`, `terraform plan`,
`terraform output`, describe and list calls.

## Deploying a container app

1. **Gather and propose; change nothing yet.** Find:
   - the domain and whether it's at the person's Namecheap account or in an existing Route53 zone
     (`--existing-zone`);
   - subdomain (default `api.<domain>`) or bare domain (`--apex`);
   - the port, a health path that returns 200, and a Dockerfile, proposing one if there isn't;
   - Postgres (`--enable-db`), Redis (`--enable-cache`), email (`--enable-email`);
   - every environment variable, and which are secrets;
   - a `VERIFY_SCRIPT` that proves real behavior;
   - who should get alarms (`alarm_emails`), for an app people rely on.

   Propose `app.tfvars` and `app.env` values, the monthly cost from `$DOF/bin/estimate-cost --config <app
   repo>/.devopsfoundry` (see [references/costs-and-modes.md](references/costs-and-modes.md); never your own
   arithmetic), and the exact command, then wait for approval.
2. **Provision**, after approval:
   `$DOF/bin/new-app <domain> --config <app repo>/.devopsfoundry --module-ref <newest vX.Y.Z in $DOF/CHANGELOG.md> [flags]`.
   It shows each phase's plan and asks. It builds at `desired_count = 0`: there's no image yet, which is expected.
   Timed out waiting for DNS? Re-run with `--resume`.
3. **Secrets.** The person stores each one with `$DOF/bin/put-secret <app>/<name> --env ENV_NAME`, or pipes it in
   from where it already is. It prints the ARN line for `app.tfvars` `secrets`. Never type, echo or log a value. See
   [references/secrets.md](references/secrets.md).
4. **Configure.** Edit `.devopsfoundry/app.tfvars` (container_port, health_check_path, cpu, memory, desired_count,
   env, secrets) and `.devopsfoundry/app.env` (DOCKERFILE, DOCKER_CONTEXT, VERIFY_SCRIPT). Commit
   `.devopsfoundry/`, but not `.terraform/` or plan files.
5. **Deploy**, after approval: `$DOF/bin/deploy-app --config <app repo>/.devopsfoundry`. It checks the secrets,
   builds, pushes, applies, rolls the service, waits, and runs `VERIFY_SCRIPT`. If ECS rolls the deployment back
   (the circuit breaker), it fails and says so: the previous version is still serving.
6. **Email**: `$DOF/bin/email-status --config <app repo>/.devopsfoundry` reports the SES sandbox and whether the
   domain is verified. Requesting production access is the person's call.
7. **Verify**: `https://<host><health_check_path>` answers 200 with a valid certificate, `VERIFY_SCRIPT` passed, and
   the ECS service shows running == desired.

For a static site the steps are `bin/new-site <domain> --build-dir <dir>`, then `bin/deploy <domain>`.

## Operating an app

See [references/operating.md](references/operating.md): redeploys, rotating the Redis token or SMTP password,
email status, nameservers, teardown, and what the injected environment variables are.

## When something fails

Read the whole error first. Don't retry with `-auto-approve`, `-replace`, `-target`, `terraform state` commands or
`--yes` to get past it. Report the error, the field or line that explains it, what you think caused it (marked
unverified unless you read the evidence), and what you'd check next. Common causes are in
[references/troubleshooting.md](references/troubleshooting.md).
