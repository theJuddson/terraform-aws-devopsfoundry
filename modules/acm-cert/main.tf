# ACM certificate for the apex + wildcard. MUST be created in us-east-1
# for CloudFront, so the caller passes an aliased us-east-1 provider:
#   module "acm_cert" { providers = { aws = aws.us_east_1 } ... }
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain_name
  subject_alternative_names = var.include_wildcard ? ["*.${var.domain_name}"] : []
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = var.domain_name
  }
}
