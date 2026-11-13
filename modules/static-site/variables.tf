variable "site_name" {
  description = "Short slug used in resource names (e.g. example-com)"
  type        = string
}

variable "domain_name" {
  description = "Domain the site serves (also the www. alias source when include_www)"
  type        = string
}

variable "include_www" {
  description = "Also serve www.<domain_name>. False for a site in a subdomain of an existing zone."
  type        = bool
  default     = true
}

variable "bucket_name" {
  description = "Globally-unique S3 bucket name (caller appends account id for uniqueness)"
  type        = string
}

variable "certificate_arn" {
  description = "Validated ACM cert ARN in us-east-1 (use the acm_certificate_validation output)"
  type        = string
}

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}
