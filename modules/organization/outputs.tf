output "organization_id" {
  value = aws_organizations_organization.this.id
}

output "management_account_id" {
  value = aws_organizations_organization.this.master_account_id
}

output "root_id" {
  value = aws_organizations_organization.this.roots[0].id
}

output "account_ids" {
  description = "Member account IDs by account name"
  value       = { for k, a in aws_organizations_account.this : k => a.id }
}

output "member_admin_role_arns" {
  description = "The admin role in each member account, by account name: what a provider's assume_role uses to build inside it"
  value       = { for k, a in aws_organizations_account.this : k => "arn:${data.aws_partition.current.partition}:iam::${a.id}:role/${var.member_admin_role_name}" }
}

output "organizational_unit_ids" {
  value = { for k, ou in aws_organizations_organizational_unit.this : k => ou.id }
}
