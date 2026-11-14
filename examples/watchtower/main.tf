# A Watchtower collector at watch.example.com in an existing public zone, with
# its release in the account's own bucket, alarm email through SES and Let's
# Encrypt staging for a test.
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "public_subnet_id" {
  type = string
}

variable "zone_id" {
  type = string
}

variable "release_sha256" {
  type = string
}

module "watchtower" {
  source         = "../../modules/watchtower"
  name           = "example-watchtower"
  subnet_id      = var.public_subnet_id
  hostname       = "watch.example.com"
  zone_id        = var.zone_id
  release_url    = "s3://example-artifacts/watchtower/v0.1.0/watchtower_v0.1.0_linux_arm64.tar.gz"
  release_sha256 = var.release_sha256
  acme_directory = "https://acme-staging-v02.api.letsencrypt.org/directory"
  rules_yaml     = <<-EOT
    rules: []
  EOT
}

output "url" {
  value = module.watchtower.url
}

output "first_admin" {
  value = module.watchtower.first_admin_command
}
