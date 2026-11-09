# route53-zone-security

DNSSEC signing and DNS query logging for an existing Route53 public hosted zone. Both are off by default. Route53
requires the signing key and the query log group to be in us-east-1, so give the module a us-east-1 provider.
`full-stack` does this for its own zone with `enable_dnssec` and `enable_dns_query_logging`.

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "zone_security" {
  source               = "theJuddson/devopsfoundry/aws//modules/route53-zone-security"
  version              = "~> 1.4"
  providers            = { aws = aws.us_east_1 }
  zone_id              = aws_route53_zone.main.zone_id
  zone_name            = "example.com"
  enable_dnssec        = true
  enable_query_logging = true
}
```

**DNSSEC is not finished at apply.** Resolvers only validate the zone once the registrar publishes the `ds_record`
output (or `ds_record_fields`, for registrars such as Namecheap that ask for its parts). Turning DNSSEC off needs the
same care in reverse, or the domain stops resolving for validating resolvers. Follow
[docs/dnssec.md](https://github.com/theJuddson/terraform-aws-devopsfoundry/blob/main/docs/dnssec.md) for both.

**Query logging** writes each query Route53 answers to `/aws/route53/<zone>`, billed per GB ingested and stored.
Each zone uses one of the 10 CloudWatch Logs resource policies an account may have per region.

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
| [aws_cloudwatch_log_group.query_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.query_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_kms_alias.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_route53_hosted_zone_dnssec.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_hosted_zone_dnssec) | resource |
| [aws_route53_key_signing_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_key_signing_key) | resource |
| [aws_route53_query_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_query_log) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.dnssec](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.query_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| zone\_id | ID of the Route53 public hosted zone to sign or log | `string` | n/a | yes |
| zone\_name | The zone's domain name (e.g. example.com), used to name the key, alias and log group | `string` | n/a | yes |
| enable\_dnssec | Sign the zone with DNSSEC. After apply, publish the ds\_record output at the registrar; see docs/dnssec.md, including how to turn it off safely. | `bool` | `false` | no |
| enable\_query\_logging | Log the DNS queries Route53 answers for the zone to a CloudWatch log group (billed per GB). | `bool` | `false` | no |
| kms\_key\_arn | Customer managed KMS key (in us-east-1) for the query log group. null (default) = CloudWatch's default encryption. The key policy must allow logs.us-east-1.amazonaws.com. | `string` | `null` | no |
| query\_log\_retention\_days | Days to keep query logs. Must be a retention period CloudWatch Logs accepts. | `number` | `30` | no |
| tags | Tags for the KMS key and log group | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dnssec\_kms\_key\_arn | ARN of the KMS key holding the key-signing key (null when DNSSEC is off) |
| ds\_record | The DS record to publish at the registrar, as one line (null when DNSSEC is off) |
| ds\_record\_fields | The DS record's parts, for registrars that ask for them separately (Namecheap: key tag, algorithm, digest type, digest). null when DNSSEC is off. |
| query\_log\_group\_name | CloudWatch log group receiving the zone's DNS query logs (null when query logging is off) |
<!-- END_TF_DOCS -->
