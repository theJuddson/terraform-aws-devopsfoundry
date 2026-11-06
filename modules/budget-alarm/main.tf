# A monthly AWS Budgets cost budget that notifies email addresses and/or an SNS
# topic when actual or forecast spend crosses each threshold.

locals {
  notifications = concat(
    [for pct in var.actual_thresholds_percent : { type = "ACTUAL", pct = pct }],
    [for pct in var.forecast_thresholds_percent : { type = "FORECASTED", pct = pct }],
  )
}

resource "aws_budgets_budget" "this" {
  name         = var.name
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_limit)
  limit_unit   = var.currency
  time_unit    = "MONTHLY"

  dynamic "cost_filter" {
    for_each = var.cost_filters
    content {
      name   = cost_filter.key
      values = cost_filter.value
    }
  }

  dynamic "notification" {
    for_each = local.notifications
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.pct
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = var.email_addresses
      subscriber_sns_topic_arns  = var.sns_topic_arns
    }
  }

  lifecycle {
    precondition {
      condition     = length(var.email_addresses) + length(var.sns_topic_arns) > 0
      error_message = "Give at least one of email_addresses or sns_topic_arns."
    }
  }

  tags = var.tags
}
