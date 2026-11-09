# DNSSEC signing and DNS query logging for an existing Route53 public hosted
# zone. Route53 requires both the signing key and the query log group to be in
# us-east-1, so the caller passes a us-east-1 provider as this module's `aws`.
# Kept apart from route53-zone so that module's callers need no second provider.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # "region" on aws provider 6.x, "name" (deprecated) on 5.x.
  region      = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  zone_arn    = "arn:${local.partition}:route53:::hostedzone/${var.zone_id}"
  name_suffix = replace(trimsuffix(var.zone_name, "."), ".", "-")
}

# ── DNSSEC (opt-in) ──────────────────────────────────
# Route53 signs with a key-signing key held in an asymmetric KMS key.
data "aws_iam_policy_document" "dnssec" {
  #checkov:skip=CKV_AWS_109:In a key policy, Resource "*" means this key itself
  #checkov:skip=CKV_AWS_111:In a key policy, Resource "*" means this key itself
  #checkov:skip=CKV_AWS_356:In a key policy, Resource "*" means this key itself
  count = var.enable_dnssec ? 1 : 0

  statement {
    sid       = "AccountAdministers"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "Route53DNSSECSigns"
    actions   = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:route53:::hostedzone/*"]
    }
  }

  statement {
    sid       = "Route53DNSSECGrants"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["dnssec-route53.amazonaws.com"]
    }
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_kms_key" "dnssec" {
  #checkov:skip=CKV_AWS_7:KMS cannot rotate asymmetric keys; rotate the key-signing key instead (docs/dnssec.md)
  count                    = var.enable_dnssec ? 1 : 0
  description              = "DNSSEC key-signing key for ${var.zone_name}"
  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7
  policy                   = data.aws_iam_policy_document.dnssec[0].json
  tags                     = merge(var.tags, { Name = "${local.name_suffix}-dnssec" })

  lifecycle {
    precondition {
      condition     = local.region == "us-east-1"
      error_message = "Route53 DNSSEC keys must be in us-east-1; pass a us-east-1 provider as this module's aws provider."
    }
  }
}

resource "aws_kms_alias" "dnssec" {
  count         = var.enable_dnssec ? 1 : 0
  name          = "alias/dnssec/${local.name_suffix}"
  target_key_id = aws_kms_key.dnssec[0].key_id
}

resource "aws_route53_key_signing_key" "this" {
  count                      = var.enable_dnssec ? 1 : 0
  hosted_zone_id             = var.zone_id
  key_management_service_arn = aws_kms_key.dnssec[0].arn
  name                       = "ksk" # unique per zone
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  count          = var.enable_dnssec ? 1 : 0
  hosted_zone_id = aws_route53_key_signing_key.this[0].hosted_zone_id
  depends_on     = [aws_route53_key_signing_key.this]
}

# ── Query logging (opt-in) ───────────────────────────
resource "aws_cloudwatch_log_group" "query_logs" {
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption unless kms_key_arn is set
  #checkov:skip=CKV_AWS_338:Retention is query_log_retention_days; a year of DNS queries is costly for a small app
  count             = var.enable_query_logging ? 1 : 0
  name              = "/aws/route53/${trimsuffix(var.zone_name, ".")}"
  retention_in_days = var.query_log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = merge(var.tags, { Name = "${local.name_suffix}-dns-query-logs" })

  lifecycle {
    precondition {
      condition     = local.region == "us-east-1"
      error_message = "Route53 query logs must go to a log group in us-east-1; pass a us-east-1 provider as this module's aws provider."
    }
  }
}

data "aws_iam_policy_document" "query_logs" {
  count = var.enable_query_logging ? 1 : 0
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.query_logs[0].arn}:*"]
    principals {
      type        = "Service"
      identifiers = ["route53.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.zone_arn]
    }
  }
}

# CloudWatch allows 10 resource policies per region per account, so each zone
# with query logging uses one of them.
resource "aws_cloudwatch_log_resource_policy" "query_logs" {
  count           = var.enable_query_logging ? 1 : 0
  policy_name     = "route53-query-logs-${local.name_suffix}"
  policy_document = data.aws_iam_policy_document.query_logs[0].json
}

resource "aws_route53_query_log" "this" {
  count                    = var.enable_query_logging ? 1 : 0
  zone_id                  = var.zone_id
  cloudwatch_log_group_arn = aws_cloudwatch_log_group.query_logs[0].arn
  depends_on               = [aws_cloudwatch_log_resource_policy.query_logs]
}
