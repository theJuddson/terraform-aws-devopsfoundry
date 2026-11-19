# Points a Namecheap domain's custom nameservers at a Route53 hosted zone, like
# namecheap-ns, but through the namecheap-gateway Lambda instead of the Namecheap
# provider. The call leaves from the gateway's fixed IP, so the machine running
# Terraform needs no Namecheap credentials and no allowlisted address: only
# permission to invoke the function.
#
# Creating or changing this resource sets the nameservers (domains.dns.setCustom).
# Destroying it resets the domain to Namecheap's default DNS (domains.dns.setDefault),
# as destroying namecheap-ns does. Only nameservers are set: every record lives in
# Route53.

resource "aws_lambda_invocation" "ns" {
  function_name   = var.gateway_function_name
  lifecycle_scope = "CRUD"

  input = jsonencode({
    action      = "set_nameservers"
    domain      = var.domain_name
    nameservers = sort(var.nameservers)
  })
}
