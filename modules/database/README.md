# database

RDS PostgreSQL with an AWS-managed master password in Secrets Manager. Defaults favor easy teardown (deletion protection off, no final snapshot); turn both on for data you keep.

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
| [aws_db_instance.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_policy_document.monitoring_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

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
| iam\_database\_authentication\_enabled | Also accept IAM authentication tokens as database passwords. The RDS-managed password keeps working. | `bool` | `false` | no |
| instance\_class | n/a | `string` | `"db.t4g.micro"` | no |
| log\_min\_duration\_ms | Log every statement that runs at least this many milliseconds (Postgres<br/>log\_min\_duration\_statement); 0 logs all statements. null (default) = off,<br/>and the instance keeps AWS's default parameter group. The logs go to the<br/>CloudWatch log group RDS already exports (/aws/rds/instance/<name>-postgres/postgresql).<br/><br/>Moving an existing instance onto the new parameter group takes effect after<br/>its next reboot; RDS shows it as pending-reboot until then. | `number` | `null` | no |
| master\_username | n/a | `string` | `"appuser"` | no |
| max\_allocated\_storage | n/a | `number` | `100` | no |
| monitoring\_interval | Seconds between enhanced monitoring samples (0 = off; 1, 5, 10, 15, 30 or 60). Creates the monitoring role when on. Billed as CloudWatch Logs. | `number` | `0` | no |
| multi\_az | n/a | `bool` | `false` | no |
| performance\_insights\_enabled | Turn on Performance Insights, kept for the free 7 days. | `bool` | `false` | no |
| skip\_final\_snapshot | Skip the final snapshot on destroy (true = easy teardown) | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| address | RDS hostname |
| db\_name | n/a |
| master\_user\_secret\_arn | ARN of the RDS-managed master password secret (JSON: username/password) |
| port | n/a |
<!-- END_TF_DOCS -->
