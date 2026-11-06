# static-site

A private S3 bucket reachable only through CloudFront Origin Access Control, serving the apex and www with the ACM certificate.

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
| domain\_name | Apex domain (also the www. alias source) | `string` | n/a | yes |
| site\_name | Short slug used in resource names (e.g. example-com) | `string` | n/a | yes |
| price\_class | CloudFront price class | `string` | `"PriceClass_100"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_name | n/a |
| distribution\_domain | n/a |
| distribution\_hosted\_zone\_id | n/a |
| distribution\_id | n/a |
<!-- END_TF_DOCS -->
