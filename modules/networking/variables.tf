variable "name" {
  description = "Resource-name prefix (app slug)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to span"
  type        = number
  default     = 2
}

variable "container_port" {
  description = "Port the app container listens on"
  type        = number
  default     = 8080
}

variable "enable_database" {
  description = "Create the RDS security group + ingress rule"
  type        = bool
  default     = false
}

variable "enable_cache" {
  description = "Create the Redis security group + ingress rule"
  type        = bool
  default     = false
}

variable "db_port" {
  description = "Postgres port"
  type        = number
  default     = 5432
}

variable "cache_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Provision a NAT gateway (~$33/month) so private-subnet tasks can reach the
    internet. Set false together with container-service's
    `tasks_in_public_subnets` to drop that cost: tasks then run in public subnets
    with public IPs, still admitting inbound traffic only from the ALB.

    Databases stay in the private subnets either way; they need no egress.
  EOT
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to a CloudWatch log group. Billed per GB ingested and stored."
  type        = bool
  default     = false
}

variable "flow_log_traffic_type" {
  description = "Which traffic the flow logs record: ACCEPT, REJECT or ALL. REJECT is the cheapest way to see blocked connections."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_log_retention_days" {
  description = "Days to keep flow logs. Must be a value CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, ...)."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a retention period CloudWatch Logs accepts, e.g. 7, 14, 30, 90 or 365."
  }
}
