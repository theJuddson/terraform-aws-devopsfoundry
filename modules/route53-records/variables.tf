variable "domain_name" {
  description = "Apex domain"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID (from route53-zone module)"
  type        = string
}

variable "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (from static-site module)"
  type        = string
}

variable "cloudfront_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID for alias records"
  type        = string
}

variable "enable_google_email" {
  description = "Create Google Workspace MX + DKIM records"
  type        = bool
  default     = false
}

variable "google_dkim_key" {
  description = "Google Workspace DKIM public key (required if enable_google_email)"
  type        = string
  default     = ""
}
