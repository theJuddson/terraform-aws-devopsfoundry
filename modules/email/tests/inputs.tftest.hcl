# Inputs that would publish a broken DMARC or MAIL FROM record are rejected at
# plan; valid spellings still pass. Plans only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
}

variables {
  name            = "demo"
  sender_domain   = "example.com"
  sender_zone_id  = "Z123EXAMPLE"
  dmarc_rua_email = "dmarc@example.com"
}

run "dmarc_policy_accepts_any_case" {
  command = plan

  variables {
    dmarc_policy = "Reject"
  }

  assert {
    condition     = aws_route53_record.dmarc.records == toset(["v=DMARC1; p=Reject; sp=Reject; rua=mailto:dmarc@example.com"])
    error_message = "DMARC tag values are case-insensitive; \"Reject\" must be accepted and published as written."
  }
}

run "dmarc_policy_rejects_unknown_value" {
  command = plan

  variables {
    dmarc_policy = "strict"
  }

  expect_failures = [var.dmarc_policy]
}

run "dmarc_rua_email_rejects_empty" {
  command = plan

  variables {
    dmarc_rua_email = ""
  }

  expect_failures = [var.dmarc_rua_email]
}

run "dmarc_rua_email_rejects_non_address" {
  command = plan

  variables {
    dmarc_rua_email = "dmarc@example"
  }

  expect_failures = [var.dmarc_rua_email]
}

run "dmarc_rua_email_rejects_tag_injection" {
  command = plan

  variables {
    dmarc_rua_email = "a@example.com;p=none"
  }

  expect_failures = [var.dmarc_rua_email]
}

run "mail_from_subdomain_accepts_multi_label" {
  command = plan

  variables {
    mail_from_subdomain = "bounce.mail"
  }

  assert {
    condition     = aws_ses_domain_mail_from.sender[0].mail_from_domain == "bounce.mail.example.com"
    error_message = "Dotted labels are a valid MAIL FROM subdomain."
  }
}

run "mail_from_subdomain_rejects_invalid_label" {
  command = plan

  variables {
    mail_from_subdomain = "mail_from"
  }

  expect_failures = [var.mail_from_subdomain]
}

run "mail_from_subdomain_rejects_leading_hyphen" {
  command = plan

  variables {
    mail_from_subdomain = "-mail"
  }

  expect_failures = [var.mail_from_subdomain]
}

run "mail_from_subdomain_rejects_trailing_dot" {
  command = plan

  variables {
    mail_from_subdomain = "mail."
  }

  expect_failures = [var.mail_from_subdomain]
}
