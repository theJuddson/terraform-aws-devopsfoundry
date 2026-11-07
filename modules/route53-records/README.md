# route53-records

CloudFront alias records for the apex and www, and optional Google Workspace MX and DKIM records. Separate from `route53-zone` because the aliases need the CloudFront distribution, which cannot exist before the certificate is validated.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| aws | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | >= 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_route53_record.apex_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.apex_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.google_dkim](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.mx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.www_a](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.www_aaaa](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cloudfront\_domain\_name | CloudFront distribution domain name (from static-site module) | `string` | n/a | yes |
| cloudfront\_hosted\_zone\_id | CloudFront distribution hosted zone ID for alias records | `string` | n/a | yes |
| domain\_name | Apex domain | `string` | n/a | yes |
| zone\_id | Route53 hosted zone ID (from route53-zone module) | `string` | n/a | yes |
| enable\_google\_email | Create Google Workspace MX + DKIM records | `bool` | `false` | no |
| google\_dkim\_key | Google Workspace DKIM public key (required if enable\_google\_email) | `string` | `""` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->
