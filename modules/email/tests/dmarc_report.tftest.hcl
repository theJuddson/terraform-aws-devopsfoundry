# DMARC aggregate reports sent to another domain need that domain's consent
# (RFC 7489 7.1): a <sender>._report._dmarc.<report domain> TXT record. The module
# creates it only in a zone the caller names, and otherwise says what to add.
# Plans only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name           = "demo"
  sender_domain  = "example.com"
  sender_zone_id = "Z123EXAMPLE"
}

run "same_domain_reports_need_no_authorization" {
  command = plan
  variables { dmarc_rua_email = "dmarc@example.com" }

  assert {
    condition     = length(aws_route53_record.dmarc_report_auth) == 0 && output.dmarc_report_authorization == null
    error_message = "Reports to the sender's own domain need no authorization record."
  }
}

# A parent or subdomain of the sender is the same organization.
run "parent_and_subdomain_reports_need_no_authorization" {
  command = plan
  variables {
    sender_domain   = "app.example.com"
    dmarc_rua_email = "dmarc@example.com"
  }

  assert {
    condition     = output.dmarc_report_authorization == null
    error_message = "Reports to the sender's parent domain need no authorization record."
  }
}

run "reports_to_a_subdomain_need_no_authorization" {
  command = plan
  variables { dmarc_rua_email = "dmarc@reports.example.com" }

  assert {
    condition     = output.dmarc_report_authorization == null
    error_message = "Reports to a subdomain of the sender need no authorization record."
  }
}

# The default keeps today's behavior: nothing is created in another zone.
run "another_domain_without_a_zone_reports_the_record_to_add" {
  command = plan
  variables { dmarc_rua_email = "dmarc@Reports.Example.NET" }

  assert {
    condition     = length(aws_route53_record.dmarc_report_auth) == 0
    error_message = "Without dmarc_report_zone_id, no record may be created in the report domain."
  }
  assert {
    condition = output.dmarc_report_authorization == {
      name    = "example.com._report._dmarc.reports.example.net"
      type    = "TXT"
      value   = "v=DMARC1"
      created = false
    }
    error_message = "The output must give the exact authorization record to add, in lower case, and say it was not created."
  }
}

run "another_domain_with_its_zone_creates_the_record" {
  command = plan
  variables {
    dmarc_rua_email      = "dmarc@example.net"
    dmarc_report_zone_id = "Z999REPORTS"
  }

  assert {
    condition = alltrue([
      aws_route53_record.dmarc_report_auth[0].zone_id == "Z999REPORTS",
      aws_route53_record.dmarc_report_auth[0].name == "example.com._report._dmarc.example.net",
      aws_route53_record.dmarc_report_auth[0].type == "TXT",
      tolist(aws_route53_record.dmarc_report_auth[0].records) == tolist(["v=DMARC1"]),
    ])
    error_message = "The authorization record must be a v=DMARC1 TXT record at <sender>._report._dmarc.<report domain>, in the named zone."
  }
  assert {
    condition     = output.dmarc_report_authorization.created
    error_message = "The output must say the record was created."
  }
}

# A zone named for a same-domain address is ignored, not used to write a record.
run "a_zone_for_a_same_domain_address_creates_nothing" {
  command = plan
  variables {
    dmarc_rua_email      = "dmarc@example.com"
    dmarc_report_zone_id = "Z999REPORTS"
  }

  assert {
    condition     = length(aws_route53_record.dmarc_report_auth) == 0
    error_message = "No authorization record is needed for the sender's own domain."
  }
}

# A domain that merely ends with the sender's name is another organization.
run "a_lookalike_suffix_is_another_domain" {
  command = plan
  variables { dmarc_rua_email = "dmarc@notexample.com" }

  assert {
    condition     = output.dmarc_report_authorization != null
    error_message = "notexample.com is not a subdomain of example.com."
  }
}
