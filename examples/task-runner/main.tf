# A runner for one-off jobs: ARM64 tasks with 50 GiB of scratch space and a
# shared EFS folder, preferring Fargate Spot. A controller role gets the
# policy that lets it start and stop them.
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

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "controller_role_name" {
  type = string
}

module "runner" {
  source     = "../../modules/task-runner"
  name       = "example-jobs"
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  task_definitions = {
    job = {
      image   = "public.ecr.aws/docker/library/alpine:3"
      command = ["sh", "-c", "echo hello"]
    }
    big-job = {
      image  = "public.ecr.aws/docker/library/alpine:3"
      cpu    = 4096
      memory = 8192
    }
  }

  efs_volumes = [{
    name           = "shared"
    file_system_id = module.files.file_system_id
    container_path = "/mnt/shared"
  }]

  default_capacity_provider_strategy = {
    FARGATE_SPOT = { weight = 3 }
    FARGATE      = { weight = 1, base = 0 }
  }
}

module "files" {
  source                    = "../../modules/shared-filesystem"
  name                      = "example-jobs-files"
  vpc_id                    = var.vpc_id
  subnet_ids                = var.private_subnet_ids
  source_security_group_ids = [module.runner.security_group_id]
}

resource "aws_iam_role_policy" "controller" {
  name   = "run-jobs"
  role   = var.controller_role_name
  policy = module.runner.controller_policy_json
}

output "network_configuration" {
  value = module.runner.run_task_network_configuration
}
