variable "name" {
  description = "Resource-name prefix (app slug)"
  type        = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "rds_security_group_id" {
  type = string
}

variable "db_name" {
  description = "Initial database name (Postgres identifier: letters/digits/underscore)"
  type        = string
  default     = "appdb"
}

variable "master_username" {
  type    = string
  default = "appuser"
}

variable "db_port" {
  type    = number
  default = 5432
}

variable "engine_version" {
  type    = string
  default = "16.11"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}

variable "backup_retention_days" {
  type    = number
  default = 1
}

variable "multi_az" {
  type    = bool
  default = false
}

variable "deletion_protection" {
  description = "Block accidental deletion (set true for prod databases)"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true = easy teardown)"
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Turn on Performance Insights, kept for the free 7 days."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Seconds between enhanced monitoring samples (0 = off; 1, 5, 10, 15, 30 or 60). Creates the monitoring role when on. Billed as CloudWatch Logs."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be 0, 1, 5, 10, 15, 30 or 60."
  }
}

variable "iam_database_authentication_enabled" {
  description = "Also accept IAM authentication tokens as database passwords. The RDS-managed password keeps working."
  type        = bool
  default     = false
}

variable "log_min_duration_ms" {
  description = <<-EOT
    Log every statement that runs at least this many milliseconds (Postgres
    log_min_duration_statement); 0 logs all statements. null (default) = off,
    and the instance keeps AWS's default parameter group. The logs go to the
    CloudWatch log group RDS already exports (/aws/rds/instance/<name>-postgres/postgresql).

    Moving an existing instance onto the new parameter group takes effect after
    its next reboot; RDS shows it as pending-reboot until then.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.log_min_duration_ms == null || try(var.log_min_duration_ms >= 0 && floor(var.log_min_duration_ms) == var.log_min_duration_ms, false)
    error_message = "log_min_duration_ms must be null (off) or a whole number of milliseconds, 0 or more."
  }
}

variable "alarm_sns_topic_arns" {
  description = "SNS topics for the baseline alarms (free storage, CPU, and CPU credits on db.t* classes). Empty = no alarms."
  type        = list(string)
  default     = []
}

variable "alarms_enabled" {
  description = "Turn the baseline alarms on or off explicitly. null (default) = on when alarm_sns_topic_arns is set. Set it when the topic ARNs are only known after apply (a topic created in the same configuration)."
  type        = bool
  default     = null
}

variable "alarm_free_storage_percent" {
  description = "Alarm when free storage falls below this percentage of allocated_storage."
  type        = number
  default     = 10

  validation {
    condition     = var.alarm_free_storage_percent > 0 && var.alarm_free_storage_percent < 100
    error_message = "alarm_free_storage_percent must be between 0 and 100."
  }
}

variable "alarm_cpu_percent" {
  description = "Alarm when average CPU stays over this percentage for 15 minutes."
  type        = number
  default     = 80

  validation {
    condition     = var.alarm_cpu_percent > 0 && var.alarm_cpu_percent <= 100
    error_message = "alarm_cpu_percent must be above 0 and at most 100."
  }
}

variable "alarm_cpu_credit_balance" {
  description = "On db.t* classes, alarm when the CPU credit balance falls below this."
  type        = number
  default     = 20

  validation {
    condition     = var.alarm_cpu_credit_balance >= 0
    error_message = "alarm_cpu_credit_balance can't be negative."
  }
}

variable "trust_policy_source_conditions" {
  description = "Limit the Enhanced Monitoring role's trust to this instance in to this account (aws:SourceAccount and aws:SourceArn), AWS's confused-deputy protection. On by default; set false to restore the unconditioned trust policy if a role can't be assumed."
  type        = bool
  default     = true
}
