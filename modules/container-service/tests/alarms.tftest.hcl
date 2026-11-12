# Opt-in baseline alarms (#62): nothing by default; with alarm_emails, a topic
# and four alarms on this app's own target group, built to AWS's CloudWatch
# guidance (M-of-N, error rate not count, p99 not Average, explicit missing
# data). Plans only, against a mocked provider.

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
  mock_resource "aws_lb" {
    override_during = plan
    defaults        = { arn_suffix = "app/demo-alb/abc123", arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/demo-alb/abc123" }
  }
  mock_resource "aws_lb_target_group" {
    override_during = plan
    defaults        = { arn_suffix = "targetgroup/demo-api/def456", arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:targetgroup/demo-api/def456" }
  }
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:us-east-1:111111111111:demo-api-alarms" }
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

run "no_alarms_by_default" {
  command = plan

  assert {
    condition     = length(aws_sns_topic.alarms) == 0 && length(aws_cloudwatch_metric_alarm.error_rate) == 0 && length(aws_cloudwatch_metric_alarm.latency_p99) == 0 && length(aws_cloudwatch_metric_alarm.unhealthy_targets) == 0 && length(aws_cloudwatch_metric_alarm.no_healthy_targets) == 0
    error_message = "Without alarm_emails or alarm_sns_topic_arns nothing is created, so existing services plan no change."
  }
  assert {
    condition     = length(output.alarm_names) == 0 && output.alarm_topic_arn == null
    error_message = "The outputs must report no alarms."
  }
}

run "emails_create_a_topic_and_four_alarms" {
  command = plan

  variables {
    alarm_emails  = ["ops@example.com", "dev@example.com"]
    desired_count = 2
  }

  assert {
    condition     = aws_sns_topic.alarms[0].name == "demo-app-alarms" && length(aws_sns_topic_subscription.alarm_email) == 2
    error_message = "One topic, one email subscription per address."
  }
  assert {
    condition     = aws_sns_topic_subscription.alarm_email["ops@example.com"].protocol == "email"
    error_message = "Subscriptions are email."
  }
  assert {
    condition     = output.alarm_names == tolist(["demo-app-5xx-rate", "demo-app-p99-latency", "demo-app-unhealthy-targets", "demo-app-no-healthy-targets"])
    error_message = "All four alarms, named after the service."
  }
  assert {
    condition     = alltrue([for a in [aws_cloudwatch_metric_alarm.error_rate[0], aws_cloudwatch_metric_alarm.latency_p99[0], aws_cloudwatch_metric_alarm.unhealthy_targets[0], aws_cloudwatch_metric_alarm.no_healthy_targets[0]] : a.alarm_actions == toset(["arn:aws:sns:us-east-1:111111111111:demo-api-alarms"]) && a.ok_actions == a.alarm_actions])
    error_message = "Every alarm notifies the topic, on alarm and on recovery."
  }
}

run "the_error_alarm_is_a_rate_over_quiet_minutes" {
  command = plan

  variables {
    alarm_emails = ["ops@example.com"]
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.error_rate[0].metric_query : q.expression if q.id == "rate"]) == "IF(requests >= 20, 100 * errors / requests, 0)"
    error_message = "The error alarm must be a percentage of requests, with quiet minutes as 0%."
  }
  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.error_rate[0].metric_query : one(q.metric).metric_name if q.id == "errors"]) == "HTTPCode_Target_5XX_Count"
    error_message = "Errors are the app's own 5xx responses."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.error_rate[0].threshold == 5 && aws_cloudwatch_metric_alarm.error_rate[0].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.error_rate[0].datapoints_to_alarm == 2 && aws_cloudwatch_metric_alarm.error_rate[0].treat_missing_data == "notBreaching"
    error_message = "5% in 2 of 3 minutes; no requests means no errors."
  }
  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.error_rate[0].metric_query : one(q.metric).dimensions if q.id == "requests"]) == tomap({ TargetGroup = "targetgroup/demo-api/def456", LoadBalancer = "app/demo-alb/abc123" })
    error_message = "The metrics must be this app's target group on its ALB."
  }
}

run "latency_is_p99_not_average" {
  command = plan

  variables {
    alarm_emails      = ["ops@example.com"]
    alarm_p99_seconds = 1.5
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.latency_p99[0].extended_statistic == "p99" && aws_cloudwatch_metric_alarm.latency_p99[0].statistic == null && aws_cloudwatch_metric_alarm.latency_p99[0].threshold == 1.5
    error_message = "Latency must alarm on p99, at the given threshold."
  }
}

run "health_alarms_treat_missing_data_differently" {
  command = plan

  variables {
    alarm_emails  = ["ops@example.com"]
    desired_count = 1
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_targets[0].treat_missing_data == "notBreaching" && aws_cloudwatch_metric_alarm.unhealthy_targets[0].datapoints_to_alarm == 3 && aws_cloudwatch_metric_alarm.unhealthy_targets[0].evaluation_periods == 5
    error_message = "Unhealthy targets: 3 of 5 minutes."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.no_healthy_targets[0].treat_missing_data == "breaching" && aws_cloudwatch_metric_alarm.no_healthy_targets[0].comparison_operator == "LessThanThreshold" && aws_cloudwatch_metric_alarm.no_healthy_targets[0].threshold == 1
    error_message = "No healthy targets: a stopped health metric counts as down."
  }
}

run "no_down_alarm_while_scaled_to_zero" {
  command = plan

  variables {
    alarm_emails  = ["ops@example.com"]
    desired_count = 0
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.no_healthy_targets) == 0 && length(aws_cloudwatch_metric_alarm.error_rate) == 1
    error_message = "A service meant to run no tasks can't be down."
  }
}

run "existing_topics_alone_turn_alarms_on_without_a_topic" {
  command = plan

  variables {
    alarm_sns_topic_arns = ["arn:aws:sns:us-east-1:111111111111:team-pager"]
  }

  assert {
    condition     = length(aws_sns_topic.alarms) == 0 && aws_cloudwatch_metric_alarm.latency_p99[0].alarm_actions == toset(["arn:aws:sns:us-east-1:111111111111:team-pager"])
    error_message = "Given topics are notified, and no topic is created."
  }
}

run "a_shared_alb_is_found_from_its_listener" {
  command = plan

  variables {
    alarm_emails                = ["ops@example.com"]
    create_alb                  = false
    create_cluster              = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/host-alb/9f8e7d/a1b2c3"
    existing_cluster_arn        = "arn:aws:ecs:us-east-1:111111111111:cluster/host"
    existing_cluster_name       = "host"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.latency_p99[0].dimensions["LoadBalancer"] == "app/host-alb/9f8e7d"
    error_message = "On a shared ALB the load balancer comes from the listener ARN."
  }
}

run "an_unreadable_shared_listener_arn_is_refused" {
  command = plan

  variables {
    alarm_emails                = ["ops@example.com"]
    create_alb                  = false
    create_cluster              = false
    existing_alb_dns_name       = "host-alb-123.us-east-1.elb.amazonaws.com"
    existing_alb_zone_id        = "Z35SXDOTRQ7X7K"
    existing_https_listener_arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/net/host-nlb/9f8e7d/a1b2c3"
    existing_cluster_arn        = "arn:aws:ecs:us-east-1:111111111111:cluster/host"
    existing_cluster_name       = "host"
  }

  expect_failures = [aws_cloudwatch_metric_alarm.error_rate]
}

run "alarm_inputs_are_checked" {
  command = plan

  variables {
    alarm_emails       = ["not-an-email"]
    alarm_5xx_percent  = 0
    alarm_p99_seconds  = 0
    alarm_min_requests = 0
  }

  expect_failures = [var.alarm_emails, var.alarm_5xx_percent, var.alarm_p99_seconds, var.alarm_min_requests]
}
