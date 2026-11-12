# The Enhanced Monitoring role trusts only this instance's monitoring in this
# account (#65), per AWS's confused-deputy guidance. Plans only, mocked provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_db_subnet_group" {
    override_during = plan
    defaults        = { arn = "arn:aws:rds:eu-west-1:111111111111:subgrp:demo-rds" }
  }
}

variables {
  name                  = "demo"
  private_subnet_ids    = ["subnet-a", "subnet-b"]
  rds_security_group_id = "sg-rds"
}

run "monitoring_trust_is_limited_to_this_instance" {
  command = plan

  variables {
    monitoring_interval = 60
  }

  assert {
    condition = toset([for c in data.aws_iam_policy_document.monitoring_assume[0].statement[0].condition : "${c.test} ${c.variable} ${one(c.values)}"]) == toset([
      "StringEquals aws:SourceAccount 111111111111",
      "StringLike aws:SourceArn arn:aws:rds:eu-west-1:111111111111:db:demo-postgres",
    ])
    error_message = "The monitoring role must trust only this instance's monitoring, as AWS documents."
  }
}

run "the_switch_restores_the_plain_trust" {
  command = plan

  variables {
    monitoring_interval            = 60
    trust_policy_source_conditions = false
  }

  assert {
    condition     = length(data.aws_iam_policy_document.monitoring_assume[0].statement[0].condition) == 0
    error_message = "trust_policy_source_conditions = false must remove the conditions."
  }
}
