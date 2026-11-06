# A private S3 bucket: SSE-KMS, versioning, every public-access block on, a
# bucket policy that refuses plain HTTP, and lifecycle rules that expire old
# versions and (optionally) whole prefixes. Also renders an IAM policy document
# that grants one prefix, for attaching to an app role.

locals {
  use_cmk           = var.kms_key_arn != null
  policy_prefix     = trimsuffix(trimprefix(var.policy_prefix, "/"), "/")
  policy_object_arn = local.policy_prefix == "" ? "${aws_s3_bucket.this.arn}/*" : "${aws_s3_bucket.this.arn}/${local.policy_prefix}/*"
  list_prefixes     = local.policy_prefix == "" ? ["*"] : ["${local.policy_prefix}/*", local.policy_prefix]
}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV2_AWS_62:Event notifications are the caller's to add (aws_s3_bucket_notification)
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles storage cost; versioning and the caller's backups cover recovery
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Without a key ARN the bucket uses the AWS-managed aws/s3 key: still SSE-KMS,
# but its key policy cannot be narrowed. Pass a customer managed key (see the
# kms-key module) to control who can decrypt.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = var.noncurrent_version_expiration_days
      newer_noncurrent_versions = var.noncurrent_versions_to_keep
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }
  }

  dynamic "rule" {
    for_each = var.prefix_expiration_days
    content {
      id     = "expire-${replace(trimsuffix(rule.key, "/"), "/", "-")}"
      status = "Enabled"
      filter {
        prefix = rule.key
      }
      expiration {
        days = rule.value
      }
    }
  }

  # Versioning must be on before noncurrent-version rules mean anything.
  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  count         = var.access_log_bucket != null ? 1 : 0
  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = "${var.bucket_name}/"
}

data "aws_iam_policy_document" "bucket" {
  source_policy_documents = var.extra_bucket_policy_documents

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # A policy write can race the public-access block and be rejected.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ── Prefix grant ───────────────────────────────────────
# An identity policy for an app role: list, read and (unless read-only) write
# and delete under one prefix, plus the KMS calls a customer managed key needs.
data "aws_iam_policy_document" "prefix" {
  statement {
    sid       = "ListPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.this.arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = local.list_prefixes
    }
  }

  statement {
    sid = "ObjectsUnderPrefix"
    actions = var.policy_read_only ? ["s3:GetObject", "s3:GetObjectVersion"] : [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [local.policy_object_arn]
  }

  dynamic "statement" {
    for_each = local.use_cmk ? [1] : []
    content {
      sid       = "UseBucketKey"
      actions   = var.policy_read_only ? ["kms:Decrypt"] : ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }
}
