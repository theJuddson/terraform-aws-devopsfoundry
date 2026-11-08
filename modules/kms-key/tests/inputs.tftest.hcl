# The deletion window and rotation period are held to the ranges KMS accepts,
# so a bad value fails at plan instead of at apply. Plans only, against a
# mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
}

variables {
  alias = "demo/data"
}

run "range_ends_are_accepted_low" {
  command = plan

  variables {
    deletion_window_in_days = 7
    rotation_period_in_days = 90
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 7 && aws_kms_key.this.rotation_period_in_days == 90
    error_message = "The lowest values KMS accepts must pass."
  }
}

run "range_ends_are_accepted_high" {
  command = plan

  variables {
    deletion_window_in_days = 30
    rotation_period_in_days = 2560
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30 && aws_kms_key.this.rotation_period_in_days == 2560
    error_message = "The highest values KMS accepts must pass."
  }
}

run "deletion_window_rejects_below_7" {
  command = plan
  variables { deletion_window_in_days = 6 }

  expect_failures = [var.deletion_window_in_days]
}

run "deletion_window_rejects_above_30" {
  command = plan
  variables { deletion_window_in_days = 31 }

  expect_failures = [var.deletion_window_in_days]
}

run "deletion_window_rejects_fraction" {
  command = plan
  variables { deletion_window_in_days = 7.5 }

  expect_failures = [var.deletion_window_in_days]
}

run "rotation_period_rejects_below_90" {
  command = plan
  variables { rotation_period_in_days = 89 }

  expect_failures = [var.rotation_period_in_days]
}

run "rotation_period_rejects_above_2560" {
  command = plan
  variables { rotation_period_in_days = 2561 }

  expect_failures = [var.rotation_period_in_days]
}

run "rotation_period_rejects_fraction" {
  command = plan
  variables { rotation_period_in_days = 365.5 }

  expect_failures = [var.rotation_period_in_days]
}
