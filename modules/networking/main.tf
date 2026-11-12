# VPC + public/private subnets + single NAT + security groups.
# Generalized to a single `name`
# prefix and a parameterized container port, with RDS/Redis SGs gated on the
# database/cache toggles.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix          = var.name
  az_names             = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  public_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_subnet" "public" {
  count                   = var.az_count
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.az_names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${local.name_prefix}-public-${local.az_names[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count             = var.az_count
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index]
  tags = {
    Name = "${local.name_prefix}-private-${local.az_names[count.index]}"
    Tier = "private"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

# A NAT gateway costs ~$33/month before carrying a single byte, which for a
# small service is usually the largest line on the bill. It exists so tasks in
# private subnets can reach ECR, Secrets Manager and CloudWatch. When
# `enable_nat_gateway` is false those tasks run in the PUBLIC subnets with public
# IPs instead, reaching the same services through the internet gateway — which is
# free. Their security group still admits traffic only from the ALB, so they stay
# unreachable from the internet.
#
# Private subnets remain, and remain private: RDS and ElastiCache live there and
# need no internet egress. With the NAT gone they simply have no default route.
resource "aws_eip" "nat" {
  count      = var.enable_nat_gateway ? 1 : 0
  domain     = "vpc"
  tags       = { Name = "${local.name_prefix}-nat-eip" }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${local.name_prefix}-nat" }
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name_prefix}-public-rt" }
}

# The private route table keeps existing either way — only its default route is
# conditional. Without a NAT there is simply no route off the VPC, which is the
# correct posture for a subnet holding only databases.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = { Name = "${local.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Security Groups ────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB - inbound 80/443 from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP from anywhere (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.name_prefix}-alb-sg" }
}

resource "aws_security_group" "api" {
  name        = "${local.name_prefix}-api-sg"
  description = "ECS Fargate tasks - inbound from ALB only, all egress"
  vpc_id      = aws_vpc.main.id
  egress {
    description = "All egress (NAT to internet for ECR, CloudWatch, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.name_prefix}-api-sg" }
}

resource "aws_security_group_rule" "api_ingress_from_alb" {
  type                     = "ingress"
  description              = "Container port from ALB"
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.api.id
}

# RDS SG (only when database enabled)
resource "aws_security_group" "rds" {
  count       = var.enable_database ? 1 : 0
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS Postgres - inbound ${var.db_port} from API only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-rds-sg" }
}

resource "aws_security_group_rule" "rds_ingress_from_api" {
  count                    = var.enable_database ? 1 : 0
  type                     = "ingress"
  description              = "Postgres from API"
  from_port                = var.db_port
  to_port                  = var.db_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id
  security_group_id        = aws_security_group.rds[0].id
}

# Redis SG (only when cache enabled)
resource "aws_security_group" "redis" {
  count       = var.enable_cache ? 1 : 0
  name        = "${local.name_prefix}-redis-sg"
  description = "ElastiCache Redis - inbound ${var.cache_port} from API only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name_prefix}-redis-sg" }
}

resource "aws_security_group_rule" "redis_ingress_from_api" {
  count                    = var.enable_cache ? 1 : 0
  type                     = "ingress"
  description              = "Redis from API"
  from_port                = var.cache_port
  to_port                  = var.cache_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.api.id
  security_group_id        = aws_security_group.redis[0].id
}

# ── State migration ───────────────────────────────────
# The NAT gateway and its EIP gained a count when it became optional. Without
# these, Terraform reads the address change as destroy-and-recreate, which would
# briefly cut internet egress for every task in the VPC.
moved {
  from = aws_eip.nat
  to   = aws_eip.nat[0]
}

moved {
  from = aws_nat_gateway.main
  to   = aws_nat_gateway.main[0]
}

# ── VPC flow logs (opt-in) ───────────────────────────
resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_158:CloudWatch default encryption unless flow_log_kms_key_arn is set
  #checkov:skip=CKV_AWS_338:Retention is flow_log_retention_days; a year of flow logs is costly for a small app
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.flow_log_kms_key_arn
  tags              = { Name = "${local.name_prefix}-flow-logs" }
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    # AWS's confused-deputy guidance for flow logs (#65): only for this account's
    # flow logs. Account, region and partition come from the VPC's ARN.
    dynamic "condition" {
      for_each = var.trust_policy_source_conditions ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [split(":", aws_vpc.main.arn)[4]]
      }
    }
    dynamic "condition" {
      for_each = var.trust_policy_source_conditions ? [1] : []
      content {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${split(":", aws_vpc.main.arn)[1]}:ec2:${split(":", aws_vpc.main.arn)[3]}:${split(":", aws_vpc.main.arn)[4]}:vpc-flow-log/*"]
      }
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count              = var.enable_flow_logs ? 1 : 0
  name               = "${local.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
}

data "aws_iam_policy_document" "flow_logs_write" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.flow_logs[0].arn,
      "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  name   = "write-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs_write[0].json
}

resource "aws_flow_log" "main" {
  count                = var.enable_flow_logs ? 1 : 0
  vpc_id               = aws_vpc.main.id
  traffic_type         = var.flow_log_traffic_type
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn
  tags                 = { Name = "${local.name_prefix}-flow-logs" }
}
