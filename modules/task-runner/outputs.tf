output "cluster_arn" {
  description = "Cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Cluster name."
  value       = aws_ecs_cluster.this.name
}

output "task_definition_families" {
  description = "Short name -> task definition family. RunTask with the family runs its latest revision."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.family }
}

output "task_definition_arns" {
  description = "Short name -> ARN of the revision this apply registered."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "container_name" {
  description = "Container name to use in RunTask overrides."
  value       = var.container_name
}

output "task_role_arn" {
  description = "Role the code inside the task runs as."
  value       = aws_iam_role.task.arn
}

output "task_role_name" {
  description = "Name of the task role, for attaching more policies."
  value       = aws_iam_role.task.name
}

output "execution_role_arn" {
  description = "Role ECS uses to pull the image, read secrets and write logs."
  value       = aws_iam_role.execution.arn
}

output "security_group_id" {
  description = "Egress-only security group for the tasks."
  value       = aws_security_group.this.id
}

output "log_group_name" {
  description = "Log group the tasks write to."
  value       = aws_cloudwatch_log_group.this.name
}

output "run_task_network_configuration" {
  description = "The `networkConfiguration` to pass to RunTask."
  value = {
    awsvpcConfiguration = {
      subnets        = var.subnet_ids
      securityGroups = [aws_security_group.this.id]
      assignPublicIp = var.assign_public_ip ? "ENABLED" : "DISABLED"
    }
  }
}

output "controller_policy_json" {
  description = "IAM policy document for the controller: RunTask, StopTask, DescribeTasks and TagResource in this cluster, and PassRole on the task and execution roles."
  value       = data.aws_iam_policy_document.controller.json
}
