# SES sending domain: identity + DKIM + DMARC + SMTP IAM user, with the SMTP
# credentials stored in a module-owned Secrets Manager secret. An app-specific
# SNS->webhook subscription is left to the caller (the topic is exposed when enable_notifications=true).
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix      = var.name
  smtp_host        = "email-smtp.${var.aws_region}.amazonaws.com"
  use_mail_from    = var.mail_from_subdomain != ""
  mail_from_domain = local.use_mail_from ? "${var.mail_from_subdomain}.${var.sender_domain}" : ""
}

resource "aws_ses_domain_identity" "sender" {
  domain = var.sender_domain
}

resource "aws_route53_record" "ses_verification" {
  zone_id = var.sender_zone_id
  name    = "_amazonses.${var.sender_domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.sender.verification_token]
}

resource "aws_ses_domain_identity_verification" "sender" {
  domain     = aws_ses_domain_identity.sender.id
  depends_on = [aws_route53_record.ses_verification]
}

resource "aws_ses_domain_dkim" "sender" {
  domain = aws_ses_domain_identity.sender.domain
}

resource "aws_route53_record" "dkim" {
  count   = 3
  zone_id = var.sender_zone_id
  name    = "${aws_ses_domain_dkim.sender.dkim_tokens[count.index]}._domainkey.${var.sender_domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.sender.dkim_tokens[count.index]}.dkim.amazonses.com"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = var.sender_zone_id
  name    = "_dmarc.${var.sender_domain}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=${var.dmarc_policy}; sp=${var.dmarc_policy}; rua=mailto:${var.dmarc_rua_email}"]
}

# ── Custom MAIL FROM domain (optional) ────────────────
# Sets the envelope Return-Path to a subdomain of sender_domain so SPF aligns with the From header
# (belt-and-suspenders with DKIM). behavior_on_mx_failure=UseDefaultValue falls back to amazonses.com
# while DNS propagates, so mail never bounces during cutover.
resource "aws_ses_domain_mail_from" "sender" {
  count                  = local.use_mail_from ? 1 : 0
  domain                 = aws_ses_domain_identity.sender.domain
  mail_from_domain       = local.mail_from_domain
  behavior_on_mx_failure = "UseDefaultValue"
}

resource "aws_route53_record" "mail_from_mx" {
  count   = local.use_mail_from ? 1 : 0
  zone_id = var.sender_zone_id
  name    = local.mail_from_domain
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  count   = local.use_mail_from ? 1 : 0
  zone_id = var.sender_zone_id
  name    = local.mail_from_domain
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}

# ── SMTP IAM user + secret ────────────────────────────
resource "aws_iam_user" "ses_smtp" {
  name = "${local.name_prefix}-ses-smtp"
  path = "/system/"
}

resource "aws_iam_access_key" "ses_smtp" {
  user = aws_iam_user.ses_smtp.name
}

data "aws_iam_policy_document" "ses_send" {
  statement {
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [aws_ses_domain_identity.sender.arn]
  }
}

resource "aws_iam_user_policy" "ses_send" {
  name   = "ses-send"
  user   = aws_iam_user.ses_smtp.name
  policy = data.aws_iam_policy_document.ses_send.json
}

resource "aws_secretsmanager_secret" "smtp" {
  name                    = "${local.name_prefix}/ses/smtp"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "smtp" {
  secret_id = aws_secretsmanager_secret.smtp.id
  secret_string = jsonencode({
    username = aws_iam_access_key.ses_smtp.id
    password = aws_iam_access_key.ses_smtp.ses_smtp_password_v4
    host     = local.smtp_host
    port     = "587"
  })
}

# ── Optional bounce/complaint topic (subscription left to caller) ──
resource "aws_sns_topic" "ses_notifications" {
  count = var.enable_notifications ? 1 : 0
  name  = "${local.name_prefix}-ses-notifications"
  tags  = { Name = "${local.name_prefix}-ses-notifications" }
}

data "aws_iam_policy_document" "ses_notifications_topic" {
  count = var.enable_notifications ? 1 : 0
  statement {
    sid       = "AllowSESPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.ses_notifications[0].arn]
    principals {
      type        = "Service"
      identifiers = ["ses.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnEquals"
      variable = "AWS:SourceArn"
      values   = [aws_ses_domain_identity.sender.arn]
    }
  }
}

resource "aws_sns_topic_policy" "ses_notifications" {
  count  = var.enable_notifications ? 1 : 0
  arn    = aws_sns_topic.ses_notifications[0].arn
  policy = data.aws_iam_policy_document.ses_notifications_topic[0].json
}

resource "aws_ses_identity_notification_topic" "bounce" {
  count                    = var.enable_notifications ? 1 : 0
  identity                 = aws_ses_domain_identity.sender.domain
  notification_type        = "Bounce"
  topic_arn                = aws_sns_topic.ses_notifications[0].arn
  include_original_headers = false
}

resource "aws_ses_identity_notification_topic" "complaint" {
  count                    = var.enable_notifications ? 1 : 0
  identity                 = aws_ses_domain_identity.sender.domain
  notification_type        = "Complaint"
  topic_arn                = aws_sns_topic.ses_notifications[0].arn
  include_original_headers = false
}
