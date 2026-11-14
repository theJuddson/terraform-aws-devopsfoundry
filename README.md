# DevOpsFoundry

Terraform modules for AWS, plus an optional command-line tool that takes a domain from nothing to a live site or
container app.

- **The modules** are the main product. Use them from your own Terraform: a private S3 bucket, a KMS key with
  per-tenant key policies, EFS with run-time access points, a Fargate runner for one-off jobs, an ECR repository,
  an SSM-only EC2 host, a budget alarm, and the pieces of a full web stack (VPC, Fargate service behind an HTTPS
  ALB, RDS Postgres, Redis, SES, Route53, ACM, CloudFront).
- **The CLI** (`bin/`) is an opinionated flow on top of those modules: Route53 zone, automatic Namecheap nameserver
  delegation, certificate, then a static site or a Fargate app. Clone the repository and run it from there.

## Modules

Pin a release. From the Terraform Registry:

```hcl
module "bucket" {
  source  = "theJuddson/devopsfoundry/aws//modules/object-store"
  version = "~> 1.2"
  # ...
}
```

or straight from git, over HTTPS or SSH, pinned to a release tag (the newest is on the
[Releases page](https://github.com/theJuddson/terraform-aws-devopsfoundry/releases)):

```hcl
source = "git::https://github.com/theJuddson/terraform-aws-devopsfoundry//modules/object-store?ref=v1.20.0"
source = "git::ssh://git@github.com/theJuddson/terraform-aws-devopsfoundry//modules/object-store?ref=v1.20.0"
```

Each module's README lists its inputs and outputs, and the building blocks have a runnable example under
`examples/`.

| Module | What it makes |
| --- | --- |
| **Building blocks** | |
| [object-store](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/object-store) | Private S3 bucket: SSE-KMS, versioning, TLS-only policy, lifecycle rules, a policy granting one prefix |
| [kms-key](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/kms-key) | Customer managed key with alias and key policy, plus a policy letting an app create and use its own tagged keys |
| [shared-filesystem](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/shared-filesystem) | EFS with mount targets and an NFS-only security group, plus a policy for access points made at run time |
| [task-runner](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/task-runner) | Fargate and Fargate Spot cluster for one-off `RunTask` jobs, with roles, logs and a controller policy |
| [ecr-repository](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/ecr-repository) | ECR repository with scan on push and a lifecycle policy |
| [ec2-host](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/ec2-host) | SSM-only EC2 instance with a data volume that survives replacement, and scheduled snapshots |
| [watchtower](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/watchtower) | A [Watchtower](https://github.com/theJuddson/DevOpsWatchtower) monitoring collector: 443 only, its own Let's Encrypt certificate, SES mail through its role, data that survives replacement |
| [watchtower-agent](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/watchtower-agent) | User data and IAM policy that install and enroll the Watchtower agent on your hosts (Amazon Linux or Ubuntu) |
| [budget-alarm](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/budget-alarm) | Monthly AWS Budgets alarm to email or SNS |
| [organization](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/organization) | An AWS Organization and member accounts, one per venture that needs its own boundary |
| [identity-center](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/identity-center) | IAM Identity Center users, groups, permission sets and account assignments: who can do what in which account |
| [project-access](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/project-access) | A role (and optional MFA-only IAM user) limited to one project's tagged resources in a shared account |
| [route53-zone-security](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/route53-zone-security) | DNSSEC signing and DNS query logging for a hosted zone (us-east-1) |
| **Web stack** | |
| [networking](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/networking) | VPC, public and private subnets, optional NAT gateway, security groups |
| [container-service](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/container-service) | Fargate service behind an HTTPS ALB, with its ECR repository, logs and Route53 alias |
| [database](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/database) | RDS PostgreSQL with an AWS-managed master password |
| [cache](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/cache) | ElastiCache Redis, encrypted, with an auth token |
| [email](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/email) | SES domain identity, DKIM, DMARC and SMTP credentials |
| [shared-platform](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/shared-platform) | Finds another stack's VPC, ALB and cluster so a small app can share them |
| [full-stack](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/full-stack) | All of the above composed, as `bin/new-app` uses it |
| **DNS and static sites** | |
| [route53-zone](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/route53-zone) | Hosted zone and ACM validation records |
| [acm-cert](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/acm-cert) | Certificate for the apex and wildcard (us-east-1) |
| [static-site](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/static-site) | Private S3 bucket behind CloudFront with Origin Access Control |
| [route53-records](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/route53-records) | CloudFront aliases and optional Google Workspace mail records |
| [namecheap-ns](https://github.com/theJuddson/terraform-aws-devopsfoundry/tree/main/modules/namecheap-ns) | Points a Namecheap domain's nameservers at Route53 |

## The CLI: clone and run

The scripts run from a checkout of this repository:

```bash
git clone https://github.com/theJuddson/terraform-aws-devopsfoundry DevOpsFoundry
cd DevOpsFoundry
```

They read `.env` and `backend.tfvars` from the checkout's root (both gitignored). Keep the folder name
`DevOpsFoundry`: scaffolds made without `--module-ref` find the modules at the sibling path
`../../DevOpsFoundry/modules/full-stack`.

Two tracks. A **static site** — S3 + CloudFront. A **containerized app** — ECS
Fargate behind an HTTPS ALB. Both are configured from the consuming repo's own
`.devopsfoundry/`, passed as `--config`, so the config is committed with the code
it deploys. Each gets its own Terraform state key, so nothing shares state with
anything else. (Sites can still live in this checkout's gitignored
`sites/<domain>/` and be named by domain, as before v1.15.0.)

| Command | Does |
|---|---|
| `bin/preflight` | Toolchain, AWS auth, state bucket, Namecheap API, IP whitelist (`--existing-zone` skips Namecheap; `--config <dir>` checks that root's backend) |
| `bin/new-site <domain> --config <dir> --module-ref vX.Y.Z` | Zone + NS delegation + ACM + S3 + CloudFront; `--existing-zone [ZONE]` uses a Route53 zone that already exists instead |
| `bin/deploy --config <dir>` | Build, sync to S3, invalidate CloudFront. Files with a content hash in their name are cached for a year, HTML never, everything else is revalidated on each request |
| `bin/destroy-site --config <dir>` | Tear down; reverts nameservers to Namecheap default (in an existing zone, removes only the site's records) |
| `bin/new-app <domain> --config <dir>` | Zone + NS + ACM + VPC + Fargate stack at `desired_count = 0`; shows each phase's plan and asks before applying it (`--yes` skips, `--plan-only` applies nothing) |
| `bin/deploy-app --config <dir>` | Build image → ECR → apply → roll service → verify |
| `bin/put-secret <name> --env ENV_NAME` | Store an app secret from a hidden prompt or stdin (never argv or history), tagged with its app, optionally under your own KMS key (`--kms-key`); prints the `app.tfvars` line |
| `bin/email-status [--config <dir>]` | Whether SES in the app's region can send to anyone yet (or is in the sandbox), whether the app's domain is verified (DKIM, MAIL FROM), and the DMARC report record to add; `--request-production` asks AWS for production access, once the domain is ready |
| `bin/rotate-secret --config <dir> redis\|smtp` | Rotate the app's Redis auth token or SMTP password with no failed requests: publish a new one while the old still works, roll the service, retire the old one; `bin/preflight` warns once one is over 90 days old |
| `bin/estimate-cost --config <dir>` | The app's monthly on-demand cost from its `app.tfvars` and AWS's Price List API: tasks, load balancer, NAT gateway, public IPv4, database and cache, priced and summed line by line (usage-driven costs listed, not priced) |
| `bin/release-nameservers --config <dir>` | Stop managing a live Namecheap delegation in Terraform, so plans and deploys never call Namecheap or need its credentials (`new-app` and `new-site` run it) |
| `bin/destroy-app --config <dir>` | Tear down the app stack; reverts the delegation unless `--keep-ns` |

Both `new-site` and `new-app` run in **two phases** to dodge the
cert-validation-vs-NS-propagation race — delegate first, poll `dig` until it
propagates, then validate ACM and build the rest. `--resume --yes` picks up a
timed-out phase 2.

### Prerequisites

Local tooling: `terraform` (>=1.7), `aws` CLI (authenticated to the account that will hold the stacks),
`jq`, `dig` (`brew install bind`), `curl`, `git`.

**State backend** (one-time): an S3 bucket and DynamoDB lock table for Terraform state. Copy
`backend.tfvars.example` to `backend.tfvars` (gitignored) and fill them in. Optionally set
`DF_EXPECTED_AWS_ACCOUNT` in `.env` so `bin/preflight` warns when the profile points at another account.

**Namecheap API** (one-time):
1. Enable API access: Namecheap → Profile → Tools → Business & Dev Tools →
   *Namecheap API Access* → toggle ON. Eligibility: the account needs **≥20
   domains OR ≥$50 balance OR ≥$50 spent in the last 2 years**.
2. Whitelist this machine's **static public IPv4** (API admin → Whitelisted IPs).
   The whitelisted IP must equal `NAMECHEAP_CLIENT_IP` (auto-detected if unset).
3. Copy `.env.example` → `.env` and fill `NAMECHEAP_USER_NAME` / `API_USER` /
   `API_KEY`. `.env` is gitignored.

No production account yet? Set `NAMECHEAP_USE_SANDBOX=true` (or `--sandbox`) to
exercise the Namecheap path against the free sandbox with no eligibility gate.

### Usage

```bash
bin/preflight                                   # check toolchain + AWS + Namecheap + IP whitelist
bin/new-site example.com --config ../MySite/.devopsfoundry --module-ref v1.20.0 --build-dir dist
                                                # scaffold + two-phase provision
bin/deploy --config ../MySite/.devopsfoundry    # build (optional) + sync + invalidate
bin/destroy-site --config ../MySite/.devopsfoundry   # tear down; reverts NS to default
```

Commit the site repo's `.devopsfoundry/`; its `.gitignore` keeps `.terraform/` out.
Paths in its `site.env` are relative to the directory holding `.devopsfoundry/`.
Without `--config`, `new-site <domain>` scaffolds into this checkout's
`sites/<domain>/` (gitignored, so nothing commits it) and the other scripts take
the domain instead of `--config`.

The state backend is the site root's own `backend.tfvars` when it has one (put it in `.devopsfoundry/` before
running `new-site`, for a project's own state bucket), else this checkout's.

`bin/new-site` runs in **two phases** to avoid the cert-validation-vs-NS-
propagation race on a fresh domain:
1. Create the Route53 zone + delegate Namecheap nameservers to it.
2. Poll `dig NS … @8.8.8.8` until delegation propagates, then validate the ACM
   cert, build CloudFront, and add the alias records.

If propagation is slow and step 2 times out, resume with the same command plus
`--resume --yes`.

Once the site is live, `new-site` stops managing the Namecheap record in Terraform (`bin/release-nameservers`: the
record leaves the state, then `namecheap.tf` becomes `namecheap.tf.released`; commit both). Later plans of the root
then need no Namecheap credentials or whitelisted IP. `bin/deploy` never needed them, since it only reads outputs.
For a site made before v1.18.2, run `bin/release-nameservers --config <dir>` once. `destroy-site` still reverts the
delegation: it renames the file back and re-adopts the record first.

`bin/deploy` uploads `BUILD_DIR` from the site root's `site.env`. With a
`BUILD_CMD` it builds first. Without one it uploads the directory as it is, so it
first checks the build is at least as new as its source: `SRC_DIR` (default:
`BUILD_DIR`'s parent, minus `BUILD_DIR`, `.git`, `node_modules` and `.devopsfoundry`) plus any
`BUILD_INPUTS`, the other files the build reads. If a source file changed after
the newest file in `BUILD_DIR`, it stops before uploading and names the file;
`--allow-stale` deploys anyway. For a hand-written site with no build, set
`SRC_DIR` to `BUILD_DIR`. Uncommitted changes in the source get a warning.

#### Existing DNS zone (site)

`--existing-zone` puts the site's records in a public Route53 zone that already exists in the account, such as one
made by hand that the registrar already points at. No zone is created, Namecheap is never called, and `.env` needs
no Namecheap settings (`bin/preflight --existing-zone` skips those checks).

```bash
bin/new-site example.com --existing-zone example.com \
  --config ../MySite/.devopsfoundry --module-ref v1.20.0 --build-dir dist        # apex and www
bin/new-site blog.example.com --existing-zone example.com \
  --config ../Blog/.devopsfoundry --module-ref v1.20.0 --build-dir dist          # a subdomain, no www
bin/new-site example.com --existing-zone --config ../MySite/.devopsfoundry ...   # list the zones that fit; choose one
```

- The zone is the domain itself (the site serves the apex and `www`) or a parent of it (a subdomain site, without
  `www`). `ZONE` is a name or a zone id; two public zones of one name are refused, naming their ids, so pass the id.
  Private zones are never used.
- Bare `--existing-zone` lists the public zones that could serve the domain, closest first, with their ids and
  record counts, and asks which to use. Put the domain before the flag (or write `--existing-zone=ZONE`): a word
  after a bare `--existing-zone` is read as its zone.
- Without the flag, `new-site` won't create a second zone where one already serves the domain: it lists them the
  same way and asks whether to use one or stop. With `--yes` it never chooses for you; it stops and prints the
  `--existing-zone` argument to pass.
- Before anything is applied, `dig NS` at 8.8.8.8 must answer the zone's own nameservers, or ACM could never
  validate. If it doesn't yet, `new-site` shows both sets and stops (exit 75); point the registrar at the zone and
  re-run with `--resume --yes`.
- ACM validation and the alias records are added without overwriting anything: a name that already has a record
  fails the apply. The certificate covers the apex and its wildcard, or exactly the subdomain. `--email` and
  `--sandbox` are refused in this mode.
- The zone id is recorded as `existing_zone_id` in the root's `terraform.tfvars`, and the root gets no
  `namecheap.tf`. `bin/deploy` works as for any site; `bin/destroy-site` removes only the site's records and never
  the zone or its nameservers (`--keep-ns` is refused).

#### Email

`bin/new-site example.com --email --dkim "<google-dkim-key>"` adds Google
Workspace MX + DKIM records (or edit `enable_google_email` / `google_dkim_key`
in the site root's `terraform.tfvars`).

#### Moving a site root out of `sites/`

The state key doesn't depend on where the root lives, so a root moves without
touching AWS:

1. Copy `*.tf`, `terraform.tfvars` and `site.env` from `sites/<domain>/` into the
   site repo's `.devopsfoundry/` (not `.terraform/` or the lock file), and add the
   `.gitignore` from `templates/static/gitignore.tmpl`.
2. Change each `source = "../../modules/<name>"` to
   `"git::ssh://git@github.com/theJuddson/terraform-aws-devopsfoundry//modules/<name>?ref=vX.Y.Z"`,
   and make the `site.env` paths relative to the repo.
3. `terraform -chdir=<dir> init -backend-config=<DevOpsFoundry>/backend.tfvars`, then
   `plan`. It must report no changes; if it doesn't, pin the release the site was
   applied with. Then commit, and delete `sites/<domain>/`.

### Apps (full-stack container services)

DevOpsFoundry also provisions a **framework-neutral container service** (ECS Fargate
behind an HTTPS ALB) with optional RDS Postgres, Redis, and SES — for a backend app
in *another* repo. The consuming repo owns its config under `.devopsfoundry/`:

```bash
# from anywhere; --config points at the app repo's .devopsfoundry dir
bin/new-app example.com --config ../MyApp/.devopsfoundry --enable-db          # serves at api.example.com (default)
# ...or serve at the bare domain:
bin/new-app example.com --config ../MyApp/.devopsfoundry --enable-db --apex   # serves at example.com
# edit ../MyApp/.devopsfoundry/app.tfvars (cpu/mem/env/secrets), ensure a Dockerfile, then:
bin/deploy-app  --config ../MyApp/.devopsfoundry
bin/destroy-app --config ../MyApp/.devopsfoundry
```

Once the domain is delegated, `new-app` stops managing the Namecheap record in Terraform (`bin/release-nameservers`:
the record leaves the state, then `manage_nameservers = false`, and `namecheap.tf` configures the Namecheap provider
with placeholders), so `deploy-app` never needs the Namecheap API, its credentials or a whitelisted IP. For an app made
before v1.18.2, run `bin/release-nameservers --config <dir>` once; it also gives an `--existing-zone` app made before
v1.18.1 the placeholders. `destroy-app` still reverts the delegation; it puts the real provider back and re-adopts the
record first.

**Email.** With `--enable-email`, `new-app` ends by saying whether SES in the app's region is still in the
**sandbox**, where mail only reaches verified addresses. Production access is per account and region, so most
accounts only ask for it once:

```bash
bin/email-status --config ../MyApp/.devopsfoundry --request-production \
  --website-url https://example.com --use-case "Sign-in links and receipts for registered users"
```

It asks before sending and only sends from the sandbox; AWS reviews the request. If `dmarc_rua_email` is on
another domain, receivers only send that domain reports once it publishes `<domain>._report._dmarc.<report domain>
TXT "v=DMARC1"`. Set `dmarc_report_zone_id` to that domain's zone and the module creates the record; otherwise
`new-app` and `email-status` print the record to add.

**Rotating secrets.** The Redis auth token and the SMTP password are made by Terraform and read by tasks when they
start. `bin/rotate-secret` replaces either without a failed request:

```bash
bin/rotate-secret --config ../MyApp/.devopsfoundry redis   # or smtp
```

It publishes a new credential while the old one still works (Redis accepts both tokens during a `ROTATE`; SMTP
uses a second IAM key), forces a new deployment and waits until every task has the new one, then retires the old
one (`SET`; the old SMTP key becomes Inactive and is replaced at the next rotation). Each apply is planned first,
shown, and refused if it would change anything else. Progress is kept in `app.tfvars`, so after a failure a re-run
carries on; commit `app.tfvars` afterwards. `bin/preflight` names any of these secrets older than 90 days
(`DF_SECRET_MAX_AGE_DAYS` changes the limit). App roots made before v1.9.0 need the "Secret rotation" variables
from `templates/full-stack/variables.tf` and the matching lines of `main.tf.tmpl`.

**CPU architecture.** Tasks run on X86_64 by default. Set `cpu_architecture = "ARM64"` in `app.tfvars` to run on
Graviton (about 20% cheaper per vCPU-hour); `deploy-app` then builds `linux/arm64` images, which on Apple Silicon
means native builds instead of slow, sometimes crashing amd64 emulation. Native dependencies must support arm64. Either
way, build steps that don't depend on the target platform (installing and compiling JavaScript, for example) can run
natively with `FROM --platform=$BUILDPLATFORM node:22 AS build` in a multi-stage Dockerfile.

The service is fronted at `<subdomain>.<domain>` (default subdomain `api`). Pass
`--apex` (or set `subdomain = ""` in `app.tfvars`) to serve at the **bare domain**
itself — the ACM cert covers the apex, and Route53 aliases the apex A record to the ALB.
In apex mode, `www.<domain>` is also wired up and **301-redirects to the apex**.

`new-app` scaffolds `.devopsfoundry/{main.tf,backend.tf,variables.tf,outputs.tf,app.tfvars,app.env}`
into the app repo and runs the same two-phase DNS flow as `new-site`, then provisions
the stack at **`desired_count = 0`** (no image yet). `deploy-app` then builds the
Dockerfile, pushes to ECR, scales the service up, rolls it, and health-checks.

**The `.devopsfoundry/` contract:**
- `app.tfvars` — the editable surface: `domain_name`, `subdomain`, `cpu`/`memory`,
  `desired_count`, `health_check_path`, `env` (plaintext map), `secrets`
  (env-name → Secrets Manager ARN map), and `enable_database`/`enable_cache`/`enable_email`.
- `app.env` — build config for `deploy-app`: `DOCKERFILE`, `DOCKER_CONTEXT`, `DOCKER_BUILD_ARGS`,
  and the optional `VERIFY_SCRIPT` (see *Verifying a deploy*). Not stamped into the
  scaffold — add the line yourself.
- `main.tf` — thin: providers + one call to the DevOpsFoundry `full-stack` module
  (`source` defaults to the sibling `../../DevOpsFoundry/modules/full-stack`; use
  `--module-ref <gitref>` for a pinned git source in CI).

When `enable_database`/`enable_cache`/`enable_email` are on, conventional connection vars
are auto-injected into the container (`DB_URL`/`DB_HOST`/`DB_PORT`/`DB_NAME` +
`DB_USERNAME`/`DB_PASSWORD`; `REDIS_HOST`/`REDIS_PORT`/`REDIS_PASSWORD`;
`MAIL_HOST`/`MAIL_PORT`/`MAIL_USERNAME`/`MAIL_PASSWORD`) — your `app.tfvars` `env`/`secrets`
override any of them.

App modules: `networking`, `shared-platform`, `container-service`, `database`, `cache`,
`email`, composed by `full-stack`. State key: `devopsfoundry/app/<slug>/terraform.tfstate`.

#### Existing DNS zone (subdomain of a live domain)

`--existing-zone <zone>` hosts the app at `<subdomain>.<zone>` inside a Route53 zone that already serves
something else (a website, mail). No zone is created and Namecheap is never called, so no Namecheap credentials
are needed; the ACM cert covers only
the app's hostname, and validation/alias records are added without ever overwriting existing ones. Apex
serving and `--enable-email` are refused in this mode, and `destroy-app` removes only the app's own records.

```bash
bin/new-app example.com --subdomain app --existing-zone example.com \
  --config ../MyApp/.devopsfoundry --enable-db --shared-platform other-app-com --module-ref v1.20.0
```

#### App-owned state

`--backend-config <file>` keeps the app's Terraform state in its own S3 bucket (for example a
`<project>-terraform-state-<account>` bucket) instead of the shared one. The file is copied to
`.devopsfoundry/backend.tfvars` and used on every later init.

#### Verifying a deploy

By default `deploy-app` finishes with a `health_check_path` request and warns that
a 200 there proves only that the process is listening. It is worth being precise
about how little that covers: a health endpoint stays green over an empty schema,
a dead database credential, a frontend whose every asset 404s, and an API whose
routes do not match what the client calls. All four have shipped green.

Set `VERIFY_SCRIPT` in `app.env` to a script in your repo and `deploy-app` runs it
instead, passing the service URL as `$1`. A non-zero exit **fails the deploy**:

```bash
# .devopsfoundry/app.env
VERIFY_SCRIPT="scripts/verify-deploy.sh"
```

Note what a failure here means. The rollout completed and the new image *is* live —
this is not a failed deploy, it is a deploy that succeeded and produced a broken
app. Fix forward, or roll back by re-tagging a previous `git-<sha>` image (every
deploy pushes both `git-<sha>` and `latest`; the task definition pulls `latest`).
An image built with uncommitted changes to tracked files is tagged
`git-<sha>-dirty` instead, since it isn't exactly that commit.

#### Deployment windows (Watchtower)

With a [Watchtower](https://github.com/theJuddson/DevOpsWatchtower) collector (the `watchtower` module),
`deploy-app`, `deploy` and `rotate-secret` open a deployment window around each run, so Watchtower holds the
target's alerts while it changes and learns how long its deploys take. It is optional: without `WATCHTOWER_URL`
nothing changes and no request is made. Set it in the checkout's `.env`, or per app or site in `app.env` /
`site.env` (which win):

```bash
WATCHTOWER_URL="https://watch.example.com"
WATCHTOWER_TOKEN_PARAMETER="/myapp/watchtower/deploy-token"   # SSM SecureString; the module's deploy_token_command makes it
WATCHTOWER_TARGET="myapp"          # default: the app's name in app.tfvars, or the site's domain
WATCHTOWER_SOURCES="web-1 web-2"   # what the window covers: sources, groups and probes,
WATCHTOWER_GROUPS="app"            # space- or comma-separated
WATCHTOWER_PROBES="home"
WATCHTOWER_SETTLE_TIMEOUT=600      # seconds to wait for settled (default twice Watchtower's estimate)
```

- The window opens after the confirmation. If a deployment of the target is already running, the script warns and
  deploys without a window rather than take over the other one.
- `deploy-app` and `rotate-secret` extend the window before rolling the service when less than 10 minutes are left,
  since ECS can take that long to stabilize. `deploy` waits for the CloudFront invalidation to complete.
- After the health check or `VERIFY_SCRIPT`, the script polls Watchtower every 15 seconds until the target is back
  to normal, extending the window by the estimate when it is about to end, then closes it as `succeeded`, saying
  whether it settled and why not. An ECS rollback closes it as `rolled-back`; any other failure as `failed`, with
  the error.
- A Watchtower that can't be reached, or answers with an error, only gets a warning: a deploy never fails because
  monitoring is down. The token is read from SSM with `ssm:GetParameter` (and `kms:Decrypt` for a customer managed
  key) and handed to curl on stdin, never on a command line.

#### WAF

`create_waf = true` puts an AWS WAF web ACL in front of a dedicated ALB: a per-IP rate limit (`waf_rate_limit`) and
AWS's managed rule groups (IP reputation, core rule set, known bad inputs), about $5/month plus $1 per rule and $0.60
per million requests. On a live app, start with `waf_count_only = true` and `waf_logging = true`: rules only count,
and the log group `aws-waf-logs-<app>-alb` records which rule matched which request (only blocked and counted
requests, with the Authorization and Cookie headers redacted; billed per GB, kept `waf_log_retention_days`, 30 by
default). When the counts look right, set `waf_count_only = false` to enforce, and exempt any rule that catches real
traffic with `waf_rule_overrides`. In shared-platform mode the WAF belongs to the platform that owns the ALB.

#### Alarms

Set `alarm_emails = ["you@example.com"]` in `app.tfvars` for baseline alarms, emailed through an SNS topic: the
app's 5xx rate, p99 latency, unhealthy targets and no healthy target, and with a database, its free storage, CPU and
(on `db.t*` classes) CPU credits. Each address must confirm the subscription email AWS sends. About $0.10 per alarm
per month; tune the thresholds with `alarm_5xx_percent` and `alarm_p99_seconds`, or send them to an existing topic
with `alarm_sns_topic_arns`.

#### Shared platform (cheap mode)

A dedicated stack carries roughly **$50/month of fixed cost before serving a
single request** — a NAT gateway (~$33) and an ALB (~$16). For a small app that
dwarfs the actual compute, and it is duplicated for every app that gets its own
stack.

`--shared-platform <slug>` attaches an app to an **existing** DevOpsFoundry
app's VPC, NAT gateway, ALB and ECS cluster instead:

```bash
bin/new-app example.com --config ../MyApp/.devopsfoundry \
  --apex --enable-db --shared-platform other-app-com
```

Typical cost falls from ~$85/mo to ~$25/mo (one Fargate task plus its own RDS).

**What is shared, and what is not.** The host platform's VPC, subnets, NAT, ALB
and ECS cluster are read-only data sources. They are found by ID from the
host's platform descriptor when it publishes one (see *Renaming a shared
platform* below), and otherwise by this tool's naming conventions
(`<slug>-vpc`, `<slug>-private-<az>`, `<slug>-alb`, `<slug>-alb-sg`,
`<slug>-cluster`). The guest app still owns its own security
groups, target group, task definition, service, and — when `enable_database` is
on — its own RDS instance, with its own credentials and backups. Nothing in the
host platform's Terraform state is modified, so it never shows drift.

The guest claims its traffic with an `aws_lb_listener_rule` matched on host
header, plus an `aws_lb_listener_certificate` for SNI. Each guest needs a
distinct `listener_rule_priority_base` (default 100); it uses `<base>` for the
forward rule and `<base>+1` for the www redirect.

**The trade-off, stated plainly:** sharing a VPC and ALB means sharing a failure
domain. An ALB or NAT problem on the host takes the guest down too, and
`destroy-app` on the host strands every guest. Right for a small app; wrong for
anything that needs independent availability.

**Ordering:** never `destroy-app` a platform that still has guests attached.

#### Renaming a shared platform

A platform keeps the name of the app that built it, so once several apps share
it, `shared_platform = "first-app-com"` describes one product. To give it a
generic name, the host publishes a **platform descriptor**: an SSM parameter
`/devopsfoundry/platform/<platform_name>` holding its VPC, subnet, ALB security
group, ALB and cluster IDs. Guests read it before falling back to naming
conventions. Nothing in AWS is renamed or replaced, so there is no downtime; the
host's resources keep their original names, visible only in the AWS console.

1. **Host:** set `platform_name = "web-platform"` in its `app.tfvars` (app roots
   scaffolded before v1.6.0 also need `platform_name = var.platform_name` in the
   module block and the variable in `variables.tf`; see `templates/full-stack`),
   then `bin/deploy-app`. The plan adds one SSM parameter and changes nothing
   else.
2. **Each guest:** set `shared_platform = "web-platform"` and plan. It should
   show no changes, because the same resources are found by ID. Guests not yet
   switched keep working under the old name.

The first rename is seamless because guests on the old name still find the host
by naming convention. Renaming *again* is not: a stack publishes one name at a
time, so changing `platform_name` deletes the previous descriptor. Guests'
running services are unaffected, but their plans fail until each one switches to
the new name, so switch them right after the host's apply. A stack in
shared-platform mode cannot publish a descriptor. Whoever plans a guest needs
`ssm:GetParametersByPath` on `/devopsfoundry/platform`; the CLI's usual
credentials have it.

#### Dropping the NAT gateway

Shared platform removes the NAT gateway by borrowing someone else's. A dedicated
stack can drop it outright instead — a service that only reaches AWS APIs and its
own database does not need one. In `app.tfvars`:

```hcl
enable_nat_gateway      = false
tasks_in_public_subnets = true
```

Tasks then run in public subnets with public IPs; inbound stays ALB-only via the
security groups. Both must be set together — turning off the NAT while tasks stay
in private subnets leaves them with no route out. Ignored in shared-platform mode,
where the host platform's networking already decided this. Neither variable is in
the generated `app.tfvars`; add them.

#### CI later

The `bin/` scripts are non-interactive with `--yes` and authenticate via the ambient
AWS profile/OIDC, so the flow lifts into GitHub Actions when ready — point the module
`source` at a pinned `--module-ref` and run `new-app --resume --yes` / `deploy-app --yes`.

### With AI agents

[AGENTS.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/AGENTS.md) holds the rules for AI coding
agents that use or change DevOpsFoundry (`CLAUDE.md` imports it for Claude Code):
- what a person must approve;
- how secrets are handled;
- how to change the modules without breaking existing stacks.

It ends with AWS's own rules for agents, from the [Agent Toolkit for AWS](https://github.com/aws/agent-toolkit-for-aws),
and says where DevOpsFoundry's rules take precedence: Terraform rather than CDK, and changes through the scripts
rather than direct AWS calls.

Those AWS rules expect the Agent Toolkit: the AWS MCP Server, plus AWS's skills for agents. Set it up once per machine
with AWS's [setup instructions](https://github.com/aws/agent-toolkit-for-aws/blob/main/setup-instructions/setup.md). It needs
AWS CLI 2.35.9 or later; `AGENTS.md` lists the other steps that catch people out.
Give them to your agent, or follow them yourself:
1. Sign in to a named AWS profile.
2. Run `aws configure agent-toolkit --region us-east-1 --profile <profile>`.
3. Set `AWS_MCP_PROXY_PROFILES` to that profile in the `aws-mcp` entry it writes.

**The DevOpsFoundry plugin** gives an agent the deploy workflow as a skill it loads when needed
(`deploying-with-devopsfoundry`: approvals, secrets, costs, operating, troubleshooting), plus a hook that asks you
before any command that skips a plan approval and blocks reading `.env` or fetching secret values. The scripts still
run from your checkout, so the skill asks where it is.

- Claude Code (2.1.275 or later): `/plugin install devopsfoundry --marketplace theJuddson/terraform-aws-devopsfoundry`.
  Earlier versions: `/plugin marketplace add theJuddson/terraform-aws-devopsfoundry`, then
  `/plugin install devopsfoundry@devopsfoundry`.
- Codex: `codex plugin marketplace add theJuddson/terraform-aws-devopsfoundry`, then install **devopsfoundry** from
  `/plugins`.
- Cursor: Settings, Plugins, Team Marketplaces, Import from Repo, `theJuddson/terraform-aws-devopsfoundry`. Cursor
  takes the skill but not the hook.

The hook is a best-effort guard, not a security boundary. Without a plugin, paste
[docs/CONSUMER_PROMPT.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/docs/CONSUMER_PROMPT.md)
into the agent instead.

## Repository layout

```
modules/        static:  acm-cert · route53-zone · route53-records · static-site · namecheap-ns
                app:     networking · container-service · database · cache · email · full-stack
                blocks:  object-store · kms-key · shared-filesystem · task-runner · ecr-repository · ec2-host · budget-alarm · route53-zone-security · watchtower · watchtower-agent
AGENTS.md       rules for AI agents using or changing DevOpsFoundry (CLAUDE.md imports it)
plugins/        the agent plugin: deploying-with-devopsfoundry skill and approval hook (bin/check-plugin validates it)
main.tf         empty root module (the Terraform Registry requires one; use the submodules)
examples/       one root per building-block module (validated in CI, never applied)
tests/          offline compatibility and validation fixtures for bin/check-*
templates/static/      site-root stamped into a repo's .devopsfoundry/ (or sites/<domain>/) by new-site
templates/full-stack/  app-root stamped into a repo's .devopsfoundry/ by new-app
sites/<domain>/        legacy, gitignored static roots (new-site without --config)
bin/            sites: preflight · new-site · deploy · destroy-site · release-nameservers
                apps:  new-app · deploy-app · destroy-app · email-status · rotate-secret · estimate-cost · release-nameservers
                repo:  check-modules (fmt/validate/tflint/checkov) · check-compat (offline no-change proof) · check-readme-pins · check-plugin · soci-index
lib/common.sh   shared shell helpers (logging, slug, tf wrappers)
backend.tfvars.example  shared S3 state backend; copy to backend.tfvars (key is per-site / per-app)
```

State: one Terraform root per site, keyed `devopsfoundry/<domain>/terraform.tfstate`
in the shared bucket, so sites never share state.

## Checks

`bin/check-modules` runs `terraform fmt -check`, `terraform validate`, tflint and checkov over every module and
example, and `bin/check-compat` proves offline that upgrading container-service from v1.2.0 (and from the earlier private
v1.1.0 state layout) plans no change. `bin/check-readme-pins` fails when this README's `?ref=` and `--module-ref`
examples pin an older release than the newest `## vX.Y.Z` in `CHANGELOG.md`; a release PR runs
`bin/check-readme-pins --fix` after adding its CHANGELOG entry.
None of them calls AWS. All run on every pull request (`.github/workflows/checks.yml`). Accepted checkov findings are
listed in [docs/checkov-accepted.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/docs/checkov-accepted.md).

## Contributing, security, license

See [CONTRIBUTING.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/CONTRIBUTING.md), [SECURITY.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/SECURITY.md) and [CHANGELOG.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/CHANGELOG.md).
Licensed under the [Apache License 2.0](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/LICENSE). Where the code comes from: [docs/PROVENANCE.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/docs/PROVENANCE.md).
