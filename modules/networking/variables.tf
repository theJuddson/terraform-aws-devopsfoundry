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
