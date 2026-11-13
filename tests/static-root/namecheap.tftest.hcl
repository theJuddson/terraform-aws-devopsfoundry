# A static site root without existing_zone_id creates its own zone and delegates
# it at Namecheap, as before. Plans only, against mocked providers.

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
mock_provider "namecheap" {}

run "creates_a_zone_and_delegates_it" {
  command = plan

  assert {
    condition     = length(module.route53_zone) == 1 && length(data.aws_route53_zone.existing) == 0
    error_message = "Without existing_zone_id the root must create its own zone and look none up."
  }
  assert {
    condition     = length(aws_route53_record.existing_zone_validation) == 0
    error_message = "Without existing_zone_id the validation records belong to the zone module."
  }
}
