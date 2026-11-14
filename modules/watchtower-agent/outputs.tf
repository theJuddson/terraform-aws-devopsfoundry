output "user_data" {
  description = "A cloud-init shell script that installs and enrolls the agent. Use it as a host's user data, or as one part of a multi-part cloud-init."
  value       = local.user_data
}

output "policy_json" {
  description = "IAM policy the hosts' role needs: the group key parameter and, for an s3:// release, that object. A parameter under a customer managed KMS key also needs kms:Decrypt on that key."
  value       = data.aws_iam_policy_document.agent.json
}
