# project-access

A role for someone who works on one project in an AWS account that other projects share. It can open shells and
run commands on the project's instances (SSM), read the project's log groups, alarms, ECS and ECR, and optionally
costs. The project is whatever carries `project_tag_key` = one of `project_tag_values`, plus the log groups under
`log_group_prefixes`. With `user_name` it also makes an IAM user that can do nothing but manage its own password
and MFA and assume the role with MFA.

```hcl
module "collaborator" {
  source             = "theJuddson/devopsfoundry/aws//modules/project-access"
  version            = "~> 1.10"
  name               = "agents-collaborator"
  project_tag_values = ["agents"]
  log_group_prefixes = ["/agents/"]
  user_name          = "tayler"
}
```

Give the user a console password with `aws iam create-login-profile --user-name tayler --password-reset-required`;
they add MFA themselves, then use `switch_role_url`.

**What a tag boundary can't do.** In a shared account some reads have no resource-level permissions, so the role
sees the names of every project's instances, clusters, alarms and log groups. Cost Explorer can't be limited to a
tag, so `allow_cost_explorer` shows every project's costs. A command through SSM runs as root on the instance with
its instance role's rights. The role can't change tags, so it can't pull another project's resources into its
boundary. When the project needs a real boundary, give it its own account (`organization` and `identity-center`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0 |
| aws | >= 5.60 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.60 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.project](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user) | resource |
| [aws_iam_user_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_user_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Role name, e.g. agents-collaborator | `string` | n/a | yes |
| project\_tag\_values | Values of project\_tag\_key that belong to the project, e.g. ["agents"] | `list(string)` | n/a | yes |
| allow\_cost\_explorer | Cost Explorer read. It can't be limited to a tag, so this shows every project's costs in the account. | `bool` | `false` | no |
| allow\_ssm | Shells (Session Manager) and commands (SendCommand) on the project's instances. Both run as root there. | `bool` | `true` | no |
| extra\_policy\_json | A further inline policy for project-specific needs (a deploy bucket, SSM parameters under the project's path, ...) | `string` | `null` | no |
| log\_group\_prefixes | CloudWatch log group name prefixes the role may read, e.g. ["/agents/", "/ecs/agents-"]. Empty = no log access. | `list(string)` | `[]` | no |
| max\_session\_hours | n/a | `number` | `4` | no |
| path | n/a | `string` | `"/people/"` | no |
| project\_tag\_key | Tag that marks the project's resources | `string` | `"project"` | no |
| require\_mfa | Only sessions signed in with MFA may assume the role | `bool` | `true` | no |
| ssm\_documents | AWS-owned SSM documents SendCommand may run on the project's instances | `list(string)` | <pre>[<br/>  "AWS-RunShellScript"<br/>]</pre> | no |
| trusted\_principal\_arns | IAM principals that may assume the role, such as an existing user or another account's root | `list(string)` | `[]` | no |
| user\_name | Make an IAM user (under /people/) that can only manage its own MFA and assume this role with MFA. null = no user. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| policy\_json | The role's project policy, for review |
| role\_arn | n/a |
| role\_name | n/a |
| switch\_role\_url | Console link that switches a signed-in user into the role |
| user\_name | n/a |
<!-- END_TF_DOCS -->
