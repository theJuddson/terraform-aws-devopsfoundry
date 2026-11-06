variable "name" {
  description = "Name for the cluster, and prefix for its roles, log group, security group and task definition families."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the tasks' security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets tasks run in. Only passed through to the `run_task_network_configuration` output."
  type        = list(string)
  default     = []
}

variable "assign_public_ip" {
  description = "Value for `assignPublicIp` in the `run_task_network_configuration` output. True for public subnets without a NAT gateway."
  type        = bool
  default     = false
}

variable "task_definitions" {
  description = <<-EOT
    Task definitions to register, by short name. Each becomes the family `<name>-<key>`. Unset fields take the
    module-wide `cpu`, `memory`, `environment` and `secrets`; per-definition maps are merged over the module-wide ones.
  EOT
  type = map(object({
    image       = string
    command     = optional(list(string))
    cpu         = optional(number)
    memory      = optional(number)
    environment = optional(map(string), {})
    secrets     = optional(map(string), {})
  }))
}

variable "container_name" {
  description = "Name of the single container in each task definition (the name RunTask overrides refer to)."
  type        = string
  default     = "task"
}

variable "cpu" {
  description = "Default task CPU units (256, 512, 1024, 2048, 4096, 8192, 16384)."
  type        = number
  default     = 1024
}

variable "memory" {
  description = "Default task memory in MiB; must be valid for the CPU size."
  type        = number
  default     = 2048
}

variable "cpu_architecture" {
  description = "`ARM64` or `X86_64`. Images must be built for it."
  type        = string
  default     = "ARM64"

  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "ephemeral_storage_gib" {
  description = "Task ephemeral storage in GiB (21-200)."
  type        = number
  default     = 50

  validation {
    condition     = var.ephemeral_storage_gib >= 21 && var.ephemeral_storage_gib <= 200
    error_message = "ephemeral_storage_gib must be between 21 and 200."
  }
}

variable "readonly_root_filesystem" {
  description = "Mount the container's root file system read-only."
  type        = bool
  default     = false
}

variable "environment" {
  description = "Plaintext environment variables for every task definition."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables for every task definition: NAME -> Secrets Manager ARN (a `:json-key::` suffix is allowed)."
  type        = map(string)
  default     = {}
}

variable "secrets_kms_key_arns" {
  description = "Customer managed keys that encrypt the secrets, so the execution role may decrypt them."
  type        = list(string)
  default     = []
}

variable "efs_volumes" {
  description = <<-EOT
    EFS volumes mounted into every task, with TLS and IAM authorization. Give an `access_point_id`, or a
    `root_directory` to mount a folder of the file system directly.
  EOT
  type = list(object({
    name            = string
    file_system_id  = string
    container_path  = string
    access_point_id = optional(string)
    root_directory  = optional(string, "/")
    read_only       = optional(bool, false)
  }))
  default = []
}

variable "task_role_policy_jsons" {
  description = "Inline policies for the task role, by policy name. This is what the code inside the task may do."
  type        = map(string)
  default     = {}
}

variable "default_capacity_provider_strategy" {
  description = "Default strategy for RunTask calls that pass none: capacity provider -> { weight, base }."
  type = map(object({
    weight = number
    base   = optional(number, 0)
  }))
  default = {
    FARGATE = { weight = 1 }
  }
}

variable "egress_cidr_blocks" {
  description = "IPv4 ranges tasks may reach, on any protocol."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "log_retention_days" {
  description = "Days to keep task logs."
  type        = number
  default     = 30
}

variable "log_kms_key_arn" {
  description = "Customer managed key for the log group. The key policy must allow `logs.<region>.amazonaws.com`."
  type        = string
  default     = null
}

variable "container_insights" {
  description = "Turn on CloudWatch Container Insights for the cluster (billed per metric)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
