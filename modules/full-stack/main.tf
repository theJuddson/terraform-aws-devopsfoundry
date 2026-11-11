# Composite: DNS (Route53 + Namecheap NS delegation) + ACM + VPC + a generic
# ECS Fargate container service, with optional RDS / Redis / SES. Designed so a
# consuming repo's .devopsfoundry/main.tf is a thin provider block + one call to
# this module.
#
# Two-phase apply (driven by bin/new-app) targets module.route53_zone +
# module.namecheap_ns first to flip nameservers, then a full apply validates the
# cert and builds the service — same race-avoidance as the static path.
# With existing_zone_name set there is no zone/NS phase: records go into that
# zone and the registrar is never touched.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.60"
      configuration_aliases = [aws, aws.us_east_1]
    }
    namecheap = {
      source  = "namecheap/namecheap"
      version = ">= 2.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

locals {
  # Conventional connection vars auto-injected when a backing service is on.
  # Caller's env/secrets (var.env / var.secrets) merge LAST so they win.
  db_env = var.enable_database ? {
    DB_URL  = "postgresql://${module.database[0].address}:${module.database[0].port}/${module.database[0].db_name}"
    DB_HOST = module.database[0].address
    DB_PORT = tostring(module.database[0].port)
    DB_NAME = module.database[0].db_name
  } : {}
  db_secrets = var.enable_database ? {
    DB_USERNAME = "${module.database[0].master_user_secret_arn}:username::"
    DB_PASSWORD = "${module.database[0].master_user_secret_arn}:password::"
  } : {}

  cache_env = var.enable_cache ? {
    REDIS_HOST        = module.cache[0].primary_endpoint
    REDIS_PORT        = tostring(module.cache[0].port)
    REDIS_SSL_ENABLED = "true"
  } : {}
  cache_secrets = var.enable_cache ? {
    REDIS_PASSWORD = aws_secretsmanager_secret.redis_auth[0].arn
  } : {}

  email_env = var.enable_email ? {
    MAIL_HOST = module.email[0].smtp_host
    MAIL_PORT = "587"
  } : {}
  email_secrets = var.enable_email ? {
    MAIL_USERNAME = "${module.email[0].smtp_secret_arn}:username::"
    MAIL_PASSWORD = "${module.email[0].smtp_secret_arn}:password::"
  } : {}

  # Shared-platform mode: borrow another DevOpsFoundry stack's VPC, NAT, ALB and
  # ECS cluster instead of building dedicated ones. Empty string (the default)
  # keeps the original behaviour exactly.
  use_shared = var.shared_platform != ""
  net        = local.use_shared ? module.shared_platform[0] : module.networking[0]

  # Existing-zone mode: records go into a zone this stack does not own; no NS delegation.
  use_existing_zone = var.existing_zone_name != ""
  service_fqdn      = (var.subdomain == "" || var.subdomain == "@") ? var.domain_name : "${var.subdomain}.${var.domain_name}"
  zone_id           = local.use_existing_zone ? data.aws_route53_zone.existing[0].zone_id : module.route53_zone[0].zone_id
  validation_fqdns = (local.use_existing_zone
    ? [for r in aws_route53_record.existing_zone_validation : r.fqdn]
  : module.route53_zone[0].validation_record_fqdns)

  merged_env     = merge(local.db_env, local.cache_env, local.email_env, var.env)
  merged_secrets = merge(local.db_secrets, local.cache_secrets, local.email_secrets, var.secrets)
}

# ── DNS + cert (Phase 1 targets route53_zone + namecheap_ns) ──
module "acm_cert" {
  source           = "../acm-cert"
  providers        = { aws = aws.us_east_1 }
  domain_name      = local.use_existing_zone ? local.service_fqdn : var.domain_name
  include_wildcard = !local.use_existing_zone
}

module "route53_zone" {
  source                        = "../route53-zone"
  count                         = local.use_existing_zone ? 0 : 1
  domain_name                   = var.domain_name
  acm_domain_validation_options = module.acm_cert.domain_validation_options
}

# DNSSEC and query logging for the zone this stack owns. Both must live in
# us-east-1. Not offered with existing_zone_name: that zone belongs to someone else.
module "route53_zone_security" {
  source                   = "../route53-zone-security"
  count                    = !local.use_existing_zone && (var.enable_dnssec || var.enable_dns_query_logging) ? 1 : 0
  providers                = { aws = aws.us_east_1 }
  zone_id                  = module.route53_zone[0].zone_id
  zone_name                = var.domain_name
  enable_dnssec            = var.enable_dnssec
  enable_query_logging     = var.enable_dns_query_logging
  query_log_retention_days = var.dns_query_log_retention_days
}

module "namecheap_ns" {
  source      = "../namecheap-ns"
  count       = local.use_existing_zone || !var.manage_nameservers ? 0 : 1
  domain_name = var.domain_name
  nameservers = module.route53_zone[0].name_servers
}

data "aws_route53_zone" "existing" {
  count        = local.use_existing_zone ? 1 : 0
  name         = var.existing_zone_name
  private_zone = false

  lifecycle {
    precondition {
      condition     = !var.enable_email
      error_message = "enable_email is not supported in an existing zone: SES records would sit beside the zone owner's mail setup."
    }
    postcondition {
      condition     = endswith(local.service_fqdn, ".${trimsuffix(var.existing_zone_name, ".")}")
      error_message = "existing_zone_name must be a parent of the service hostname, and apex serving is not allowed in an existing zone."
    }
  }
}

# Validation records in the existing zone. Never overwrite: a name clash means someone else owns it.
resource "aws_route53_record" "existing_zone_validation" {
  for_each = local.use_existing_zone ? {
    for dvo in module.acm_cert.domain_validation_options : dvo.resource_record_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}
  zone_id         = data.aws_route53_zone.existing[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 300
  records         = [each.value.record]
  allow_overwrite = false
}

resource "aws_acm_certificate_validation" "main" {
  provider                = aws.us_east_1
  certificate_arn         = module.acm_cert.certificate_arn
  validation_record_fqdns = local.validation_fqdns
  timeouts {
    create = "45m"
  }
}

# ── Network ───────────────────────────────────────────
module "networking" {
  source             = "../networking"
  count              = local.use_shared ? 0 : 1
  name               = var.name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  container_port     = var.container_port
  enable_database    = var.enable_database
  enable_cache       = var.enable_cache
  enable_nat_gateway = var.enable_nat_gateway

  enable_flow_logs        = var.enable_flow_logs
  flow_log_traffic_type   = var.flow_log_traffic_type
  flow_log_retention_days = var.flow_log_retention_days
  flow_log_kms_key_arn    = var.kms_key_arn
}

# ── Optional backing services ─────────────────────────
module "shared_platform" {
  source          = "../shared-platform"
  count           = local.use_shared ? 1 : 0
  platform_name   = var.shared_platform
  name            = var.name
  container_port  = var.container_port
  enable_database = var.enable_database
  enable_cache    = var.enable_cache

  tasks_in_public_subnets = var.tasks_in_public_subnets
}

module "database" {
  source                = "../database"
  count                 = var.enable_database ? 1 : 0
  name                  = var.name
  private_subnet_ids    = local.net.private_subnet_ids
  rds_security_group_id = local.net.rds_security_group_id
  db_name               = var.db_name
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  engine_version        = var.db_engine_version
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot

  performance_insights_enabled        = var.db_performance_insights_enabled
  monitoring_interval                 = var.db_monitoring_interval
  iam_database_authentication_enabled = var.db_iam_database_authentication_enabled
  log_min_duration_ms                 = var.db_log_min_duration_ms
}

module "cache" {
  source                  = "../cache"
  count                   = var.enable_cache ? 1 : 0
  name                    = var.name
  private_subnet_ids      = local.net.private_subnet_ids
  redis_security_group_id = local.net.redis_security_group_id
  node_type               = var.cache_node_type
  engine_version          = var.cache_engine_version
  num_cache_clusters      = var.cache_num_cache_clusters
  kms_key_arn             = var.kms_key_arn
}

# Composite owns the Redis auth secret (cache module only generates the token).
resource "aws_secretsmanager_secret" "redis_auth" {
  count                   = var.enable_cache ? 1 : 0
  name                    = "${var.name}/redis/auth"
  recovery_window_in_days = 7
  kms_key_id              = var.kms_key_arn
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  count         = var.enable_cache ? 1 : 0
  secret_id     = aws_secretsmanager_secret.redis_auth[0].id
  secret_string = module.cache[0].auth_token
}

module "email" {
  source              = "../email"
  count               = var.enable_email ? 1 : 0
  name                = var.name
  sender_domain       = var.domain_name
  sender_zone_id      = local.zone_id
  aws_region          = var.aws_region
  dmarc_rua_email     = var.dmarc_rua_email
  dmarc_policy        = var.dmarc_policy
  mail_from_subdomain = var.mail_from_subdomain

  dmarc_report_zone_id = var.dmarc_report_zone_id
  kms_key_arn          = var.kms_key_arn
}

# ── The service ───────────────────────────────────────
module "container_service" {
  source          = "../container-service"
  name            = var.name
  service_name    = var.service_name
  domain_name     = var.domain_name
  subdomain       = var.subdomain
  zone_id         = local.zone_id
  certificate_arn = aws_acm_certificate_validation.main.certificate_arn

  vpc_id                = local.net.vpc_id
  public_subnet_ids     = local.net.public_subnet_ids
  private_subnet_ids    = local.net.private_subnet_ids
  alb_security_group_id = local.net.alb_security_group_id
  api_security_group_id = local.net.api_security_group_id

  # In shared mode the ALB and cluster already exist and are read-only here.
  create_alb                  = !local.use_shared
  create_cluster              = !local.use_shared
  existing_alb_dns_name       = local.use_shared ? module.shared_platform[0].alb_dns_name : ""
  existing_alb_zone_id        = local.use_shared ? module.shared_platform[0].alb_zone_id : ""
  existing_https_listener_arn = local.use_shared ? module.shared_platform[0].https_listener_arn : ""
  existing_cluster_arn        = local.use_shared ? module.shared_platform[0].ecs_cluster_arn : ""
  existing_cluster_name       = local.use_shared ? module.shared_platform[0].ecs_cluster_name : ""
  listener_rule_priority_base = var.listener_rule_priority_base

  container_image       = var.container_image
  container_port        = var.container_port
  cpu                   = var.cpu
  memory                = var.memory
  desired_count         = var.desired_count
  health_check_path     = var.health_check_path
  health_check_matcher  = var.health_check_matcher
  health_check_interval = var.health_check_interval
  health_check_timeout  = var.health_check_timeout

  tasks_in_public_subnets = var.tasks_in_public_subnets
  cpu_architecture        = var.cpu_architecture
  container_insights      = var.container_insights
  alb_deletion_protection = var.alb_deletion_protection
  log_kms_key_arn         = var.kms_key_arn

  alb_access_logs                = var.alb_access_logs
  alb_access_logs_bucket         = var.alb_access_logs_bucket
  alb_access_logs_retention_days = var.alb_access_logs_retention_days
  secrets_kms_key_arns           = var.kms_key_arn == null ? [] : [var.kms_key_arn]

  create_waf              = var.create_waf
  waf_web_acl_arn         = var.waf_web_acl_arn
  waf_count_only          = var.waf_count_only
  waf_rate_limit          = var.waf_rate_limit
  waf_managed_rule_groups = var.waf_managed_rule_groups
  waf_rule_overrides      = var.waf_rule_overrides

  env     = local.merged_env
  secrets = local.merged_secrets
}

# ── Platform descriptor (opt-in) ──────────────────────
# Publishes this stack's shared infrastructure by ID under a name of its own, so
# guests can find it without relying on the <name>-vpc/-alb/-cluster naming
# conventions. Renaming a shared platform is then: publish under the new name,
# point guests at it. No AWS resource is renamed or replaced. Read by
# modules/shared-platform; the schema is documented there.
resource "aws_ssm_parameter" "platform_descriptor" {
  #checkov:skip=CKV2_AWS_34:Holds only resource IDs (VPC, subnets, ALB, cluster), no secrets; String (and insecure_value, so plans show it) keeps it readable without KMS grants
  count       = var.platform_name != "" ? 1 : 0
  name        = "/devopsfoundry/platform/${var.platform_name}"
  description = "DevOpsFoundry shared platform ${var.platform_name}, hosted by ${var.name}"
  type        = "String"
  insecure_value = jsonencode({
    version               = 1
    host                  = var.name
    vpc_id                = local.net.vpc_id
    public_subnet_ids     = local.net.public_subnet_ids
    private_subnet_ids    = local.net.private_subnet_ids
    alb_security_group_id = local.net.alb_security_group_id
    alb_arn               = module.container_service.alb_arn
    ecs_cluster_name      = module.container_service.ecs_cluster_name
  })

  lifecycle {
    precondition {
      condition     = !local.use_shared
      error_message = "platform_name publishes this stack's own network and ALB; a stack in shared-platform mode has none to publish. Set it on the host platform instead."
    }
  }
}

# ── State migration ───────────────────────────────────
# `networking` gained a count when shared-platform mode was added. Without this,
# Terraform would plan to destroy and recreate the VPC (and everything in it)
# for every app already using this module.
moved {
  from = module.networking
  to   = module.networking[0]
}

# `route53_zone` and `namecheap_ns` gained a count with existing-zone mode. Without these, every app
# already using this module would plan to destroy its zone and revert its nameservers.
moved {
  from = module.route53_zone
  to   = module.route53_zone[0]
}

moved {
  from = module.namecheap_ns
  to   = module.namecheap_ns[0]
}
