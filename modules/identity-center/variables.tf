variable "users" {
  description = "People who sign in, keyed by a short name used in groups and assignments. The email is their user name and where Identity Center sends the invitation."
  type = map(object({
    given_name   = string
    family_name  = string
    email        = string
    display_name = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for u in values(var.users) : can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", u.email))])
    error_message = "Every user needs a valid email address."
  }
}

variable "groups" {
  description = "Groups by name, each with the user keys in it."
  type = map(object({
    description = optional(string)
    members     = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue(flatten([for g in values(var.groups) : [for m in g.members : contains(keys(var.users), m)]]))
    error_message = "A group lists a member that is not in users."
  }
}

variable "permission_sets" {
  description = "Permission sets by name: AWS managed or customer policies to attach, an optional inline policy (JSON), and how long a sign-in lasts (ISO 8601, PT1H to PT12H)."
  type = map(object({
    description         = optional(string)
    session_duration    = optional(string, "PT8H")
    managed_policy_arns = optional(list(string), [])
    inline_policy       = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for p in values(var.permission_sets) : can(regex("^PT([1-9]|1[0-2])H$", p.session_duration))])
    error_message = "session_duration must be PT1H to PT12H."
  }
  validation {
    condition     = alltrue([for n in keys(var.permission_sets) : can(regex("^[A-Za-z0-9+=,.@_-]{1,32}$", n))])
    error_message = "Permission set names are 1 to 32 letters, digits or +=,.@_-."
  }
}

variable "assignments" {
  description = "Who gets which permission set in which account. Each names exactly one of user (a key of users) or group (a key of groups)."
  type = list(object({
    permission_set = string
    account_id     = string
    user           = optional(string)
    group          = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for a in var.assignments : (a.user == null) != (a.group == null)])
    error_message = "Each assignment names exactly one of user or group."
  }
  validation {
    condition     = alltrue([for a in var.assignments : can(regex("^[0-9]{12}$", a.account_id))])
    error_message = "account_id must be a 12-digit AWS account ID."
  }
  validation {
    condition     = alltrue([for a in var.assignments : contains(keys(var.permission_sets), a.permission_set)])
    error_message = "An assignment names a permission set that is not in permission_sets."
  }
  validation {
    condition     = alltrue([for a in var.assignments : a.user == null || contains(keys(var.users), coalesce(a.user, "-"))])
    error_message = "An assignment names a user that is not in users."
  }
  validation {
    condition     = alltrue([for a in var.assignments : a.group == null || contains(keys(var.groups), coalesce(a.group, "-"))])
    error_message = "An assignment names a group that is not in groups."
  }
}
