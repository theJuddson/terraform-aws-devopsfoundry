# Identity Center users, groups, permission sets and assignments. Plans only,
# mocked provider.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-example"]
      identity_store_ids = ["d-example"]
    }
  }
}

variables {
  users = {
    tayler = { given_name = "Tayler", family_name = "Example", email = "tayler@example.com" }
    owner  = { given_name = "Owner", family_name = "Example", email = "owner@example.com", display_name = "The Owner" }
  }
  groups = {
    agents-admins = { description = "Run the agents account", members = ["tayler", "owner"] }
  }
  permission_sets = {
    AdministratorAccess = { managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"], session_duration = "PT4H" }
    ReadOnly = {
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess", "arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"]
      inline_policy       = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"s3:GetObject\",\"Resource\":\"*\"}]}"
    }
  }
  assignments = [
    { permission_set = "AdministratorAccess", account_id = "222222222222", user = "tayler" },
    { permission_set = "ReadOnly", account_id = "222222222222", group = "agents-admins" },
  ]
}

run "users_sign_in_by_email" {
  command = plan

  assert {
    condition     = aws_identitystore_user.this["tayler"].user_name == "tayler@example.com" && aws_identitystore_user.this["tayler"].identity_store_id == "d-example"
    error_message = "A user's name is their email, in the instance's identity store."
  }
  assert {
    condition     = aws_identitystore_user.this["tayler"].display_name == "Tayler Example" && aws_identitystore_user.this["owner"].display_name == "The Owner"
    error_message = "The display name defaults to given and family name."
  }
  assert {
    condition     = length(aws_identitystore_group_membership.this) == 2
    error_message = "Each group member gets a membership."
  }
}

run "permission_sets_get_their_policies" {
  command = plan

  assert {
    condition     = aws_ssoadmin_permission_set.this["AdministratorAccess"].session_duration == "PT4H" && aws_ssoadmin_permission_set.this["ReadOnly"].session_duration == "PT8H"
    error_message = "Session duration is as given, PT8H by default."
  }
  assert {
    condition     = length(aws_ssoadmin_managed_policy_attachment.this) == 3
    error_message = "Every managed policy of every permission set must be attached."
  }
  assert {
    condition     = aws_ssoadmin_managed_policy_attachment.this["ReadOnly|arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"].managed_policy_arn == "arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess"
    error_message = "Attachments are keyed by permission set and policy."
  }
  assert {
    condition     = keys(aws_ssoadmin_permission_set_inline_policy.this) == ["ReadOnly"]
    error_message = "Only permission sets with an inline policy get one."
  }
}

run "assignments_go_to_users_or_groups" {
  command = plan

  assert {
    condition     = aws_ssoadmin_account_assignment.this["AdministratorAccess|222222222222|user:tayler"].principal_type == "USER"
    error_message = "A user assignment must have principal type USER."
  }
  assert {
    condition     = aws_ssoadmin_account_assignment.this["ReadOnly|222222222222|group:agents-admins"].principal_type == "GROUP"
    error_message = "A group assignment must have principal type GROUP."
  }
  assert {
    condition     = alltrue([for a in values(aws_ssoadmin_account_assignment.this) : a.target_type == "AWS_ACCOUNT" && a.target_id == "222222222222" && a.instance_arn == "arn:aws:sso:::instance/ssoins-example"])
    error_message = "Assignments target the account, in the instance."
  }
  assert {
    condition     = output.assignments == ["AdministratorAccess|222222222222|user:tayler", "ReadOnly|222222222222|group:agents-admins"]
    error_message = "The assignments output lists each assignment."
  }
}

run "identity_center_not_turned_on_is_said" {
  command = plan

  override_data {
    target = data.aws_ssoadmin_instances.this
    values = { arns = [], identity_store_ids = [] }
  }

  expect_failures = [aws_identitystore_user.this, aws_identitystore_group.this, aws_ssoadmin_permission_set.this]
}

run "an_assignment_names_one_principal" {
  command = plan

  variables {
    assignments = [{ permission_set = "ReadOnly", account_id = "222222222222", user = "tayler", group = "agents-admins" }]
  }

  expect_failures = [var.assignments]
}

run "assignments_name_known_things" {
  command = plan

  variables {
    assignments = [
      { permission_set = "Nope", account_id = "222222222222", user = "tayler" },
      { permission_set = "ReadOnly", account_id = "2222", user = "nobody" },
      { permission_set = "ReadOnly", account_id = "222222222222", group = "nogroup" },
    ]
  }

  expect_failures = [var.assignments]
}

run "group_members_must_be_users" {
  command = plan

  variables {
    groups = { g = { members = ["nobody"] } }
  }

  expect_failures = [var.groups]
}

run "sessions_last_one_to_twelve_hours" {
  command = plan

  variables {
    permission_sets = { Long = { session_duration = "PT13H" } }
    assignments     = []
  }

  expect_failures = [var.permission_sets]
}
