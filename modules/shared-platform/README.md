# shared-platform

Looks up an existing DevOpsFoundry app's VPC, subnets, NAT, ALB and ECS cluster by naming convention, so another app can attach to them instead of paying for its own. Read-only: it creates the guest app's own security groups only.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| aws | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_security_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.redis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.api_ingress_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.rds_ingress_from_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.redis_ingress_from_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_ecs_cluster.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecs_cluster) | data source |
| [aws_lb.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/lb) | data source |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/lb_listener) | data source |
| [aws_security_group.platform_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/security_group) | data source |
| [aws_subnets.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_subnets.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnets) | data source |
| [aws_vpc.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Resource-name prefix for THIS app (app slug) | `string` | n/a | yes |
| platform\_name | Slug of an EXISTING DevOpsFoundry app whose VPC, NAT, ALB and ECS cluster<br/>this app should share (e.g. "other-app-com"). Resources are located by this<br/>tool's own naming conventions — see main.tf. | `string` | n/a | yes |
| cache\_port | Redis port | `number` | `6379` | no |
| container\_port | Port the app container listens on | `number` | `8080` | no |
| db\_port | Postgres port | `number` | `5432` | no |
| enable\_cache | Create the Redis security group + ingress rule | `bool` | `false` | no |
| enable\_database | Create the RDS security group + ingress rule | `bool` | `false` | no |
| https\_listener\_port | Port of the shared ALB's HTTPS listener | `number` | `443` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_arn | n/a |
| alb\_dns\_name | n/a |
| alb\_security\_group\_id | The platform's ALB security group (read-only) |
| alb\_zone\_id | n/a |
| api\_security\_group\_id | This app's own task security group |
| ecs\_cluster\_arn | n/a |
| ecs\_cluster\_name | n/a |
| https\_listener\_arn | n/a |
| private\_subnet\_ids | Shared private subnet IDs (for this app's tasks, RDS, Redis) |
| public\_subnet\_ids | Shared public subnet IDs (the platform's ALB already lives here) |
| rds\_security\_group\_id | This app's own RDS SG id, or null when database disabled |
| redis\_security\_group\_id | This app's own Redis SG id, or null when cache disabled |
| vpc\_id | n/a |
<!-- END_TF_DOCS -->
