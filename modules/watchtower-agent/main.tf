# Installs the Watchtower agent on hosts you build: a user data script and the
# IAM policy it needs. No resources; add `user_data` to your hosts' cloud-init
# and attach `policy_json` to their role.
#
# It fetches with curl's SigV4 signing and the instance role's credentials from
# IMDSv2, so it needs no AWS CLI and runs on Amazon Linux and Ubuntu alike.

data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region     = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))
  partition  = data.aws_partition.current.partition
  release_s3 = startswith(var.release_url, "s3://") ? regex("^s3://([^/]+)/(.+)$", var.release_url) : null
  parameter  = trimprefix(var.group_key_parameter, "/")

  user_data = templatefile("${path.module}/install-agent.sh.tftpl", {
    region         = local.region
    release_url    = var.release_url
    release_https  = local.release_s3 == null ? var.release_url : "https://${local.release_s3[0]}.s3.${local.region}.amazonaws.com/${local.release_s3[1]}"
    release_signed = local.release_s3 != null
    release_sha256 = var.release_sha256
    parameter      = var.group_key_parameter
    collector_url  = var.collector_url
    source_name    = var.source_name
  })
}

data "aws_iam_policy_document" "agent" {
  statement {
    sid       = "ReadTheGroupKey"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${local.partition}:ssm:${local.region}:${data.aws_caller_identity.current.account_id}:parameter/${local.parameter}"]
  }
  dynamic "statement" {
    for_each = local.release_s3 == null ? [] : [1]
    content {
      sid       = "ReadTheRelease"
      actions   = ["s3:GetObject"]
      resources = ["arn:${local.partition}:s3:::${local.release_s3[0]}/${local.release_s3[1]}"]
    }
  }
}
