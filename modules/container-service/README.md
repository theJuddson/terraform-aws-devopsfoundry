# container-service

A containerized service on ECS Fargate behind an HTTPS ALB, framework-neutral: you supply plaintext `env` and `secrets` (env name to Secrets Manager ARN). Creates the ECR repository, log group, IAM roles, ALB and listeners, ECS cluster, service and task definition, and an alias record at `<subdomain>.<domain>` or the apex. Can attach to a shared ALB and cluster instead (see `shared-platform`).

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| aws | n/a |

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
| container\_image | Image URI. Empty -> the module's own ECR repo :latest tag. | `string` | `""` | no |
| container\_port | n/a | `number` | `8080` | no |
| cpu | Fargate task CPU units (256/512/1024/...) | `number` | `512` | no |
| create\_alb | Create a dedicated ALB. False = attach to an existing one via existing\_*. | `bool` | `true` | no |
| create\_cluster | Create a dedicated ECS cluster. False = run in an existing one. | `bool` | `true` | no |
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
| log\_retention\_days | n/a | `number` | `14` | no |
| memory | Fargate task memory (MiB) | `number` | `1024` | no |
| secrets | Secret env vars: ENV\_NAME -> Secrets Manager valueFrom ARN (supports :json\_key:: selector) | `map(string)` | `{}` | no |
| service\_name | Container/service short name (used in ECR repo, log group, container name) | `string` | `"app"` | no |
| subdomain | Subdomain that fronts the service (api -> api.example.com). Empty or "@" serves at the apex (example.com). | `string` | `"api"` | no |
| tasks\_in\_public\_subnets | Run ECS tasks in the public subnets with public IPs, so the VPC needs no NAT<br/>gateway. Pair with networking's `enable_nat_gateway = false`.<br/><br/>Safe because the task security group admits inbound traffic only from the<br/>ALB. Do not enable if anything downstream allowlists this app's outbound IP —<br/>egress moves from the NAT's stable Elastic IP to per-task ephemeral IPs. | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_dns\_name | The ALB serving this app — dedicated or shared |
| ecr\_repository\_url | n/a |
| ecs\_cluster\_name | n/a |
| ecs\_service\_name | n/a |
| log\_group | n/a |
| service\_fqdn | n/a |
| service\_url | n/a |
| task\_role\_arn | IAM role assumed by the app container (attach extra policies here) |
<!-- END_TF_DOCS -->
