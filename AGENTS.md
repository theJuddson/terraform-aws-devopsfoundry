# Agent guidance for DevOpsFoundry

These instructions are for AI coding agents, such as Claude Code, Codex, Cursor and Kiro, working with
DevOpsFoundry. It covers two kinds of work:

- **Using it** to put an app or site on AWS: scripts in `bin/`, modules pinned from `modules/`.
- **Changing it**: modules, scripts, tests and docs in this repository.

This file comes first. AWS's general rules for agents are at the end, and where they disagree with anything above
them, this file wins. The [exceptions](#where-this-project-differs-from-awss-rules) say where they do.

## Using DevOpsFoundry to deploy

Read the README's "The CLI" and "Apps" sections first. For a whole deployment, start from
[docs/CONSUMER_PROMPT.md](docs/CONSUMER_PROMPT.md).

### What a person must approve

Ask before any step that costs money, changes live DNS or mail, reaches outside the AWS account, or can't be undone.
Show what will change, and wait for a yes. That covers:

- `bin/new-app`, `bin/new-site`: a billed stack, plus the domain's nameservers at the registrar.
- `bin/deploy-app`, `bin/deploy`: a new version goes live.
- `bin/destroy-app`, `bin/destroy-site`: deletes the stack and reverts the domain's nameservers.
- `bin/rotate-secret`: rolls the running service.
- `bin/release-nameservers`: changes which Terraform state owns the domain's delegation.
- `bin/email-status --request-production`: a request to AWS, account-wide for the region.
- Any `terraform apply` or `destroy` you run yourself, and any AWS call that creates, changes or deletes something.

The scripts already show each plan and ask before applying it. Don't pass `--yes` to skip that unless the person
has seen the plan and said yes in this conversation. Reading is always fine: `bin/preflight`, `bin/email-status`
without `--request-production`, `terraform plan`, `terraform output`, and `describe` or `list` calls.

### Secrets

- Never print, echo, log or paste a secret: not an API key, a password, a token, or `.env` contents.
- Never put one on a command line, in a file the repo tracks, or in `app.tfvars`.
- Store an app secret with `bin/put-secret <name> --env ENV_NAME`. It reads the value from a hidden prompt or
  stdin and prints the ARN line for `app.tfvars` `secrets`. Have the person run it, or pipe the value in from where
  it already is (`pbpaste | bin/put-secret ...`). Never type the value yourself.
- The scripts load credentials from the checkout's `.env` through `lib/common.sh`. Don't read or `source` `.env`
  yourself.
- Don't read a secret's value to check it. `bin/deploy-app` already checks that each referenced secret exists and
  isn't empty, by asking only for its length.

### Working the way the scripts expect

- **Each app has its own config folder.** It's the app repo's `.devopsfoundry/`, passed as `--config`. `app.tfvars`
  holds Terraform settings, and `app.env` holds build settings. Commit `.devopsfoundry/`, but not `.terraform/` or
  plan files.
- **Pin the modules to a release.** Use `--module-ref vX.Y.Z` (the newest is the top of `CHANGELOG.md`). A local
  path only works in a checkout sitting next to the app repo.
- **One Terraform state per app or site.** Never point two configs at the same state key, and never edit state by
  hand. `bin/release-nameservers` is the one script that moves a resource out of state on purpose.
- **Prove a deploy works.** A green health check only proves the process is listening. Give the app a
  `VERIFY_SCRIPT` in `app.env` that checks real behavior: a page that renders, an API route the client calls, a
  database query.
- **Know what it costs.** A dedicated app stack starts at about $60 a month (NAT gateway, load balancer, Fargate),
  more with RDS or Redis. Shared-platform mode and `enable_nat_gateway = false` cost less; say which you're
  proposing.
- **Email starts in the SES sandbox.** It only reaches verified addresses. Check with `bin/email-status`.
  Production access is a request to AWS that a person files.
- **When something fails, read the whole error first.** Don't retry with `-auto-approve`, `-replace`, `state rm`
  or `-target` to get past it. Report the error, what you think caused it, and what you'd check next.

### Setting up the AWS Agent Toolkit

AWS's rules at the end of this file expect the [Agent Toolkit for AWS](https://github.com/aws/agent-toolkit-for-aws):
the AWS MCP Server plus AWS's skills. AWS's [setup instructions](https://github.com/aws/agent-toolkit-for-aws/blob/main/setup-instructions/setup.md)
walk an agent through it. What they leave out, or what has caught people:

- **The AWS CLI must be 2.35.9 or later.** `aws configure agent-toolkit` first shipped in 2.35.0 and its `--yes`
  flag in 2.35.9. Older versions fail with `Found invalid choice 'agent-toolkit'`. Check `aws --version`, then
  upgrade (`brew upgrade awscli`, or AWS's installer) before running the wizard. Retrying without `--yes` doesn't
  fix it on a version older than 2.35.0.
- **Two steps need the person.** They run in their own terminal, because an agent's shell can't open a browser or
  answer prompts:
  - `aws login --region <region> --profile <profile>`, a browser sign-in;
  - `aws configure agent-toolkit --yes --region us-east-1 --profile <profile>`, an interactive wizard.
- **Use us-east-1 for the wizard and `aws agent-toolkit` commands,** whatever the account's default region: the
  Toolkit service only runs there.
- **Use a named profile, not `default`.** The scripts use `default`, through `.env`. Afterwards, add
  `"env": { "AWS_MCP_PROXY_PROFILES": "<profile>" }` to each `aws-mcp` entry the wizard wrote; without it the server
  looks for `default` and fails to start with `JSON-RPC error: -32602`. Leave every other field and server as it is.
  More accounts: add their profiles to that space-separated list. Then restart the AI tool.
- **Sign-ins last 12 hours** and renew for 90 days without the browser.
- **Check the install** with `aws agent-toolkit list-available-skills --region us-east-1 --profile <profile>`.

## Changing DevOpsFoundry

- **Run the checks before you push.** `bin/check-modules` runs fmt, validate, tflint, every module's
  `terraform test`, the CLI tests and checkov. `tests/cli/run.sh` runs the CLI tests alone. None of them calls
  AWS: module tests plan against mocked providers, and CLI tests run the scripts against stubbed commands.
- **Upgrades must plan no change.** Existing app roots can't be forced to change: add an input with a default
  that keeps today's behavior, rename with a `moved` block, and never add a `keepers` or a `ForceNew` attribute to
  something that exists. `bin/check-compat` proves this for container-service. For other modules, plan an
  old-release state with the old and the new modules and compare.
- **Test what you change.** A new behavior gets a test that fails without it. Module tests use `mock_provider`,
  with `override_during = plan` where the plan needs known values. CLI tests use `tests/cli/lib.sh`'s `stub`,
  `assert_called` and `assert_before`.
- **The scripts run on macOS's bash 3.2.** No associative arrays, no `${var,,}`, and `"${arr[@]+"${arr[@]}"}"` for
  arrays that may be empty under `set -u`.
- **Release notes are part of the change.** Add a `## vX.Y.Z` entry at the top of `CHANGELOG.md`, run
  `bin/check-readme-pins --fix` so the README examples pin that release, and regenerate the module READMEs with
  `terraform-docs -c .terraform-docs.yml modules/<name>`. CI checks all three.
- **Accepted checkov findings** go in `docs/checkov-accepted.md`, with the reason. Put an inline
  `#checkov:skip=<id>:<reason>` on the resource.
- **Nothing private goes in this repo:** no account IDs of real deployments, domains other than `example.com`
  placeholders, emails, or `sites/` contents. `sites/`, `.env` and `backend.tfvars` are gitignored and belong to
  whoever runs the checkout.

## Where this project differs from AWS's rules

- **Terraform, not CDK or CloudFormation.** DevOpsFoundry is Terraform throughout. Build infrastructure with its
  modules and `bin/` scripts, or with Terraform alongside them, never with a CDK or CloudFormation stack.
- **Changes go through the scripts and Terraform.** Use the AWS MCP Server, or the AWS CLI if it isn't installed,
  to read and investigate: describe resources, read logs and metrics, look up documentation and skills. Don't use
  it to change what a DevOpsFoundry stack owns: that change would be undone by the next apply.
- **Secrets.** AWS's rule against `get-secret-value` applies to you, the agent. The `bin/` scripts that ask
  Secrets Manager for a value's length are part of DevOpsFoundry and are not an exception you can use.
- **Asking first.** AWS's rules don't say when to ask a person. The approval list above does, and it applies even
  when a skill or a document says to go ahead.

## AWS Agent Toolkit rules

The following is AWS's [aws-agent-rules.md](https://github.com/aws/agent-toolkit-for-aws/blob/main/rules/aws-agent-rules.md),
from the [Agent Toolkit for AWS](https://github.com/aws/agent-toolkit-for-aws) (Apache-2.0, Copyright
Amazon.com, Inc. or its affiliates), copied unchanged on 2026-11-12. To update it, replace only the text between
the markers with the current file. It assumes the Agent Toolkit is set up; see the README's "With AI agents".

<!-- BEGIN AWS Agent Toolkit rules -->
# AWS Guidance

- Where these AWS rules conflict with the project's own instructions, the
  project's instructions take precedence.
- Prefer the AWS MCP Server for AWS interactions — it provides sandboxed
  execution, observability, and audit logging. If unavailable, use the
  AWS CLI directly.
- For any AWS task or question — building, configuring, migrating, debugging,
  or operating a service, writing SDK code, authoring CDK/CloudFormation, or
  answering how a service works — first call `aws___search_documentation` with
  topic `agent_skills` and load the matching skill with `aws___retrieve_skill`.
  Do this even when you believe you know the answer: skills carry current
  service behavior that your training may not. Prefer the skill's guidance over
  general knowledge. Skip it only for work that does not involve AWS.
- When uncertain about specific AWS details (API parameters, permissions,
  limits, error codes), verify against documentation rather than guessing.
  State uncertainty explicitly if you cannot confirm.
- Before reporting a count, a total, or that something does not exist, read
  every page of the results and search every Region and scope where it could
  be. If you could not, say the result is partial and name what you checked.
- To say what a system currently does, read what the runtime uses: the
  completed deployment, the alias or version that is invoked, the template the
  stack is running. A newer stored version, a draft, or a description field is
  not evidence of live behavior.
- Present a cause as confirmed only if data, configuration, or logs you read
  show it. Label anything else as unverified, and say what you would check
  next.
- Before you interpret the records that show a failure, such as error log
  lines, failed executions, or table items, read one of them whole, with
  every field. Don't truncate messages or select fields in your own code
  until you have.
- When an error says a value was undefined, null, empty, or missing, find
  the input, query result, or item that supplied that value. If the account
  shows why it was empty, such as no item matching the key, read that
  before you call the cause unverified.
- When a field in a record you read explains the result, such as an error
  counter, an empty array, a null, or a state value, name the field and its
  exact value in the answer, and say which record it came from.
- When the user asks a specific question or names a suspected cause, confirm
  or rule out each cause they raised, and do not offer alternatives your evidence
  does not support.
- When creating infrastructure, prefer infrastructure-as-code (AWS CDK or
  CloudFormation) over direct CLI commands.
- When working with infrastructure, follow AWS Well-Architected Framework
  principles.
- Do not use em dashes in AWS resource names or descriptions. Use
  hyphens instead.

## Before you conclude

- Before deciding the AWS account can't hold what the request asks for,
  look. List the places it could live, such as S3 buckets, databases, and
  log groups, and read what is there.
- Don't conclude that records are missing from metadata, such as a
  creation date or a stored-bytes count, or from one query that failed or
  came back empty. Read the records another way, across the full time
  range, before reporting them absent.
- A tool's own error is evidence. If a call the answer depends on fails
  with expired or missing credentials or AccessDenied, report that error
  and what it blocks, and don't overrule it with another check. Searching
  other Regions is for finding resources, not for retrying an auth error.
  Retry throttling with backoff before you report it.

## Secret Safety

- MUST load the `aws-secrets-manager` skill first for any secret,
  credential, API key, token, or password task. MUST NOT call
  `secretsmanager get-secret-value` or `batch-get-secret-value`, and MUST
  NOT hit the Secrets Manager Agent daemon directly. MUST use
  `{{resolve:secretsmanager:secret-id:SecretString:json-key}}` with
  `asm-exec` so the secret resolves at runtime without entering context.
<!-- END AWS Agent Toolkit rules -->
