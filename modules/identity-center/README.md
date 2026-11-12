# identity-center

People's access to an organization's accounts through IAM Identity Center, AWS's own sign-in: users and groups in
its identity store, permission sets, and which permission set each person or group gets in which account. Nobody
gets an IAM user or long-lived keys; they sign in at the access portal with MFA, and the CLI uses
`aws configure sso`.

```hcl
module "access" {
  source  = "theJuddson/devopsfoundry/aws//modules/identity-center"
  version = "~> 1.10"
  users = {
    tayler = { given_name = "Tayler", family_name = "Example", email = "tayler@example.com" }
  }
  permission_sets = {
    AdministratorAccess = { managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"] }
  }
  assignments = [
    { permission_set = "AdministratorAccess", account_id = module.org.account_ids["agents"], user = "tayler" },
  ]
}
```

- Apply it in the management account, in Identity Center's region.
- Turn Identity Center on once in the console first (IAM Identity Center > Enable, with AWS Organizations). AWS has
  no API for that step; until it's done the plan stops and says so.
- A new user gets an email invitation to set a password and MFA.

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
| [aws_identitystore_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group) | resource |
| [aws_identitystore_group_membership.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_group_membership) | resource |
| [aws_identitystore_user.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/identitystore_user) | resource |
| [aws_ssoadmin_account_assignment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_account_assignment) | resource |
| [aws_ssoadmin_managed_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_managed_policy_attachment) | resource |
| [aws_ssoadmin_permission_set.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set) | resource |
| [aws_ssoadmin_permission_set_inline_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssoadmin_permission_set_inline_policy) | resource |
| [aws_ssoadmin_instances.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssoadmin_instances) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| assignments | Who gets which permission set in which account. Each names exactly one of user (a key of users) or group (a key of groups). | <pre>list(object({<br/>    permission_set = string<br/>    account_id     = string<br/>    user           = optional(string)<br/>    group          = optional(string)<br/>  }))</pre> | `[]` | no |
| groups | Groups by name, each with the user keys in it. | <pre>map(object({<br/>    description = optional(string)<br/>    members     = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| permission\_sets | Permission sets by name: AWS managed or customer policies to attach, an optional inline policy (JSON), and how long a sign-in lasts (ISO 8601, PT1H to PT12H). | <pre>map(object({<br/>    description         = optional(string)<br/>    session_duration    = optional(string, "PT8H")<br/>    managed_policy_arns = optional(list(string), [])<br/>    inline_policy       = optional(string)<br/>  }))</pre> | `{}` | no |
| users | People who sign in, keyed by a short name used in groups and assignments. The email is their user name and where Identity Center sends the invitation. | <pre>map(object({<br/>    given_name   = string<br/>    family_name  = string<br/>    email        = string<br/>    display_name = optional(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| assignments | Each assignment as permission set \| account \| principal |
| identity\_store\_id | n/a |
| instance\_arn | n/a |
| permission\_set\_arns | n/a |
| user\_ids | Identity store user IDs by user key |
<!-- END_TF_DOCS -->
