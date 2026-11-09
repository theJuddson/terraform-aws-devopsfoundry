# The Redis replication group: encrypted with an auth token, one node by
# default, Multi-AZ failover when replicas are asked for. Plans only, against
# mocked providers: no AWS account is touched.

mock_provider "aws" {}
mock_provider "random" {}

variables {
  name                    = "demo"
  private_subnet_ids      = ["subnet-a", "subnet-b"]
  redis_security_group_id = "sg-redis"
}

run "defaults_single_encrypted_node" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.main.replication_group_id == "demo-redis" && aws_elasticache_replication_group.main.num_cache_clusters == 1
    error_message = "By default the cache is one node, named after the app."
  }
  assert {
    condition     = aws_elasticache_replication_group.main.at_rest_encryption_enabled && aws_elasticache_replication_group.main.transit_encryption_enabled
    error_message = "Redis must be encrypted at rest and in transit (the auth token needs TLS)."
  }
  assert {
    condition     = !aws_elasticache_replication_group.main.automatic_failover_enabled && !aws_elasticache_replication_group.main.multi_az_enabled
    error_message = "A single node cannot fail over; both must stay off."
  }
  assert {
    condition     = random_password.auth_token.length == 48 && !random_password.auth_token.special
    error_message = "The auth token must be long and use only characters Redis accepts."
  }
  assert {
    condition     = aws_elasticache_replication_group.main.security_group_ids == toset(["sg-redis"])
    error_message = "The cache must sit behind the given security group."
  }
}

run "replicas_turn_on_multi_az_failover" {
  command = plan

  variables {
    num_cache_clusters = 2
  }

  assert {
    condition     = aws_elasticache_replication_group.main.num_cache_clusters == 2
    error_message = "num_cache_clusters must set the node count."
  }
  assert {
    condition     = aws_elasticache_replication_group.main.automatic_failover_enabled && aws_elasticache_replication_group.main.multi_az_enabled
    error_message = "With replicas, Redis must fail over automatically across AZs."
  }
}

run "num_cache_clusters_is_checked" {
  command = plan

  variables {
    num_cache_clusters = 0
  }

  expect_failures = [var.num_cache_clusters]
}
