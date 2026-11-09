output "ds_record" {
  description = "The DS record to publish at the registrar, as one line (null when DNSSEC is off)"
  value       = one(aws_route53_key_signing_key.this[*].ds_record)
}

output "ds_record_fields" {
  description = "The DS record's parts, for registrars that ask for them separately (Namecheap: key tag, algorithm, digest type, digest). null when DNSSEC is off."
  value = var.enable_dnssec ? {
    key_tag     = aws_route53_key_signing_key.this[0].key_tag
    algorithm   = aws_route53_key_signing_key.this[0].signing_algorithm_type
    digest_type = aws_route53_key_signing_key.this[0].digest_algorithm_type
    digest      = aws_route53_key_signing_key.this[0].digest_value
  } : null
}

output "dnssec_kms_key_arn" {
  description = "ARN of the KMS key holding the key-signing key (null when DNSSEC is off)"
  value       = one(aws_kms_key.dnssec[*].arn)
}

output "query_log_group_name" {
  description = "CloudWatch log group receiving the zone's DNS query logs (null when query logging is off)"
  value       = one(aws_cloudwatch_log_group.query_logs[*].name)
}
