# namecheap-ns

Points a Namecheap domain's custom nameservers at a Route53 hosted zone. It sets only nameservers, so every record then lives in Route53.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| namecheap | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [namecheap_domain_records.ns](https://registry.terraform.io/providers/namecheap/namecheap/latest/docs/resources/domain_records) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain\_name | Apex domain registered at Namecheap | `string` | n/a | yes |
| nameservers | Route53 nameservers to delegate to (route53-zone name\_servers output) | `list(string)` | n/a | yes |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
