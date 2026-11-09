# Opt-in observability and protection: off by default, on when asked. Plans
# only, against a mocked provider: no AWS account is touched.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
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
