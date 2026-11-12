variable "accounts" {
  description = "Member accounts, keyed by account name. Each needs an email no other AWS account uses (a plus-address works). organizational_unit names one in organizational_units; null puts it at the root."
  type = map(object({
    email                      = string
    organizational_unit        = optional(string)
    iam_user_access_to_billing = optional(bool, true)
    tags                       = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.accounts) : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", a.email))])
    error_message = "Every account needs a valid email address."
  }
  validation {
    condition     = length(distinct([for a in values(var.accounts) : lower(a.email)])) == length(var.accounts)
    error_message = "Each account needs its own email address."
  }
  validation {
    condition     = alltrue([for a in values(var.accounts) : a.organizational_unit == null || contains(var.organizational_units, coalesce(a.organizational_unit, "-"))])
    error_message = "An account names an organizational unit that is not in organizational_units."
  }
  validation {
    condition     = alltrue([for n in keys(var.accounts) : length(n) >= 1 && length(n) <= 50])
    error_message = "Account names must be 1 to 50 characters."
  }
}

variable "organizational_units" {
  description = "Organizational units directly under the root, by name. Empty = accounts sit at the root."
  type        = set(string)
  default     = []
}

variable "service_access_principals" {
  description = "AWS services trusted across the organization. sso.amazonaws.com is what IAM Identity Center needs; account.amazonaws.com lets the management account manage members' contact details."
  type        = list(string)
  default     = ["sso.amazonaws.com", "account.amazonaws.com"]
}

variable "enabled_policy_types" {
  description = "Organization policy types to turn on, e.g. SERVICE_CONTROL_POLICY. Empty by default: SCPs never apply to the management account, so they only matter once workloads live in member accounts."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.enabled_policy_types : contains(["SERVICE_CONTROL_POLICY", "TAG_POLICY", "BACKUP_POLICY", "AISERVICES_OPT_OUT_POLICY", "RESOURCE_CONTROL_POLICY", "DECLARATIVE_POLICY_EC2", "CHATBOT_POLICY"], p)])
    error_message = "enabled_policy_types holds an unknown policy type."
  }
}

variable "member_admin_role_name" {
  description = "Role AWS creates in each new member account, trusting the management account with full admin. Used only until Identity Center access works, and for break-glass."
  type        = string
  default     = "OrganizationAccountAccessRole"
}
