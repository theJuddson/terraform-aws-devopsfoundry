variable "name" {
  description = "Role name, e.g. agents-collaborator"
  type        = string
}

variable "path" {
  type    = string
  default = "/people/"
}

variable "project_tag_key" {
  description = "Tag that marks the project's resources"
  type        = string
  default     = "project"
}

variable "project_tag_values" {
  description = "Values of project_tag_key that belong to the project, e.g. [\"agents\"]"
  type        = list(string)

  validation {
    condition     = length(var.project_tag_values) > 0 && alltrue([for v in var.project_tag_values : length(trimspace(v)) > 0])
    error_message = "Name at least one non-empty project tag value."
  }
}

variable "log_group_prefixes" {
  description = "CloudWatch log group name prefixes the role may read, e.g. [\"/agents/\", \"/ecs/agents-\"]. Empty = no log access."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.log_group_prefixes : length(p) >= 2 && !strcontains(p, "*")])
    error_message = "Log group prefixes must be at least 2 characters, with no wildcard (one is added)."
  }
}

variable "allow_ssm" {
  description = "Shells (Session Manager) and commands (SendCommand) on the project's instances. Both run as root there."
  type        = bool
  default     = true
}

variable "ssm_documents" {
  description = "AWS-owned SSM documents SendCommand may run on the project's instances"
  type        = list(string)
  default     = ["AWS-RunShellScript"]
}

variable "allow_cost_explorer" {
  description = "Cost Explorer read. It can't be limited to a tag, so this shows every project's costs in the account."
  type        = bool
  default     = false
}

variable "extra_policy_json" {
  description = "A further inline policy for project-specific needs (a deploy bucket, SSM parameters under the project's path, ...)"
  type        = string
  default     = null
}

variable "trusted_principal_arns" {
  description = "IAM principals that may assume the role, such as an existing user or another account's root"
  type        = list(string)
  default     = []
}

variable "user_name" {
  description = "Make an IAM user (under /people/) that can only manage its own MFA and assume this role with MFA. null = no user."
  type        = string
  default     = null
}

variable "require_mfa" {
  description = "Only sessions signed in with MFA may assume the role"
  type        = bool
  default     = true
}

variable "max_session_hours" {
  type    = number
  default = 4

  validation {
    condition     = var.max_session_hours >= 1 && var.max_session_hours <= 12 && floor(var.max_session_hours) == var.max_session_hours
    error_message = "max_session_hours must be a whole number from 1 to 12."
  }
}
