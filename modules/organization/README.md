# organization

An AWS Organization run from the account you apply it in, which becomes the management account, and member
accounts made in it. Give a venture its own account when it needs its own boundary: its own bill, its own people
(through the `identity-center` module), and nothing it can reach in your other ventures.

```hcl
module "org" {
  source  = "theJuddson/devopsfoundry/aws//modules/organization"
  version = "~> 1.10"
  accounts = {
    agents = { email = "you+agents@example.com", tags = { project = "agents" } }
  }
}
```

- Each account needs an email no other AWS account uses; a plus-address works.
- An organization that already exists is imported (`import { to = module.org.aws_organizations_organization.this
  id = "o-..." }`), as are existing accounts (`id = "<account id>"`).
- Terraform never destroys an account (`prevent_destroy`, `close_on_deletion = false`). Closing one takes 90 days.
  To stop managing one, use a `removed` block, then close it in the console if you mean to.
- AWS creates `OrganizationAccountAccessRole` in each new account, trusting the management account. Build inside a
  member account with a provider that assumes `member_admin_role_arns["<name>"]`.

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
| [aws_organizations_account.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_account) | resource |
| [aws_organizations_organization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organization) | resource |
| [aws_organizations_organizational_unit.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/organizations_organizational_unit) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| accounts | Member accounts, keyed by account name. Each needs an email no other AWS account uses (a plus-address works). organizational\_unit names one in organizational\_units; null puts it at the root. | <pre>map(object({<br/>    email                      = string<br/>    organizational_unit        = optional(string)<br/>    iam_user_access_to_billing = optional(bool, true)<br/>    tags                       = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| enabled\_policy\_types | Organization policy types to turn on, e.g. SERVICE\_CONTROL\_POLICY. Empty by default: SCPs never apply to the management account, so they only matter once workloads live in member accounts. | `list(string)` | `[]` | no |
| member\_admin\_role\_name | Role AWS creates in each new member account, trusting the management account with full admin. Used only until Identity Center access works, and for break-glass. | `string` | `"OrganizationAccountAccessRole"` | no |
| organizational\_units | Organizational units directly under the root, by name. Empty = accounts sit at the root. | `set(string)` | `[]` | no |
| service\_access\_principals | AWS services trusted across the organization. sso.amazonaws.com is what IAM Identity Center needs; account.amazonaws.com lets the management account manage members' contact details. | `list(string)` | <pre>[<br/>  "sso.amazonaws.com",<br/>  "account.amazonaws.com"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| account\_ids | Member account IDs by account name |
| management\_account\_id | n/a |
| member\_admin\_role\_arns | The admin role in each member account, by account name: what a provider's assume\_role uses to build inside it |
| organization\_id | n/a |
| organizational\_unit\_ids | n/a |
| root\_id | n/a |
<!-- END_TF_DOCS -->
