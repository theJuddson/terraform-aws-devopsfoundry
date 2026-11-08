variable "alias" {
  description = "Alias name without the `alias/` prefix."
  type        = string
}

variable "description" {
  description = "Key description."
  type        = string
  default     = "Customer managed key"
}

variable "deletion_window_in_days" {
  description = "Waiting period between scheduling deletion and the key being deleted (7-30)."
  type        = number
  default     = 30
  validation {
    condition     = floor(var.deletion_window_in_days) == var.deletion_window_in_days && var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be a whole number from 7 to 30."
  }
}

variable "rotation_period_in_days" {
  description = "Days between automatic rotations of the key material (90-2560). Rotation is always on."
  type        = number
  default     = 365
  validation {
    condition     = floor(var.rotation_period_in_days) == var.rotation_period_in_days && var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "rotation_period_in_days must be a whole number from 90 to 2560."
  }
}

variable "key_administrator_arns" {
  description = "IAM principals that may manage the key (not use it)."
  type        = list(string)
  default     = []
}

variable "key_user_arns" {
  description = "IAM principals that may encrypt and decrypt with the key."
  type        = list(string)
  default     = []
}

variable "service_principals" {
  description = "AWS service principals (for example `logs.amazonaws.com`) that may use the key on behalf of this account."
  type        = list(string)
  default     = []
}

variable "extra_key_policy_documents" {
  description = "Further key policy JSON documents merged into the key policy."
  type        = list(string)
  default     = []
}

variable "runtime_tag_key" {
  description = "Tag key every run-time key must carry."
  type        = string
  default     = "managed-by"
}

variable "runtime_tag_value" {
  description = "Tag value every run-time key must carry. Null leaves `runtime_policy_json` empty."
  type        = string
  default     = null
}

variable "runtime_alias_prefix" {
  description = "Run-time keys may only be given aliases under `alias/<prefix>/`."
  type        = string
  default     = "app"
}

variable "runtime_allow_key_deletion" {
  description = "Let the app role disable and schedule deletion of its own keys (for example when a tenant leaves)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the key."
  type        = map(string)
  default     = {}
}
