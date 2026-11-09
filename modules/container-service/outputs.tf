output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = local.cluster_name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}

output "service_fqdn" {
  value = local.service_fqdn
}

output "service_url" {
  value = "https://${local.service_fqdn}"
}

output "alb_dns_name" {
  description = "The ALB serving this app — dedicated or shared"
  value       = local.alb_dns_name
}

output "log_group" {
  value = aws_cloudwatch_log_group.app.name
}

output "task_role_arn" {
  description = "IAM role assumed by the app container (attach extra policies here)"
  value       = aws_iam_role.task.arn
}

output "waf_web_acl_arn" {
  description = "The web ACL attached to this app's ALB: created (create_waf), supplied (waf_web_acl_arn), or empty"
  value       = local.waf_web_acl_arn
}
