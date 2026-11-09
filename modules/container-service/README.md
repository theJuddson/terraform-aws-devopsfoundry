# container-service

A containerized service on ECS Fargate behind an HTTPS ALB, framework-neutral: you supply plaintext `env` and `secrets` (env name to Secrets Manager ARN). Creates the ECR repository, log group, IAM roles, ALB and listeners, ECS cluster, service and task definition, and an alias record at `<subdomain>.<domain>` or the apex. Can attach to a shared ALB and cluster instead (see `shared-platform`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.60 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.60 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| ecr | ../ecr-repository | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_service.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task_execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.task_execution_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.task_execution_managed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lb.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_certificate.shared](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_certificate) | resource |
| [aws_lb_listener_rule.host_forward](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.www_redirect](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.www](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_s3_bucket.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_ownership_controls.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_wafv2_web_acl.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [aws_wafv2_web_acl_association.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_elb_service_account.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |
| [aws_iam_policy_document.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecs_tasks_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.task_execution_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alb\_security\_group\_id | n/a | `string` | n/a | yes |
| api\_security\_group\_id | n/a | `string` | n/a | yes |
| certificate\_arn | Validated ACM cert ARN (us-east-1) covering the service FQDN | `string` | n/a | yes |
| domain\_name | Apex domain | `string` | n/a | yes |
| name | Resource-name prefix (app slug) | `string` | n/a | yes |
| private\_subnet\_ids | n/a | `list(string)` | n/a | yes |
| public\_subnet\_ids | n/a | `list(string)` | n/a | yes |
| vpc\_id | ── Networking wiring ────────────────────────────────── | `string` | n/a | yes |
| zone\_id | Route53 hosted zone ID for the domain | `string` | n/a | yes |
| alb\_access\_logs | Write ALB access logs to S3. Creates a private, SSE-S3 encrypted bucket <name>-alb-logs-<account> unless alb\_access\_logs\_bucket names one. Ignored when create\_alb = false. | `bool` | `false` | no |
| alb\_access\_logs\_bucket | Existing bucket for the ALB access logs, which must already allow ELB log delivery (see AWS's ALB access logs guide). Empty (default) = create one. | `string` | `""` | no |
| alb\_access\_logs\_retention\_days | Days to keep access logs in the bucket this module creates. | `number` | `90` | no |
| alb\_deletion\_protection | Block deleting the ALB until this is set back to false. Leave off if you tear stacks down with destroy-app. Ignored when create\_alb = false. | `bool` | `false` | no |
| container\_image | Image URI. Empty -> the module's own ECR repo :latest tag. | `string` | `""` | no |
| container\_insights | Turn on CloudWatch Container Insights for the cluster (billed per metric). Ignored when create\_cluster = false. | `bool` | `false` | no |
| container\_port | n/a | `number` | `8080` | no |
| cpu | Fargate task CPU units (256/512/1024/...) | `number` | `512` | no |
| cpu\_architecture | `X86_64` (default) or `ARM64` (Graviton, about 20% cheaper per vCPU-hour). The image must be built for it; deploy-app reads the cpu\_architecture output to do that. Changing it replaces the task definition (a normal rolling deploy). | `string` | `"X86_64"` | no |
| create\_alb | Create a dedicated ALB. False = attach to an existing one via existing\_*. | `bool` | `true` | no |
| create\_cluster | Create a dedicated ECS cluster. False = run in an existing one. | `bool` | `true` | no |
| create\_waf | Create a regional WAF web ACL and attach it to the ALB: a per-IP rate limit<br/>plus the AWS managed rule groups in waf\_managed\_rule\_groups. Costs about<br/>$5/month per web ACL + $1/month per rule + $0.60 per million requests.<br/>Ignored when create\_alb = false. | `bool` | `false` | no |
| desired\_count | Running task count. new-app provisions at 0; deploy-app scales up. | `number` | `1` | no |
| env | Plaintext environment variables injected into the container | `map(string)` | `{}` | no |
| existing\_alb\_dns\_name | DNS name of the shared ALB (required when create\_alb = false) | `string` | `""` | no |
| existing\_alb\_zone\_id | Hosted-zone id of the shared ALB (required when create\_alb = false) | `string` | `""` | no |
| existing\_cluster\_arn | ARN of the shared ECS cluster (required when create\_cluster = false) | `string` | `""` | no |
| existing\_cluster\_name | Name of the shared ECS cluster (required when create\_cluster = false) | `string` | `""` | no |
| existing\_https\_listener\_arn | ARN of the shared ALB's HTTPS listener (required when create\_alb = false) | `string` | `""` | no |
| health\_check\_interval | n/a | `number` | `15` | no |
| health\_check\_matcher | n/a | `string` | `"200"` | no |
| health\_check\_path | ── Health check ─────────────────────────────────────── | `string` | `"/health"` | no |
| health\_check\_timeout | n/a | `number` | `5` | no |
| listener\_rule\_priority\_base | First listener-rule priority to claim on a shared ALB. This app uses<br/><base> for its host-header forward and <base>+1 for the www redirect, so<br/>each guest app on the same listener needs a distinct base. Ignored when<br/>create\_alb = true. | `number` | `100` | no |
| log\_kms\_key\_arn | Customer managed KMS key for the app's CloudWatch log group. null (default) = CloudWatch's default encryption. The key policy must allow logs.<region>.amazonaws.com (see AWS's CloudWatch Logs encryption guide). | `string` | `null` | no |
| log\_retention\_days | n/a | `number` | `14` | no |
| memory | Fargate task memory (MiB) | `number` | `1024` | no |
| secrets | Secret env vars: ENV\_NAME -> Secrets Manager valueFrom ARN (supports :json\_key:: selector) | `map(string)` | `{}` | no |
| secrets\_kms\_key\_arns | Customer managed KMS keys that encrypt any of `secrets`. The task execution role gets kms:Decrypt on them, which it needs to read those secrets at start. | `list(string)` | `[]` | no |
| service\_name | Container/service short name (used in ECR repo, log group, container name) | `string` | `"app"` | no |
| subdomain | Subdomain that fronts the service (api -> api.example.com). Empty or "@" serves at the apex (example.com). | `string` | `"api"` | no |
| tasks\_in\_public\_subnets | Run ECS tasks in the public subnets with public IPs, so the VPC needs no NAT<br/>gateway. Pair with networking's `enable_nat_gateway = false`.<br/><br/>Safe because the task security group admits inbound traffic only from the<br/>ALB. Do not enable if anything downstream allowlists this app's outbound IP —<br/>egress moves from the NAT's stable Elastic IP to per-task ephemeral IPs. | `bool` | `false` | no |
| waf\_count\_only | Run every WAF rule in count mode: matches are counted in CloudWatch metrics<br/>and sampled requests, nothing is blocked. Start here on a live ALB, check the<br/>counts, then set false to enforce. | `bool` | `false` | no |
| waf\_managed\_rule\_groups | AWS managed rule groups (vendor AWS) to apply, in order. The defaults are<br/>free of extra subscription charges: the core rule set (OWASP-style checks),<br/>known bad inputs (e.g. Log4Shell) and Amazon's IP reputation list. | `list(string)` | <pre>[<br/>  "AWSManagedRulesAmazonIpReputationList",<br/>  "AWSManagedRulesCommonRuleSet",<br/>  "AWSManagedRulesKnownBadInputsRuleSet"<br/>]</pre> | no |
| waf\_rate\_limit | Requests per client IP per 5 minutes before the rate rule blocks that IP<br/>(AWS minimum 10). Counts every host on the ALB together, so size it for the<br/>busiest legitimate client, e.g. an office behind one NAT using several apps. | `number` | `2000` | no |
| waf\_rule\_overrides | Individual managed rules to run in count mode instead of blocking, keyed by<br/>rule group, e.g. { AWSManagedRulesCommonRuleSet = ["SizeRestrictions\_BODY"] }<br/>when an app legitimately accepts request bodies over 8 KB. | `map(list(string))` | `{}` | no |
| waf\_web\_acl\_arn | Attach this existing regional web ACL to the ALB instead of creating one. Mutually exclusive with create\_waf. Ignored when create\_alb = false. | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_dns\_name | The ALB serving this app — dedicated or shared |
| cpu\_architecture | CPU architecture the tasks run on (X86\_64 or ARM64); build images for it |
| ecr\_repository\_url | n/a |
| ecs\_cluster\_name | n/a |
| ecs\_service\_name | n/a |
| log\_group | n/a |
| service\_fqdn | n/a |
| service\_url | n/a |
| task\_role\_arn | IAM role assumed by the app container (attach extra policies here) |
| waf\_web\_acl\_arn | The web ACL attached to this app's ALB: created (create\_waf), supplied (waf\_web\_acl\_arn), or empty |
<!-- END_TF_DOCS -->
