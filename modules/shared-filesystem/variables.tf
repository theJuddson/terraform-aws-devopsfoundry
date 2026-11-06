variable "name" {
  description = "Name for the file system, its security group and tags."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the security group."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets that get a mount target, normally one private subnet per availability zone."
  type        = list(string)
}

variable "source_security_group_ids" {
  description = "Security groups allowed to reach NFS (TCP 2049). Nothing else is."
  type        = list(string)
}

variable "client_role_arns" {
  description = "IAM principals the file system policy lets mount and write. Defaults to any principal in this account."
  type        = list(string)
  default     = null
}

variable "allow_root_access" {
  description = "Let clients act as root on the file system. Off means root is squashed."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for encryption at rest. Null uses the AWS-managed aws/elasticfilesystem key."
  type        = string
  default     = null
}

variable "throughput_mode" {
  description = "`elastic`, `bursting` or `provisioned`."
  type        = string
  default     = "elastic"
}

variable "transition_to_ia" {
  description = "Move files to Infrequent Access after this long without access (for example `AFTER_30_DAYS`). Null keeps everything in Standard."
  type        = string
  default     = "AFTER_30_DAYS"
}

variable "runtime_tag_key" {
  description = "Tag key the file system carries and every run-time access point must carry."
  type        = string
  default     = "managed-by"
}

variable "runtime_tag_value" {
  description = "Value for `runtime_tag_key`. Null uses `name`."
  type        = string
  default     = null
}

variable "runtime_allow_create_file_system" {
  description = "Also let the app role create, mount, configure and delete encrypted file systems that carry the tag."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
