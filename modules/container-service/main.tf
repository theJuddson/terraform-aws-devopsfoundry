# Generic containerized service on ECS Fargate behind an HTTPS ALB.
# Framework-neutral: the caller supplies arbitrary `env` (plaintext) and
# `secrets` (env-name -> Secrets Manager valueFrom). Creates ECR (via
# ../ecr-repository), CloudWatch logs, IAM roles, ALB + listeners,
# ECS cluster/service/task-def, and an A-alias to the ALB at either
# <subdomain>.<domain> or the apex <domain> (when subdomain is empty/"@").
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

# The region attribute is "region" on aws provider 6.x and "name" on 5.x (deprecated
# in 6.x). Reading it by key works on both without a deprecation warning.
data "aws_region" "current" {}

locals {
  region      = lookup(data.aws_region.current, "region", lookup(data.aws_region.current, "name", null))
  name_prefix = var.name
  # Empty (or "@") subdomain serves the app at the apex domain itself.
  apex         = var.subdomain == "" || var.subdomain == "@"
  service_fqdn = local.apex ? var.domain_name : "${var.subdomain}.${var.domain_name}"
  image_uri    = var.container_image != "" ? var.container_image : "${module.ecr.repository_url}:latest"

  # PORT is injected for convenience; caller's env map overrides it.
  env_final = merge({ PORT = tostring(var.container_port) }, var.env)
  env_list  = [for k, v in local.env_final : { name = k, value = v }]

  # Shared mode: the ALB, its listeners and the ECS cluster belong to another
  # app's stack and are read-only here. This app still owns its target group,
  # task definition, service, and the listener rule/certificate that route its
  # host name — so the host platform's state never sees drift.
  shared_alb = !var.create_alb

  alb_dns_name       = var.create_alb ? aws_lb.main[0].dns_name : var.existing_alb_dns_name
  alb_zone_id        = var.create_alb ? aws_lb.main[0].zone_id : var.existing_alb_zone_id
  https_listener_arn = var.create_alb ? aws_lb_listener.https[0].arn : var.existing_https_listener_arn
  cluster_arn        = var.create_cluster ? aws_ecs_cluster.main[0].id : var.existing_cluster_arn
  cluster_name       = var.create_cluster ? aws_ecs_cluster.main[0].name : var.existing_cluster_name

  # A dedicated ALB forwards this app by default, so only the www redirect needs
  # a rule (priority 1). A shared ALB forwards by host header, so this app needs
  # its own forward rule plus the redirect — at priorities that cannot collide
  # with rules the host platform or another guest app already holds.
  forward_rule_priority      = var.listener_rule_priority_base
  www_redirect_rule_priority = local.shared_alb ? var.listener_rule_priority_base + 1 : 1

  # WAF: only an ALB this stack owns gets a web ACL; guests inherit the host's.
  waf_create      = var.create_alb && var.create_waf
  waf_attach      = var.create_alb && (var.create_waf || var.waf_web_acl_arn != "")
  waf_web_acl_arn = local.waf_create ? aws_wafv2_web_acl.alb[0].arn : (local.waf_attach ? var.waf_web_acl_arn : "")
  waf_metric      = replace("${local.name_prefix}-alb", "/[^A-Za-z0-9_-]/", "-")

  secrets_list = [for k, v in var.secrets : { name = k, valueFrom = v }]
  # Exec role needs GetSecretValue on the underlying secret ARN. Strip any
  # trailing ":<json-key>::" selector from each valueFrom to get the base ARN.
  secret_arns = distinct([for v in values(var.secrets) : replace(v, "/:[^:]*::$/", "")])
}

# ── ECR ───────────────────────────────────────────────
# The repository lives in the ecr-repository module. These settings reproduce
# what this module always made: mutable tags (deploys move :latest),
# force_delete so teardown works with images inside, scan on push, keep the
# last 10 images.
module "ecr" {
  source               = "../ecr-repository"
  name                 = "${local.name_prefix}-${var.service_name}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  max_image_count      = 10
}

# ── CloudWatch Logs ───────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name_prefix}-${var.service_name}"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${local.name_prefix}-${var.service_name}-logs" }
}

# ── IAM ───────────────────────────────────────────────
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-${var.service_name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Only attach a secrets-read policy when there are secrets to read.
# count keys off the NUMBER OF SECRET ENTRIES (var.secrets keys are known at
# plan), NOT length(local.secret_arns): with --enable-db the injected RDS master
# secret ARN is unknown until apply, and distinct() over unknown values yields an
# unknown-length list — which Terraform rejects for `count`. The policy body can
# still reference local.secret_arns (unknown values are fine as arguments).
data "aws_iam_policy_document" "task_execution_secrets" {
  count = length(var.secrets) > 0 ? 1 : 0
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = local.secret_arns
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count  = length(var.secrets) > 0 ? 1 : 0
  name   = "read-task-secrets"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-${var.service_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ── ALB ───────────────────────────────────────────────
resource "aws_lb" "main" {
  #checkov:skip=CKV2_AWS_76:The opt-in WAF's rule groups are a variable; the default list includes AWSManagedRulesKnownBadInputsRuleSet (Log4j)
  count                      = var.create_alb ? 1 : 0
  name                       = "${local.name_prefix}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_security_group_id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.alb_deletion_protection
  idle_timeout               = 60
  tags                       = { Name = "${local.name_prefix}-alb" }
}

# ── WAF (opt-in) ──────────────────────────────────────
# A per-IP rate limit first (cheapest to evaluate), then the AWS managed rule
# groups. waf_count_only runs everything in count mode for a safe first rollout.
resource "aws_wafv2_web_acl" "alb" {
  #checkov:skip=CKV2_AWS_31:Request logging is billed per GB; CloudWatch metrics and sampled requests are on
  #checkov:skip=CKV_AWS_192:Rule groups are dynamic; the default list includes AWSManagedRulesKnownBadInputsRuleSet (Log4j)
  count       = local.waf_create ? 1 : 0
  name        = "${local.name_prefix}-alb"
  description = "Rate limit and AWS managed rules for ${local.name_prefix}-alb"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-per-ip"
    priority = 0

    action {
      dynamic "block" {
        for_each = var.waf_count_only ? [] : [1]
        content {}
      }
      dynamic "count" {
        for_each = var.waf_count_only ? [1] : []
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.waf_metric}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  dynamic "rule" {
    for_each = { for i, g in var.waf_managed_rule_groups : g => i }
    content {
      name     = rule.key
      priority = 10 + rule.value

      override_action {
        dynamic "none" {
          for_each = var.waf_count_only ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = var.waf_count_only ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = lookup(var.waf_rule_overrides, rule.key, [])
            content {
              name = rule_action_override.value
              action_to_use {
                count {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.waf_metric}-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.waf_metric
    sampled_requests_enabled   = true
  }

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count        = local.waf_attach ? 1 : 0
  resource_arn = aws_lb.main[0].arn
  web_acl_arn  = local.waf_web_acl_arn

  lifecycle {
    precondition {
      condition     = !(var.create_waf && var.waf_web_acl_arn != "")
      error_message = "Set create_waf or waf_web_acl_arn, not both."
    }
  }
}

resource "aws_lb_target_group" "app" {
  name                 = "${local.name_prefix}-${var.service_name}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "ip"
  deregistration_delay = 30
  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval
    timeout             = var.health_check_timeout
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
  tags = { Name = "${local.name_prefix}-${var.service_name}-tg" }
}

resource "aws_lb_listener" "http_redirect" {
  count             = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.main[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── ECS ───────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  count = var.create_cluster ? 1 : 0
  name  = "${local.name_prefix}-cluster"
  setting {
    name  = "containerInsights"
    value = var.container_insights ? "enabled" : "disabled"
  }
  tags = { Name = "${local.name_prefix}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  count              = var.create_cluster ? 1 : 0
  cluster_name       = aws_ecs_cluster.main[0].name
  capacity_providers = ["FARGATE"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-${var.service_name}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = var.service_name
    image        = local.image_uri
    essential    = true
    portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
    environment  = local.env_list
    secrets      = local.secrets_list
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = local.region
        awslogs-stream-prefix = var.service_name
      }
    }
  }])

  tags = { Name = "${local.name_prefix}-${var.service_name}-task" }
}

resource "aws_ecs_service" "app" {
  name                               = "${local.name_prefix}-${var.service_name}"
  cluster                            = local.cluster_arn
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  health_check_grace_period_seconds  = var.desired_count > 0 ? 120 : null
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Blocks apply until the task set is steady. With desired_count=0 (bootstrap)
  # the service is steady immediately; deploy-app scales it up after the first
  # image is pushed.
  wait_for_steady_state = true

  # Public-subnet placement exists to avoid needing a NAT gateway (~$33/month).
  # A public IP here does NOT make the task reachable: the security group admits
  # traffic only from the ALB. It only gives the task a route to ECR, Secrets
  # Manager and CloudWatch via the internet gateway instead of via NAT.
  #
  # One consequence worth knowing: outbound traffic then leaves from each task's
  # own ephemeral IP rather than the NAT's stable Elastic IP, so this is unsafe
  # if a third party allowlists this app's egress address.
  network_configuration {
    subnets          = var.tasks_in_public_subnets ? var.public_subnet_ids : var.private_subnet_ids
    security_groups  = [var.api_security_group_id]
    assign_public_ip = var.tasks_in_public_subnets
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.service_name
    container_port   = var.container_port
  }

  # New image lands on the same :latest tag; deploys roll via
  # `aws ecs update-service --force-new-deployment`, so ignore task_definition
  # churn from out-of-band image pushes is not needed (tag string is stable).
  depends_on = [aws_lb_listener.https, aws_lb_listener_rule.host_forward]

  lifecycle {
    precondition {
      condition     = var.create_cluster || (var.existing_cluster_arn != "" && var.existing_cluster_name != "")
      error_message = "create_cluster = false needs existing_cluster_arn and existing_cluster_name."
    }
  }
}

# ── Route53 alias (service FQDN -> ALB; apex alias when subdomain empty) ──
resource "aws_route53_record" "service" {
  zone_id = var.zone_id
  name    = local.service_fqdn
  type    = "A"
  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = true
  }

  lifecycle {
    precondition {
      condition = var.create_alb || (
        var.existing_alb_dns_name != "" && var.existing_alb_zone_id != "" && var.existing_https_listener_arn != ""
      )
      error_message = "create_alb = false needs existing_alb_dns_name, existing_alb_zone_id and existing_https_listener_arn."
    }
  }
}

# ── www -> apex redirect (apex serving only) ──────────
# When serving at the apex, also resolve www.<domain> to the ALB and 301 it to
# the apex. The ACM cert covers *.domain, so www terminates TLS fine; an ALB
# listener rule (higher priority than the default forward) does the redirect.
resource "aws_route53_record" "www" {
  count   = local.apex ? 1 : 0
  zone_id = var.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = local.alb_dns_name
    zone_id                = local.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_lb_listener_rule" "www_redirect" {
  count        = local.apex ? 1 : 0
  listener_arn = local.https_listener_arn
  priority     = local.www_redirect_rule_priority

  action {
    type = "redirect"
    redirect {
      host        = var.domain_name
      path        = "/#{path}"
      query       = "#{query}"
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header {
      values = ["www.${var.domain_name}"]
    }
  }
}

# ── Shared-ALB routing ────────────────────────────────
# On a dedicated ALB this app IS the default action, so nothing below is needed.
# On a shared ALB the default action belongs to the host platform, so this app
# claims its traffic by host header and adds its certificate for SNI. Both are
# resources this app owns; neither mutates the listener the platform manages.

resource "aws_lb_listener_certificate" "shared" {
  count           = local.shared_alb ? 1 : 0
  listener_arn    = local.https_listener_arn
  certificate_arn = var.certificate_arn
}

resource "aws_lb_listener_rule" "host_forward" {
  count        = local.shared_alb ? 1 : 0
  listener_arn = local.https_listener_arn
  priority     = local.forward_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    host_header {
      values = [local.service_fqdn]
    }
  }

  # The certificate must be on the listener before traffic is routed to this
  # host name, or the first requests fail TLS.
  depends_on = [aws_lb_listener_certificate.shared]
}

# ── State migration ───────────────────────────────────
# These resources gained `count` when shared-platform mode was added. Without
# these blocks Terraform reads the address change (aws_lb.main ->
# aws_lb.main[0]) as "destroy and recreate", which would tear down the load
# balancer and cluster of every app already using this module. `moved` tells it
# to re-key the existing state entry instead — a no-op plan for those apps.
moved {
  from = aws_lb.main
  to   = aws_lb.main[0]
}

moved {
  from = aws_lb_listener.http_redirect
  to   = aws_lb_listener.http_redirect[0]
}

moved {
  from = aws_lb_listener.https
  to   = aws_lb_listener.https[0]
}

moved {
  from = aws_ecs_cluster.main
  to   = aws_ecs_cluster.main[0]
}

moved {
  from = aws_ecs_cluster_capacity_providers.main
  to   = aws_ecs_cluster_capacity_providers.main[0]
}

# The ECR repository moved into the ecr-repository module. Re-key existing
# state so nothing is destroyed or recreated.
moved {
  from = aws_ecr_repository.app
  to   = module.ecr.aws_ecr_repository.this
}

moved {
  from = aws_ecr_lifecycle_policy.app
  to   = module.ecr.aws_ecr_lifecycle_policy.this
}
