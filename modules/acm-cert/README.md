# acm-cert

ACM certificate for the apex domain and its wildcard, validated by DNS. It must be created in us-east-1 for CloudFront, so the caller passes an aliased us-east-1 provider.

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
| [aws_acm_certificate.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/acm_certificate) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| domain\_name | Apex domain (e.g. example.com). The cert covers it plus *.example.com. | `string` | n/a | yes |
| include\_wildcard | Also cover *.<domain\_name>. False issues a cert for exactly domain\_name (existing-zone mode). | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| certificate\_arn | ARN of the (as-yet-unvalidated) ACM certificate |
| domain\_validation\_options | DNS validation records to create in the Route53 zone |
<!-- END_TF_DOCS -->
