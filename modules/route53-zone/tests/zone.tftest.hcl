# The hosted zone and the ACM validation records, one per distinct record name.
# Plans only, against a mocked AWS provider.

mock_provider "aws" {
  # Known at plan so the records' zone can be checked.
  mock_resource "aws_route53_zone" {
    override_during = plan
    defaults        = { zone_id = "Z0EXAMPLE" }
  }
}

variables {
  domain_name = "example.com"
}

run "zone_with_no_validation_records" {
  command = plan

  assert {
    condition     = aws_route53_zone.main.name == "example.com"
    error_message = "The zone must be for the given domain."
  }
  assert {
    condition     = length(aws_route53_record.acm_validation) == 0
    error_message = "With no validation options, no records are created."
  }
}

# The apex and its wildcard usually share one validation record.
run "shared_validation_record_is_created_once" {
  command = plan

  variables {
    acm_domain_validation_options = [
      { domain_name = "example.com", resource_record_name = "_abc.example.com.", resource_record_type = "CNAME", resource_record_value = "_xyz.acm-validations.aws." },
      { domain_name = "*.example.com", resource_record_name = "_abc.example.com.", resource_record_type = "CNAME", resource_record_value = "_xyz.acm-validations.aws." },
    ]
  }

  assert {
    condition     = length(aws_route53_record.acm_validation) == 1
    error_message = "A record name shared by the apex and the wildcard must be created once."
  }
  assert {
    condition = alltrue([
      aws_route53_record.acm_validation["_abc.example.com."].name == "_abc.example.com.",
      aws_route53_record.acm_validation["_abc.example.com."].type == "CNAME",
      toset(aws_route53_record.acm_validation["_abc.example.com."].records) == toset(["_xyz.acm-validations.aws."]),
      aws_route53_record.acm_validation["_abc.example.com."].zone_id == "Z0EXAMPLE",
    ])
    error_message = "The validation record must be the CNAME ACM asked for, in this zone."
  }
  assert {
    condition     = aws_route53_record.acm_validation["_abc.example.com."].allow_overwrite
    error_message = "A validation record left from an earlier certificate must be overwritten, not fail the apply."
  }
}

run "distinct_validation_records_are_each_created" {
  command = plan

  variables {
    acm_domain_validation_options = [
      { domain_name = "example.com", resource_record_name = "_a.example.com.", resource_record_type = "CNAME", resource_record_value = "_1.acm-validations.aws." },
      { domain_name = "www.example.com", resource_record_name = "_b.www.example.com.", resource_record_type = "CNAME", resource_record_value = "_2.acm-validations.aws." },
    ]
  }

  assert {
    condition     = length(aws_route53_record.acm_validation) == 2
    error_message = "Each distinct validation record name gets its own record."
  }
  assert {
    condition     = toset(aws_route53_record.acm_validation["_b.www.example.com."].records) == toset(["_2.acm-validations.aws."])
    error_message = "Each record must carry its own validation value."
  }
}
