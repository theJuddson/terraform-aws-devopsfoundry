variable "name" {
  description = "Name for the instance and prefix for its volume, roles and security group."
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the instance. The data volume is made in the same availability zone."
  type        = string
}

variable "instance_type" {
  description = "Instance type. Graviton (for example `t4g.large`) needs an arm64 AMI."
  type        = string
  default     = "t4g.small"
}

variable "ami_id" {
  description = "AMI ID. Null uses the latest image named by `ami_ssm_parameter`."
  type        = string
  default     = null
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter holding the default AMI ID."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

variable "associate_public_ip_address" {
  description = "Give the instance a public IPv4 address (for outbound traffic without a NAT gateway). Inbound stays closed."
  type        = bool
  default     = false
}

variable "extra_security_group_ids" {
  description = "More security groups for the instance, for example one that a database admits."
  type        = list(string)
  default     = []
}

variable "egress_cidr_blocks" {
  description = "IPv4 ranges the instance may reach, on any protocol. SSM needs HTTPS to its endpoints."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "metadata_hop_limit" {
  description = "IMDSv2 response hop limit. 1 keeps it from containers; 2 lets containers reach it."
  type        = number
  default     = 1
}

variable "detailed_monitoring" {
  description = "One-minute CloudWatch metrics (billed)."
  type        = bool
  default     = false
}

variable "user_data" {
  description = "Cloud-init user data. Never put secrets here; read them from SSM or Secrets Manager at boot."
  type        = string
  default     = null
}

variable "user_data_replace_on_change" {
  description = "Replace the instance when user data changes. The data volume is kept either way."
  type        = bool
  default     = true
}

variable "root_volume_size_gib" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20
}

variable "data_volume_size_gib" {
  description = "Data volume size in GiB."
  type        = number
  default     = 50
}

variable "data_volume_iops" {
  description = "gp3 IOPS for the data volume (3000 is included in the price)."
  type        = number
  default     = 3000
}

variable "data_volume_throughput" {
  description = "gp3 throughput for the data volume in MiB/s (125 is included in the price)."
  type        = number
  default     = 125
}

variable "data_volume_final_snapshot" {
  description = "Take a snapshot when Terraform deletes the data volume."
  type        = bool
  default     = true
}

variable "data_device_name" {
  description = "Device name for the data volume. On Nitro instances it appears as an NVMe device; mount it by filesystem label or UUID."
  type        = string
  default     = "/dev/sdf"
}

variable "kms_key_arn" {
  description = "Customer managed key for the root and data volumes. Null uses the account's default EBS key."
  type        = string
  default     = null
}

variable "managed_policy_arns" {
  description = "Managed policies to attach to the instance role, besides AmazonSSMManagedInstanceCore."
  type        = list(string)
  default     = []
}

variable "inline_policy_jsons" {
  description = "Inline policies for the instance role, by policy name."
  type        = map(string)
  default     = {}
}

variable "snapshot_interval_hours" {
  description = "Hours between data volume snapshots (1, 2, 3, 4, 6, 8, 12 or 24)."
  type        = number
  default     = 24
}

variable "snapshot_time_utc" {
  description = "Time of day (HH:MM, UTC) the snapshot schedule starts."
  type        = string
  default     = "03:00"
}

variable "snapshot_retain_count" {
  description = "Snapshots to keep."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
