# route53-zone

A hosted zone and the ACM DNS-validation records, and nothing else, so `bin/new-site` can create it and delegate nameservers before any certificate or CloudFront distribution exists.

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| aws | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.acm_validation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_zone.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_zone) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain\_name | Apex domain for the hosted zone | `string` | n/a | yes |
| acm\_domain\_validation\_options | domain\_validation\_options output from the acm-cert module | <pre>set(object({<br/>    domain_name           = string<br/>    resource_record_name  = string<br/>    resource_record_type  = string<br/>    resource_record_value = string<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| name\_servers | Route53 nameservers — set these as the domain's custom NS at the registrar |
| validation\_record\_fqdns | FQDNs of the ACM validation records, for aws\_acm\_certificate\_validation |
| zone\_id | Route53 hosted zone ID |
<!-- END_TF_DOCS -->
