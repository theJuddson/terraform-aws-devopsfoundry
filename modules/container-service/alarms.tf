# Opt-in baseline alarms (#62): the app's error rate, its p99 latency, unhealthy
# targets, and no healthy target at all, sent to an SNS topic. On when
# alarm_emails or alarm_sns_topic_arns is set; nothing is created otherwise, so
# existing services plan no change.
#
# Defaults follow AWS's CloudWatch alarm guidance: 1-minute periods, alarm on 2
# of the last 3 (M-of-N, never 1 of 1), the error rate as a percentage rather
# than a count, latency at p99 rather than Average, and missing data set
# explicitly (no requests means no errors; a health metric that stops means
# trouble). All metrics are the target group's, so they are this app's own even
# on a shared ALB.

locals {
  alarms_on       = length(var.alarm_emails) > 0 || length(var.alarm_sns_topic_arns) > 0
  alarm_topic_on  = length(var.alarm_emails) > 0
  alarm_actions   = concat(aws_sns_topic.alarms[*].arn, var.alarm_sns_topic_arns)
  alarm_prefix    = "${local.name_prefix}-${var.service_name}"
  target_group_id = aws_lb_target_group.app.arn_suffix
  # app/<name>/<id>: from our ALB, or from the shared ALB's listener ARN
  # (arn:...:listener/app/<name>/<id>/<listener id>).
  load_balancer_id = var.create_alb ? aws_lb.main[0].arn_suffix : try(regex("listener/(app/[^/]+/[^/]+)/", var.existing_https_listener_arn)[0], "")
  tg_dimensions = {
    TargetGroup  = local.target_group_id
    LoadBalancer = local.load_balancer_id
  }
}

resource "aws_sns_topic" "alarms" {
  #checkov:skip=CKV_AWS_26:CloudWatch can't publish to a topic under the AWS-managed SNS key; pass alarm_topic_kms_key_arn (a customer managed key whose policy allows cloudwatch.amazonaws.com) to encrypt it. Alarm notices hold no app data
  count             = local.alarm_topic_on ? 1 : 0
  name              = "${local.alarm_prefix}-alarms"
  kms_master_key_id = var.alarm_topic_kms_key_arn
  tags              = { Name = "${local.alarm_prefix}-alarms" }
}

# Each address must confirm the email AWS sends before it receives alarms.
resource "aws_sns_topic_subscription" "alarm_email" {
  for_each  = local.alarm_topic_on ? toset(var.alarm_emails) : toset([])
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# 5xx responses from the app as a share of its requests. Quiet minutes (fewer
# than alarm_min_requests) count as 0%, so one failed request at 3 a.m. doesn't
# page anyone.
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  count               = local.alarms_on ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-5xx-rate"
  alarm_description   = "More than ${var.alarm_5xx_percent}% of ${local.alarm_prefix}'s responses were 5xx in 2 of the last 3 minutes."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_5xx_percent
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  lifecycle {
    precondition {
      condition     = local.load_balancer_id != ""
      error_message = "Can't tell the shared ALB's ID from existing_https_listener_arn (expected arn:...:listener/app/<name>/<id>/<listener id>), so the alarms would watch nothing."
    }
  }

  metric_query {
    id          = "rate"
    expression  = "IF(requests >= ${var.alarm_min_requests}, 100 * errors / requests, 0)"
    label       = "5xx rate (%)"
    return_data = true
  }
  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.tg_dimensions
      period      = 60
      stat        = "Sum"
    }
  }
  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      dimensions  = local.tg_dimensions
      period      = 60
      stat        = "Sum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "latency_p99" {
  count               = local.alarms_on ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-p99-latency"
  alarm_description   = "${local.alarm_prefix}'s p99 response time was over ${var.alarm_p99_seconds}s in 2 of the last 3 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.tg_dimensions
  extended_statistic  = "p99"
  period              = 60
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_p99_seconds
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_targets" {
  count               = local.alarms_on ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-unhealthy-targets"
  alarm_description   = "At least one of ${local.alarm_prefix}'s tasks failed its health check in 3 of the last 5 minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Maximum"
  period              = 60
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# No healthy task at all: the app is down. Only when the service is meant to
# run tasks; a missing datapoint counts as down, since the metric stopping is
# itself a sign of trouble.
resource "aws_cloudwatch_metric_alarm" "no_healthy_targets" {
  count               = local.alarms_on && var.desired_count > 0 ? 1 : 0
  alarm_name          = "${local.alarm_prefix}-no-healthy-targets"
  alarm_description   = "${local.alarm_prefix} had no healthy task for 3 minutes: it is down."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Minimum"
  period              = 60
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}
