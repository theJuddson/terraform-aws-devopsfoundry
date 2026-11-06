# EFS file system: encrypted, AWS Backup on, one mount target per subnet and a
# security group that admits NFS only from the groups you name. Also renders an
# IAM policy document that lets an app role create access points (and, as an
# option, whole file systems) at run time, limited by a tag.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  arn_base   = "arn:${data.aws_partition.current.partition}:elasticfilesystem:${data.aws_region.current.name}:${local.account_id}"
  tag_value  = coalesce(var.runtime_tag_value, var.name)
  request    = "aws:RequestTag/${var.runtime_tag_key}"
  resource   = "aws:ResourceTag/${var.runtime_tag_key}"
}

resource "aws_efs_file_system" "this" {
  creation_token   = var.name
  encrypted        = true
  kms_key_id       = var.kms_key_arn
  performance_mode = "generalPurpose"
  throughput_mode  = var.throughput_mode

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_ia != null ? [1] : []
    content {
      transition_to_ia = var.transition_to_ia
    }
  }

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_ia != null ? [1] : []
    content {
      transition_to_primary_storage_class = "AFTER_1_ACCESS"
    }
  }

  # The file system carries the run-time tag too, so access points created at
  # run time can only be made on file systems the app is meant to use.
  tags = merge(var.tags, { Name = var.name, (var.runtime_tag_key) = local.tag_value })
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  backup_policy {
    status = "ENABLED"
  }
}

# ── Network ───────────────────────────────────────────
resource "aws_security_group" "this" {
  name        = "${var.name}-efs"
  description = "NFS to ${var.name} from the listed security groups only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-efs" })
}

resource "aws_vpc_security_group_ingress_rule" "nfs" {
  for_each                     = toset(var.source_security_group_ids)
  security_group_id            = aws_security_group.this.id
  description                  = "NFS from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
}

resource "aws_efs_mount_target" "this" {
  for_each        = toset(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [aws_security_group.this.id]
}

# ── File system policy ────────────────────────────────
# Clients must connect over TLS and through a mount target. Root access is off
# unless allowed, so a client's root user is squashed.
data "aws_iam_policy_document" "file_system" {
  statement {
    sid       = "MountThroughMountTargets"
    actions   = concat(["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"], var.allow_root_access ? ["elasticfilesystem:ClientRootAccess"] : [])
    resources = [aws_efs_file_system.this.arn]
    principals {
      type        = "AWS"
      identifiers = var.client_role_arns != null ? var.client_role_arns : ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
    condition {
      test     = "Bool"
      variable = "elasticfilesystem:AccessedViaMountTarget"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["*"]
    resources = [aws_efs_file_system.this.arn]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_efs_file_system_policy" "this" {
  file_system_id = aws_efs_file_system.this.id
  policy         = data.aws_iam_policy_document.file_system.json
}

# ── Run-time access points (and file systems) ─────────
data "aws_iam_policy_document" "runtime" {
  #checkov:skip=CKV_AWS_356:Only EC2 Describe calls (which take no resource) and the deny use "*"
  statement {
    sid       = "CreateTaggedAccessPoints"
    actions   = ["elasticfilesystem:CreateAccessPoint"]
    resources = ["${local.arn_base}:file-system/*"]
    condition {
      test     = "StringEquals"
      variable = local.request
      values   = [local.tag_value]
    }
    condition {
      test     = "StringEquals"
      variable = local.resource
      values   = [local.tag_value]
    }
  }

  statement {
    sid       = "TagOnCreate"
    actions   = ["elasticfilesystem:TagResource"]
    resources = ["${local.arn_base}:access-point/*", "${local.arn_base}:file-system/*"]
    condition {
      test     = "StringEquals"
      variable = local.request
      values   = [local.tag_value]
    }
  }

  # Never move the ownership tag off a resource that belongs to someone else.
  statement {
    sid       = "KeepOthersOwnershipTag"
    effect    = "Deny"
    actions   = ["elasticfilesystem:TagResource", "elasticfilesystem:UntagResource"]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = [var.runtime_tag_key]
    }
    condition {
      test     = "Null"
      variable = local.resource
      values   = ["false"]
    }
    condition {
      test     = "StringNotEquals"
      variable = local.resource
      values   = [local.tag_value]
    }
  }

  statement {
    sid       = "ManageOwnAccessPoints"
    actions   = ["elasticfilesystem:DeleteAccessPoint", "elasticfilesystem:TagResource"]
    resources = ["${local.arn_base}:access-point/*"]
    condition {
      test     = "StringEquals"
      variable = local.resource
      values   = [local.tag_value]
    }
  }

  statement {
    sid = "Describe"
    actions = [
      "elasticfilesystem:DescribeAccessPoints",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets",
      "elasticfilesystem:ListTagsForResource",
    ]
    resources = ["${local.arn_base}:file-system/*", "${local.arn_base}:access-point/*"]
  }

  dynamic "statement" {
    for_each = var.runtime_allow_create_file_system ? [1] : []
    content {
      sid       = "CreateTaggedFileSystems"
      actions   = ["elasticfilesystem:CreateFileSystem"]
      resources = ["${local.arn_base}:file-system/*"]
      condition {
        test     = "StringEquals"
        variable = local.request
        values   = [local.tag_value]
      }
      condition {
        test     = "Bool"
        variable = "elasticfilesystem:Encrypted"
        values   = ["true"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.runtime_allow_create_file_system ? [1] : []
    content {
      sid = "ManageOwnFileSystems"
      actions = [
        "elasticfilesystem:CreateMountTarget",
        "elasticfilesystem:DeleteMountTarget",
        "elasticfilesystem:DeleteFileSystem",
        "elasticfilesystem:PutBackupPolicy",
        "elasticfilesystem:PutFileSystemPolicy",
        "elasticfilesystem:PutLifecycleConfiguration",
      ]
      resources = ["${local.arn_base}:file-system/*"]
      condition {
        test     = "StringEquals"
        variable = local.resource
        values   = [local.tag_value]
      }
    }
  }

  # CreateMountTarget makes a network interface in the caller's name.
  dynamic "statement" {
    for_each = var.runtime_allow_create_file_system ? [1] : []
    content {
      sid     = "MountTargetNetworkInterfaces"
      actions = ["ec2:CreateNetworkInterface"]
      resources = [
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${local.account_id}:network-interface/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${local.account_id}:subnet/*",
        "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${local.account_id}:security-group/*",
      ]
    }
  }

  # EC2 Describe calls cannot be limited to resources.
  dynamic "statement" {
    for_each = var.runtime_allow_create_file_system ? [1] : []
    content {
      sid = "MountTargetDescribe"
      actions = [
        "ec2:DescribeSubnets",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeNetworkInterfaceAttribute",
      ]
      resources = ["*"]
    }
  }
}
