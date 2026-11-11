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

output "dnssec_ds_record" {
  description = "DS record to publish at the registrar when enable_dnssec = true (null otherwise)"
  value       = one(module.route53_zone_security[*].ds_record)
}

output "dnssec_ds_record_fields" {
  description = "The DS record's parts for registrars that ask for them separately, such as Namecheap (null when DNSSEC is off)"
  value       = one(module.route53_zone_security[*].ds_record_fields)
}

output "dns_query_log_group_name" {
  description = "CloudWatch log group (us-east-1) with the zone's DNS query logs (null when off)"
  value       = one(module.route53_zone_security[*].query_log_group_name)
}

output "cpu_architecture" {
  description = "CPU architecture the app's tasks run on; deploy-app builds the image for it"
  value       = module.container_service.cpu_architecture
}

output "platform_descriptor_name" {
  description = "SSM parameter publishing this stack as a shared platform (platform_name), or null"
  value       = one(aws_ssm_parameter.platform_descriptor[*].name)
}

output "dmarc_report_authorization" {
  description = "With enable_email and dmarc_rua_email on another domain: the TXT record that domain must publish to receive reports, and whether it was created. Null otherwise."
  value       = one(module.email[*].dmarc_report_authorization)
}
