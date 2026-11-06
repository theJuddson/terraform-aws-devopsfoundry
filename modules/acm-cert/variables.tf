variable "domain_name" {
  description = "Apex domain (e.g. example.com). The cert covers it plus *.example.com."
  type        = string
}

variable "include_wildcard" {
  description = "Also cover *.<domain_name>. False issues a cert for exactly domain_name (existing-zone mode)."
  type        = bool
  default     = true
}
