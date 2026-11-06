output "certificate_arn" {
  description = "ARN of the (as-yet-unvalidated) ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "domain_validation_options" {
  description = "DNS validation records to create in the Route53 zone"
  value       = aws_acm_certificate.main.domain_validation_options
}
