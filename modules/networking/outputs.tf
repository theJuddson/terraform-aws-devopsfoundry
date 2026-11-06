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
