# kms-key

One customer managed KMS key with an alias, yearly rotation and a key policy that names its administrators, users
and AWS services. It also renders `runtime_policy_json`, an IAM policy for an app role that makes keys of its own at
run time, for example one key per customer when the customer signs up. Terraform does not manage those keys; the
app does, within the limits of that policy.

```hcl
module "key" {
  source            = "theJuddson/devopsfoundry/aws//modules/kms-key"
  version           = "~> 1.2"
  alias             = "my-app"
  key_user_arns     = [aws_iam_role.app.arn]
  runtime_tag_value = "my-app"   # turns on runtime_policy_json
}
```

## The run-time policy

Every key the role creates must carry `runtime_tag_key = runtime_tag_value` (default tag key `managed-by`). The role may:

- create a key only with that tag in the request, and never with the policy lockout safety check bypassed;
- encrypt, decrypt, generate data keys, describe, turn on rotation and tag keys that carry the tag;
- give those keys aliases under `alias/<runtime_alias_prefix>/`;
- with `runtime_allow_key_deletion = true`, disable and schedule deletion of its own keys.

It may never move the ownership tag off a key that carries a different value.

**What it does not prevent.** KMS authorizes the tags in a `CreateKey` call as `kms:TagResource` on any key in the
account, so the role must be allowed to add the tag without a resource-tag condition. A key elsewhere in the same
account and region that has *no* ownership tag, and whose key policy delegates to IAM, could therefore be tagged and
then used by the role. Keep such keys out of reach by running the app in its own account, by giving other keys key
policies that do not delegate to IAM, or by attaching a permissions boundary to the role. The role can also pass any
key policy it likes to `CreateKey`; that only affects keys it owns.

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
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.runtime](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| alias | Alias name without the `alias/` prefix. | `string` | n/a | yes |
| deletion\_window\_in\_days | Waiting period between scheduling deletion and the key being deleted (7-30). | `number` | `30` | no |
| description | Key description. | `string` | `"Customer managed key"` | no |
| extra\_key\_policy\_documents | Further key policy JSON documents merged into the key policy. | `list(string)` | `[]` | no |
| key\_administrator\_arns | IAM principals that may manage the key (not use it). | `list(string)` | `[]` | no |
| key\_user\_arns | IAM principals that may encrypt and decrypt with the key. | `list(string)` | `[]` | no |
| rotation\_period\_in\_days | Days between automatic rotations of the key material (90-2560). Rotation is always on. | `number` | `365` | no |
| runtime\_alias\_prefix | Run-time keys may only be given aliases under `alias/<prefix>/`. | `string` | `"app"` | no |
| runtime\_allow\_key\_deletion | Let the app role disable and schedule deletion of its own keys (for example when a tenant leaves). | `bool` | `false` | no |
| runtime\_tag\_key | Tag key every run-time key must carry. | `string` | `"managed-by"` | no |
| runtime\_tag\_value | Tag value every run-time key must carry. Null leaves `runtime_policy_json` empty. | `string` | `null` | no |
| service\_principals | AWS service principals (for example `logs.amazonaws.com`) that may use the key on behalf of this account. | `list(string)` | `[]` | no |
| tags | Tags for the key. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| alias\_arn | Alias ARN. |
| alias\_name | Alias name, `alias/<alias>`. |
| key\_arn | Key ARN. |
| key\_id | Key ID. |
| runtime\_policy\_json | IAM policy document for an app role that creates and uses its own tagged keys. Null when `runtime_tag_value` is null. |
<!-- END_TF_DOCS -->
