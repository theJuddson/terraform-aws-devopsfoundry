# RDS Postgres with AWS-managed master password (Secrets Manager).
# Generic names + teardown-friendly
# defaults (deletion protection off, skip final snapshot) for the generic tool.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

locals {
  name_prefix = var.name
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-rds"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${local.name_prefix}-rds-subnet-group" }
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false
  port                   = var.db_port

  backup_retention_period   = var.backup_retention_days
  backup_window             = "08:00-09:00"
  maintenance_window        = "sun:09:00-sun:10:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = !var.skip_final_snapshot
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-postgres-final-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  multi_az                   = var.multi_az
  deletion_protection        = var.deletion_protection
  auto_minor_version_upgrade = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? 7 : null
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null
  iam_database_authentication_enabled   = var.iam_database_authentication_enabled

  enabled_cloudwatch_logs_exports = ["postgresql"]
  tags                            = { Name = "${local.name_prefix}-postgres" }

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

# ── Enhanced monitoring (opt-in) ─────────────────────
data "aws_partition" "current" {
  count = var.monitoring_interval > 0 ? 1 : 0
}

data "aws_iam_policy_document" "monitoring_assume" {
  count = var.monitoring_interval > 0 ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count              = var.monitoring_interval > 0 ? 1 : 0
  name               = "${local.name_prefix}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume[0].json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current[0].partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
