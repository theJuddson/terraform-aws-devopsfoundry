output "primary_endpoint" {
  description = "Redis primary endpoint hostname"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "port" {
  value = aws_elasticache_replication_group.main.port
}

output "auth_token" {
  description = "Generated Redis AUTH token"
  value       = random_password.auth_token.result
  sensitive   = true
  # Whoever stores the token (full-stack's secret) writes a new one only after
  # Redis accepts it, so a task started mid-apply never reads a token Redis refuses.
  depends_on = [aws_elasticache_replication_group.main]
}

output "auth_token_rotation" {
  description = "Where token rotation stands: the token generation and the update strategy last applied (bin/rotate-secret)."
  value = {
    generation = var.auth_token_generation
    strategy   = aws_elasticache_replication_group.main.auth_token_update_strategy
  }
}
