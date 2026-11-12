# Operating an app

All commands take `--config <app repo>/.devopsfoundry`. The ones marked * change something: show the plan and get a
yes first.

| Task | Command |
| --- | --- |
| Redeploy the current code* | `$DOF/bin/deploy-app --config <dir>` |
| Rotate the Redis token or SMTP password* | `$DOF/bin/rotate-secret --config <dir> redis` or `smtp`. Publishes a new credential while the old one works, rolls the service, retires the old one. Safe to re-run after a failure; `app.tfvars` records progress, so commit it afterwards |
| Email status | `$DOF/bin/email-status --config <dir>`: sandbox or production, whether the domain is verified (DKIM, MAIL FROM), and the DMARC report record to add |
| Request SES production access* | `... --request-production --website-url URL --use-case TEXT`. Refused until the domain is ready; the person decides |
| Stop Terraform managing a live delegation* | `$DOF/bin/release-nameservers --config <dir>` (`new-app` runs it once DNS is live) |
| Tear down* | `$DOF/bin/destroy-app --config <dir>`. Deletes the stack and reverts the nameservers unless `--keep-ns`. Only when the person asks |

## Injected environment variables

With `--enable-db`, `--enable-cache` or `--enable-email`, the container gets:

- `DB_URL` (`postgresql://...`), `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_SSL_ENABLED`, `REDIS_PASSWORD`
- `MAIL_HOST`, `MAIL_PORT`, `MAIL_USERNAME`, `MAIL_PASSWORD`

Apps that expect other names or formats (Spring's `SPRING_DATASOURCE_URL` with `jdbc:postgresql://`, for example) set
them in `app.tfvars` `env` and `secrets`; those override the injected ones.

## Upgrading

Change `--module-ref` in the app root's `main.tf` source to the newer release, read that release's CHANGELOG entry,
and run `terraform plan`: upgrades are meant to plan no change. New opt-in features (such as
`deployment_circuit_breaker`) need their variable and `module "app"` argument copied from
`$DOF/templates/full-stack` into older app roots.
