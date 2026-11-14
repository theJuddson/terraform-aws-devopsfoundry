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
variable "cpu_architecture" {
  description = "X86_64 or ARM64 (Graviton); deploy-app builds the image to match"
  type        = string
  default     = "X86_64"
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

# ── Secret rotation (written to app.tfvars by bin/rotate-secret) ──
variable "cache_auth_token_generation" {
  description = "Bump to generate a new Redis auth token. Managed by bin/rotate-secret."
  type        = number
  default     = 0
}

variable "cache_auth_token_update_strategy" {
  description = "ROTATE keeps the previous Redis token valid while tasks restart; SET retires it. null = provider default. Managed by bin/rotate-secret."
  type        = string
  default     = null
}

variable "smtp_active_key" {
  description = "SMTP key slot (a or b) in the <name>/ses/smtp secret. Managed by bin/rotate-secret."
  type        = string
  default     = "a"
}

variable "smtp_standby_key" {
  description = "The other SMTP key slot: none, active (previous key still works) or inactive (retired). Managed by bin/rotate-secret."
  type        = string
  default     = "none"
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

variable "dmarc_report_zone_id" {
  description = "Route53 zone of dmarc_rua_email's domain, when that is another domain you control: creates the record that lets it receive reports"
  type        = string
  default     = ""
}

variable "shared_platform" {
  description = "Platform to share the VPC/NAT/ALB/ECS cluster of: a host's platform_name, or the host app's slug; empty = dedicated"
  type        = string
  default     = ""
}

variable "platform_name" {
  description = "Host only: publish this app's VPC/ALB/cluster as a shared platform under this name (an SSM parameter guests read); empty = none"
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

variable "manage_nameservers" {
  description = "Whether Terraform manages the Namecheap delegation. new-app sets false once it is live (bin/release-nameservers); never set it false by hand."
  type        = bool
  default     = true
}

variable "existing_zone_name" {
  description = "Existing Route53 zone to add this app's records to; empty = create a zone and delegate NS"
  type        = string
  default     = ""
}

variable "deployment_circuit_breaker" {
  description = "Stop a deployment whose tasks keep failing and roll back to the last working one. On for new app roots (bin/deploy-app then fails fast on a rolled-back deploy)."
  type        = bool
  default     = true
}

variable "alarm_emails" {
  description = "Email addresses for the baseline alarms: the service's 5xx rate, p99 latency and unhealthy targets, and the database's free storage and CPU. Each address confirms AWS's subscription email. Empty, with alarm_sns_topic_arns empty, means no alarms."
  type        = list(string)
  default     = []
}

variable "alarm_sns_topic_arns" {
  description = "Existing SNS topics the baseline alarms also notify. Setting this alone turns the alarms on."
  type        = list(string)
  default     = []
}

variable "waf_logging" {
  description = "Log the WAF's blocked and counted requests to CloudWatch Logs (Authorization and Cookie redacted). Only with create_waf; billed per GB."
  type        = bool
  default     = false
}

variable "waf_allowed_countries" {
  description = "Block requests from outside these countries (ISO 3166 alpha-2, e.g. [\"US\"]); empty allows all. Always blocks, even with waf_count_only. Only with create_waf."
  type        = list(string)
  default     = []
}

variable "trust_policy_source_conditions" {
  description = "Limit the service roles' trust (ECS task role, flow logs, RDS Enhanced Monitoring) to this account with aws:SourceAccount and aws:SourceArn. On by default; false restores the plain trust policies."
  type        = bool
  default     = true
}

variable "waf_country_exempt_paths" {
  description = "Paths the country rule lets through from anywhere, matched exactly (e.g. [\"/api/billing/webhook\"]), for webhooks the app authenticates itself."
  type        = list(string)
  default     = []
}
