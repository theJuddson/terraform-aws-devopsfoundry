# A Graviton host that reports to a Watchtower collector, enrolling with a group
# key kept in SSM.
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

variable "subnet_id" {
  type = string
}

variable "agent_sha256" {
  type = string
}

module "watchtower_agent" {
  source              = "../../modules/watchtower-agent"
  collector_url       = "https://watch.example.com"
  release_url         = "s3://example-artifacts/watchtower/v0.1.0/watchtower-agent_v0.1.0_linux_arm64.tar.gz"
  release_sha256      = var.agent_sha256
  group_key_parameter = "/example/watchtower/group-key/hosts"
}

module "host" {
  source              = "../../modules/ec2-host"
  name                = "example-monitored"
  subnet_id           = var.subnet_id
  user_data           = module.watchtower_agent.user_data
  inline_policy_jsons = { watchtower-agent = module.watchtower_agent.policy_json }
}
