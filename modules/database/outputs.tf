output "address" {
  description = "RDS hostname"
  value       = aws_db_instance.main.address
}

output "port" {
  value = aws_db_instance.main.port
}

output "db_name" {
  value = aws_db_instance.main.db_name
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed master password secret (JSON: username/password)"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}
