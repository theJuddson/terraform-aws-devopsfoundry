variable "domain_name" {
  description = "Apex domain registered at Namecheap"
  type        = string
}

variable "nameservers" {
  description = "Route53 nameservers to delegate to (route53-zone name_servers output)"
  type        = list(string)
}

variable "gateway_function_name" {
  description = "The namecheap-gateway function (its `function_name` output)."
  type        = string
  default     = "devopsfoundry-namecheap"
}
