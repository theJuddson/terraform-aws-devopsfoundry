variable "name" {
  description = "Resource-name prefix (app slug)"
  type        = string
}

variable "service_name" {
  description = "Container/service short name (used in ECR repo, log group, container name)"
  type        = string
  default     = "app"
}

variable "domain_name" {
  description = "Apex domain"
  type        = string
}

variable "subdomain" {
  description = "Subdomain that fronts the service (api -> api.example.com). Empty or \"@\" serves at the apex (example.com)."
  type        = string
  default     = "api"
}

variable "zone_id" {
  description = "Route53 hosted zone ID for the domain"
  type        = string
}

variable "certificate_arn" {
  description = "Validated ACM cert ARN (us-east-1) covering the service FQDN"
  type        = string
}

# ── Networking wiring ──────────────────────────────────
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "alb_security_group_id" { type = string }
variable "api_security_group_id" { type = string }

# ── Container ──────────────────────────────────────────
variable "container_image" {
  description = "Image URI. Empty -> the module's own ECR repo :latest tag."
  type        = string
  default     = ""
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  description = "Fargate task CPU units (256/512/1024/...)"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Fargate task memory (MiB)"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Running task count. new-app provisions at 0; deploy-app scales up."
  type        = number
  default     = 1
}

variable "env" {
  description = "Plaintext environment variables injected into the container"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret env vars: ENV_NAME -> Secrets Manager valueFrom ARN (supports :json_key:: selector)"
  type        = map(string)
  default     = {}
}

# ── Health check ───────────────────────────────────────
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

variable "log_retention_days" {
  type    = number
  default = 14
}

# ── Shared-platform mode ──────────────────────────────
# Defaults reproduce the original behaviour exactly: this app builds its own ALB
# and ECS cluster. Set create_alb/create_cluster false and supply the existing_*
# values to attach to another stack's infrastructure instead.

variable "create_alb" {
  description = "Create a dedicated ALB. False = attach to an existing one via existing_*."
  type        = bool
  default     = true
}

variable "create_cluster" {
  description = "Create a dedicated ECS cluster. False = run in an existing one."
  type        = bool
  default     = true
}

variable "existing_alb_dns_name" {
  description = "DNS name of the shared ALB (required when create_alb = false)"
  type        = string
  default     = ""
}

variable "existing_alb_zone_id" {
  description = "Hosted-zone id of the shared ALB (required when create_alb = false)"
  type        = string
  default     = ""
}

variable "existing_https_listener_arn" {
  description = "ARN of the shared ALB's HTTPS listener (required when create_alb = false)"
  type        = string
  default     = ""
}

variable "existing_cluster_arn" {
  description = "ARN of the shared ECS cluster (required when create_cluster = false)"
  type        = string
  default     = ""
}

variable "existing_cluster_name" {
  description = "Name of the shared ECS cluster (required when create_cluster = false)"
  type        = string
  default     = ""
}

variable "listener_rule_priority_base" {
  description = <<-EOT
    First listener-rule priority to claim on a shared ALB. This app uses
    <base> for its host-header forward and <base>+1 for the www redirect, so
    each guest app on the same listener needs a distinct base. Ignored when
    create_alb = true.
  EOT
  type        = number
  default     = 100
}

variable "tasks_in_public_subnets" {
  description = <<-EOT
    Run ECS tasks in the public subnets with public IPs, so the VPC needs no NAT
    gateway. Pair with networking's `enable_nat_gateway = false`.

    Safe because the task security group admits inbound traffic only from the
    ALB. Do not enable if anything downstream allowlists this app's outbound IP —
    egress moves from the NAT's stable Elastic IP to per-task ephemeral IPs.
  EOT
  type        = bool
  default     = false
}

variable "container_insights" {
  description = "Turn on CloudWatch Container Insights for the cluster (billed per metric). Ignored when create_cluster = false."
  type        = bool
  default     = false
}

variable "alb_deletion_protection" {
  description = "Block deleting the ALB until this is set back to false. Leave off if you tear stacks down with destroy-app. Ignored when create_alb = false."
  type        = bool
  default     = false
}
