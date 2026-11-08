# ec2-host

One EC2 instance for work that needs a long-lived machine: a container host, a build box, a stateful server. There
is no SSH key and the security group has no inbound rules; you reach the instance through SSM Session Manager
(`aws ssm start-session --target <id>`, also the `ssm_session_command` output). The role carries
`AmazonSSMManagedInstanceCore`; add more with `managed_policy_arns` or `inline_policy_jsons`.

```hcl
module "host" {
  source        = "theJuddson/devopsfoundry/aws//modules/ec2-host"
  version       = "~> 1.2"
  name          = "my-worker"
  subnet_id     = module.networking.private_subnet_ids[0]
  instance_type = "t4g.large"
}
```

## The data volume outlives the instance

The data lives on its own encrypted gp3 volume (`aws_ebs_volume.data`), attached as `data_device_name`. Replacing the
instance (a new AMI with `terraform apply -replace=module.host.aws_instance.this`, changed user data, a new instance
type that needs it) detaches the volume, stops the old instance first so the file system is clean, and attaches it
to the new one. Only destroying the module deletes the volume, and then with a final snapshot unless
`data_volume_final_snapshot = false`.

Format the volume once and mount it by label so the device name does not matter (Nitro instances show it as an
NVMe device); `examples/ec2-host` shows user data that does this.

## Snapshots

A Data Lifecycle Manager policy snapshots the data volume every `snapshot_interval_hours` (default 24, starting at
`snapshot_time_utc`) and keeps the newest `snapshot_retain_count` (default 14). It finds the volume by the tag
`dlm-snapshot = <name>`, so do not copy that tag onto other volumes.

## Other defaults

IMDSv2 only, with a hop limit of 1 so containers on bridge networks cannot reach instance credentials. The root
volume is encrypted. The AMI defaults to the latest Amazon Linux 2023 for arm64, read from SSM at plan time; a newer
AMI does not replace the instance until you ask for it.

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
| [aws_dlm_lifecycle_policy.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dlm_lifecycle_policy) | resource |
| [aws_ebs_volume.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | resource |
| [aws_iam_instance_profile.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.dlm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.dlm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_volume_attachment.data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/volume_attachment) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.dlm_assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_ssm_parameter.ami](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |
| [aws_subnet.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name for the instance and prefix for its volume, roles and security group. | `string` | n/a | yes |
| subnet\_id | Subnet for the instance. The data volume is made in the same availability zone. | `string` | n/a | yes |
| ami\_id | AMI ID. Null uses the latest image named by `ami_ssm_parameter`. | `string` | `null` | no |
| ami\_ssm\_parameter | Public SSM parameter holding the default AMI ID. | `string` | `"/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"` | no |
| associate\_public\_ip\_address | Give the instance a public IPv4 address (for outbound traffic without a NAT gateway). Inbound stays closed. | `bool` | `false` | no |
| data\_device\_name | Device name for the data volume. On Nitro instances it appears as an NVMe device; mount it by filesystem label or UUID. | `string` | `"/dev/sdf"` | no |
| data\_volume\_final\_snapshot | Take a snapshot when Terraform deletes the data volume. | `bool` | `true` | no |
| data\_volume\_iops | gp3 IOPS for the data volume (3000 is included in the price). | `number` | `3000` | no |
| data\_volume\_size\_gib | Data volume size in GiB. | `number` | `50` | no |
| data\_volume\_throughput | gp3 throughput for the data volume in MiB/s (125 is included in the price). | `number` | `125` | no |
| detailed\_monitoring | One-minute CloudWatch metrics (billed). | `bool` | `false` | no |
| egress\_cidr\_blocks | IPv4 ranges the instance may reach, on any protocol. SSM needs HTTPS to its endpoints. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| extra\_security\_group\_ids | More security groups for the instance, for example one that a database admits. | `list(string)` | `[]` | no |
| inline\_policy\_jsons | Inline policies for the instance role, by policy name. | `map(string)` | `{}` | no |
| instance\_type | Instance type. Graviton (for example `t4g.large`) needs an arm64 AMI. | `string` | `"t4g.small"` | no |
| kms\_key\_arn | Customer managed key for the root and data volumes. Null uses the account's default EBS key. | `string` | `null` | no |
| managed\_policy\_arns | Managed policies to attach to the instance role, besides AmazonSSMManagedInstanceCore. | `list(string)` | `[]` | no |
| metadata\_hop\_limit | IMDSv2 response hop limit. 1 keeps it from containers; 2 lets containers reach it. | `number` | `1` | no |
| root\_volume\_size\_gib | Root volume size in GiB. | `number` | `20` | no |
| snapshot\_interval\_hours | Hours between data volume snapshots (1, 2, 3, 4, 6, 8, 12 or 24). | `number` | `24` | no |
| snapshot\_retain\_count | Snapshots to keep. | `number` | `14` | no |
| snapshot\_time\_utc | Time of day (HH:MM, UTC) the snapshot schedule starts. | `string` | `"03:00"` | no |
| tags | Tags for every resource. | `map(string)` | `{}` | no |
| user\_data | Cloud-init user data. Never put secrets here; read them from SSM or Secrets Manager at boot. | `string` | `null` | no |
| user\_data\_replace\_on\_change | Replace the instance when user data changes. The data volume is kept either way. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| data\_volume\_id | ID of the data volume that outlives the instance. |
| instance\_id | Instance ID. |
| private\_ip | Private IPv4 address. |
| public\_ip | Public IPv4 address, if any. |
| role\_arn | Instance role ARN. |
| role\_name | Instance role name, for attaching more policies. |
| security\_group\_id | The instance's security group (no inbound rules). |
| ssm\_session\_command | Command that opens a shell on the instance. |
<!-- END_TF_DOCS -->
