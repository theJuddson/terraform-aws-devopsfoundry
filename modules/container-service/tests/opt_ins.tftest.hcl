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
