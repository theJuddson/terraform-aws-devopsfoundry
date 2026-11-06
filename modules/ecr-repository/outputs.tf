output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Repository URL, `<account>.dkr.ecr.<region>.amazonaws.com/<name>`."
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "Registry (account) ID."
  value       = aws_ecr_repository.this.registry_id
}
