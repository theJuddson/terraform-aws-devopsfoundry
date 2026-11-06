variable "domain_name" {
  description = "Apex domain registered at Namecheap"
  type        = string
}

variable "nameservers" {
  description = "Route53 nameservers to delegate to (route53-zone name_servers output)"
  type        = list(string)
}
