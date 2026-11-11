# ElastiCache Redis (single node by default, encrypted) with a generated auth token.
# The composite stores auth_token in a
# Secrets Manager secret and wires REDIS_PASSWORD into the task.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
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
  # bin/rotate-secret bumps auth_token_generation to make a new token. Null at 0,
  # so roots from before rotation existed plan no change.
  keepers = var.auth_token_generation == 0 ? null : { generation = tostring(var.auth_token_generation) }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${local.name_prefix}-redis"
  description                = "${local.name_prefix} Redis"
  engine                     = "redis"
  engine_version             = var.engine_version
  node_type                  = var.node_type
  num_cache_clusters         = var.num_cache_clusters
  port                       = var.cache_port
  parameter_group_name       = var.parameter_group_name # tflint-ignore: aws_elasticache_replication_group_default_parameter_group # default.redis7 is intended; callers may pass their own
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [var.redis_security_group_id]
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_arn
  transit_encryption_enabled = true
  auth_token                 = random_password.auth_token.result
  # ROTATE keeps the previous token valid alongside the new one; SET makes the
  # current token the only one. The provider applies either change immediately.
  auth_token_update_strategy = var.auth_token_update_strategy
  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1
  snapshot_retention_limit   = 0
  apply_immediately          = false
  tags                       = { Name = "${local.name_prefix}-redis" }
}
