output "file_system_id" {
  description = "File system ID."
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "File system ARN."
  value       = aws_efs_file_system.this.arn
}

output "dns_name" {
  description = "Regional DNS name for mounting."
  value       = aws_efs_file_system.this.dns_name
}

output "security_group_id" {
  description = "Security group on the mount targets."
  value       = aws_security_group.this.id
}

output "mount_target_ids" {
  description = "Subnet ID -> mount target ID."
  value       = { for k, v in aws_efs_mount_target.this : k => v.id }
}

output "runtime_tag" {
  description = "The tag run-time access points must carry, as { key, value }."
  value       = { key = var.runtime_tag_key, value = local.tag_value }
}

output "runtime_policy_json" {
  description = "IAM policy document for an app role that creates access points (and optionally file systems) at run time."
  value       = data.aws_iam_policy_document.runtime.json
}
