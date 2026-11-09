# full-stack

The composite behind `bin/new-app`: Route53 zone and Namecheap delegation (or an existing zone), ACM, VPC, a Fargate container service, and optional RDS, Redis and SES, with connection variables injected into the container. Needs an aliased `aws.us_east_1` provider from its caller.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.60 |
| namecheap | >= 2.1.0 |
| random | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.60 |
| aws.us\_east\_1 | >= 5.60 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| acm\_cert | ../acm-cert | n/a |
| cache | ../cache | n/a |
| container\_service | ../container-service | n/a |
| database | ../database | n/a |
| email | ../email | n/a |
| namecheap\_ns | ../namecheap-ns | n/a |
| networking | ../networking | n/a |
| route53\_zone | ../route53-zone | n/a |
| route53\_zone\_security | ../route53-zone-security | n/a |
| shared\_platform | ../shared-platform | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_acm_certificate_validation.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate_validation) | resource |
| [aws_route53_record.existing_zone_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_secretsmanager_secret.redis_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.redis_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_route53_zone.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain\_name | Apex domain registered at Namecheap | `string` | n/a | yes |
| name | Resource-name prefix / app slug (e.g. myapp-com) | `string` | n/a | yes |
| alb\_access\_logs | Write ALB access logs to S3 (a private bucket <name>-alb-logs-<account>, unless alb\_access\_logs\_bucket names one). Ignored in shared-platform mode. | `bool` | `false` | no |
| alb\_access\_logs\_bucket | Existing bucket for the access logs; it must already allow ELB log delivery. Empty = create one. | `string` | `""` | no |
| alb\_access\_logs\_retention\_days | n/a | `number` | `90` | no |
| alb\_deletion\_protection | Block deleting the ALB; turn off again before destroy-app. Ignored in shared-platform mode. | `bool` | `false` | no |
| aws\_region | n/a | `string` | `"us-east-1"` | no |
| az\_count | n/a | `number` | `2` | no |
| cache\_engine\_version | n/a | `string` | `"7.1"` | no |
| cache\_node\_type | ── Cache tuning ─────────────────────────────────────── | `string` | `"cache.t4g.micro"` | no |
| cache\_num\_cache\_clusters | Redis nodes; 2 or more adds replicas with Multi-AZ automatic failover. | `number` | `1` | no |
| container\_image | ── Container ────────────────────────────────────────── | `string` | `""` | no |
| container\_insights | CloudWatch Container Insights on the app's cluster (billed per metric). Ignored in shared-platform mode. | `bool` | `false` | no |
| container\_port | n/a | `number` | `8080` | no |
| cpu | n/a | `number` | `512` | no |
| cpu\_architecture | `X86_64` (default) or `ARM64` (Graviton: about 20% cheaper, and native builds on Apple Silicon). deploy-app builds the image for it. | `string` | `"X86_64"` | no |
| create\_waf | Create a WAF web ACL (per-IP rate limit + AWS managed rules) on the ALB. About $5/month + $1/rule + $0.60 per million requests. | `bool` | `false` | no |
| db\_allocated\_storage | n/a | `number` | `20` | no |
| db\_backup\_retention\_days | n/a | `number` | `1` | no |
| db\_deletion\_protection | n/a | `bool` | `false` | no |
| db\_engine\_version | n/a | `string` | `"16.11"` | no |
| db\_iam\_database\_authentication\_enabled | n/a | `bool` | `false` | no |
| db\_instance\_class | n/a | `string` | `"db.t4g.micro"` | no |
| db\_log\_min\_duration\_ms | Log Postgres statements slower than this many ms (0 = all, null = off). Takes effect after the instance's next reboot. | `number` | `null` | no |
| db\_monitoring\_interval | Enhanced monitoring interval in seconds (0 = off). | `number` | `0` | no |
| db\_multi\_az | n/a | `bool` | `false` | no |
| db\_name | ── Database tuning ──────────────────────────────────── | `string` | `"appdb"` | no |
| db\_performance\_insights\_enabled | Performance Insights, kept for the free 7 days. | `bool` | `false` | no |
| db\_skip\_final\_snapshot | n/a | `bool` | `true` | no |
| desired\_count | n/a | `number` | `1` | no |
| dmarc\_policy | DMARC policy: none \| quarantine \| reject | `string` | `"none"` | no |
| dmarc\_rua\_email | DMARC report address (required when enable\_email=true) | `string` | `""` | no |
| dns\_query\_log\_retention\_days | n/a | `number` | `30` | no |
| enable\_cache | n/a | `bool` | `false` | no |
| enable\_database | ── Toggles ──────────────────────────────────────────── | `bool` | `false` | no |
| enable\_dns\_query\_logging | Log the DNS queries Route53 answers for the stack's zone to CloudWatch in us-east-1 (billed per GB). | `bool` | `false` | no |
| enable\_dnssec | Sign the stack's zone with DNSSEC. After apply, publish the dnssec\_ds\_record output at the registrar; turning it off later needs the order in docs/dnssec.md. | `bool` | `false` | no |
| enable\_email | n/a | `bool` | `false` | no |
| enable\_flow\_logs | Send VPC flow logs to CloudWatch (billed per GB). Ignored in shared-platform mode, where the host owns the VPC. | `bool` | `false` | no |
| enable\_nat\_gateway | Provision a NAT gateway (~$33/month). Ignored in shared-platform mode, where<br/>the host platform's networking already decides this.<br/><br/>Set false together with `tasks_in_public_subnets = true` to remove the single<br/>largest fixed cost of a small stack. | `bool` | `true` | no |
| env | n/a | `map(string)` | `{}` | no |
| existing\_zone\_name | Name of an EXISTING public Route53 hosted zone (e.g. "example.com") to place this app's records in.<br/>Empty (default) = DevOpsFoundry creates a zone for domain\_name and delegates the domain's Namecheap<br/>nameservers to it. When set, no zone is created and the registrar is never touched: the ACM cert covers<br/>exactly the service hostname (no wildcard), and only its validation and alias records are added, never<br/>overwriting existing ones. For hosting an app under a domain whose DNS already serves something else. | `string` | `""` | no |
| flow\_log\_retention\_days | n/a | `number` | `30` | no |
| flow\_log\_traffic\_type | ACCEPT, REJECT or ALL; see the networking module. | `string` | `"ALL"` | no |
| health\_check\_interval | n/a | `number` | `15` | no |
| health\_check\_matcher | n/a | `string` | `"200"` | no |
| health\_check\_path | n/a | `string` | `"/health"` | no |
| health\_check\_timeout | n/a | `number` | `5` | no |
| kms\_key\_arn | One customer managed KMS key for the stack's Redis data, the Redis auth and SMTP secrets, the app's logs and the flow logs. null (default) = AWS-managed keys. The key policy must allow logs.<region>.amazonaws.com; tasks get kms:Decrypt automatically. Setting it on an existing cache REPLACES the cache. | `string` | `null` | no |
| listener\_rule\_priority\_base | First ALB listener-rule priority to claim in shared mode; each guest app needs a distinct base | `number` | `100` | no |
| mail\_from\_subdomain | Custom MAIL FROM subdomain label for SPF alignment (e.g. 'mail'). Empty = SES default. | `string` | `""` | no |
| manage\_nameservers | Whether Terraform manages the domain's Namecheap nameserver delegation to the Route53 zone (ignored when<br/>existing\_zone\_name is set). The delegation is set once and never changes, but managing it makes every plan<br/>call the Namecheap API, which only answers whitelisted IPs. Set false after the first apply so deploys<br/>never need Namecheap. On an existing stack, first run<br/>`terraform state rm 'module.<name>.module.namecheap_ns[0].namecheap_domain_records.ns'`; without it,<br/>Terraform deletes the delegation. (A `removed` block can't do this: the module block is still declared.) | `bool` | `true` | no |
| memory | n/a | `number` | `1024` | no |
| secrets | n/a | `map(string)` | `{}` | no |
| service\_name | Short container/service name | `string` | `"app"` | no |
| shared\_platform | Slug of an EXISTING DevOpsFoundry app whose VPC, NAT gateway, ALB and ECS<br/>cluster this app should share (e.g. "other-app-com"). Empty (the default)<br/>provisions dedicated infrastructure.<br/><br/>Sharing removes the two largest fixed costs — NAT (~$33/mo) and ALB<br/>(~$16/mo) — at the price of a shared failure domain with the host platform.<br/>A database, when enabled, is still this app's own. | `string` | `""` | no |
| subdomain | Subdomain fronting the service (api -> api.example.com). Empty or "@" serves at the apex (example.com). | `string` | `"api"` | no |
| tasks\_in\_public\_subnets | Run ECS tasks in public subnets with public IPs (no NAT needed). Inbound stays ALB-only. In shared-platform mode this must match the host: true if the host has no NAT gateway (the plan fails otherwise). | `bool` | `false` | no |
| vpc\_cidr | ── Networking ───────────────────────────────────────── | `string` | `"10.0.0.0/16"` | no |
| waf\_count\_only | Count WAF matches without blocking. Start here on a live ALB, then set false to enforce. | `bool` | `false` | no |
| waf\_managed\_rule\_groups | AWS managed rule groups to apply, in order. | `list(string)` | <pre>[<br/>  "AWSManagedRulesAmazonIpReputationList",<br/>  "AWSManagedRulesCommonRuleSet",<br/>  "AWSManagedRulesKnownBadInputsRuleSet"<br/>]</pre> | no |
| waf\_rate\_limit | Requests per client IP per 5 minutes before the rate rule blocks it, across every host on the ALB. | `number` | `2000` | no |
| waf\_rule\_overrides | Managed rules to count instead of block, keyed by rule group, e.g. { AWSManagedRulesCommonRuleSet = ["SizeRestrictions\_BODY"] }. | `map(list(string))` | `{}` | no |
| waf\_web\_acl\_arn | Attach an existing regional web ACL to the ALB instead of creating one. Mutually exclusive with create\_waf. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cpu\_architecture | CPU architecture the app's tasks run on; deploy-app builds the image for it |
| db\_address | RDS endpoint address (null without enable\_database) |
| db\_master\_secret\_arn | Secrets Manager ARN of the RDS-managed master credential (rotates every 7 days by default) |
| db\_name | n/a |
| db\_port | n/a |
| dns\_query\_log\_group\_name | CloudWatch log group (us-east-1) with the zone's DNS query logs (null when off) |
| dnssec\_ds\_record | DS record to publish at the registrar when enable\_dnssec = true (null otherwise) |
| dnssec\_ds\_record\_fields | The DS record's parts for registrars that ask for them separately, such as Namecheap (null when DNSSEC is off) |
| ecr\_repository\_url | n/a |
| ecs\_cluster\_name | n/a |
| ecs\_service\_name | n/a |
| health\_check\_path | Path deploy-app curls after rollout |
| log\_group | n/a |
| name\_servers | Route53 nameservers delegated at Namecheap |
| private\_subnet\_ids | n/a |
| rds\_security\_group\_id | Security group on the RDS instance; add ingress rules here for companion services |
| service\_url | n/a |
| task\_security\_group\_id | Security group attached to this app's ECS tasks |
| waf\_web\_acl\_arn | Web ACL attached to the ALB this stack owns (empty when none, or in shared-platform mode) |
<!-- END_TF_DOCS -->
