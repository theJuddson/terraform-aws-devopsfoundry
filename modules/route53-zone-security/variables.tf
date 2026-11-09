variable "zone_id" {
  description = "ID of the Route53 public hosted zone to sign or log"
  type        = string
}

variable "zone_name" {
  description = "The zone's domain name (e.g. example.com), used to name the key, alias and log group"
  type        = string
}

variable "enable_dnssec" {
  description = "Sign the zone with DNSSEC. After apply, publish the ds_record output at the registrar; see docs/dnssec.md, including how to turn it off safely."
  type        = bool
  default     = false
}

variable "enable_query_logging" {
  description = "Log the DNS queries Route53 answers for the zone to a CloudWatch log group (billed per GB)."
  type        = bool
  default     = false
}

variable "query_log_retention_days" {
  description = "Days to keep query logs. Must be a retention period CloudWatch Logs accepts."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.query_log_retention_days)
    error_message = "query_log_retention_days must be a retention period CloudWatch Logs accepts, e.g. 7, 14, 30, 90 or 365."
  }
}

variable "kms_key_arn" {
  description = "Customer managed KMS key (in us-east-1) for the query log group. null (default) = CloudWatch's default encryption. The key policy must allow logs.us-east-1.amazonaws.com."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:us-east-1:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be the ARN of a KMS key in us-east-1, not an alias."
  }
}

variable "tags" {
  description = "Tags for the KMS key and log group"
  type        = map(string)
  default     = {}
}
