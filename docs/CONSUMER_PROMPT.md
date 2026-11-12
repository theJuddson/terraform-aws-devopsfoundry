# Consumer prompt: deploy an app with DevOpsFoundry

Paste the block below into an agent session (Claude Code, Codex, Cursor, ...) running **inside the app repo you
want to deploy**. Replace `<DEVOPSFOUNDRY_DIR>` with your DevOpsFoundry checkout. Leave the other `<...>`
placeholders, or fill them in: the prompt has the agent gather them and propose values before it runs anything. The
agent uses DevOpsFoundry's `bin/` scripts and the `.devopsfoundry/` contract, and must not change DevOpsFoundry
itself.

If your agent takes plugins, install the DevOpsFoundry plugin instead (README, "With AI agents"): its
`deploying-with-devopsfoundry` skill carries this workflow, and its hook enforces the approvals. This prompt is
for agents without plugin support.

For best results, set up AWS's Agent Toolkit on the machine first (README, "With AI agents"). The agent then reads
AWS documentation and skills through the AWS MCP Server.

---

```
We're going to put THIS application on AWS with DevOpsFoundry, a separate toolkit checked out at
<DEVOPSFOUNDRY_DIR>. Use it; don't change it.

READ FIRST
- <DEVOPSFOUNDRY_DIR>/AGENTS.md: the rules for agents using DevOpsFoundry. They take precedence over general AWS
  guidance. Above all: what I must approve, and how secrets are handled.
- <DEVOPSFOUNDRY_DIR>/README.md, sections "The CLI" and "Apps (full-stack container services)".
AWS and Namecheap credentials are already in <DEVOPSFOUNDRY_DIR>/.env. The scripts load them; don't read that file.

WHAT IT BUILDS
A container service on ECS Fargate behind an HTTPS load balancer, with Route53 DNS and the domain's nameservers
set at Namecheap. Optional: Postgres (RDS), Redis and SES email. It can share another app's network and load
balancer (--shared-platform) to cost less.

FIRST, GATHER AND REPORT (run nothing that changes anything yet)
- The domain. Is it in the Namecheap account, or is it an existing Route53 zone (--existing-zone)? Should the app
  serve at a subdomain (default api.<DOMAIN>) or the bare domain (--apex)?
- The port the container listens on, and a health path that returns 200.
- A Dockerfile that builds a runnable image. If there isn't one, propose a multi-stage production Dockerfile.
  Graviton (cpu_architecture = "ARM64" in app.tfvars) is about 20% cheaper if the image's dependencies support
  arm64.
- Backing services: Postgres (--enable-db), Redis (--enable-cache), email (--enable-email).
- Every environment variable the app reads, and which are secrets.
- A VERIFY_SCRIPT for app.env: a small script that proves the deployed app works (a page renders, a real API route
  answers, the database is reachable). A health check alone doesn't prove that.
- The cost: dedicated, with or without a NAT gateway, or shared with an existing platform. Once the proposed
  settings are in .devopsfoundry/app.tfvars, run <DEVOPSFOUNDRY_DIR>/bin/estimate-cost --config
  <THIS_REPO>/.devopsfoundry and show me its table. Don't work out prices yourself.
Then propose app.tfvars and app.env values, and the exact new-app command with --module-ref <latest vX.Y.Z from
CHANGELOG.md>, and wait for my approval.

THE WORKFLOW
1. Scaffold and provision. This creates billed infrastructure and changes the domain's nameservers:
     <DEVOPSFOUNDRY_DIR>/bin/new-app <DOMAIN> --config <THIS_REPO>/.devopsfoundry --module-ref <vX.Y.Z> [flags]
   It shows each phase's plan and asks before applying it. Show me each plan; don't pass --yes.
   It provisions at desired_count = 0 (no image yet). That's expected.
2. Secrets: I store each one with
     <DEVOPSFOUNDRY_DIR>/bin/put-secret <app>/<name> --env ENV_NAME
   and paste the ARN line it prints into app.tfvars `secrets`. Never type, echo or log a secret value yourself.
3. Edit .devopsfoundry/app.tfvars (container_port, health_check_path, cpu, memory, desired_count, env, secrets) and
   .devopsfoundry/app.env (DOCKERFILE, DOCKER_CONTEXT, VERIFY_SCRIPT). Commit .devopsfoundry/, but not .terraform/.
4. Deploy, after I approve:
     <DEVOPSFOUNDRY_DIR>/bin/deploy-app --config <THIS_REPO>/.devopsfoundry
   It checks the secrets, builds, pushes, applies, rolls the service, waits until it's stable, and runs
   VERIFY_SCRIPT.
5. Email: SES starts in the sandbox, where mail only reaches verified addresses. Check with
     <DEVOPSFOUNDRY_DIR>/bin/email-status --config <THIS_REPO>/.devopsfoundry
   and tell me what it reports. Requesting production access is my decision.

GOTCHAS
- app.tfvars is Terraform settings; app.env is build settings. They are different files.
- With --enable-db, --enable-cache or --enable-email the container gets conventional variables: DB_URL
  (postgresql://...), DB_HOST, DB_PORT, DB_NAME, DB_USERNAME, DB_PASSWORD; REDIS_HOST, REDIS_PORT,
  REDIS_SSL_ENABLED, REDIS_PASSWORD; MAIL_HOST, MAIL_PORT, MAIL_USERNAME, MAIL_PASSWORD. If the app expects other
  names or formats (Spring's SPRING_DATASOURCE_URL with jdbc:postgresql://, for example), set them in env/secrets:
  your values override these.
- new-app can take 10 to 20 minutes, waiting for nameservers to propagate and the certificate to validate. If it
  times out, rerun it with --resume.
- If a step fails, read the whole error and report it with your diagnosis. Don't force past it with
  -auto-approve, -replace, -target or terraform state commands.

VERIFY at the end: https://<host><health_check_path> answers 200 with a valid certificate, VERIFY_SCRIPT passed,
and the ECS service shows running == desired.
TEARDOWN, only when I ask: <DEVOPSFOUNDRY_DIR>/bin/destroy-app --config <THIS_REPO>/.devopsfoundry
(it also reverts the nameservers at Namecheap).
```

---

## Notes

- **Pin a release.** `--module-ref vX.Y.Z` makes the app root use a pinned git source, so it works from anywhere,
  including CI. Without it, the module source is the sibling path `../../DevOpsFoundry/modules/full-stack`, and the
  app repo must sit next to a checkout named `DevOpsFoundry`.
- **Spring Boot and other JDBC apps** need `jdbc:postgresql://` URLs or their own variable names. Set them in
  `app.tfvars` `env`; they override the injected ones.
- **The prompt is framework-neutral.** The workflow was validated end to end against a throwaway app: provision,
  deploy, 200, teardown.
