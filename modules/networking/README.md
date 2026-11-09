# networking

A VPC with public and private subnets, an optional single NAT gateway, and security groups for the ALB, the app and (when enabled) RDS and Redis.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_iam_role.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.flow_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_internet_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.redis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.api_ingress_from_alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.rds_ingress_from_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.redis_ingress_from_api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_iam_policy_document.flow_logs_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.flow_logs_write](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Resource-name prefix (app slug) | `string` | n/a | yes |
| az\_count | Number of availability zones to span | `number` | `2` | no |
| cache\_port | Redis port | `number` | `6379` | no |
| container\_port | Port the app container listens on | `number` | `8080` | no |
| db\_port | Postgres port | `number` | `5432` | no |
| enable\_cache | Create the Redis security group + ingress rule | `bool` | `false` | no |
| enable\_database | Create the RDS security group + ingress rule | `bool` | `false` | no |
| enable\_flow\_logs | Send VPC flow logs to a CloudWatch log group. Billed per GB ingested and stored. | `bool` | `false` | no |
| enable\_nat\_gateway | Provision a NAT gateway (~$33/month) so private-subnet tasks can reach the<br/>internet. Set false together with container-service's<br/>`tasks_in_public_subnets` to drop that cost: tasks then run in public subnets<br/>with public IPs, still admitting inbound traffic only from the ALB.<br/><br/>Databases stay in the private subnets either way; they need no egress. | `bool` | `true` | no |
| flow\_log\_kms\_key\_arn | Customer managed KMS key for the flow log group. null (default) = CloudWatch's default encryption. The key policy must allow logs.<region>.amazonaws.com. | `string` | `null` | no |
| flow\_log\_retention\_days | Days to keep flow logs. Must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, ...). | `number` | `30` | no |
| flow\_log\_traffic\_type | Which traffic the flow logs record: ACCEPT, REJECT or ALL. REJECT is the cheapest way to see blocked connections. | `string` | `"ALL"` | no |
| vpc\_cidr | CIDR block for the VPC | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alb\_security\_group\_id | n/a |
| api\_security\_group\_id | n/a |
| flow\_log\_group\_name | CloudWatch log group holding the VPC flow logs (null when enable\_flow\_logs = false) |
| private\_subnet\_ids | Private subnet IDs (for ECS, RDS, Redis) |
| public\_subnet\_ids | Public subnet IDs (for the ALB) |
| rds\_security\_group\_id | RDS SG id, or null when database disabled |
| redis\_security\_group\_id | Redis SG id, or null when cache disabled |
| vpc\_id | n/a |
<!-- END_TF_DOCS -->
