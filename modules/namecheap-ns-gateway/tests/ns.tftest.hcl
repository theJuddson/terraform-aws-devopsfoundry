# The gateway is asked to set exactly the Route53 nameservers, for the given
# domain, and to reset the domain when the resource is destroyed. Plans only,
# against a mocked AWS provider.

mock_provider "aws" {}

variables {
  domain_name = "example.com"
  nameservers = ["ns-4.awsdns-04.net", "ns-1.awsdns-01.org", "ns-3.awsdns-03.com", "ns-2.awsdns-02.co.uk"]
}

run "asks_the_gateway_to_set_the_nameservers" {
  command = plan

  assert {
    condition     = aws_lambda_invocation.ns.function_name == "devopsfoundry-namecheap"
    error_message = "The default gateway function must be called."
  }
  assert {
    condition     = jsondecode(aws_lambda_invocation.ns.input).action == "set_nameservers"
    error_message = "The input must ask for the nameservers to be set."
  }
  assert {
    condition     = jsondecode(aws_lambda_invocation.ns.input).domain == "example.com"
    error_message = "The input must name the given domain."
  }
  assert {
    condition     = toset(jsondecode(aws_lambda_invocation.ns.input).nameservers) == toset(var.nameservers)
    error_message = "The gateway must be sent exactly the Route53 nameservers."
  }
  assert {
    # Sorted, so Route53 returning them in another order plans no change.
    condition     = jsonencode(jsondecode(aws_lambda_invocation.ns.input).nameservers) == jsonencode(sort(var.nameservers))
    error_message = "The nameservers must be sent sorted."
  }
  assert {
    # CRUD sends the destroy to the function too, which resets the domain.
    condition     = aws_lambda_invocation.ns.lifecycle_scope == "CRUD"
    error_message = "Destroying the delegation must reach the gateway, so the domain is reset."
  }
}

run "uses_the_given_function" {
  command = plan

  variables {
    gateway_function_name = "other-namecheap"
  }

  assert {
    condition     = aws_lambda_invocation.ns.function_name == "other-namecheap"
    error_message = "gateway_function_name must be the function called."
  }
}
