output "ecr_repository_url" {
  value = module.container_service.ecr_repository_url
}

output "ecs_cluster_name" {
  value = module.container_service.ecs_cluster_name
}

output "ecs_service_name" {
  value = module.container_service.ecs_service_name
}

output "service_url" {
  value = module.container_service.service_url
}

output "health_check_path" {
  description = "Path deploy-app curls after rollout"
  value       = var.health_check_path
}

output "name_servers" {
  description = "Route53 nameservers delegated at Namecheap"
  value       = local.use_existing_zone ? [] : module.route53_zone[0].name_servers
}

output "log_group" {
  value = module.container_service.log_group
}

# ── Wiring for companion stacks (e.g. a second service using this app's database) ──
output "db_address" {
  description = "RDS endpoint address (null without enable_database)"
  value       = var.enable_database ? module.database[0].address : null
}

output "db_port" {
  value = var.enable_database ? module.database[0].port : null
}

output "db_name" {
  value = var.enable_database ? module.database[0].db_name : null
}

output "db_master_secret_arn" {
  description = "Secrets Manager ARN of the RDS-managed master credential (rotates every 7 days by default)"
  value       = var.enable_database ? module.database[0].master_user_secret_arn : null
}

output "rds_security_group_id" {
  description = "Security group on the RDS instance; add ingress rules here for companion services"
  value       = var.enable_database ? local.net.rds_security_group_id : null
}

output "task_security_group_id" {
  description = "Security group attached to this app's ECS tasks"
  value       = local.net.api_security_group_id
}

output "private_subnet_ids" {
  value = local.net.private_subnet_ids
}

output "waf_web_acl_arn" {
  description = "Web ACL attached to the ALB this stack owns (empty when none, or in shared-platform mode)"
  value       = module.container_service.waf_web_acl_arn
}
