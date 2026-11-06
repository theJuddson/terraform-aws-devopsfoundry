output "smtp_host" {
  value = local.smtp_host
}

output "smtp_secret_arn" {
  description = "Secrets Manager ARN holding SMTP creds (JSON: username/password/host/port)"
  value       = aws_secretsmanager_secret.smtp.arn
}

output "notifications_topic_arn" {
  description = "SNS topic ARN for SES bounce/complaint (null when disabled)"
  value       = one(aws_sns_topic.ses_notifications[*].arn)
}
