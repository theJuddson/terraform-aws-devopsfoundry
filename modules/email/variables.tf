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
  validation {
    condition     = can(regex("^[^@\\s;,]+@[^@\\s;,]+\\.[^@\\s;,]+$", var.dmarc_rua_email))
    error_message = "dmarc_rua_email must be an email address, e.g. dmarc@example.com."
  }
}

variable "dmarc_report_zone_id" {
  description = "Route53 zone of dmarc_rua_email's domain, when that is another domain: creates the <sender_domain>._report._dmarc.<report domain> TXT record receivers need before they send reports there. Empty = create nothing; the dmarc_report_authorization output gives the record to add by hand."
  type        = string
  default     = ""
}

variable "dmarc_policy" {
  description = "DMARC policy applied to the domain + subdomains: none | quarantine | reject"
  type        = string
  default     = "none"
  validation {
    # DMARC tag values are case-insensitive, so "Reject" is accepted as written.
    condition     = contains(["none", "quarantine", "reject"], lower(var.dmarc_policy))
    error_message = "dmarc_policy must be none, quarantine or reject."
  }
}

variable "mail_from_subdomain" {
  description = "Label for a custom MAIL FROM subdomain (e.g. 'mail' -> mail.<sender_domain>), giving SPF alignment. Empty = SES default (amazonses.com), DKIM-only DMARC alignment."
  type        = string
  default     = ""
  validation {
    condition     = var.mail_from_subdomain == "" || can(regex("^(?i)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$", var.mail_from_subdomain))
    error_message = "mail_from_subdomain must be empty or DNS labels such as \"mail\": letters, digits and hyphens, with dots between labels."
  }
}

variable "enable_notifications" {
  description = "Create an SNS topic wired to SES Bounce/Complaint (subscription left to the caller)"
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for the SMTP credentials secret. null (default) = the AWS-managed key. Whatever reads the secret also needs kms:Decrypt on it."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "smtp_active_key" {
  description = "Key slot (a or b) whose SMTP credentials are in the secret. Set by bin/rotate-secret."
  type        = string
  default     = "a"

  validation {
    condition     = contains(["a", "b"], var.smtp_active_key)
    error_message = "smtp_active_key must be \"a\" or \"b\"."
  }
}

variable "smtp_standby_key" {
  description = "The other key slot: none (no second key yet), active (the previous key still works while tasks restart) or inactive (retired, replaced at the next rotation). Set by bin/rotate-secret."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "active", "inactive"], var.smtp_standby_key)
    error_message = "smtp_standby_key must be none, active or inactive."
  }
}
