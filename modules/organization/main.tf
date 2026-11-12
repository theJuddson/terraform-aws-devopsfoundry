# An AWS Organization run from the account this is applied in (which becomes its
# management account), and member accounts made in it. Each venture that needs
# its own boundary (its own bill, its own people, its own blast radius) gets
# an account; people reach them through IAM Identity Center (the identity-center
# module), not IAM users.
#
# An organization that already exists is imported, not recreated:
#   import { to = module.org.aws_organizations_organization.this  id = "o-..." }
# Accounts are never destroyed by Terraform: closing one takes 90 days and
# frees its email only then, so prevent_destroy refuses it. Remove an account
# from the configuration with a `removed` block, then close it in the console.

data "aws_partition" "current" {}

resource "aws_organizations_organization" "this" {
  feature_set                   = "ALL"
  aws_service_access_principals = var.service_access_principals
  enabled_policy_types          = var.enabled_policy_types
}

resource "aws_organizations_organizational_unit" "this" {
  for_each  = var.organizational_units
  name      = each.key
  parent_id = aws_organizations_organization.this.roots[0].id
}

resource "aws_organizations_account" "this" {
  for_each = var.accounts

  name      = each.key
  email     = each.value.email
  parent_id = each.value.organizational_unit == null ? aws_organizations_organization.this.roots[0].id : aws_organizations_organizational_unit.this[each.value.organizational_unit].id
  # The management account reaches each member through this role (switch role,
  # or a provider assume_role) until Identity Center access is in place.
  role_name                  = var.member_admin_role_name
  iam_user_access_to_billing = each.value.iam_user_access_to_billing ? "ALLOW" : "DENY"
  close_on_deletion          = false
  tags                       = each.value.tags

  lifecycle {
    prevent_destroy = true
    # AWS doesn't return these after creation, so an imported account would
    # otherwise plan a replacement.
    ignore_changes = [role_name, iam_user_access_to_billing]
  }
}
