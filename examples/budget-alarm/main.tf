# Two budgets: the whole account, by email, and one app's tagged costs, to an
# SNS topic that budgets may publish to.
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "account" {
  source          = "../../modules/budget-alarm"
  name            = "example-account-monthly"
  monthly_limit   = 300
  email_addresses = ["ops@example.com"]
}

resource "aws_sns_topic" "budget" {
  name              = "example-budget"
  kms_master_key_id = "alias/aws/sns"
}

data "aws_iam_policy_document" "budget_topic" {
  statement {
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.budget.arn]
    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "budget" {
  arn    = aws_sns_topic.budget.arn
  policy = data.aws_iam_policy_document.budget_topic.json
}

module "app" {
  source         = "../../modules/budget-alarm"
  name           = "example-app-monthly"
  monthly_limit  = 50
  sns_topic_arns = [aws_sns_topic.budget.arn]
  cost_filters   = { TagKeyValue = ["user:app$example-app"] }
}
