variable "domain_name" {
  description = "Apex domain for the hosted zone"
  type        = string
}

variable "acm_domain_validation_options" {
  description = "domain_validation_options output from the acm-cert module"
  type = set(object({
    domain_name           = string
    resource_record_name  = string
    resource_record_type  = string
    resource_record_value = string
  }))
  default = []
}
