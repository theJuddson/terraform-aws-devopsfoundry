# Attaches an app to an EXISTING DevOpsFoundry stack's shared infrastructure
# instead of building its own.
#
# WHY: modules/networking creates a VPC with a NAT gateway (~$33/mo) and
# container-service creates an ALB (~$16/mo). That fixed overhead dwarfs a small
# app's actual compute cost, and it is duplicated for every app that gets its own
# stack. This module lets an app borrow another stack's VPC, NAT, ALB and ECS
# cluster, so it pays only for its own task (and its own database, if enabled).
#
# WHAT IT DOES NOT DO: nothing here modifies a resource owned by the host
# platform's Terraform state. The platform's VPC, subnets, ALB, listener,
# security groups and cluster are read-only data sources. Everything this module
# creates — the security groups below, and in container-service the target group,
# listener rule and listener certificate — is owned by the consuming app's own
# state, so the platform never sees drift.
#
# THE TRADE-OFF, STATED PLAINLY: sharing a VPC and ALB means sharing a failure
# domain. An ALB or NAT problem on the host platform takes this app down too, and
# destroying the host stack strands this one. That is the right trade for a small
# app and the wrong one for anything that needs independent availability.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# ── Locating the host platform ────────────────────────
# 1. A platform descriptor, if the host publishes one: the SSM parameter
#    /devopsfoundry/platform/<platform_name>, written by full-stack's
#    platform_name. A JSON object:
#
#      { "version": 1, "host": "<host app slug>", "vpc_id": "vpc-...",
#        "public_subnet_ids": [...], "private_subnet_ids": [...],
#        "alb_security_group_id": "sg-...", "alb_arn": "arn:...",
#        "ecs_cluster_name": "..." }
#
#    Resources are then found by ID, so a platform can be published under a
#    generic name while its AWS resources keep the names they were built with.
#
# 2. Otherwise DevOpsFoundry's own naming conventions, which modules/networking
#    and modules/container-service apply consistently (platform_name is then the
#    host app's slug):
#
#      VPC      <platform>-vpc                 (tag:Name)
#      subnets  <platform>-public-<az>         (tag:Name)
#               <platform>-private-<az>        (tag:Name)
#      ALB SG   <platform>-alb-sg              (tag:Name)
#      ALB      <platform>-alb                 (name)
#      cluster  <platform>-cluster             (name)
#
# Either way every lookup still runs against AWS, so a stale descriptor or a
# platform built outside this tool fails loudly at plan time rather than
# silently attaching to the wrong network.

# By path, not by name: a missing parameter is an empty result here, where a
# by-name lookup would fail the plan for every platform without a descriptor.
data "aws_ssm_parameters_by_path" "platforms" {
  path = "/devopsfoundry/platform"
}

locals {
  descriptor_name  = "/devopsfoundry/platform/${var.platform_name}"
  descriptor_names = data.aws_ssm_parameters_by_path.platforms.names
  # The provider marks parameter values sensitive; a descriptor holds only
  # resource IDs, which the outputs below must pass on in the clear. A value
  # that is not JSON decodes to {} and fails descriptor_ok.
  descriptor = (contains(local.descriptor_names, local.descriptor_name)
    ? try(jsondecode(nonsensitive(data.aws_ssm_parameters_by_path.platforms.values[index(local.descriptor_names, local.descriptor_name)])), {})
  : null)
  use_descriptor = local.descriptor != null
  descriptor_ok = !local.use_descriptor || (
    try(local.descriptor.version, null) == 1 &&
    can(tostring(local.descriptor.vpc_id)) &&
    can(tolist(local.descriptor.public_subnet_ids)) &&
    can(tolist(local.descriptor.private_subnet_ids)) &&
    can(tostring(local.descriptor.alb_security_group_id)) &&
    can(tostring(local.descriptor.alb_arn)) &&
    can(tostring(local.descriptor.ecs_cluster_name))
  )
  d = local.use_descriptor && local.descriptor_ok ? local.descriptor : null
}

data "aws_vpc" "platform" {
  id = local.d != null ? local.d.vpc_id : null
  lifecycle {
    # Checked before any lookup, so a malformed descriptor is reported as such
    # rather than as a missing VPC. aws_lb and aws_ecs_cluster wait for this.
    precondition {
      condition     = local.descriptor_ok
      error_message = "The SSM parameter ${local.descriptor_name} is not a version 1 platform descriptor (see modules/shared-platform/main.tf for the schema). Fix or delete it; nothing was attached."
    }
  }
  dynamic "filter" {
    for_each = local.d == null ? [1] : []
    content {
      name   = "tag:Name"
      values = ["${var.platform_name}-vpc"]
    }
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  dynamic "filter" {
    for_each = local.d != null ? { "subnet-id" = local.d.public_subnet_ids } : { "tag:Name" = ["${var.platform_name}-public-*"] }
    content {
      name   = filter.key
      values = filter.value
    }
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  dynamic "filter" {
    for_each = local.d != null ? { "subnet-id" = local.d.private_subnet_ids } : { "tag:Name" = ["${var.platform_name}-private-*"] }
    content {
      name   = filter.key
      values = filter.value
    }
  }
}

data "aws_security_group" "platform_alb" {
  vpc_id = data.aws_vpc.platform.id
  id     = local.d != null ? local.d.alb_security_group_id : null
  dynamic "filter" {
    for_each = local.d == null ? [1] : []
    content {
      name   = "tag:Name"
      values = ["${var.platform_name}-alb-sg"]
    }
  }
}

data "aws_lb" "platform" {
  arn  = local.d != null ? local.d.alb_arn : null
  name = local.d != null ? null : "${var.platform_name}-alb"
  # After the descriptor check on aws_vpc.platform; reading is not deferred.
  depends_on = [data.aws_vpc.platform]
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.platform.arn
  port              = var.https_listener_port
}

data "aws_ecs_cluster" "platform" {
  cluster_name = local.d != null ? local.d.ecs_cluster_name : "${var.platform_name}-cluster"
  # After the descriptor check on aws_vpc.platform; reading is not deferred.
  depends_on = [data.aws_vpc.platform]
}

# ── Can this app's tasks reach the internet? ──────────
# Tasks pull their image and secrets from AWS over the internet. A platform
# built with enable_nat_gateway = false runs its own tasks in the public subnets
# and leaves its private subnets with no default route. A guest whose tasks run
# there never starts: deploy-app waits out its 20-minute timeout on a
# ResourceInitializationError. Checked at plan instead (see aws_security_group.api).
data "aws_route_table" "private" {
  for_each  = toset(data.aws_subnets.private.ids)
  subnet_id = each.value
}

locals {
  private_subnets_have_egress = alltrue([
    for rt in data.aws_route_table.private : anytrue([for r in rt.routes : r.cidr_block == "0.0.0.0/0"])
  ])
}

# ── This app's own security groups, inside the shared VPC ──
# Deliberately not reusing the platform's api-sg: a dedicated group is what keeps
# this app's database reachable only by this app's tasks.

resource "aws_security_group" "api" {
  name        = "${var.name}-api-sg"
  description = "ECS Fargate tasks (${var.name}) - inbound from shared ALB only, all egress"
  vpc_id      = data.aws_vpc.platform.id

  egress {
    description = "All egress (NAT to internet for ECR, CloudWatch, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-api-sg" }

  lifecycle {
    precondition {
      condition     = var.tasks_in_public_subnets || local.private_subnets_have_egress
      error_message = "Platform \"${var.platform_name}\" has no NAT gateway, so its private subnets have no route to the internet and this app's tasks could not pull their image or secrets. Set tasks_in_public_subnets = true, as the platform itself does, or give the platform a NAT gateway."
    }
  }
}

# An ingress rule ON THIS APP'S security group that names the platform's ALB
# group as the source. This does not alter the platform's group.
resource "aws_security_group_rule" "api_ingress_from_alb" {
  type                     = "ingress"
  description              = "Container port from shared ALB"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.api.id
  source_security_group_id = data.aws_security_group.platform_alb.id
}

resource "aws_security_group" "rds" {
  count       = var.enable_database ? 1 : 0
  name        = "${var.name}-rds-sg"
  description = "RDS Postgres (${var.name}) - inbound ${var.db_port} from ${var.name} tasks only"
  vpc_id      = data.aws_vpc.platform.id
  tags        = { Name = "${var.name}-rds-sg" }
}

resource "aws_security_group_rule" "rds_ingress_from_api" {
  count                    = var.enable_database ? 1 : 0
  type                     = "ingress"
  description              = "Postgres from ${var.name} tasks"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds[0].id
  source_security_group_id = aws_security_group.api.id
}

resource "aws_security_group" "redis" {
  count       = var.enable_cache ? 1 : 0
  name        = "${var.name}-redis-sg"
  description = "ElastiCache Redis (${var.name}) - inbound ${var.cache_port} from ${var.name} tasks only"
  vpc_id      = data.aws_vpc.platform.id
  tags        = { Name = "${var.name}-redis-sg" }
}

resource "aws_security_group_rule" "redis_ingress_from_api" {
  count                    = var.enable_cache ? 1 : 0
  type                     = "ingress"
  description              = "Redis from ${var.name} tasks"
  from_port                = var.cache_port
  to_port                  = var.cache_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis[0].id
  source_security_group_id = aws_security_group.api.id
}
