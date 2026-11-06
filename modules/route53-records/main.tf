# CloudFront alias records (apex + www) and optional Google Workspace email.
# Separate from route53-zone because these depend on the CloudFront
# distribution, which can't exist until the cert is validated.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# Apex: A + AAAA alias -> CloudFront
resource "aws_route53_record" "apex_a" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex_aaaa" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# www: A + AAAA alias -> CloudFront
resource "aws_route53_record" "www_a" {
  zone_id = var.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www_aaaa" {
  zone_id = var.zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"
  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# ── Optional Google Workspace email (MX + DKIM) ────────
resource "aws_route53_record" "mx" {
  count   = var.enable_google_email ? 1 : 0
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 300
  records = ["1 SMTP.GOOGLE.COM."]
}

resource "aws_route53_record" "google_dkim" {
  count   = var.enable_google_email && var.google_dkim_key != "" ? 1 : 0
  zone_id = var.zone_id
  name    = "google._domainkey.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  # DKIM keys exceed the 255-char TXT string limit; chunk into quoted segments.
  records = [join("\" \"", [for i in range(0, ceil(length(var.google_dkim_key) / 255.0)) : substr(var.google_dkim_key, i * 255, min(255, length(var.google_dkim_key) - i * 255))])]
}
