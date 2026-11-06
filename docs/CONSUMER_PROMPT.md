# Consumer prompt — deploy an app with DevOpsFoundry

Paste the block below into a Claude Code session running **inside the app repo you
want to deploy**. Replace the `<…>` placeholders (or leave them — the prompt tells
the session to gather and propose them before doing anything). The session consumes
DevOpsFoundry's `bin/` + the `.devopsfoundry/` contract; it must not modify
DevOpsFoundry itself.

---

```
We're going to provision and deploy THIS application into AWS using DevOpsFoundry,
a separate DevOps tool checked out at <DEVOPSFOUNDRY_DIR> (do not modify it — only consume it).

WHAT DEVOPSFOUNDRY DOES
It provisions a framework-neutral container service — ECS Fargate behind an HTTPS ALB,
with Route53 DNS and automated Namecheap nameserver delegation, plus optional RDS
Postgres, Redis, and SES. AWS creds + Namecheap API creds are already configured in
<DEVOPSFOUNDRY_DIR>/.env. The full contract is in <DEVOPSFOUNDRY_DIR>/README.md
("Apps (full-stack container services)") — read it first.

THE WORKFLOW (three steps)
1. Scaffold + provision infra:
     cd <DEVOPSFOUNDRY_DIR>
     bash bin/new-app <YOURDOMAIN.com> --config <THIS_REPO>/.devopsfoundry \
       [--subdomain api | --apex] [--enable-db] [--enable-cache] [--enable-email] --yes
   By default the service is fronted at api.<YOURDOMAIN.com>; pass --apex to serve at
   the bare domain (<YOURDOMAIN.com>) instead.
   This delegates YOURDOMAIN's nameservers to Route53 (a real DNS change), validates an
   ACM cert, and stands up VPC/ALB/ECS at desired_count=0 (no image yet). It scaffolds
   <THIS_REPO>/.devopsfoundry/{main.tf,backend.tf,app.tfvars,app.env,...}.
2. Edit <THIS_REPO>/.devopsfoundry/app.tfvars (container_port, health_check_path,
   cpu/memory, desired_count, env{}, secrets{}) and .devopsfoundry/app.env (DOCKERFILE,
   DOCKER_CONTEXT). Commit the .devopsfoundry dir to this repo.
3. Build + deploy:
     bash bin/deploy-app --config <THIS_REPO>/.devopsfoundry --yes
   Builds the Dockerfile, pushes to ECR, scales the service up, rolls it, waits for
   stable, and health-checks https://api.YOURDOMAIN.com<health_check_path>.

BEFORE YOU RUN ANYTHING, gather these facts about THIS app and report them to me:
- The domain to use, and whether to serve at a subdomain (default `api` →
  api.YOURDOMAIN.com) or at the bare apex domain (`--apex` → YOURDOMAIN.com). Confirm
  the domain is registered in the Namecheap account.
- The port the container listens on (set container_port).
- A health endpoint that returns HTTP 200 (set health_check_path; default /health).
- Whether there's a Dockerfile that builds a runnable image (linux/amd64). If not, create
  a production multi-stage Dockerfile that EXPOSEs the port and runs the server.
- Which backing services it needs: Postgres (--enable-db), Redis (--enable-cache),
  SES email (--enable-email).
- All required environment variables and which are secret.

REQUIREMENTS & GOTCHAS
- Repo layout: the default module source is the relative sibling path
  ../../DevOpsFoundry/modules/full-stack, so THIS repo should sit in the same parent
  directory as the DevOpsFoundry checkout. Prefer --module-ref <tag> (a pinned git source),
  which works from anywhere.
- Config split: app.tfvars is Terraform config (sizing, env, secrets, toggles); app.env is
  build config (Dockerfile path, context). They are NOT the same file.
- env vs secrets: `env` is a plaintext map; `secrets` is a map of ENV_NAME → AWS Secrets
  Manager ARN (append ":json_key::" to pull one JSON field). For app secrets (JWT, OAuth,
  API keys, etc.), create the secrets in Secrets Manager first, then reference their ARNs
  in the `secrets` map.
- Auto-injection: with --enable-db/cache/email, DevOpsFoundry auto-injects CONVENTIONAL
  vars into the container — DB_URL (a generic postgresql:// URL), DB_HOST, DB_PORT, DB_NAME,
  DB_USERNAME, DB_PASSWORD; REDIS_HOST, REDIS_PORT, REDIS_SSL_ENABLED, REDIS_PASSWORD;
  MAIL_HOST, MAIL_PORT, MAIL_USERNAME, MAIL_PASSWORD. If THIS app reads different names or
  formats (e.g. Spring wants SPRING_DATASOURCE_URL with a `jdbc:postgresql://` prefix), set
  those explicitly in the `env`/`secrets` maps — YOUR values override the auto-injected ones.
- Bootstrap: new-app intentionally provisions at desired_count=0 (no image exists yet), so
  the service shows 0 tasks until deploy-app runs. That's expected, not a failure. Set the
  real desired_count in app.tfvars before deploy-app.
- This is a real, billed deployment (NAT gateway + ALB + Fargate ≈ ~$60/mo baseline, more
  with RDS/Redis) and it changes live DNS. Confirm with me before running new-app.
- These can run 10–20 min (NS propagation + provisioning, then image build + ECS rollout).

VERIFY at the end: curl https://api.YOURDOMAIN.com<health_check_path> returns 200 with a
valid TLS cert, and the ECS service shows running == desired.
TEARDOWN when done: bash bin/destroy-app --config <THIS_REPO>/.devopsfoundry --yes
(this also reverts the Namecheap nameservers to default).

Start by reading <DEVOPSFOUNDRY_DIR>/README.md, then inspect THIS repo and report the
gathered facts + your proposed app.tfvars/app.env values for my approval BEFORE running.
```

---

## Notes

- **Fill in before pasting**: `<DEVOPSFOUNDRY_DIR>` (where you cloned DevOpsFoundry) and, unless you let the session propose them, `<THIS_REPO>`,
  `<api.YOURDOMAIN.com>`, and the `--enable-*` toggles for the backing services the app
  needs.
- **Repo location matters.** The default module source is the relative sibling path
  `../../DevOpsFoundry/modules/full-stack`, so the consuming repo should sit next to the
  DevOpsFoundry checkout. For CI, switch to a pinned git source with
  `--module-ref <gitref>`.
- **Spring Boot / JDBC apps**: the auto-injected `DB_URL` is a generic `postgresql://`
  URL. Frameworks that need a `jdbc:postgresql://` URL or differently-named vars
  (`SPRING_DATASOURCE_URL`, etc.) should set them explicitly in `app.tfvars`'s `env` map —
  caller values override the auto-injected ones.
- This prompt is intentionally framework-neutral. Validated end-to-end against a throwaway
  app (provision → deploy → 200 → teardown).
