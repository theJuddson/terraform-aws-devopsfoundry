# Every live trusted service is declared, so the check passes (#59).
# Plans only, mocked provider.

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
    defaults = { aws_service_access_principals = ["sso.amazonaws.com", "compute-optimizer.amazonaws.com"] }
  }
}

run "declared_trusted_services_pass_the_check" {
  command = plan

  variables {
    service_access_principals = ["sso.amazonaws.com", "account.amazonaws.com", "compute-optimizer.amazonaws.com"]
  }

  assert {
    condition     = contains(aws_organizations_organization.this.aws_service_access_principals, "compute-optimizer.amazonaws.com")
    error_message = "Declared services must stay in the organization's trusted list."
  }
}
