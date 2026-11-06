variable "name" {
  description = "Resource-name prefix (app slug)"
  type        = string
}

variable "sender_domain" {
  description = "Domain to send mail from (SES identity)"
  type        = string
}

variable "sender_zone_id" {
  description = "Route53 hosted zone ID for sender_domain"
  type        = string
}

variable "aws_region" {
  description = "Region (the SES SMTP endpoint is region-scoped)"
  type        = string
  default     = "us-east-1"
}

variable "dmarc_rua_email" {
  description = "DMARC aggregate-report address (rua=mailto:)"
  type        = string
}

variable "dmarc_policy" {
  description = "DMARC policy applied to the domain + subdomains: none | quarantine | reject"
  type        = string
  default     = "none"
}

variable "mail_from_subdomain" {
  description = "Label for a custom MAIL FROM subdomain (e.g. 'mail' -> mail.<sender_domain>), giving SPF alignment. Empty = SES default (amazonses.com), DKIM-only DMARC alignment."
  type        = string
  default     = ""
}

variable "enable_notifications" {
  description = "Create an SNS topic wired to SES Bounce/Complaint (subscription left to the caller)"
  type        = bool
  default     = false
}
