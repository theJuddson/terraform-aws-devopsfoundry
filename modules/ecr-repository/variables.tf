variable "name" {
  description = "Repository name."
  type        = string
}

variable "image_tag_mutability" {
  description = "`IMMUTABLE` or `MUTABLE`. Mutable lets a tag such as `latest` move to a new image."
  type        = string
  default     = "IMMUTABLE"
}

variable "force_delete" {
  description = "Let `terraform destroy` delete the repository while it still holds images."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Customer managed KMS key for image encryption. Null uses AES-256. Changing it replaces the repository."
  type        = string
  default     = null
}

variable "max_image_count" {
  description = "Keep this many newest images; older ones expire."
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Also expire untagged images this many days after push. Null adds no such rule."
  type        = number
  default     = null
}

variable "lifecycle_policy_json" {
  description = "Full lifecycle policy JSON, replacing the rules above."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for the repository (a Name tag is added)."
  type        = map(string)
  default     = {}
}
