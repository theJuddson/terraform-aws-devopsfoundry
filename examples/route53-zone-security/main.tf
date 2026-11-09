# Sign a hosted zone with DNSSEC and log its DNS queries. After apply, publish
# the ds_record output at the registrar (docs/dnssec.md).
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# Route53's DNSSEC keys and query log groups must be in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_route53_zone" "main" {
  name = "example.com"
}

module "zone_security" {
  source               = "../../modules/route53-zone-security"
  providers            = { aws = aws.us_east_1 }
  zone_id              = aws_route53_zone.main.zone_id
  zone_name            = aws_route53_zone.main.name
  enable_dnssec        = true
  enable_query_logging = true
}

output "ds_record" {
  description = "Publish this at the registrar to complete DNSSEC"
  value       = module.zone_security.ds_record
}
