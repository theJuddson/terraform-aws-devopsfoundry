# budget-alarm

A monthly cost budget in AWS Budgets. By default it notifies at 80% and 100% of actual spend and at 100% of
forecast spend, by email, to an SNS topic, or both. Narrow it to one app's costs with `cost_filters`, for example
by a cost allocation tag.

```hcl
module "budget" {
  source          = "theJuddson/devopsfoundry/aws//modules/budget-alarm"
  version         = "~> 1.2"
  name            = "my-app-monthly"
  monthly_limit   = 300
  email_addresses = ["ops@example.com"]
}
```

Budgets are evaluated a few times a day, so an alarm can arrive hours after the spend. For an SNS topic, its access
policy must allow `budgets.amazonaws.com` to `SNS:Publish`, and an encrypted topic's key must let that service use
it.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
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
| [aws_budgets_budget.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| monthly\_limit | Monthly budget amount. | `number` | n/a | yes |
| name | Budget name, unique in the account. | `string` | n/a | yes |
| actual\_thresholds\_percent | Notify when actual spend this month passes each of these percentages of the limit. | `list(number)` | <pre>[<br/>  80,<br/>  100<br/>]</pre> | no |
| cost\_filters | Limit the budget to some costs, for example { TagKeyValue = ["user:app$my-app"] } or { Service = ["Amazon Elastic Compute Cloud - Compute"] }. | `map(list(string))` | `{}` | no |
| currency | Currency of `monthly_limit`. | `string` | `"USD"` | no |
| email\_addresses | Addresses to notify (up to 10). AWS Budgets emails them directly; no confirmation is needed. | `list(string)` | `[]` | no |
| forecast\_thresholds\_percent | Notify when forecast spend for the month passes each of these percentages of the limit. | `list(number)` | <pre>[<br/>  100<br/>]</pre> | no |
| sns\_topic\_arns | SNS topics to notify (at most one per notification). The topic policy must let budgets.amazonaws.com publish. | `list(string)` | `[]` | no |
| tags | Tags for the budget. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| budget\_arn | Budget ARN. |
| budget\_name | Budget name. |
<!-- END_TF_DOCS -->
