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
