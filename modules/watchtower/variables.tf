variable "name" {
  description = "Name for the host and its resources, such as `myapp-watchtower`."
  type        = string
}

variable "subnet_id" {
  description = "A public subnet: people, agents and the ACME CA reach the collector on 443."
  type        = string
}

variable "hostname" {
  description = "The collector's public name, such as `watch.example.com`. It gets its certificate for this name."
  type        = string
}

variable "zone_id" {
  description = "Route53 zone to put the hostname's A record in. Null leaves DNS to you: point the name at the `public_ip` output."
  type        = string
  default     = null
}

variable "release_url" {
  description = "The full Watchtower release tarball (`watchtower_<version>_linux_<arch>.tar.gz`), as `https://...` or `s3://bucket/key`. Its arch must match `instance_type` (arm64 for Graviton). An `s3://` URL gives the host read access to that one object."
  type        = string

  validation {
    condition     = can(regex("^(https://|s3://[^/]+/.+)", var.release_url))
    error_message = "release_url must be an https:// URL or s3://bucket/key."
  }
}

variable "release_sha256" {
  description = "SHA-256 of the tarball at `release_url`, from the release's SHA256SUMS. The host refuses any other file."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.release_sha256))
    error_message = "release_sha256 must be 64 lowercase hex characters."
  }
}

variable "rules_yaml" {
  description = "Alarm rules and probes, as Watchtower's YAML. Empty for none. They reach the host through an SSM parameter, and a change restarts the collector within a minute; it doesn't replace the instance. Gzipped, they must fit 4 KB."
  type        = string
  default     = ""

  validation {
    condition     = var.rules_yaml == "" || can(yamldecode(var.rules_yaml))
    error_message = "rules_yaml must be YAML; the collector would not start with these rules."
  }
  validation {
    condition     = length(base64gzip(var.rules_yaml)) <= 4096
    error_message = "rules_yaml, gzipped and base64-encoded, must fit a Standard SSM parameter's 4096 characters."
  }
}

variable "rules_in_user_data" {
  description = "Puts the rules in user data as before v1.25.0, so every rules change replaces the instance, and leaves the users' ids to chance. Only for an upgrade that must plan no change; the one replacement the default makes moves to the fixed ids."
  type        = bool
  default     = false
}

variable "mail_from" {
  description = "From address for sign-in links, invites and alarm email, sent through SES with the instance role. Null sends no email: invites are then printed links only."
  type        = string
  default     = null
}

variable "ses_identity_arn" {
  description = "ARN of the verified SES identity (domain or address) `mail_from` belongs to; the role may send as that identity only. Required with `mail_from`."
  type        = string
  default     = null
}

variable "ses_region" {
  description = "Region of the SES identity. Null uses the provider's region."
  type        = string
  default     = null
}

variable "acme_email" {
  description = "Contact address given to Let's Encrypt (optional)."
  type        = string
  default     = ""
}

variable "acme_directory" {
  description = "ACME directory URL. Empty for Let's Encrypt production; use `https://acme-staging-v02.api.letsencrypt.org/directory` for a test deployment."
  type        = string
  default     = ""
}

variable "retention_hours" {
  description = "How long raw 1 s samples are kept. The minute (90 days) and hour (2 years) tiers are fixed."
  type        = number
  default     = 72
}

variable "extra_flags" {
  description = "More collector flags, each one word such as \"--orgs\" or \"--org-max-sources=100\". They go on the collector's command line as given."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for f in var.extra_flags : can(regex("^--[a-z][a-z0-9-]*(=[A-Za-z0-9._:/@,+-]+)?$", f))])
    error_message = "Each extra flag is --name or --name=value, with letters, digits and ._:/@,+- in the value; nothing a shell would read."
  }
}

variable "ingress_cidr_blocks" {
  description = "IPv4 ranges allowed to reach 443. Agents on Fargate tasks and the ACME CA come from anywhere, so narrow this only if every source is known."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "Instance type. The default is Graviton, so `release_url` must be the arm64 tarball."
  type        = string
  default     = "t4g.micro"
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter holding the AMI. Amazon Linux 2023 is what the user data is written for."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

variable "data_volume_size_gib" {
  description = "Data volume for the TSDB, its rollups and the auth database. It outlives the instance."
  type        = number
  default     = 40
}

variable "snapshot_retain_count" {
  description = "Daily data volume snapshots to keep."
  type        = number
  default     = 14
}

variable "kms_key_arn" {
  description = "Customer managed key for the volumes. Null uses the account's default EBS key."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags for every resource."
  type        = map(string)
  default     = {}
}
