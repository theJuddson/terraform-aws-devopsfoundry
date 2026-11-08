# Which records the module plans: apex and www aliases to CloudFront always,
# Google Workspace MX and DKIM only when asked. Plans only, against a mocked
# provider: no AWS account is touched.

mock_provider "aws" {}

variables {
  domain_name               = "example.com"
  zone_id                   = "Z0000000000MOCK"
  cloudfront_domain_name    = "d111111abcdef8.cloudfront.net"
  cloudfront_hosted_zone_id = "Z2FDTNDATAQYW2"
}

run "defaults_alias_apex_and_www_to_cloudfront_without_email" {
  command = plan

  assert {
    condition = (
      aws_route53_record.apex_a.name == "example.com" && aws_route53_record.apex_a.type == "A" &&
      aws_route53_record.apex_aaaa.name == "example.com" && aws_route53_record.apex_aaaa.type == "AAAA"
    )
    error_message = "The apex must resolve over both IPv4 and IPv6."
  }
  assert {
    condition = (
      aws_route53_record.www_a.name == "www.example.com" && aws_route53_record.www_a.type == "A" &&
      aws_route53_record.www_aaaa.name == "www.example.com" && aws_route53_record.www_aaaa.type == "AAAA"
    )
    error_message = "www must resolve over both IPv4 and IPv6."
  }
  assert {
    condition = alltrue([
      for r in [aws_route53_record.apex_a, aws_route53_record.apex_aaaa, aws_route53_record.www_a, aws_route53_record.www_aaaa] :
      r.zone_id == "Z0000000000MOCK" &&
      r.alias[0].name == "d111111abcdef8.cloudfront.net" &&
      r.alias[0].zone_id == "Z2FDTNDATAQYW2"
    ])
    error_message = "Every alias must live in the given zone and point at the CloudFront distribution."
  }
  assert {
    condition     = length(aws_route53_record.mx) == 0 && length(aws_route53_record.google_dkim) == 0
    error_message = "No email records unless Google email is enabled."
  }
}

run "google_email_without_dkim_key_adds_mx_only" {
  command = plan

  variables {
    enable_google_email = true
  }

  assert {
    condition = (
      length(aws_route53_record.mx) == 1 &&
      aws_route53_record.mx[0].name == "example.com" &&
      aws_route53_record.mx[0].records == toset(["1 SMTP.GOOGLE.COM."])
    )
    error_message = "Enabling Google email must route the domain's mail to Google."
  }
  assert {
    condition     = length(aws_route53_record.google_dkim) == 0
    error_message = "No DKIM record may be planned without a key."
  }
}

run "dkim_key_ignored_while_email_disabled" {
  command = plan

  variables {
    google_dkim_key = "v=DKIM1; k=rsa; p=short"
  }

  assert {
    condition     = length(aws_route53_record.mx) == 0 && length(aws_route53_record.google_dkim) == 0
    error_message = "A DKIM key alone must not create email records."
  }
}

run "short_dkim_key_is_one_txt_string" {
  command = plan

  variables {
    enable_google_email = true
    google_dkim_key     = "v=DKIM1; k=rsa; p=short"
  }

  assert {
    condition = (
      length(aws_route53_record.google_dkim) == 1 &&
      aws_route53_record.google_dkim[0].name == "google._domainkey.example.com" &&
      aws_route53_record.google_dkim[0].type == "TXT" &&
      aws_route53_record.google_dkim[0].records == toset(["v=DKIM1; k=rsa; p=short"])
    )
    error_message = "A key under 255 characters must be published as a single TXT string."
  }
}

run "long_dkim_key_is_split_into_255_char_strings" {
  command = plan

  variables {
    enable_google_email = true
    # 300 characters: one full 255-character segment plus 45.
    google_dkim_key = "${join("", [for i in range(255) : "a"])}${join("", [for i in range(45) : "b"])}"
  }

  assert {
    condition     = aws_route53_record.google_dkim[0].records == toset(["${join("", [for i in range(255) : "a"])}\" \"${join("", [for i in range(45) : "b"])}"])
    error_message = "A key over 255 characters must be split into quoted 255-character strings, or Route53 rejects it."
  }
}
