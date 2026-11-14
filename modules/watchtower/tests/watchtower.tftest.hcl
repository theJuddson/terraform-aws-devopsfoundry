# The collector host: 443 only, a fixed address, DNS when a zone is given, and an
# instance role that may read only its release object and send only as its
# identity. Plans only, against a mocked AWS provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-mock", availability_zone = "us-east-1a" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-fromssm", value = "ami-fromssm" }
  }
  mock_resource "aws_instance" {
    override_during = plan
    defaults        = { id = "i-0mock" }
  }
  mock_resource "aws_eip" {
    override_during = plan
    defaults        = { public_ip = "203.0.113.10" }
  }
}

variables {
  name           = "demo-watchtower"
  subnet_id      = "subnet-a"
  hostname       = "watch.example.com"
  release_url    = "https://example.com/watchtower_v0.1.0_linux_arm64.tar.gz"
  release_sha256 = "4541408e81809615f6eed04671ad74c86530243f4e8ba57e48d939366ad308c9"
}

run "defaults" {
  command = plan

  assert {
    condition     = output.url == "https://watch.example.com"
    error_message = "url must be the hostname over HTTPS."
  }
  assert {
    condition = (startswith(output.deploy_token_command, "aws ssm start-session --target i-0mock --document-name AWS-StartNonInteractiveCommand ")
      && strcontains(output.deploy_token_command, "watchtower admin --data /var/lib/watchtower/collector deploy-token <name>")
    && endswith(output.deploy_token_command, "| aws ssm put-parameter --name <parameter> --type SecureString --value file:///dev/stdin"))
    error_message = "deploy_token_command must mint the token over SSM and store it from stdin."
  }
  assert {
    condition = (length(aws_vpc_security_group_ingress_rule.https) == 1
      && aws_vpc_security_group_ingress_rule.https["0.0.0.0/0"].from_port == 443
    && aws_vpc_security_group_ingress_rule.https["0.0.0.0/0"].to_port == 443)
    error_message = "The only inbound rule is 443 from ingress_cidr_blocks."
  }
  assert {
    condition     = length(aws_route53_record.this) == 0
    error_message = "Without zone_id no DNS record is made."
  }
  assert {
    condition     = length(data.aws_iam_policy_document.host.statement) == 0
    error_message = "An https release without mail needs no permissions beyond SSM."
  }
  assert {
    condition = (strcontains(output.collector_flags, "--acme-domain watch.example.com")
      && strcontains(output.collector_flags, "--origin https://watch.example.com")
      && strcontains(output.collector_flags, "--retention 72h")
      && !strcontains(output.collector_flags, "--ses-region")
      && !strcontains(output.collector_flags, "--rules")
    && !strcontains(output.collector_flags, "--acme-directory"))
    error_message = "Default flags: ACME for the hostname, no mail, no rules, production CA."
  }
}

run "s3_release_mail_rules_and_dns" {
  command = plan

  variables {
    release_url      = "s3://artifacts-bucket/watchtower/v0.1.0/watchtower_v0.1.0_linux_arm64.tar.gz"
    mail_from        = "watchtower@example.com"
    ses_identity_arn = "arn:aws:ses:us-east-1:111111111111:identity/example.com"
    rules_yaml       = "rules: []\n"
    zone_id          = "Z0EXAMPLE"
    acme_directory   = "https://acme-staging-v02.api.letsencrypt.org/directory"
  }

  assert {
    condition = (one([for s in data.aws_iam_policy_document.host.statement : s.resources if s.sid == "ReadTheRelease"])
    == toset(["arn:aws:s3:::artifacts-bucket/watchtower/v0.1.0/watchtower_v0.1.0_linux_arm64.tar.gz"]))
    error_message = "The host may read only its release object."
  }
  assert {
    condition = (one([for s in data.aws_iam_policy_document.host.statement : s.resources if s.sid == "SendAsTheIdentity"])
    == toset(["arn:aws:ses:us-east-1:111111111111:identity/*"]))
    error_message = "SES checks recipients' identities too, so the host may send to any identity in its identity's account and region."
  }
  assert {
    condition = anytrue([for c in one([for s in data.aws_iam_policy_document.host.statement : s.condition if s.sid == "SendAsTheIdentity"]) :
    c.test == "StringEquals" && c.variable == "ses:FromAddress" && contains(c.values, "watchtower@example.com")])
    error_message = "The host may send only as mail_from."
  }
  assert {
    condition     = aws_route53_record.this[0].records == toset(["203.0.113.10"]) && aws_route53_record.this[0].name == "watch.example.com"
    error_message = "The A record points the hostname at the fixed address."
  }
  assert {
    condition = (strcontains(output.collector_flags, "--ses-region us-east-1 --smtp-from watchtower@example.com")
      && strcontains(output.collector_flags, "--rules /etc/watchtower/rules.yaml")
    && strcontains(output.collector_flags, "--acme-directory https://acme-staging-v02.api.letsencrypt.org/directory"))
    error_message = "Mail, rules and the CA reach the collector's flags."
  }
}

run "mail_needs_an_identity" {
  command = plan
  variables {
    mail_from = "watchtower@example.com"
  }
  expect_failures = [aws_eip.this]
}

run "refuses_a_bad_checksum" {
  command = plan
  variables {
    release_sha256 = "not-a-sha"
  }
  expect_failures = [var.release_sha256]
}

run "refuses_a_bad_url" {
  command = plan
  variables {
    release_url = "http://example.com/watchtower.tar.gz"
  }
  expect_failures = [var.release_url]
}
