# Attaching to an existing ALB or cluster without saying which one fails at
# plan, instead of at apply with an empty name or ARN. Plans only, against a
# mocked AWS provider.

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

run "shared_alb_without_dns_name_is_rejected" {
  command = plan

  variables {
    create_alb                  = false
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host/mock/https"
  }

  expect_failures = [aws_route53_record.service]
}

run "shared_alb_without_zone_id_is_rejected" {
  command = plan

  variables {
    create_alb                  = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host/mock/https"
  }

  expect_failures = [aws_route53_record.service]
}

run "shared_alb_without_listener_is_rejected" {
  command = plan

  variables {
    create_alb            = false
    existing_alb_dns_name = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id  = "Z35SXDOTRQ7X7K"
  }

  expect_failures = [aws_route53_record.service]
}

run "shared_cluster_without_arn_is_rejected" {
  command = plan

  variables {
    create_cluster        = false
    existing_cluster_name = "host"
  }

  expect_failures = [aws_ecs_service.app]
}

run "shared_cluster_without_name_is_rejected" {
  command = plan

  variables {
    create_cluster       = false
    existing_cluster_arn = "arn:aws:ecs:us-east-1:111111111111:cluster/host"
  }

  expect_failures = [aws_ecs_service.app]
}
