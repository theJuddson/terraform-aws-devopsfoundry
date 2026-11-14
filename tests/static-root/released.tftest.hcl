# A static site root released by bin/release-nameservers (its namecheap.tf set
# aside as namecheap.tf.released) keeps its own zone and plans with no
# Namecheap provider configured. Namecheap is not mocked here, and
# tests/static-root/run.sh unsets NAMECHEAP_*, so a root that still needed
# Namecheap credentials would fail this plan.

mock_provider "aws" {}
mock_provider "aws" {
  alias = "us_east_1"
  mock_resource "aws_acm_certificate" {
    override_during = plan
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
      domain_validation_options = [
        { domain_name = "example.com", resource_record_name = "_abc.example.com.", resource_record_type = "CNAME", resource_record_value = "_xyz.acm-validations.aws." },
      ]
    }
  }
}

run "keeps_its_zone_without_namecheap" {
  command = plan

  assert {
    condition     = length(module.route53_zone) == 1 && length(data.aws_route53_zone.existing) == 0
    error_message = "A released site keeps the zone it created."
  }
}
