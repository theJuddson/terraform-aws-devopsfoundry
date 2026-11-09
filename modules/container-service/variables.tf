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

# ── WAF (opt-in) ──────────────────────────────────────
# Both are ignored when create_alb = false: a shared ALB's web ACL belongs to
# the platform that owns the ALB, so guest apps inherit it.
variable "create_waf" {
  description = <<-EOT
    Create a regional WAF web ACL and attach it to the ALB: a per-IP rate limit
    plus the AWS managed rule groups in waf_managed_rule_groups. Costs about
    $5/month per web ACL + $1/month per rule + $0.60 per million requests.
    Ignored when create_alb = false.
  EOT
  type        = bool
  default     = false
}

variable "waf_web_acl_arn" {
  description = "Attach this existing regional web ACL to the ALB instead of creating one. Mutually exclusive with create_waf. Ignored when create_alb = false."
  type        = string
  default     = ""

  validation {
    condition     = var.waf_web_acl_arn == "" || can(regex("^arn:aws[a-z-]*:wafv2:[a-z0-9-]+:[0-9]{12}:regional/webacl/", var.waf_web_acl_arn))
    error_message = "waf_web_acl_arn must be a regional WAFv2 web ACL ARN (arn:aws:wafv2:<region>:<account>:regional/webacl/...)."
  }
}

variable "waf_count_only" {
  description = <<-EOT
    Run every WAF rule in count mode: matches are counted in CloudWatch metrics
    and sampled requests, nothing is blocked. Start here on a live ALB, check the
    counts, then set false to enforce.
  EOT
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = <<-EOT
    Requests per client IP per 5 minutes before the rate rule blocks that IP
    (AWS minimum 10). Counts every host on the ALB together, so size it for the
    busiest legitimate client, e.g. an office behind one NAT using several apps.
  EOT
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 10 && var.waf_rate_limit <= 2000000000
    error_message = "waf_rate_limit must be between 10 and 2,000,000,000 (AWS limits)."
  }
}

variable "waf_managed_rule_groups" {
  description = <<-EOT
    AWS managed rule groups (vendor AWS) to apply, in order. The defaults are
    free of extra subscription charges: the core rule set (OWASP-style checks),
    known bad inputs (e.g. Log4Shell) and Amazon's IP reputation list.
  EOT
  type        = list(string)
  default = [
    "AWSManagedRulesAmazonIpReputationList",
    "AWSManagedRulesCommonRuleSet",
    "AWSManagedRulesKnownBadInputsRuleSet",
  ]
}

variable "waf_rule_overrides" {
  description = <<-EOT
    Individual managed rules to run in count mode instead of blocking, keyed by
    rule group, e.g. { AWSManagedRulesCommonRuleSet = ["SizeRestrictions_BODY"] }
    when an app legitimately accepts request bodies over 8 KB.
  EOT
  type        = map(list(string))
  default     = {}
}

variable "log_kms_key_arn" {
  description = "Customer managed KMS key for the app's CloudWatch log group. null (default) = CloudWatch's default encryption. The key policy must allow logs.<region>.amazonaws.com (see AWS's CloudWatch Logs encryption guide)."
  type        = string
  default     = null

  validation {
    condition     = var.log_kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "secrets_kms_key_arns" {
  description = "Customer managed KMS keys that encrypt any of `secrets`. The task execution role gets kms:Decrypt on them, which it needs to read those secrets at start."
  type        = list(string)
  default     = []
}

variable "alb_access_logs" {
  description = "Write ALB access logs to S3. Creates a private, SSE-S3 encrypted bucket <name>-alb-logs-<account> unless alb_access_logs_bucket names one. Ignored when create_alb = false."
  type        = bool
  default     = false
}

variable "alb_access_logs_bucket" {
  description = "Existing bucket for the ALB access logs, which must already allow ELB log delivery (see AWS's ALB access logs guide). Empty (default) = create one."
  type        = string
  default     = ""
}

variable "alb_access_logs_retention_days" {
  description = "Days to keep access logs in the bucket this module creates."
  type        = number
  default     = 90

  validation {
    condition     = var.alb_access_logs_retention_days >= 1 && floor(var.alb_access_logs_retention_days) == var.alb_access_logs_retention_days
    error_message = "alb_access_logs_retention_days must be a whole number of days, 1 or more."
  }
}
