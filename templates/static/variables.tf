variable "domain_name" {
  description = "Apex domain"
  type        = string
}

variable "site_name" {
  description = "Resource-name slug (e.g. example-com)"
  type        = string
}

variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
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
