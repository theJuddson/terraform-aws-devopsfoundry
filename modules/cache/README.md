# cache

ElastiCache Redis: a single encrypted node with a generated auth token. `full-stack` stores the token in Secrets Manager and injects `REDIS_PASSWORD` into the container.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| aws | n/a |
| random | n/a |

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
| cache\_port | n/a | `number` | `6379` | no |
| engine\_version | n/a | `string` | `"7.1"` | no |
| node\_type | n/a | `string` | `"cache.t4g.micro"` | no |
| parameter\_group\_name | n/a | `string` | `"default.redis7"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| auth\_token | Generated Redis AUTH token |
| port | n/a |
| primary\_endpoint | Redis primary endpoint hostname |
<!-- END_TF_DOCS -->
