# The certificate covers the apex, plus the wildcard unless it is turned off, and
# is validated by DNS. Plans only, against a mocked AWS provider.

mock_provider "aws" {}

variables {
  domain_name = "example.com"
}

run "apex_and_wildcard_by_default" {
  command = plan

  assert {
    condition     = aws_acm_certificate.main.domain_name == "example.com"
    error_message = "The certificate must be issued for the apex domain."
  }
  assert {
    condition     = toset(aws_acm_certificate.main.subject_alternative_names) == toset(["*.example.com"])
    error_message = "By default the certificate must also cover *.example.com, and nothing else."
  }
  assert {
    condition     = aws_acm_certificate.main.validation_method == "DNS"
    error_message = "The certificate must be validated by DNS, so route53-zone can create the records."
  }
  assert {
    condition     = aws_acm_certificate.main.tags["Name"] == "example.com"
    error_message = "The certificate must be named after its domain."
  }
}

run "apex_only_without_wildcard" {
  command = plan

  variables {
    include_wildcard = false
  }

  assert {
    condition     = length(aws_acm_certificate.main.subject_alternative_names) == 0
    error_message = "include_wildcard = false must issue a certificate for exactly the apex."
  }
}
