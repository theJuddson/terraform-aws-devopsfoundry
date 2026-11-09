output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for the ALB)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for ECS, RDS, Redis)"
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "api_security_group_id" {
  value = aws_security_group.api.id
}

output "rds_security_group_id" {
  description = "RDS SG id, or null when database disabled"
  value       = one(aws_security_group.rds[*].id)
}

output "redis_security_group_id" {
  description = "Redis SG id, or null when cache disabled"
  value       = one(aws_security_group.redis[*].id)
}

output "flow_log_group_name" {
  description = "CloudWatch log group holding the VPC flow logs (null when enable_flow_logs = false)"
  value       = var.enable_flow_logs ? aws_cloudwatch_log_group.flow_logs[0].name : null
}
