# What each hosting mode plans: a dedicated ALB and cluster by default, a
# shared ALB and cluster when attached to another stack, and the www redirect
# when serving at the apex. Plans only, against a mocked provider: no AWS
# account is touched.

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

run "defaults_dedicated_alb_and_cluster_at_api_subdomain" {
  command = plan

  assert {
    condition = (
      length(aws_lb.main) == 1 &&
      length(aws_lb_listener.http_redirect) == 1 &&
      length(aws_lb_listener.https) == 1
    )
    error_message = "By default the app gets its own ALB with an HTTP->HTTPS redirect and an HTTPS listener."
  }
  assert {
    condition     = aws_lb.main[0].name == "demo-alb" && aws_lb_listener.https[0].certificate_arn == var.certificate_arn
    error_message = "The dedicated ALB must be named after the app and terminate TLS with the given certificate."
  }
  assert {
    condition     = length(aws_ecs_cluster.main) == 1 && length(aws_ecs_cluster_capacity_providers.main) == 1
    error_message = "By default the app gets its own Fargate cluster."
  }
  assert {
    condition     = aws_ecs_cluster.main[0].name == "demo-cluster" && output.ecs_cluster_name == "demo-cluster"
    error_message = "The dedicated cluster must be named after the app and reported in ecs_cluster_name."
  }
  assert {
    condition     = length(aws_lb_listener_certificate.shared) == 0 && length(aws_lb_listener_rule.host_forward) == 0
    error_message = "A dedicated ALB forwards by default; no host-header rule or extra certificate is needed."
  }
  assert {
    condition     = aws_route53_record.service.name == "api.example.com" && aws_route53_record.service.zone_id == "Z0000000000MOCK"
    error_message = "By default the service must be served at api.<domain> in the given zone."
  }
  assert {
    condition     = output.service_fqdn == "api.example.com" && output.service_url == "https://api.example.com"
    error_message = "service_fqdn and service_url must name the subdomain host."
  }
  assert {
    condition     = length(aws_route53_record.www) == 0 && length(aws_lb_listener_rule.www_redirect) == 0
    error_message = "A subdomain service must not claim www or redirect it."
  }
}

run "empty_subdomain_serves_apex_and_redirects_www" {
  command = plan

  variables {
    subdomain = ""
  }

  assert {
    condition     = aws_route53_record.service.name == "example.com" && output.service_fqdn == "example.com"
    error_message = "An empty subdomain must serve the app at the apex domain."
  }
  assert {
    condition     = length(aws_route53_record.www) == 1 && aws_route53_record.www[0].name == "www.example.com"
    error_message = "Serving at the apex must also point www at the ALB."
  }
  assert {
    condition = (
      length(aws_lb_listener_rule.www_redirect) == 1 &&
      aws_lb_listener_rule.www_redirect[0].priority == 1 &&
      aws_lb_listener_rule.www_redirect[0].action[0].redirect[0].host == "example.com" &&
      aws_lb_listener_rule.www_redirect[0].action[0].redirect[0].status_code == "HTTP_301" &&
      one(aws_lb_listener_rule.www_redirect[0].condition).host_header[0].values == toset(["www.example.com"])
    )
    error_message = "On a dedicated ALB, www must be 301-redirected to the apex by a priority-1 rule."
  }
}

run "at_subdomain_also_serves_apex" {
  command = plan

  variables {
    subdomain = "@"
  }

  assert {
    condition     = aws_route53_record.service.name == "example.com" && length(aws_lb_listener_rule.www_redirect) == 1
    error_message = "subdomain = \"@\" must behave like an empty subdomain: apex serving plus the www redirect."
  }
}

run "shared_alb_and_cluster_attach_without_creating" {
  command = plan

  variables {
    create_alb                  = false
    create_cluster              = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host/mock/https"
    existing_cluster_arn        = "arn:aws:ecs:us-east-1:111111111111:cluster/host"
    existing_cluster_name       = "host"
    listener_rule_priority_base = 300
  }

  assert {
    condition = (
      length(aws_lb.main) == 0 &&
      length(aws_lb_listener.http_redirect) == 0 &&
      length(aws_lb_listener.https) == 0
    )
    error_message = "A guest app must not create an ALB or listeners of its own."
  }
  assert {
    condition     = length(aws_ecs_cluster.main) == 0 && length(aws_ecs_cluster_capacity_providers.main) == 0
    error_message = "A guest app must not create a cluster of its own."
  }
  assert {
    condition     = aws_ecs_service.app.cluster == var.existing_cluster_arn && output.ecs_cluster_name == "host"
    error_message = "The service must run in the shared cluster and report its name."
  }
  assert {
    condition = (
      aws_route53_record.service.alias[0].name == var.existing_alb_dns_name &&
      aws_route53_record.service.alias[0].zone_id == var.existing_alb_zone_id &&
      output.alb_dns_name == var.existing_alb_dns_name
    )
    error_message = "The service record must alias the shared ALB."
  }
  assert {
    condition = (
      length(aws_lb_listener_certificate.shared) == 1 &&
      aws_lb_listener_certificate.shared[0].listener_arn == var.existing_https_listener_arn &&
      aws_lb_listener_certificate.shared[0].certificate_arn == var.certificate_arn
    )
    error_message = "The app's certificate must be added to the shared HTTPS listener for SNI."
  }
  assert {
    condition = (
      length(aws_lb_listener_rule.host_forward) == 1 &&
      aws_lb_listener_rule.host_forward[0].listener_arn == var.existing_https_listener_arn &&
      aws_lb_listener_rule.host_forward[0].priority == 300 &&
      one(aws_lb_listener_rule.host_forward[0].condition).host_header[0].values == toset(["api.example.com"])
    )
    error_message = "On a shared ALB the app must claim its host name with a forward rule at the base priority."
  }
}

run "shared_alb_apex_redirect_takes_base_plus_one" {
  command = plan

  variables {
    subdomain                   = ""
    create_alb                  = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host/mock/https"
    listener_rule_priority_base = 300
  }

  assert {
    condition = (
      aws_lb_listener_rule.host_forward[0].priority == 300 &&
      one(aws_lb_listener_rule.host_forward[0].condition).host_header[0].values == toset(["example.com"])
    )
    error_message = "At the apex on a shared ALB the forward rule must claim the apex host at the base priority."
  }
  assert {
    condition = (
      aws_lb_listener_rule.www_redirect[0].priority == 301 &&
      aws_lb_listener_rule.www_redirect[0].listener_arn == var.existing_https_listener_arn
    )
    error_message = "On a shared ALB the www redirect must sit on the shared listener at base + 1, clear of other apps' rules."
  }
  assert {
    condition     = length(aws_ecs_cluster.main) == 1
    error_message = "create_alb = false alone must still create the app's own cluster."
  }
}
