# Checkov findings accepted

Install checkov with pip (`pip install checkov==3.4.3`), as CI does. The Homebrew build did not run the graph
checks (`CKV2_*`) here, so it reports fewer findings than CI.

`bin/check-modules` runs checkov over the whole repository. A finding fails the run unless it is listed in
`.checkov.baseline` or suppressed in the code with a `#checkov:skip` comment that gives the reason.

## Baseline: the modules as they were at v1.1.0

These findings were in the existing modules before the checks were added. Fixing any of them would change what
existing stacks build, which a minor release must not do, so they are recorded in `.checkov.baseline` instead. Each
is a candidate for an opt-in variable in a later release.

| Module | Check | Finding | Why it stays for now |
| --- | --- | --- | --- |
| all VPC modules | CKV2_AWS_5 | Security groups for RDS, Redis and tasks not attached in the same module | They are attached by the database, cache and container-service modules |
| cache | CKV2_AWS_50 | Redis without Multi-AZ automatic failover | Single node for cost |
| cache | CKV_AWS_191 | Redis encrypted with the AWS-managed key, not a customer managed key | Still encrypted at rest; a CMK adds cost and a key policy to manage |
| container-service | CKV_AWS_158 | Log group not encrypted with a customer managed key | Logs are encrypted with the CloudWatch default key |
| container-service | CKV_AWS_338 | Logs kept 14 days, not a year | `log_retention_days` is a variable; 14 days suits small apps |
| container-service | CKV_AWS_65 | Container Insights off | Billed per metric; off keeps a small app cheap |
| container-service | CKV_AWS_150 | ALB deletion protection off | `destroy-app` must be able to tear a stack down |
| container-service | CKV_AWS_91 | ALB access logs off | Needs a log bucket; not every app wants one |
| database | CKV_AWS_118, CKV_AWS_353 | No enhanced monitoring, no Performance Insights | Cost; turn on per app when needed |
| database | CKV_AWS_157 | Single-AZ | `db_multi_az` is a variable; off by default for cost |
| database | CKV2_AWS_30 | No Postgres query logging | Turn on with a parameter group when needed |
| database | CKV_AWS_161 | No IAM database authentication | Apps use the RDS-managed password from Secrets Manager |
| database | CKV_AWS_293 | Deletion protection off by default | `db_deletion_protection` is a variable; off so teardown works |
| email | CKV_AWS_273, CKV_AWS_40 | IAM user with an inline policy | SES SMTP credentials can only be derived from an IAM user's access key; the policy allows `ses:SendRawEmail` only |
| email, full-stack | CKV2_AWS_57 | SMTP password and Redis auth token not rotated automatically | The app reads them at start; rotation needs an app restart plan first |
| email | CKV_AWS_149 | SMTP secret encrypted with the AWS-managed key | Still encrypted at rest |
| container-service | CKV2_AWS_28 | ALB without WAF | WAF costs about $5/month per ACL plus rules; add per app |
| networking | CKV2_AWS_11, CKV2_AWS_12 | No VPC flow logs; default security group not emptied | Flow logs cost; nothing uses the default group |
| route53-zone | CKV2_AWS_38, CKV2_AWS_39 | No DNSSEC signing, no query logging | DNSSEC needs a KMS key in us-east-1 and registrar DS records |
| networking | CKV_AWS_394 | Availability zones not pinned by zone ID | Changing it would re-plan subnets for existing stacks |
| networking | CKV_AWS_130 | Public subnets assign public IPs | They hold the ALB and NAT, and NAT-free tasks need public IPs |
| networking | CKV_AWS_260 | ALB security group open on port 80 | Port 80 only redirects to HTTPS |
| networking, shared-platform | CKV_AWS_382 | Security groups allow all egress | Tasks call AWS APIs and third parties on arbitrary hosts |
| static-site | CKV_AWS_310, CKV_AWS_68, CKV_AWS_86, CKV_AWS_374, CKV2_AWS_32, CKV2_AWS_47 | CloudFront without origin failover, WAF, access logs, geo restriction or response headers policy | A static site behind private S3 and OAC; each adds cost for little gain |
| static-site | CKV_AWS_18, CKV_AWS_144, CKV_AWS_145, CKV2_AWS_61, CKV2_AWS_62 | Site bucket without access logs, replication, KMS, lifecycle or notifications | The bucket holds a rebuildable build output |

## Suppressed in the new modules

| Module | Check | Reason |
| --- | --- | --- |
| kms-key | CKV_AWS_109, CKV_AWS_111, CKV_AWS_356 | In a key policy, `Resource: "*"` means the key itself |
| shared-filesystem | CKV_AWS_356 | Only EC2 `Describe*` calls (which accept no resource) and a deny statement use `"*"` |
| object-store | CKV2_AWS_62 | Event notifications are the caller's to add |
| object-store | CKV_AWS_144 | Cross-region replication doubles storage cost; versioning covers recovery |
| task-runner | CKV2_AWS_5 | The security group is attached at run time by the controller's `RunTask` call |
| task-runner | CKV_AWS_382 | Tasks reach arbitrary internet hosts by design; narrow `egress_cidr_blocks` to restrict |
| task-runner | CKV_AWS_65 | Container Insights is billed; opt in with `container_insights = true` |
| task-runner | CKV_AWS_338 | Retention is `log_retention_days`; one-off task logs rarely need a year |
| ecr-repository | CKV_AWS_136 | AES-256 by default; pass `kms_key_arn` for a customer managed key |
| ecr-repository | CKV_AWS_51 | Tags are immutable by default; `container-service` keeps `MUTABLE` for its `:latest` deploy flow |

## tflint

Every module must be free of tflint warnings and notices; `bin/check-modules` fails on any. The modules from v1.1.0
had warnings until v1.2.4 added their version constraints. One notice is ignored inline, with its reason:
`cache` uses AWS's default `default.redis7` parameter group on purpose.
