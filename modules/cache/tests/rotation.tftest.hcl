# Auth token rotation (#22): bin/rotate-secret bumps the generation to make a
# new token, applies it with ROTATE so the old one keeps working while tasks
# restart, then with SET to retire the old one. Plans only, mocked providers.

mock_provider "aws" {}
mock_provider "random" {}

variables {
  name                    = "demo"
  private_subnet_ids      = ["subnet-a", "subnet-b"]
  redis_security_group_id = "sg-redis"
}

# Roots from before rotation existed have no keepers on the token; adding any
# would replace it. Generation 0 must leave both unset.
run "defaults_keep_the_original_token" {
  command = plan

  assert {
    condition     = random_password.auth_token.keepers == null
    error_message = "Generation 0 must not set keepers, or upgrading would replace the token."
  }
  assert {
    condition     = aws_elasticache_replication_group.main.auth_token_update_strategy == null || aws_elasticache_replication_group.main.auth_token_update_strategy == "ROTATE"
    error_message = "With no strategy given, the provider default must apply."
  }
  assert {
    condition     = output.auth_token_rotation.generation == 0
    error_message = "The rotation output must report generation 0."
  }
}

run "a_new_generation_makes_a_new_token_applied_with_rotate" {
  command = plan

  variables {
    auth_token_generation      = 3
    auth_token_update_strategy = "ROTATE"
  }

  assert {
    condition     = random_password.auth_token.keepers == tomap({ generation = "3" })
    error_message = "The generation must key the token, so bumping it makes a new one."
  }
  assert {
    condition     = aws_elasticache_replication_group.main.auth_token_update_strategy == "ROTATE"
    error_message = "The strategy must reach the replication group."
  }
  assert {
    condition     = output.auth_token_rotation == { generation = 3, strategy = "ROTATE" }
    error_message = "The rotation output must report the generation and strategy."
  }
}

run "set_retires_the_previous_token" {
  command = plan

  variables {
    auth_token_generation      = 3
    auth_token_update_strategy = "SET"
  }

  assert {
    condition     = aws_elasticache_replication_group.main.auth_token_update_strategy == "SET"
    error_message = "SET must reach the replication group."
  }
}

run "an_unknown_strategy_is_refused" {
  command = plan

  variables {
    auth_token_update_strategy = "DELETE"
  }

  expect_failures = [var.auth_token_update_strategy]
}

run "a_negative_generation_is_refused" {
  command = plan

  variables {
    auth_token_generation = -1
  }

  expect_failures = [var.auth_token_generation]
}

run "a_fractional_generation_is_refused" {
  command = plan

  variables {
    auth_token_generation = 1.5
  }

  expect_failures = [var.auth_token_generation]
}
