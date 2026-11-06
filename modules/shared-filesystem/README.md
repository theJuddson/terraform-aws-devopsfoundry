# shared-filesystem

An EFS file system for many clients: encrypted at rest (with your key if you pass `kms_key_arn`), AWS Backup on,
elastic throughput, one mount target per subnet, and a security group that admits NFS (TCP 2049) only from the
security groups in `source_security_group_ids`. A file system policy refuses connections that are not over TLS or
not through a mount target, and squashes root unless `allow_root_access` is true.

```hcl
module "files" {
  source                    = "git::https://github.com/theJuddson/DevOpsFoundry//modules/shared-filesystem?ref=v1.2.0"
  name                      = "my-app-files"
  vpc_id                    = module.networking.vpc_id
  subnet_ids                = module.networking.private_subnet_ids
  source_security_group_ids = [module.tasks.security_group_id]
}
```

## Folders made at run time

When each customer gets their own folder, the app makes an access point for it when the customer signs up, and
Terraform never sees it. `runtime_policy_json` is the IAM policy that allows this. The file system carries the tag
`runtime_tag_key = runtime_tag_value` (default `managed-by = <name>`), and the role may:

- create access points only on file systems with that tag, and only with the same tag on the new access point;
- delete and re-tag access points that carry the tag, and describe file systems, access points and mount targets;
- with `runtime_allow_create_file_system = true`, also create encrypted file systems with the tag, and add mount
  targets, policies and backup and lifecycle settings to them, or delete them.

The role may never move the ownership tag off a resource that carries a different value. As with the `kms-key`
module, an untagged access point elsewhere in the account could be tagged and then deleted by the role; keep apps
in their own account if that matters.

Mount from ECS with `transit_encryption = "ENABLED"` and `iam = "ENABLED"`; the `task-runner` module does both.

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
| [aws_efs_backup_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_backup_policy) | resource |
| [aws_efs_file_system.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_file_system_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system_policy) | resource |
| [aws_efs_mount_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.nfs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.file_system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name for the file system, its security group and tags. | `string` | n/a | yes |
| source\_security\_group\_ids | Security groups allowed to reach NFS (TCP 2049). Nothing else is. | `list(string)` | n/a | yes |
| subnet\_ids | Subnets that get a mount target, normally one private subnet per availability zone. | `list(string)` | n/a | yes |
| vpc\_id | VPC for the security group. | `string` | n/a | yes |
| allow\_root\_access | Let clients act as root on the file system. Off means root is squashed. | `bool` | `false` | no |
| client\_role\_arns | IAM principals the file system policy lets mount and write. Defaults to any principal in this account. | `list(string)` | `null` | no |
| kms\_key\_arn | Customer managed KMS key for encryption at rest. Null uses the AWS-managed aws/elasticfilesystem key. | `string` | `null` | no |
| runtime\_allow\_create\_file\_system | Also let the app role create, mount, configure and delete encrypted file systems that carry the tag. | `bool` | `false` | no |
| runtime\_tag\_key | Tag key the file system carries and every run-time access point must carry. | `string` | `"managed-by"` | no |
| runtime\_tag\_value | Value for `runtime_tag_key`. Null uses `name`. | `string` | `null` | no |
| tags | Tags for every resource. | `map(string)` | `{}` | no |
| throughput\_mode | `elastic`, `bursting` or `provisioned`. | `string` | `"elastic"` | no |
| transition\_to\_ia | Move files to Infrequent Access after this long without access (for example `AFTER_30_DAYS`). Null keeps everything in Standard. | `string` | `"AFTER_30_DAYS"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| dns\_name | Regional DNS name for mounting. |
| file\_system\_arn | File system ARN. |
| file\_system\_id | File system ID. |
| mount\_target\_ids | Subnet ID -> mount target ID. |
| runtime\_policy\_json | IAM policy document for an app role that creates access points (and optionally file systems) at run time. |
| runtime\_tag | The tag run-time access points must carry, as { key, value }. |
| security\_group\_id | Security group on the mount targets. |
<!-- END_TF_DOCS -->
