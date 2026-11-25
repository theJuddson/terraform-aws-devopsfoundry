# A Watchtower collector (https://github.com/theJuddson/DevOpsWatchtower): one
# Graviton host from ec2-host, reached on 443 only, with a fixed public address,
# its data on a volume that outlives the instance and is snapshotted daily, and a
# certificate it gets from Let's Encrypt itself. The host's agent watches the
# host. No SSH; administer it over SSM.

data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  url        = "https://${var.hostname}"
  ses_region = coalesce(var.ses_region, local.region)
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
    join(" ", var.extra_flags),
  ]))

  health_check = length(var.health_alarm_actions) > 0 && !var.rules_in_user_data
  region       = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))

  user_data = var.rules_in_user_data ? templatefile("${path.module}/user-data-legacy.sh.tftpl", {
    release_url    = var.release_url
    release_sha256 = var.release_sha256
    rules_b64      = base64encode(var.rules_yaml)
    flags          = local.flags
    collector_url  = local.url
    source         = var.name
    }) : templatefile("${path.module}/user-data.sh.tftpl", {
    release_url     = var.release_url
    release_sha256  = var.release_sha256
    rules_parameter = try(aws_ssm_parameter.rules[0].name, "")
    region          = local.region
    flags           = local.flags
    collector_url   = local.url
    source          = var.name
    # Fixed, so the kept data volume's owners match on every instance. Outside
    # Amazon Linux's system range (counted down from 999) and its users' (from 1000).
    health_check  = local.health_check
    hostname      = var.hostname
    curl_insecure = var.acme_directory != ""
    collector_uid = 61001
    agent_uid     = 61002
  })
}

# The alarm rules, outside user data: the host's watchtower-rules timer reads
# this every minute and restarts the collector when it changed, so a rules
# change never replaces the instance. Gzipped, so a Standard parameter's 4 KB
# holds well over 4 KB of YAML. The host's AmazonSSMManagedInstanceCore policy
# already allows ssm:GetParameter.
resource "aws_ssm_parameter" "rules" {
  #checkov:skip=CKV2_AWS_34:Alarm rules are configuration, not a secret, and are in Terraform state in the clear anyway
  count       = var.rules_yaml != "" && !var.rules_in_user_data ? 1 : 0
  name        = "/watchtower/${var.name}/rules"
  description = "Watchtower alarm rules for ${var.name}, gzipped and base64-encoded"
  type        = "String"
  tier        = "Standard"
  value       = base64gzip(var.rules_yaml)
  tags        = var.tags
}

data "aws_iam_policy_document" "host" {
  dynamic "statement" {
    for_each = local.health_check ? [1] : []
    content {
      sid       = "PutTheHealthMetric"
      actions   = ["cloudwatch:PutMetricData"]
      resources = ["*"] # PutMetricData takes no resource; the namespace condition limits it.
      condition {
        test     = "StringEquals"
        variable = "cloudwatch:namespace"
        values   = ["Watchtower"]
      }
    }
  }
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
      sid     = "SendAsTheIdentity"
      actions = ["ses:SendEmail"]
      # SES checks the permission against each recipient's identity in the account as well as the
      # sender's (the sandbox's verified addresses, and any other address), so the resource is every
      # identity in the sender identity's account and region; the From condition limits the sender.
      resources = ["${regex("^(arn:[^:]+:ses:[^:]+:[0-9]+:identity/)", var.ses_identity_arn)[0]}*"]
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
  # Rules don't (see aws_ssm_parameter.rules), unless rules_in_user_data.
  user_data_replace_on_change = true
  inline_policy_jsons = (local.release_s3 == null && var.mail_from == null && !local.health_check ? {} :
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

# Down while its instance passes status checks: the host's watchtower-health
# timer reports 1 or 0 each minute, and no data (no instance, user data that
# never got that far, no network) counts as down too.
resource "aws_cloudwatch_metric_alarm" "health" {
  count               = local.health_check ? 1 : 0
  alarm_name          = "${var.name}-collector-health"
  alarm_description   = "Watchtower collector ${var.hostname} has not answered /healthz for 5 minutes"
  namespace           = "Watchtower"
  metric_name         = "CollectorHealthy"
  dimensions          = { Collector = var.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = var.health_alarm_actions
  ok_actions          = var.health_alarm_actions
  tags                = var.tags
}
