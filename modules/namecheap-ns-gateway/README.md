# namecheap-ns-gateway

Points a Namecheap domain's custom nameservers at a Route53 hosted zone through the `namecheap-gateway` Lambda, so the
call leaves from the gateway's fixed, allowlisted IP. The machine running Terraform needs no Namecheap credentials, only
`lambda:InvokeFunction` on the gateway. Destroying it resets the domain to Namecheap's default DNS.

Same inputs as `namecheap-ns`, plus `gateway_function_name`. It is a separate module, not a mode of `namecheap-ns`, so
existing roots keep their state addresses.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.60 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.60 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lambda_invocation.ns](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain\_name | Apex domain registered at Namecheap | `string` | n/a | yes |
| nameservers | Route53 nameservers to delegate to (route53-zone name\_servers output) | `list(string)` | n/a | yes |
| gateway\_function\_name | The namecheap-gateway function (its `function_name` output). | `string` | `"devopsfoundry-namecheap"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| result | What the gateway reported: the domain and the nameservers it set. |
<!-- END_TF_DOCS -->
