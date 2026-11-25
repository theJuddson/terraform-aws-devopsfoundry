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

run "extra_flags_go_on_the_command_line" {
  command = plan

  variables {
    extra_flags = ["--orgs", "--org-max-sources=100"]
  }

  assert {
    condition     = endswith(output.collector_flags, "--orgs --org-max-sources=100")
    error_message = "Extra flags follow the module's own."
  }
}

run "extra_flags_refuse_what_a_shell_would_read" {
  command = plan

  variables {
    extra_flags = ["--orgs; curl evil"]
  }

  expect_failures = [var.extra_flags]
}

# #87: a rules change replaced the instance, and the new one couldn't read the
# kept volume, whose files the old instance's users owned under other ids.
run "rules_reach_the_host_through_ssm_not_user_data" {
  command = plan

  variables {
    rules_yaml = "rules:\n  - name: disk-full\n    expr: disk_used_pct > 90\n"
  }

  assert {
    condition = (aws_ssm_parameter.rules[0].name == "/watchtower/demo-watchtower/rules"
      && aws_ssm_parameter.rules[0].tier == "Standard"
    && aws_ssm_parameter.rules[0].value == base64gzip(var.rules_yaml))
    error_message = "The rules go to a Standard SSM parameter, gzipped and base64-encoded."
  }
  assert {
    condition = (!strcontains(local.user_data, base64encode(var.rules_yaml))
      && !strcontains(local.user_data, base64gzip(var.rules_yaml))
    && !strcontains(local.user_data, "disk-full"))
    error_message = "The rules must not be in user data, or changing them replaces the instance."
  }
  assert {
    condition = (strcontains(local.user_data, "--name \"/watchtower/demo-watchtower/rules\"")
      && strcontains(local.user_data, "--region \"us-east-1\"")
      && strcontains(local.user_data, "OnCalendar=minutely")
    && strcontains(local.user_data, "systemctl enable --now watchtower-rules.timer"))
    error_message = "The host fetches the rules at boot and then every minute."
  }
  assert {
    condition     = strcontains(output.collector_flags, "--rules /etc/watchtower/rules.yaml")
    error_message = "The collector still reads the rules file the timer writes."
  }
}

run "the_kept_volume_belongs_to_the_same_ids_on_every_instance" {
  command = plan

  assert {
    condition = (strcontains(local.user_data, "groupadd --system --gid 61001 watchtower")
      && strcontains(local.user_data, "useradd --system --uid 61001 --gid watchtower")
      && strcontains(local.user_data, "groupadd --system --gid 61002 watchtower-agent")
    && strcontains(local.user_data, "useradd --system --uid 61002 --gid watchtower-agent"))
    error_message = "The collector's and agent's users get fixed ids before install.sh makes them."
  }
  assert {
    condition     = strcontains(local.user_data, "find /var/lib/watchtower \\( ! -user watchtower -o ! -group watchtower \\) -exec chown -h watchtower:watchtower {} +")
    error_message = "Files an earlier instance left under other ids are handed to the collector's user."
  }
  assert {
    condition     = strcontains(local.user_data, "mount -a\n\n# A volume") && !strcontains(local.user_data, "watchtower-rules")
    error_message = "The ownership fix runs after the mount; with no rules there is no rules timer."
  }
  assert {
    condition     = length(aws_ssm_parameter.rules) == 0
    error_message = "No rules, no parameter."
  }
}

run "rules_in_user_data_keeps_the_old_user_data" {
  command = plan

  variables {
    rules_yaml         = "rules: []\n"
    rules_in_user_data = true
  }

  assert {
    condition = (length(aws_ssm_parameter.rules) == 0
      && strcontains(local.user_data, "echo \"${base64encode("rules: []\n")}\" | base64 -d > /etc/watchtower/rules.yaml")
    && !strcontains(local.user_data, "61001"))
    error_message = "rules_in_user_data renders the pre-v1.25.0 user data."
  }
}

run "refuses_rules_that_are_not_yaml" {
  command = plan
  variables {
    rules_yaml = "rules: [unclosed\n"
  }
  expect_failures = [var.rules_yaml]
}

run "refuses_rules_too_big_for_the_parameter" {
  command = plan
  variables {
    rules_yaml = join("\n", [for i in range(200) : "# ${sha256(tostring(i))}"])
  }
  expect_failures = [var.rules_yaml]
}

# #87: the collector was down for good while its instance passed status checks.
run "health_alarm_is_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.health) == 0 && !strcontains(local.user_data, "watchtower-health")
    error_message = "Without health_alarm_actions there is no metric timer and no alarm (both are billed)."
  }
}

run "health_alarm_watches_the_collector_not_the_instance" {
  command = plan

  variables {
    health_alarm_actions = ["arn:aws:sns:us-east-1:111111111111:ops"]
  }

  assert {
    condition = (aws_cloudwatch_metric_alarm.health[0].namespace == "Watchtower"
      && aws_cloudwatch_metric_alarm.health[0].metric_name == "CollectorHealthy"
      && aws_cloudwatch_metric_alarm.health[0].dimensions["Collector"] == "demo-watchtower"
      && aws_cloudwatch_metric_alarm.health[0].comparison_operator == "LessThanThreshold"
      && aws_cloudwatch_metric_alarm.health[0].threshold == 1
    && aws_cloudwatch_metric_alarm.health[0].evaluation_periods == 5)
    error_message = "The alarm fires after 5 minutes of the host's health metric below 1."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.health[0].treat_missing_data == "breaching"
    error_message = "No data (no instance, user data that never got far) must count as down."
  }
  assert {
    condition = (aws_cloudwatch_metric_alarm.health[0].alarm_actions == toset(["arn:aws:sns:us-east-1:111111111111:ops"])
    && aws_cloudwatch_metric_alarm.health[0].ok_actions == toset(["arn:aws:sns:us-east-1:111111111111:ops"]))
    error_message = "The topics hear of both the outage and the recovery."
  }
  assert {
    condition = (strcontains(local.user_data, "--resolve \"watch.example.com:443:127.0.0.1\"")
      && strcontains(local.user_data, "--dimensions \"Collector=demo-watchtower\"")
      && !strcontains(local.user_data, "--insecure")
    && strcontains(local.user_data, "systemctl enable --now watchtower-health.timer"))
    error_message = "The host checks its own /healthz with the real certificate and reports every minute."
  }
  assert {
    condition     = strcontains(local.user_data, "watchtower-health.timer\n\nwork=$(mktemp -d)")
    error_message = "The health timer starts before the install, so a failed install reports 0."
  }
  assert {
    condition = anytrue([for c in one([for s in data.aws_iam_policy_document.host.statement : s.condition if s.sid == "PutTheHealthMetric"]) :
    c.variable == "cloudwatch:namespace" && contains(c.values, "Watchtower")])
    error_message = "The host may put metrics in the Watchtower namespace only."
  }
}

run "health_check_accepts_the_staging_certificate" {
  command = plan

  variables {
    health_alarm_actions = ["arn:aws:sns:us-east-1:111111111111:ops"]
    acme_directory       = "https://acme-staging-v02.api.letsencrypt.org/directory"
  }

  assert {
    condition     = strcontains(local.user_data, "curl -fsS --insecure --max-time 10")
    error_message = "A test deployment's staging certificate isn't trusted, so its check skips verification."
  }
}
