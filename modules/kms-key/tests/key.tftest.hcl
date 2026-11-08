# The key, its alias and who its key policy lets in, plus the optional
# run-time policy for an app role that creates its own tagged keys. Plans only,
# against a mocked provider: no AWS account is touched.

# Mocked providers return random strings for computed values. Give the
# account, partition and region realistic values so the ARNs the policies are
# built from can be checked, and a JSON policy the provider will accept.
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

run "defaults_rotating_key_with_alias_and_account_root_policy" {
  command = plan

  assert {
    condition     = aws_kms_alias.this.name == "alias/demo/data" && output.alias_name == "alias/demo/data"
    error_message = "The alias must be alias/<alias>."
  }
  assert {
    condition     = aws_kms_key.this.enable_key_rotation && aws_kms_key.this.rotation_period_in_days == 365 && aws_kms_key.this.deletion_window_in_days == 30
    error_message = "By default the key must rotate yearly and wait 30 days before deletion."
  }
  assert {
    condition     = aws_kms_key.this.description == "Customer managed key" && aws_kms_key.this.tags["Name"] == "demo/data"
    error_message = "The key must carry the default description and be tagged Name = alias."
  }
  assert {
    condition     = [for s in data.aws_iam_policy_document.key.statement : s.sid] == ["AccountRootAndIAM"]
    error_message = "By default the key policy must only delegate to IAM in this account."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.key.statement :
    one(s.principals).identifiers == toset(["arn:aws:iam::111111111111:root"]) if s.sid == "AccountRootAndIAM"])
    error_message = "The account root statement must name this account's root, or IAM policies cannot grant the key."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.runtime) == 0 && output.runtime_policy_json == null
    error_message = "Without runtime_tag_value there must be no run-time policy."
  }
}

run "settings_reach_the_key" {
  command = plan

  variables {
    description             = "Tenant data"
    deletion_window_in_days = 7
    rotation_period_in_days = 90
    tags                    = { app = "demo" }
  }

  assert {
    condition     = aws_kms_key.this.description == "Tenant data" && aws_kms_key.this.deletion_window_in_days == 7 && aws_kms_key.this.rotation_period_in_days == 90
    error_message = "description, deletion_window_in_days and rotation_period_in_days must be passed to the key."
  }
  assert {
    condition     = aws_kms_key.this.tags == tomap({ app = "demo", Name = "demo/data" })
    error_message = "Caller tags must be kept alongside the Name tag."
  }
}

run "principals_get_their_own_statements" {
  command = plan

  variables {
    key_administrator_arns     = ["arn:aws:iam::111111111111:role/admin"]
    key_user_arns              = ["arn:aws:iam::111111111111:role/app"]
    service_principals         = ["logs.amazonaws.com"]
    extra_key_policy_documents = ["{\"Version\":\"2012-10-17\",\"Statement\":[]}"]
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.key.statement : s.sid] == ["AccountRootAndIAM", "KeyAdministrators", "KeyUsers", "AWSServices"]
    error_message = "Administrators, users and services must each get their statement in the key policy."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.key.statement :
    one(s.principals).identifiers == toset(["arn:aws:iam::111111111111:role/admin"]) && !contains(s.actions, "kms:Decrypt") if s.sid == "KeyAdministrators"])
    error_message = "Administrators must be named and may manage the key but not decrypt with it."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.key.statement :
    one(s.principals).identifiers == toset(["arn:aws:iam::111111111111:role/app"]) && contains(s.actions, "kms:Decrypt") && !contains(s.actions, "kms:ScheduleKeyDeletion") if s.sid == "KeyUsers"])
    error_message = "Key users must be named and may use the key but not delete it."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.key.statement :
      one(s.principals).type == "Service" && one(s.principals).identifiers == toset(["logs.amazonaws.com"]) &&
    one(s.condition).variable == "aws:SourceAccount" && one(s.condition).values == tolist(["111111111111"]) if s.sid == "AWSServices"])
    error_message = "Services must be limited to acting for this account (confused deputy)."
  }
  assert {
    condition     = data.aws_iam_policy_document.key.source_policy_documents == tolist(["{\"Version\":\"2012-10-17\",\"Statement\":[]}"])
    error_message = "extra_key_policy_documents must be merged into the key policy."
  }
}

run "runtime_tag_value_enables_runtime_policy" {
  command = plan

  variables {
    runtime_tag_value = "demo-app"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.runtime) == 1 && output.runtime_policy_json != null
    error_message = "Setting runtime_tag_value must produce the run-time policy."
  }
  assert {
    condition = [for s in data.aws_iam_policy_document.runtime[0].statement : s.sid] == [
      "CreateTaggedKeys", "TagAtCreation", "KeepOthersOwnershipTag", "UseOwnKeys", "OwnAliasNames", "ListKeys",
    ]
    error_message = "The run-time policy must have every statement the role needs to create, tag, alias and use its keys."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
      anytrue([for c in s.condition : c.variable == "aws:RequestTag/managed-by" && c.values == tolist(["demo-app"])]) &&
      anytrue([for c in s.condition : c.variable == "kms:BypassPolicyLockoutSafetyCheck" && c.values == tolist(["false"])])
    if s.sid == "CreateTaggedKeys"])
    error_message = "The role may only create keys tagged with the ownership tag, and never bypass the lockout check."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
      s.resources == toset(["arn:aws:kms:us-east-1:111111111111:key/*"]) && one(s.condition).variable == "aws:ResourceTag/managed-by" && one(s.condition).values == tolist(["demo-app"])
    if s.sid == "UseOwnKeys"])
    error_message = "The role may only use keys in this account and region that carry its ownership tag."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
    s.effect == "Deny" && length(s.condition) == 3 if s.sid == "KeepOthersOwnershipTag"])
    error_message = "The role must be denied changing the ownership tag on keys it does not own."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
    s.resources == toset(["arn:aws:kms:us-east-1:111111111111:alias/app/*"]) if s.sid == "OwnAliasNames"])
    error_message = "Run-time aliases must stay under alias/<runtime_alias_prefix>/."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
    !contains(s.actions, "kms:ScheduleKeyDeletion") && !contains(s.actions, "kms:DisableKey")])
    error_message = "By default the role must not be able to disable or delete its keys."
  }
}

run "runtime_options_change_tag_alias_prefix_and_deletion" {
  command = plan

  variables {
    runtime_tag_value          = "demo-app"
    runtime_tag_key            = "owner"
    runtime_alias_prefix       = "tenants"
    runtime_allow_key_deletion = true
  }

  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
    one(s.condition).variable == "aws:ResourceTag/owner" && contains(s.actions, "kms:ScheduleKeyDeletion") && contains(s.actions, "kms:DisableKey") if s.sid == "UseOwnKeys"])
    error_message = "runtime_tag_key must name the ownership tag and runtime_allow_key_deletion must let the role disable and delete its keys."
  }
  assert {
    condition = alltrue([for s in data.aws_iam_policy_document.runtime[0].statement :
    s.resources == toset(["arn:aws:kms:us-east-1:111111111111:alias/tenants/*"]) if s.sid == "OwnAliasNames"])
    error_message = "runtime_alias_prefix must set where run-time aliases may live."
  }
}
