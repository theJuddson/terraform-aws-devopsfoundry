# static-site

A private S3 bucket reachable only through CloudFront Origin Access Control, serving the apex and www with the ACM certificate.

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
| [aws_cloudfront_distribution.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_s3_bucket.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_policy.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.site](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_cloudfront_cache_policy.caching_optimized](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/cloudfront_cache_policy) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Globally-unique S3 bucket name (caller appends account id for uniqueness) | `string` | n/a | yes |
| certificate\_arn | Validated ACM cert ARN in us-east-1 (use the acm\_certificate\_validation output) | `string` | n/a | yes |
| domain\_name | Domain the site serves (also the www. alias source when include\_www) | `string` | n/a | yes |
| site\_name | Short slug used in resource names (e.g. example-com) | `string` | n/a | yes |
| allowed\_countries | Serve only viewers in these countries (ISO 3166 alpha-2 codes, e.g. ["US"]);<br/>CloudFront answers everyone else with 403. Empty, the default, serves every<br/>country. Free. CloudFront places viewers by IP, so people on a VPN or<br/>travelling are refused too. | `list(string)` | `[]` | no |
| include\_www | Also serve www.<domain\_name>. False for a site in a subdomain of an existing zone. | `bool` | `true` | no |
| price\_class | CloudFront price class | `string` | `"PriceClass_100"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | n/a |
| distribution\_domain | n/a |
| distribution\_hosted\_zone\_id | n/a |
| distribution\_id | n/a |
<!-- END_TF_DOCS -->
