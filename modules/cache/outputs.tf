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
}
