# People's access to an organization's accounts through IAM Identity Center:
# users and groups in its own identity store, permission sets, and which
# permission set each user or group gets in which account. Sign-in is AWS's
# own (Identity Center's portal with MFA); there is no separate identity
# service and no long-lived IAM user keys.
#
# Apply it in the organization's management account (or a delegated
# administrator). Identity Center itself has to be turned on once in the
# console first: AWS has no API that enables the organization instance.

data "aws_ssoadmin_instances" "this" {}

locals {
  # Empty when Identity Center is off; the preconditions below then say so.
  instance_arn      = try(tolist(data.aws_ssoadmin_instances.this.arns)[0], "")
  identity_store_id = try(tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0], "")
  not_enabled       = "IAM Identity Center is not turned on in this account and region. Turn it on once in the console (IAM Identity Center > Enable, with AWS Organizations), then apply again."

  policy_attachments = merge([
    for ps, cfg in var.permission_sets : {
      for arn in cfg.managed_policy_arns : "${ps}|${arn}" => { permission_set = ps, policy_arn = arn }
    }
  ]...)

  memberships = merge([
    for g, cfg in var.groups : { for u in cfg.members : "${g}|${u}" => { group = g, user = u } }
  ]...)

  # One assignment per (permission set, account, principal).
  assignments = {
    for a in var.assignments :
    "${a.permission_set}|${a.account_id}|${a.user != null ? "user:${a.user}" : "group:${a.group}"}" => a
  }
}

resource "aws_identitystore_user" "this" {
  for_each          = var.users
  identity_store_id = local.identity_store_id

  user_name    = each.value.email
  display_name = coalesce(each.value.display_name, "${each.value.given_name} ${each.value.family_name}")

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }

  lifecycle {
    precondition {
      condition     = local.identity_store_id != ""
      error_message = local.not_enabled
    }
  }
}

resource "aws_identitystore_group" "this" {
  for_each          = var.groups
  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value.description

  lifecycle {
    precondition {
      condition     = local.identity_store_id != ""
      error_message = local.not_enabled
    }
  }
}

resource "aws_identitystore_group_membership" "this" {
  for_each          = local.memberships
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.value.user].user_id
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each         = var.permission_sets
  instance_arn     = local.instance_arn
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration

  lifecycle {
    precondition {
      condition     = local.instance_arn != ""
      error_message = local.not_enabled
    }
  }
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each           = local.policy_attachments
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each           = { for ps, cfg in var.permission_sets : ps => cfg if cfg.inline_policy != null }
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value.inline_policy
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each           = local.assignments
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account_id
  principal_type     = each.value.user != null ? "USER" : "GROUP"
  principal_id       = each.value.user != null ? aws_identitystore_user.this[each.value.user].user_id : aws_identitystore_group.this[each.value.group].group_id

  # Policies attach before anyone is given the permission set, so the first
  # sign-in already has them.
  depends_on = [aws_ssoadmin_managed_policy_attachment.this, aws_ssoadmin_permission_set_inline_policy.this]
}
