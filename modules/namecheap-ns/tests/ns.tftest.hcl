# The domain's nameservers are pointed at Route53, and nothing else is sent to
# Namecheap. Plans only, against a mocked Namecheap provider.

mock_provider "namecheap" {}

variables {
  domain_name = "example.com"
  nameservers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"]
}

run "delegates_to_the_given_nameservers" {
  command = plan

  assert {
    condition     = namecheap_domain_records.ns.domain == "example.com"
    error_message = "The records must be for the given domain."
  }
  assert {
    condition     = toset(namecheap_domain_records.ns.nameservers) == toset(var.nameservers)
    error_message = "Namecheap must be sent exactly the Route53 nameservers."
  }
  assert {
    condition     = namecheap_domain_records.ns.mode == "OVERWRITE"
    error_message = "The nameservers must replace the domain's current ones, not be merged with them."
  }
  assert {
    # Custom nameservers and Namecheap host records are mutually exclusive.
    condition     = length(coalesce(namecheap_domain_records.ns.record, [])) == 0
    error_message = "No host records may be sent: all records live in Route53."
  }
}
