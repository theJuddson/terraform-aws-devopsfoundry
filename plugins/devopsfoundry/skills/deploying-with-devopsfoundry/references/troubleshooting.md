# Troubleshooting

Read the whole error first, and name the field or line that explains it. Don't force past an error with
`-auto-approve`, `-replace`, `-target`, `terraform state` commands or `--yes`.

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| `bin/preflight`: sign-in has expired | `aws login` or IAM Identity Center session ended | The person runs the command it prints (`aws login --profile ...` or `aws sso login ...`) |
| `new-app` times out waiting for nameservers | DNS propagation is slow | Wait, then re-run with `--resume` |
| `deploy-app`: "rolled the service back" | New tasks kept failing; the circuit breaker restored the previous version, which is still serving | Read the new tasks' logs (the log group it names), fix, redeploy |
| `deploy-app`: secrets listed as missing, deleted or no value | A referenced ARN is wrong, scheduled for deletion, or never stored | Fix with `bin/put-secret`, or restore a deleted one |
| Service doesn't stabilize; tasks stop with `ResourceInitializationError` | Tasks can't reach ECR or Secrets Manager (no NAT and private subnets), or can't decrypt a secret | Check `enable_nat_gateway` / `tasks_in_public_subnets` together, and `secrets_kms_key_arns` |
| Health check fails but the app runs | Wrong `container_port` or `health_check_path`, or the path isn't 200 | Fix `app.tfvars`, redeploy |
| Mail only reaches some addresses | SES sandbox | `bin/email-status`; production access is the person's request |
| `Missing required provider` / backend not initialized | Fresh clone of the app repo | The `bin/` scripts initialize it; run them rather than bare `terraform` |
| A plan wants to replace a database, cache or zone | Something forces replacement (often a KMS key change or a stale config) | Stop and show the person; never apply a replacement of stateful resources without an explicit yes |
