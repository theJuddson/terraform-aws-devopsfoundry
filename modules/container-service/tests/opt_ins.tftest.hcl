# Opt-in observability and protection: off by default, on when asked. Plans
# only, against a mocked provider: no AWS account is touched.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::127311923021:root" }
  }
  # Real bucket ARNs are known only after apply; the policy needs a valid one.
  mock_resource "aws_s3_bucket" {
    override_during = plan
    defaults = {
      id  = "demo-alb-logs-111111111111"
      arn = "arn:aws:s3:::demo-alb-logs-111111111111"
    }
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

run "defaults_leave_insights_and_deletion_protection_off" {
  command = plan

  assert {
    condition     = one([for s in aws_ecs_cluster.main[0].setting : s.value if s.name == "containerInsights"]) == "disabled"
    error_message = "Container Insights must stay off unless asked for: it is billed per metric."
  }
  assert {
    condition     = aws_lb.main[0].enable_deletion_protection == false
    error_message = "ALB deletion protection must stay off by default so destroy-app works."
  }
}

run "opt_ins_turn_them_on" {
  command = plan

  variables {
    container_insights      = true
    alb_deletion_protection = true
  }

  assert {
    condition     = one([for s in aws_ecs_cluster.main[0].setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "container_insights = true must enable Container Insights on the cluster."
  }
  assert {
    condition     = aws_lb.main[0].enable_deletion_protection == true
    error_message = "alb_deletion_protection = true must protect the ALB."
  }
}

run "log_group_uses_cloudwatch_encryption_by_default" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.app.kms_key_id == null
    error_message = "Without log_kms_key_arn the log group must use CloudWatch's default encryption."
  }
}

run "customer_managed_keys_for_logs_and_secrets" {
  command = plan

  variables {
    log_kms_key_arn      = "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    secrets              = { API_TOKEN = "arn:aws:secretsmanager:us-east-1:111111111111:secret:demo/token-AbCdEf" }
    secrets_kms_key_arns = ["arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"]
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.kms_key_id == "arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"
    error_message = "log_kms_key_arn must encrypt the app's log group."
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.task_execution_secrets[0].statement :
      toset(s.actions) == toset(["kms:Decrypt"]) && toset(s.resources) == toset(["arn:aws:kms:us-east-1:111111111111:key/11111111-2222-3333-4444-555555555555"])
    ])
    error_message = "The execution role must be able to decrypt secrets encrypted with secrets_kms_key_arns."
  }
}

run "no_decrypt_grant_without_customer_keys" {
  command = plan

  variables {
    secrets = { API_TOKEN = "arn:aws:secretsmanager:us-east-1:111111111111:secret:demo/token-AbCdEf" }
  }

  assert {
    condition     = length(data.aws_iam_policy_document.task_execution_secrets[0].statement) == 1
    error_message = "Without secrets_kms_key_arns the role must only read the secrets, nothing more."
  }
}

run "access_logs_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_lb.main[0].access_logs) == 0 && length(aws_s3_bucket.alb_logs) == 0
    error_message = "Access logs need a bucket and cost storage; nothing may be planned unless alb_access_logs = true."
  }
}

run "access_logs_create_a_private_expiring_bucket" {
  command = plan

  variables {
    alb_access_logs = true
  }

  assert {
    condition     = aws_s3_bucket.alb_logs[0].bucket == "demo-alb-logs-111111111111" && aws_s3_bucket.alb_logs[0].force_destroy
    error_message = "The log bucket must be named <name>-alb-logs-<account> and deletable by destroy-app."
  }
  assert {
    condition     = one(aws_lb.main[0].access_logs).bucket == "demo-alb-logs-111111111111" && one(aws_lb.main[0].access_logs).enabled
    error_message = "The ALB must write its access logs to the new bucket."
  }
  assert {
    condition = (
      aws_s3_bucket_public_access_block.alb_logs[0].block_public_acls && aws_s3_bucket_public_access_block.alb_logs[0].block_public_policy &&
      aws_s3_bucket_public_access_block.alb_logs[0].ignore_public_acls && aws_s3_bucket_public_access_block.alb_logs[0].restrict_public_buckets
    )
    error_message = "The log bucket must block all public access."
  }
  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.alb_logs[0].rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "ALB access logs need SSE-S3 (AES256); KMS is not supported for them."
  }
  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.alb_logs[0].rule).expiration).days == 90
    error_message = "Logs must expire after alb_access_logs_retention_days (default 90)."
  }
  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.alb_logs[0].statement :
      s.resources == toset(["arn:aws:s3:::demo-alb-logs-111111111111/AWSLogs/111111111111/*"]) if s.effect != "Deny"
    ])
    error_message = "Log delivery may only write under AWSLogs/<this account>/."
  }
  assert {
    condition = toset(flatten([
      for s in data.aws_iam_policy_document.alb_logs[0].statement : [for p in s.principals : p.identifiers] if s.effect != "Deny"
    ])) == toset(["arn:aws:iam::127311923021:root", "logdelivery.elasticloadbalancing.amazonaws.com"])
    error_message = "Both ELB delivery principals (account for older regions, service for newer) must be allowed."
  }
  assert {
    condition     = anytrue([for s in data.aws_iam_policy_document.alb_logs[0].statement : s.effect == "Deny" && one(s.condition).variable == "aws:SecureTransport"])
    error_message = "The bucket must refuse requests without TLS."
  }
}

run "access_logs_to_an_existing_bucket_create_none" {
  command = plan

  variables {
    alb_access_logs        = true
    alb_access_logs_bucket = "my-org-alb-logs"
  }

  assert {
    condition     = length(aws_s3_bucket.alb_logs) == 0 && one(aws_lb.main[0].access_logs).bucket == "my-org-alb-logs"
    error_message = "With alb_access_logs_bucket set, the ALB must log there and no bucket may be created."
  }
}

run "access_log_retention_follows_the_variable" {
  command = plan

  variables {
    alb_access_logs                = true
    alb_access_logs_retention_days = 30
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.alb_logs[0].rule).expiration).days == 30
    error_message = "alb_access_logs_retention_days must set the expiry."
  }
}

run "access_logs_ignored_on_a_shared_alb" {
  command = plan

  variables {
    alb_access_logs             = true
    create_alb                  = false
    create_cluster              = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host-alb/mock/https"
    existing_cluster_arn        = "arn:aws:ecs:us-east-1:111111111111:cluster/host-cluster"
    existing_cluster_name       = "host-cluster"
  }

  assert {
    condition     = length(aws_s3_bucket.alb_logs) == 0
    error_message = "A guest on a shared ALB must not create a log bucket; the host owns the ALB's logging."
  }
}

run "tasks_run_on_x86_64_by_default" {
  command = plan

  assert {
    condition     = one(aws_ecs_task_definition.app.runtime_platform).cpu_architecture == "X86_64" && output.cpu_architecture == "X86_64"
    error_message = "Existing services must stay on X86_64 unless cpu_architecture is set."
  }
}

run "arm64_tasks_when_asked" {
  command = plan

  variables {
    cpu_architecture = "ARM64"
  }

  assert {
    condition     = one(aws_ecs_task_definition.app.runtime_platform).cpu_architecture == "ARM64" && output.cpu_architecture == "ARM64"
    error_message = "cpu_architecture = ARM64 must run the tasks on Graviton and report it for deploy-app."
  }
}

run "cpu_architecture_is_checked" {
  command = plan

  variables {
    cpu_architecture = "arm64"
  }

  expect_failures = [var.cpu_architecture]
}

run "no_circuit_breaker_by_default" {
  command = plan

  assert {
    condition     = length(aws_ecs_service.app.deployment_circuit_breaker) == 0
    error_message = "Without the input the service must plan as before: no circuit breaker block."
  }
}

run "circuit_breaker_rolls_back_when_asked" {
  command = plan

  variables {
    deployment_circuit_breaker = true
  }

  assert {
    condition     = one(aws_ecs_service.app.deployment_circuit_breaker).enable && one(aws_ecs_service.app.deployment_circuit_breaker).rollback
    error_message = "The circuit breaker must stop a failing deployment and roll it back."
  }
}
