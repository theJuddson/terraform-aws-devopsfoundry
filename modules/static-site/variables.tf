variable "site_name" {
  description = "Short slug used in resource names (e.g. example-com)"
  type        = string
}

variable "domain_name" {
  description = "Apex domain (also the www. alias source)"
  type        = string
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
