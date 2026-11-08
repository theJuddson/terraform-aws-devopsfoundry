# Points the domain's custom nameservers at the Route53 hosted zone.
# This is the step that was previously done by hand in the Namecheap UI.
#
# When `nameservers` is set, Namecheap stops serving DNS for the domain and
# delegates to these NS — so all records live in Route53. We deliberately set
# ONLY nameservers here (no `record {}` blocks), which is mutually exclusive
# with managing host records on Namecheap's own DNS.
#
# Provider creds come from the env (NAMECHEAP_API_USER / API_KEY / USER_NAME /
# CLIENT_IP / USE_SANDBOX); the provider is configured in the site root.
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    namecheap = {
      source  = "namecheap/namecheap"
      version = ">= 2.1.0"
    }
  }
}

resource "namecheap_domain_records" "ns" {
  domain      = var.domain_name
  mode        = "OVERWRITE"
  nameservers = var.nameservers
}
