# A static site root with existing_zone_id (bin/new-site --existing-zone) adds
# its records to that zone: no zone is created, nothing is overwritten, and the
# root has no Namecheap provider at all (no mock for it here: configuring one
# would fail without credentials). Plans only, against mocked providers. A
# private zone is refused by bin/new-site's lookup; the mock can't set
# private_zone, so that refusal is tested in tests/cli.

mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id      = "Z0EXISTING"
      name         = "example.com"
      private_zone = false
      name_servers = ["ns-1.awsdns-01.org"]
    }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
  # The apex and its wildcard share one validation record; known at plan so the
  # records' for_each can be checked.
  mock_resource "aws_acm_certificate" {
    override_during = plan
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc"
      domain_validation_options = [
        { domain_name = "example.com", resource_record_name = "_abc.example.com.", resource_record_type = "CNAME", resource_record_value = "_xyz.acm-validations.aws." },
        { domain_name = "*.example.com", resource_record_name = "_abc.example.com.", resource_record_type = "CNAME", resource_record_value = "_xyz.acm-validations.aws." },
      ]
    }
  }
}

variables {
  existing_zone_id = "Z0EXISTING"
}

run "apex_site_uses_the_existing_zone" {
  command = plan

  assert {
    condition     = length(module.route53_zone) == 0
    error_message = "With existing_zone_id no zone may be created."
  }
  assert {
    condition     = length(aws_route53_record.existing_zone_validation) == 1
    error_message = "The apex and its wildcard share one validation record, created once."
  }
  assert {
    condition = alltrue([for r in aws_route53_record.existing_zone_validation :
    r.zone_id == "Z0EXISTING" && r.allow_overwrite == false && r.name == "_abc.example.com."])
    error_message = "Validation records must go into the existing zone and never overwrite a record there."
  }
  assert {
    condition     = output.name_servers == tolist(["ns-1.awsdns-01.org"])
    error_message = "name_servers must be the existing zone's."
  }
}

run "subdomain_site_in_a_parent_zone" {
  command = plan

  variables {
    domain_name = "blog.example.com"
    include_www = false
  }

  assert {
    condition     = length(module.route53_zone) == 0 && length(data.aws_route53_zone.existing) == 1
    error_message = "A subdomain site must use the parent zone and create none."
  }
}

run "refuses_a_zone_that_is_not_the_domain_or_a_parent" {
  command = plan

  override_data {
    target = data.aws_route53_zone.existing[0]
    values = { zone_id = "Z0OTHER", name = "other.com", private_zone = false }
  }

  expect_failures = [data.aws_route53_zone.existing]
}

run "refuses_a_zone_whose_name_only_ends_like_the_domain" {
  command = plan

  override_data {
    target = data.aws_route53_zone.existing[0]
    values = { zone_id = "Z0LOOKALIKE", name = "ample.com", private_zone = false }
  }

  expect_failures = [data.aws_route53_zone.existing]
}
