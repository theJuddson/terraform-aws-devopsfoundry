variable "name" {
  description = "Resource-name prefix (app slug)"
  type        = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "redis_security_group_id" {
  type = string
}

variable "cache_port" {
  type    = number
  default = 6379
}

variable "engine_version" {
  type    = string
  default = "7.1"
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "parameter_group_name" {
  type    = string
  default = "default.redis7"
}

variable "num_cache_clusters" {
  description = "Nodes in the replication group. 1 is a single node; 2 or more adds replicas in other AZs with automatic failover (each node is billed)."
  type        = number
  default     = 1

  validation {
    condition     = var.num_cache_clusters >= 1 && var.num_cache_clusters <= 6 && floor(var.num_cache_clusters) == var.num_cache_clusters
    error_message = "num_cache_clusters must be a whole number from 1 to 6."
  }
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for encryption at rest. null (default) = the AWS-managed key. Changing it on an existing cache REPLACES the replication group (data is lost)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}
