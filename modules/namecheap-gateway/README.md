# namecheap-gateway

A Lambda that makes DevOpsFoundry's Namecheap nameserver calls from a fixed address. It runs in private subnets whose
route out is a NAT gateway with an Elastic IP, so one Namecheap allowlist entry (`client_ip`) works from any network.
The API key is an SSM SecureString created with `bin/namecheap put-key`, outside Terraform, and read at run time. The
function can only check access, read a domain's nameservers, set them, or reset the domain to Namecheap's default DNS
(`lambda/handler.py`). Call it with `bin/namecheap`, or delegate a domain with `namecheap-ns-gateway`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.7.0 |
| archive | >= 2.4 |
| aws | >= 5.60 |

## Providers

| Name | Version |
| ---- | ------- |
| archive | >= 2.4 |
| aws | >= 5.60 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_log_group.fn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.fn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.fn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_security_group.fn](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [archive_file.code](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.first](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| api\_user | Namecheap API user (NAMECHEAP\_API\_USER). Not a secret. | `string` | n/a | yes |
| client\_ip | The NAT gateway's Elastic IP. Namecheap requires it as `ClientIp` on every call, and it is the address to allowlist under Profile, Tools, Namecheap API Access. | `string` | n/a | yes |
| subnet\_ids | Private subnets whose default route is a NAT gateway with an Elastic IP. The function's calls leave from that IP; give it `client_ip`. All must be in one VPC. | `list(string)` | n/a | yes |
| allowed\_domains | Apex domains the gateway may read or change. Empty allows every domain in the Namecheap account. | `list(string)` | `[]` | no |
| api\_key\_kms\_key\_arn | Customer managed KMS key the parameter is encrypted with. Null for the AWS-managed `aws/ssm` key, which needs no extra permission. | `string` | `null` | no |
| api\_key\_parameter | Name of the SSM SecureString parameter that holds the API key, such as `/devopsfoundry/namecheap/api-key`. Create it with `bin/namecheap put-key`, outside Terraform, so the key never reaches state. | `string` | `"/devopsfoundry/namecheap/api-key"` | no |
| log\_kms\_key\_arn | Customer managed KMS key for the log group. Null uses CloudWatch default encryption. | `string` | `null` | no |
| log\_retention\_days | Days to keep the function's logs (action names and domains, never the key). | `number` | `365` | no |
| name | Name for the function, its role, security group and log group. | `string` | `"devopsfoundry-namecheap"` | no |
| reserved\_concurrency | Reserved concurrent executions, such as 2, to cap how many calls can run at once. Null reserves none. | `number` | `null` | no |
| sandbox | Call Namecheap's sandbox API instead of production. | `bool` | `false` | no |
| tags | Tags for every resource. | `map(string)` | `{}` | no |
| user\_name | Namecheap user the calls act for (NAMECHEAP\_USER\_NAME). Null uses `api_user`, which is the usual case. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| client\_ip | The address to allowlist at Namecheap: Profile, Tools, Namecheap API Access, Whitelisted IPs. |
| function\_arn | ARN of the gateway function, for an IAM policy that lets someone invoke it. |
| function\_name | The gateway function. Set `NAMECHEAP_GATEWAY` to it in `.env` for `bin/namecheap`, and pass it to `namecheap-ns` as `gateway_function_name`. |
| security\_group\_id | The function's security group (HTTPS out only). |
<!-- END_TF_DOCS -->