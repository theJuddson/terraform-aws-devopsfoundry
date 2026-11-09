# ── Identity / DNS ─────────────────────────────────────
variable "name" {
  description = "Resource-name prefix / app slug (e.g. myapp-com)"
  type        = string
}

variable "domain_name" {
  description = "Apex domain registered at Namecheap"
  type        = string
}

variable "subdomain" {
  description = "Subdomain fronting the service (api -> api.example.com). Empty or \"@\" serves at the apex (example.com)."
  type        = string
  default     = "api"
}

variable "service_name" {
  description = "Short container/service name"
  type        = string
  default     = "app"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# ── Container ──────────────────────────────────────────
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

# ── Networking ─────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}
variable "az_count" {
  type    = number
  default = 2
}

variable "enable_flow_logs" {
  description = "Send VPC flow logs to CloudWatch (billed per GB). Ignored in shared-platform mode, where the host owns the VPC."
  type        = bool
  default     = false
}
variable "flow_log_traffic_type" {
  description = "ACCEPT, REJECT or ALL; see the networking module."
  type        = string
  default     = "ALL"
}
variable "flow_log_retention_days" {
  type    = number
  default = 30
}

# ── Toggles ────────────────────────────────────────────
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

# ── Database tuning ────────────────────────────────────
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

variable "db_performance_insights_enabled" {
  description = "Performance Insights, kept for the free 7 days."
  type        = bool
  default     = false
}
variable "db_monitoring_interval" {
  description = "Enhanced monitoring interval in seconds (0 = off)."
  type        = number
  default     = 0
}
variable "db_iam_database_authentication_enabled" {
  type    = bool
  default = false
}
variable "db_log_min_duration_ms" {
  description = "Log Postgres statements slower than this many ms (0 = all, null = off). Takes effect after the instance's next reboot."
  type        = number
  default     = null
}

# ── Cache tuning ───────────────────────────────────────
variable "cache_node_type" {
  type    = string
  default = "cache.t4g.micro"
}
variable "cache_engine_version" {
  type    = string
  default = "7.1"
}

variable "cache_num_cache_clusters" {
  description = "Redis nodes; 2 or more adds replicas with Multi-AZ automatic failover."
  type        = number
  default     = 1
}

# ── Email ──────────────────────────────────────────────
variable "dmarc_rua_email" {
  description = "DMARC report address (required when enable_email=true)"
  type        = string
  default     = ""
}

variable "dmarc_policy" {
  description = "DMARC policy: none | quarantine | reject"
  type        = string
  default     = "none"
}

variable "mail_from_subdomain" {
  description = "Custom MAIL FROM subdomain label for SPF alignment (e.g. 'mail'). Empty = SES default."
  type        = string
  default     = ""
}

variable "shared_platform" {
  description = <<-EOT
    Slug of an EXISTING DevOpsFoundry app whose VPC, NAT gateway, ALB and ECS
    cluster this app should share (e.g. "other-app-com"). Empty (the default)
    provisions dedicated infrastructure.

    Sharing removes the two largest fixed costs — NAT (~$33/mo) and ALB
    (~$16/mo) — at the price of a shared failure domain with the host platform.
    A database, when enabled, is still this app's own.
  EOT
  type        = string
  default     = ""
}

variable "listener_rule_priority_base" {
  description = "First ALB listener-rule priority to claim in shared mode; each guest app needs a distinct base"
  type        = number
  default     = 100
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Provision a NAT gateway (~$33/month). Ignored in shared-platform mode, where
    the host platform's networking already decides this.

    Set false together with `tasks_in_public_subnets = true` to remove the single
    largest fixed cost of a small stack.
  EOT
  type        = bool
  default     = true
}

variable "tasks_in_public_subnets" {
  description = "Run ECS tasks in public subnets with public IPs (no NAT needed). Inbound stays ALB-only. In shared-platform mode this must match the host: true if the host has no NAT gateway (the plan fails otherwise)."
  type        = bool
  default     = false
}

variable "existing_zone_name" {
  validation {
    condition     = var.existing_zone_name == "" || can(regex("^[a-z0-9.-]+$", var.existing_zone_name))
    error_message = "existing_zone_name must be a DNS name like example.com."
  }
  description = <<-EOT
    Name of an EXISTING public Route53 hosted zone (e.g. "example.com") to place this app's records in.
    Empty (default) = DevOpsFoundry creates a zone for domain_name and delegates the domain's Namecheap
    nameservers to it. When set, no zone is created and the registrar is never touched: the ACM cert covers
    exactly the service hostname (no wildcard), and only its validation and alias records are added, never
    overwriting existing ones. For hosting an app under a domain whose DNS already serves something else.
  EOT
  type        = string
  default     = ""
}

variable "manage_nameservers" {
  description = <<-EOT
    Whether Terraform manages the domain's Namecheap nameserver delegation to the Route53 zone (ignored when
    existing_zone_name is set). The delegation is set once and never changes, but managing it makes every plan
    call the Namecheap API, which only answers whitelisted IPs. Set false after the first apply so deploys
    never need Namecheap. On an existing stack, first run
    `terraform state rm 'module.<name>.module.namecheap_ns[0].namecheap_domain_records.ns'`; without it,
    Terraform deletes the delegation. (A `removed` block can't do this: the module block is still declared.)
  EOT
  type        = bool
  default     = true
}

# ── Observability and protection (opt-in) ──────────────
variable "container_insights" {
  description = "CloudWatch Container Insights on the app's cluster (billed per metric). Ignored in shared-platform mode."
  type        = bool
  default     = false
}
variable "alb_deletion_protection" {
  description = "Block deleting the ALB; turn off again before destroy-app. Ignored in shared-platform mode."
  type        = bool
  default     = false
}

# ── WAF on the ALB (opt-in) ─────────────────────────────
# Ignored in shared-platform mode: guest apps inherit the host platform's web ACL.
variable "create_waf" {
  description = "Create a WAF web ACL (per-IP rate limit + AWS managed rules) on the ALB. About $5/month + $1/rule + $0.60 per million requests."
  type        = bool
  default     = false
}
variable "waf_web_acl_arn" {
  description = "Attach an existing regional web ACL to the ALB instead of creating one. Mutually exclusive with create_waf."
  type        = string
  default     = ""
}
variable "waf_count_only" {
  description = "Count WAF matches without blocking. Start here on a live ALB, then set false to enforce."
  type        = bool
  default     = false
}
variable "waf_rate_limit" {
  description = "Requests per client IP per 5 minutes before the rate rule blocks it, across every host on the ALB."
  type        = number
  default     = 2000
}
variable "waf_managed_rule_groups" {
  description = "AWS managed rule groups to apply, in order."
  type        = list(string)
  default     = ["AWSManagedRulesAmazonIpReputationList", "AWSManagedRulesCommonRuleSet", "AWSManagedRulesKnownBadInputsRuleSet"]
}
variable "waf_rule_overrides" {
  description = "Managed rules to count instead of block, keyed by rule group, e.g. { AWSManagedRulesCommonRuleSet = [\"SizeRestrictions_BODY\"] }."
  type        = map(list(string))
  default     = {}
}
