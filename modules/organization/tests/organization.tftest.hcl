# The organization and its member accounts. Plans only, mocked provider.

# prevent_destroy keeps accounts from being destroyed, so these runs only
# plan; override_during = plan gives the mocked IDs at plan time.
mock_provider "aws" {
  override_during = plan

  mock_resource "aws_organizations_organization" {
    defaults = {
      id                = "o-example"
      master_account_id = "111111111111"
      roots             = [{ id = "r-root", arn = "arn:aws:organizations::111111111111:root/o-example/r-root", name = "Root", policy_types = [] }]
    }
  }
  mock_resource "aws_organizations_account" {
    defaults = { id = "222222222222" }
  }
  mock_resource "aws_organizations_organizational_unit" {
    defaults = { id = "ou-root-ventures" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

run "defaults_trust_identity_center_and_no_policies" {
  command = plan

  assert {
    condition     = aws_organizations_organization.this.feature_set == "ALL"
    error_message = "All features are needed for Identity Center and SCPs."
  }
  assert {
    condition     = contains(aws_organizations_organization.this.aws_service_access_principals, "sso.amazonaws.com")
    error_message = "Identity Center must be trusted by the organization."
  }
  assert {
    condition     = length(aws_organizations_organization.this.enabled_policy_types) == 0
    error_message = "No policy types by default."
  }
  assert {
    condition     = length(aws_organizations_account.this) == 0
    error_message = "No accounts unless asked."
  }
}

run "an_account_at_the_root" {
  command = plan

  variables {
    accounts = { agents = { email = "owner+agents@example.com", tags = { project = "agents" } } }
  }

  assert {
    condition     = aws_organizations_account.this["agents"].email == "owner+agents@example.com" && aws_organizations_account.this["agents"].name == "agents"
    error_message = "The account takes its name from the key and the given email."
  }
  assert {
    condition     = aws_organizations_account.this["agents"].parent_id == "r-root"
    error_message = "With no organizational unit the account sits at the root."
  }
  assert {
    condition     = aws_organizations_account.this["agents"].role_name == "OrganizationAccountAccessRole" && aws_organizations_account.this["agents"].iam_user_access_to_billing == "ALLOW"
    error_message = "The member admin role and billing access must be the defaults."
  }
  assert {
    condition     = !aws_organizations_account.this["agents"].close_on_deletion
    error_message = "Terraform must never close an account."
  }
  assert {
    condition     = output.account_ids == { agents = "222222222222" } && output.member_admin_role_arns == { agents = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole" }
    error_message = "The outputs must give each account's ID and admin role."
  }
}

run "an_account_in_an_organizational_unit" {
  command = plan

  variables {
    organizational_units = ["ventures"]
    accounts = {
      shop = { email = "a@example.com", organizational_unit = "ventures", iam_user_access_to_billing = false }
    }
  }

  assert {
    condition     = aws_organizations_organizational_unit.this["ventures"].parent_id == "r-root"
    error_message = "Organizational units sit under the root."
  }
  assert {
    condition     = aws_organizations_account.this["shop"].parent_id == "ou-root-ventures"
    error_message = "The account must be placed in its organizational unit."
  }
  assert {
    condition     = aws_organizations_account.this["shop"].iam_user_access_to_billing == "DENY"
    error_message = "Billing access can be turned off."
  }
}

run "an_unknown_organizational_unit_is_refused" {
  command = plan

  variables {
    accounts = { agents = { email = "a@example.com", organizational_unit = "nope" } }
  }

  expect_failures = [var.accounts]
}

run "emails_must_be_valid" {
  command = plan

  variables {
    accounts = { bad = { email = "not-an-email" } }
  }

  expect_failures = [var.accounts]
}

# AWS treats addresses that differ only in case as the same.
run "emails_must_be_distinct_ignoring_case" {
  command = plan

  variables {
    accounts = {
      one = { email = "same@example.com" }
      two = { email = "SAME@example.com" }
    }
  }

  expect_failures = [var.accounts]
}

run "unknown_policy_types_are_refused" {
  command = plan

  variables {
    enabled_policy_types = ["SERVICE_CONTROL_POLICY", "MADE_UP_POLICY"]
  }

  expect_failures = [var.enabled_policy_types]
}
