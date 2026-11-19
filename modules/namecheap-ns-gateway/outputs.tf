output "result" {
  description = "What the gateway reported: the domain and the nameservers it set."
  value       = jsondecode(aws_lambda_invocation.ns.result)
}
