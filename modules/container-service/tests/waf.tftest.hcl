# Opt-in WAF on the ALB. Plans only, against a mocked provider: no AWS account
# is touched.

mock_provider "aws" {
  override_during = plan # known ARNs at plan time, so the association can be checked

  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/demo-alb/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults        = { arn = "arn:aws:logs:us-east-1:111111111111:log-group:aws-waf-logs-demo-alb" }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:111111111111:regional/webacl/demo-alb/mock" }
  }
}

variables {
  name                  = "demo"
  domain_name           = "example.com"
  zone_id               = "Z0000000000MOCK"
  certificate_arn       = "arn:aws:acm:us-east-1:111111111111:certificate/mock"
  vpc_id                = "vpc-mock"
  public_subnet_ids     = ["subnet-pub-a", "subnet-pub-b"]
  private_subnet_ids    = ["subnet-priv-a", "subnet-priv-b"]
  alb_security_group_id = "sg-alb"
  api_security_group_id = "sg-api"
}

run "default_has_no_waf" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.alb) == 0 && length(aws_wafv2_web_acl_association.alb) == 0
    error_message = "No web ACL unless asked for: it is billed monthly."
  }
}

run "create_waf_blocks_with_rate_limit_and_managed_rules" {
  command = plan

  variables {
    create_waf     = true
    waf_rate_limit = 500
  }

  assert {
    condition     = aws_wafv2_web_acl.alb[0].scope == "REGIONAL" && length(aws_wafv2_web_acl.alb[0].default_action[0].allow) == 1
    error_message = "The web ACL must be regional (ALB) and allow by default."
  }
  assert {
    condition = (
      length(aws_wafv2_web_acl.alb[0].rule) == 4 &&
      one([for r in aws_wafv2_web_acl.alb[0].rule : r.statement[0].rate_based_statement[0].limit if r.name == "rate-limit-per-ip"]) == 500 &&
      length(one([for r in aws_wafv2_web_acl.alb[0].rule : r.action[0].block if r.name == "rate-limit-per-ip"])) == 1
    )
    error_message = "Expected a blocking per-IP rate rule at waf_rate_limit plus the three default managed groups."
  }
  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.alb[0].rule : length(r.override_action[0].none) == 1 if r.name != "rate-limit-per-ip"
    ])
    error_message = "Managed rule groups must enforce their own actions (override none) unless waf_count_only."
  }
  assert {
    condition = (
      aws_wafv2_web_acl_association.alb[0].resource_arn == aws_lb.main[0].arn &&
      aws_wafv2_web_acl_association.alb[0].web_acl_arn == aws_wafv2_web_acl.alb[0].arn &&
      output.waf_web_acl_arn == aws_wafv2_web_acl.alb[0].arn
    )
    error_message = "The created web ACL must be attached to this stack's ALB and exposed as an output."
  }
}

run "count_only_and_rule_overrides" {
  command = plan

  variables {
    create_waf         = true
    waf_count_only     = true
    waf_rule_overrides = { AWSManagedRulesCommonRuleSet = ["SizeRestrictions_BODY", "NoUserAgent_HEADER"] }
  }

  assert {
    condition = (
      length(one([for r in aws_wafv2_web_acl.alb[0].rule : r.action[0].count if r.name == "rate-limit-per-ip"])) == 1 &&
      alltrue([for r in aws_wafv2_web_acl.alb[0].rule : length(r.override_action[0].count) == 1 if r.name != "rate-limit-per-ip"])
    )
    error_message = "waf_count_only must put every rule in count mode."
  }
  assert {
    condition = toset(one([
      for r in aws_wafv2_web_acl.alb[0].rule : [for o in r.statement[0].managed_rule_group_statement[0].rule_action_override : o.name]
      if r.name == "AWSManagedRulesCommonRuleSet"
    ])) == toset(["SizeRestrictions_BODY", "NoUserAgent_HEADER"])
    error_message = "waf_rule_overrides must count the named rules of that group."
  }
}

run "existing_web_acl_is_attached_not_created" {
  command = plan

  variables {
    waf_web_acl_arn = "arn:aws:wafv2:us-east-1:111111111111:regional/webacl/shared/abc"
  }

  assert {
    condition = (
      length(aws_wafv2_web_acl.alb) == 0 &&
      aws_wafv2_web_acl_association.alb[0].web_acl_arn == var.waf_web_acl_arn &&
      output.waf_web_acl_arn == var.waf_web_acl_arn
    )
    error_message = "waf_web_acl_arn must attach that ACL and create none."
  }
}

run "both_options_are_rejected" {
  command = plan

  variables {
    create_waf      = true
    waf_web_acl_arn = "arn:aws:wafv2:us-east-1:111111111111:regional/webacl/shared/abc"
  }

  expect_failures = [aws_wafv2_web_acl_association.alb]
}

run "bad_arn_is_rejected" {
  command = plan

  variables {
    waf_web_acl_arn = "arn:aws:wafv2:us-east-1:111111111111:global/webacl/cloudfront/abc"
  }

  expect_failures = [var.waf_web_acl_arn]
}

run "guest_app_on_shared_alb_creates_and_attaches_nothing" {
  command = plan

  variables {
    create_alb                  = false
    create_cluster              = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host/mock/https"
    existing_cluster_arn        = "arn:aws:ecs:us-east-1:111111111111:cluster/host"
    existing_cluster_name       = "host"
    create_waf                  = true
  }

  assert {
    condition     = length(aws_wafv2_web_acl.alb) == 0 && length(aws_wafv2_web_acl_association.alb) == 0 && output.waf_web_acl_arn == ""
    error_message = "A guest app must not create or attach a web ACL: the shared ALB's belongs to the host platform."
  }
}

# ── Request logging (#66) ─────────────────────────────
run "no_waf_logging_by_default" {
  command = plan

  variables {
    create_waf = true
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.waf) == 0 && length(aws_wafv2_web_acl_logging_configuration.alb) == 0 && output.waf_log_group == null
    error_message = "WAF logging is opt-in."
  }
}

run "waf_logging_keeps_blocked_and_counted_requests_with_credentials_redacted" {
  command = plan

  variables {
    create_waf  = true
    waf_logging = true
  }

  assert {
    condition     = aws_cloudwatch_log_group.waf[0].name == "aws-waf-logs-demo-alb" && aws_cloudwatch_log_group.waf[0].retention_in_days == 30
    error_message = "The log group must be named aws-waf-logs-..., which WAF requires, and keep 30 days by default."
  }
  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.alb[0].log_destination_configs == toset(["arn:aws:logs:us-east-1:111111111111:log-group:aws-waf-logs-demo-alb"])
    error_message = "The web ACL must log to that group."
  }
  assert {
    condition     = toset([for r in aws_wafv2_web_acl_logging_configuration.alb[0].redacted_fields : one(r.single_header).name]) == toset(["authorization", "cookie"])
    error_message = "Authorization and Cookie headers must be redacted."
  }
  assert {
    condition     = one(aws_wafv2_web_acl_logging_configuration.alb[0].logging_filter).default_behavior == "DROP"
    error_message = "Requests no rule acted on are dropped by default."
  }
  assert {
    condition     = toset([for c in one(one(aws_wafv2_web_acl_logging_configuration.alb[0].logging_filter).filter).condition : one(c.action_condition).action]) == toset(["BLOCK", "COUNT"])
    error_message = "Blocked and counted requests are kept."
  }
  assert {
    condition     = output.waf_log_group == "aws-waf-logs-demo-alb"
    error_message = "The output must name the log group."
  }
}

run "all_requests_can_be_logged" {
  command = plan

  variables {
    create_waf             = true
    waf_logging            = true
    waf_log_all_requests   = true
    waf_log_retention_days = 7
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.alb[0].logging_filter) == 0 && aws_cloudwatch_log_group.waf[0].retention_in_days == 7
    error_message = "waf_log_all_requests removes the filter; retention follows the variable."
  }
}

run "waf_logging_needs_a_waf_this_module_creates" {
  command = plan

  variables {
    waf_logging = true
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.waf) == 0
    error_message = "Without create_waf there is no web ACL of ours to log."
  }
}

run "waf_log_retention_must_be_one_cloudwatch_accepts" {
  command = plan

  variables {
    waf_log_retention_days = 10
  }

  expect_failures = [var.waf_log_retention_days]
}
