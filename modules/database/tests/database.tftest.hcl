# The Postgres instance: encrypted, private, teardown-friendly defaults, and
# the opt-in monitoring and IAM login. Plans only, against a mocked provider:
# no AWS account is touched.

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

run "defaults_private_encrypted_and_easy_to_tear_down" {
  command = plan

  assert {
    condition     = aws_db_instance.main.identifier == "demo-postgres" && aws_db_instance.main.engine == "postgres"
    error_message = "The instance must be Postgres, named after the app."
  }
  assert {
    condition     = aws_db_instance.main.storage_encrypted && !aws_db_instance.main.publicly_accessible
    error_message = "The database must be encrypted at rest and never publicly reachable."
  }
  assert {
    condition     = aws_db_instance.main.manage_master_user_password
    error_message = "The master password must be managed by RDS in Secrets Manager, never set in Terraform."
  }
  assert {
    condition     = aws_db_instance.main.vpc_security_group_ids == toset(["sg-rds"]) && aws_db_subnet_group.main.subnet_ids == toset(["subnet-a", "subnet-b"])
    error_message = "The instance must sit in the given private subnets behind the given security group."
  }
  assert {
    condition     = aws_db_instance.main.skip_final_snapshot && !aws_db_instance.main.deletion_protection && aws_db_instance.main.final_snapshot_identifier == null
    error_message = "By default the database must be deletable without a final snapshot, so teardown works."
  }
  assert {
    condition     = !aws_db_instance.main.delete_automated_backups
    error_message = "Without a final snapshot, the automated backups must outlive the instance as the way back."
  }
  assert {
    condition     = !aws_db_instance.main.multi_az
    error_message = "Single-AZ by default, for cost."
  }
}

run "monitoring_and_iam_login_off_by_default" {
  command = plan

  assert {
    condition     = !aws_db_instance.main.performance_insights_enabled && aws_db_instance.main.monitoring_interval == 0
    error_message = "Performance Insights and enhanced monitoring must stay off unless asked for."
  }
  assert {
    condition     = length(aws_iam_role.monitoring) == 0 && length(aws_iam_role_policy_attachment.monitoring) == 0
    error_message = "No monitoring role without enhanced monitoring."
  }
  assert {
    condition     = !aws_db_instance.main.iam_database_authentication_enabled
    error_message = "IAM database login must stay off by default."
  }
}

run "opt_ins_turn_them_on" {
  command = plan

  variables {
    performance_insights_enabled        = true
    monitoring_interval                 = 60
    iam_database_authentication_enabled = true
  }

  assert {
    condition     = aws_db_instance.main.performance_insights_enabled && aws_db_instance.main.performance_insights_retention_period == 7
    error_message = "Performance Insights must keep only the free 7 days."
  }
  assert {
    condition     = aws_db_instance.main.monitoring_interval == 60 && length(aws_iam_role.monitoring) == 1 && aws_iam_role.monitoring[0].name == "demo-rds-monitoring"
    error_message = "Enhanced monitoring needs its role, named after the app."
  }
  assert {
    condition     = endswith(aws_iam_role_policy_attachment.monitoring[0].policy_arn, ":iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole")
    error_message = "The monitoring role must carry AWS's enhanced monitoring policy."
  }
  assert {
    condition     = aws_db_instance.main.iam_database_authentication_enabled
    error_message = "iam_database_authentication_enabled = true must turn on IAM login."
  }
}

run "keeping_a_final_snapshot_names_it" {
  command = plan

  variables {
    skip_final_snapshot = false
  }

  assert {
    condition     = startswith(aws_db_instance.main.final_snapshot_identifier, "demo-postgres-final-") && aws_db_instance.main.delete_automated_backups
    error_message = "With skip_final_snapshot = false the final snapshot must be named; it replaces the automated backups."
  }
}

run "monitoring_interval_is_checked" {
  command = plan

  variables {
    monitoring_interval = 45
  }

  expect_failures = [var.monitoring_interval]
}
