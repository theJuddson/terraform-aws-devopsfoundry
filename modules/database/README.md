# database

RDS PostgreSQL with an AWS-managed master password in Secrets Manager. Defaults favor easy teardown (deletion protection off, no final snapshot); turn both on for data you keep.

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
| [aws_db_instance.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Resource-name prefix (app slug) | `string` | n/a | yes |
| private\_subnet\_ids | n/a | `list(string)` | n/a | yes |
| rds\_security\_group\_id | n/a | `string` | n/a | yes |
| allocated\_storage | n/a | `number` | `20` | no |
| backup\_retention\_days | n/a | `number` | `1` | no |
| db\_name | Initial database name (Postgres identifier: letters/digits/underscore) | `string` | `"appdb"` | no |
| db\_port | n/a | `number` | `5432` | no |
| deletion\_protection | Block accidental deletion (set true for prod databases) | `bool` | `false` | no |
| engine\_version | n/a | `string` | `"16.11"` | no |
| instance\_class | n/a | `string` | `"db.t4g.micro"` | no |
| master\_username | n/a | `string` | `"appuser"` | no |
| max\_allocated\_storage | n/a | `number` | `100` | no |
| multi\_az | n/a | `bool` | `false` | no |
| skip\_final\_snapshot | Skip the final snapshot on destroy (true = easy teardown) | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| address | RDS hostname |
| db\_name | n/a |
| master\_user\_secret\_arn | ARN of the RDS-managed master password secret (JSON: username/password) |
| port | n/a |
<!-- END_TF_DOCS -->
