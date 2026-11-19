output "function_name" {
  description = "The gateway function. Set `NAMECHEAP_GATEWAY` to it in `.env` for `bin/namecheap`, and pass it to `namecheap-ns` as `gateway_function_name`."
  value       = aws_lambda_function.fn.function_name
}

output "function_arn" {
  description = "ARN of the gateway function, for an IAM policy that lets someone invoke it."
  value       = aws_lambda_function.fn.arn
}

output "client_ip" {
  description = "The address to allowlist at Namecheap: Profile, Tools, Namecheap API Access, Whitelisted IPs."
  value       = var.client_ip
}

output "security_group_id" {
  description = "The function's security group (HTTPS out only)."
  value       = aws_security_group.fn.id
}
