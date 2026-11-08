# What the monthly budget alerts on and who it notifies, and the checks on
# subscribers. Plans only, against a mocked provider: no AWS account is touched.

mock_provider "aws" {}

variables {
  name            = "demo-monthly"
  monthly_limit   = 50
  email_addresses = ["ops@example.com"]
}

run "defaults_alert_on_actual_80_100_and_forecast_100" {
  command = plan

  assert {
    condition = toset([for n in aws_budgets_budget.this.notification : "${n.notification_type}:${n.threshold}"]) == toset([
      "ACTUAL:80", "ACTUAL:100", "FORECASTED:100",
    ])
    error_message = "By default the budget must alert at 80% and 100% actual and 100% forecast spend."
  }
  assert {
    condition     = alltrue([for n in aws_budgets_budget.this.notification : n.comparison_operator == "GREATER_THAN" && n.threshold_type == "PERCENTAGE"])
    error_message = "Thresholds must be percentages of the limit, crossed upwards."
  }
  assert {
    condition     = alltrue([for n in aws_budgets_budget.this.notification : toset(n.subscriber_email_addresses) == toset(["ops@example.com"])])
    error_message = "Every notification must email the given addresses."
  }
}

run "budget_is_a_monthly_cost_budget_in_the_given_currency" {
  command = plan

  variables {
    monthly_limit = 12.5
    currency      = "EUR"
  }

  assert {
    condition     = aws_budgets_budget.this.name == "demo-monthly" && output.budget_name == "demo-monthly"
    error_message = "The budget must be named after var.name."
  }
  assert {
    condition     = aws_budgets_budget.this.budget_type == "COST" && aws_budgets_budget.this.time_unit == "MONTHLY"
    error_message = "The budget must track monthly cost."
  }
  assert {
    condition     = aws_budgets_budget.this.limit_amount == "12.50" && aws_budgets_budget.this.limit_unit == "EUR"
    error_message = "The limit must be monthly_limit to two decimals, in the given currency."
  }
  assert {
    condition     = length(aws_budgets_budget.this.cost_filter) == 0
    error_message = "Without cost_filters the budget must cover all costs."
  }
}

run "custom_thresholds_replace_the_defaults" {
  command = plan

  variables {
    actual_thresholds_percent   = [50]
    forecast_thresholds_percent = []
  }

  assert {
    condition     = toset([for n in aws_budgets_budget.this.notification : "${n.notification_type}:${n.threshold}"]) == toset(["ACTUAL:50"])
    error_message = "Only the given thresholds may alert; an empty forecast list means no forecast alerts."
  }
}

run "sns_topic_alone_is_enough" {
  command = plan

  variables {
    email_addresses = []
    sns_topic_arns  = ["arn:aws:sns:us-east-1:111111111111:budget"]
  }

  assert {
    condition     = alltrue([for n in aws_budgets_budget.this.notification : toset(n.subscriber_sns_topic_arns) == toset(["arn:aws:sns:us-east-1:111111111111:budget"])])
    error_message = "Every notification must publish to the given SNS topic."
  }
}

run "cost_filters_limit_the_budget" {
  command = plan

  variables {
    cost_filters = { TagKeyValue = ["user:app$my-app"] }
  }

  assert {
    condition     = length(aws_budgets_budget.this.cost_filter) == 1 && one(aws_budgets_budget.this.cost_filter).name == "TagKeyValue" && toset(one(aws_budgets_budget.this.cost_filter).values) == toset(["user:app$my-app"])
    error_message = "Each cost_filters entry must become a cost filter on the budget."
  }
}

run "no_subscribers_is_rejected" {
  command = plan

  variables {
    email_addresses = []
  }

  expect_failures = [aws_budgets_budget.this]
}

run "more_than_one_sns_topic_is_rejected" {
  command = plan

  variables {
    sns_topic_arns = [
      "arn:aws:sns:us-east-1:111111111111:a",
      "arn:aws:sns:us-east-1:111111111111:b",
    ]
  }

  expect_failures = [var.sns_topic_arns]
}
