output "instance_id" {
  description = "Instance ID."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IPv4 address."
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public IPv4 address, if any."
  value       = aws_instance.this.public_ip
}

output "security_group_id" {
  description = "The instance's security group (no inbound rules)."
  value       = aws_security_group.this.id
}

output "role_name" {
  description = "Instance role name, for attaching more policies."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "Instance role ARN."
  value       = aws_iam_role.this.arn
}

output "data_volume_id" {
  description = "ID of the data volume that outlives the instance."
  value       = aws_ebs_volume.data.id
}

output "ssm_session_command" {
  description = "Command that opens a shell on the instance."
  value       = "aws ssm start-session --target ${aws_instance.this.id}"
}
