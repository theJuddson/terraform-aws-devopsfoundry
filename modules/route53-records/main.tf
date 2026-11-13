# CloudFront alias records (apex + www) and optional Google Workspace email.
# None sets allow_overwrite (the provider's default is false), so a name that already has a record fails the apply
# instead of being taken over (the zone may be one this site doesn't own).
# Separate from route53-zone because these depend on the CloudFront
# distribution, which can't exist until the cert is validated.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
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
  count   = var.include_www ? 1 : 0
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
  count   = var.include_www ? 1 : 0
  zone_id = var.zone_id
  name    = "www.${var.domain_name}"
  type    = "AAAA"
  alias {
    name                   = var.cloudfront_domain_name
    zone_id                = var.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

# www gained a count with include_www; without these, upgrading would replace both records.
moved {
  from = aws_route53_record.www_a
  to   = aws_route53_record.www_a[0]
}

moved {
  from = aws_route53_record.www_aaaa
  to   = aws_route53_record.www_aaaa[0]
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
