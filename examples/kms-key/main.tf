# A key for application data, readable by the app role, and a run-time policy
# that lets the same role create one key per customer, each tagged
# managed-by = example-app and aliased under alias/example-app/.
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

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "example-app"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

module "key" {
  source               = "../../modules/kms-key"
  alias                = "example-app"
  description          = "Example app data"
  key_user_arns        = [aws_iam_role.app.arn]
  runtime_tag_value    = "example-app"
  runtime_alias_prefix = "example-app"
}

resource "aws_iam_role_policy" "runtime_keys" {
  name   = "runtime-keys"
  role   = aws_iam_role.app.id
  policy = module.key.runtime_policy_json
}
