# EFS for a fleet of tasks, reachable only from the tasks' security group. The
# app role may create one access point per customer at run time.
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

variable "task_security_group_id" {
  type = string
}

variable "app_role_name" {
  type = string
}

module "files" {
  source                    = "../../modules/shared-filesystem"
  name                      = "example-workspaces"
  vpc_id                    = var.vpc_id
  subnet_ids                = var.private_subnet_ids
  source_security_group_ids = [var.task_security_group_id]
}

resource "aws_iam_role_policy" "access_points" {
  name   = "runtime-access-points"
  role   = var.app_role_name
  policy = module.files.runtime_policy_json
}
