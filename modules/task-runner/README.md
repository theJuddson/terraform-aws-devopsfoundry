# task-runner

Runs one-off containers on ECS Fargate: jobs, sandboxes, per-request workers. There is no service and no load
balancer. Something you write (the "controller") starts each task with `RunTask` and stops it with `StopTask`.

The module makes:

- an ECS cluster with the `FARGATE` and `FARGATE_SPOT` capacity providers, and a default strategy you choose;
- one task definition per entry in `task_definitions` (family `<name>-<key>`), with one container named
  `container_name`, ARM64 by default, 50 GiB of ephemeral storage by default, and any EFS volumes in `efs_volumes`
  mounted with TLS and IAM authorization;
- a task role (what the code in the task may do; add policies with `task_role_policy_jsons`) and an execution role
  (pull the image, read the listed secrets, write logs);
- a log group `/ecs/<name>`;
- a security group with no ingress rules, so nothing can connect to a task;
- `controller_policy_json`: `ecs:RunTask` on these task definitions in this cluster only, `ecs:StopTask`,
  `ecs:DescribeTasks` and `ecs:TagResource` on this cluster's tasks only, and `iam:PassRole` on exactly the task and
  execution roles, only to ECS tasks.

```hcl
module "runner" {
  source     = "git::https://github.com/theJuddson/terraform-aws-devopsfoundry//modules/task-runner?ref=v1.2.1"
  name       = "my-jobs"
  vpc_id     = module.networking.vpc_id
  subnet_ids = module.networking.private_subnet_ids
  task_definitions = {
    job = { image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-job:latest" }
  }
}
```

Starting a task from the controller, with the values the module outputs:

```sh
aws ecs run-task --cluster "$CLUSTER" --task-definition "$FAMILY" \
  --capacity-provider-strategy capacityProvider=FARGATE_SPOT,weight=1 \
  --network-configuration "$NETWORK_CONFIGURATION_JSON" \
  --overrides '{"containerOverrides":[{"name":"task","command":["run","42"]}]}' \
  --tags key=job,value=42
```

Fargate Spot tasks can be stopped with two minutes' warning; use it for work that can be retried.

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
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecs_cluster.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster) | resource |
| [aws_ecs_cluster_capacity_providers.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_cluster_capacity_providers) | resource |
| [aws_ecs_task_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task_efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task_extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.assume](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.execution_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.task_efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Name for the cluster, and prefix for its roles, log group, security group and task definition families. | `string` | n/a | yes |
| task\_definitions | Task definitions to register, by short name. Each becomes the family `<name>-<key>`. Unset fields take the<br/>module-wide `cpu`, `memory`, `environment` and `secrets`; per-definition maps are merged over the module-wide ones. | <pre>map(object({<br/>    image       = string<br/>    command     = optional(list(string))<br/>    cpu         = optional(number)<br/>    memory      = optional(number)<br/>    environment = optional(map(string), {})<br/>    secrets     = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| vpc\_id | VPC for the tasks' security group. | `string` | n/a | yes |
| assign\_public\_ip | Value for `assignPublicIp` in the `run_task_network_configuration` output. True for public subnets without a NAT gateway. | `bool` | `false` | no |
| container\_insights | Turn on CloudWatch Container Insights for the cluster (billed per metric). | `bool` | `false` | no |
| container\_name | Name of the single container in each task definition (the name RunTask overrides refer to). | `string` | `"task"` | no |
| cpu | Default task CPU units (256, 512, 1024, 2048, 4096, 8192, 16384). | `number` | `1024` | no |
| cpu\_architecture | `ARM64` or `X86_64`. Images must be built for it. | `string` | `"ARM64"` | no |
| default\_capacity\_provider\_strategy | Default strategy for RunTask calls that pass none: capacity provider -> { weight, base }. | <pre>map(object({<br/>    weight = number<br/>    base   = optional(number, 0)<br/>  }))</pre> | <pre>{<br/>  "FARGATE": {<br/>    "weight": 1<br/>  }<br/>}</pre> | no |
| efs\_volumes | EFS volumes mounted into every task, with TLS and IAM authorization. Give an `access_point_id`, or a<br/>`root_directory` to mount a folder of the file system directly. | <pre>list(object({<br/>    name            = string<br/>    file_system_id  = string<br/>    container_path  = string<br/>    access_point_id = optional(string)<br/>    root_directory  = optional(string, "/")<br/>    read_only       = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| egress\_cidr\_blocks | IPv4 ranges tasks may reach, on any protocol. | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |
| environment | Plaintext environment variables for every task definition. | `map(string)` | `{}` | no |
| ephemeral\_storage\_gib | Task ephemeral storage in GiB (21-200). | `number` | `50` | no |
| log\_kms\_key\_arn | Customer managed key for the log group. The key policy must allow `logs.<region>.amazonaws.com`. | `string` | `null` | no |
| log\_retention\_days | Days to keep task logs. | `number` | `30` | no |
| memory | Default task memory in MiB; must be valid for the CPU size. | `number` | `2048` | no |
| readonly\_root\_filesystem | Mount the container's root file system read-only. | `bool` | `false` | no |
| secrets | Secret environment variables for every task definition: NAME -> Secrets Manager ARN (a `:json-key::` suffix is allowed). | `map(string)` | `{}` | no |
| secrets\_kms\_key\_arns | Customer managed keys that encrypt the secrets, so the execution role may decrypt them. | `list(string)` | `[]` | no |
| subnet\_ids | Subnets tasks run in. Only passed through to the `run_task_network_configuration` output. | `list(string)` | `[]` | no |
| tags | Tags for every resource. | `map(string)` | `{}` | no |
| task\_role\_policy\_jsons | Inline policies for the task role, by policy name. This is what the code inside the task may do. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| cluster\_arn | Cluster ARN. |
| cluster\_name | Cluster name. |
| container\_name | Container name to use in RunTask overrides. |
| controller\_policy\_json | IAM policy document for the controller: RunTask, StopTask, DescribeTasks and TagResource in this cluster, and PassRole on the task and execution roles. |
| execution\_role\_arn | Role ECS uses to pull the image, read secrets and write logs. |
| log\_group\_name | Log group the tasks write to. |
| run\_task\_network\_configuration | The `networkConfiguration` to pass to RunTask. |
| security\_group\_id | Egress-only security group for the tasks. |
| task\_definition\_arns | Short name -> ARN of the revision this apply registered. |
| task\_definition\_families | Short name -> task definition family. RunTask with the family runs its latest revision. |
| task\_role\_arn | Role the code inside the task runs as. |
| task\_role\_name | Name of the task role, for attaching more policies. |
<!-- END_TF_DOCS -->
