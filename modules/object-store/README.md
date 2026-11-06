# object-store

A private S3 bucket: SSE-KMS by default (with a customer managed key if you pass one), versioning, all four public
access blocks, bucket-owner-enforced ownership, and a bucket policy that refuses requests not made over TLS.
Lifecycle rules delete noncurrent versions after `noncurrent_version_expiration_days`, abort stale multipart uploads,
and expire whole prefixes you list in `prefix_expiration_days`.

The `prefix_policy_json` output is an IAM policy that grants one prefix (list, get, and unless `policy_read_only`,
put and delete), plus decrypt and generate-data-key on the bucket's key. Attach it to the role that needs it.

```hcl
module "bucket" {
  source                 = "git::https://github.com/theJuddson/terraform-aws-devopsfoundry//modules/object-store?ref=v1.2.1"
  bucket_name            = "my-app-data-123456789012"
  kms_key_arn            = module.key.key_arn        # optional; see modules/kms-key
  policy_prefix          = "uploads"
  prefix_expiration_days = { "tmp/" = 7 }
}
```

Access logging is off unless you name a log bucket in `access_log_bucket`. `force_destroy` defaults to false, so
`terraform destroy` refuses a bucket that still holds objects.

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
| [aws_s3_bucket.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_logging.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_logging) | resource |
| [aws_s3_bucket_ownership_controls.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_iam_policy_document.bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.prefix](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| bucket\_name | Globally unique bucket name. | `string` | n/a | yes |
| abort\_incomplete\_multipart\_days | Days before an unfinished multipart upload is aborted and its parts deleted. | `number` | `7` | no |
| access\_log\_bucket | Bucket that receives server access logs. Null turns access logging off. | `string` | `null` | no |
| extra\_bucket\_policy\_documents | Further bucket policy JSON documents merged with the TLS-only statement. | `list(string)` | `[]` | no |
| force\_destroy | Allow `terraform destroy` to delete the bucket while it still holds objects. Leave false for data you need. | `bool` | `false` | no |
| kms\_key\_arn | ARN of a customer managed KMS key for default encryption. Null uses the AWS-managed aws/s3 key. | `string` | `null` | no |
| noncurrent\_version\_expiration\_days | Days after an object version stops being current before it is deleted. | `number` | `30` | no |
| noncurrent\_versions\_to\_keep | Keep this many newest noncurrent versions regardless of age. Null keeps none beyond the age rule. | `number` | `null` | no |
| policy\_prefix | Key prefix granted by the `prefix_policy_json` output, without leading or trailing slash. Empty grants the whole bucket. | `string` | `""` | no |
| policy\_read\_only | Make `prefix_policy_json` read-only (no put or delete). | `bool` | `false` | no |
| prefix\_expiration\_days | Prefix -> days. Current objects under each prefix expire after that many days (for example { "tmp/" = 7 }). | `map(number)` | `{}` | no |
| tags | Tags for the bucket. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| bucket\_arn | Bucket ARN. |
| bucket\_id | Bucket name. |
| bucket\_regional\_domain\_name | Regional domain name of the bucket. |
| prefix\_policy\_json | IAM policy document granting `policy_prefix` (and the KMS key, if one was given). Attach it to an app role. |
<!-- END_TF_DOCS -->
