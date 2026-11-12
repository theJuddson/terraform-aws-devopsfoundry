# Checkov findings accepted

Install checkov with pip (`pip install checkov==3.4.3`), as CI does. The Homebrew build did not run the graph
checks (`CKV2_*`) here, so it reports fewer findings than CI.

`bin/check-modules` runs checkov over the whole repository. A finding fails the run unless it is listed in
`.checkov.baseline` or suppressed in the code with a `#checkov:skip` comment that gives the reason.

## Baseline: the modules as they were at v1.1.0

These findings were in the existing modules before the checks were added. Fixing any of them would change what
existing stacks build, which a minor release must not do, so they are recorded in `.checkov.baseline` instead. Each
is a candidate for an opt-in variable in a later release. v1.3.0 and v1.4.0 added the ones named below; the rest are tracked as
[GitHub issues](https://github.com/theJuddson/terraform-aws-devopsfoundry/issues?q=is%3Aissue+label%3Aenhancement).
The defaults still match v1.1.0, so checkov keeps reporting these for the default settings.

| Module | Check | Finding | Why it stays for now |
| --- | --- | --- | --- |
| all VPC modules | CKV2_AWS_5 | Security groups for RDS, Redis and tasks not attached in the same module | They are attached by the database, cache and container-service modules |
| cache | CKV2_AWS_50 | Redis without Multi-AZ automatic failover | Single node for cost; `num_cache_clusters = 2` or more turns on Multi-AZ failover (v1.3.0) |
| cache | CKV_AWS_191 | Redis encrypted with the AWS-managed key, not a customer managed key | Still encrypted at rest; opt in with `kms_key_arn` (v1.4.0; replaces an existing cache) |
| container-service | CKV_AWS_158 | Log group not encrypted with a customer managed key | CloudWatch default encryption; opt in with `log_kms_key_arn` (v1.4.0) |
| container-service | CKV_AWS_338 | Logs kept 14 days, not a year | `log_retention_days` is a variable; 14 days suits small apps |
| container-service | CKV_AWS_65 | Container Insights off | Billed per metric; opt in with `container_insights = true` (v1.3.0) |
| container-service | CKV_AWS_150 | ALB deletion protection off | `destroy-app` must be able to tear a stack down; opt in with `alb_deletion_protection = true` (v1.3.0) |
| container-service | CKV_AWS_91 | ALB access logs off | Needs a log bucket; opt in with `alb_access_logs = true` (v1.4.0) |
| database | CKV_AWS_118, CKV_AWS_353 | No enhanced monitoring, no Performance Insights | Cost; opt in with `monitoring_interval` and `performance_insights_enabled` (v1.3.0) |
| database | CKV_AWS_157 | Single-AZ | `db_multi_az` is a variable; off by default for cost |
| database | CKV2_AWS_30 | No Postgres query logging | Opt in with `log_min_duration_ms` (v1.4.0) |
| database | CKV_AWS_161 | No IAM database authentication | Apps use the RDS-managed password from Secrets Manager; opt in with `iam_database_authentication_enabled = true` (v1.3.0) |
| database | CKV_AWS_293 | Deletion protection off by default | `db_deletion_protection` is a variable; off so teardown works |
| email | CKV_AWS_273, CKV_AWS_40 | IAM user with an inline policy | SES SMTP credentials can only be derived from an IAM user's access key; the policy allows `ses:SendRawEmail` only |
| project-access | CKV_AWS_273, CKV_AWS_40 (inline skip) | Optional IAM user with an inline policy | Only when `user_name` is set, for a shared account without Identity Center; it can only assume the project role with MFA and manage its own password and MFA. Separate accounts with `organization` and `identity-center` are the SSO way |
| email, full-stack | CKV2_AWS_57 | SMTP password and Redis auth token have no rotation Lambda | Rotated by `bin/rotate-secret` (v1.9.0), which also rolls the service so tasks read the new value; a Lambda would fight Terraform, which owns the secret versions |
| email | CKV_AWS_149 | SMTP secret encrypted with the AWS-managed key | Still encrypted at rest; opt in with `kms_key_arn` (v1.4.0) |
| container-service | CKV2_AWS_28 | ALB without WAF | WAF costs about $5/month per ACL plus rules; opt in with `create_waf = true` or attach one with `waf_web_acl_arn` (v1.3.0) |
| networking | CKV2_AWS_11, CKV2_AWS_12 | No VPC flow logs; default security group not emptied | Flow logs cost; opt in with `enable_flow_logs = true` (v1.3.0). Nothing uses the default group |
| route53-zone | CKV2_AWS_38, CKV2_AWS_39 | No DNSSEC signing, no query logging | Opt in with the `route53-zone-security` module or full-stack's `enable_dnssec` / `enable_dns_query_logging` (v1.4.0) |
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
| networking | CKV_AWS_158, CKV_AWS_338 | The opt-in flow log group uses CloudWatch default encryption unless `flow_log_kms_key_arn` is set, and `flow_log_retention_days` |
| container-service | CKV_AWS_18, CKV_AWS_144, CKV_AWS_145, CKV_AWS_21, CKV2_AWS_62 | The opt-in ALB log bucket: logging it would recurse, replication and versioning add nothing to expiring logs, ALB logs support SSE-S3 only, no consumer needs notifications |
| database | CKV2_AWS_69 | The opt-in parameter group (`log_min_duration_ms`) changes logging only; TLS enforcement stays the engine default (`rds.force_ssl = 1` from Postgres 15) |
| route53-zone-security | CKV_AWS_7, CKV_AWS_109, CKV_AWS_111, CKV_AWS_356 | KMS cannot rotate the asymmetric DNSSEC key; `Resource: "*"` in a key policy means the key itself |
| route53-zone-security | CKV_AWS_158, CKV_AWS_338 | The query log group uses CloudWatch default encryption unless `kms_key_arn` is set, and `query_log_retention_days` |
| ecr-repository | CKV_AWS_51 | Tags are immutable by default; `container-service` keeps `MUTABLE` for its `:latest` deploy flow |
| container-service | CKV2_AWS_31 | The opt-in WAF doesn't log requests (billed per GB); CloudWatch metrics and sampled requests are on |
| container-service | CKV_AWS_192, CKV2_AWS_76 | The WAF's managed rule groups are a variable; the default list includes `AWSManagedRulesKnownBadInputsRuleSet`, which blocks Log4j lookups |

## tflint

Every module must be free of tflint warnings and notices; `bin/check-modules` fails on any. The modules from v1.1.0
had warnings until v1.2.4 added their version constraints. One notice is ignored inline, with its reason:
`cache` uses AWS's default `default.redis7` parameter group on purpose.
