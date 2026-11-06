output "key_arn" {
  description = "Key ARN."
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "Key ID."
  value       = aws_kms_key.this.key_id
}

output "alias_arn" {
  description = "Alias ARN."
  value       = aws_kms_alias.this.arn
}

output "alias_name" {
  description = "Alias name, `alias/<alias>`."
  value       = aws_kms_alias.this.name
}

output "runtime_policy_json" {
  description = "IAM policy document for an app role that creates and uses its own tagged keys. Null when `runtime_tag_value` is null."
  value       = local.runtime_on ? data.aws_iam_policy_document.runtime[0].json : null
}
