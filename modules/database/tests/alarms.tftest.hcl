# Opt-in database alarms (#62): nothing by default; with a topic, free storage
# and CPU, plus CPU credits on burstable classes. Plans only, mocked provider.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  name                  = "demo"
  private_subnet_ids    = ["subnet-a", "subnet-b"]
  rds_security_group_id = "sg-rds"
}

run "no_alarms_by_default" {
  command = plan

  assert {
    condition     = length(output.alarm_names) == 0
    error_message = "Without a topic nothing is created, so existing databases plan no change."
  }
}

run "a_topic_turns_on_storage_and_cpu_alarms" {
  command = plan

  variables {
    alarm_sns_topic_arns = ["arn:aws:sns:us-east-1:111111111111:demo-api-alarms"]
    allocated_storage    = 20
    instance_class       = "db.m7g.large"
  }

  assert {
    condition     = output.alarm_names == tolist(["demo-postgres-free-storage", "demo-postgres-cpu"])
    error_message = "Free storage and CPU; no credit alarm on a non-burstable class."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.free_storage[0].threshold == 2147483648 && aws_cloudwatch_metric_alarm.free_storage[0].comparison_operator == "LessThanThreshold"
    error_message = "10% of 20 GiB is 2147483648 bytes."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.free_storage[0].dimensions == tomap({ DBInstanceIdentifier = "demo-postgres" })
    error_message = "The alarms watch this instance."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu[0].threshold == 80 && aws_cloudwatch_metric_alarm.cpu[0].period == 300 && aws_cloudwatch_metric_alarm.cpu[0].evaluation_periods == 3 && aws_cloudwatch_metric_alarm.cpu[0].datapoints_to_alarm == 3
    error_message = "CPU over 80% for 15 minutes."
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu[0].alarm_actions == toset(["arn:aws:sns:us-east-1:111111111111:demo-api-alarms"]) && aws_cloudwatch_metric_alarm.cpu[0].ok_actions == aws_cloudwatch_metric_alarm.cpu[0].alarm_actions
    error_message = "The alarms notify the given topic, on alarm and on recovery."
  }
}

run "burstable_classes_also_watch_cpu_credits" {
  command = plan

  variables {
    alarm_sns_topic_arns = ["arn:aws:sns:us-east-1:111111111111:demo-api-alarms"]
    instance_class       = "db.t4g.micro"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_credits) == 1 && aws_cloudwatch_metric_alarm.cpu_credits[0].metric_name == "CPUCreditBalance" && aws_cloudwatch_metric_alarm.cpu_credits[0].threshold == 20
    error_message = "A db.t* class must also alarm on its CPU credit balance."
  }
}

run "database_alarm_inputs_are_checked" {
  command = plan

  variables {
    alarm_free_storage_percent = 100
    alarm_cpu_percent          = 0
    alarm_cpu_credit_balance   = -1
  }

  expect_failures = [var.alarm_free_storage_percent, var.alarm_cpu_percent, var.alarm_cpu_credit_balance]
}

run "alarms_enabled_decides_when_given" {
  command = plan

  variables {
    alarms_enabled = true
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.free_storage) == 1 && length(aws_cloudwatch_metric_alarm.cpu) == 1
    error_message = "alarms_enabled = true turns the alarms on even before the topic ARNs are known."
  }
}

run "alarms_enabled_false_wins_over_topics" {
  command = plan

  variables {
    alarms_enabled       = false
    alarm_sns_topic_arns = ["arn:aws:sns:us-east-1:111111111111:x"]
  }

  assert {
    condition     = length(output.alarm_names) == 0
    error_message = "alarms_enabled = false turns them off."
  }
}
