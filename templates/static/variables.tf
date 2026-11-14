variable "domain_name" {
  description = "Domain the site serves: the apex, or with existing_zone_id a subdomain of that zone"
  type        = string
}

variable "existing_zone_id" {
  description = "Route53 zone to add the site's records to instead of creating one (bin/new-site --existing-zone). Empty: create a zone and delegate it at Namecheap."
  type        = string
  default     = ""
}

variable "include_www" {
  description = "Also serve www.<domain_name>. False for a site in a subdomain of an existing zone."
  type        = bool
  default     = true
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

variable "allowed_countries" {
  description = "Serve only viewers in these countries (ISO 3166 alpha-2, e.g. [\"US\"]); everyone else gets 403. Empty serves every country."
  type        = list(string)
  default     = []
}
