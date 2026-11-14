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

variable "cpu_architecture" {
  description = "`X86_64` (default) or `ARM64` (Graviton, about 20% cheaper per vCPU-hour). The image must be built for it; deploy-app reads the cpu_architecture output to do that. Changing it replaces the task definition (a normal rolling deploy)."
  type        = string
  default     = "X86_64"

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "deployment_circuit_breaker" {
  description = "Stop a deployment whose tasks keep failing and roll back to the last working one. Off by default so existing services plan no change; new app roots from bin/new-app turn it on."
  type        = bool
  default     = false
}

variable "alarm_emails" {
  description = "Email addresses for the baseline alarms (5xx rate, p99 latency, unhealthy and no healthy targets). Creates an SNS topic; each address must confirm AWS's subscription email. Empty, with alarm_sns_topic_arns empty, means no alarms."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.alarm_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", e))])
    error_message = "alarm_emails must be email addresses."
  }
}

variable "alarm_sns_topic_arns" {
  description = "Existing SNS topics the baseline alarms also notify (a team's topic, a chat integration). Setting this alone turns the alarms on without creating a topic."
  type        = list(string)
  default     = []
}

variable "alarm_topic_kms_key_arn" {
  description = "Customer managed KMS key for the alarm topic. Its key policy must let cloudwatch.amazonaws.com use it (kms:Decrypt, kms:GenerateDataKey*); the AWS-managed SNS key doesn't work with CloudWatch alarms. null = unencrypted."
  type        = string
  default     = null
}

variable "alarm_5xx_percent" {
  description = "Alarm when more than this percentage of the app's responses are 5xx (in 2 of 3 minutes)."
  type        = number
  default     = 5

  validation {
    condition     = var.alarm_5xx_percent > 0 && var.alarm_5xx_percent <= 100
    error_message = "alarm_5xx_percent must be above 0 and at most 100."
  }
}

variable "alarm_min_requests" {
  description = "Minutes with fewer requests than this count as a 0% error rate, so a single failure in a quiet minute doesn't alarm."
  type        = number
  default     = 20

  validation {
    condition     = var.alarm_min_requests >= 1 && floor(var.alarm_min_requests) == var.alarm_min_requests
    error_message = "alarm_min_requests must be a whole number, 1 or more."
  }
}

variable "alarm_p99_seconds" {
  description = "Alarm when the app's p99 response time is over this many seconds (in 2 of 3 minutes). Tune to about twice your normal p99."
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_p99_seconds > 0
    error_message = "alarm_p99_seconds must be above 0."
  }
}

variable "waf_allowed_countries" {
  description = <<-EOT
    Block every request whose client IP isn't in one of these countries (ISO 3166
    alpha-2 codes, e.g. ["US"]). Empty, the default, allows every country. The
    rule always blocks, even with waf_count_only: it's a decision, not a rule to
    tune. It sits after the rate rule and before the managed groups. Only with
    create_waf; one more WAF rule at $1 a month. AWS maps IPs to countries from
    its own database, so a few legitimate visitors (VPNs, travellers, webhooks
    sent from abroad) are blocked too.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.waf_allowed_countries : can(regex("^[A-Z]{2}$", c))])
    error_message = "waf_allowed_countries takes two-letter upper-case country codes, e.g. [\"US\", \"CA\"]."
  }
  validation {
    condition     = length(var.waf_allowed_countries) == 0 || (var.create_alb && var.create_waf)
    error_message = "waf_allowed_countries needs a WAF this module creates (create_waf on an app with its own ALB). A shared-platform guest gets the host's WAF: set it on the host."
  }
}

variable "waf_country_exempt_paths" {
  description = <<-EOT
    Request paths the country rule lets through from anywhere, matched exactly
    (e.g. ["/api/billing/webhook"]): webhooks from senders that don't promise
    where they send from, such as Stripe. The other WAF rules still apply. Only
    with waf_allowed_countries. Exempt only paths the app authenticates itself,
    by a signature or a token.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.waf_country_exempt_paths : startswith(p, "/")])
    error_message = "waf_country_exempt_paths are request paths, starting with /."
  }
  validation {
    condition     = length(var.waf_country_exempt_paths) == 0 || length(var.waf_allowed_countries) > 0
    error_message = "waf_country_exempt_paths only has a meaning with waf_allowed_countries."
  }
}

variable "waf_logging" {
  description = "Log the WAF's requests to CloudWatch Logs (aws-waf-logs-<name>-alb), with Authorization and Cookie redacted. Only with create_waf. Billed per GB ingested and stored; by default only blocked and counted requests are kept."
  type        = bool
  default     = false
}

variable "waf_log_all_requests" {
  description = "Keep every request in the WAF log, allowed ones too, not only blocked and counted. Much more volume."
  type        = bool
  default     = false
}

variable "waf_log_retention_days" {
  description = "Days to keep WAF request logs."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.waf_log_retention_days)
    error_message = "waf_log_retention_days must be a retention period CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, ...)."
  }
}

variable "trust_policy_source_conditions" {
  description = "Limit the task role's trust to ECS acting for to this account (aws:SourceAccount and aws:SourceArn), AWS's confused-deputy protection. On by default; set false to restore the unconditioned trust policy if a role can't be assumed."
  type        = bool
  default     = true
}
