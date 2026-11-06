# One customer managed KMS key with an alias and a key policy, plus an IAM
# policy document that lets an application role create, tag and use keys of
# its own at run time (for example one key per tenant), limited by a tag the
# role must put on every key it creates.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  region       = data.aws_region.current.name
  account_root = "arn:${local.partition}:iam::${local.account_id}:root"
  key_arns     = "arn:${local.partition}:kms:${local.region}:${local.account_id}:key/*"
  alias_arns   = "arn:${local.partition}:kms:${local.region}:${local.account_id}:alias/${var.runtime_alias_prefix}/*"
  tag_cond     = "aws:ResourceTag/${var.runtime_tag_key}"
  runtime_on   = var.runtime_tag_value != null
}

# ── The key ────────────────────────────────────────────
data "aws_iam_policy_document" "key" {
  # In a key policy, Resource "*" means this key and nothing else.
  #checkov:skip=CKV_AWS_109:Key policy; "*" is the key itself
  #checkov:skip=CKV_AWS_111:Key policy; "*" is the key itself
  #checkov:skip=CKV_AWS_356:Key policy; "*" is the key itself
  source_policy_documents = var.extra_key_policy_documents

  # Lets IAM policies in this account grant access to the key. Without it only
  # the principals named below could ever use or manage it.
  statement {
    sid       = "AccountRootAndIAM"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = [local.account_root]
    }
  }

  dynamic "statement" {
    for_each = length(var.key_administrator_arns) > 0 ? [1] : []
    content {
      sid = "KeyAdministrators"
      actions = [
        "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
        "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
        "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion", "kms:RotateKeyOnDemand",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.key_administrator_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.key_user_arns) > 0 ? [1] : []
    content {
      sid = "KeyUsers"
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.key_user_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []
    content {
      sid = "AWSServices"
      actions = [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*",
        "kms:GenerateDataKey*", "kms:DescribeKey",
      ]
      resources = ["*"]
      principals {
        type        = "Service"
        identifiers = var.service_principals
      }
      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  rotation_period_in_days = var.rotation_period_in_days
  policy                  = data.aws_iam_policy_document.key.json
  tags                    = merge(var.tags, { Name = var.alias })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}

# ── Run-time keys ─────────────────────────────────────
# An identity policy for the app role. Every key the role creates must carry
# runtime_tag_key = runtime_tag_value, and the role can use and alias only keys
# that carry it. See the README for what this does and does not prevent.
data "aws_iam_policy_document" "runtime" {
  count = local.runtime_on ? 1 : 0

  statement {
    sid       = "CreateTaggedKeys"
    actions   = ["kms:CreateKey"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${var.runtime_tag_key}"
      values   = [var.runtime_tag_value]
    }
    condition {
      test     = "Bool"
      variable = "kms:BypassPolicyLockoutSafetyCheck"
      values   = ["false"]
    }
  }

  # Tags passed to CreateKey are authorized as kms:TagResource on any key in
  # the account, so this cannot be narrowed by resource tag.
  statement {
    sid       = "TagAtCreation"
    actions   = ["kms:TagResource"]
    resources = [local.key_arns]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/${var.runtime_tag_key}"
      values   = [var.runtime_tag_value]
    }
  }

  # Never move the ownership tag off a key that belongs to someone else.
  statement {
    sid       = "KeepOthersOwnershipTag"
    effect    = "Deny"
    actions   = ["kms:TagResource", "kms:UntagResource"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = [var.runtime_tag_key]
    }
    condition {
      test     = "Null"
      variable = local.tag_cond
      values   = ["false"]
    }
    condition {
      test     = "StringNotEquals"
      variable = local.tag_cond
      values   = [var.runtime_tag_value]
    }
  }

  statement {
    sid = "UseOwnKeys"
    actions = concat(
      [
        "kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*",
        "kms:DescribeKey", "kms:EnableKeyRotation", "kms:GetKeyRotationStatus",
        "kms:TagResource", "kms:ListResourceTags", "kms:CreateAlias", "kms:DeleteAlias",
      ],
      var.runtime_allow_key_deletion ? ["kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:DisableKey"] : [],
    )
    resources = [local.key_arns]
    condition {
      test     = "StringEquals"
      variable = local.tag_cond
      values   = [var.runtime_tag_value]
    }
  }

  # CreateAlias and DeleteAlias are authorized on the alias as well as the key.
  statement {
    sid       = "OwnAliasNames"
    actions   = ["kms:CreateAlias", "kms:DeleteAlias"]
    resources = [local.alias_arns]
  }

  statement {
    sid       = "ListKeys"
    actions   = ["kms:ListKeys", "kms:ListAliases"]
    resources = ["*"]
  }
}
