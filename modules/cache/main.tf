# ElastiCache Redis (single node, encrypted) with a generated auth token.
# The composite stores auth_token in a
# Secrets Manager secret and wires REDIS_PASSWORD into the task.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

locals {
  name_prefix = var.name
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-redis"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${local.name_prefix}-redis-subnet-group" }
}

resource "random_password" "auth_token" {
  length  = 48
  special = false
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${local.name_prefix}-redis"
  description                = "${local.name_prefix} Redis"
  engine                     = "redis"
  engine_version             = var.engine_version
  node_type                  = var.node_type
  num_cache_clusters         = 1
  port                       = var.cache_port
  parameter_group_name       = var.parameter_group_name
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [var.redis_security_group_id]
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result
  automatic_failover_enabled = false
  snapshot_retention_limit   = 0
  apply_immediately          = false
  tags                       = { Name = "${local.name_prefix}-redis" }
}
