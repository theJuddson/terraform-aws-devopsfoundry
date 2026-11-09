output "ecr_repository_url" {
  value = module.app.ecr_repository_url
}
output "ecs_cluster_name" {
  value = module.app.ecs_cluster_name
}
output "ecs_service_name" {
  value = module.app.ecs_service_name
}
output "service_url" {
  value = module.app.service_url
}
output "health_check_path" {
  value = module.app.health_check_path
}
output "name_servers" {
  value = module.app.name_servers
}
output "log_group" {
  value = module.app.log_group
}

output "db_address" { value = module.app.db_address }
output "db_port" { value = module.app.db_port }
output "db_name" { value = module.app.db_name }
output "db_master_secret_arn" { value = module.app.db_master_secret_arn }
output "rds_security_group_id" { value = module.app.rds_security_group_id }
output "task_security_group_id" { value = module.app.task_security_group_id }
output "private_subnet_ids" { value = module.app.private_subnet_ids }
output "waf_web_acl_arn" { value = module.app.waf_web_acl_arn }

output "dnssec_ds_record_fields" {
  description = "With enable_dnssec: the DS record to add at the registrar (Namecheap: Advanced DNS > DNSSEC)"
  value       = module.app.dnssec_ds_record_fields
}
