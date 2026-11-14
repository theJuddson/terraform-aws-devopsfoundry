# A Watchtower collector (https://github.com/theJuddson/DevOpsWatchtower): one
# Graviton host from ec2-host, reached on 443 only, with a fixed public address,
# its data on a volume that outlives the instance and is snapshotted daily, and a
# certificate it gets from Let's Encrypt itself. The host's agent watches the
# host. No SSH; administer it over SSM.

data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  url        = "https://${var.hostname}"
  ses_region = coalesce(var.ses_region, lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null)))
  # s3://bucket/key -> the one object the host may read.
  release_s3 = startswith(var.release_url, "s3://") ? regex("^s3://([^/]+)/(.+)$", var.release_url) : null

  flags = join(" ", compact([
    "--origin ${local.url}",
    "--acme-domain ${var.hostname}",
    var.acme_email != "" ? "--acme-email ${var.acme_email}" : "",
    var.acme_directory != "" ? "--acme-directory ${var.acme_directory}" : "",
    "--retention ${var.retention_hours}h",
    var.mail_from != null ? "--ses-region ${local.ses_region} --smtp-from ${var.mail_from}" : "",
    var.rules_yaml != "" ? "--rules /etc/watchtower/rules.yaml" : "",
  ]))

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    release_url    = var.release_url
    release_sha256 = var.release_sha256
    rules_b64      = base64encode(var.rules_yaml)
    flags          = local.flags
    collector_url  = local.url
    source         = var.name
  })
}

data "aws_iam_policy_document" "host" {
  dynamic "statement" {
    for_each = local.release_s3 == null ? [] : [1]
    content {
      sid       = "ReadTheRelease"
      actions   = ["s3:GetObject"]
      resources = ["arn:${data.aws_partition.current.partition}:s3:::${local.release_s3[0]}/${local.release_s3[1]}"]
    }
  }
  dynamic "statement" {
    for_each = var.mail_from == null || var.ses_identity_arn == null ? [] : [1]
    content {
      sid       = "SendAsTheIdentity"
      actions   = ["ses:SendEmail"]
      resources = [var.ses_identity_arn]
      condition {
        test     = "StringEquals"
        variable = "ses:FromAddress"
        values   = [var.mail_from]
      }
    }
  }
}

module "host" {
  source = "../ec2-host"

  name                        = var.name
  subnet_id                   = var.subnet_id
  instance_type               = var.instance_type
  ami_ssm_parameter           = var.ami_ssm_parameter
  associate_public_ip_address = true
  data_volume_size_gib        = var.data_volume_size_gib
  snapshot_retain_count       = var.snapshot_retain_count
  kms_key_arn                 = var.kms_key_arn
  user_data                   = local.user_data
  # A new release or settings replace the instance; the data volume is kept.
  user_data_replace_on_change = true
  inline_policy_jsons = (local.release_s3 == null && var.mail_from == null ? {} :
  { "${var.name}-watchtower" = data.aws_iam_policy_document.host.json })
  tags = var.tags
}

# People, agents and the ACME CA's TLS-ALPN-01 challenge all arrive on 443.
resource "aws_vpc_security_group_ingress_rule" "https" {
  #checkov:skip=CKV_AWS_260:Not port 80; 443 is the collector's only port and is meant to be public
  for_each          = toset(var.ingress_cidr_blocks)
  security_group_id = module.host.security_group_id
  description       = "HTTPS to the Watchtower collector"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
  tags              = var.tags
}

# A fixed address, so the DNS record and the certificate survive the instance
# being replaced.
resource "aws_eip" "this" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = var.mail_from == null || var.ses_identity_arn != null
      error_message = "mail_from needs ses_identity_arn, the SES identity the role may send as."
    }
  }
}

resource "aws_eip_association" "this" {
  allocation_id = aws_eip.this.id
  instance_id   = module.host.instance_id
}

resource "aws_route53_record" "this" {
  count   = var.zone_id == null ? 0 : 1
  zone_id = var.zone_id
  name    = var.hostname
  type    = "A"
  ttl     = 300
  records = [aws_eip.this.public_ip]
}
