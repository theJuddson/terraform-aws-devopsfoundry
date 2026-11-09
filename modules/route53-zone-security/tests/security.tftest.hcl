# DNSSEC signing and query logging for a hosted zone: nothing by default, the
# right key and policies when asked, and a refusal outside us-east-1. Plans only,
# against a mocked provider: no AWS account is touched.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  # Real log group ARNs are known only after apply; the policy needs a valid one.
  mock_resource "aws_cloudwatch_log_group" {
    override_during = plan
    defaults        = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/route53/example.com" }
  }
  mock_resource "aws_kms_key" {
    override_during = plan
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
      key_id = "11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  zone_id   = "Z0000000000MOCK"
  zone_name = "example.com"
}

run "nothing_by_default" {
  command = plan

  assert {
    condition     = length(aws_kms_key.dnssec) == 0 && length(aws_route53_key_signing_key.this) == 0 && length(aws_route53_hosted_zone_dnssec.this) == 0
    error_message = "DNSSEC needs registrar work and a careful off-switch; nothing may be planned unless enable_dnssec = true."
  }
  assert {
    condition     = length(aws_cloudwatch_log_group.query_logs) == 0 && length(aws_route53_query_log.this) == 0
    error_message = "Query logs are billed; nothing may be planned unless enable_query_logging = true."
  }
  assert {
    condition     = output.ds_record == null && output.ds_record_fields == null && output.query_log_group_name == null
    error_message = "Outputs must be null for features that are off."
  }
}

run "dnssec_signs_with_an_asymmetric_key_route53_may_use" {
  command = plan

  variables {
    enable_dnssec = true
  }

  assert {
    condition     = aws_kms_key.dnssec[0].customer_master_key_spec == "ECC_NIST_P256" && aws_kms_key.dnssec[0].key_usage == "SIGN_VERIFY"
    error_message = "Route53 DNSSEC requires an ECC_NIST_P256 SIGN_VERIFY key."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.dnssec[0].statement :
      toset(s.actions) == toset(["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign"]) &&
      one(s.principals).identifiers == toset(["dnssec-route53.amazonaws.com"]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && c.values == tolist(["123456789012"])])
    ])
    error_message = "The key policy must let Route53 DNSSEC sign, only on behalf of this account."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.dnssec[0].statement :
      toset(s.actions) == toset(["kms:CreateGrant"]) && one(s.condition).variable == "kms:GrantIsForAWSResource"
    ])
    error_message = "Route53 must be able to create grants on the key, only for AWS resources."
  }
  assert {
    condition     = aws_route53_key_signing_key.this[0].hosted_zone_id == "Z0000000000MOCK" && aws_route53_key_signing_key.this[0].key_management_service_arn == aws_kms_key.dnssec[0].arn
    error_message = "The key-signing key must sign the given zone with the module's KMS key."
  }
  assert {
    condition     = length(aws_route53_hosted_zone_dnssec.this) == 1 && aws_kms_alias.dnssec[0].name == "alias/dnssec/example-com"
    error_message = "Signing must be switched on for the zone, and the key aliased after it."
  }
}

run "query_logging_writes_to_a_us_east_1_log_group" {
  command = plan

  variables {
    enable_query_logging     = true
    query_log_retention_days = 14
  }

  assert {
    condition     = aws_cloudwatch_log_group.query_logs[0].name == "/aws/route53/example.com" && aws_cloudwatch_log_group.query_logs[0].retention_in_days == 14
    error_message = "Query logs must go to /aws/route53/<zone>, kept for query_log_retention_days."
  }
  assert {
    condition     = aws_route53_query_log.this[0].zone_id == "Z0000000000MOCK" && output.query_log_group_name == "/aws/route53/example.com"
    error_message = "Query logging must be switched on for the given zone."
  }
  assert {
    condition = (
      one(one(data.aws_iam_policy_document.query_logs[0].statement).principals).identifiers == toset(["route53.amazonaws.com"]) &&
      anytrue([for c in one(data.aws_iam_policy_document.query_logs[0].statement).condition : c.variable == "aws:SourceArn" && c.values == tolist(["arn:aws:route53:::hostedzone/Z0000000000MOCK"])])
    )
    error_message = "Only Route53, logging for this zone, may write to the log group."
  }
  assert {
    condition     = aws_cloudwatch_log_resource_policy.query_logs[0].policy_name == "route53-query-logs-example-com"
    error_message = "The resource policy must be named after the zone, so zones don't overwrite each other's."
  }
}

run "dnssec_refused_outside_us_east_1" {
  command = plan

  variables {
    enable_dnssec = true
  }

  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-1", name = "eu-west-1" }
  }

  expect_failures = [aws_kms_key.dnssec]
}

run "query_logging_refused_outside_us_east_1" {
  command = plan

  variables {
    enable_query_logging = true
  }

  override_data {
    target = data.aws_region.current
    values = { region = "eu-west-1", name = "eu-west-1" }
  }

  expect_failures = [aws_cloudwatch_log_group.query_logs]
}

run "query_log_retention_is_checked" {
  command = plan

  variables {
    enable_query_logging     = true
    query_log_retention_days = 10
  }

  expect_failures = [var.query_log_retention_days]
}
