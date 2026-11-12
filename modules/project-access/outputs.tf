output "role_arn" {
  value = aws_iam_role.this.arn
}

output "role_name" {
  value = aws_iam_role.this.name
}

output "user_name" {
  value = var.user_name == null ? null : aws_iam_user.this[0].name
}

output "switch_role_url" {
  description = "Console link that switches a signed-in user into the role"
  value       = "https://signin.aws.amazon.com/switchrole?account=${data.aws_caller_identity.current.account_id}&roleName=${urlencode(var.name)}&displayName=${urlencode(var.name)}"
}

output "policy_json" {
  description = "The role's project policy, for review"
  value       = aws_iam_role_policy.project.policy
}
