variable "bucket_name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of a customer managed KMS key for default encryption. Null uses the AWS-managed aws/s3 key."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow `terraform destroy` to delete the bucket while it still holds objects. Leave false for data you need."
  type        = bool
  default     = false
}

variable "noncurrent_version_expiration_days" {
  description = "Days after an object version stops being current before it is deleted."
  type        = number
  default     = 30
}

variable "noncurrent_versions_to_keep" {
  description = "Keep this many newest noncurrent versions regardless of age. Null keeps none beyond the age rule."
  type        = number
  default     = null
}

variable "abort_incomplete_multipart_days" {
  description = "Days before an unfinished multipart upload is aborted and its parts deleted."
  type        = number
  default     = 7
}

variable "prefix_expiration_days" {
  description = "Prefix -> days. Current objects under each prefix expire after that many days (for example { \"tmp/\" = 7 })."
  type        = map(number)
  default     = {}
}

variable "access_log_bucket" {
  description = "Bucket that receives server access logs. Null turns access logging off."
  type        = string
  default     = null
}

variable "extra_bucket_policy_documents" {
  description = "Further bucket policy JSON documents merged with the TLS-only statement."
  type        = list(string)
  default     = []
}

variable "policy_prefix" {
  description = "Key prefix granted by the `prefix_policy_json` output, without leading or trailing slash. Empty grants the whole bucket."
  type        = string
  default     = ""
}

variable "policy_read_only" {
  description = "Make `prefix_policy_json` read-only (no put or delete)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the bucket."
  type        = map(string)
  default     = {}
}
