output "bucket_id" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the bucket."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "prefix_policy_json" {
  description = "IAM policy document granting `policy_prefix` (and the KMS key, if one was given). Attach it to an app role."
  value       = data.aws_iam_policy_document.prefix.json
}
