# ecr-repository

One ECR repository: scan on push, a lifecycle policy that keeps the newest `max_image_count` images (and, if you
set `untagged_expire_days`, drops untagged images sooner), AES-256 or your own KMS key, and a Name tag.

Tags are immutable by default. `force_delete` is off by default, so `terraform destroy` refuses a repository that
still holds images.

```hcl
module "ecr" {
  source               = "git::https://github.com/theJuddson/terraform-aws-devopsfoundry//modules/ecr-repository?ref=v1.2.1"
  name                 = "my-job"
  untagged_expire_days = 7
}
```

`container-service` builds its repository with this module, passing `MUTABLE` tags, `force_delete = true` and
`max_image_count = 10`, which is exactly what it made before. Stacks created with v1.1.0 or earlier see the
repository move to `module.ecr` in the plan and nothing else (`moved` blocks re-key the state;
`bin/check-compat` checks this offline).

For faster Fargate start-up of large images, build a SOCI index after each push: see
[docs/soci.md](../../docs/soci.md) and `bin/soci-index`.

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
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Repository name. | `string` | n/a | yes |
| force\_delete | Let `terraform destroy` delete the repository while it still holds images. | `bool` | `false` | no |
| image\_tag\_mutability | `IMMUTABLE` or `MUTABLE`. Mutable lets a tag such as `latest` move to a new image. | `string` | `"IMMUTABLE"` | no |
| kms\_key\_arn | Customer managed KMS key for image encryption. Null uses AES-256. Changing it replaces the repository. | `string` | `null` | no |
| lifecycle\_policy\_json | Full lifecycle policy JSON, replacing the rules above. | `string` | `null` | no |
| max\_image\_count | Keep this many newest images; older ones expire. | `number` | `10` | no |
| tags | Tags for the repository (a Name tag is added). | `map(string)` | `{}` | no |
| untagged\_expire\_days | Also expire untagged images this many days after push. Null adds no such rule. | `number` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| registry\_id | Registry (account) ID. |
| repository\_arn | Repository ARN. |
| repository\_name | Repository name. |
| repository\_url | Repository URL, `<account>.dkr.ecr.<region>.amazonaws.com/<name>`. |
<!-- END_TF_DOCS -->
