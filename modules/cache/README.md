# cache

ElastiCache Redis: a single encrypted node with a generated auth token. `full-stack` stores the token in Secrets Manager and injects `REDIS_PASSWORD` into the container.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.0 |
| random | >= 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.0 |
| random | >= 3.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_elasticache_replication_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_replication_group) | resource |
| [aws_elasticache_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group) | resource |
| [random_password.auth_token](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Resource-name prefix (app slug) | `string` | n/a | yes |
| private\_subnet\_ids | n/a | `list(string)` | n/a | yes |
| redis\_security\_group\_id | n/a | `string` | n/a | yes |
| auth\_token\_generation | Bump to generate a new auth token (bin/rotate-secret does this). 0 keeps the token made at creation. | `number` | `0` | no |
| auth\_token\_update\_strategy | How a token change is applied: ROTATE keeps the old token valid too, SET makes the current token the only one. null leaves the provider default. Set by bin/rotate-secret. | `string` | `null` | no |
| cache\_port | n/a | `number` | `6379` | no |
| engine\_version | n/a | `string` | `"7.1"` | no |
| kms\_key\_arn | Customer managed KMS key for encryption at rest. null (default) = the AWS-managed key. Changing it on an existing cache REPLACES the replication group (data is lost). | `string` | `null` | no |
| node\_type | n/a | `string` | `"cache.t4g.micro"` | no |
| num\_cache\_clusters | Nodes in the replication group. 1 is a single node; 2 or more adds replicas in other AZs with automatic failover (each node is billed). | `number` | `1` | no |
| parameter\_group\_name | n/a | `string` | `"default.redis7"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| auth\_token | Generated Redis AUTH token |
| auth\_token\_rotation | Where token rotation stands: the token generation and the update strategy last applied (bin/rotate-secret). |
| port | n/a |
| primary\_endpoint | Redis primary endpoint hostname |
<!-- END_TF_DOCS -->
