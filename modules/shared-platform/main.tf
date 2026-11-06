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
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# ── Locating the host platform ────────────────────────
# Resolution is by DevOpsFoundry's own naming conventions, which modules/
# networking and modules/container-service apply consistently:
#
#   VPC      <platform>-vpc                 (tag:Name)
#   subnets  <platform>-public-<az>         (tag:Name)
#            <platform>-private-<az>        (tag:Name)
#   ALB SG   <platform>-alb-sg              (tag:Name)
#   ALB      <platform>-alb                 (name)
#   cluster  <platform>-cluster             (name)
#
# If a platform was renamed or built outside this tool, these lookups fail loudly
# at plan time rather than silently attaching to the wrong network.

data "aws_vpc" "platform" {
  filter {
    name   = "tag:Name"
    values = ["${var.platform_name}-vpc"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.platform_name}-public-*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.platform.id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.platform_name}-private-*"]
  }
}

data "aws_security_group" "platform_alb" {
  vpc_id = data.aws_vpc.platform.id
  filter {
    name   = "tag:Name"
    values = ["${var.platform_name}-alb-sg"]
  }
}

data "aws_lb" "platform" {
  name = "${var.platform_name}-alb"
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.platform.arn
  port              = var.https_listener_port
}

data "aws_ecs_cluster" "platform" {
  cluster_name = "${var.platform_name}-cluster"
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
