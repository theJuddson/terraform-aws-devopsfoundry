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

# ── Opt-in observability and protection ───────────────
variable "enable_flow_logs" {
  description = "VPC flow logs to CloudWatch (billed per GB). Ignored in shared-platform mode."
  type        = bool
  default     = false
}
variable "container_insights" {
  description = "CloudWatch Container Insights on the cluster (billed per metric). Ignored in shared-platform mode."
  type        = bool
  default     = false
}
variable "alb_deletion_protection" {
  description = "Block deleting the ALB; turn off again before destroy-app. Ignored in shared-platform mode."
  type        = bool
  default     = false
}
variable "db_performance_insights_enabled" {
  type    = bool
  default = false
}
variable "db_monitoring_interval" {
  description = "RDS enhanced monitoring interval in seconds (0 = off)"
  type        = number
  default     = 0
}
variable "db_iam_database_authentication_enabled" {
  type    = bool
  default = false
}
variable "enable_dnssec" {
  description = "Sign the app's zone with DNSSEC; then publish dnssec_ds_record at the registrar (docs/dnssec.md)"
  type        = bool
  default     = false
}
variable "enable_dns_query_logging" {
  description = "Log the zone's DNS queries to CloudWatch in us-east-1 (billed per GB)"
  type        = bool
  default     = false
}
variable "alb_access_logs" {
  description = "ALB access logs to a private S3 bucket (storage billed; 90-day expiry). Ignored in shared-platform mode."
  type        = bool
  default     = false
}
variable "kms_key_arn" {
  description = "Customer managed KMS key for Redis, secrets and logs (null = AWS-managed keys)"
  type        = string
  default     = null
}
variable "db_log_min_duration_ms" {
  description = "Log Postgres statements slower than this many ms (null = off)"
  type        = number
  default     = null
}
variable "cache_num_cache_clusters" {
  description = "Redis nodes; 2 or more adds replicas with Multi-AZ failover"
  type        = number
  default     = 1
}

# ── Opt-in WAF on the ALB ─────────────────────────────
variable "create_waf" {
  description = "WAF web ACL on the ALB: per-IP rate limit + AWS managed rules (~$5/month + $1/rule + $0.60/M requests). Ignored in shared-platform mode."
  type        = bool
  default     = false
}

variable "waf_web_acl_arn" {
  description = "Attach an existing regional web ACL instead of creating one. Mutually exclusive with create_waf."
  type        = string
  default     = ""
}

variable "waf_count_only" {
  description = "Count WAF matches without blocking; set false to enforce once the counts look right."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Requests per client IP per 5 minutes before it's blocked, across every host on the ALB."
  type        = number
  default     = 2000
}

variable "waf_rule_overrides" {
  description = "Managed rules to count instead of block, keyed by rule group."
  type        = map(list(string))
  default     = {}
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
  description = "Run ECS tasks in public subnets with public IPs (no NAT needed). Inbound stays ALB-only. A guest on a shared platform must match the host."
  type        = bool
  default     = false
}

variable "existing_zone_name" {
  description = "Existing Route53 zone to add this app's records to; empty = create a zone and delegate NS"
  type        = string
  default     = ""
}
