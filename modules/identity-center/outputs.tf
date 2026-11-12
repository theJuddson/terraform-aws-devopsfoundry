output "instance_arn" {
  value = local.instance_arn == "" ? null : local.instance_arn
}

output "identity_store_id" {
  value = local.identity_store_id == "" ? null : local.identity_store_id
}

output "user_ids" {
  description = "Identity store user IDs by user key"
  value       = { for k, u in aws_identitystore_user.this : k => u.user_id }
}

output "permission_set_arns" {
  value = { for k, p in aws_ssoadmin_permission_set.this : k => p.arn }
}

output "assignments" {
  description = "Each assignment as permission set | account | principal"
  value       = keys(local.assignments)
}
