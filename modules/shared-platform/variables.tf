variable "platform_name" {
  description = <<-EOT
    Name of an EXISTING DevOpsFoundry platform whose VPC, NAT, ALB and ECS
    cluster this app should share: the platform_name it publishes, or the host
    app's slug (e.g. "other-app-com"). A published descriptor is used first,
    then this tool's own naming conventions — see main.tf.
  EOT
  type        = string
}

variable "name" {
  description = "Resource-name prefix for THIS app (app slug)"
  type        = string
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

variable "https_listener_port" {
  description = "Port of the shared ALB's HTTPS listener"
  type        = number
  default     = 443
}

variable "tasks_in_public_subnets" {
  description = "Whether this app's tasks run in the public subnets (container-service's setting of the same name). When false, the plan fails if the platform's private subnets have no route to the internet."
  type        = bool
  default     = false
}
