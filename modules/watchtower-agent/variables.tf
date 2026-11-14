variable "collector_url" {
  description = "The Watchtower collector, such as `https://watch.example.com` (the watchtower module's `url` output)."
  type        = string

  validation {
    condition     = startswith(var.collector_url, "https://")
    error_message = "collector_url must be https://."
  }
}

variable "release_url" {
  description = "The agent tarball (`watchtower-agent_<version>_linux_<arch>.tar.gz`), as `https://...` or `s3://bucket/key`, for the hosts' arch. An `s3://` URL adds read access to that one object to `policy_json`."
  type        = string

  validation {
    condition     = can(regex("^(https://|s3://[^/]+/.+)", var.release_url))
    error_message = "release_url must be an https:// URL or s3://bucket/key."
  }
}

variable "release_sha256" {
  description = "SHA-256 of the tarball at `release_url`, from the release's SHA256SUMS."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.release_sha256))
    error_message = "release_sha256 must be 64 lowercase hex characters."
  }
}

variable "group_key_parameter" {
  description = "Name of the SSM SecureString holding a group enrollment key (`watchtower admin group-key <group>` on the collector). Each host trades it once for a token of its own."
  type        = string
}

variable "source_name" {
  description = "The host's name at the collector. Empty uses the hostname, which suits fleets that come and go."
  type        = string
  default     = ""
}
