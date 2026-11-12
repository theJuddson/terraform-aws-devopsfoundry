# The live organization trusts a service the configuration doesn't list
# (turned on outside Terraform). The plan must warn before the apply switches
# it off (#59). Plans only, mocked provider.

mock_provider "aws" {
  override_during = plan

  mock_resource "aws_organizations_organization" {
    defaults = {
      id                = "o-example"
      master_account_id = "111111111111"
      roots             = [{ id = "r-root", arn = "arn:aws:organizations::111111111111:root/o-example/r-root", name = "Root", policy_types = [] }]
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_organizations_organization" {
    defaults = { aws_service_access_principals = ["sso.amazonaws.com", "account.amazonaws.com", "compute-optimizer.amazonaws.com"] }
  }
}

run "an_undeclared_trusted_service_is_warned_about" {
  command = plan

  expect_failures = [check.service_access_kept]
}
