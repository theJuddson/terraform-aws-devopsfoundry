# SES sending domain: the DNS records that verify and authenticate it (SES
# verification, DKIM, DMARC, optional custom MAIL FROM), the SMTP user and its
# secret, and the optional bounce/complaint topic. Plans only, against a mocked
# AWS provider: no account is touched.

mock_provider "aws" {
  # The provider validates policy JSON; a random string would be rejected
  # whenever the document is read at plan.
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

run "defaults_verify_domain_with_dkim_and_dmarc" {
  command = plan

  assert {
    condition     = aws_ses_domain_identity.sender.domain == "example.com" && aws_ses_domain_dkim.sender.domain == "example.com"
    error_message = "The SES identity and DKIM must be for sender_domain."
  }
  assert {
    condition     = aws_route53_record.ses_verification.name == "_amazonses.example.com" && aws_route53_record.ses_verification.type == "TXT" && aws_route53_record.ses_verification.zone_id == "Z123EXAMPLE"
    error_message = "SES verification needs a _amazonses TXT record in the sender zone."
  }
  assert {
    condition     = length(aws_route53_record.dkim) == 3 && alltrue([for r in aws_route53_record.dkim : r.type == "CNAME" && r.zone_id == "Z123EXAMPLE"])
    error_message = "SES issues three DKIM tokens; each needs a CNAME in the sender zone."
  }
  assert {
    condition     = aws_route53_record.dmarc.name == "_dmarc.example.com" && aws_route53_record.dmarc.type == "TXT" && aws_route53_record.dmarc.zone_id == "Z123EXAMPLE"
    error_message = "DMARC must be published as a _dmarc TXT record in the sender zone."
  }
  assert {
    condition     = tolist(aws_route53_record.dmarc.records) == tolist(["v=DMARC1; p=none; sp=none; rua=mailto:dmarc@example.com"])
    error_message = "The default DMARC policy must be p=none for the domain and subdomains, reporting to dmarc_rua_email."
  }
  assert {
    condition     = length(aws_ses_domain_mail_from.sender) == 0 && length(aws_route53_record.mail_from_mx) == 0 && length(aws_route53_record.mail_from_spf) == 0
    error_message = "No custom MAIL FROM domain or its records unless mail_from_subdomain is set."
  }
  assert {
    condition     = aws_iam_user.ses_smtp.name == "demo-ses-smtp" && aws_iam_user.ses_smtp.path == "/system/"
    error_message = "The SMTP user must be <name>-ses-smtp under /system/."
  }
  assert {
    condition     = aws_iam_user_policy.ses_send.user == "demo-ses-smtp"
    error_message = "The send policy must be attached to the SMTP user."
  }
  assert {
    condition     = aws_secretsmanager_secret.smtp.name == "demo/ses/smtp" && aws_secretsmanager_secret.smtp.recovery_window_in_days == 7
    error_message = "SMTP credentials must live in the <name>/ses/smtp secret."
  }
  assert {
    condition     = output.smtp_host == "email-smtp.us-east-1.amazonaws.com"
    error_message = "The SMTP host must be the default region's SES endpoint."
  }
  assert {
    condition     = length(aws_sns_topic.ses_notifications) == 0 && length(aws_sns_topic_policy.ses_notifications) == 0 && length(data.aws_iam_policy_document.ses_notifications_topic) == 0
    error_message = "No notification topic unless enable_notifications is set."
  }
  assert {
    condition     = length(aws_ses_identity_notification_topic.bounce) == 0 && length(aws_ses_identity_notification_topic.complaint) == 0
    error_message = "No bounce/complaint wiring unless enable_notifications is set."
  }
  assert {
    condition     = output.notifications_topic_arn == null
    error_message = "The notifications topic output must be null when disabled."
  }
}

run "dmarc_policy_applies_to_domain_and_subdomains" {
  command = plan

  variables {
    dmarc_policy = "reject"
  }

  assert {
    condition     = tolist(aws_route53_record.dmarc.records) == tolist(["v=DMARC1; p=reject; sp=reject; rua=mailto:dmarc@example.com"])
    error_message = "dmarc_policy must set both p= and sp=."
  }
}

run "mail_from_subdomain_adds_spf_aligned_return_path" {
  command = plan

  variables {
    mail_from_subdomain = "mail"
  }

  assert {
    condition     = length(aws_ses_domain_mail_from.sender) == 1 && aws_ses_domain_mail_from.sender[0].mail_from_domain == "mail.example.com"
    error_message = "mail_from_subdomain must set the MAIL FROM domain to <subdomain>.<sender_domain>."
  }
  assert {
    condition     = aws_ses_domain_mail_from.sender[0].behavior_on_mx_failure == "UseDefaultValue"
    error_message = "MAIL FROM must fall back to amazonses.com while DNS propagates, or mail bounces during cutover."
  }
  assert {
    condition     = length(aws_route53_record.mail_from_mx) == 1 && aws_route53_record.mail_from_mx[0].name == "mail.example.com" && aws_route53_record.mail_from_mx[0].type == "MX"
    error_message = "The MAIL FROM domain needs an MX record."
  }
  assert {
    condition     = tolist(aws_route53_record.mail_from_mx[0].records) == tolist(["10 feedback-smtp.us-east-1.amazonses.com"])
    error_message = "The MAIL FROM MX record must point at the region's SES feedback endpoint."
  }
  assert {
    condition     = length(aws_route53_record.mail_from_spf) == 1 && aws_route53_record.mail_from_spf[0].name == "mail.example.com" && aws_route53_record.mail_from_spf[0].type == "TXT"
    error_message = "The MAIL FROM domain needs an SPF TXT record."
  }
  assert {
    condition     = tolist(aws_route53_record.mail_from_spf[0].records) == tolist(["v=spf1 include:amazonses.com ~all"])
    error_message = "The SPF record must authorise SES to send for the MAIL FROM domain."
  }
}

run "region_sets_smtp_endpoint" {
  command = plan

  variables {
    aws_region          = "eu-west-1"
    mail_from_subdomain = "mail"
  }

  assert {
    condition     = output.smtp_host == "email-smtp.eu-west-1.amazonaws.com"
    error_message = "The SMTP host must be the SES endpoint of aws_region."
  }
  assert {
    condition     = tolist(aws_route53_record.mail_from_mx[0].records) == tolist(["10 feedback-smtp.eu-west-1.amazonses.com"])
    error_message = "The MAIL FROM MX record must point at aws_region's SES feedback endpoint."
  }
}

run "notifications_wire_bounces_and_complaints_to_topic" {
  command = plan

  variables {
    enable_notifications = true
  }

  assert {
    condition     = length(aws_sns_topic.ses_notifications) == 1 && aws_sns_topic.ses_notifications[0].name == "demo-ses-notifications"
    error_message = "enable_notifications must create the <name>-ses-notifications topic."
  }
  assert {
    condition     = length(aws_sns_topic_policy.ses_notifications) == 1 && length(data.aws_iam_policy_document.ses_notifications_topic) == 1
    error_message = "SES needs a topic policy allowing it to publish."
  }
  assert {
    condition     = length(aws_ses_identity_notification_topic.bounce) == 1 && aws_ses_identity_notification_topic.bounce[0].notification_type == "Bounce" && aws_ses_identity_notification_topic.bounce[0].identity == "example.com"
    error_message = "Bounces from the sender domain must be sent to the topic."
  }
  assert {
    condition     = length(aws_ses_identity_notification_topic.complaint) == 1 && aws_ses_identity_notification_topic.complaint[0].notification_type == "Complaint" && aws_ses_identity_notification_topic.complaint[0].identity == "example.com"
    error_message = "Complaints from the sender domain must be sent to the topic."
  }
}
