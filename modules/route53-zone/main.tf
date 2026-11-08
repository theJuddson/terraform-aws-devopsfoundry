# Hosted zone + ACM DNS-validation records ONLY.
# Deliberately contains NO CloudFront alias records so that `bin/new-site`
# can -target this module (plus namecheap-ns) in Phase 1 to flip nameservers
# BEFORE any CloudFront/cert-validation exists. Alias + email records live in
# the separate route53-records module, which depends on CloudFront.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "DevOpsFoundry — ${var.domain_name}"
}

# ACM validation CNAMEs. Grouped by record name (`...`) to dedupe the apex +
# wildcard SANs, which often share one validation record.
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in var.acm_domain_validation_options : dvo.resource_record_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }...
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value[0].name
  type            = each.value[0].type
  ttl             = 300
  records         = [each.value[0].record]
  allow_overwrite = true
}
