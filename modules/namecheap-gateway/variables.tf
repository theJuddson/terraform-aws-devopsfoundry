variable "name" {
  description = "Name for the function, its role, security group and log group."
  type        = string
  default     = "devopsfoundry-namecheap"
}

variable "subnet_ids" {
  description = "Private subnets whose default route is a NAT gateway with an Elastic IP. The function's calls leave from that IP; give it `client_ip`. All must be in one VPC."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "Give at least one subnet."
  }
}

variable "client_ip" {
  description = "The NAT gateway's Elastic IP. Namecheap requires it as `ClientIp` on every call, and it is the address to allowlist under Profile, Tools, Namecheap API Access."
  type        = string

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", var.client_ip))
    error_message = "client_ip must be an IPv4 address."
  }
}

variable "api_user" {
  description = "Namecheap API user (NAMECHEAP_API_USER). Not a secret."
  type        = string
}

variable "user_name" {
  description = "Namecheap user the calls act for (NAMECHEAP_USER_NAME). Null uses `api_user`, which is the usual case."
  type        = string
  default     = null
}

variable "api_key_parameter" {
  description = "Name of the SSM SecureString parameter that holds the API key, such as `/devopsfoundry/namecheap/api-key`. Create it with `bin/namecheap put-key`, outside Terraform, so the key never reaches state."
  type        = string
  default     = "/devopsfoundry/namecheap/api-key"

  validation {
    condition     = can(regex("^/?[A-Za-z0-9_.\\-/]+$", var.api_key_parameter))
    error_message = "api_key_parameter must be an SSM parameter name."
  }
}

variable "api_key_kms_key_arn" {
  description = "Customer managed KMS key the parameter is encrypted with. Null for the AWS-managed `aws/ssm` key, which needs no extra permission."
  type        = string
  default     = null
}

variable "allowed_domains" {
  description = "Apex domains the gateway may read or change. Empty allows every domain in the Namecheap account."
  type        = list(string)
  default     = []
}

variable "sandbox" {
  description = "Call Namecheap's sandbox API instead of production."
  type        = bool
  default     = false
}

variable "reserved_concurrency" {
  description = "Reserved concurrent executions, such as 2, to cap how many calls can run at once. Null reserves none."
  type        = number
  default     = null
}

variable "log_retention_days" {
  description = "Days to keep the function's logs (action names and domains, never the key)."
  type        = number
  default     = 365
}

variable "log_kms_key_arn" {
  description = "Customer managed KMS key for the log group. Null uses CloudWatch default encryption."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
