# Root variables — values come from app.tfvars. Mirror of the full-stack
# module's inputs; new-app sets the identity defaults, you edit app.tfvars.
variable "name" { type = string }
variable "domain_name" { type = string }
variable "subdomain" {
  type    = string
  default = "api"
}
variable "service_name" {
  type    = string
  default = "app"
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "container_image" {
  type    = string
  default = ""
}
variable "container_port" {
  type    = number
  default = 8080
}
variable "cpu" {
  type    = number
  default = 512
}
variable "memory" {
  type    = number
  default = 1024
}
variable "desired_count" {
  type    = number
  default = 1
}
variable "env" {
  type    = map(string)
  default = {}
}
variable "secrets" {
  type    = map(string)
  default = {}
}
variable "health_check_path" {
  type    = string
  default = "/health"
}
variable "health_check_matcher" {
  type    = string
  default = "200"
}
variable "health_check_interval" {
  type    = number
  default = 15
}
variable "health_check_timeout" {
  type    = number
  default = 5
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "az_count" {
  type    = number
  default = 2
}

variable "enable_database" {
  type    = bool
  default = false
}
variable "enable_cache" {
  type    = bool
  default = false
}
variable "enable_email" {
  type    = bool
  default = false
}

variable "db_name" {
  type    = string
  default = "appdb"
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}
variable "db_allocated_storage" {
  type    = number
  default = 20
}
variable "db_engine_version" {
  type    = string
  default = "16.11"
}
variable "db_multi_az" {
  type    = bool
  default = false
}
variable "db_backup_retention_days" {
  type    = number
  default = 1
}
variable "db_deletion_protection" {
  type    = bool
  default = false
}
variable "db_skip_final_snapshot" {
  type    = bool
  default = true
}

variable "cache_node_type" {
  type    = string
  default = "cache.t4g.micro"
}
variable "cache_engine_version" {
  type    = string
  default = "7.1"
}

variable "dmarc_rua_email" {
  type    = string
  default = ""
}

variable "shared_platform" {
  description = "Slug of an existing DevOpsFoundry app whose VPC/NAT/ALB/ECS cluster to share; empty = dedicated"
  type        = string
  default     = ""
}

variable "listener_rule_priority_base" {
  description = "First ALB listener-rule priority to claim in shared mode; each guest app needs a distinct base"
  type        = number
  default     = 100
}

variable "enable_nat_gateway" {
  description = "Provision a NAT gateway (~$33/month). False + tasks_in_public_subnets = true removes it."
  type        = bool
  default     = true
}

variable "tasks_in_public_subnets" {
  description = "Run ECS tasks in public subnets with public IPs (no NAT needed). Inbound stays ALB-only."
  type        = bool
  default     = false
}

variable "existing_zone_name" {
  description = "Existing Route53 zone to add this app's records to; empty = create a zone and delegate NS"
  type        = string
  default     = ""
}
