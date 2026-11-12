# The flow logs role trusts only flow logs in this account (#65), per AWS's
# confused-deputy guidance. Plans only, mocked provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  # The module slices this list by az_count and names subnets after it.
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_resource "aws_vpc" {
    override_during = plan
    defaults        = { arn = "arn:aws:ec2:us-east-1:111111111111:vpc/vpc-mock" }
  }
}

variables {
  name = "demo"
}

run "flow_logs_trust_is_limited_to_this_account" {
  command = plan

  variables {
    enable_flow_logs = true
  }

  assert {
    condition = toset([for c in data.aws_iam_policy_document.flow_logs_assume[0].statement[0].condition : "${c.test} ${c.variable} ${one(c.values)}"]) == toset([
      "StringEquals aws:SourceAccount 111111111111",
      "ArnLike aws:SourceArn arn:aws:ec2:us-east-1:111111111111:vpc-flow-log/*",
    ])
    error_message = "The flow logs role must trust only flow logs in this account, as AWS documents."
  }
}

run "the_switch_restores_the_plain_trust" {
  command = plan

  variables {
    enable_flow_logs               = true
    trust_policy_source_conditions = false
  }

  assert {
    condition     = length(data.aws_iam_policy_document.flow_logs_assume[0].statement[0].condition) == 0
    error_message = "trust_policy_source_conditions = false must remove the conditions."
  }
}
