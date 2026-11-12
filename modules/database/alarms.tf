# Opt-in baseline alarms (#62): free storage, sustained CPU, and CPU credits on
# burstable (db.t*) classes, sent to the SNS topics in alarm_sns_topic_arns.
# Nothing is created while it's empty, so existing databases plan no change.
# (full-stack passes container-service's alarm topic here.)

locals {
  # alarms_enabled, when given, decides; otherwise the alarms are on when topics
  # are. full-stack passes it because its topic's ARN is only known after apply,
  # and count must be known at plan time.
  db_alarms_on    = var.alarms_enabled != null ? var.alarms_enabled : length(var.alarm_sns_topic_arns) > 0
  db_alarm_prefix = "${local.name_prefix}-postgres"
  db_dimensions   = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  # RDS sizes storage in GiB. With storage autoscaling the volume grows, so this
  # threshold is on the size it started at: an early warning, never a late one.
  free_storage_threshold_bytes = floor(var.allocated_storage * 1073741824 * var.alarm_free_storage_percent / 100)
}

resource "aws_cloudwatch_metric_alarm" "free_storage" {
  count               = local.db_alarms_on ? 1 : 0
  alarm_name          = "${local.db_alarm_prefix}-free-storage"
  alarm_description   = "${local.db_alarm_prefix} has under ${var.alarm_free_storage_percent}% of its ${var.allocated_storage} GiB free."
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = local.db_dimensions
  statistic           = "Minimum"
  period              = 300
  comparison_operator = "LessThanThreshold"
  threshold           = local.free_storage_threshold_bytes
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_sns_topic_arns
  ok_actions          = var.alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  count               = local.db_alarms_on ? 1 : 0
  alarm_name          = "${local.db_alarm_prefix}-cpu"
  alarm_description   = "${local.db_alarm_prefix}'s CPU was over ${var.alarm_cpu_percent}% for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = local.db_dimensions
  statistic           = "Average"
  period              = 300
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_percent
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arns
  ok_actions          = var.alarm_sns_topic_arns
}

# A burstable class that runs out of credits is throttled to its baseline.
resource "aws_cloudwatch_metric_alarm" "cpu_credits" {
  count               = local.db_alarms_on && startswith(var.instance_class, "db.t") ? 1 : 0
  alarm_name          = "${local.db_alarm_prefix}-cpu-credits"
  alarm_description   = "${local.db_alarm_prefix} (${var.instance_class}) is down to ${var.alarm_cpu_credit_balance} CPU credits; at 0 it's throttled to its baseline."
  namespace           = "AWS/RDS"
  metric_name         = "CPUCreditBalance"
  dimensions          = local.db_dimensions
  statistic           = "Minimum"
  period              = 300
  comparison_operator = "LessThanThreshold"
  threshold           = var.alarm_cpu_credit_balance
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_sns_topic_arns
  ok_actions          = var.alarm_sns_topic_arns
}
