# Output names mirror modules/networking exactly, so full-stack can select
# between the two with a single local and pass the result on unchanged.

output "vpc_id" {
  value = data.aws_vpc.platform.id
}

output "public_subnet_ids" {
  description = "Shared public subnet IDs (the platform's ALB already lives here)"
  value       = data.aws_subnets.public.ids
}

output "private_subnet_ids" {
  description = "Shared private subnet IDs (for this app's tasks, RDS, Redis)"
  value       = data.aws_subnets.private.ids
}

output "alb_security_group_id" {
  description = "The platform's ALB security group (read-only)"
  value       = data.aws_security_group.platform_alb.id
}

output "api_security_group_id" {
  description = "This app's own task security group"
  value       = aws_security_group.api.id
}

output "rds_security_group_id" {
  description = "This app's own RDS SG id, or null when database disabled"
  value       = one(aws_security_group.rds[*].id)
}

output "redis_security_group_id" {
  description = "This app's own Redis SG id, or null when cache disabled"
  value       = one(aws_security_group.redis[*].id)
}

# ── Shared ALB + cluster, for container-service ───────

output "alb_arn" {
  value = data.aws_lb.platform.arn
}

output "alb_dns_name" {
  value = data.aws_lb.platform.dns_name
}

output "alb_zone_id" {
  value = data.aws_lb.platform.zone_id
}

output "https_listener_arn" {
  value = data.aws_lb_listener.https.arn
}

output "ecs_cluster_arn" {
  value = data.aws_ecs_cluster.platform.arn
}

output "ecs_cluster_name" {
  value = data.aws_ecs_cluster.platform.cluster_name
}

output "private_subnets_have_egress" {
  description = "Whether every private subnet has a default route (a NAT gateway or other egress). False on a platform built with enable_nat_gateway = false."
  value       = local.private_subnets_have_egress
}

output "platform_source" {
  description = "How the platform was found: \"descriptor\" (its SSM parameter) or \"naming\" (naming conventions)"
  value       = local.d != null ? "descriptor" : "naming"
}
