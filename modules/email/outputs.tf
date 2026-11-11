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

output "dmarc_report_authorization" {
  description = "When dmarc_rua_email is on another domain: the TXT record that domain must publish before receivers send it reports, and whether this module created it (dmarc_report_zone_id). Null when no record is needed."
  value = local.rua_external ? {
    name    = local.dmarc_report_auth_name
    type    = "TXT"
    value   = "v=DMARC1"
    created = var.dmarc_report_zone_id != ""
  } : null
}

output "smtp_keys" {
  description = "Status of each SMTP key slot (Active or Inactive), and which slot the secret holds (bin/rotate-secret)."
  value = {
    active = var.smtp_active_key
    status = { for slot, key in aws_iam_access_key.ses_smtp : slot => key.status }
  }
}
